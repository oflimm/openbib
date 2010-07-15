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

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::URI ();
use APR::URI ();
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;

use OpenBib::Handler::Apache::Admin;
use OpenBib::Handler::Apache::BibSonomy;
use OpenBib::Handler::Apache::DBIS;
use OpenBib::Handler::Apache::EZB;
use OpenBib::Handler::Apache::Circulation;
use OpenBib::Handler::Apache::Search;
use OpenBib::Handler::Apache::VirtualSearch;
use OpenBib::Handler::Apache::ResultLists;
use OpenBib::Handler::Apache::StartOpac;
use OpenBib::Handler::Apache::SearchMask;
use OpenBib::Handler::Apache::Info;
use OpenBib::Handler::Apache::ExternalJump;
use OpenBib::Handler::Apache::DispatchQuery;
use OpenBib::Handler::Apache::DatabaseChoice;
use OpenBib::Handler::Apache::Login;
use OpenBib::Handler::Apache::LoadBalancer;
use OpenBib::Handler::Apache::Leave;
use OpenBib::Handler::Apache::ManageCollection;
use OpenBib::Handler::Apache::MailCollection;
use OpenBib::Handler::Apache::MailPassword;
use OpenBib::Handler::Apache::DatabaseProfile;
use OpenBib::Handler::Apache::SelfReg;
use OpenBib::Handler::Apache::UserPrefs;
use OpenBib::Handler::Apache::ServerLoad;
use OpenBib::Handler::Apache::Connector::Availability;
use OpenBib::Handler::Apache::Connector::AvailabilityImage;
use OpenBib::Handler::Apache::Connector::DigiBib;
use OpenBib::Handler::Apache::Connector::LiveSearch;
use OpenBib::Handler::Apache::Connector::LocationMark;
use OpenBib::Handler::Apache::Connector::OLWS;
use OpenBib::Handler::Apache::Connector::PermaLink;
use OpenBib::Handler::Apache::Connector::RSS;
use OpenBib::Handler::Apache::Connector::SeeAlso;
use OpenBib::Handler::Apache::Connector::SimilarPersons;
use OpenBib::Handler::Apache::Connector::SimilarSubjects;
use OpenBib::Handler::Apache::Connector::SpellCheck;
use OpenBib::Handler::Apache::Connector::UnAPI;
use OpenBib::Handler::Apache::LitLists;
use OpenBib::Handler::Apache::Resource::Title;
use OpenBib::Handler::Apache::Resource::Person;
use OpenBib::Handler::Apache::Resource::CorporateBody;
use OpenBib::Handler::Apache::Resource::Subject;
use OpenBib::Handler::Apache::Resource::Classification;
use OpenBib::Handler::Apache::Resource::Tag;
use OpenBib::Handler::Apache::Resource::Litlist;
use OpenBib::Handler::Apache::RSSFeeds;
use OpenBib::Handler::Apache::Redirect;
use OpenBib::Handler::Apache::Resource;
use OpenBib::Handler::Apache::Tags;
use OpenBib::Handler::Apache::UserReviews;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;


    # Initialisierung von OpenBib

    my $dispatch_ref = {};

    foreach my $loc (grep /\_loc$/, keys %{$config->{handler}}){
        $dispatch_ref->{$config->{handler}{$loc}{name}}{$config->{handler}{$loc}{realm}}=$config->{handler}{$loc}{module};
    }

#    $logger->debug(YAML::Dump($dispatch_ref));

    # Basisipfad entfernen
    my $basepath = $config->{base_loc};
    $path=~s/$basepath//;

    my ($view,$location)=(undef,undef);

    # View-spezifische URI's
    if ($path=~m/^\/([^\/]+)\/(connector\/[^\/]+)/){
        ($view,$location)=($1,$2);
    }
    elsif ($path=~m/^\/([^\/]+)\/(resource\/[^\/]+)/){
        ($view,$location)=($1,$2);
    }
    elsif ($path=~m/^\/([^\/]+)\/([^\/]+)/){
        ($view,$location)=($1,$2);
    }

    return Apache2::Const::OK unless ($view && $location);

    $logger->debug("Got view $view and location $location");

    my $dispatch_target = "";
    
    if ($view eq "common" && exists $dispatch_ref->{$location}{common}){
        $dispatch_target = $dispatch_ref->{$location}{common};
    }
    elsif (exists $dispatch_ref->{$location}{view}){
        $dispatch_target = $dispatch_ref->{$location}{view};
    }

    if ($dispatch_target){
        $logger->debug("Dispatch to $dispatch_target");
        
        $r->handler('modperl');
        $r->set_handlers(PerlResponseHandler => $dispatch_target);

        $r->subprocess_env('openbib_view' => $view);

    }
    
    return Apache2::Const::OK;
}

1;
