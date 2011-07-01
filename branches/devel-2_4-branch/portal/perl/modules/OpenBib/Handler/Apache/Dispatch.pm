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
    my ($self, $args) = @_;

    my $logger=get_logger();
    
    my $config  = OpenBib::Config->instance;

    my $table_ref = [];

    foreach my $item (@{$config->{dispatch_rules}}){
        my $rule    = $item->{rule};
        my $module  = $item->{module};
        my $runmode = $item->{runmode};

#       $logger->debug("CGI Dispatching");

        push @{$table_ref}, $rule;

        my $rule_specs = {
            'app' => "$module",
            'rm'  => "$runmode",
        };
        
        if ($item->{args}){
            # Request-Object dazu, da sonst ueberschrieben
            $item->{args}->{r} = $args->{args_to_new}->{PARAMS}->{r};
            $rule_specs->{args_to_new}->{PARAMS} = $item->{args}; 
        }
                       
        
        push @{$table_ref}, $rule_specs;
    }
    
    return {
        debug => 1,
        table => $table_ref,
    };
}


1;
