#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use Date::Manip;
use Log::Log4perl qw(get_logger :levels);
use Net::OpenSSH;
use OpenBib::Config;
use POSIX;

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=/var/log/openbib/upload_provenances.log
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config;

if ($config->local_server_belongs_to_updatable_cluster()){
    $logger->error("Server not in searchable cluster. Exiting.\n");
    exit;
}

my $now          = Date::Manip::ParseDate("now");
my $this_date    = Date::Manip::UnixDate($now,"%Y%m%d");
my $this_month   = Date::Manip::UnixDate($now,"%m");
my $this_quarter = ceil($this_month / 3);

my $host         = $config->{upload_provenances}{host};
my $user         = $config->{upload_provenances}{user};
my $password     = $config->{upload_provenances}{password};
my $local_path   = $config->{upload_provenances}{local_path}."DE-38.xml";
my $remote_path  = $config->{upload_provenances}{remote_path}."provenances_de38_361_".$this_date.".xml";

my $last_month_in_this_quarter = ($this_quarter == 1)?"March":($this_quarter == 2)?"June":($this_quarter == 3)?"September":"December";

my $wanted = Date::Manip::ParseDate("Last Tuesday in $last_month_in_this_quarter");

my $wanted_date = Date::Manip::UnixDate($wanted,"%Y%m%d");

$logger->info("This date: $this_date / Wanted date: $wanted_date");

if ($this_date eq $wanted_date){
    # Copy with scp
    $logger->info("Copying file with scp from $local_path to $remote_path");

    my $ssh = Net::OpenSSH->new($host, user => $user, password => $password);
    $ssh->scp_put($local_path, $remote_path) or die "scp failed: " . $ssh->error;
}
else {
    $logger->error("Wrong date. Exiting");
}
