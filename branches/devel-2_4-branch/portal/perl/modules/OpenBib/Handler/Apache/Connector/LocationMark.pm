####################################################################
#
#  OpenBib::Handler::Apache::Connector::LocationMark.pm
#
#  ehemals biblio-signatur.pl
#
#  Herausgabe von Titellisten anhand einer Grundsignatur
#
#  Dieses File ist (C) 2000-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::LocationMark;

use Apache2::Const -compile => qw(:common);
use Apache2::RequestRec ();

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;
use Encode qw(decode_utf8);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::VirtualSearch::Util;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);
    
#     my $status=$query->parse;
    
#     if ($status){
#         $logger->error("Cannot parse Arguments");
#     }

    my $session = OpenBib::Session->instance;

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle('de') || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # CGI-Input auslesen
    
    #####################################################################
    #
    # Eingabeparamter
    #

    my $base       = $query->param('base')       || undef;
    my $location   = decode_utf8($query->param('location'))   || undef;
    my $range_start= $query->param('start')      || undef;
    my $range_end  = $query->param('end')        || undef;
    my $title      = decode_utf8($query->param('title'))      || '';

    my $offset     = $query->param('offset')     || 1;
    my $hitrange   = $query->param('hitrange')   || 50;;

    my $database   = $query->param('database')   || '';

    return Apache2::Const::OK unless (defined $base);

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
    
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    
    if ($base && $location){
        $logger->debug("Bestimme Titel zur Grundsignatur '$base' und Standort '$location'");

        my $sql = "select distinct c.sourceid, m1.content from conn as c, mex as m1 left join mex as m2 on m1.id=m2.id where m1.category=14 and m1.content like ? and m1.content != 'bestellt' and m1.content != 'vergriffen' and m1.content != 'storniert' and m2.category = 16 and m2.content = ? and c.targettype=6 and c.targetid=m1.id and c.sourcetype=1";
        my $request=$dbh->prepare($sql); # "select distinct conn.sourceid from mex, conn where mex.category=14 and mex.content like ? and mex.content != 'bestellt' and mex.content != 'vergriffen' and mex.content != 'storniert' and conn.sourcetype=1 and conn.targettype=6 and conn.targetid=mex.id and mex.id in (select distinct id from mex where category = 16 and content = ? )");
        $request->execute("$base%",$location);

        my @filtered_titids = ();
        while (my $result=$request->fetchrow_hashref){
            my $titid   = $result->{sourceid};
            my $locmark = $result->{content};

            $logger->debug("Found titid $titid with location mark $locmark");
            
            if ($locmark=~m/^$base/){
                $logger->debug("Location mark $locmark matches base $base");

                if ($range_start > 0 && $range_end > 0){
                     my ($number)=$locmark=~m/^$base(\d+)/;
                     $logger->debug("Number part is $number");

                     if ($number >= $range_start && $number <= $range_end) {
                        $logger->debug("Location mark $locmark in Range $range_start - $range_end");
                        push @filtered_titids, {
                            id       => $titid,
                            locmark  => $locmark,
                            base     => $base,
                        }
                     }
                     else {
                        $logger->debug("Location mark $locmark NOT in Range $range_start - $range_end");
                     }
                 }
                 else {
                        $logger->debug("No range specified for location mark $locmark ");
                     push @filtered_titids, {
                         id       => $titid,
                         locmark  => $locmark,
                         base     => $base,
                     };
                 }
             }
        }

        my @sortedtitids = sort by_signature @filtered_titids;

        $logger->debug("Gefundene Titelids: ".YAML::Dump(\@sortedtitids));
        
        my @outputbuffer = ();

        foreach my $titid_ref (@sortedtitids) {
            my $id = $titid_ref->{id};

            my $listitem_ref = OpenBib::Record::Title->new({id => $id, database => $database})->load_brief_record({ dbh => $dbh })->get_brief_normdata;
            
            # Bereinigung der Signaturen. Alle Signaturen, die nicht zur Grundsignatur gehoeren,
            # werden entfernt.
            my $cleansig_ref = [];
            foreach my $sig_ref (@{$listitem_ref->{X0014}}){
                if ($sig_ref->{content}=~m/^$base/){
                    push @$cleansig_ref, $sig_ref;
                }
            }
            $listitem_ref->{X0014}=$cleansig_ref;
            push @outputbuffer, $listitem_ref;
        }

        $logger->debug("Vollstaendige Titel: ".YAML::Dump(\@outputbuffer));

        # TT-Data erzeugen
        my $ttdata={
            itemlist     => \@outputbuffer,
            signaturdesc => $title,
            database     => $database,
            view         => $view,
            config       => $config,
        };
        
        my $template = Template->new({ 
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config->{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            OUTPUT         => $r,    # Output geht direkt an Apache Request
            RECURSION      => 1,
        });

        # Start der Ausgabe mit korrektem Header
        $r->content_type("text/html");

        $template->process($config->{tt_connector_locationmark_titlist_tname}, $ttdata) || do {
#        $template->process("lbs_systematik", $ttdata) || do {
            $logger->error("Fehler bei der Ausgabe des Template: ".$template->error());
            return;
        };
    }
    
    return Apache2::Const::OK;
}

sub by_signature {
    my %line1=%$a;
    my %line2=%$b;

#    my $logger = get_logger() ;
    
    my $base = $line1{base};
    
    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{locmark} && defined $line1{locmark})?cleanrl($line1{locmark}):"0";
    my $line2=(exists $line2{locmark} && defined $line2{locmark})?cleanrl($line2{locmark}):"0";

#    $logger->debug("1 L1: $line1 / L2: $line2 / Base: $base");
    
    my ($zahl1,$rest1)=$line1=~m/$base(\d+)(.*?)/i;
    my ($zahl2,$rest2)=$line2=~m/$base(\d+)(.*?)/i;

#    $logger->debug("2 Z1: $zahl1 / R1: $rest1 / Z2: $zahl2 / R2: $rest2");
    
    $line1=sprintf "%08d%s", $zahl1, $rest1;
    $line2=sprintf "%08d%s", $zahl2, $rest2;

#    $logger->debug("3 L1: $line1 / L2: $line2");
    
    $line1 cmp $line2;
}

sub cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}

1;
