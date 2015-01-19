#!/usr/bin/perl

use strict;
use warnings;

use OpenBib::Handler::PSGI::Dispatch;
use OpenBib::Request;
use Plack::Builder;
use OpenBib::Config;
#use Devel::NYTProf;
use Log::Log4perl qw(:levels get_logger);

my $cgiapp = sub {
    my $env = shift;

    my $config = OpenBib::Config->instance;
    Log::Log4perl->init($config->{log4perl_path});
    
    my $app = OpenBib::Handler::PSGI::Dispatch->as_psgi(
        #debug      => 1,
        args_to_new => {
            QUERY      => OpenBib::Request->new($env),
        });

    return $app->($env);
};

builder {
    enable "Plack::Middleware::Static",
        path => qr!^/(css|images|yaml|js)/!,
            root => '/var/www';

#    enable 'Debug', panels =>
#        [ qw(Environment Response Timer Memory Profiler::NYTProf)
#      ];
    
    $cgiapp;
};
