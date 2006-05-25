#!/usr/bin/perl

use Locale::Maketext::Extract;

my $pofilepath   = "/opt/openbib/locales/messages.po";
my $l10nfilepath = "/opt/openbib/locales/FILES";

my @l10nfiles=();

open (L10NFILES,$l10nfilepath);
while (my $file=<L10NFILES>){
    chomp($file);
    push @l10nfiles, $file;
}
close(L10NFILES);

my $messages = Locale::Maketext::Extract->new;

$messages->read_po($pofilepath) if (-f $pofilepath);
foreach my $file (@l10nfiles){
    $messages->extract_file($file);
}

$messages->compile;
$messages->write_po($pofilepath);
