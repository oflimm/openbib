#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
 
BEGIN {
	$ENV{HTTP_HOST} = 'http://localhost:8008/';
}
 
use Plack::Test;
use HTTP::Request::Common qw(GET);
use Path::Tiny qw(path);
 
my $app  = do './portal.profile.psgi';
my $test = Plack::Test->create($app);
#my $res  = $test->request( GET 'http://localhost:8008/portal/unikatalog/search.html?l=de;fs=programming perl' );
my $res  = $test->request( GET 'http://localhost:8008/portal/unikatalog/databases/id/inst001/titles/id/583239.html?l=de' );
 
say 'ERROR: code is     ' . $res->code . ' instead of 200'   if $res->code != 200;
say 'ERROR: messages is ' . $res->message . ' instead of OK' if $res->message ne 'OK';
say 'ERROR: incorrect content'                               if $res->content !~ m{Unikatalog};
