#!/usr/bin/perl

#####################################################################
#
#  marc2meta.pl
#
#  Konverierung von MARC-Daten in das Meta-Format
#
#  Dieses File ist (C) 2009-2013 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use utf8;

use Encode 'decode';
use Getopt::Long;
use DBI;
use MARC::Batch;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

$mexidn  =  1;

my $config = OpenBib::Config->instance;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
marc2meta.pl - Aufrufsyntax

    marc2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

open (TITLE,         ">:utf8","meta.title");
open (PERSON,        ">:utf8","meta.person");
open (CORPORATEBODY, ">:utf8","meta.corporatebody");
open (CLASSIFICATION,">:utf8","meta.classification");
open (SUBJECT,       ">:utf8","meta.subject");
open (HOLDING,       ">:utf8","meta.holding");

my $titleid = 1;

my $multcount_ref = {};

my $batch = MARC::Batch->new('USMARC', $inputfile);

# Recover from errors
$batch->strict_off();
$batch->warnings_off();


my @buffer = ();
while (my $record = $batch->next()){

    my $title_ref  = {};
    $multcount_ref = {};

    my $idfield = $record->field('000');

    $title_ref->{id} = $idfield->as_string();

    foreach my $field ($record->fields()){
        my $kateg   = $field->tag(),defined $field->indicator(1)?$field->indicator(1):"",$field->indicator(2)?$field->indicator(2):"";
        my $content = decode($convconfig->{encoding},$field->as_string()) || $field->as_string();

        print ":$kateg:",$field->as_string(),"\n";
        if (exists $convconfig->{title}{$kateg}){
            # Filter

            if ($kateg eq "040"){
                $content=~s/PGUSA //;
            }

            if ($kateg eq "245"){
                my ($vorlverf) = $content=~m/\s+\/\s+(.*?)$/;

                push @{$title_ref->{'0359'}}, {
                    mult       => 1,
                    subfield   => '',
                    content    => $vorlverf,
                } if ($vorlverf);

                $content=~s/\s+\/\s+(.*?)$//;
                $content=~s/\s+\[electronic resource\]//;
            }

            if ($kateg eq "260"){
                my ($ejahr) = $content=~m/,\s+(\d\d\d\d)$/;

                push @{$title_ref->{'0425'}}, {
                    mult       => 1,
                    subfield   => '',
                    content    => $ejahr,
                } if ($ejahr);

                $content=~s/,\s+\d\d\d\d$//;
            }

            if ($kateg eq "856"){
                if ($content =~/http:\/\/www.gutenberg.org\/license/){
                    next;
                }
            }
            
            if ($content){
                print TIT $convconfig->{title}{$kateg}.$content."\n";
            }
        }
        
        # Autoren abarbeiten Anfang
        elsif (exists $convconfig->{pers}{$kateg} && $content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $autidn=get_autidn($part);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$part\n";
                    print AUT "9999:\n";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                print TIT $convconfig->{pers}{$kateg}."IDN: $autidn\n";
            }
        }       
        # Autoren abarbeiten Ende
        
        # Koerperschaften abarbeiten Anfang
        elsif (exists $convconfig->{corp}{$kateg} && $content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                
                my $koridn=get_koridn($part);
                
                if ($koridn > 0){
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$part\n";
                    print KOR "9999:\n";
                    
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                print TIT $convconfig->{corp}{$kateg}."IDN: $koridn\n";
            }
        }
        # Koerperschaften abarbeiten Ende
        
        # Notationen abarbeiten Anfang
        elsif (exists $convconfig->{sys}{$kateg} && $content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $notidn=get_notidn($part);
                
                if ($notidn > 0){	  
                    print NOTATION "0000:$notidn\n";
                    print NOTATION "0001:$part\n";
                    print NOTATION "9999:\n";
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                print TIT $convconfig->{sys}{$kateg}."IDN: $swtidn\n";
            }
        }
        # Schlagworte abarbeiten Ende
        
        
        # Schlagworte abarbeiten Anfang
        elsif (exists $convconfig->{subj}{$kateg} && $content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $swtidn=get_swtidn($part);
                
                if ($swtidn > 0){	  
                    print SWT "0000:$swtidn\n";
                    print SWT "0001:$part\n";
                    print SWT "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                print TIT $convconfig->{subj}{$kateg}."IDN: $swtidn\n";
            }
        }
        # Schlagworte abarbeiten Ende
        
        elsif (exists $convconfig->{exempl}{$kateg} && $content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                print MEX "0000:$mexidn\n";
                print MEX "0004:$titleid\n";
                print MEX $convconfig->{exempl}{$kateg}.$part."\n";
                print MEX "9999:\n";
                $mexidn++;
            }
        }
    }
    print TIT "9999:\n";
    $titleid++;
}

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

close(DAT);
