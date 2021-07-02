#!/usr/bin/perl

my $line = <>;
my @firstline = split("\t",$line);

my $num_columns = @firstline;

print $line;

while ($line = <>){
    my @thisline = split("\t", $line);

    if (@thisline != $num_columns){
	print STDERR "Fehler: $line\n";
	next;
    }

    print $line;
}
