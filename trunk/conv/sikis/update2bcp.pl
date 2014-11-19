#!/usr/local/bin/perl

use Log::Log4perl qw(get_logger :levels);
use DBI;
use YAML;

my $configfile = "/opt/sisis/myscripts/update2bcp.yml";
my $logfile  = '/tmp/update2bcp.log';
my $loglevel = "INFO";

my $config = YAML::LoadFile($configfile);

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

my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{database};server=$config->{dbserver};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or error_die($DBI::errstr);


my $set_ref = {
    1 => {
	desc => 'title',
	table => 'titel_daten',
    },
    2 => {
	desc => 'person',
	table => 'per_daten',
    },
    3 => {
	desc => 'corporatebody',
	table => 'koe_daten',
    },
    4 => {
	desc => 'subject',
	table => 'swd_daten',
    },
    5 => {
	desc => 'classification',
	table => 'sys_daten',
    }
};

# open(SIKFSTAB,">sik_fstab.bcp");

# my $sql_statement = qq{
#   select * 

#   from $config->{database}.sisis.sik_fstab
# };
  
# my $request=$dbh->prepare($sql_statement);
# $request->execute() or $logger->error_die($DBI::errstr);

# while (my $result = $request->fetchrow_arrayref){
#     print SIKFSTAB join('',@$result),"\n";
# }

# close(SIKFSTAB);

my $update_orders_ref = {};

my $sql_statement = qq{
  select * 

  from $config->{database}.sisis.cat_orders

  where katkey < 20000000
};
  
my $request=$dbh->prepare($sql_statement);
$request->execute() or $logger->error_die($DBI::errstr);

while (my $result = $request->fetchrow_hashref){
    $update_orders_ref->{$set_ref->{$result->{setnr}}{desc}}{$result->{katkey}} = $result->{action};
}

foreach my $type (keys %$set_ref){
    open(OUT,">$set_ref->{$type}{table}.bcp");
  
    foreach my $katkey (keys %{$update_orders_ref->{$set_ref->{$type}{desc}}}){
	my $action = $update_orders_ref->{$set_ref->{$type}{desc}}{$katkey};
	
	if ($action eq "d"){
	    if ($type == 1){
		print OUT "$katkey$action\n";
	    }
	    elsif ($type >= 2 && $type <= 4){
		print OUT "$katkey$action\n";
	    }
	    elsif ($type == 5){
		print OUT "$katkey$action\n";
	    }
	    next;
	}

	my $sql_statement2 = qq{
  select * 

  from $config->{database}.sisis.$set_ref->{$type}{table}

  where katkey = $katkey
};
	
	my $request2=$dbh->prepare($sql_statement2);
	$request2->execute() or $logger->error_die($DBI::errstr);
	
	while (my $result2 = $request2->fetchrow_arrayref){
	    print OUT join('',@$result2),"$action\n";
	}
    }
    
    close(OUT);
}

# Buchdaten

my %titelbuchkey = ();

open(TITBUCHKEY,">titel_buch_key.bcp");

foreach my $katkey (keys %{$update_orders_ref->{title}}){

    my $sql_statement = qq{
  select * 

  from $config->{database}.sisis.titel_buch_key

  where katkey = $katkey
};
    
    my $request=$dbh->prepare($sql_statement);
    $request->execute() or $logger->error_die($DBI::errstr);
    
    while (my $result = $request->fetchrow_arrayref){
	print TITBUCHKEY join('',@$result),"\n";
	$titelbuchkey{$result->[1]} = 1;
    }
}

close(TITBUCHKEY);

open(D01BUCH,">d01buch.bcp");

foreach my $mcopynum (keys %titelbuchkey){

    my $sql_statement = qq{
  select * 

  from $config->{database}.sisis.d01buch

  where d01mcopyno = $mcopynum
};
    
    my $request=$dbh->prepare($sql_statement);
    $request->execute() or $logger->error_die($DBI::errstr);
    
    while (my $result = $request->fetchrow_arrayref){
	print D01BUCH join('',@$result),"\n";
    }
}

close(D01BUCH);
