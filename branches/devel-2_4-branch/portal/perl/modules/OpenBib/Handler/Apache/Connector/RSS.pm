####################################################################
#
#  OpenBib::Handler::Apache::Connector::RSS.pm
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::RSS;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # print, rflush
use Apache2::RequestRec ();
use Apache2::URI ();
use APR::URI ();

use Benchmark;
use Date::Manip;
use DBI;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use Template;
use XML::RSS;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

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

    # Shared Args
    my $view           = $self->param('view');
    my $type           = $self->param('type')           || '';
    my $subtype        = $self->param('subtype')        || '-1';
    my ($database)     = $self->param('dispatch_url_remainder') =~/^(.+?)\.rdf/;

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');


    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    # Check
    if (! exists $config->{rss_types}{$type} || ! exists $dbinfotable->{dbnames}{$database}{full}){
        OpenBib::Common::Util::print_warning("RSS-Feed ungueltig",$r);
    }

    # Wenn Aliases fuer den Typ existieren, dann loese ihn zur entsprechenden
    # Type-Nr auf, ansonsten nehme den uebergebenen Typ (der einer Nr sein
    # sollte...)
    $type=(exists $config->{rss_types}{$type})?$config->{rss_types}{$type}:$type;

    my $thistimedate   = Date::Manip::ParseDate("today");
    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-12hours");
#    my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-2seconds");

    $expiretimedate = Date::Manip::UnixDate($expiretimedate,"%Y-%m-%d %H:%M:%S");
    
#    $logger->debug("ExpireTimeDate: $expiretimedate");

    my $rss_content = $config->get_valid_rsscache_entry({
        database       => $database,
        type           => $type,
        subtype        => $subtype,
        expiretimedate => $expiretimedate,
    });
    
    if (! $rss_content ){
        my $bestserver='localhost';#OpenBib::Common::Util::get_loadbalanced_servername();

        $logger->debug("Getting RSS-Data from Server $bestserver");
        
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$bestserver;port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
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
            $rssfeedinfo_ref->{2}->{channel_title}.=" '".OpenBib::Record::Person->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
            $rssfeedinfo_ref->{2}->{channel_desc} .=" '".OpenBib::Record::Person->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
        }
        elsif ($type == 3){
            $rssfeedinfo_ref->{3}->{channel_title}.=" '".OpenBib::Record::CorporateBody->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
            $rssfeedinfo_ref->{3}->{channel_desc} .=" '".OpenBib::Record::CorporateBody->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
        }
        elsif ($type == 4){
            $rssfeedinfo_ref->{4}->{channel_title}.=" '".OpenBib::Record::Subject->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
            $rssfeedinfo_ref->{4}->{channel_desc} .=" '".OpenBib::Record::Subject->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
        }
        elsif ($type == 5){
            $rssfeedinfo_ref->{5}->{channel_title}.=" '".OpenBib::Record::Classification->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
            $rssfeedinfo_ref->{5}->{channel_desc} .=" '".OpenBib::Record::Classification->new({database => $database, id => $subtype})->load_name({dbh => $dbh})->name_as_string."'";
        }
        
        $logger->debug("Update des RSS-Caches");
        
        my $dbdesc=$dbinfotable->{dbnames}{$database}{full};
   
        my $rss = new XML::RSS ( version => '1.0' );
        
        $rss->channel(
            title         => "$dbdesc: ".$rssfeedinfo_ref->{$type}{channel_title},
            link        => "http://".$config->{frontendservername}.$config->{base_loc}."/$view/".$config->{loadbalancer_loc},            
            language      => "de",
            description   => $rssfeedinfo_ref->{$type}{channel_desc},
        );

        $logger->debug("DB: $database Type: $type Subtype: $subtype");
        
        my $recordlist;

        # Letzte 50 Neuaufnahmen
        if ($type == 1){
            $recordlist=OpenBib::Search::Util::get_recent_titids({
                id       => $subtype,
                database => $database,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Verfasser/Person mit Id subtypeid
        elsif ($type == 2 && $subtype){
            $recordlist=OpenBib::Search::Util::get_recent_titids_by_aut({
                id       => $subtype,
                database => $database,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Koerperschaft/Urheber mit Id subtypeid
        elsif ($type == 3 && $subtype){
            $recordlist=OpenBib::Search::Util::get_recent_titids_by_kor({
                id       => $subtype,
                database => $database,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Schlagwort mit Id subtypeid
        elsif ($type == 4 && $subtype){
            $recordlist=OpenBib::Search::Util::get_recent_titids_by_swt({
                id       => $subtype,
                database => $database,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Systematik mit Id subtypeid
        elsif ($type == 5 && $subtype){
            $recordlist=OpenBib::Search::Util::get_recent_titids_by_not({
                id       => $subtype,
                database => $database,
                limit    => 50,
            });
        }


        $logger->debug("Titel-ID's".YAML::Dump($recordlist));
        
        foreach my $record ($recordlist->get_records){
            $record->load_brief_record;
            
            my $desc  = "";
            my $title = $record->get_category({category => 'T0331', indicator => 1});
            my $ast   = $record->get_category({category => 'T0310', indicator => 1});

            $title = $ast if ($ast);
            
            my $itemtemplatename = $config->{tt_connector_rss_item_tname};
            my $itemtemplate = Template->new({
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config->{tt_include_path},
                    ABSOLUTE       => 1,
                }) ],
                RECURSION      => 1,
                OUTPUT         => \$desc,
            });
            
            
            # TT-Data erzeugen
            my $ttdata={
                record          => $record,
                msg             => $msg,
            };
            
            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                $r->log_error($itemtemplate->error(), $r->filename);
                return Apache2::Const::SERVER_ERROR;
            };
            
            $logger->debug("Adding $title / $desc") if (defined $title && defined $desc);

            $rss->add_item(
                title       => $title,
                link        => "http://".$config->{frontendservername}.$config->{base_loc}."/$view/".$config->{title_loc}."/$database/".$record->{id}.".html",
                description => $desc
            );
        }
        
        $rss_content=$rss->as_string;

        $config->update_rsscache({
            database => $database,
            type     => $type,
            subtype  => $subtype,
            rssfeed  => $rss_content,
        });

        $dbh->disconnect;
    }
    else {
        $logger->debug("Verwende Eintrag aus RSS-Cache");
    }

    #$self->header_props(-type => 'application/xml');
    #print $r->content_type("application/rdf+xml");
    $r->content_type("application/xml");

    $r->print($rss_content);

    # Aufruf des Feeds loggen
    $session->log_event({
        type      => 801,
        content   => "$database:$type:$subtype",
    });

#    return $rss_content;
    return Apache2::Const::OK;
}

1;
