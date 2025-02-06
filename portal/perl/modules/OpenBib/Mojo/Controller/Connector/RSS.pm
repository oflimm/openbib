####################################################################
#
#  OpenBib::Mojo::Controller::Connector::RSS.pm
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

package OpenBib::Mojo::Controller::Connector::RSS;

use strict;
use warnings;
no warnings 'redefine';

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
use OpenBib::Catalog::Factory;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $type           = $self->param('type')           || '';
    my $subtype        = $self->param('subtype')        || '-1';
    my ($database)     = $self->param('dispatch_url_remainder') =~/^(.+?)\.rdf/;

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $path           = $self->stash('path');
    my $servername     = $self->stash('servername');


    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

    my $sysprofile= $config->get_profilename_of_view($view);

    # Check
    if (! exists $config->{rss_types}{$type} || ! defined $dbinfotable->get('dbnames')->{$database}{full}){
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

#    my $rss_content;
    my $rss_content = $config->get_valid_rsscache_entry({
        database       => $database,
        type           => $type,
        id             => $subtype,
        expiretimedate => $expiretimedate,
    });
    
    if (! $rss_content ){

        $logger->debug("Getting RSS-Data");

        my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database });

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
            $rssfeedinfo_ref->{2}->{channel_title}.=" '".OpenBib::Record::Person->new({database => $database, id => $subtype})->load_name->name_as_string."'";
            $rssfeedinfo_ref->{2}->{channel_desc} .=" '".OpenBib::Record::Person->new({database => $database, id => $subtype})->load_name->name_as_string."'";
        }
        elsif ($type == 3){
            $rssfeedinfo_ref->{3}->{channel_title}.=" '".OpenBib::Record::CorporateBody->new({database => $database, id => $subtype})->load_name->name_as_string."'";
            $rssfeedinfo_ref->{3}->{channel_desc} .=" '".OpenBib::Record::CorporateBody->new({database => $database, id => $subtype})->load_name->name_as_string."'";
        }
        elsif ($type == 4){
            $rssfeedinfo_ref->{4}->{channel_title}.=" '".OpenBib::Record::Subject->new({database => $database, id => $subtype})->load_name->name_as_string."'";
            $rssfeedinfo_ref->{4}->{channel_desc} .=" '".OpenBib::Record::Subject->new({database => $database, id => $subtype})->load_name->name_as_string."'";
        }
        elsif ($type == 5){
            $rssfeedinfo_ref->{5}->{channel_title}.=" '".OpenBib::Record::Classification->new({database => $database, id => $subtype})->load_name->name_as_string."'";
            $rssfeedinfo_ref->{5}->{channel_desc} .=" '".OpenBib::Record::Classification->new({database => $database, id => $subtype})->load_name->name_as_string."'";
        }
        
        $logger->debug("Update des RSS-Caches");
        
        my $dbdesc=$dbinfotable->get('dbnames')->{$database}{full};
   
        my $rss = new XML::RSS ( version => '1.0' );
        
        $rss->channel(
            title         => "$dbdesc: ".$rssfeedinfo_ref->{$type}{channel_title},
            link          => "http://$servername$path",            
            language      => "de",
            description   => $rssfeedinfo_ref->{$type}{channel_desc},
        );

        $logger->debug("DB: $database Type: $type Subtype: $subtype");
        
        my $recordlist;

        # Letzte 50 Neuaufnahmen
        if ($type == 1){
            $recordlist = $catalog->get_recent_titles({
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Verfasser/Person mit Id subtypeid
        elsif ($type == 2 && $subtype){
            $recordlist = $catalog->get_recent_titles_of_person({
                id       => $subtype,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Koerperschaft/Urheber mit Id subtypeid
        elsif ($type == 3 && $subtype){
            $recordlist = $catalog->get_recent_titles_of_corporatebody({
                id       => $subtype,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Schlagwort mit Id subtypeid
        elsif ($type == 4 && $subtype){
            $recordlist = $catalog->get_recent_titles_of_subject({
                id       => $subtype,
                limit    => 50,
            });
        }
        # Letzte 50 Neuaufnahmen zu Systematik mit Id subtypeid
        elsif ($type == 5 && $subtype){
            $recordlist = $catalog->get_recent_titles_of_classification({
                id       => $subtype,
                limit    => 50,
            });
        }


        if ($logger->is_debug){
            $logger->debug("Titel-ID's".YAML::Dump($recordlist));
        }       
        
        foreach my $record ($recordlist->get_records){
            $record->load_brief_record;
            
            my $desc  = "";
            my $title = $record->get_field({field => 'T0331', mult => 1});
            my $ast   = $record->get_field({field => 'T0310', mult => 1});

            $title = $ast if ($ast);
            
            my $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
                view         => $view,
                profile      => $sysprofile,
                templatename => $config->{tt_connector_rss_item_tname},
            });

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
                $logger->error($itemtemplate->error());
                $self->header_add('Status',400); # server error
                return;
            };
            
            $logger->debug("Adding $title / $desc") if (defined $title && defined $desc);

            my $link = "http://$servername$path_prefix/".$config->{databases_loc}."/id/$record->{database}/".$config->{titles_loc}."/id/".$record->{id};
            $rss->add_item(
                title       => $title,
                link        => $link,
                description => $desc
            );
        }
        
        $rss_content=$rss->as_string;

       $config->update_rsscache({
           database => $database,
           type     => $type,
           id       => $subtype,
           rssfeed  => $rss_content,
       });

    }
    else {
        $logger->debug("Verwende Eintrag aus RSS-Cache");
    }

    $self->header_add('Content-Type' => 'application/xml');

    # Aufruf des Feeds loggen
    $session->log_event({
        type      => 801,
        content   => "$database:$type:$subtype",
    });

    return $rss_content;

}

1;
