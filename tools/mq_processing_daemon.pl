#!/usr/bin/perl

use warnings;
use strict;
use Daemon::Control;
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);

my $dir = "/opt/openbib/bin/";

exit Daemon::Control->new(
    name        => 'OpenBib MQ Processing Daemon',
    lsb_start   => '$syslog $remote_fs',
    lsb_stop    => '$syslog',
    lsb_sdesc   => 'OpenBib MQ Daemon',
    lsb_desc    => 'OpenBib MQ Processing Daemon',
    path        => $dir,

    program     => catfile($dir, 'process_mq_task.pl'),
    program_args => [ ],

    pid_file    => '/var/log/openbib/mq_processing_daemon.pid',
    stderr_file => '/var/log/openbib/mq_processing_daemon.log',
    stdout_file => '/var/log/openbib/mq_processing_daemon.log',

    fork        => 2,

)->run;
