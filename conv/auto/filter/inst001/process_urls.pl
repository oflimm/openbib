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
    # Link in content von 4662
    # Zugriffsstatus in subfield von 4662
    # Beschreibungstext in content von 4663
    #
    # Eintraege von 4662 und 4663 bilden eine Multgruppe (Zuordnung via mult)   
    #
    # Ausnahme Links zu Inhaltsvereichnissen
    # Link zum Inhaltsverzeichnis in content von 4110 analog
    # zu angereicherten Links zu Inhaltsverzeichnissen in E4110
    #
    # Zugriffstatus
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Eingeschraenkter Zugriff (yellow)
    # 'r': Kein Zugriff (red)

    my $mult_ref = {};

    $mult_ref->{'4662'} = 1;

    my $have_ezb  = 0;
    my $have_dbis = 0;
    my $have_toc  = 0;
    
    # Kategorieinhalte zusammenfuehren zum vereinfachten Matchen 0662/2662
    my $all_0662 = "";
    
    if (defined $fields_ref->{'0662'}) {
	my @content_0662 = ();
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    push @content_0662, $item_ref->{content};
	}

	$all_0662 = join(' ; ',@content_0662);
    }

    # Ab jetzt Analyse der Kategoriebesetzung

    # Zuerst Analyse der Links in 2662
    if (defined $fields_ref->{'2662'}) {

	my $linktext_ref = {};

	foreach my $item_ref (@{$fields_ref->{'2663'}}){
	    $linktext_ref->{$item_ref->{mult}} = $item_ref->{content};
	}

	# Andere Felder aus der Multgruppe zu 2662/2663
	# als Entscheidungskriterium
	
	my $field1209_ref = {};

	foreach my $item_ref (@{$fields_ref->{'1209'}}){
	    $field1209_ref->{$item_ref->{mult}} = $item_ref->{content};
	}
	
	foreach my $item_ref (@{$fields_ref->{'2662'}}){
	    my $content = $item_ref->{content};
	    my $mult    = $mult_ref->{'4662'}++;

	    # Hochschulschriften
	    if ($content =~m/^https?:\/\/kups\.ub\.uni\-koeln\.de/){
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'g', # green
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Elektronische Hochschulschrift im Volltext",
		};
	    }
	    # Lokale Digitalisate
	    elsif ($content =~m/^https?:\/\/www\.ub\.uni\-koeln\.de\/permalink/){
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'f', # fulltext = green or yellow. Es gibt auch gelbe Objekte ID=6612903
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
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
		my $access      = " "; # Default: unknown

		if ($all_0662 =~m/https?:\/\/www\.ub\.uni-koeln\.de\/permalink\//){
		    $access     = "g"; # green
		}
		else {
		    $access     = "y"; # yellow
		}

		# Lokal vorhanden Bsp.: ID=Rendite (Hallische Jahrbuecher / Intelligenzblatt)
		# Dann: EZB-Frontdoor umgehen, falls Permalink der USB existiert
		if ($all_0662 =~m/(https?:\/\/www\.ub\.uni-koeln\.de\/permalink\/.+?katkey:\d+)/){
		    $url        = $1;
		}

		# Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
		# Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
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
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # E-Books mit lokaler URL, z.B.: ID=5902307
	    elsif (defined $linktext_ref->{$item_ref->{mult}} && $linktext_ref->{$item_ref->{mult}} =~m/Zugriff nur im Hochschulnetz/){
		my $url         = $content;
		my $description = "E-Book im Volltext";
		my $access      = "y"; # yellow
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # KMB
	    elsif (defined $linktext_ref->{$item_ref->{mult}} && $linktext_ref->{$item_ref->{mult}} =~m/Zugriff im Netz der Kunst- und Museumsbibliothek möglich/ ){
		my $url         = $content;
		my $description = "E-Book im Volltext";
		my $access      = "y"; # yellow
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # OA
	    elsif (defined $linktext_ref->{$item_ref->{mult}} && ( $linktext_ref->{$item_ref->{mult}} =~m/^Open access. Im Internet weltweit frei verfügbar/ || $linktext_ref->{$item_ref->{mult}} =~m/^Frei zugänglich/ )){
		my $url         = $content;
		my $description = "E-Book im Volltext";
		my $access      = "g"; # green
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    
	    elsif (defined $field1209_ref->{$item_ref->{mult}} && $field1209_ref->{$item_ref->{mult}} =~m/^fzo$/){
		my $url         = $content;
		my $description = "Volltext";
		my $access      = "g"; # green
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
		
	    }
	    else { # Bsp.: ID=277940
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => ' ', # Unbestimmt
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $content,
		};
	    }
	    
	}
    }
    
    # Dann Analyse der Links in 0662
    if (defined $fields_ref->{'0662'}) {

	# Zuerst Linkbeschreibung zu einfacheren Matchen aus 0663 und 0655 merken
	my $linktext_ref = {};

	if (defined $fields_ref->{'0663'}){
	    foreach my $item_ref (@{$fields_ref->{'0663'}}){
		$linktext_ref->{$item_ref->{mult}} = $item_ref->{content};
	    }
	}

	if (defined $fields_ref->{'0655'}){	
	    foreach my $item_ref (@{$fields_ref->{'0655'}}){
		if (defined $linktext_ref->{$item_ref->{mult}}){
		    $linktext_ref->{$item_ref->{mult}} .= " ; ".$item_ref->{content};
		}
		else {
		    $linktext_ref->{$item_ref->{mult}} = $item_ref->{content};		
		}
	    }
	}

	# Dann alle Links nacheinander durchgehen
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    my $content = $item_ref->{content};
	    my $mult    = $mult_ref->{'4662'}++;

	    # Hochschulschriften
	    if ($content =~m/^https?:\/\/kups\.ub\.uni\-koeln\.de/){
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'g', # green
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Elektronische Hochschulschrift im Volltext",
		};
	    }
	    # Lokale Digitalisate
	    elsif ($content =~m/https?:\/\/www\.ub\.uni\-koeln\.de\/permalink/){
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'f', # fulltext = green or yellow. Es gibt auch gelbe Objekte ID=6612903
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Volltext",
		};
	    }
	    # EZB Zeitschriften
	    elsif ($content =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\// && !$have_ezb){ # Bsp.: ISSN=1572-8358

		$have_ezb = 1;
		
		my $url         = $content;
		my $description = "Elektronische Zeitschrift im Volltext";
		my $access      = " "; # Default: unknown

		if ($all_0662 =~m/https?:\/\/www\.ub\.uni-koeln\.de\/permalink\//){
		    $access     = "g"; # green
		}
		else {
		    $access     = "y"; # yellow
		}

		# Lokal vorhanden Bsp.: ID=Rendite (Hallische Jahrbuecher / Intelligenzblatt)
		# Dann: EZB-Frontdoor umgehen, falls Permalink der USB existiert
		if ($all_0662 =~m/(https?:\/\/www\.ub\.uni-koeln\.de\/permalink\/.+?katkey:\d+)/){
		    $url        = $1;
		}

		# Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
		# Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
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
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    # E-Books mit lokaler URL, z.B.: ID=5902307
	    elsif (defined $linktext_ref->{$item_ref->{mult}} && $linktext_ref->{$item_ref->{mult}} =~m/Zugriff nur im Hochschulnetz/){
		my $url         = $content;
		my $description = "E-Book im Volltext";
		my $access      = "y"; # yellow
		
		push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $content,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		};
	    }
	    
	    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4110	    
	    elsif (defined $linktext_ref->{$item_ref->{mult}} && $linktext_ref->{$item_ref->{mult}} =~m/Inhaltsverzeichnis|Inh\.\-Verz\./){ # Inhaltsverzeichnisse

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

	    # Wenn Linktext zum aktuellen Link vorhanden ist
	    # (Zuordnung ueber mult) kann dieser zur Analyse
	    # herangezogen werden
	    elsif (defined $linktext_ref->{$item_ref->{mult}}){
		my $linktext = $linktext_ref->{$item_ref->{mult}};

		$linktext =~ s!.*Interna: (.+)!$1!; 
		$linktext =~ s!(.+); Bez.: \d[^;]*!$1!; # ID=6685427 
		
		if ($linktext =~m/(Digitalisierung|Langzeitarchivierung|Volltext)\; Info: kostenfrei/i # ID=6521146 ; Projekt Digitalis, Bsp.: Achenbach Berggesetzgebung
                    or $linktext =~m/Info: kostenfrei; Bezugswerk: Volltext/i # ID=6625319
                    or $linktext =~m/Open Access/) { # ID=6693843  
		    
		    my $description = "Volltext";
		    my $url         = $content;
		    my $access      = "g"; # green

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    
		}
		elsif ($linktext =~m/(Resolving-System|URN)/) { # Bsp.: TI=Bayerische Bauordnung 2008 ; ID=6685427 
		    my $description = "Volltext";
		    my $url         = $content;
		    my $access      = ""; # Keine Ampel

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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
		    my $access      = ''; # Default: keine Ampel. Ggf. Anpassung (s.u.)
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    
		}
	    }
	    else { # Keine Linkbeschreibung in 663 oder 655 vorhanden

		if ($content =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\//) {
		    my $description = "Elektronische Zeitschrift im Volltext"; # Bsp.: TI=Unix review.com
		    my $url = $content;
		    my $access = "g"; # green

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		elsif ($content =~ /^https?:\/\/kups\.ub\.uni\-koeln\.de/) { # Bsp.: AU=Joecker, Anita
		    my $description = "Elektronische Hochschulschrift im Volltext";
		    my $url = $content;
		    my $access = "g"; # green

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
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

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
		elsif ($content) {
		    my $description = $content;
		    my $url = $content;
		    my $access = ""; # keine Ampel;

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
		    };		    		    		    
		}
	    }
	}
    }

    my $pakete = "";

    if (defined $fields_ref->{'0078'} || defined $fields_ref->{'1209'}){
	$pakete = (defined $fields_ref->{'0078'})?$fields_ref->{'0078'}[0]{content}:"";
	if (defined $fields_ref->{'1209'}){
	    $pakete.="; ".$fields_ref->{'1209'}[0]{content};
	}
    }

    # Wichtig: Damit 4410 ausgewertet werden kann muss vorher add_fields.pl gelaufen sein!!!
    
    my $is_digital = 0;

    if (defined $fields_ref->{'4410'}){
	foreach my $item_ref (@{$fields_ref->{'4410'}}){
	    if ($item_ref->{content} eq "Digital"){
		$is_digital = 1;
	    }
	}
    }

    my $has_isbn = 0;

    if (defined $fields_ref->{'0540'} || defined $fields_ref->{'0541'}){
	$has_isbn = 1;
    }

    my $restricted_access = 0;

    if (defined $fields_ref->{'1203'}){
	foreach my $item_ref (@{$fields_ref->{'1203'}}){
	    if ($item_ref->{content} =~m/Zugriff nur im Hochschulnetz/){
		$restricted_access = 1;
	    }
	}
    }

    if (defined $fields_ref->{'1212'}){
	foreach my $item_ref (@{$fields_ref->{'1212'}}){
	    if ($item_ref->{content} =~m/Zugriff nur im Hochschulnetz/){
		$restricted_access = 1;
	    }
	}
    }

    if (defined $fields_ref->{'2663'}){
	foreach my $item_ref (@{$fields_ref->{'2663'}}){
	    if ($item_ref->{content} =~m/Zugriff nur im Hochschulnetz/){
		$restricted_access = 1;
	    }
	}
    }
        
    # Zweiter Durchang durch alle Links und Analyse weiterer Kategorien
    if (defined $fields_ref->{'4662'}){
	my $i = 0;
	while (defined $fields_ref->{'4662'}[$i]){
	    my $url         = $fields_ref->{'4662'}[$i]{content};
	    my $description = (defined $fields_ref->{'4663'} && defined $fields_ref->{'4663'}[$i])?$fields_ref->{'4663'}[$i]{content}:"";
	    
	    if ($is_digital && $url !~ /dbinfo/ && $description !~ /^(Inhalt|Verlag)/ &&
		($has_isbn or $pakete=~m/(oecd|ZDB-14-DLO|ZDB-57-DVR|ZDB-57-DSG|ZDB-57-DFS)$/)){ # ggf. Bedingung ergaenzen: Hat ISBN der Paralellausgabe in '1586', '1587', '1588', '1590', '1591', '1592', '1594', '1595', '1596'
		$description = "E-Book im Volltext";
		$fields_ref->{'4663'}[$i]{content} = $description;
	    }

	    if ($description =~m/Volltext/ && $restricted_access){
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
	    }
	    elsif ($pakete =~m/(ZDB-57-DVR|ZDB-57-DSG|ZDB-57-DFS)/){ # Freie E-Books aus dem Projekt Digi20
		$fields_ref->{'4662'}[$i]{subfield} = "g"; # green Bsp.: ID=6822919		
	    }
	    elsif ($pakete =~m/(ZDB-2-SWI|ZDB-2-SNA|ZDB-2-STI|ZDB-2-SGR|ZDB-2-SGRSpringer|ZDB-2-SEP|ZDB-2-SBE|ZDB-2-CMS|ZDB-2-PHA|ZDB-13-SOC|ZDB-14-DLO|ZDB-5-WEB|ZDB-5-WMS|ZDB-5-WMW|ZDB-18-BEO|ZDB-18-BOH|ZDB-18-BST|ZDB-2-SMA|ZDB-2-MGE|ZDB-2-SZR|ZDB-2-BUM|ZDB-2-ECF|ZDB-2-SCS|ZDB-2-ESA|ZDB-23-DGG|ZDB-98-IGB)/){
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
		$fields_ref->{'4663'}[$i]{content}  = "E-Book im Volltext" if ($description !~m/Verlag/);
		
	    }
	    elsif ($pakete =~m/ZDB-2-SpringerOpen/) { # z.B. ID=7807222, ID=6813324
		$fields_ref->{'4662'}[$i]{subfield} = "g"; # green
		$fields_ref->{'4663'}[$i]{content}  = "E-Book im Volltext";
	    }
	    elsif ($pakete =~m/(ZDB-185-STD|ZDB-185-SDI)/){ # Statista-Dossiers
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
		$fields_ref->{'4663'}[$i]{content}  = "Dossier im Volltext";
	    }
	    elsif ($pakete =~m/ZDB-101-VTB/){ # video2brain
		$fields_ref->{'4663'}[$i]{content}  = "Video";
	    }
	    
	    $i++;
	}       
    }
    
    # Volltext-Links zusaetzlich in 4120 ablegen fuer direkte Verlinkung in Trefferliste

    if (defined $fields_ref->{'4662'}){
	foreach my $item_ref (@{$fields_ref->{'4662'}}){
	    if ($item_ref->{subfield} =~m/(g|y|f)/){
		$record_ref->{fields}{'4120'} = [{
		    mult     => 1,
		    subfield => $item_ref->{subfield},
		    content  => $item_ref->{content},
						 }];
	    }
	    last;
	}	
    }    
    
    print encode_json $record_ref, "\n";
}
