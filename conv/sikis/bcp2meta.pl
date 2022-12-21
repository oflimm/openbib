#!/usr/bin/perl

#####################################################################
#
#  bcp2meta.pl
#
#  Aufloesung der mit bcp exportierten Blob-Daten in den Normdateien 
#  und Konvertierung in ein Metaformat.
#  Zusaetzlich werden die Daten in einem leicht modifizierten
#  Original-Format ausgegeben.
#
#  Routinen zum Aufloesen der Blobs (das intellektuelle Herz
#  des Programs):
#
#  Copyright 2003 Friedhelm Komossa
#                 <friedhelm.komossa@uni-muenster.de>
#
#  Programm, Konvertierungsroutinen in das Metaformat
#  und generelle Optimierung auf Bulk-Konvertierungen
#
#  Copyright 2003-2018 Oliver Flimm
#                      <flimm@openbib.org>
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

use 5.008000;
#use warnings;
use strict;
use utf8;

use Encode;
use Getopt::Long;
use JSON::XS;
use Data::Dumper;
#use MLDBM qw(DB_File Storable);
use Storable ();

our ($bcppath,$usestatus,$useusbschema,$used01buch,$used01buchstandort,$usemcopynum,$blobencoding,$reducemem);

&GetOptions(
    "reduce-mem"           => \$reducemem,
    "bcp-path=s"           => \$bcppath,
    "blob-encoding=s"      => \$blobencoding, # V<4.0: iso-8859-1, V>=4.0: utf8
    "use-d01buch"          => \$used01buch,
    "use-status"           => \$usestatus,
    "use-usbschema"        => \$useusbschema,
    "use-d01buch-standort" => \$used01buchstandort,
    "use-mcopynum"         => \$usemcopynum,
);

# Wo liegen die bcp-Dateien

$bcppath=($bcppath)?$bcppath:"/tmp";
$blobencoding=($blobencoding)?$blobencoding:"utf8";

# Problematische Kategorien in den Titeln:
#
# - 0220.001 Entspricht der Verweisform, die eigentlich zu den
#            Koerperschaften gehoert.
#

my $subfield_transform_ref = {
    person => {
        '0806a' => '0200',      # Lebensjahre
        '0806i' => '0201',      # Beruf
        '0806c' => '0305',      # Geburtsort
    },
};

our $entl_map_ref = {
    'X' => 0, # nein
    ' ' => 1, # ja
    'L' => 2, # Lesesaal
    'B' => 3, # Bes. Lesesaal
    'W' => 4, # Wochenende
};

our $updatecode_map_ref = {
    'c' => 'change',
    'n' => 'create',
    'd' => 'delete',
};

###
## Feldstrukturtabelle auswerten
#

our ($fstab_ref,$subfield_ref) = read_fstab();

my %zweigstelle  = ();
my %abteilung    = ();
my %standort     = ();
my %buchdaten    = ();
my %titelbuchkey = ();

if ($reducemem) {
    #tie %buchdaten,        'MLDBM', "./buchdaten.db"
    #or die "Could not tie buchdaten.\n";
    
    #tie %titelbuchkey,     'MLDBM', "./titelbuchkey.db"
    #or die "Could not tie titelbuchkey.\n";
}

#goto WEITER;
###
## Normdateien einlesen
#

print STDERR  "Processing persons\n";

open(PER,"cat $bcppath/per_daten.bcp |");
#open(PERSIK,"|gzip > ./unload.PER.gz");
open(PERSIKJSON,"|gzip > ./meta.person.gz");
#binmode(PERSIK,     ":utf8");
binmode(PERSIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten,$updatecode) = split ("",<PER>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    chomp($updatecode);

    my %record  = decode_blob('person',$daten,$subfield_ref->{person});

#    printf PERSIK "0000:%0d\n", $katkey;

    my $person_ref = {
        id     => $katkey,
        fields => {},
    };

    if ($updatecode){
	$person_ref->{action} = $updatecode_map_ref->{$updatecode};
    }

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;

        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content  = $record{$key};

        my $subfield = "";

        if (defined $subfield_ref->{'person'}{$field} && $content =~m/^\((.)\)(.+)/){
            ($subfield,$content) = ($1,$2);
        }
        
        my $thiskey = $key;
        my $newkey  = transform_subfield('person',$key,$subfield,$content) if (defined $subfield_ref->{'person'}{$field});

        if ($newkey) {
            $thiskey = $newkey;
            $content=~s/^[a-z]\|*//;
            $content=~s/\$\$.+$//;
            $content=~s/^\d\d\d\d\d\d\d-\d           //;

            # Aufteilung in Geburts/Sterbedatum, wenn genaue Datumsangaben in 0200
            if ($newkey eq "0200" && $content=~/\d\d\.\d\d\.\d\d\d\d/) {
                my ($dateofbirth) = $content=~/^(\d\d\.\d\d\.\d\d\d\d)-/;
                my ($dateofdeath) = $content=~/-(\d\d\.\d\d\.\d\d\d\d)$/;

                if ($dateofbirth) {
#                    print PERSIK "0304:".konv($dateofbirth)."\n";
                }

                if ($dateofdeath) {
#                    print PERSIK "0306:".konv($dateofdeath)."\n";
                }

                next;
            }
        }

        $content = konv($content);
            
#        print PERSIK $thiskey.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$person_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }
    
    eval {
	print PERSIKJSON encode_json $person_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }
#    print PERSIK "9999:\n\n";    
}
close(PERSIKJSON);
close(PERSIK);
close(PER);

print STDERR  "Processing corporate bodies\n";

open(KOE,"cat $bcppath/koe_daten.bcp |");
#open(KOESIK,"| gzip >./unload.KOE.gz");
open(KOESIKJSON,"|gzip > ./meta.corporatebody.gz");
#binmode(KOESIK,     ":utf8");
binmode(KOESIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten,$updatecode) = split ("",<KOE>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    chomp($updatecode);

    my %record  = decode_blob('corporatebody',$daten,$subfield_ref->{corporatebody});

#    printf KOESIK "0000:%0d\n", $katkey;

    my $corporatebody_ref = {
        id     => $katkey,
        fields => {},
    };

    if ($updatecode){
	$corporatebody_ref->{action} = $updatecode_map_ref->{$updatecode};
    }

    foreach my $key (sort {$b cmp $a} keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

        my $subfield = "";

        if (defined $subfield_ref->{'corporatebody'}{$field} && $content =~m/^\((.)\)(.+)/){
            ($subfield,$content) = ($1,$2);
        }
        
#        print KOESIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$corporatebody_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }

    eval {
	print KOESIKJSON encode_json $corporatebody_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }

#    print KOESIK "9999:\n\n";
}
close(KOESIKJSON);
#close(KOESIK);
close(KOE);

print STDERR  "Processing classifications\n";

open(SYS,"cat $bcppath/sys_daten.bcp |");
#open(SYSSIK,"| gzip >./unload.SYS.gz");
open(SYSSIKJSON,"| gzip >./meta.classification.gz");
#binmode(SYSSIK,     ":utf8");
binmode(SYSSIKJSON);

while (my ($katkey,$aktion,$reserv,$ansetzung,$daten,$updatecode) = split ("",<SYS>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    chomp($updatecode);

    my %record  = decode_blob('classification',$daten,$subfield_ref->{classification});
        
#    printf SYSSIK "0000:%0d\n", $katkey;

    my $classification_ref = {
        id     => $katkey,
        fields => {},
    };

    if ($updatecode){
	$classification_ref->{action} = $updatecode_map_ref->{$updatecode};
    }

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

        my $subfield = "";
        
        if (defined $subfield_ref->{'classification'}{$field} && $content =~m/^\((.)\)(.+)/){
            ($subfield,$content) = ($1,$2);
        }
        
#        print SYSSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$classification_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }

    eval {
	print SYSSIKJSON encode_json $classification_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }

#    print SYSSIK "9999:\n\n";
}
close(SYSSIKJSON);
#close(SYSSIK);
close(SYS);

print STDERR  "Processing subjects\n";

open(SWD,       "cat $bcppath/swd_daten.bcp |");
#open(SWDSIK,    "| gzip >./unload.SWD.gz");
open(SWDSIKJSON,"| gzip >./meta.subject.gz");
#binmode(SWDSIK,     ":utf8");
binmode(SWDSIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten,$updatecode) = split ("",<SWD>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    chomp($updatecode);

    my %record  = decode_blob('subject',$daten,$subfield_ref->{subject});
    
#    printf SWDSIK "0000:%0d\n", $katkey;

    my $subject_ref = {
        id     => $katkey,
        fields => {},
    };

    if ($updatecode){
	$subject_ref->{action} = $updatecode_map_ref->{$updatecode};
    }

    # Schlagwortkettensonderbehandlung SIKIS
    # Nicht im JSON-Format!!!
    
    my @swtkette=();
    foreach my $key (sort {$b cmp $a} keys %record) {
        if ($key =~/^0800/) {
            $record{$key}=~s/^\(?[a-z]\)?([\p{Lu}0-9¬])/$1/; # Indikator herausfiltern
            push @swtkette, konv($record{$key});
        }
    }

    my $schlagw;
    
    if ($#swtkette > 0) {
        $schlagw=join (" / ",reverse @swtkette);

    } else {
        $schlagw=$swtkette[0];
    }

#    printf SWDSIK "0800.001:$schlagw\n" if ($schlagw !~ /idn:/);

    # Jetzt den Rest ausgeben.

    foreach my $key (sort {$b cmp $a} keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content  = konv($record{$key});

        my $subfield = "";
        
        if (defined $subfield_ref->{'subject'}{$field} && $content =~m/^\((.)\)(.+)/){
            ($subfield,$content) = ($1,$2);
        }

#        print SWDSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/ && $key !~/^0800/);
    
        push @{$subject_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
    }

    eval {
	print SWDSIKJSON encode_json $subject_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }
    
#    print SWDSIK "9999:\n\n";
}

close(SWDSIKJSON);
#close(SWDSIK);
close(SWD);

#WEITER:
# cat eingefuegt, da bei 'zu grossen' bcp-Dateien bei Systemtools wie less oder perl
# ein Fehler bei open() auftritt:
# Fehler: Wert zu gro�ss fuer definierten Datentyp
# Daher Umweg ueber cat, bei dem dieses Problem nicht auftritt

print STDERR  "Processing titles and holdings\n";

if ($used01buch) {
    ###
    ## Zweigstellen auswerten
    #
    
    open(ZWEIG,"cat $bcppath/d50zweig.bcp |");
    while (<ZWEIG>) {
        my ($zwnr,$zwname)=split("",$_);
        $zweigstelle{$zwnr}=$zwname;
    }
    close(ZWEIG);
    
    if ($used01buchstandort){
	###
	## Originaeres Standortfeld auswerten
	#
	
	open(ORT,"cat $bcppath/d615standort.bcp |");
	while (<ORT>) {
	    my ($lfd,$standortkuerzel,$text)=split("",$_);
	    $standort{$standortkuerzel}=$text;
	}
	close(ORT);
    } 
    else {
	###
	## Abteilungen als "Standorte" auswerten
	#
	
	open(ABT,"cat $bcppath/d60abteil.bcp |");
	while (<ABT>) {
	    my ($zwnr,$abtnr,$abtname)=split("",$_);
	    $abteilung{$zwnr}{$abtnr}=$abtname;
	}
	close(ABT);
    }

    ###
    ## Titel-Buch-Key auswerten
    #

    if ($usemcopynum) {
        print STDERR  "Using mcopynum\n";
        open(TITELBUCHKEY,"cat $bcppath/titel_buch_key.bcp |");
        while (<TITELBUCHKEY>) {
            my ($katkey,$mcopynum,$seqnr)=split("",$_);
            push @{$titelbuchkey{$mcopynum}},$katkey;
        }
        close(TITELBUCHKEY);
    }
    
    ###
    ## Buchdaten auswerten
    #

    print STDERR  "Reading d01buch\n";
    open(D01BUCH,"cat $bcppath/d01buch.bcp |");
    while (<D01BUCH>) {
        my @line = split("",$_);

        if ($usemcopynum) {            
	    my ($d01gsi,$d01ex,$d01zweig,$d01entl,$d01mcopynum,$d01status,$d01skond,$d01ort,$d01abtlg,$d01ort2,$d01standort)=@line[0,1,2,3,7,11,12,24,31,53,55];
            #print "$d01gsi,$d01ex,$d01zweig,$d01mcopynum,$d01ort,$d01abtlg\n";
            foreach my $katkey (@{$titelbuchkey{$d01mcopynum}}) {
                push @{$buchdaten{$katkey}}, [$d01zweig,$d01ort,$d01abtlg,$d01standort,$d01entl,$d01status,$d01skond,$d01gsi,$d01ex,$d01ort2];
            }
        } else {
            my ($d01gsi,$d01ex,$d01zweig,$d01entl,$d01katkey,$d01status,$d01skond,$d01ort,$d01abtlg,$d01ort2,$d01standort)=@line[0,1,2,3,7,11,12,24,31,53,55];
            #print "$d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg\n";
            push @{$buchdaten{$d01katkey}}, [$d01zweig,$d01ort,$d01abtlg,$d01standort,$d01entl,$d01status,$d01skond,$d01gsi,$d01ex,$d01ort2];
        }
    }
    close(D01BUCH);

}

###
## titel_exclude Daten auswerten
#

print STDERR  "Reading titel_exclude\n";

my %titelexclude = ();
open(TEXCL,"cat $bcppath/titel_exclude.bcp |");
while (<TEXCL>) {
    my ($junk,$titidn)=split("",$_);
    chomp($titidn);
    $titelexclude{"$titidn"}="excluded";
}
close(TEXCL);

open(TITEL,"cat $bcppath/titel_daten.bcp |");
open(TITSIKJSON,"| gzip >./meta.title.gz");
open(MEXSIKJSON,"| gzip >./meta.holding.gz");
binmode(TITSIKJSON);
binmode(MEXSIKJSON);

while (my ($katkey,$aktion,$fcopy,$reserv,$vsias,$vsiera,$vopac,$daten,$updatecode) = split ("",<TITEL>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);
    next if ($titelexclude{"$katkey"} eq "excluded");

    chomp($updatecode);

    my %record  = decode_blob('title',$daten,$subfield_ref->{title});
        
    my $treffer="";
    my $active=0;
    my $idx=0;
    my @fussnbuf=();

    my $maxmex          = 0;
    my %besbibbuf       = ();
    my %erschverlbuf    = ();
    my %erschverlbufpos = ();
    my %erschverlbufneg = ();
    my %bemerkbuf1      = ();
    my %bemerkbuf2      = ();
    my %signaturbuf     = ();
    my %standortbuf     = ();
    my %inventarbuf     = ();

#    printf TITSIK "0000:%0d\n", $katkey;

    my $title_ref = {
        id     => $katkey,
        fields => {},
    };

    if ($updatecode){
	$title_ref->{action} = $updatecode_map_ref->{$updatecode};
    }

    my $langmult = 1;
    
    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }

        if ($key !~/^0000/) {

            my $content  = konv($record{$key});
            
            my $subfield = "";
            
            if (defined $subfield_ref->{'title'}{$field} && $content =~m/^\((.)\)(.+)/){
                ($subfield,$content) = ($1,$2);
            }
            
            my $line = $key.":".$content."\n";
#            print TITSIK $line if ($record{$key} !~ /idn:/);

            # Verknuepfungskategorien?
            if ($content =~m/^IDN: (\S+)/) {
                my $id = $1;
                my $supplement = "";
                if ($content =~m/^IDN: \S+ ; (.+)/) {
                    $supplement = $1;
                }

                push @{$title_ref->{fields}{$field}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $id,
                    supplement => $supplement,
                };
            }
            else {

                push @{$title_ref->{fields}{$field}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $content,
                };
                
                if ($useusbschema) {
		    # Mapping
		    #
		    # 1200 (Bemerkung 1) -> 1200
		    # 1201 (Erscheinungsverlauf positiv) -> 1204 (pos u. neg)
		    # 1202 (Erscheinungsverlauf negativ) -> 1204 (pos u. neg)
		    # 1203 (Bemerkung 2) -> 1203
		    # 1204 (Signatur) -> 0014
		    # 0012 (Sigel Besitzende Bibliothek) -> 3330

		    # bisher ungemappt
		    # 1205
		    # 1212 (zusammengesetzte Angabe)
		    
                    # Grundsignatur ZDB-Aufnahme
                    if ($line=~/^1204\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $signaturbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1200\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $bemerkbuf1{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1201\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $erschverlbufpos{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1202\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $erschverlbufneg{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1203\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $bemerkbuf2{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
		    

                    # if ($line=~/^1212\.(\d\d\d):(.*$)/) {
                    #     my $zaehlung=$1;
                    #     my $inhalt=$2;

		    # 	# Parsen des Inhalts
		    # 	if ($inhalt =~m/^(.+?) : (.+?) : (.+?)$/){
		    # 	    $erschverlbufpos{$zaehlung}=$1;
		    # 	    $signaturbuf{$zaehlung} = $2;
		    # 	    $bemerkbuf2{$zaehlung} = $3;

		    # 	}
		    # 	elsif ($inhalt =~m/^(.+?) : (.+?)$/){
		    # 	    $erschverlbufpos{$zaehlung}=$1;
		    # 	    $signaturbuf{$zaehlung} = $2;
		    # 	}
		    # 	else {
		    # 	    $erschverlbufpos{$zaehlung}=$inhalt;
		    # 	}
			
                    #     if ($maxmex <= $zaehlung) {
                    #         $maxmex=$zaehlung;
                    #     }
                    # }
		    
                    if ($line=~/^0012\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $besbibbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung
                        }
                    }
                }
                else {
                    if ($line=~/^0016.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $standortbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^0014\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $signaturbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                                        
                    if ($line=~/^1204\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $erschverlbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^3330\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $besbibbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung
                        }
                    }
                    
                    if ($line=~/^0005\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $inventarbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                }
            }
        }
    }                           # Ende foreach

    # Exemplardaten abarbeiten Anfang
  
    # Wenn ZDB-Aufnahmen gefunden wurden, dann diese Ausgeben
    if ($maxmex && !exists $buchdaten{$katkey}) {
        my $k=1;
        while ($k <= $maxmex) {	  
            my $multkey=sprintf "%03d",$k;
            
            my $signatur = $signaturbuf{$multkey};
            my $standort = $standortbuf{$multkey};
            my $inventar = $inventarbuf{$multkey};
            my $bemerk1  = $bemerkbuf1{$multkey};
            my $bemerk2  = $bemerkbuf2{$multkey};
            my $sigel    = $besbibbuf{$multkey};
	    my $erschpos = $erschverlbufpos{$multkey};
	    my $erschneg = $erschverlbufneg{$multkey};
            #$sigel=~s!^38/!!;

	    # Leere Saetze ignorieren
	    if (!$signatur && !$standort && !$inventar && !$erschpos){
		$k++;
		next;
	    }

	    my $holdingid = $katkey."-".$multkey;

            if ($useusbschema) {
                my $erschverl=$erschverlbufpos{$multkey};
                $erschverl.=" ".$erschverlbufneg{$multkey} if (exists $erschverlbufneg{$multkey});
                
                my $holding_ref = {
                    'id'     => $holdingid,
                    'fields' => {
                        '0004'   => [
                            {
                                mult     => 1,
                                subfield => '',
                                content  => $katkey,
                            },
                         ],
                    },                    
                };

                if ($inventar) {
                    push @{$holding_ref->{fields}{'0005'}}, {
                        content  => $inventar,
                        mult     => 1,
                        subfield => '',
                    };
                }
                            
                if ($signatur) {
                    push @{$holding_ref->{fields}{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }

                if ($standort) {
                    push @{$holding_ref->{fields}{'0016'}}, {
                        content  => $standort,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk1) {
                    push @{$holding_ref->{fields}{'1200'}}, {
                        content  => $bemerk1,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk2) {
                    push @{$holding_ref->{fields}{'1203'}}, {
                        content  => $bemerk2,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{fields}{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{fields}{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

		eval {
		    print MEXSIKJSON encode_json $holding_ref, "\n";
		};

		if ($@){
		    print STDERR $@, "\n";
		}
            }
            else {
                my $erschverl=$erschverlbuf{$multkey};

                my $holding_ref = {
                    id      => $holdingid,
                    'fields' => {
                       '0004' =>
                        [
                            {
                                mult     => 1,
                                subfield => '',
                                content  => $katkey,
                            },
                        ],
                     },
                };

                if ($inventar) {
                    push @{$holding_ref->{fields}{'0005'}}, {
                        content  => $inventar,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($signatur) {
                    push @{$holding_ref->{fields}{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }

                if ($standort) {
                    push @{$holding_ref->{fields}{'0016'}}, {
                        content  => $standort,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{fields}{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{fields}{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

		eval {
		    print MEXSIKJSON encode_json $holding_ref, "\n";
		};

		if ($@){
		    print STDERR $@, "\n";
		}
            }
          
            $k++;
        }

	# Nur Zeitschriften ohne Buchdaten, aber keine E-Medien
        if ($usestatus && defined $title_ref->{fields}{'0543'}){
            push @{$title_ref->{fields}{'4400'}}, {
                mult       => 1,
                subfield   => '',
                content    => 'presence',
            };
        }
    }
    elsif (exists $buchdaten{$katkey}) {
        my $overall_mediastatus_ref = {}; # lendable_[immediate|order|weekend] oder presence_[immediate|order]
        
        foreach my $buchsatz_ref (@{$buchdaten{$katkey}}) {
            my $mediennr    = $buchsatz_ref->[7];
            my $ex          = $buchsatz_ref->[8];
            my $signatur    = $buchsatz_ref->[1];
            my $signatur2   = $buchsatz_ref->[9];
            my $standort    = $zweigstelle{$buchsatz_ref->[0]};

            my $mediastatus;

            if ($ex ne " "){
                $mediennr = $mediennr."#".$ex;
		if ($signatur =~/\#$/){
		    $signatur = $signatur.$ex;
		}
            }

	    # Kombination mit dem Katkey, um Bindeeinheiten - ein Buchdatensatz mit einer Mediennummer fuer mehrere Titel - abbilden zu koennen und eine Eindeutige ID fuer duplizierte Exemplarsaetze zu erhalten

	    my $holdingid = $katkey."-".$mediennr;

            if ($usestatus){
                $mediastatus = get_mediastatus($buchsatz_ref) ;

                if ($mediastatus eq "bestellbar"){
                    $overall_mediastatus_ref->{lendable} = 1;
#                    $overall_mediastatus_ref->{lendable_order} = 1;
                }
                elsif ($mediastatus eq "nur in Lesesaal bestellbar" || $mediastatus eq "nur in bes. Lesesaal bestellbar"){
                    $overall_mediastatus_ref->{presence} = 1;
#                    $overall_mediastatus_ref->{presence_order} = 1;                    
                }
                elsif ($mediastatus eq "nur Wochenende"){
                    $overall_mediastatus_ref->{lendable} = 1;
#                    $overall_mediastatus_ref->{lendable_weekend} = 1;                    
                }
                elsif ($mediastatus eq "nicht entleihbar"){
                    $overall_mediastatus_ref->{presence} = 1;
#                    $overall_mediastatus_ref->{presence_immediate} = 1;                    
                }
                elsif ($mediastatus eq "entliehen"){
                    $overall_mediastatus_ref->{lent} = 1;
#                    $overall_mediastatus_ref->{presence_immediate} = 1;                    
                }
            }
            
	    if ($used01buchstandort){
		if ($standort{$buchsatz_ref->[3]}){
		    $standort .= " / ".$standort{$buchsatz_ref->[3]};
		}
	    }
	    else {
		if ($abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]}){
		    $standort .= " / ".$abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]};
		}
	    }
            chomp($standort);
	  
            my $holding_ref = {
                'id'     => $holdingid,
                'fields' => {
                  '0004' =>
                    [
                        {
                            mult     => 1,
                            subfield => '',
                            content  => $katkey,
                        },
                    ],
                },
            };
          
            if ($mediennr) {
                push @{$holding_ref->{fields}{'0010'}}, {
                    content  => $mediennr,
                    mult     => 1,
                    subfield => '',
                };
            }

            if ($signatur) {
                push @{$holding_ref->{fields}{'0014'}}, {
                    content  => $signatur,
                    mult     => 1,
                    subfield => '',
                };
            }

            if ($signatur2) {
                push @{$holding_ref->{fields}{'0107'}}, { # Zweite Signatur laut MAB2 Lokaldaten
                    content  => $signatur2,
                    mult     => 1,
                    subfield => '',
                };
            }
	    
            if ($standort) {
                push @{$holding_ref->{fields}{'0016'}}, {
                    content  => $standort,
                    mult     => 1,
                    subfield => '',
                };
            }
            
	    eval {
		print MEXSIKJSON encode_json $holding_ref, "\n";
	    };

	    if ($@){
		print STDERR $@, "\n";
	    }
        }

        if ($usestatus){
            my $mult = 1;
            foreach my $thisstatus (keys %{$overall_mediastatus_ref}){
                push @{$title_ref->{fields}{'4400'}}, {
                    mult       => $mult++,
                    subfield   => '',
                    content    => $thisstatus,
                };                
            }
        }
    }

    # Exemplardaten abarbeiten Ende

    eval {
        print TITSIKJSON encode_json $title_ref, "\n";
    };
    
    if ($@){
        print STDERR $@,"\n";
    }
    
    %inventarbuf     = ();
    %signaturbuf     = ();
    %standortbuf     = ();
    %besbibbuf       = ();
    %erschverlbufpos = ();
    %erschverlbufneg = ();
    %bemerkbuf1      = ();
    %bemerkbuf2      = ();
    undef $maxmex;

}                               # Ende einzelner Satz in while

close(TITSIKJSON);
close(TITEL);
#close(MEXSIK);
close(MEXSIKJSON);

sub get_mediastatus {
    my ($buchsatz_ref) = @_;

    my $statusstring   = "";
    my $entl   = $buchsatz_ref->[4];
    my $status = $buchsatz_ref->[5];
    my $skond  = $buchsatz_ref->[6];

    if    ($entl_map_ref->{$entl} == 0){
        $statusstring="nicht entleihbar";
    }
    elsif ($entl_map_ref->{$entl} == 1){
    	if ($status eq "0"){
            $statusstring="bestellbar";
        }
        elsif ($status eq "2"){
            $statusstring="entliehen"; # Sonderwunsch. Eigentlich: bestellt
        }
        elsif ($status eq "4"){
            $statusstring="entliehen";
        }
        else {
            $statusstring="unbekannt";
        }
    }
    elsif ($entl_map_ref->{$entl} == 2){
      $statusstring="nur in Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 3){
      $statusstring="nur in bes. Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 4){
      $statusstring="nur Wochenende";
    }
    else {
      $statusstring="unbekannt";
    }

    # Sonderkonditionen

    if ($skond eq "16"){
      $statusstring="verloren";
    }
    elsif ($skond eq "32"){
      $statusstring="vermi&szlig;t";
    }

    return $statusstring;
}

sub konv {
    my ($content)=@_;

    if ($blobencoding eq "utf8"){
        $content=decode_utf8($content);
    }
    else {
        $content=decode($blobencoding, $content);
    }
    
    $content=~s/\&amp;/&/g;     # zuerst etwaige &amp; auf & normieren 
    $content=~s/\&/&amp;/g;     # dann erst kann umgewandet werden (sonst &amp;amp;) 
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    $content=~s/¯e/\x{113}/g;   # Kl. e mit Ueberstrich/Macron
    $content=~s/µe/\x{115}/g;   # Kl. e mit Hacek/Breve
    $content=~s/·e/\x{11b}/g;   # Kl. e mit Caron
    $content=~s/±e/\x{117}/g;   # Kl. e mit Punkt
    $content=~s/ªd/ð/g;         # Kl. Islaend. e Eth (durchgestrichenes D)

    $content=~s/¯E/\x{112}/g;   # Gr. E mit Ueberstrich/Macron
    $content=~s/µE/\x{114}/g;   # Gr. E mit Hacek/Breve
    $content=~s/·E/\x{11a}/g;   # Gr. E mit Caron
    $content=~s/±E/\x{116}/g;   # Gr. E mit Punkt
    $content=~s/ªD/Ð/g;         # Gr. Islaend. E Eth (durchgestrichenes D)

    $content=~s/¯a/\x{101}/g;   # Kl. a mit Ueberstrich/Macron
    $content=~s/µa/\x{103}/g;   # Kl. a mit Hacek/Breve

    $content=~s/¯A/\x{100}/g;   # Gr. A mit Ueberstrich/Macron
    $content=~s/µA/\x{102}/g;   # Gr. A mit Hacek/Breve

    $content=~s/¯o/\x{14d}/g;   # Kl. o mit Ueberstrich/Macron
    $content=~s/µo/\x{14f}/g;   # Kl. o mit Hacek/Breve
    $content=~s/¶o/\x{151}/g;   # Kl. o mit Doppel-Acute

    $content=~s/¯O/\x{14c}/g;   # Gr. O mit Ueberstrich/Macron
    $content=~s/µO/\x{14e}/g;   # Gr. O mit Hacek/Breve
    $content=~s/¶O/\x{150}/g;   # Gr. O mit Doppel-Acute

    #     $content=~s//\x{131}/g; # Kl. punktloses i
    $content=~s/¯i/\x{12b}/g;   # Kl. i mit Ueberstrich/Macron
    $content=~s/µi/\x{12d}/g;   # Kl. i mit Hacek/Breve

    $content=~s/±I/\x{130}/g;   # Gr. I mit Punkt
    $content=~s/¯I/\x{12a}/g;   # Gr. i mit Ueberstrich/Macron
    $content=~s/µI/\x{12c}/g;   # Gr. i mit Hacek/Breve


    #     $content=~s//\x{168}/g; # Gr. U mit Tilde
    $content=~s/¯U/\x{16a}/g;   # Gr. U mit Ueberstrich/Macron
    $content=~s/µU/\x{16c}/g;   # Gr. U mit Hacek/Breve
    $content=~s/¶U/\x{170}/g;   # Gr. U mit Doppel-Acute
    $content=~s/¹U/\x{16e}/g;   # Gr. U mit Ring oben

    #     $content=~s//\x{169}/g; # Kl. u mit Tilde
    $content=~s/¯u/\x{16b}/g;   # Kl. u mit Ueberstrich/Macron
    $content=~s/µu/\x{16d}/g;   # Kl. u mit Hacek/Breve
    $content=~s/¶u/\x{171}/g;   # Kl. u mit Doppel-Acute
    $content=~s/¹u/\x{16f}/g;   # Kl. u mit Ring oben
    
    $content=~s/´n/\x{144}/g;   # Kl. n mit Acute
    $content=~s/½n/\x{146}/g;   # Kl. n mit Cedille
    $content=~s/·n/\x{148}/g;   # Kl. n mit Caron

    $content=~s/´N/\x{143}/g;   # Gr. N mit Acute
    $content=~s/½N/\x{145}/g;   # Gr. N mit Cedille
    $content=~s/·N/\x{147}/g;   # Gr. N mit Caron

    $content=~s/´r/\x{155}/g;   # Kl. r mit Acute
    $content=~s/½r/\x{157}/g;   # Kl. r mit Cedille
    $content=~s/·r/\x{159}/g;   # Kl. r mit Caron

    $content=~s/´R/\x{154}/g;   # Gr. R mit Acute
    $content=~s/½R/\x{156}/g;   # Gr. R mit Cedille
    $content=~s/·R/\x{158}/g;   # Gr. R mit Caron

    $content=~s/´s/\x{15b}/g;   # Kl. s mit Acute
    #     $content=~s//\x{15d}/g; # Kl. s mit Circumflexe
    $content=~s/½s/\x{15f}/g;   # Kl. s mit Cedille
    $content=~s/·s/š/g;         # Kl. s mit Caron

    $content=~s/´S/\x{15a}/g;   # Gr. S mit Acute
    #     $content=~s//\x{15c}/g; # Gr. S mit Circumflexe
    $content=~s/½S/\x{15e}/g;   # Gr. S mit Cedille
    $content=~s/·S/Š/g;         # Gr. S mit Caron

    $content=~s/ªt/\x{167}/g;   # Kl. t mit Mittelstrich
    $content=~s/½t/\x{163}/g;   # Kl. t mit Cedille
    $content=~s/·t/\x{165}/g;   # Kl. t mit Caron

    $content=~s/ªT/\x{166}/g;   # Gr. T mit Mittelstrich
    $content=~s/½T/\x{162}/g;   # Gr. T mit Cedille
    $content=~s/·T/\x{164}/g;   # Gr. T mit Caron

    $content=~s/´z/\x{17a}/g;   # Kl. z mit Acute
    $content=~s/±z/\x{17c}/g;   # Kl. z mit Punkt oben
    $content=~s/·z/ž/g;         # Kl. z mit Caron

    $content=~s/´Z/\x{179}/g;   # Gr. Z mit Acute
    $content=~s/±Z/\x{17b}/g;   # Gr. Z mit Punkt oben
    $content=~s/·Z/Ž/g;         # Gr. Z mit Caron

    $content=~s/´c/\x{107}/g;   # Kl. c mit Acute
    #     $content=~s//\x{108}/g; # Kl. c mit Circumflexe
    $content=~s/±c/\x{10b}/g;   # Kl. c mit Punkt oben
    $content=~s/·c/\x{10d}/g;   # Kl. c mit Caron
    
    $content=~s/´C/\x{106}/g;   # Gr. C mit Acute
    #     $content=~s//\x{108}/g; # Gr. C mit Circumflexe
    $content=~s/±C/\x{10a}/g;   # Gr. C mit Punkt oben
    $content=~s/·C/\x{10c}/g;   # Gr. C mit Caron

    $content=~s/·d/\x{10f}/g;   # Kl. d mit Caron
    $content=~s/·D/\x{10e}/g;   # Gr. D mit Caron

    $content=~s/½g/\x{123}/g;   # Kl. g mit Cedille
    $content=~s/·g/\x{11f}/g;   # Kl. g mit Breve
    $content=~s/µg/\x{11d}/g;   # Kl. g mit Circumflexe
    $content=~s/±g/\x{121}/g;   # Kl. g mit Punkt oben

    $content=~s/½G/\u0122/g;    # Gr. G mit Cedille
    $content=~s/·G/\x{11e}/g;   # Gr. G mit Breve
    $content=~s/µG/\x{11c}/g;   # Gr. G mit Circumflexe
    $content=~s/±G/\x{120}/g;   # Gr. G mit Punkt oben
        
    $content=~s/ªh/\x{127}/g;   # Kl. h mit Ueberstrich
    $content=~s/¾h/\x{e1}\x{b8}\x{a5}/g; # Kl. h mit Punkt unten
    $content=~s/ªH/\x{126}/g;   # Gr. H mit Ueberstrich
    $content=~s/¾H/\x{e1}\x{b8}\x{a4}/g; # Gr. H mit Punkt unten

    $content=~s/½k/\x{137}/g;   # Kl. k mit Cedille
    $content=~s/½K/\x{136}/g;   # Gr. K mit Cedille

    $content=~s/½l/\x{13c}/g;   # Kl. l mit Cedille
    $content=~s/´l/\x{13a}/g;   # Kl. l mit Acute
    #     $content=~s//\x{13e}/g; # Kl. l mit Caron
    $content=~s/·l/\x{140}/g;   # Kl. l mit Punkt mittig
    $content=~s/ºl/\x{142}/g;   # Kl. l mit Querstrich

    $content=~s/½L/\x{13b}/g;   # Gr. L mit Cedille
    $content=~s/´L/\x{139}/g;   # Gr. L mit Acute
    #     $content=~s//\x{13d}/g; # Gr. L mit Caron
    $content=~s/·L/\x{13f}/g;   # Gr. L mit Punkt mittig
    $content=~s/ºL/\x{141}/g;   # Gr. L mit Querstrick

    $content=~s/¾z/\x{e1}\x{ba}\x{93}/g; # Kl. z mit Punkt unten
    $content=~s/¾Z/\x{e1}\x{ba}\x{92}/g; # Gr. z mit Punkt unten

    #     $content=~s//\x{160}/g;   # S hacek
    #     $content=~s//\x{161}/g;   # s hacek
    #     $content=~s//\x{17d}/g;   # Z hacek
    #     $content=~s//\x{17e}/g;   # z hacek
    #     $content=~s//\x{178}/g;   # Y Umlaut

    return $content;
}

sub decode_blob {
    my ($type,$BLOB,$subfield_ref) = @_;

    my %record = ();
    my $j = length($BLOB);
    my $outBLOB = pack "H$j", $BLOB;
    $j /= 2;
    my $i = 0;
    while ( $i < $j ) {
        my $idup = $i*2;
        my $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
        my $kateg = $fstab_ref->{$type}[$fnr]{field};
        my $len = hex(substr($BLOB,$idup+4,4));
        if ( $len < 1000 ) {
            # nicht multiples Feld
            my $KAT = sprintf "%04d", $kateg;

            my $inh = substr($outBLOB,$i+4,$len);

            if (defined $subfield_ref->{$KAT} && defined $subfield_ref->{$KAT}{substr($inh,0,1)} ) {
                $inh = "(" . substr($inh,0,1) . ")" . substr($inh,1);
            }
            else {
                if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                    $inh = hex(substr($BLOB,$idup+8,8));
                    $inh="IDN: $inh";
                }
            }
            
            if ( substr($inh,0,1) eq " " ){
                $inh =~ s/^ //;
            }

            # Schmutzzeichen weg
            $inh=~s/ //g;
            
            
            if ($inh ne "") {
                $record{$KAT} = $inh;
            }

            $i = $i + 4 + $len;
        }
        else {
            # multiples Feld
            my $mlen = 65536 - $len;
            my $k = $i + 4;
            my $ukat = 1;
            while ( $k < $i + 4 + $mlen ) {
                my $kdup = $k*2;
                my $ulen = hex(substr($BLOB,$kdup,4));
                if ( $ulen > 0 ) {
                    my $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
                    my $inh  = substr($outBLOB,$k+2,$ulen);
                    
                    $kateg   = sprintf "%04d", $kateg;
                    
                    if (defined $subfield_ref->{$kateg} && defined $subfield_ref->{$kateg}{substr($inh,0,1)} ) {
                        $inh = "(" . substr($inh,0,1) . ")" . substr($inh,1);
                    }
                    else {
                        if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                            my $verwnr = hex(substr($BLOB,$kdup+4,8));
                            my $zusatz="";
                            if ($ulen > 4) {
                                $zusatz=substr($inh,4,$ulen);
                                $inh="IDN: $verwnr ;$zusatz";
                            }
                            else {
                                $inh="IDN: $verwnr";
                            }
                        }
                    }

                    if ( substr($inh,0,1) eq " " ){
                        $inh =~ s/^ //;
                    }

                    $inh=~s/ //g;
                    
                    if ($inh ne "") {
                        $record{$uKAT} = $inh;
                    }
                    
                }
                $ukat++;
                $k = $k + 2 + $ulen;
            }

            $i = $i + 4 + $mlen;
        }
    }

    return %record;
}

sub read_fstab {

    my $fstab_map_ref = {
        1 => 'title',
        2 => 'person',
        3 => 'corporatebody',
        4 => 'subject',
        5 => 'classification',
    };

    my $fstab_ref = {};

    my $subfield_ref = {};
    
    open(FSTAB,"cat $bcppath/sik_fstab.bcp |");
    while (<FSTAB>) {
        my ($setnr,$fnr,$name,$kateg,$muss,$fldtyp,$mult,$invert,$stop,$zusatz,$multgr,$refnr,$vorbnr,$pruef,$knuepf,$trenn,$normueber,$bewahrenjn,$pool_cop,$indikator,$ind_bezeicher,$ind_indikator,$sysnr,$vocnr)=split("",$_);
        
        if ($setnr >= 1 && $setnr <= 5){
            if ($indikator){

                my $field = sprintf "%04d", $kateg;
                $subfield_ref->{$fstab_map_ref->{$setnr}}{$field}{$ind_indikator} = 1;
            }

            $fstab_ref->{$fstab_map_ref->{$setnr}}[$fnr] = {
                field => $kateg,
                type  => $fldtyp,
                refnr => $refnr,
            };
        }
    }
    close(FSTAB);

    return ($fstab_ref,$subfield_ref);
}

sub transform_subfield {
    my ($type,$field,$subfield,$content) = @_;

    if ($field=~/^(\d\d\d\d)/) {
        if ($subfield_transform_ref->{$type}{"$1$subfield"}) {
            return $subfield_transform_ref->{$type}{"$1$subfield"};
        }
    }

    return;
}
