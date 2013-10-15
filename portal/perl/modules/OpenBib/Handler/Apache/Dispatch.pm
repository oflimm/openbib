#####################################################################
#
#  OpenBib::Handler::Apache::Dispatch
#
#  Dieses File ist (C) 2010-2012 Oliver Flimm <flimm@openbib.org>
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
use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;

use base 'CGI::Application::Dispatch';

sub handler : method {
    my ($self, $r) = @_;

    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # set the PATH_INFO
    $ENV{PATH_INFO} = $r->uri(); # was $r->path_info();

    my $query = Apache2::Request->new($r);
    
    # set method for http-tunnel based on _method-CGI-Parameter
    if ($query->param('_method')){
        $r->method($query->param('_method'));
        if ($logger->is_debug){
            $logger->debug("Changed method to tunneled ".$query->param('_method'));
        }
    }
    
    # setup our args to dispatch()
    my %args;
    my $config_args = $r->dir_config();
    foreach my $var ('DEFAULT','PREFIX','ERROR_DOCUMENT') {
        my $dir_var = "CGIAPP_DISPATCH_$var";
        $args{lc($var)} = $config_args->{$dir_var}
          if($config_args->{$dir_var});
    }

    # add $r to the args_to_new's PARAMS
    $args{args_to_new}->{PARAMS}->{r} = $r;

    # set debug if we need to
    $DEBUG = 0; # if($config_args->{CGIAPP_DISPATCH_DEBUG});
    if($DEBUG) {
        require Data::Dumper;
        warn "[Dispatch] Calling dispatch() with the following arguments: "
          . Data::Dumper::Dumper(\%args) . "\n";
    }

    $logger->debug("Dispatching");

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 ".$r->uri()." is ".timestr($timeall));
    }

    $self->dispatch(%args);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for dispatching ".$r->uri()." is ".timestr($timeall));
    }
    
    if ($logger->is_debug){
        $logger->debug("Dispatching done with status ".$r->status);
    }

    if($r->status == 404) {
        return Apache2::Const::NOT_FOUND;
    } elsif($r->status == 500) {
        return Apache2::Const::NOT_FOUND;
#        return Apache2::Const::SERVER_ERROR;
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
        my $rule       = $item->{rule};
        my $module     = $item->{module};
        my $runmode    = $item->{runmode};

        if (defined $item->{representations}){
            my @representations = @{$item->{representations}};

            foreach my $representation (@representations){
                my $new_rule = "";
                
                if ($representation eq "none"){
                    $new_rule=$rule;
                }
                elsif ($rule=~/^(.+)(\[.+?\])$/){
                    $new_rule="$1.$representation$2";
                }
                else {
                    $new_rule="$rule.$representation";
                }
                
                push @{$table_ref}, $new_rule;
                
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
        }
        else {
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
    }

    if ($logger->is_debug){
        $logger->debug("Dispatch-table: ".YAML::Dump($table_ref));
    }
    
    return {
        #debug => 1,
        table => $table_ref,
    };
}


1;
