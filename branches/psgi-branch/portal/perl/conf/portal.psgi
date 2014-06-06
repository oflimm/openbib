#!/usr/bin/perl

use strict;
use warnings;

use OpenBib::Handler::PSGI::Dispatch;
use OpenBib::Request;
use Plack::Builder;
use OpenBib::Config;

use Log::Log4perl qw(:levels get_logger);

my $config = OpenBib::Config->instance;

my $cgiapp = sub {
    my $env = shift;

    Log::Log4perl->init($config->{log4perl_path});
    
    OpenBib::Handler::PSGI::Dispatch->as_psgi(
        args_to_new => {
            QUERY      => OpenBib::Request->new($env),
        })->($env);
};

builder {
    enable "Plack::Middleware::Static",
        path => qr!^/(css|images|yaml|js)/!,
            root => '/var/www';
    $cgiapp;
};
