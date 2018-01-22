#!/usr/bin/perl

#####################################################################
#
#  mab2meta.pl
#
#  Konvertierung von MAB2-Daten in das Meta-Format
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
use JSON::XS;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use Data::Dumper;
use YAML::Syck;

use OpenBib::Conv::Common::Util;

my ($titlefile,$personfile,$corporatebodyfile,$subjectfile,$classificationfile,$holdingfile,$holding_in_title,$configfile);

&GetOptions(
	    "titlefile=s"          => \$titlefile,
            "personfile=s"         => \$personfile,
            "corporatebodyfile=s"  => \$corporatebodyfile,
            "subjectfile=s"        => \$subjectfile,
            "classificationfile=s" => \$classificationfile,
            "holdingfile=s"        => \$holdingfile,
            "holding-in-title"     => \$holding_in_title,
            "configfile=s"         => \$configfile,
	    );

if (!$configfile){
    print << "HELP";
mab2meta.pl - Aufrufsyntax

    mab2meta.pl --titlefile=xxx --holdingfile=yyy --configfile=config.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

print "Bearbeite Personen\n";

if (-e $personfile){
    open(PEROUT,'>:raw','meta.person');
    
    tie @mab2perdata, 'Tie::MAB2::Recno', file => $personfile;
    
    foreach my $rawrec (@mab2perdata){
        my $item_ref = {
            'fields' => {},
        };
        
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
                $indicator=1;
            }

            if (exists $convconfig->{person}{$category}{newcat}){
                $newcategory = $convconfig->{person}{$category}{newcat};
            }

            if ($newcategory eq "id" && $content){
                $item_ref->{id} = $content;
                next;
            }

            if ($newcategory && $convconfig->{person}{$category}{mult} && $content){
                my $multcount=++$multcount_ref->{$newcategory};
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => $multcount,
                    content  => $content,
                    subfield => '',
                };
            }
            elsif ($newcategory && $content){
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => 1,
                    content  => $content,
                    subfield => '',
                };
            }
        }
        print PEROUT encode_json $item_ref, "\n";
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
    open(KOROUT,'>:raw','meta.corporatebody');
    
    tie @mab2kordata, 'Tie::MAB2::Recno', file => $corporatebodyfile;
    
    foreach my $rawrec (@mab2kordata){
        my $item_ref = {
            'fields' => {},
        };

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

            if ($newcategory eq "id" && $content){
                $item_ref->{id} = $content;
                next;
            }
            
            if ($newcategory && $convconfig->{corporatebody}{$category}{mult} && $content){
                my $multcount=++$multcount_ref->{$newcategory};
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => $multcount,
                    content  => $content,
                    subfield => '',
                };
            }
            elsif ($newcategory && $content){
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => 1,
                    content  => $content,
                    subfield => '',
                };
            }
        }
        print KOROUT encode_json $item_ref, "\n";
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
    open(SWTOUT,'>:raw','meta.subject');
    
    tie @mab2swtdata, 'Tie::MAB2::Recno', file => $subjectfile;
    
  SWTLOOP: foreach my $rawrec (@mab2swtdata){
        my $item_ref = {
            'fields' => {},
        };

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

            if ($newcategory eq "id" && $content){
                $item_ref->{id} = $content;
                next;
            }
            
            if ($newcategory && $convconfig->{subject}{$category}{mult} && $content){
                my $multcount=++$multcount_ref->{$newcategory};
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => $multcount,
                    content  => $content,
                    subfield => '',
                };
            }
            elsif ($newcategory && $content){
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => 1,
                    content  => $content,
                    subfield => '',
                };
            }
        }
        print SWTOUT encode_json $item_ref, "\n";
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
    open(NOTOUT,'>:raw','meta.classification');

    tie @mab2notdata, 'Tie::MAB2::Recno', file => $classificationfile;
    
    foreach my $rawrec (@mab2notdata){
        my $item_ref = {
            'fields' => {},
        };
                
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

            if ($newcategory eq "id" && $content){
                $item_ref->{id} = $content;
                next;
            }
            
            if ($newcategory && $convconfig->{classification}{$category}{mult} && $content){
                my $multcount=++$multcount_ref->{$newcategory};
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => $multcount,
                    content  => $content,
                    subfield => '',
                };
            }
            elsif ($newcategory && $content){
                push @{$item_ref->{fields}{$newcategory}},{
                    mult     => 1,
                    content  => $content,
                    subfield => '',
                };
            }
        }
        print NOTOUT encode_json $item_ref, "\n";
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
    open(TITOUT,'>:raw','meta.title');

    if (!$personfile){
        open(PEROUT,'>:raw','meta.person');
    }
    if (!$corporatebodyfile){
        open(KOROUT,'>:raw','meta.corporatebody');
    }
    if (!$subjectfile){
        open(SWTOUT,'>:raw','meta.subject');
    }
    if (!$classificationfile){
        open(NOTOUT,'>:raw','meta.classification');
    }
    if (!$holdingfile){
        open(MEXOUT,'>:raw','meta.holding');
    }
    
    tie @mab2titdata, 'Tie::MAB2::Recno', file => $titlefile;
    
    foreach my $rawrec (@mab2titdata){
        my $title_ref = {
            'fields' => {},
        };

        my $rec = MAB2::Record::Base->new($rawrec);
        print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = $category_ref->[2];
            
            print "$category - $indicator - $content\n";

            $category = $category.$indicator;

            my $newcategory = "";
            
            if (!exists $convconfig->{title}{$category}){
		print "Ignoring category $category with content $content\n";
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
                $content=~s/[^-0-9xX]//g;
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

            if ($newcategory eq "id" && $content){
                $title_ref->{id} = $content;
                next;
            }

            # 1) Verweise
            if (exists $convconfig->{title}{$category}{ref}){
                
                if ($category =~/^9[0123][27][kgs]/){
                    my $tmpcontent=$content;
                    ($content)=$tmpcontent=~m/(\d+-.)/;
                }

                push @{$title_ref->{fields}{$newcategory}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $content,
                    supplement => '',
                } if ($content);

            }
            # 2) Inhalte, aus denen Verweise generiert werden
            elsif (exists $convconfig->{title}{$category}{type}){
                my $type = $convconfig->{title}{$category}{type};

		my $supplement = "";
		
                $content = konv($content);

                if ($type eq "person"){		    
		    if ($content =~m/.+\s+\[/){
			($content, $supplement)=$content=~m/^(.*?)\S+(\[.+?)$/;
		    }
		    
                    my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($content);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $person_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $content,
                        };
                        
                        print PEROUT encode_json $item_ref, "\n";
                    }

                    my $multcount=++$multcount_ref->{$newcategory};

                    push @{$title_ref->{fields}{$newcategory}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $person_id,
                        supplement => $supplement,
                    };
                }
                elsif ($type eq "corporatebody"){
                    my ($corporatebody_id,$new)=OpenBib::Conv::Common::Util::get_corporatebody_id($content);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $corporatebody_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => $multcount,
                            subfield => '',
                            content  => $content,
                        };
                        
                        print KOROUT encode_json $item_ref, "\n";
                    }

                    my $multcount=++$multcount_ref->{$newcategory};

                    push @{$title_ref->{fields}{$newcategory}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $corporatebody_id,
                        supplement => $supplement,
                    };
                }
                elsif ($type eq "subject"){
                    my ($subject_id,$new)=OpenBib::Conv::Common::Util::get_subject_id($content);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $subject_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $content,
                        };
                        print SWTOUT encode_json $item_ref, "\n";
                    }

                    my $multcount=++$multcount_ref->{$newcategory};

                    push @{$title_ref->{fields}{$newcategory}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                }
                elsif ($type eq "classification"){
                    my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($content);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $classification_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $content,
                        };

                        print NOTOUT encode_json $item_ref, "\n";
                    }

                    my $multcount=++$multcount_ref->{$newcategory};

                    push @{$title_ref->{fields}{$newcategory}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $classification_id,
                        supplement => '',
                    };
                }

                next;
            }
            # 4) Holdings im Titel mit Unterfeldern
            elsif ($holding_in_title && exists $convconfig->{holding}{$category}{subfield}){
                print STDERR "$content\n";
                
                my $holding_ref = {
                    'fields' => {},
                };

                foreach my $item (split("",$content)){
                    if ($item=~/^(.)(.+)/){
                        my $subfield = $1;
                        my $thiscontent  = $2;

			print "Handling subfield $subfield with content $thiscontent\n";
                        $thiscontent=konv($thiscontent) unless ($convconfig->{title}{$category}{no_conv});
                        if ($convconfig->{filter}{$category}{filter_generic}){
                            foreach my $filter (@{$convconfig->{filter}{$category}{filter_generic}}){
                                my $from = $filter->{from};
                                my $to   = $filter->{to};
                                $thiscontent =~s/$from/$to/g;
                            }
                        }
                        
                        if ($convconfig->{filter}{$category}{filter_junk}){
                            $thiscontent = filter_junk($thiscontent);
                        }
                        
                        if ($convconfig->{filter}{$category}{filter_newline2br}){
                            $thiscontent = filter_newline2br($thiscontent);
                        }
                        
                        if ($convconfig->{filter}{$category}{filter_match}){
                            $thiscontent = filter_match($thiscontent,$convconfig->{filter}{$category}{filter_match});
                        }

                        print STDERR "$category - $subfield - $thiscontent\n";
                        my $newcategory = $convconfig->{holding}{$category}{subfield}{$subfield};

                        if ($newcategory && $convconfig->{holding}{$category}{mult} && $content){
                            my $multcount=++$multcount_ref->{$newcategory};
                            push @{holding_ref->{fields}{$newcategory}},{
                                mult     => $multcount,
                                content  => $thiscontent,
                                subfield => $subfield,
                            };
                        }
                        elsif ($newcategory && $content){
                            push @{$holding_ref->{fields}{$newcategory}},{
                                mult     => 1,
                                content  => $thiscontent,
                                subfield => $subfield,
                            };
                        }
                    }
                }

                print MEXOUT encode_json $holding_ref, "\n";

            } 
            # Ansonsten normale Umwandlung
            else {

		if (exists $convconfig->{title}{$category}{subfield}){
		    
		    foreach my $item (split("",$content)){
			if ($item=~/^(.)(.+)/){
			    my $subfield = $1;
			    my $thiscontent  = $2;
			    
			    print "Handling subfield $subfield with content $thiscontent\n";
			    $thiscontent=konv($thiscontent) unless ($convconfig->{title}{$category}{no_conv});
			    
			    if ($convconfig->{filter}{$category}{filter_generic}){
				foreach my $filter (@{$convconfig->{filter}{$category}{filter_generic}}){
				    my $from = $filter->{from};
				    my $to   = $filter->{to};
				    $thiscontent =~s/$from/$to/g;
				}
			    }
			    
			    if ($convconfig->{filter}{$category}{filter_junk}){
				$thiscontent = filter_junk($thiscontent);
			    }
			    
			    if ($convconfig->{filter}{$category}{filter_newline2br}){
				$thiscontent = filter_newline2br($thiscontent);
			    }
			    
			    if ($convconfig->{filter}{$category}{filter_match}){
				$thiscontent = filter_match($thiscontent,$convconfig->{filter}{$category}{filter_match});
			    }

			    my $newcategory = $convconfig->{title}{$category}{subfield}{$subfield};
			    
			    if ($newcategory && $convconfig->{title}{$category}{mult} && $thiscontent){
				my $multcount=++$multcount_ref->{$newcategory};
				push @{$title_ref->{fields}{$newcategory}},{
				    mult     => $multcount,
				    content  => $thiscontent,
				    subfield => '',
				};
			    }
			    elsif ($newcategory && $thiscontent){
				push @{$title_ref->{fields}{$newcategory}},{
				    mult     => 1,
				    content  => $thiscontent,
				    subfield => '',
				};
			    }
			}
		    }
		}
		else {
		    $content = konv($content);
		    
		    if ($convconfig->{filter}{$category}{filter_generic}){
			foreach my $filter (@{$convconfig->{filter}{$category}{filter_generic}}){
			    my $from = $filter->{from};
			    my $to   = $filter->{to};
			    $content =~s/$from/$to/g;
			}
		    }
		    
		    if ($convconfig->{filter}{$category}{filter_junk}){
			$content = filter_junk($content);
		    }
		    
		    if ($convconfig->{filter}{$category}{filter_newline2br}){
			$content = filter_newline2br($content);
		    }
		    
		    if ($convconfig->{filter}{$category}{filter_match}){
			$content = filter_match($content,$convconfig->{filter}{$category}{filter_match});
		    }
		    
		    if ($newcategory && $convconfig->{title}{$category}{mult} && $content){
			my $multcount=++$multcount_ref->{$newcategory};
			push @{$title_ref->{fields}{$newcategory}},{
			    mult     => $multcount,
			    content  => $content,
			    subfield => '',
			};
		    }
		    elsif ($newcategory && $content){
			push @{$title_ref->{fields}{$newcategory}},{
			    mult     => 1,
			    content  => $content,
			    subfield => '',
			};
		    }
		}
            }
        }
        print TITOUT encode_json $title_ref, "\n";
    }

    if (!$personfile){
        close(PEROUT);
    }
    if (!$corporatebodyfile){
        close(KOROUT);
    }
    if (!$subjectfile){
        close(SWTOUT);
    }
    if (!$classificationfile){
        close(NOTOUT);
    }
    if (!$holdingfile){
        close(MEXOUT);
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
    open(MEXOUT,'>:raw','meta.holding');

    tie @mab2mexdata, 'Tie::MAB2::Recno', file => $holdingfile;
    
    foreach my $rawrec (@mab2mexdata){
        my $item_ref = {
            'fields' => {},
        };

        my $rec = MAB2::Record::Base->new($rawrec);
        #print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = $category_ref->[2];
            
            #        print "$category - $indicator - $content\n";
            
            $category = $category.$indicator;
            
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
            
            if (exists $convconfig->{holding}{$category}{subfield}){
                foreach my $item (split("",$content)){
                    if ($item=~/^(.)(.+)/){
                        my $subfield = $1;
                        my $thiscontent  = konv($2);
                        
                        #print STDERR $item, " - $subfield - $thiscontent\n";
                        my $newcategory = $convconfig->{holding}{$category}{subfield}{$subfield};
                        
                        if ($newcategory && $convconfig->{holding}{$category}{mult} && $content){
                            my $multcount=++$multcount_ref->{$newcategory};
                            push @{$item_ref->{fields}{$newcategory}},{
                                mult     => $multcount,
                                content  => $thiscontent,
                                subfield => $subfield,
                            };
                        }
                        elsif ($newcategory && $content){
                            push @{$item_ref->{fields}{$newcategory}},{
                                mult     => 1,
                                content  => $thiscontent,
                                subfield => $subfield,
                            };
                        }
                    }
                }
            }
            else {
                $content=konv($content);
                if (exists $convconfig->{holding}{$category}{newcat}){
                    $newcategory = $convconfig->{holding}{$category}{newcat};
                }

                if ($newcategory eq "id" && $content){
                    $item_ref->{id} = $content;
                    next;
                }
                
                if ($newcategory && $convconfig->{holding}{$category}{mult} && $content){
                    my $multcount=++$multcount_ref->{$newcategory};
                    push @{$item_ref->{fields}{$newcategory}},{
                        mult     => $multcount,
                        content  => $content,
                        subfield => '',
                    };
                }
                elsif ($newcategory && $content){
                    push @{$item_ref->{fields}{$newcategory}},{
                        mult     => 1,
                        content  => $content,
                        subfield => '',
                    };
                }
            }
            
        }
        print MEXOUT encode_json $item_ref, "\n";
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

sub filter_junk {
    my ($content) = @_;

    $content=~s/\W/ /g;
    $content=~s/\s+/ /g;
    $content=~s/\s\D\s/ /g;

    
    return $content;
}

sub filter_newline2br {
    my ($content) = @_;

    $content=~s/\n/<br\/>/g;
    
    return $content;
}

sub filter_match {
    my ($content,$regexp) = @_;

    my ($match)=$content=~m/$regexp/g;

    return $match;
}
