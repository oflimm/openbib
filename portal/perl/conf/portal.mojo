#!/usr/bin/perl

use strict;
use warnings;

use Mojo::Base -strict;
use lib qw(lib);
use Mojolicious::Commands;

# Start command line interface for application
Mojolicious::Commands->start_app('OpenBib::Mojo');
