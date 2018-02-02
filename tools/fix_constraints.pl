#!/usr/bin/perl

use Log::Log4perl qw(get_logger :levels);
use Getopt::Long;
use DBI;

use OpenBib::Config;

my ($help,$dryrun,$logfile,$loglevel);

&GetOptions("dryrun"          => \$dryrun,
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "help"            => \$help
	    );

# if ($help){
#     print_help();
# }


$logfile=($logfile)?$logfile:'/var/log/openbib/fix_constraints.log';
$loglevel=($loglevel)?$loglevel:'INFO';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
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

# Verbindung zur SQL-Datenbank herstellen
my $dbh = DBI->connect("DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd},{'pg_enable_utf8'    => 1})
    or $logger->error($DBI::errstr);


my $sql = "select conname,consrc from pg_constraint where conname ~ '_tstamp_check' and consrc ~ '0[1-9]:00:00' order by conname;";

my $request = $dbh->prepare($sql);

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $name = $result->{conname};
    my $src  = $result->{consrc};

    my ($table) = $name =~m/^(.+)_tstamp_check/;

    my $fixedsrc=$src;

    $fixedsrc =~s/0[1-9]:00:00/00:00:00/g;

    my $ch_request1 = $dbh->prepare("alter table $table drop constraint $name;");
    $ch_request1->execute();

    my $ch_request2 = $dbh->prepare("alter table $table add constraint $name CHECK $fixedsrc;");
    $ch_request2->execute();
}
