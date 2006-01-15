#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2005 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;
use utf8;

my $dir=`pwd`;
chop $dir;

my $inverted_aut_ref={
    '0001' => 1, # Ansetzung
    '0102' => 1, # Verweisform
};

my $inverted_kor_ref={
    '0001' => 1, # Ansetzung
    '0102' => 1, # Verweisform
    '0103' => 1, # Abkuerzung der Verweisform
    '0110' => 1, # Abkuerzung der Ansetzung
    '0111' => 1, # Frueherer/Spaeterer Name
};

my $inverted_not_ref={
    '0001' => 1, # Ansetzung
    '0002' => 1, # Ansetzung
    '0102' => 1, # Stichwort
    '0103' => 1, # Verweisform
};

my $inverted_swt_ref={
    '0001' => 1, # Ansetzung
    '0102' => 1, # Verweisform
};

my $inverted_tit_ref={
    '0304' => 1, # EST
    '0310' => 1, # AST
    '0331' => 1, # HST
    '0335' => 1, # Zusatz zum HST
    '0341' => 1, # PSTVorlage
    '0370' => 1, # WST
    '0412' => 1, # Verlag
    '0750' => 1, # Abstract
    '0425' => 1, # Erschjahr
};

my $inverted_mex_ref={
    '0014' => 1, # Signatur
};

# In die initiale Volltextsuche werden neben den bereits definierten
# Normdateikategorien inverted_*_ref folgende weitere Kategorien aus dem
# Titelbereich einbezogen. So koennen z.B. bestimmte im Titelbereich
# angesiedelte Kategorien in den anderen Normdaten-Klassen verf, kor oder
# swt recherchierbar gemacht werden.

my $search_category_ref={

    verf => {
        '0413' => 1, # Drucker
    },

    kor => {
    },

    swt => {
    },
    
    hst => {
        '0304' => 1, # EST
        '0310' => 1, # AST
        '0331' => 1, # HST
        '0335' => 1, # Zusatz zum HST
        '0341' => 1, # PSTVorlage
        '0370' => 1, # WST
        '0412' => 1, # Verlag
        '0750' => 1, # Abstract
    },
    
    hststring => {
        '0331' => 1, # HSTString
    },

    isbn => {
        '0540' => 1, # ISBN
    },

    issn => {
        '0543' => 1, # ISSN
    },
    
    artinh => {
        '0800' => 1, # ArtInhalt
    },
    
    sign => {
        '0014' => 1, # Signatur
        '1203' => 1, # Zeitschriftensignatur
    },

    ejahr => {
        '0425' => 1, # Erschjahr
    },
};

my $stammdateien_ref = {
    aut => {
        type => "aut",
        infile  => "aut.exp",
        outfile => "aut.mysql",
        inverted_ref => $inverted_aut_ref,
    },
    
    kor => {
        infile  => "kor.exp",
        outfile => "kor.mysql",
        inverted_ref => $inverted_kor_ref,
    },
    
    swt => {
        infile  => "swt.exp",
        outfile => "swt.mysql",
        inverted_ref => $inverted_swt_ref,
    },
    
    notation => {
        infile  => "not.exp",
        outfile => "not.mysql",
        inverted_ref => $inverted_not_ref,
    },
};


foreach my $type (keys %{$stammdateien_ref}){
  print STDERR "Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}\n";

  open(IN , "<:utf8",$stammdateien_ref->{$type}{infile} )  || die "IN konnte nicht geoeffnet werden";
  open(OUT, ">:utf8",$stammdateien_ref->{$type}{outfile})  || die "OUT konnte nicht geoeffnet werden";

  my $id;
 CATLINE:
  while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
      $id=$1;
      next CATLINE;
    }
    elsif ($line=~m/^9999:/){
      next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*$)/){
      ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*$)/){
      ($category,$content)=($1,$2);
    }

    my $contentnorm   = "";
    my $contentnormft = "";
    if (exists $stammdateien_ref->{$type}{inverted_ref}->{$category}){
       $contentnorm   = grundform({
           category => $category,
           content  => $content,
       });
       $contentnormft = $contentnorm;

       push @{$stammdateien_ref->{$type}{data}{$id}}, $contentnormft;
   }

    if ($category && $content){
      print OUT "$id$category$indicator$content$contentnorm$contentnormft\n";
    }
  }
  close(OUT);
  close(IN);
}


#######################3

$stammdateien_ref->{mex} = {
    infile  => "mex.exp",
    outfile => "mex.mysql",
    inverted_ref => $inverted_mex_ref,
};

print STDERR "Bearbeite mex.exp\n";

open(IN ,          "<:utf8","mex.exp"         ) || die "IN konnte nicht geoeffnet werden";
open(OUT,          ">:utf8","mex.mysql"       ) || die "OUT konnte nicht geoeffnet werden";
open(OUTCONNECTION,">:utf8","connection.mysql") || die "OUTCONNECTION konnte nicht geoeffnet werden";

my $id;
CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
        $id=$1;
        next CATLINE;
    }
    elsif ($line=~m/^9999:/){
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*$)/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*$)/){
        ($category,$content)=($1,$2);
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";

    if ($category && $content){

        if (exists $stammdateien_ref->{mex}{inverted_ref}->{$category}){
            $contentnorm   = grundform({
                category => $category,
                content  => $content,
            });
	    $contentnormft = $contentnorm;

	    push @{$stammdateien_ref->{mex}{data}{$id}}, $contentnormft;
	}

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($sourceid)=$content=~m/^(\d+)/;
            my $sourcetype="tit";
            my $targettype="mex";
            my $targetid=$id;
            my $supplement="";
            my $category="";
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
    
        print OUT "$id$category$indicator$content$contentnorm$contentnormft\n";
    }
}

close(OUT);
close(IN);

$stammdateien_ref->{tit} = {
    infile  => "tit.exp",
    outfile => "tit.mysql",
    inverted_ref => $inverted_tit_ref,
};

print STDERR "Bearbeite tit.exp\n";

open(IN ,           "<:utf8","tit.exp"      ) || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","tit.mysql"    ) || die "OUT konnte nicht geoeffnet werden";
open(OUTSEARCH,     ">:utf8","search.mysql" ) || die "OUT konnte nicht geoeffnet werden";

my @verf      = ();
my @kor       = ();
my @swt       = ();
my @notation  = ();
my @hst       = ();
my @hststring = ();
my @sign      = ();
my @isbn      = ();
my @issn      = ();
my @artinh    = ();
my @ejahr     = ();
my @titverf   = ();
my @titkor    = ();
my @titswt    = ();

CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    my ($ejahr,$sign,$isbn,$issn,$artinh,$hststring);

    if ($line=~m/^0000:(\d+)$/){
        $id=$1;

        @verf      = ();
        @kor       = ();
        @swt       = ();
        @notation  = ();
        @hst       = ();
        @hststring = ();
        @sign      = ();
        @isbn      = ();
        @issn      = ();
        @artinh    = ();
        @ejahr     = ();
        @titverf   = ();
        @titkor    = ();
        @titswt    = ();
        
        next CATLINE;
    }
    elsif ($line=~m/^9999:/){

        my @temp=();
        foreach my $item (@verf){
            push @temp, join(" ",@{$stammdateien_ref->{aut}{data}{$item}});
        }
        push @temp, join(" ",@titverf);
        my $verf      = join(" ",@temp);

        @temp=();
        foreach my $item (@kor){
            push @temp, join(" ",@{$stammdateien_ref->{kor}{data}{$item}});
        }
        push @temp, join(" ",@titkor);
        my $kor      = join(" ",@temp);

        @temp=();
        foreach my $item (@swt){
            push @temp, join(" ",@{$stammdateien_ref->{swt}{data}{$item}});
        }
        push @temp, join(" ",@titswt);
        my $swt      = join(" ",@temp);

        @temp=();
        foreach my $item (@notation){
            push @temp, join(" ",@{$stammdateien_ref->{notation}{data}{$item}});
        }
        my $notation = join(" ",@temp);

        @temp=();
	push @temp, join(" ",@{$stammdateien_ref->{mex}{data}{$id}});
        my $mex = join(" ",@temp);
        
#        my $verf      = join(" ",@{$stammdateien_ref->{aut}{data}{$id}});
#        my $kor       = join(" ",@{$stammdateien_ref->{kor}{data}{$id}});
#        my $swt       = join(" ",@{$stammdateien_ref->{swt}{data}{$id}});
#        my $notation  = join(" ",@{$stammdateien_ref->{notation}{data}{$id}});
        my $hst       = join(" ",@hst);
        my $hststring = join(" ",@hststring);
        my $isbn      = join(" ",@isbn);
        my $issn      = join(" ",@issn);
        my $artinh    = join(" ",@artinh);
        my $ejahr     = join(" ",@ejahr);
        
        print OUTSEARCH "NULL$id$verf$hst$kor$swt$notation$mex$ejahr$isbn$issn$artinh$hststring\n";

        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*$)/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*$)/){
        ($category,$content)=($1,$2);
    }
    
    if ($category && $content){
        
        my $contentnorm   = "";
        my $contentnormft = "";

        if (exists $stammdateien_ref->{tit}{inverted_ref}->{$category}){
            $contentnorm   = grundform({
                category => $category,
                content  => $content,
            });
            $contentnormft = $contentnorm;
        }

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($targetid)=$content=~m/^(\d+)/;
            my $targettype="tit";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="";
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0100/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="aut";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0100";

            push @verf, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0101/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="aut";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement=$1;
            }
            
            my $category="0101";

            push @verf, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0103/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="aut";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement=$1;
            }

            my $category="0103";

            push @verf, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0200/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="kor";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0200";

            push @kor, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0201/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="kor";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0201";

            push @kor, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0700/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="notation";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0700";

            push @notation, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0710/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0710";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0902/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0902";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0907/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0907";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0912/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0912";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0917/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0917";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0922/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0922";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0927/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0927";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0932/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0932";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0937/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0937";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0942/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0942";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0947/){
            my ($targetid)=$content=~m/^IDN: (\d+)/;
            my $targettype="swt";
            my $sourceid=$id;
            my $sourcetype="tit";
            my $supplement="";
            my $category="0947";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        # Titeldaten
        else {
            if (   exists $search_category_ref->{ejahr    }{$category}){
                push @ejahr, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{hst      }{$category}){
                push @hst, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{hststring}{$category}){
                push @hststring, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{isbn     }{$category}){
                push @isbn,      grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{issn     }{$category}){
                push @issn,      grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{artinh   }{$category}){
                push @artinh, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{verf     }{$category}){
                push @titverf, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{kor      }{$category}){
                push @titkor, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{swt      }{$category}){
                push @titswt, grundform({
                    category => $category,
                    content  => $content,
                });
            }
            
            print OUT "$id$category$indicator$content$contentnorm$contentnormft\n";
        }	
    }
}
close(OUT);
close(OUTCONNECTION);
close(OUTSEARCH);
close(IN);


#######################


open(CONTROL,">control.mysql");

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "DISABLEKEYS";
alter table $type disable keys;
DISABLEKEYS
}

print CONTROL "alter table connection disable keys;\n";
print CONTROL "alter table search     disable keys;\n";

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "ITEM";
load data infile '$dir/$stammdateien_ref->{$type}{outfile}' into table $type fields terminated by '' ;
ITEM
}

print CONTROL << "TITITEM";
load data infile '$dir/connection.mysql' into table connection fields terminated by '' ;
load data infile '$dir/search.mysql'     into table search     fields terminated by '' ;
TITITEM

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "ENABLEKEYS";
alter table $type enable keys;
ENABLEKEYS
}

print CONTROL "alter table connection enable keys;\n";
print CONTROL "alter table search     enable keys;\n";

close(CONTROL);


sub grundform {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $content  = exists $arg_ref->{content}
        ? $arg_ref->{content}             : "";

    my $category = exists $arg_ref->{category}
        ? $arg_ref->{category}            : "";


    # Sonderbehandlung verschiedener Kategorien

    # ISBN filtern
    if ($category eq "0540"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
    }

    # ISSN filtern
    if ($category eq "0543"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)/$1$2$3$4$5$6$7$8/g;
    }

    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;
    
    # Ausfiltern nicht akzeptierter Zeichen
    $content=~s/[^-+\p{Alphabetic}0-9\/: ']//g;
    
    # Zeichenersetzungen
    $content=~s/\"//g;
    $content=~s/'/ /g;
    $content=~s/\// /g;
    $content=~s/:/ /g;
    $content=~s/  / /g;

    # Buchstabenersetzungen
    $content=~s/ü/ue/g;
    $content=~s/ä/ae/g;
    $content=~s/ö/oe/g;
    $content=~s/Ü/Ue/g;
    $content=~s/Ö/Oe/g;
    $content=~s/Ü/Ae/g;
    $content=~s/ß/ss/g;

    $content=~s/é/e/g;
    $content=~s/è/e/g;
    $content=~s/ê/e/g;
    $content=~s/É/E/g;
    $content=~s/È/E/g;
    $content=~s/Ê/E/g;

    $content=~s/á/a/g;
    $content=~s/à/a/g;
    $content=~s/â/a/g;
    $content=~s/Á/A/g;
    $content=~s/À/A/g;
    $content=~s/Â/A/g;

    $content=~s/ó/o/g;
    $content=~s/ò/o/g;
    $content=~s/ô/o/g;
    $content=~s/Ó/O/g;
    $content=~s/Ò/o/g;
    $content=~s/Ô/o/g;

    $content=~s/í/i/g;
    $content=~s/ì/i/g;
    $content=~s/î/i/g;
    $content=~s/Í/I/g;
    $content=~s/Ì/I/g;
    $content=~s/Î/I/g;

    $content=~s/ø/o/g;
    $content=~s/Ø/o/g;
    $content=~s/ñ/n/g;
    $content=~s/Ñ/N/g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;

#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;

#    $line=~s/?/g;

#     $line=~s/该/g;
#     $line=~s/?/g;
#     $line=~s/?g;
#     $line=~s/?;
#     $line=~s/?e/g;
#     $line=~s//a/g;
#     $line=~s/?o/g;
#     $line=~s/?u/g;
#     $line=~s/鯥/g;
#     $line=~s/ɯE/g;
#     $line=~s/?/g;
#     $line=~s/oa/g;
#     $line=~s/?/g;
#     $line=~s/?I/g;
#     $line=~s/?g;
#     $line=~s/?O/g;
#     $line=~s/?;
#     $line=~s/?U/g;
#     $line=~s/ /y/g;
#     $line=~s/?Y/g;
#     $line=~s/毡e/g; # ae
#     $line=~s/?/g; # Hacek
#     $line=~s/?/g; # Macron / Oberstrich
#     $line=~s/?/g;
#     $line=~s/&gt;//g;
#     $line=~s/&lt;//g;
#     $line=~s/>//g;
#     $line=~s/<//g;

    return $content;
}

