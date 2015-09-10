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

    my $config = OpenBib::Config->new;
    Log::Log4perl->init($config->{log4perl_path});
    
    my $app = OpenBib::Handler::PSGI::Dispatch->as_psgi(
#        debug      => 1,
        args_to_new => {
            QUERY      => OpenBib::Request->new($env),
        });

    return $app->($env);
};

builder {
    enable "Plack::Middleware::Static",
        path => qr!^/(css|images|yaml|js)/!,
            root => '/var/www';

    enable "Plack::Middleware::SizeLimit" => (
        max_unshared_size_in_kb => '4194304', # 4GB
        # min_shared_size_in_kb => '8192', # 8MB
        # max_process_size_in_kb => '16384', # 16MB
        check_every_n_requests => 2
    );

#    enable 'Debug', panels =>
#        [ qw(Environment Response Timer Memory Profiler::NYTProf)
#      ];
    
    $cgiapp;
};
