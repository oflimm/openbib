#!/usr/bin/perl

$year=2016;


my @tables=('eventlog','eventlogjson','searchfields','searchterms');

my @months=('12');

foreach my $month (sort @months){
    my $nextyear  = $year;
    my $nextmonth = sprintf "%02d", $month+1;
    if ($month eq "12"){
	$nextyear++;
	$nextmonth="01";
    };
    foreach my $table (@tables) {
	print "begin;\n";
	print "alter table ${table}_p${year}_${month} drop constraint ${table}_p${year}_${month}_tstamp_check;\n";
	print "alter table ${table}_p${year}_${month} add constraint ${table}_p${year}_${month}_tstamp_check CHECK (tstamp >= '$year-${month}-01 00:00:00'::timestamp without time zone AND tstamp < '$nextyear-${nextmonth}-01 00:00:00'::timestamp without time zone);\n";
	print "commit;\n";
    }
}
