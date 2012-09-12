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
#  Copyright 2003-2012 Oliver Flimm
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
#use MLDBM qw(DB_File Storable);
use Storable ();

our ($bcppath,$used01buch,$usemcopynum,$blobencoding,$reducemem);

&GetOptions(
    "reduce-mem"      => \$reducemem,
    "bcp-path=s"      => \$bcppath,
    "blob-encoding=s" => \$blobencoding, # V<4.0: iso-8859-1, V>=4.0: utf8
    "use-d01buch"     => \$used01buch,
    "use-mcopynum"    => \$usemcopynum,
);

# Konfiguration:

# Wo liegen die bcp-Dateien

$bcppath=($bcppath)?$bcppath:"/tmp";
$blobencoding=($blobencoding)?$blobencoding:"utf8";

# Problematische Kategorien in den Titeln:
#
# - 0220.001 Entspricht der Verweisform, die eigentlich zu den
#            Koerperschaften gehoert.
#

my $indicator_tab = {
    person => {
        '0806a' => '0200',      # Lebensjahre
        '0806i' => '0201',      # Beruf
        '0806c' => '0305',      # Geburtsort
    },
};

###
## Feldstrukturtabelle auswerten
#

our $fstab_ref = read_fstab();

my %zweigstelle  = ();
my %abteilung    = ();
my %buchdaten    = ();
my %titelbuchkey = ();

if ($reducemem) {
#    tie %buchdaten,        'MLDBM', "./buchdaten.db"
#        or die "Could not tie buchdaten.\n";

#    tie %titelbuchkey,     'MLDBM', "./titelbuchkey.db"
#        or die "Could not tie titelbuchkey.\n";
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
binmode(PERSIKJSON, ":utf8");

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<PER>)) {
    next if ($aktion);

    my %record  = decode_blob('person',$daten);

#    printf PERSIK "0000:%0d\n", $katkey;

    my $person_ref = {
        id => $katkey,
    };

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;

        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = $record{$key};
        my $thiskey = $key;
        my $newkey  = have_indicator('person',$key,$content);
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

        push @{$person_ref->{$field}}, {
            mult      => $mult,
            subfield  => '',
            content   => $content,
        };

    }
    
    print PERSIKJSON encode_json $person_ref, "\n";
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
binmode(KOESIKJSON, ":utf8");

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<KOE>)) {
    next if ($aktion);

    my %record  = decode_blob('corporatebody',$daten);

#    printf KOESIK "0000:%0d\n", $katkey;

    my $corporatebody_ref = {
        id => $katkey,
    };

    foreach my $key (sort {$b cmp $a} keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

#        print KOESIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$corporatebody_ref->{$field}}, {
            mult      => $mult,
            subfield  => '',
            content   => $content,
        };

    }

    print KOESIKJSON encode_json $corporatebody_ref, "\n";

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
binmode(SYSSIKJSON, ":utf8");

while (my ($katkey,$aktion,$reserv,$ansetzung,$daten) = split ("",<SYS>)) {
    next if ($aktion);

    my %record  = decode_blob('classification',$daten);
        
#    printf SYSSIK "0000:%0d\n", $katkey;

    my $classification_ref = {
        id => $katkey,
    };

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

#        print SYSSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$classification_ref->{$field}}, {
            mult      => $mult,
            subfield  => '',
            content   => $content,
        };

    }

    print SYSSIKJSON encode_json $classification_ref, "\n";

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
binmode(SWDSIKJSON, ":utf8");

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<SWD>)) {
    next if ($aktion);

    my %record  = decode_blob('subject',$daten);
    
#    printf SWDSIK "0000:%0d\n", $katkey;

    my $subject_ref = {
        id => $katkey,
    };

    # Schlagwortkettensonderbehandlung SIKIS
    # Nicht im JSON-Format!!!
    
    my @swtkette=();
    foreach my $key (sort {$b cmp $a} keys %record) {
        if ($key =~/^0800/) {
            $record{$key}=~s/^[a-z]([\p{Lu}0-9¬])/$1/; # Indikator herausfiltern
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
        
        my $content  = $record{$key};
        my $subfield = "";
        # etwaige Indikatoren bestimmen        
        if ($content=~m/^([a-z])([\p{Lu}0-9¬].+?)$/) {
            $subfield = $1;
            $content  = $2;
        }

        $content  = konv($content);

#        print SWDSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/ && $key !~/^0800/);
    
        push @{$subject_ref->{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
    }

    print SWDSIKJSON encode_json $subject_ref, "\n";
    
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
    
    ###
    ## Abteilungen auswerten
    #
    
    open(ABT,"cat $bcppath/d60abteil.bcp |");
    while (<ABT>) {
        my ($zwnr,$abtnr,$abtname)=split("",$_);
        $abteilung{$zwnr}{$abtnr}=$abtname;
    }
    close(ABT);

    ###
    ## Titel-Buch-Key auswerten
    #

    if ($usemcopynum) {
        print STDERR  "Usinb mcopynum\n";
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
            my ($d01gsi,$d01ex,$d01zweig,$d01mcopynum,$d01ort,$d01abtlg)=@line[0,1,2,7,24,31];
            #print "$d01gsi,$d01ex,$d01zweig,$d01mcopynum,$d01ort,$d01abtlg\n";
            foreach my $katkey (@{$titelbuchkey{$d01mcopynum}}) {
                push @{$buchdaten{$katkey}}, [$d01zweig,$d01ort,$d01abtlg];
            }
        } else {
            my ($d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg)=@line[0,1,2,7,24,31];
            #print "$d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg\n";
            push @{$buchdaten{$d01katkey}}, [$d01zweig,$d01ort,$d01abtlg];
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
#open(TITSIK,"| gzip >./unload.TIT.gz");
#open(MEXSIK,"| gzip >./unload.MEX.gz");
open(TITSIKJSON,"| gzip >./meta.title.gz");
open(MEXSIKJSON,"| gzip >./meta.holding.gz");
#binmode(TITSIK, ":utf8");
#binmode(MEXSIK, ":utf8");
binmode(TITSIKJSON, ":utf8");
binmode(MEXSIKJSON, ":utf8");

my $mexid           = 1;

while (my ($katkey,$aktion,$fcopy,$reserv,$vsias,$vsiera,$vopac,$daten) = split ("",<TITEL>)) {
    next if ($aktion);
    next if ($titelexclude{"$katkey"} eq "excluded");

    my %record  = decode_blob('title',$daten);
        
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
        id => $katkey,
    };

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }

        if ($key !~/^0000/) {
            my $content  = konv($record{$key});

            my $line = $key.":".$content."\n";
#            print TITSIK $line if ($record{$key} !~ /idn:/);

            # Verknuepfungskategorien?
            if ($content =~m/^IDN: (\S+)/) {
                my $id = $1;
                my $supplement = "";
                if ($content =~m/^IDN: \S+ ; (.+)/) {
                    $supplement = $1;
                }

                push @{$title_ref->{$field}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $id,
                    supplement => $supplement,
                };
            }
            else {

                push @{$title_ref->{$field}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $content,
                };
                
                if ($used01buch) {
                    # Anfang: Exemplardaten fuer Zeitschriften ZDB-Aufnahme
                    
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
                    
                    if ($line=~/^0012\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $besbibbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung
                        }
                    }
                }
                # Ende: Exemplardaten fuer Zeitschriften ZDB-Aufnahme
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
                    
                    # Zeitschriftensignaturen USB Koeln
                    
                    if ($line=~/^1203\.(\d\d\d):(.*$)/) {
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
        #      print STDERR "$katkey - $maxmex\n";
        my $k=1;
        while ($k <= $maxmex) {	  
            my $multkey=sprintf "%03d",$k;
            
            my $signatur=$signaturbuf{$multkey};
            my $standort=$standortbuf{$multkey};
            my $inventar=$inventarbuf{$multkey};
            my $bemerk1=$bemerkbuf1{$multkey};
            my $bemerk2=$bemerkbuf2{$multkey};
            my $sigel=$besbibbuf{$multkey};
            $sigel=~s!^38/!!;
            
            if ($used01buch) {
                my $erschverl=$erschverlbufpos{$multkey};
                $erschverl.=" ".$erschverlbufneg{$multkey} if (exists $erschverlbufneg{$multkey});
#                print MEXSIK "0000:$mexid\n";
#                print MEXSIK "0004:$katkey\n";
#                print MEXSIK "0014:$signatur\n"  if ($signatur);
#                print MEXSIK "1200:$bemerk1\n" if ($bemerk1);
#                print MEXSIK "1203:$bemerk2\n" if ($bemerk2);
#                print MEXSIK "1204:$erschverl\n" if ($erschverl);
#                print MEXSIK "3330:$sigel\n"     if ($sigel);
#                print MEXSIK "9999:\n";
                
                my $holding_ref = {
                    'id'     => $mexid,
                    '0004'   => [
                        {
                            mult     => 1,
                            subfield => '',
                            content  => $katkey,
                        },
                    ],
                };
              
                if ($signatur) {
                    push @{$holding_ref->{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk1) {
                    push @{$holding_ref->{'1200'}}, {
                        content  => $bemerk1,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk2) {
                    push @{$holding_ref->{'1203'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

                print MEXSIKJSON encode_json $holding_ref, "\n";
            }
            else {
                my $erschverl=$erschverlbuf{$multkey};
#                print MEXSIK "0000:$mexid\n";
#                print MEXSIK "0004:$katkey\n";
#                print MEXSIK "0014:$signatur\n"  if ($signatur);
#                print MEXSIK "1204:$erschverl\n" if ($erschverl);
#                print MEXSIK "3330:$sigel\n"     if ($sigel);
#                print MEXSIK "9999:\n";

                my $holding_ref = {
                    id     => $mexid,
                    '0004' =>
                        [
                            {
                                mult     => 1,
                                subfield => '',
                                content  => $katkey,
                            },
                        ],
                };
              
                if ($signatur) {
                    push @{$holding_ref->{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

                print MEXSIKJSON encode_json $holding_ref, "\n";

            }
          
            $mexid++;
            $k++;
        }
    } elsif (exists $buchdaten{$katkey}) {
        #      print STDERR "D01BUCH $katkey";
        foreach my $buchsatz_ref (@{$buchdaten{$katkey}}) {
            #print join(" ; ",@{$buchsatz});
            my $signatur = $buchsatz_ref->[1];
            my $standort = $zweigstelle{$buchsatz_ref->[0]}." / ".$abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]};
            chomp($standort);
	  
#            print MEXSIK "0000:$mexid\n";
#            print MEXSIK "0004:$katkey\n";
#            print MEXSIK "0014:$signatur\n"  if ($signatur);
#            print MEXSIK "0016:$standort\n"  if ($standort);
#            print MEXSIK "9999:\n";

            my $holding_ref = {
                id     => $mexid,
                '0004' =>
                    [
                        {
                            mult     => 1,
                            subfield => '',
                            content  => $katkey,
                        },
                    ],
            };
          
            if ($signatur) {
                push @{$holding_ref->{'0014'}}, {
                    content  => $signatur,
                    mult     => 1,
                    subfield => '',
                };
            }
          
            if ($standort) {
                push @{$holding_ref->{'0016'}}, {
                    content  => $standort,
                    mult     => 1,
                    subfield => '',
                };
            }
              
            print MEXSIKJSON encode_json $holding_ref, "\n";

            $mexid++;
        }
    }

    # Exemplardaten abarbeiten Ende

#    print TITSIK "9999:\n\n";

    print TITSIKJSON encode_json $title_ref, "\n";
    

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

#close(TITSIK);
close(TITSIKJSON);
close(TITEL);
#close(MEXSIK);
close(MEXSIKJSON);

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
    my ($type,$BLOB) = @_;

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
            my $inh = substr($outBLOB,$i+4,$len);
            if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                $inh = hex(substr($BLOB,$idup+8,8));
                $inh="IDN: $inh";
            }
            if ( substr($inh,0,1) eq " " ) {
                $inh =~ s/^ //;
            }

            # Schmutzzeichen weg
            $inh=~s/ //g;

            my $KAT = sprintf "%04d", $kateg;

            if ($inh ne "") {
                $record{$KAT} = $inh;
            }

            $i = $i + 4 + $len;
        } else {
            # multiples Feld
            my $mlen = 65536 - $len;
            my $k = $i + 4;
            my $ukat = 1;
            while ( $k < $i + 4 + $mlen ) {
                my $kdup = $k*2;
                my $ulen = hex(substr($BLOB,$kdup,4));
                if ( $ulen > 0 ) {
                    my $inh = substr($outBLOB,$k+2,$ulen);
                    if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                        my $verwnr = hex(substr($BLOB,$kdup+4,8));
                        my $zusatz="";
                        if ($ulen > 4) {
                            $zusatz=substr($inh,4,$ulen);
                            $inh="IDN: $verwnr ;$zusatz";
                        } else {
                            $inh="IDN: $verwnr";
                        }
                    }
                    my $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
                    if ( substr($inh,0,1) eq " " ) {
                        $inh =~ s/^ //;
                    }

                    # Schmutzzeichen weg
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
    
    open(FSTAB,"cat $bcppath/sik_fstab.bcp |");
    while (<FSTAB>) {
        my ($setnr,$fnr,$name,$kateg,$muss,$fldtyp,$mult,$invert,$stop,$zusatz,$multgr,$refnr,$vorbnr,$pruef,$knuepf,$trenn,$normueber,$bewahrenjn,$pool_cop,$indikator,$ind_bezeicher,$ind_indikator,$sysnr,$vocnr)=split("",$_);
        
        if ($setnr >= 1 && $setnr <= 5){
            $fstab_ref->{$fstab_map_ref->{$setnr}}[$fnr] = {
                field => $kateg,
                type  => $fldtyp,
                refnr => $refnr,
            };
        }
    }
    close(FSTAB);

    return $fstab_ref;
}

sub have_indicator {
    my ($type,$category,$content) = @_;

    if ($category=~/^(\d\d\d\d)/) {
        my $indicator = substr($content,0,1);
        if ($indicator_tab->{$type}{"$1$indicator"}) {
            return $indicator_tab->{$type}{"$1$indicator"};
        }
    }

    return;
}

