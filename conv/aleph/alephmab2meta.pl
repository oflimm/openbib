#!/usr/bin/perl

#####################################################################
#
#  alephmab2meta.pl
#
#  Konvertierung von Aleph MAB2-Daten in das Meta-Format
#
#  Dieses File ist (C) 2007-2012 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use Data::Dumper;
use YAML::Syck;

use OpenBib::Conv::Common::Util;

my ($titlefile,$personfile,$corporatebodyfile,$subjectfile,$classificationfile,$holdingfile,$configfile);

&GetOptions(
	    "titlefile=s"          => \$titlefile,
            "personfile=s"         => \$personfile,
            "corporatebodyfile=s"  => \$corporatebodyfile,
            "subjectfile=s"        => \$subjectfile,
            "classificationfile=s" => \$classificationfile,
            "holdingfile=s"        => \$holdingfile,
            "configfile=s"         => \$configfile,
	    );

if (!$configfile){
    print << "HELP";
alephmab2meta.pl - Aufrufsyntax

    alephmab2meta.pl --titlefile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

print "Bearbeite Personen\n";

if (-e $personfile){
    open(PEROUT,'>:utf8','meta.person');
    
    tie @mab2perdata, 'Tie::MAB2::Recno', file => $personfile;
    
    foreach my $rawrec (@mab2perdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $convconfig->{person}{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{person}{$category}{mult}){
                $indicator="";
            }
            
            if (exists $convconfig->{person}{$category}{newcat}){
                $newcategory = $convconfig->{person}{$category}{newcat};
            }
            
            if ($newcategory && $convconfig->{person}{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print PEROUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print PEROUT "$newcategory:$content\n";
            }
        }
        print PEROUT "9999:\n\n";
    }
    
    close(PEROUT);
}
else {
    print STDERR "Keine Persoenendaten vorhanden\n";
}

######################################################################
# Koerperschafts-Daten

print "Bearbeite Koerperschaften\n";

if (-e $corporatebodyfile){
    open(KOROUT,'>:utf8','meta.corporatebody');
    
    tie @mab2kordata, 'Tie::MAB2::Recno', file => $corporatebodyfile;
    
    foreach my $rawrec (@mab2kordata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $convconfig->{corporatebody}{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{corporatebody}{$category}{mult}){
                $indicator="";
            }
            
            if (exists $convconfig->{corporatebody}{$category}{newcat}){
                $newcategory = $convconfig->{corporatebody}{$category}{newcat};
            }
            
            if ($newcategory && $convconfig->{corporatebody}{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print KOROUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print KOROUT "$newcategory:$content\n";
            }
        }
        print KOROUT "9999:\n\n";
    }
    
    close(KOROUT);
}
else {
    print "Keine Koerperschaftsdaten vorhanden\n";
}

######################################################################
# Schlagwort-Daten

print "Bearbeite Schlagworte\n";

if (-e $subjectfile){
    open(SWTOUT,'>:utf8','meta.subject');
    
    tie @mab2swtdata, 'Tie::MAB2::Recno', file => $subjectfile;
    
  SWTLOOP: foreach my $rawrec (@mab2swtdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $convconfig->{subject}{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #            $content = sprintf "%d", $content;
            #            next SWTLOOP if ($content > 10000000);
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{subject}{$category}{mult}){
                $indicator="";
            }
            
            if (exists $convconfig->{subject}{$category}{newcat}){
                $newcategory = $convconfig->{subject}{$category}{newcat};
            }
            
            if ($newcategory && $convconfig->{subject}{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print SWTOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print SWTOUT "$newcategory:$content\n";
            }
        }
        print SWTOUT "9999:\n\n";
    }
    
    close(SWTOUT);
}
else {
    print "Keine Schlagwortdaten vorhanden\n";
}


######################################################################
# Systematik-Daten

print "Bearbeite Systematik\n";

if (-e $classificationfile){
    open(NOTOUT,'>:utf8','meta.classification');

    tie @mab2notdata, 'Tie::MAB2::Recno', file => $classificationfile;
    
    foreach my $rawrec (@mab2notdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $convconfig->{classification}{$category}){
                next;
            }
            
            # Vorabfilterung
            #         if ($category =~ /^001$/){
            #             $content=~s/\D//g;
            #         }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{classification}{$category}{mult}){
                $indicator="";
            }
            
            if (exists $convconfig->{classification}{$category}{newcat}){
                $newcategory = $convconfig->{classification}{$category}{newcat};
            }
            
            if ($newcategory && $convconfig->{classification}{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print NOTOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print NOTOUT "$newcategory:$content\n";
            }
        }
        print NOTOUT "9999:\n\n";
    }
    
    close(NOTOUT);
}
else {
    print STDERR "Keine Systemaitkdaten vorhanden\n";
}

######################################################################
# Titel-Daten

print "Bearbeite Titel\n";

if (-e $titlefile){
    open(TITOUT,'>:utf8','meta.title');

    if (!$personfile && !$corporatebodyfile && !$subjectfile){
        open(PEROUT,'>:utf8','meta.person');
        open(KOROUT,'>:utf8','meta.corporatebody');
        open(SWTOUT,'>:utf8','meta.subject');
    }
    
    tie @mab2titdata, 'Tie::MAB2::Recno', file => $titlefile;
    
    foreach my $rawrec (@mab2titdata){
        my $rec = MAB2::Record::Base->new($rawrec);
#        print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            # print "$category - $indicator - $content\n";

            $category = $category.$indicator;
            
            my $newcategory = "";
            
            if (!exists $convconfig->{title}{$category}){
                next;
            }
            
            # Vorabfilterung
            
#             # Titel-ID sowie Ueberordnungs-ID
#             if ($category =~ /^001$/ || $category =~ /^010$/){
#                 $content=~s/\D//g;
#             }
            
            if ($category =~ /^002a$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }

            if ($category =~ /^020a$/ || $category =~ /^026 $/){
                $content=~s/[^-0-9]//g;
            }
            
            if ($category =~ /^542a$/){
                $content=~s/^\D+//;
            }

            if ($category =~ /^52[79]z$/  || $category =~ /^53[0123]z$/){
                $content=substr($content,20);
            }

            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{title}{$category}{mult}){
                $indicator="";
            }
            
            if (exists $convconfig->{title}{$category}{newcat}){
                $newcategory = $convconfig->{title}{$category}{newcat};
            }
            
            if (exists $convconfig->{title}{$category}{ref}){
                
                if ($category =~/^9[0123][27][kgs]/){
                    my $tmpcontent=$content;
                    ($content)=$tmpcontent=~m/(\d+-.)/;
                }
                #            print "REF: Category $category Content $content\n";
                #            my $tmpcontent=$content;
                #            ($content)=$tmpcontent=~m/^(\d+.*)/;
                $content="IDN: $content" if ($content);
            }
            elsif (exists $convconfig->{title}{$category}{type}){
                my $type = $convconfig->{title}{$category}{type};

                if ($type eq "person"){
                    my $autidn=OpenBib::Conv::Common::Util::get_autidn($content);
                    
                    if ($autidn > 0){
                        print PEROUT "0000:$autidn\n";
                        print PEROUT "0001:$content\n";
                        print PEROUT "9999:\n";
                        
                    }
                    else {
                        $autidn=(-1)*$autidn;
                    }

                    
                    $content = "IDN: $autidn";
                    
                }
                elsif ($type eq "corporatebody"){
                    my $koridn=OpenBib::Conv::Common::Util::get_koridn($content);
                    
                    if ($koridn > 0){
                        print KOROUT "0000:$koridn\n";
                        print KOROUT "0001:$content\n";
                        print KOROUT "9999:\n";
                        
                    }
                    else {
                        $koridn=(-1)*$koridn;
                    }
                    
                    
                    $content = "IDN: $koridn";
                }                        
                elsif ($type eq "subject"){
                    my $swtidn=OpenBib::Conv::Common::Util::get_swtidn($content);
                    
                    if ($swtidn > 0){
                        print KOROUT "0000:$swtidn\n";
                        print KOROUT "0001:$content\n";
                        print KOROUT "9999:\n";
                        
                    }
                    else {
                        $swtidn=(-1)*$swtidn;
                    }
                    
                    
                    $content = "IDN: $swtidn";
                }                                        
            }
            
            if ($newcategory && $convconfig->{title}{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print TITOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print TITOUT "$newcategory:$content\n";
            }
        }
        print TITOUT "9999:\n\n";
    }

    if (!$personfile && !$corporatebodyfile && !$subjectfile){
        close(PEROUT);
        close(KOROUT);
        close(SWTOUT);
    }
    
    close(TITOUT);
}
else {
    print "Keine Titeldaten vorhanden. EXIT!!!!\n";
    exit;
}

######################################################################
# Exemplar-Daten

print "Bearbeite Exemplare\n";

if (-e $holdingfile){
    open(MEXOUT,'>:utf8','meta.holding');

    tie @mab2mexdata, 'Tie::MAB2::Recno', file => $holdingfile;
    
    foreach my $rawrec (@mab2mexdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = $category_ref->[2];
            
            #        print "$category - $indicator - $content\n";
            
            $category = $category.$indicator;
            
            my %subfield=();        
            if (exists $convconfig->{holding}{$category}{subfields}){
                foreach my $item (split("",$content)){
                    if ($item=~/^(.)(.+)/){
                        $subfield{$1}=$2;
                    }
                }
            }
            
            my $newcategory = "";
            
            if (!exists $convconfig->{holding}{$category}){
                next;
            }
            
            # Vorabfilterung
            #         if ($category =~ /^001$/){
            #             $content=~s/\D//g;
            #         }
            
            
            if ($category =~ /^002 $/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            if ($category =~ /^071 $/){
                $content=~s/^38\///;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$convconfig->{holding}{$category}{mult}){
                $indicator="";
            }
            
            #        print YAML::Dump(\%subfield);
            
            if (exists $convconfig->{holding}{$category}{subfields}){
                foreach my $newcategory (keys %{$convconfig->{holding}{$category}{subfields}}){
                    my @newcontent=();
                    foreach my $thissubfield (@{$convconfig->{holding}{$category}{subfields}{$newcategory}}){
                        if ($subfield{$thissubfield}){
                            push @newcontent,$subfield{$thissubfield};
                        }
                    }
                    
                    $content=konv(join(" ",@newcontent));
                    
                    if ($newcategory && $convconfig->{holding}{$category}{mult} && $content){
                        my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                        print MEXOUT "$newcategory.$multcount:$content\n";
                    }
                    elsif ($newcategory && $content){
                        print MEXOUT "$newcategory:$content\n";
                    }
                }
            }
            else {
                $content=konv($content);
                if (exists $convconfig->{holding}{$category}{newcat}){
                    $newcategory = $convconfig->{holding}{$category}{newcat};
                }
                
                if ($newcategory && $convconfig->{holding}{$category}{mult} && $content){
                    my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                    print MEXOUT "$newcategory.$multcount:$content\n";
                }
                elsif ($newcategory && $content){
                    print MEXOUT "$newcategory:$content\n";
                }
            }
            
        }
        print MEXOUT "9999:\n\n";
    }

    close(MEXOUT);
}


sub konv {
  my ($line)=@_;

  $line=~s/\&/&amp;/g;
  $line=~s/>/&gt;/g;
  $line=~s/</&lt;/g;
  $line=~s/\x{0088}//g;
  $line=~s/\x{0089}//g;
  $line=~s/‡/ /g;
  $line=~s/^\|//;
  return $line;
}
