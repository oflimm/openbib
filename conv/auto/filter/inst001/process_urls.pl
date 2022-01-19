#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    my $titleid = $record_ref->{id};
    
    # Uebertragung der URLs in andere Katagorie
    #
    # Link zum Volltext:
    #
    # Uebertragen in Titelfeld fuer E-Medien T4120
    # Analog zu angereicherten Link zu E-Medien in E4120
    #
    # Markierung von URLs nach Typ in Subfield
    #
    #  : Unbekannt
    # a: Freier Zugriff    
    # b: Eingeschraenkter Zugriff
    # c: Kein Zugriff

    # Uebertragung der URLs in andere Katagorie    

    my $mult_ref = {};

    $mult_ref->{'4120'} = 1 if (!defined $mult_ref->{'4120'});

    my $have_ezb = 0;
    my $have_dbis = 0;
    my $have_toc = 0;
    
    # Kategorieinhalte zusammenfuehren zum vereinfachten Matchen 0662
    my $all_0662 = "";
    my $all_2662 = "";
    
    if (defined $fields_ref->{'0662'}) {
	my @content_0662 = ();
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    push @content_0662, $item_ref->{content};
	}

	$all_0662 = join(' ; ',@content_0662);
    }
   
    # Zuerst 2662
    if (defined $fields_ref->{'2662'}) {

	my $description_ref = {};

	foreach my $item_ref (@{$fields_ref->{'2663'}}){
	    $description_ref->{$item_ref->{mult}} = $item_ref->{content};
	}

	# Kategorieinhalte zusammenfuehren zum vereinfachten Matchen 2662	
	my @content_2662 = ();
	foreach my $item_ref (@{$fields_ref->{'2662'}}){
	    push @content_2662, $item_ref->{content};
	}

	$all_2662 = join(' ; ',@content_2662);
	
	foreach my $item_ref (@{$fields_ref->{'2662'}}){
	    my $content = $item_ref->{content};
	    my $mult    = $mult_ref->{'4120'}++;

	    # Hochschulschriften
	    if ($content =~m/^https?:\/\/kups\.ub\.uni\-koeln\.de/){
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => 'a', # green
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Elektronische Hochschulschrift im Volltext",
		};
	    }
	    # Lokale Digitalisate
	    elsif ($content =~m/^https?:\/\/www\.ub\.uni\-koeln\.de\/permalink/){
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => ' ', # unbestimmt. Es gibt auch gelbe Objekte ID=6612903
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Volltext",
		};
	    }
	    # EZB Zeitschriften
	    elsif ($content =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\//){ # Bsp.: ISSN=1572-8358
		$have_ezb = 1;
		
		my $url         = $content;
		my $description = "Elektronische Zeitschrift im Volltext";
		my $access      = "u"; # unknown

		# Lokal vorhanden Bsp.: ID=Rendite (Hallische Jahrbuecher / Intelligenzblatt)
		# Dann: EZB-Frontdoor umgehen, falls Permalink der USB existiert
		
		if ($all_0662 =~m/(https?:\/\/www\.ub\.uni-koeln\.de\/permalink\/.+?katkey:\d+)/){
		    $url        = $1;
		    $access     = "g"; # green
		}
		else {
		    $access     = "y"; # yellow
		}

		# Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
		# Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen
		
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # Datenbanken
	    elsif ($content =~m/^^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/dbinfo\/|cdroms\.digibib\.net|\.ica$/
		   or $content =~m/https?:\/\/www\.ub\.uni\-koeln\.de\/usbportal\?service=dbinfo/){ # Bsp.: TI=wiso-net
		$have_dbis = 1;

		my $url         = $content;
		my $description = "Datenbankrecherche starten";
		my $access      = "y"; # yellow

		if ($titleid == 5255340 && $content =~m/id=1061/){
		    $description = "MLA directory of periodicals";
		}
		elsif ($titleid == 5255340 && $content =~m/id=76/){
		    $description = "MLA international bibliography";
		}
		
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # E-Books mit lokaler URL, z.B.: ID=5902307
	    elsif ($description_ref->{$mult} =~m/Zugriff nur im Hochschulnetz/){
		my $url         = $content;
		my $description = "E-Book im Volltext";
		my $access      = "y"; # yellow
		
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    else { # Bsp.: ID=277940
		push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => ' ', # Unbestimmt
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $content,
		};
	    }
	    
	}
    }
    
    # Dann 0662
    if (defined $fields_ref->{'0662'}) {
	my $linktext_ref = {};
	
	foreach my $item_ref (@{$fields_ref->{'0663'}}){
	    $linktext_ref->{$item_ref->{mult}} = $item_ref->{content};
	}
	
	foreach my $item_ref (@{$fields_ref->{'0655'}}){
	    if (defined $linktext_ref->{$item_ref->{mult}}){
		$linktext_ref->{$item_ref->{mult}} .= " ; ".$item_ref->{content};
	    }
	    else {
		$linktext_ref->{$item_ref->{mult}} = $item_ref->{content};		
	    }
	}

	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    my $content = $item_ref->{content};
	    my $mult    = $mult_ref->{'4120'}++;
	    
	    # Inhaltsverzeichnisse
	    #
	    # Link zum Inhaltsverzeichnis:
	    #
	    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4110
	    # Analog zu angereicherten Link zu Inhaltsverzeichnissen in E4110
	    
	    if (defined $linktext_ref->{$item_ref->{mult}} && $linktext_ref->{$item_ref->{mult}} =~m/Inhaltsverzeichnis|Inh\.\-Verz\./){

		# Falls bereits ein Link "Inhaltsverzeichnis" existiert, nur insgesamt einen Link berücksichtigen
		if ($content =~m/hbz\-nrw\.de/){ # hbz-Inhaltsverzeichnis hat Vorrang, z.B. ID=7741043
		    $record_ref->{fields}{'4110'} = [{
			mult     => 1,
			subfield => '',
			content  => $item_ref->{content},
						     }];
		}
		elsif (!$have_toc){
		    $record_ref->{fields}{'4110'} = [{
			mult     => 1,
			subfield => '',
			content  => $item_ref->{content},
						     }];
		}		
		$have_toc = 1;
	    }

	    # Volltexte
	    #
	    # Link zum Inhaltsverzeichnis:
	    #
	    # Uebertragen in Titelfeld fuer Volltext-URls T4120 + Mult-Nummer
	    # Bestimmung des Zugriffstatus und Abspeicherung in Subfeld von T4120
	    # Bestimmung des Link-Textes in T4121 + Mult-Nummer
	    
	    # Freie Volltextlinks:
	    #
	    # Inhalt von 0663 (.+? steht fuer einen beliebigen Inhalt dazwischen):
	    #
	    # - Interna: Verlag.+?Info: kostenfrei
	    # - Interna: Verlag.+?Info: Deutschlandweit zugänglich
	    # - Interna: Langzeitarchivierung.+?Info: kostenfrei
	    # - Interna: Digitalisierung.+?Info: kostenfrei
	    if (defined $linktext_ref->{$item_ref->{mult}}){
		my $linktext = $linktext_ref->{$item_ref->{mult}};
		
		if ($linktext =~m/(Digitalisierung|Langzeitarchivierung|Volltext)\; Info: kostenfrei/i # ID=6521146 ; Projekt Digitalis, Bsp.: Achenbach Berggesetzgebung
                    or $linktext =~m/Info: kostenfrei; Bezugswerk: Volltext/i # ID=6625319
                    or $linktext =~m/Open Access/) { # ID=6693843  
		    
		    my $description = "Volltext";
		    my $url         = $content;
		    my $access      = "g"; # green

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    
		}
		elsif ($linktext =~m/(Verlag.*); Info: kostenfrei/i){
		    my $description = $1;
		    my $url         = $content;
		    my $access      = "g"; # green

		    if ($content =~m/^https?:\/\/dx\.doi\.org\//) {  # Bsp.: ID=6683669
			$description = "Volltext";
		    }
		    else {
			$description = "Webseite ($description)";			
		    }

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    
		}
		elsif ($linktext =~m/(Resolving-System|URN)/) { # Bsp.: TI=Bayerische Bauordnung 2008 ; ID=6685427 
		    my $description = "Volltext";
		    my $url         = $content;
		    my $access      = ""; # Keine Ampel

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    
		    
		}
		elsif ($linktext =~m/^Zus.*tzliche Angaben$/i) { # Bsp.: HBZID=HT013697253, HBZID=HT016192826 (falsch kodierter Umlaut)
                    next; # Link auf Objektbaum ueberspringen
                }
		elsif ($linktext =~m/Link-Text: C\;/) { # Bsp.: ID=6713163
                    next; # Link auf Coverscans ueberspringen
		}
		elsif ($linktext =~m/ebooks.ciando.com/) { # Bsp.: ID=6713163
                    next; # PKN: Link auf E-Books von Ciando ueberspringen
		}
		elsif ($linktext =~m/Bez.: 2/) { # Bsp.: ID=inst001:81361
                    # Linktext "Bez.: 2" durch URL ersetzen

		    my $description = $content;
		    my $url         = $content;
		    my $access      = ""; # Keine Ampel

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    

		}
		elsif ($linktext =~m/EZB/) { # Bsp.: ID=6348154 (Hallische Jahrbuecher) -> gruen ; ID=6111996 (Bibliotheksdienst) -> rot
		    # Nicht implementiert: EZB-Link fuer E-Journals der KMB ueberspringen
		    # Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
		    # Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen

		    my $description = "Elektronische Zeitschrift im Volltext";
		    my $url         = $content;
		    my $access      = ""; # Keine Ampel

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    
		    
		}
		elsif ($linktext =~m/DBIS/ && $mult > 1) { # Bsp.: TI=Bayerische Bauordnung 2008
                     # 2. DBIS-Link loeschen, da Titel evtl. nicht in die DBIS-Sicht der USB aufgenommen wurde
                    next;
		}
		elsif ($linktext =~m/^Kontakt/ && $content =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
		    if (!$have_toc){
			$record_ref->{fields}{'4110'} = [{
			    mult     => 1,
			    subfield => '',
			    content  => $content,
							 }];
		    }
		    $have_toc = 1;
		}
		elsif ($linktext =~m/^Inhaltsverzeichnis/ && $content =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
		    if (!$have_toc){
			$record_ref->{fields}{'4110'} = [{
			    mult     => 1,
			    subfield => '',
			    content  => $content,
							 }];
		    }
		    $have_toc = 1;
		}		
		else {
		    my $description = $linktext;
		    my $url         = $content;

		    $description =~ s!.*Interna: (.+)!$1!; 
		    $description =~ s!(.+); Bez.: \d[^;]*!$1!; # ID=6685427 
		    $description =~ s!.*Bezugswerk: ([^\;]+).*!$1!; # Bsp.: ID=7733592 (ADAM-Links)
                    $description =~ s!.*Link-Text: ([^;]+).*!$1!; # Bsp.: ISBN=978-3-86009-086-2
                    $description =~ s!^Metadaten$!Dokumentbeschreibung!; # Bsp.: ISBN=978-3-86009-086-2
                    $description =~ s!Media!Inhaltsverzeichis / Abstract / Zusätze!;
                    $description =~ s!.*(Bezugswerk|Info): Inhaltstext.*!Inhaltsbeschreibung!; # Bsp.: ISBN=3-8348-9961-5
                    $description =~ s!.*(Bezugswerk|Info): Inhaltsverzeichnis.*!Inhaltsverzeichnis!; # Bsp.: ISBN=3-540-89993-6 ; ISBN=978-3-8300-6282-0
                    $description =~ s!.*Bezugswerk: \d+!Verlagsinformationen!; # Bsp.: ISBN=978-3-8300-6282-0
                    $description =~ s!.*Bezugswerk: .*Beschreibung.*!Verlagsinformationen!; # Bsp.: ISBN=978-3-8300-5801-4
                    $description =~ s!.*Bezugswerk: .*Cover.*!Cover!; # Bsp.: ISBN=978-3-527-71296-0
                    $description =~ s!Verlagsdaten!Verlagsinformationen!; # Bsp.: ISBN=3-540-41515-7
                    $description =~ s!Kapitel!Kapitelvorschau!; # Bsp.: ID=7733592 (ADAM-Links)
                    $description =~ s!Inh\.\-Verz\.!Inhaltsverzeichnis!; # Bsp.: ID=6595544 (DNB-Inhaltsverzeichnis)
                    $description =~ s!^Info: !!; # Bsp.: ID=6779590
                    $description = $url if $description =~ /^Verlag;/; # Bsp.: ID=6111996 (Bibliotheksdienst)
		}

		# Alte Kriterien
		# $linktext_ref->{$item_ref->{mult}} =~m/Interna: Verlag.+?Info: kostenfrei/
		# $linktext_ref->{$item_ref->{mult}} =~m/Interna: Verlag.+?Info: Deutschlandweit zugänglich/
		# $linktext_ref->{$item_ref->{mult}} =~m/Interna: Langzeitarchivierung.+?Info: kostenfrei/
		# $linktext_ref->{$item_ref->{mult}} =~m/Interna: Digitalisierung.+?Info: kostenfrei/ )
		
	    }
	    else { # Keine Linkbeschreibung in 663 oder 655 vorhanden

		if ($content =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\//) {
		    my $description = "Elektronische Zeitschrift im Volltext"; # Bsp.: TI=Unix review.com
		    my $url = $content;
		    my $access = "g"; # green

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		# DBIS
		elsif ($content =~ /^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/dbinfo\//) {
		    my $description = "Datenbankrecherche starten";
		    my $url = $content;
		    my $access = "g"; # green

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		elsif ($content =~ /^https?:\/\/kups\.ub\.uni\-koeln\.de/) { # Bsp.: AU=Joecker, Anita
		    my $description = "Elektronische Hochschulschrift im Volltext";
		    my $url = $content;
		    my $access = "g"; # green

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		elsif ($content =~m/www\.gbv\.de\/dms\/|www\.ulb\.tu-darmstadt\.de\/tocs\//) { # Bsp.: IB=978-3-7723-7449-4, ID=6262313
		    if (!$have_toc){
			$record_ref->{fields}{'4110'} = [{
			    mult     => 1,
			    subfield => '',
			    content  => $content,
							 }];
		    }
		    $have_toc = 1;		    
		}
		elsif ($content =~m/deposit\.d\-nb\.de\/cgi\-bin\/dokserv/) { # Bsp.: ID=6262313
		    my $description = "Verlagsinformationen";
		    my $url = $content;
		    my $access = ""; # keine Ampel;

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		elsif ($content) {
		    my $description = $content;
		    my $url = $content;
		    my $access = ""; # keine Ampel;

		    push @{$record_ref->{fields}{'4120'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4121'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
	    }
	}
    }

    # Zweiter Durchang durch alle Links und Analyse weiterer Kategorien

    my $linktext_ref = {};
    
    foreach my $item_ref (@{$fields_ref->{'4121'}}){
	$linktext_ref->{$item_ref->{mult}} = $item_ref->{content};
    }

    foreach my $item_ref (@{$fields_ref->{'4120'}}){
	# Todo	
    }

    print encode_json $record_ref, "\n";
}
