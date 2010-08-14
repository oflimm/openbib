#####################################################################
#
#  OpenBib::Handler::Apache::Dispatch
#
#  Dieses File ist (C) 2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Dispatch;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestRec ();
use Apache2::URI ();
use APR::URI ();
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;

use base 'CGI::Application::Dispatch';

# sub cgiapp_init() {       # overrides
#   my $self = shift;
#   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
# }

sub handler : method {
    my ($self, $r) = @_;

    my $logger = get_logger();

    # set the PATH_INFO
    $ENV{PATH_INFO} = $r->uri(); # was $r->path_info();

    # setup our args to dispatch()
    my %args;
    my $config_args = $r->dir_config();
    foreach my $var qw(DEFAULT PREFIX ERROR_DOCUMENT) {
        my $dir_var = "CGIAPP_DISPATCH_$var";
        $args{lc($var)} = $config_args->{$dir_var}
          if($config_args->{$dir_var});
    }

    # add $r to the args_to_new's PARAMS
    $args{args_to_new}->{PARAMS}->{r} = $r;

    # set debug if we need to
    $DEBUG = 1 if($config_args->{CGIAPP_DISPATCH_DEBUG});
    if($DEBUG) {
        require Data::Dumper;
        warn "[Dispatch] Calling dispatch() with the following arguments: "
          . Data::Dumper::Dumper(\%args) . "\n";
    }

    $self->dispatch(%args);

    if($r->status == 404) {
        return Apache2::Const::NOT_FOUND;
    } elsif($r->status == 500) {
        return Apache2::Const::SERVER_ERROR;
    } elsif($r->status == 400) {
        return Apache2::Const::HTTP_BAD_REQUEST;
    } else {
        return Apache2::Const::OK;
    }
}


sub dispatch_args {

#     my $config  = OpenBib::Config->instance;

#     my $logger=get_logger();

#     my $table_ref = [];

#     foreach my $loc (grep /\_loc$/, keys %{$config->{handler}}){
#         my $rule    = $config->{handler}{$loc}{rule};
#         my $module  = $config->{handler}{$loc}{module};
#         my $runmode = $config->{handler}{$loc}{runmode};

#         $logger->debug("CGI Dispatching");
        
#         push @{$table_ref}, {
#             "$rule" => {
#                 'app' => "$module",
#                 'rm'  => "$runmode",
#             }
#         };
#     }

    my $table_ref = [
        '/portal/:view/searchmask/:type?'
            => {
                'app' => 'OpenBib::Handler::Apache::SearchMask',
                'rm'  => 'show',
            },

        '/portal/:view/admin'
            => {
                'app' => 'OpenBib::Handler::Apache::Admin',
                'rm'  => 'show',
            },

        '/portal/:view/home'
            => {
                'app' => 'OpenBib::Handler::Apache::StartOpac',
                'rm'  => 'show',
            },
        
        '/portal/:view/bibsonomy'
            => {
                'app' => 'OpenBib::Handler::Apache::BibSonomy',
                'rm'  => 'show',
            },
        
        '/portal/:view/circulation'
            => {
                'app' => 'OpenBib::Handler::Apache::Circulation',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/availabilityimage/:rm/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::AvailabilityImage',
                'rm'  => 'gbs',
            },
        
        '/portal/:view/connector/availability'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::Availability',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/literaturverwaltung'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::DigiBib',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/digibib'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::DigiBib',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/livesearch'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::LiveSearch',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/sykasignatur'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::LocationMark',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/olws'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::OLWS',
                'rm'  => 'show',
            },

        # Legacy URI - Ab v2.4 kann jeder URL direkt gebookmarkt werden
        '/portal/connector/permalink/:id1/:id2/:type/:view/index.html
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::PermaLink',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/seealso'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::SeeAlso',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/similarpersons'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::SimilarPersons',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/similarsubjects'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::SimilarSubjects',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/spellcheck'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::SpellCheck',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/rss'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::RSS',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/uk-online'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::DigiBib',
                'rm'  => 'show',
            },
        
        '/portal/:view/connector/unapi'
            => {
                'app' => 'OpenBib::Handler::Apache::Connector::UnAPI',
                'rm'  => 'show',
            },

        '/portal/:view/dbchoice'
            => {
                'app' => 'OpenBib::Handler::Apache::DatabaseChoice',
                'rm'  => 'show',
            },

        '/portal/:view/databaseprofile'
            => {
                'app' => 'OpenBib::Handler::Apache::DatabaseProfile',
                'rm'  => 'show',
            },

        '/portal/:view/dispatchquery'
            => {
                'app' => 'OpenBib::Handler::Apache::DispatchQuery',
                'rm'  => 'show',
            },

        '/portal/:view/jumpto'
            => {
                'app' => 'OpenBib::Handler::Apache::ExternalJump',
                'rm'  => 'show',
            },

        '/portal/:view/ezb'
            => {
                'app' => 'OpenBib::Handler::Apache::EZB',
                'rm'  => 'show',
            },

        '/portal/:view/dbis'
            => {
                'app' => 'OpenBib::Handler::Apache::DBIS',
                'rm'  => 'show',
            },

        '/portal/:view/info/:stid/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Info',
                'rm'  => 'show',
            },

        '/portal/:view/litlists'
            => {
                'app' => 'OpenBib::Handler::Apache::LitLists',
                'rm'  => 'show',
            },

        '/portal/:view/loadbalancer'
            => {
                'app' => 'OpenBib::Handler::Apache::LoadBalancer',
                'rm'  => 'show',
            },

        '/portal/:view/login'
            => {
                'app' => 'OpenBib::Handler::Apache::Login',
                'rm'  => 'show',
            },
        
        '/portal/:view/mailcollection'
            => {
                'app' => 'OpenBib::Handler::Apache::MailCollection',
                'rm'  => 'show',
            },
        
        '/portal/:view/mailpassword'
            => {
                'app' => 'OpenBib::Handler::Apache::MailPassword',
                'rm'  => 'show',
            },
        
        '/portal/:view/collection'
            => {
                'app' => 'OpenBib::Handler::Apache::ManageCollection',
                'rm'  => 'show',
            },
        
        '/portal/:view/redirect'
            => {
                'app' => 'OpenBib::Handler::Apache::Redirect',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/title/:database/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Title',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/person/:database/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Person',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/corporatebody/:database/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::CorporateBody',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/subject/:database/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Subject',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/classification/:database/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Classification',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/litlist/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Litlist',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/tag/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Tag',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/library/:id/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::Library',
                'rm'  => 'show',
            },
        
        '/portal/:view/resource/user/:id/:rm/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::User',
                'rm'  => 'show',
            },
        
        '/portal/:view/resultlists'
            => {
                'app' => 'OpenBib::Handler::Apache::Resource::ResultLists',
                'rm'  => 'show',
            },
        
        '/portal/:view/rssfeeds'
            => {
                'app' => 'OpenBib::Handler::Apache::RSSFeeds',
                'rm'  => 'show',
            },
        
        '/portal/:view/search'
            => {
                'app' => 'OpenBib::Handler::Apache::Search',
                'rm'  => 'show',
            },
        
        '/portal/:view/virtualsearch'
            => {
                'app' => 'OpenBib::Handler::Apache::VirtualSearch',
                'rm'  => 'show',
            },
        
        '/portal/:view/searchmask/:type'
            => {
                'app' => 'OpenBib::Handler::Apache::SearchMask',
                'rm'  => 'simple',
            },
        
        '/portal/:view/selfreg'
            => {
                'app' => 'OpenBib::Handler::Apache::SelfReg',
                'rm'  => 'show',
            },
        
        '/portal/:view/getload'
            => {
                'app' => 'OpenBib::Handler::Apache::ServerLoad',
                'rm'  => 'show',
            },
        
        '/portal/:view/tags'
            => {
                'app' => 'OpenBib::Handler::Apache::Tags',
                'rm'  => 'show',
            },
        
        '/portal/:view/userprefs'
            => {
                'app' => 'OpenBib::Handler::Apache::UserPrefs',
                'rm'  => 'show',
            },
        
        '/portal/:view/userreviews'
            => {
                'app' => 'OpenBib::Handler::Apache::UserReviews',
                'rm'  => 'show',
            },
        
        '/portal/:view/logout'
            => {
                'app' => 'OpenBib::Handler::Apache::Leave',
                'rm'  => 'show',
            },
        
        '/portal/:view/info/:stid/:representation?'
            => {
                'app' => 'OpenBib::Handler::Apache::Info',
                'rm'  => 'show',
            }

    ];
    
    return {
        debug => 1,
        table => $table_ref,
    };
}


1;
