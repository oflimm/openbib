#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Catalog::Subset;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

unlink "./title_locationid.db";
unlink "./title_has_parent.db";

my %title_locationid             = ();
my %title_locationid_with_parent = ();
my %title_has_parent             = ();

tie %title_locationid,             'MLDBM', "./title_locationid.db"
    or die "Could not tie title_locationid.\n";

tie %title_has_parent,             'MLDBM', "./title_has_parent.db"
    or die "Could not tie title_has_parent.\n";

print STDERR "### inst001 Analysiere Exemplardaten\n";

open(HOLDING,"meta.holding");

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    next unless ($titleid);

    my $element_ref = (defined $title_locationid{$titleid})?$title_locationid{$titleid}:[];
    
    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} =~m/^Humanwiss. Abteilung/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38";
            push @{$element_ref}, "DE-38-HWA";
        }
        elsif ($location_ref->{content} =~m/^KMB/){
            push @{$element_ref}, "DE-Kn3";
	    push @{$element_ref}, "DE-38-ZBKUNST";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung\s*\/\s*Lehrbuchsammlung/){
            push @{$element_ref}, "DE-38-LBS";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung \/ Lesesaal/){
            push @{$element_ref}, "DE-38-LS";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek VWL/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-101";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek BWL/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-106";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Versicherungswiss/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-123";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Soziologie/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-132";
        }
        elsif ($location_ref->{content} =~m/^Philosoph/){
            push @{$element_ref}, "DE-38-401";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Rechtswissenschaft/){
            push @{$element_ref}, "DE-38-201";
        }
        elsif ($location_ref->{content} =~m/^HF-Bibliothek/){
            push @{$element_ref}, "DE-38-307";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Slavistik/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-418";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Arch.*?ologien \/ .*?Ur- u. Fr.*?geschichte/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-426";
            push @{$element_ref}, "DE-38-ARCH";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Arch.*?ologien \/ Arch.*?ologisches Institut/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-427";
            push @{$element_ref}, "DE-38-ARCH";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Arch.*?ologien \/ Forschungsstelle Afrika/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-438";
            push @{$element_ref}, "DE-38-ARCH";
        }
        elsif ($location_ref->{content} =~m/Theaterwiss. Sammlung/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-429";
            push @{$element_ref}, "DE-38-MEKUTH";
        }
        elsif ($location_ref->{content} =~m/Inst.*?Medienkultur und Theater/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-448";
            push @{$element_ref}, "DE-38-MEKUTH";
        }
        elsif ($location_ref->{content} =~m/Mediensammlung Medienkulturwiss/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-448";
            push @{$element_ref}, "DE-38-MEKUTH";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Asien \/ China/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-450";
            push @{$element_ref}, "DE-38-ASIEN";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Asien \/ Japanologie/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-459";
            push @{$element_ref}, "DE-38-ASIEN";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Chemie/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-507";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Biologie/){
            push @{$element_ref}, "DE-38-USBFB";
            push @{$element_ref}, "DE-38-503";
        }
        elsif ($location_ref->{content} =~m/inst411 /){
            push @{$element_ref}, "DE-38-411";
        }
        elsif ($location_ref->{content} =~m/inst428 /){
            push @{$element_ref}, "DE-38-428";
	    push @{$element_ref}, "DE-38-ZBKUNST";
        }
        elsif ($location_ref->{content} =~m/^Informatik/){
            push @{$element_ref}, "DE-38-006";
        }
        elsif ($location_ref->{content} =~m/inst(\d\d\d) /){
            push @{$element_ref}, "DE-38-$1";
        }

        if ($location_ref->{content} =~m/Oppenheim-Stiftung/){
            push @{$element_ref}, "DE-38-435";
        }
        
        if ($location_ref->{content} =~m/^Hauptabteilung/){
            push @{$element_ref}, "DE-38";
            push @{$element_ref}, "DE-38-USBFB";
        }
    }

    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        if ($mark_ref->{content} =~m/^2[4-9]A/ || $mark_ref->{content} =~m/^[3-9][0-9]A/){
            push @{$element_ref}, "DE-38-SAB";
        }
    }

    foreach my $isil_ref (@{$holding_ref->{fields}{'3330'}}){
        if ($isil_ref->{content} =~m/^(\d\d\d)$/){
            push @{$element_ref}, "DE-38-$1";
        }
        elsif ($isil_ref->{content} eq "Kn 3"){
	    push @{$element_ref}, "DE-Kn3";
	}
        elsif ($isil_ref->{content}){
	    push @{$element_ref}, "DE-".$isil_ref->{content};
	}
    }
    
    $title_locationid{$titleid} = $element_ref if (@$element_ref);
}

close(HOLDING);

print STDERR "### inst001 Analysiere Hierarchie-Struktur der Titeldaten und setze titelspezifische Markierung\n";

open(TITLE,"meta.title");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $element_ref = (defined $title_locationid{$titleid})?$title_locationid{$titleid}:[];

    if (defined $title_ref->{fields}{'0004'}){
        $title_has_parent{$titleid} = $title_ref->{fields}{'0004'}[0]{content};
    }

    # Das EDZ wurde aufgeloest und die Bestaende sind im Magazin
    #
    # if (defined $title_ref->{fields}{'4715'}){
    #     foreach my $item (@{$title_ref->{fields}{'4715'}}){
    #         if ($item->{content} eq "edz"){
    #             push @{$element_ref}, "DE-38-EDZ";
    #         }
    #     }
    # }

    # Thematische Markierung fuer ZB-Kunst
    if (defined $title_ref->{fields}{'4723'}){
        foreach my $item (@{$title_ref->{fields}{'4723'}}){
	    if ($item->{content}=~/^zb-kunst$/){
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
        }
    }

    # KMB-Daten ohne Buchsaetze anhand 4800
    if (defined $title_ref->{fields}{'4800'}){
        foreach my $item (@{$title_ref->{fields}{'4800'}}){
	    if ($item->{content}=~/^E[BKZ]A?$/){
		push @{$element_ref}, "DE-Kn3";
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
	    elsif ($item->{content}=~/^yk$/){
		push @{$element_ref}, "DE-Kn3";
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
        }
    }

    # Online-Medien werden keinen Print-Standorten zugewiesen
    # Neu: wg. KMB wieder deaktiviert
    if (defined $title_ref->{fields}{'4400'}){
        foreach my $item (@{$title_ref->{fields}{'4400'}}){
            if ($item->{content} eq "online"){
#                 $element_ref = [];		
                 push @{$element_ref}, "emedien";
                 push @{$element_ref}, "usbebooks";
            }
        }
    }
    
    # Zeitschriften anhand besetzter ZDB-ID
    if (defined $title_ref->{fields}{'0572'}){
        foreach my $item (@{$title_ref->{fields}{'0012'}}){
            my @isils = sigel2isil($item->{content});
            push @{$element_ref}, @isils if (@isils);
        }
    }
    
    # Vorrangig KMB-eigene E-Books anhand ISIL in 4719
    # Ueberschreiben alle anderen Standorte!!!
    if (defined $title_ref->{fields}{'4719'}){
	$element_ref = [];
        foreach my $item (@{$title_ref->{fields}{'4719'}}){
            if ($item->{content} eq "DE-Kn3"){
                push @{$element_ref}, "DE-Kn3";
		push @{$element_ref}, "DE-38-ZBKUNST";
            }
	    else {
		push @{$element_ref}, $item->{content};
	    }
        }
    }

    # Schwarze Lade der KMB
    if (defined $title_ref->{fields}{'4802'}){
        foreach my $item (@{$title_ref->{fields}{'4802'}}){
            if ($item->{content} eq "88"){
		my @tmp = ( "DE-Kn3-SL", "DE-38-ZBKUNST" );
		foreach my $element (@{$element_ref}){
		    push @tmp, $element unless ($element eq "DE-Kn3");
		}
                @{$element_ref} = @tmp;
            }
        }
    }
    
    $title_locationid{$titleid} = $element_ref;
}

close(TITLE);

print STDERR "### inst001 Hierarchien markieren: Uebergeordnete Titel bekommen Markierung der untergeordneten Titel\n";

my $is_parent_ref         = {};
my $title_with_no_children_ref = {};

# Eltern bestimmen
foreach my $child_id (keys %title_has_parent){
    $is_parent_ref->{$title_has_parent{$child_id}} = 1;
}

# Titel ohne Kinder bestimmen
foreach my $titleid (keys %title_has_parent){
    $title_with_no_children_ref->{$titleid} = 1 if (!defined $is_parent_ref->{$titleid});
}

foreach my $titleid (keys %$title_with_no_children_ref){
    my $this_titleid = $titleid;

    next unless (defined $title_locationid{$titleid});
                 
    my $level = 0;

    # Kind-Markierungen werden sukzessive auf Eltern uebertragen
    while (defined $title_has_parent{$this_titleid}){
        my $parent_titleid = $title_has_parent{$this_titleid};

        # Ggf bereits bestehende Elternmarkierungen werden uebernommen.
        my $parent_element_ref = (defined $title_locationid{$parent_titleid})?$title_locationid{$parent_titleid}:[];

        # Kind-Markierungen werden hinzugefuegt
        push @{$parent_element_ref}, @{$title_locationid{$this_titleid}};

        # .. und Gesamt-Eltern-Markierung wieder zurueckgeschrieben
        $title_locationid{$parent_titleid} = $parent_element_ref;

        # Und weiter zur naechst hoeheren Hierarchieebene.
        
        $this_titleid = $parent_titleid;

        # Abbruch bei Ring-Verknuepfungen
        if ($level > 20){
            print STDERR "### Ueberordnungen - Abbbruch ! Ebene $level erreicht\n";
            $this_titleid = -1;
        }    
        
        $level++;
    }
}


# foreach my $titleid (keys %title_locationid){
#     my $this_titleid = $titleid;

#     next unless (defined $title_locationid{$titleid});
                 
#     my $level = 0;

#     # Markierungen von $this_titleid werden in Gesamtmenge $title_locationid_with_parent kopier
#     if (defined $title_locationid{$titleid}){
#         $title_locationid_with_parent{$this_titleid} = $title_locationid{$this_titleid};
#     }

#     # Kind-Markierungen werden sukzessive auf Eltern uebertragen
#     while (defined $title_has_parent{$this_titleid}){
#         my $parent_titleid = $title_has_parent{$this_titleid};

#         # Ggf bereits bestehende Elternmarkierungen werden uebernommen.
#         my $parent_element_ref = (defined $title_locationid_with_parent{$parent_titleid})?$title_locationid_with_parent{$parent_titleid}:[];

#         # Kind-Markierungen werden hinzugefuegt
#         push @{$parent_element_ref}, @{$title_locationid_with_parent{$this_titleid}};

#         # .. und Gesamt-Eltern-Markierung wieder zurueckgeschrieben
#         $title_locationid_with_parent{$parent_titleid} = $parent_element_ref;

#         # Und weiter zur naechst hoeheren Hierarchieebene.
        
#         $this_titleid = $parent_titleid;

#         # Abbruch bei Ring-Verknuepfungen
#         if ($level > 20){
#             print STDERR "### Ueberordnungen - Abbbruch ! Ebene $level erreicht\n";
#             $this_titleid = -1;
#         }    
        
#         $level++;
#     }
# }


print STDERR "### inst001 Erweitere Titeldaten anhand der bestimmten Markierungen\n";

#open(LOGGING,">location.log.new3");

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $title_locationid{$titleid}){
        my $mult = 1;
        foreach my $locationid (uniq @{$title_locationid{$titleid}}){
            push @{$title_ref->{'locations'}}, $locationid;
        }

#        print LOGGING "$titleid:",join(';',uniq @{$title_locationid{$titleid}}),"\n";
    }
    
    print encode_json $title_ref, "\n";
}

#close(LOGGING);

sub sigel2isil {
    my $content = shift;

    my @isils = ();
    
    if ($content =~m/^38$/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38";
    }
    elsif ($content =~m/38\/101/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-101";
    }
    elsif ($content =~m/38\/123/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-123";
    }
    elsif ($content =~m/38\/132/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-132";
    }
    elsif ($content =~m/^38\/418/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-418";
    }
    elsif ($content =~m/^38\/426/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-426";
        push @isils, "DE-38-ARCH";
    }
    elsif ($content =~m/^38\/427/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-427";
        push @isils, "DE-38-ARCH";
    }
    elsif ($content =~m/38\/429/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-429";
        push @isils, "DE-38-MEKUTH";
    }
    elsif ($content =~m/38\/448/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-448";
        push @isils, "DE-38-MEKUTH";
    }
    elsif ($content =~m/^38\/450/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-450";
        push @isils, "DE-38-ASIEN";
    }
    elsif ($content =~m/^38\/459/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-459";
        push @isils, "DE-38-ASIEN";
    }
    elsif ($content =~m/38\/507/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-507";
    }
    elsif ($content =~m/^Kn\s*3/){
        push @isils, "DE-Kn3";
        push @isils, "DE-38-ZBKUNST";
    }
    elsif ($content =~m/^38\/(\d\d\d)/){
        push @isils, "DE-38-$1";
    }
    else {
	$content =~s/ //g;
        $content =~s/\//-/g;
        $content = "DE-$content";
        push @isils, $content;
    }

#    print STDERR "ZSST ISILs: ",join(';',@isils),"\n" if (@isils);
    
    return @isils;
}

