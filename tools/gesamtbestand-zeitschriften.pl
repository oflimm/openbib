#!/usr/bin/perl

#####################################################################
#
#  gesamtbestand-zeitschriften.pl
#
#  Ausgabe des Gesamtbestands an Zeitschriften aufgeschluesselt nach
#  USB, Fakultaten und einzelne Besitzende Bibliothek in eine csv-Datei
#
#  Grundlage ist die ZDB-ID in den Katalogen inst001 (USB Bestand) und
#  instzs (Bestand aller Institute)
#
#  Dieses File ist (C) 2009-2011 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################   

use strict;
use warnings;

use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML::Syck;

my $config      = OpenBib::Config->instance;

my ($help,$logfile,$selector,$filename);

&GetOptions(
            "logfile=s"       => \$logfile,
            "filename=s"      => \$filename,
	    "help"            => \$help
	    );

if ($help || !$filename){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gesamtbestand-zeitschriften.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=instzs;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);
my $usbdbh = DBI->connect("DBI:$config->{dbimodule}:dbname=inst001;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

my $configdbh = DBI->connect("DBI:$config->{dbimodule}:dbname=config;host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd}) or $logger->error_die($DBI::errstr);

my $configrequest=$configdbh->prepare("select sigel,orgunit from dbinfo where orgunit rlike '^[0-5]' and active=1 and sigel rlike '^[0-6][0-9][0-9]\$' order by sigel") or $logger->error($DBI::errstr);

$configrequest->execute() or $logger->error($DBI::errstr);;

my @sigel = ();
my %sigel2fak=();

while (my $result=$configrequest->fetchrow_hashref){
    push @sigel,"38/".$result->{sigel};
    $sigel2fak{"38/".$result->{sigel}} = $result->{orgunit};
}

$logger->debug("Sigelliste: ".YAML::Dump(\@sigel));

#  my %all_sigel = (
#    '38/514' => 1,
#    '38/006' => 1,
#  );

# @sigel = map { ($all_sigel{$_})?$all_sigel{$_}:'0' } @sigel;

#  print join(";",@sigel);

#  exit;

my %zdbids_all  = ();
my %zdbids_usb  = ();
my %zdbids_inst = ();

my %zdb2tit_usb  = ();
my %zdb2tit_inst = ();

# Laufender Bestand - mindestens ein Owner hat den laufenden Bestand
my $request=$dbh->prepare("select distinct conn.sourceid as zdbid from mex,conn where mex.category=1204 and mex.content like '%-' and conn.sourcetype=1 and conn.targettype=6 and conn.targetid=mex.id") or $logger->error($DBI::errstr);

$request->execute() or $logger->error($DBI::errstr);;

while (my $result=$request->fetchrow_hashref){
    my $zdbid = $result->{zdbid};
    $zdbids_inst{$zdbid}=1;
    $zdb2tit_inst{$zdbid}=$zdbid;
    $zdbids_all{$zdbid}=1;    
}

#print "Institute\n";
#foreach my $zdbid (keys %zdbids_all){
#   print "$zdbid\n";
#}
#print YAML::Dump(\%zdbids_all);

my $request=$usbdbh->prepare("select tit.content as zdbid ,conn.sourceid as titid from mex,conn,tit where mex.category=1204 and mex.content like '%-' and conn.sourcetype=1 and conn.targettype=6 and conn.targetid=mex.id and conn.sourceid=tit.id and tit.category=572 and tit.indicator=11") or $logger->error($DBI::errstr);

$request->execute() or $logger->error($DBI::errstr);;

while (my $result=$request->fetchrow_hashref){
    my $zdbid = $result->{zdbid};
    my $titid = $result->{titid};

    $zdbids_usb{$zdbid}=1;
    $zdb2tit_usb{$zdbid}=$titid;
    $zdbids_all{$zdbid}=1;    
}

#print "USB\n";

#foreach my $zdbid (keys %zdbids_all){
#   print "$zdbid\n";
#}

#print YAML::Dump(\%zdb2tit_usb);

open(OUT,">$filename");

print OUT "Titel\tZDB-ID\tISSN\tVerlag\tUSB\tUnabh\tWiso\tRecht\tHuman\tPhil\tMatNat\t".join("\t",@sigel)."\n";

foreach my $zdbid (keys %zdbids_all){

    my $insttitle;
    my $usbtitle;
    my $usbnormset;
    my $usbmexset;
    my $instnormset;
    my $instmexset;

    my $hst    = "";
    my $issn   = "";
    my $verlag = "";

    next unless ($zdbid);

    if ($zdbids_inst{$zdbid}){
        $insttitle = new OpenBib::Record::Title({id => $zdb2tit_inst{$zdbid}, database=> 'instzs'})->load_full_record;
        $instnormset = $insttitle->get_normdata;
        $instmexset  = $insttitle->get_mexdata;
        $hst    = konv($instnormset->{'T0331'}->[0]->{content});
        $issn   = konv($instnormset->{'T0543'}->[0]->{content});
        $verlag = konv($instnormset->{'T0412'}->[0]->{content});

    }

    if ($zdbids_usb{$zdbid}){
        $usbtitle = new OpenBib::Record::Title({id => $zdb2tit_usb{$zdbid}, database=> 'inst001'})->load_full_record;
        $usbnormset = $usbtitle->get_normdata;
        $usbmexset  = $usbtitle->get_mexdata;
        $hst    = konv($usbnormset->{'T0331'}->[0]->{content}) if (!$hst);
        $issn   = konv($usbnormset->{'T0543'}->[0]->{content}) if (!$issn);
        $verlag = konv($usbnormset->{'T0412'}->[0]->{content}) if (!$verlag);
    }
    
    my %all_sigel = ();

    my $laufend = 0;

    foreach my $mex (@{$instmexset}){
        my $bestandsverlauf = $mex->{'X1204'}->{content};
        my $sigel           = "38/".$mex->{'X3330'}->{content};
        $bestandsverlauf =~s/\[.+?]//g;
        if ($bestandsverlauf =~/-\s*$/){
            $all_sigel{$sigel} = 1;
            $laufend = 1;
        }
    }

    foreach my $mex (@{$usbmexset}){
        my $bestandsverlauf = $mex->{'X1204'}->{content};
        $bestandsverlauf =~s/\[.+?]//g;
        if ($bestandsverlauf =~/-\s*$/){
            $all_sigel{'38'} = 1;
            $laufend = 1;
        }
    }

    if ($laufend){
       $logger->debug("ZDBID $zdbid hat laufenden Bestand");
       $logger->debug("Sigel".YAML::Dump(\%all_sigel));
       my %have_fakult = ();
       my $have_usb    = ($zdbids_usb{$zdbid})?'1':'0';

       map { $have_fakult{$sigel2fak{$_}} = $have_fakult{$sigel2fak{$_}} + 1} keys %all_sigel;

       $logger->debug("Vor".YAML::Dump(\@sigel));

       my @aktive_sigel = @sigel;

       map { $_ = ($all_sigel{$_})?$all_sigel{$_}:'0' } @aktive_sigel;
       
       $logger->debug("Nach".YAML::Dump(\@aktive_sigel));

       my $ungeb  = ($have_fakult{'0ungeb'})?$have_fakult{'0ungeb'}:'0';
       my $wiso   = ($have_fakult{'1wiso'})?$have_fakult{'1wiso'}:'0';
       my $recht  = ($have_fakult{'2recht'})?$have_fakult{'2recht'}:'0';
       my $human  = ($have_fakult{'3human'})?$have_fakult{'3human'}:'0';
       my $phil   = ($have_fakult{'4phil'})?$have_fakult{'4phil'}:'0';
       my $matnat = ($have_fakult{'5matnat'})?$have_fakult{'5matnat'}:'0';

       $logger->debug("Fakultaeten".YAML::Dump(\%have_fakult));

       print OUT "$hst\t$zdbid\t$issn\t$verlag\t$have_usb\t$ungeb\t$wiso\t$recht\t$human\t$phil\t$matnat\t".join("\t",@aktive_sigel)."\n";
    }

}

close(OUT);

$request->finish;
$dbh->disconnect;
$usbdbh->disconnect;

sub print_help {
    print << "HELP";
bestandsvergleich-zeitschriften.pl - Abgleich des Uni-Zeitschriften-Bestandes und Ausgabe in eine csv-Datei

    bestandsvergleich-zeitschriften.pl --filename=out.csv
HELP
exit;
}

sub konv {
    my ($line) = @_;

    $line=~s/&amp;/\&/g;
    $line=~s/&gt;/>/g;
    $line=~s/&lt;/</g;

    return $line;
}
