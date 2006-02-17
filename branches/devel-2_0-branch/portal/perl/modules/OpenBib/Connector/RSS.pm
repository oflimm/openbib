####################################################################
#
#  OpenBib::Connector::RSS.pm
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Connector::RSS;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Apache::URI ();
use Benchmark;
use Date::Manip;
use DBI;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use Template;
use XML::RSS;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Search::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    # Basisipfad entfernen
    my $basepath = $config{connector_rss_loc};
    $path=~s/$basepath//;

    # RSS-Feedparameter aus URI bestimmen
    my ($type,$subtype,$database);
    if ($path=~m/^\/(\w+?)\/(\w+?).rdf$/){
        ($type,$subtype,$database)=($1,"-1",$2);
    }
    elsif ($path=~m/^\/(\w+?)\/(\w+?)\/(\w+?).rdf$/){
        ($type,$subtype,$database)=($1,$2,$3);
    }

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);


    # Check

    if (! exists $config{rss_types}{$type} || ! exists $targetdbinfo_ref->{dbnames}{$database}){
        OpenBib::Common::Util::print_warning("RSS-Feed ungueltig",$r);
    }

    my $rss_type = $config{rss_types}{$type};

    my $thistimedate   = Date::Manip::ParseDate("today");
    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-12hours");
#    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-2seconds");

    $expiretimedate = Date::Manip::UnixDate($expiretimedate,"%Y-%m-%d %H:%M:%S");
    
    $logger->debug("ExpireTimeDate: $expiretimedate");

    # Bestimmung, ob ein valider Cacheeintrag existiert
    my $request=$sessiondbh->prepare("select content from rsscache where dbname=? and type=? and subtype = ? and tstamp > ?");
    $request->execute($database,$type,$subtype,$expiretimedate);

    my $res=$request->fetchrow_arrayref;
    my $rss_content=(exists $res->[0])?$res->[0]:undef;

    if (! $rss_content ){
        my $dbh
            = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                or $logger->error_die($DBI::errstr);

        $logger->debug("Update des RSS-Caches");
        
        my $dbdesc=$targetdbinfo_ref->{dbnames}{$database};
   
        my $rss = new XML::RSS ( version => '1.0' );
        
        $rss->channel(
            title         => "$dbdesc: Neue Katalogisate",
            link          => "http://kug.ub.uni-koeln.de/portal/lastverteilung?view=$database",
            language      => "de",
            description   => "Hier finden sie die 50 zuletzt katalogisierten Medien des Kataloges '$dbdesc'",
        );
        
        $request=$dbh->prepare("select id,content from tit_string where category=2 order by content desc limit 50");
        $request->execute();
        
        while (my $res=$request->fetchrow_hashref()){
            my $idn  = $res->{id};
            my $date = $res->{content};
            
            my $tititem_ref=OpenBib::Search::Util::get_tit_listitem_by_idn({
                titidn            => $idn,
                dbh               => $dbh,
                sessiondbh        => $sessiondbh,
                database          => $database,
                sessionID         => '-1',
                targetdbinfo_ref  => $targetdbinfo_ref,
            });

            my $desc  = "";
            my $title = $tititem_ref->{'T0331'}[0]{content};
            
            my $itemtemplatename = $config{tt_connector_rss_item_tname};
            my $itemtemplate = Template->new({
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config{tt_include_path},
                }) ],
                #                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
                OUTPUT         => \$desc,
            });


            # TT-Data erzeugen
            my $ttdata={
                item            => $tititem_ref,
                date            => $date,
            };

            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                $r->log_reason($itemtemplate->error(), $r->filename);
                return SERVER_ERROR;
            };

            $logger->debug("Desc: $desc");
            
            $logger->debug("Adding $title / $desc");
            $rss->add_item(
                title       => $title,
                link        => "http://kug.ub.uni-koeln.de/portal/lastverteilung?view=$database;database=$database;searchsingletit=$idn",
                description => $desc
            );
        }
        
        $request->finish;

        $rss_content=$rss->as_string;
        
        # Etwaig vorhandenen Eintrag loeschen
        $request=$sessiondbh->prepare("delete from rsscache where dbname=? and type=? and subtype = ?");
        $request->execute($database,$type,$subtype);

        $request=$sessiondbh->prepare("insert into rsscache values (?,NULL,?,?,?)");
        $request->execute($database,$type,$subtype,$rss_content);

        $request->finish();
        $dbh->disconnect;
    }
    else {
        $logger->debug("Verwende Eintrag aus RSS-Cache");
    }
    print $r->send_http_header("application/rdf+xml");

    print $rss_content;


    $request->finish();

    $sessiondbh->disconnect;
    
    return OK;
}

1;
