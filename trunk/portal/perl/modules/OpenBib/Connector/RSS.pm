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
use OpenBib::L10N;
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

    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Basisipfad entfernen
    my $basepath = $config{connector_rss_loc};
    $path=~s/$basepath//;

    # RSS-Feedparameter aus URI bestimmen
    #
    # 

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

    if (! exists $config{rss_types}{$type} || ! exists $targetdbinfo_ref->{dbnames}{$database}{full}){
        OpenBib::Common::Util::print_warning("RSS-Feed ungueltig",$r);
    }

    # Wenn Aliases fuer den Typ existieren, dann loese ihn zur entsprechenden
    # Type-Nr auf, ansonsten nehme den uebergebenen Typ (der einer Nr sein
    # sollte...)
    $type=(exists $config{rss_types}{$type})?$config{rss_types}{$type}:$type;

    my $thistimedate   = Date::Manip::ParseDate("today");
    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-12hours");
#    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-2seconds");

    $expiretimedate = Date::Manip::UnixDate($expiretimedate,"%Y-%m-%d %H:%M:%S");
    
#    $logger->debug("ExpireTimeDate: $expiretimedate");

    # Bestimmung, ob ein valider Cacheeintrag existiert
    my $request=$sessiondbh->prepare("select content from rsscache where dbname=? and type=? and subtype = ? and tstamp > ?");
    $request->execute($database,$type,$subtype,$expiretimedate);

    my $res=$request->fetchrow_arrayref;
    my $rss_content=(exists $res->[0])?$res->[0]:undef;

    if (! $rss_content ){
        my $bestserver=OpenBib::Common::Util::get_loadbalanced_servername();

        $logger->debug("Getting RSS-Data from Server $bestserver");
        
        my $dbh
            = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$bestserver;port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                or $logger->error_die($DBI::errstr);

        my $rssfeedinfo_ref = {
            1 => {
                channel_title => "Neue Katalogisate",
                channel_desc  => "Hier finden Sie die 50 zuletzt katalogisierten Medien des Kataloges",
            },
            2 => {
                channel_title => "Neue Katalogisate zu Verfasser/Person",
                channel_desc  => "Hier finden Sie die 50 zuletzt katalogisierten Medien des Kataloges zu Verfasser/Person ",
            },
            3 => {
                channel_title => "Neue Katalogisate zu K&ouml;rperschaft/Urheber",
                channel_desc  => "Hier finden Sie die 50 zuletzt katalogisierten Medien des Kataloges zu K&ouml;rperschaft/Urheber ",
            },
            4 => {
                channel_title => "Neue Katalogisate zum Schlagwort",
                channel_desc  => "Hier finden Sie die 50 zuletzt katalogisierten Medien des Kataloges zum Schlagwort ",
            },
            5 => {
                channel_title => "Neue Katalogisate zur Systematik",
                channel_desc  => "Hier finden Sie die 50 zuletzt katalogisierten Medien des Kataloges zur Systematik ",
            },

            99 => {
                channel_title => 'Neuerwerbungen',
                channel_desc  => 'Hier finden Sie die 50 zuletzt erworbenen Medien des Kataloges',
            },
        };

        if    ($type == 2){
            $rssfeedinfo_ref->{2}->{channel_title}.=" '".OpenBib::Search::Util::get_aut_ans_by_idn($subtype,$dbh)."'";
            $rssfeedinfo_ref->{2}->{channel_desc} .=" '".OpenBib::Search::Util::get_aut_ans_by_idn($subtype,$dbh)."'";
        }
        elsif ($type == 3){
            $rssfeedinfo_ref->{3}->{channel_title}.=" '".OpenBib::Search::Util::get_kor_ans_by_idn($subtype,$dbh)."'";
            $rssfeedinfo_ref->{3}->{channel_desc} .=" '".OpenBib::Search::Util::get_kor_ans_by_idn($subtype,$dbh)."'";
        }
        elsif ($type == 4){
            $rssfeedinfo_ref->{4}->{channel_title}.=" '".OpenBib::Search::Util::get_swt_ans_by_idn($subtype,$dbh)."'";
            $rssfeedinfo_ref->{4}->{channel_desc} .=" '".OpenBib::Search::Util::get_swt_ans_by_idn($subtype,$dbh)."'";
        }
        elsif ($type == 5){
            $rssfeedinfo_ref->{5}->{channel_title}.=" '".OpenBib::Search::Util::get_not_ans_by_idn($subtype,$dbh)."'";
            $rssfeedinfo_ref->{5}->{channel_desc} .=" '".OpenBib::Search::Util::get_not_ans_by_idn($subtype,$dbh)."'";
        }
        
        $logger->debug("Update des RSS-Caches");
        
        my $dbdesc=$targetdbinfo_ref->{dbnames}{$database}{full};
   
        my $rss = new XML::RSS ( version => '1.0' );
        
        $rss->channel(
            title         => "$dbdesc: ".$rssfeedinfo_ref->{$type}{channel_title},
            link          => "http://".$config{loadbalancerservername}.$config{loadbalancer_loc}."?view=$database",
            language      => "de",
            description   => $rssfeedinfo_ref->{$type}{channel_desc}." '$dbdesc'",
        );

        $logger->debug("DB: $database Type: $type Subtype: $subtype");
        
        my $titlist_ref=();

        # Letzte 50 Neuaufnahmen
        if ($type == 1){
            $titlist_ref=OpenBib::Search::Util::get_recent_titids({
                dbh   => $dbh,
                id    => $subtype,
                limit => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Verfasser/Person mit Id subtypeid
        elsif ($type == 2 && $subtype){
            $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_aut({
                dbh   => $dbh,
                id    => $subtype,
                limit => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Koerperschaft/Urheber mit Id subtypeid
        elsif ($type == 3 && $subtype){
            $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_kor({
                dbh   => $dbh,
                id    => $subtype,
                limit => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Schlagwort mit Id subtypeid
        elsif ($type == 4 && $subtype){
            $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_swt({
                dbh   => $dbh,
                id    => $subtype,
                limit => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Systematik mit Id subtypeid
        elsif ($type == 5 && $subtype){
            $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_not({
                dbh   => $dbh,
                id    => $subtype,
                limit => 50,
            });
        }


        $logger->debug("Titel-ID's".YAML::Dump($titlist_ref));
        
        foreach my $title_ref (@$titlist_ref){
            my $tititem_ref=OpenBib::Search::Util::get_tit_listitem_by_idn({
                titidn            => $title_ref->{id},
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
                    ABSOLUTE       => 1,
                }) ],
#                INCLUDE_PATH   => $config{tt_include_path},
#                ABSOLUTE       => 1,
                OUTPUT         => \$desc,
            });
            
            
            # TT-Data erzeugen
            my $ttdata={
                item            => $tititem_ref,
                date            => $title_ref->{date},
                msg             => $msg,
            };
            
            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                $r->log_reason($itemtemplate->error(), $r->filename);
                return SERVER_ERROR;
            };
            
            $logger->debug("Desc: $desc");
            
            $logger->debug("Adding $title / $desc");
            $rss->add_item(
                title       => $title,
                link        => "http://".$config{loadbalancerservername}.$config{loadbalancer_loc}."?view=$database;database=$database;searchsingletit=".$title_ref->{id},
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
    #print $r->send_http_header("application/rdf+xml");
    print $r->send_http_header("application/xml");

    print $rss_content;


    $request->finish();

    $sessiondbh->disconnect;
    
    return OK;
}

1;
