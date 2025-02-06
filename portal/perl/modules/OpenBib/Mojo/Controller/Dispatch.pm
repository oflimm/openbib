#####################################################################
#
#  OpenBib::Mojo::Controller::Dispatch
#
#  Dieses File ist (C) 2010-2018 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Dispatch;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;
use Data::Dumper;
use HTTP::Exception;

use OpenBib::Config::File;
use OpenBib::Config::DispatchTable;

use base 'CGI::Application::Dispatch::PSGI';

our $DEBUG   = 0;

sub as_psgi {
    my ($self, %args) = @_;

    my $logger = get_logger();

    my $query = $args{args_to_new}->{QUERY};

    #$logger->debug("Query: ".ref($query));

    # set method for http-tunnel based on _method-CGI-Parameter
    if ($r->param('_method')){
        $args{args_to_new}->{PARAMS}->{method} = $r->param('_method');

        $query->env->{REQUEST_METHOD} = $r->param('_method');
        
        #if ($logger->is_debug){
        #    $logger->debug("Changed method to tunneled ".$r->param('_method'));
        #}
    }
    
    #$logger->debug("Dispatching as PSGI");

    $args{args_to_new}->{PARAMS}->{r} = $query;
    $args{args_to_new}->{PARAMS}->{QUERY} = $query;
    $args{args_to_new}->{QUERY} = $query;

    
    #$logger->debug("ARGS as_psgi: ".Data::Dumper::Dumper(\%args));
    
    my $psgi_app = $self->SUPER::as_psgi(%args) ;

#    $logger->debug("Output is :".YAML::Dump($psgi_app));
    
    return $psgi_app;
}


# sub handler : method {
#     my ($self, $r) = @_;

#     my $logger = get_logger();

#     my $config  = OpenBib::Config->new;

#     my ($atime,$btime,$timeall)=(0,0,0);

#     if ($config->{benchmark}) {
#         $atime=new Benchmark;
#     }

#     # set the PATH_INFO
#     $ENV{PATH_INFO} = $r->uri(); # was $r->path_info();

#     my $query = Apache2::Request->new($r);
    
#     # set method for http-tunnel based on _method-CGI-Parameter
#     if ($r->param('_method')){
#         $r->method($r->param('_method'));
#         if ($logger->is_debug){
#             $logger->debug("Changed method to tunneled ".$r->param('_method'));
#         }
#     }
    
#     # setup our args to dispatch()
#     my %args;
#     my $config_args = $r->dir_config();
#     foreach my $var ('DEFAULT','PREFIX','ERROR_DOCUMENT') {
#         my $dir_var = "CGIAPP_DISPATCH_$var";
#         $args{lc($var)} = $config_args->{$dir_var}
#           if($config_args->{$dir_var});
#     }

#     # add $r to the args_to_new's PARAMS
#     $args{args_to_new}->{PARAMS}->{r} = $r;

#     # set debug if we need to
#     $DEBUG = 0; # if($config_args->{CGIAPP_DISPATCH_DEBUG});
#     if($DEBUG) {
#         require Data::Dumper;
#         warn "[Dispatch] Calling dispatch() with the following arguments: "
#           . Data::Dumper::Dumper(\%args) . "\n";
#     }

#     $logger->debug("Dispatching");

#     if ($config->{benchmark}) {
#         $btime=new Benchmark;
#         $timeall=timediff($btime,$atime);
#         $logger->info("Total time for stage 2 ".$r->uri()." is ".timestr($timeall));
#     }

#     $self->dispatch(%args);

#     if ($config->{benchmark}) {
#         $btime=new Benchmark;
#         $timeall=timediff($btime,$atime);
#         $logger->info("Total time for dispatching ".$r->uri()." is ".timestr($timeall));
#     }
    
#     if ($logger->is_debug){
#         $logger->debug("Dispatching done with status ".$r->status);
#     }

#     if($r->status == 404) {
#         return Apache2::Const::NOT_FOUND;
#     } elsif($r->status == 500) {
#         return Apache2::Const::NOT_FOUND;
# #        return Apache2::Const::SERVER_ERROR;
#     } elsif($r->status == 400) {
#         return Apache2::Const::HTTP_BAD_REQUEST;
#     } else {
#         return Apache2::Const::OK;
#     }
# }


sub dispatch_args {
    my ($self, $args) = @_;

    my $logger = get_logger();
    
    my $dispatch_rules  = OpenBib::Config::DispatchTable->instance;

    my $table_ref = [];

    foreach my $item (@{$dispatch_rules}){
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

                if (defined $item->{scope} && defined $item->{scope}){
                    $item->{args}->{scope} = $item->{scope};
                }

                if (defined $item->{send_new_cookie} && $item->{send_new_cookie} ){
                    $item->{args}->{send_new_cookie} = 1;
                }
		else {
		    $item->{args}->{send_new_cookie} = 0;
		}
                
                if ($item->{args}){
                    # Request-Object dazu, da sonst ueberschrieben
                    $item->{args}->{r}                   = $args->{args_to_new}->{PARAMS}->{r};
                    $item->{args}->{method}              = $args->{args_to_new}->{method};
                    $item->{args}->{QUERY}               = $args->{args_to_new}->{QUERY};
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

	    if (defined $item->{scope} && defined $item->{scope}){
		$item->{args}->{scope} = $item->{scope};
	    }
	    
	    if (defined $item->{send_new_cookie} && $item->{send_new_cookie} ){
		$item->{args}->{send_new_cookie} = 1;
	    }
	    else {
		$item->{args}->{send_new_cookie} = 0;
	    }
            
            if ($item->{args}){
                # Request-Object dazu, da sonst ueberschrieben
                $item->{args}->{r}                   = $args->{args_to_new}->{PARAMS}->{r};
                $item->{args}->{method}              = $args->{args_to_new}->{method};
                $item->{args}->{QUERY}               = $args->{args_to_new}->{QUERY};
                $rule_specs->{args_to_new}->{PARAMS} = $item->{args}; 
            }
            
#            if ($item->{scope}){
#                $rule_specs->{args_to_new}->{PARAMS}->{scope} = $item->{scope}; 
#            }
            
            push @{$table_ref}, $rule_specs;
        }
    }
    
    return {
        #debug => 1,
        table => $table_ref,
    };
}

sub _run_app {
    my ($self, $module, $rm, $args,$env) = @_;

    my $logger=get_logger();

    my $config  = OpenBib::Config::File->instance;

    my $atime;
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if($DEBUG) {
        require Data::Dumper;
        warn "[Dispatch] Final args to pass to new(): " . Data::Dumper::Dumper($args) . "\n";
    }

    if($rm) {

        # check runmode name
        ($rm) = ($rm =~ /^([a-zA-Z_][\w']+)$/);
        HTTP::Exception->throw(400, status_message => "Invalid characters in runmode name") unless $rm;

    }

    # now create and run then application object
    warn "[Dispatch] creating instance of $module\n" if($DEBUG);

    my $psgi;
    eval {
        my $app = do {
            if (ref($args) eq 'HASH' and not defined $args->{PARAMS}{QUERY}) {
                require CGI::PSGI;
                $args->{QUERY} = CGI::PSGI->new($env);
                $module->new($args);
            }
            elsif (ref($args) eq 'HASH' and defined $args->{PARAMS}{QUERY}) {
                $args->{QUERY} = $args->{PARAMS}{QUERY};
                $module->new($args);
            }
            elsif (ref($args) eq 'HASH') {
                $module->new($args);
            }
            else {
                $module->new();
            }
        };
        $app->mode_param(sub { return $rm }) if($rm);
        $psgi = $app->run_as_psgi;
    };

    if ($config->{benchmark}){
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $logger->info("Processing runmode $rm in module $module took $resulttime seconds");
    }

    # App threw an HTTP::Exception? Cool. Bubble it up.
    my $e;
    if ($e = HTTP::Exception->caught) {
        $e->rethrow;   
    } 
    else {
          $e = Exception::Class->caught();

          # catch invalid run-mode stuff
          if (not ref $e and  $e =~ /No such run mode/) {
              HTTP::Exception->throw(404, status_message => "RM '$rm' not found");
          }
          # otherwise, it's an internal server error.
          elsif (defined $e and length $e) {
              HTTP::Exception->throw(500, status_message => "Unknown error: $e");
              #return $psgi;
          }
          else {
              # no exception
              return $psgi;
          }
    }
}

1;
