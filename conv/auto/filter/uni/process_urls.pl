#!/usr/bin/perl

use HTML::Entities qw/decode_entities/;
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
    # Link zum Volltext in 4120 mit Zugriffsstatus in subfield
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
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'n': Zugriff ueber Nationallizenz
    # 'r': Kein Zugriff (red)

    my $mult_ref = {};

    $mult_ref->{'4662'} = 1;

    my $field1209_ref = {};
    
    my $have_ezb  = 0;
    my $have_dbis = 0;
    my $have_toc  = 0;

    my $url_done_ref = {};
    
    # Zuerst Analyse der Portfolie-Informationen in 1945

    if (defined $fields_ref->{'1945'}){
	# Umorganisieren nach Mult-Gruppe
	my $portfolio_ref = {};
	
	foreach my $item_ref (@{$fields_ref->{'1945'}}){
	    $portfolio_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content}; 
	}

	foreach my $pmult (sort keys %$portfolio_ref){
	    if (defined $portfolio_ref->{$pmult}{'e'}){ # Static URL available
		my $url = $portfolio_ref->{$pmult}{'e'};
		my $mult    = $mult_ref->{'4662'}++;

		# Hochschulschriften
		if ($url =~m/^https?:\/\/kups\.ub\.uni\-koeln\.de/){
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'g', # green
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Elektronische Hochschulschrift im Volltext",
		    };
		    
		    $url_done_ref->{$url} = 1;
		}
		# Lokale Digitalisate
		elsif ($url =~m/^https?:\/\/www\.ub\.uni\-koeln\.de\/permalink/){
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'f', # fulltext = green or yellow. Es gibt auch gelbe Objekte ID=6612903
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Volltext",
		    };
		    
		    $url_done_ref->{$url} = 1;
		}
		# EZB Zeitschriften
		elsif ($url =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\//){ # Bsp.: ISSN=1572-8358
		    
		    $have_ezb = 1;
		    
		    my $description = "Elektronische Zeitschrift im Volltext";
		    my $access      = " "; # Default: unknown
		    
		    # Wie kann man hier green und yellow unterscheiden?
		    
		    # Lokal vorhanden Bsp.: ID=Rendite (Hallische Jahrbuecher / Intelligenzblatt)
		    # Dann: EZB-Frontdoor umgehen, falls Permalink der USB existiert
		    
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

		    $url_done_ref->{$url} = 1;
		}
		# Datenbanken
		elsif ($url =~m/^^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/dbinfo\/|cdroms\.digibib\.net|\.ica$/
		       or $url =~m/https?:\/\/www\.ub\.uni\-koeln\.de\/usbportal\?service=dbinfo/){ # Bsp.: TI=wiso-net
		    $have_dbis = 1;
		    
		    my $description = "Datenbankrecherche starten";
		    my $access      = "y"; # yellow
		    
		    # if ($titleid == 5255340 && $url =~m/id=1061/){
		    # 	$description = "MLA directory of periodicals";
		    # }
		    # elsif ($titleid == 5255340 && $url =~m/id=76/){
		    # 	$description = "MLA international bibliography";
		    # }
		    
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

		    $url_done_ref->{$url} = 1;
		}
		elsif ($url =~m/www\.gbv\.de\/dms\/|www\.ulb\.tu-darmstadt\.de\/tocs\//) { # Bsp.: IB=978-3-7723-7449-4, ID=6262313
		    if (!$have_toc){
			$record_ref->{fields}{'4110'} = [{
			    mult     => 1,
			    subfield => '',
			    content  => $url,
							 }];
		    }
		    $have_toc = 1;

		    $url_done_ref->{$url} = 1;
		}
		# public_note aus Portfolio zum URL verfuegbar
		elsif (defined $portfolio_ref->{$pmult}{'l'}){
		    my $public_note = $portfolio_ref->{$pmult}{'l'};
		    
		    # E-Books mit lokaler URL, z.B.: ID=5902307
		    if ($public_note =~m/(Zugriff nur im Hochschulnetz|lizenzpflichtig|Access restricted to subscribers)/i){
			my $description = "E-Book im Volltext";
			my $access      = "y"; # yellow
			
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

			$url_done_ref->{$url} = 1;
		    }
		    # KMB
		    elsif ($public_note =~m/Zugriff im Netz der Kunst- und Museumsbibliothek möglich/){
			my $description = "E-Book im Volltext (KMB)";
			my $access      = "y"; # yellow
			
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

			$url_done_ref->{$url} = 1;
		    }
		    # OA
		    elsif ($public_note =~m/(kostenfrei|lizenzfrei|Frei zugänglich|Full text online|Open *Access|DOAB)/i ){
			my $description = "E-Book im Volltext";
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
			
			$url_done_ref->{$url} = 1;
		    }
		    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4110	    
		    elsif ($public_note =~m/Inhaltsverzeichnis|Inh\.\-Verz\./){ # Inhaltsverzeichnisse
			
			# Falls bereits ein Link "Inhaltsverzeichnis" existiert, nur insgesamt einen Link berücksichtigen
			if ($url =~m/hbz\-nrw\.de/){ # hbz-Inhaltsverzeichnis hat Vorrang, z.B. ID=7741043
			    $record_ref->{fields}{'4110'} = [{
				mult     => 1,
				subfield => '',
				content  => $url,
							     }];
			}
			elsif (!$have_toc){
			    $record_ref->{fields}{'4110'} = [{
				mult     => 1,
				subfield => '',
				content  => $url,
							     }];
			}		
			$have_toc = 1;

			$url_done_ref->{$url} = 1;			
		    }
		    else {
			$public_note =~ s!.*Interna: (.+)!$1!; 
			$public_note =~ s!(.+); Bez.: \d[^;]*!$1!; # ID=6685427 
			
			if ($public_note =~m/(Digitalisierung|Langzeitarchivierung|Volltext)\; Info: kostenfrei/i # ID=6521146 ; Projekt Digitalis, Bsp.: Achenbach Berggesetzgebung
			    or $public_note =~m/Info: kostenfrei; Bezugswerk: Volltext/i # ID=6625319
			    or $public_note =~m/Open Access/) { # ID=6693843  
			    
			    my $description = "Volltext";
			    my $url         = $url;
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

			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/(Verlag.*); Info: kostenfrei/i){
			    my $description = $1;
			    my $url         = $url;
			    my $access      = "g"; # green
			    
			    if ($url =~m/^https?:\/\/dx\.doi\.org\//) {  # Bsp.: ID=6683669
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
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/(Resolving-System|URN)/) { # Bsp.: TI=Bayerische Bauordnung 2008 ; ID=6685427 
			    my $description = "Volltext";
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/^Zus.*tzliche Angaben$/i) { # Bsp.: HBZID=HT013697253, HBZID=HT016192826 (falsch kodierter Umlaut)

			    $url_done_ref->{$url} = 1;			

			    next; # Link auf Objektbaum ueberspringen
			}
			elsif ($public_note =~m/Link-Text: C\;/) { # Bsp.: ID=6713163
			    $url_done_ref->{$url} = 1;			    
			    next; # Link auf Coverscans ueberspringen
			}
			elsif ($public_note =~m/ebooks.ciando.com/) { # Bsp.: ID=6713163
			    $url_done_ref->{$url} = 1;			
			    next; # PKN: Link auf E-Books von Ciando ueberspringen
			}
			elsif ($public_note =~m/Bez.: 2/) { # Bsp.: ID=inst001:81361
			    # Linktext "Bez.: 2" durch URL ersetzen
			    
			    my $description = $url;
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/EZB/) { # Bsp.: ID=6348154 (Hallische Jahrbuecher) -> gruen ; ID=6111996 (Bibliotheksdienst) -> rot
			    # Nicht implementiert: EZB-Link fuer E-Journals der KMB ueberspringen
			    # Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
			    # Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen
			    
			    my $description = "Elektronische Zeitschrift im Volltext";
			    my $url         = $url;
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

			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/DBIS/ && $pmult > 1) { # Bsp.: TI=Bayerische Bauordnung 2008
			    # 2. DBIS-Link loeschen, da Titel evtl. nicht in die DBIS-Sicht der USB aufgenommen wurde
			    $url_done_ref->{$url} = 1;			
			    next;
			}
			elsif ($public_note =~m/^Kontakt/ && $url =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
			    if (!$have_toc){
				$record_ref->{fields}{'4110'} = [{
				    mult     => 1,
				    subfield => '',
				    content  => $url,
								 }];
			    }
			    $have_toc = 1;
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/^Inhaltsverzeichnis/ && $url =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
			    if (!$have_toc){
				$record_ref->{fields}{'4110'} = [{
				    mult     => 1,
				    subfield => '',
				    content  => $url,
								 }];
			    }
			    $have_toc = 1;

			    $url_done_ref->{$url} = 1;			
			}		
			else {
			    my $description = $public_note;
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;			
			}
		    }
		}
		# Keine Public note
		else {
		    my $access = "f"; # zunaechst unbestimmt zugreifbar. Spaeter ggf. postprocessing bei Zugehoerigkeit zu einem Paket
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => $access,
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Volltext",
			
		    };
		    
		    $url_done_ref->{$url} = 1;			
		}
		# elsif (defined $field1209_ref->{$item_ref->{mult}} && $field1209_ref->{$item_ref->{mult}} =~m/^fzo$/){
		#     my $description = "Volltext";
		#     my $access      = "g"; # green
		    
		#     push @{$record_ref->{fields}{'4662'}}, {
		# 	mult     => $mult,
		# 	subfield => $access,
		# 	content  => $url,
		#     };
		    
		#     push @{$record_ref->{fields}{'4663'}}, {
		# 	mult     => $mult,
		# 	subfield => '',
		# 	content  => $description,
		#     };
		    
		#     $url_done_ref->{$url} = 1;
		# }
	    }
	    elsif (defined $portfolio_ref->{$pmult}{'2'}){ # Dynamic URL (OpenURL Resolver) available
		my $url = $portfolio_ref->{$pmult}{'2'};
		$url = decode_entities($url);
		
		my $mult        = $mult_ref->{'4662'}++;
		my $description = "Zum Volltext";
		my $access      = "f";
		
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
		
		$url_done_ref->{$url} = 1;
		
	    }
	    # Else build URL-Resolver URL with portfolio_id
	    else {
		my $portfolio_id = $portfolio_ref->{$pmult}{'a'};

		if ($portfolio_id){
		    my $url="https://eu04.alma.exlibrisgroup.com/view/uresolver/49HBZ_UBK/openurl?u.ignore_date_coverage=true&portfolio_pid=$portfolio_id&Force_direct=true";
		    
		    my $mult        = $mult_ref->{'4662'}++;
		    my $description = "Zum Volltext";
		    my $access      = "f";
		    
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
		    
		    $url_done_ref->{$url} = 1;
		}
	    }
	}
    }
    
    # Jetzt Analyse der URLs in 856
    
    if (defined $fields_ref->{'0856'}){

	# Umorganisieren nach Mult-Gruppe
	my $url_info_ref = {};
	
	foreach my $item_ref (@{$fields_ref->{'0856'}}){
	    $url_info_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content};
	    $url_info_ref->{$item_ref->{mult}}{'ind'} = $item_ref->{ind}; 
	    
	}

	foreach my $umult (sort keys %$url_info_ref){
	    if (defined $url_info_ref->{$umult}{'u'}){
		my $url  = $url_info_ref->{$umult}{'u'};
		my $mult = $mult_ref->{'4662'}++;
		my $ind  = $url_info_ref->{$umult}{'ind'};
		
		# URL schon ueber Portfolios verarbeitet? Dann ignorieren
		next if (defined $url_done_ref->{$url} && $url_done_ref->{$url});
		
		# Hochschulschriften
		if ($url =~m/^https?:\/\/kups\.ub\.uni\-koeln\.de/){
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'g', # green
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Elektronische Hochschulschrift im Volltext",
		    };
		}
		# Lokale Digitalisate
		elsif ($url =~m/^https?:\/\/www\.ub\.uni\-koeln\.de\/permalink/){
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => 'f', # fulltext = green or yellow. Es gibt auch gelbe Objekte ID=6612903
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => "Volltext",
		    };
		}
		# EZB Zeitschriften
		elsif ($url =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/ezeit\//
		    ){ # Bsp.: ISSN=1572-8358
		    
		    $have_ezb = 1;
		    
		    my $description = "Elektronische Zeitschrift im Volltext";
		    my $access      = " "; # Default: unknown

		    # Wie kann man hier green und yellow unterscheiden?

		    # Lokal vorhanden Bsp.: ID=Rendite (Hallische Jahrbuecher / Intelligenzblatt)
		    # Dann: EZB-Frontdoor umgehen, falls Permalink der USB existiert

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
		elsif ($url =~m/^https?:\/\/www\.bibliothek\.uni\-regensburg\.de\/dbinfo/
		       or $url =~m/^https?:\/\/rzblx10\.uni\-regensburg\.de\/dbinfo/
		       or $url =~m/^https?:\/\/dbis\.uni\-regensburg\.de\//
		       or $url =~m/^https?:\/\/dbis\.ur\.de\//
		       or $url =~m/https?:\/\/www\.ub\.uni\-koeln\.de\/usbportal\?service=dbinfo/){ # Bsp.: TI=wiso-net
		    $have_dbis = 1;
		    
		    my $description = "Datenbankrecherche starten";
		    my $access      = "y"; # yellow
		    
		    # if ($titleid == 5255340 && $url =~m/id=1061/){
		    # 	$description = "MLA directory of periodicals";
		    # }
		    # elsif ($titleid == 5255340 && $url =~m/id=76/){
		    # 	$description = "MLA international bibliography";
		    # }
		    
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
		elsif ($url =~m/www\.gbv\.de\/dms\/|www\.ulb\.tu-darmstadt\.de\/tocs\//) { # Bsp.: IB=978-3-7723-7449-4, ID=6262313
		    if (!$have_toc){
			$record_ref->{fields}{'4110'} = [{
			    mult     => 1,
			    subfield => '',
			    content  => $url,
							 }];
		    }
		    $have_toc = 1;		    
		}

		# Hinweise aus 856$z
		elsif (defined $url_info_ref->{$umult}{'z'}){
		    my $public_note = $url_info_ref->{$umult}{'z'};
		    my $material = $url_info_ref->{$umult}{'z'};

		    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4110
		    if ($public_note =~m/Inhaltsverzeichnis|Inh\.\-Verz\./i || $material =~m/Inhaltsverz/i ){ # Inhaltsverzeichnisse
			
			# Falls bereits ein Link "Inhaltsverzeichnis" existiert, nur insgesamt einen Link berücksichtigen
			if ($url =~m/hbz\-nrw\.de/){ # hbz-Inhaltsverzeichnis hat Vorrang, z.B. ID=7741043
			    $record_ref->{fields}{'4110'} = [{
				mult     => 1,
				subfield => '',
				content  => $url,
							     }];
			}
			elsif (!$have_toc){
			    $record_ref->{fields}{'4110'} = [{
				mult     => 1,
				subfield => '',
				content  => $url,
							     }];
			}		
			$have_toc = 1;
		    }
		    elsif ($public_note =~m/(Nationallizenz)/i){
			my $description = "E-Book im Volltext über Nationallizenz";
			my $access      = "n"; # Nationallizenz
			
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
		    elsif ($ind =~m/[01]$/ && $public_note =~m/(digitalisiert|kostenfrei|kostenlos|DOAB|Frei zugänglich|Full text online|Freier Zugriff|Frei zugänglich|Gratis|kostenloser Download|lizenzfrei|Open ?Access)/i && $material =~m/(digitalisiert|Digitalisat|e-?book|PDF|Online-Ausgabe|Online-Zugang|Online-Version|Volltext)/i && ! $material =~m/(Verlag)/i){
			my $description = "E-Book im Volltext";
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
		    elsif ($ind =~m/[01]$/ && $public_note =~m/(lizenzpflichtig)/i && $material =~m/(e-?book|PDF|Online-Ausgabe|Online-Zugang|Online-Version|Volltext)/i && ! $material =~m/(Verlag)/){
		    	my $description = "E-Book im Volltext";
		    	my $access      = "y"; # yellow
			
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
		    else {
			$public_note =~ s!.*Interna: (.+)!$1!; 
			$public_note =~ s!(.+); Bez.: \d[^;]*!$1!; # ID=6685427 
			
			if ($ind =~m/[01]$/ &&  ( $public_note =~m/(Digitalisierung|Langzeitarchivierung|Volltext)\; Info: kostenfrei/i # ID=6521146 ; Projekt Digitalis, Bsp.: Achenbach Berggesetzgebung
			    or $public_note =~m/Info: kostenfrei; Bezugswerk: Volltext/i # ID=6625319
			    or $public_note =~m/Open Access/ ) ) { # ID=6693843  
			    
			    my $description = "Volltext";
			    my $url         = $url;
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

			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/(Verlag.*); Info: kostenfrei/i){
			    my $description = $1;
			    my $url         = $url;
			    my $access      = "g"; # green
			    
			    if ($url =~m/^https?:\/\/dx\.doi\.org\//) {  # Bsp.: ID=6683669
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
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/(Resolving-System)/) { # Bsp.: TI=Bayerische Bauordnung 2008 ; ID=6685427 
			    my $description = "Volltext";
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/^Zus.*tzliche Angaben$/i) { # Bsp.: HBZID=HT013697253, HBZID=HT016192826 (falsch kodierter Umlaut)

			    $url_done_ref->{$url} = 1;			

			    next; # Link auf Objektbaum ueberspringen
			}
			elsif ($public_note =~m/Link-Text: C\;/) { # Bsp.: ID=6713163
			    $url_done_ref->{$url} = 1;			    
			    next; # Link auf Coverscans ueberspringen
			}
			elsif ($public_note =~m/ebooks.ciando.com/) { # Bsp.: ID=6713163
			    $url_done_ref->{$url} = 1;			
			    next; # PKN: Link auf E-Books von Ciando ueberspringen
			}
			elsif ($public_note =~m/Bez.: 2/) { # Bsp.: ID=inst001:81361
			    # Linktext "Bez.: 2" durch URL ersetzen
			    
			    my $description = $url;
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/EZB/) { # Bsp.: ID=6348154 (Hallische Jahrbuecher) -> gruen ; ID=6111996 (Bibliotheksdienst) -> rot
			    # Nicht implementiert: EZB-Link fuer E-Journals der KMB ueberspringen
			    # Nicht implementiert: EZB-Frontdoor-Link durch Permalink zum ejinfo-Service der USB ersetzen
			    # Gff. spaeter EZB-Frontdoor-Link auf EZB-Integration in OpenBib umbiegen
			    
			    my $description = "Elektronische Zeitschrift im Volltext";
			    my $url         = $url;
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

			    $url_done_ref->{$url} = 1;						    
			}
			elsif ($public_note =~m/DBIS/ && $umult > 1) { # Bsp.: TI=Bayerische Bauordnung 2008
			    # 2. DBIS-Link loeschen, da Titel evtl. nicht in die DBIS-Sicht der USB aufgenommen wurde
			    $url_done_ref->{$url} = 1;			
			    next;
			}
			elsif ($public_note =~m/^Kontakt/ && $url =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
			    if (!$have_toc){
				$record_ref->{fields}{'4110'} = [{
				    mult     => 1,
				    subfield => '',
				    content  => $url,
								 }];
			    }
			    $have_toc = 1;
			    
			    $url_done_ref->{$url} = 1;			
			}
			elsif ($public_note =~m/^Inhaltsverzeichnis/ && $url =~m/scans\.hebis\.de.*toc\.pdf/) { # ID=6938417
			    if (!$have_toc){
				$record_ref->{fields}{'4110'} = [{
				    mult     => 1,
				    subfield => '',
				    content  => $url,
								 }];
			    }
			    $have_toc = 1;

			    $url_done_ref->{$url} = 1;			
			}		
			else {
			    my $description = $public_note;
			    my $url         = $url;
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
			    
			    $url_done_ref->{$url} = 1;			
			}
		    }
		}
		# Beschreibung aus 856$x wg. falsch erfasster valider Inhalte als Non-Public-Note in $x
		elsif (defined $url_info_ref->{$umult}{'x'}){
		    my $description = $url_info_ref->{$umult}{'x'};

		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => '',
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $description,
			
		    };
		    
		    $url_done_ref->{$url} = 1;			
		}		
		# Sonst UrL als Beschreibung
		else {
		    push @{$record_ref->{fields}{'4662'}}, {
			mult     => $mult,
			subfield => '',
			content  => $url,
		    };
		    
		    push @{$record_ref->{fields}{'4663'}}, {
			mult     => $mult,
			subfield => '',
			content  => $url,
			
		    };
		    
		    $url_done_ref->{$url} = 1;			
		}		
	    }
	}
    }
    
    my @pakete = ();

    my $paketstring = "";
    
    if (defined $fields_ref->{'0912'} || defined $fields_ref->{'0962'}){
	foreach my $item_ref (@{$fields_ref->{'0912'}}){
	    if ($item_ref->{'subfield'} eq "a"){
		push @pakete, $item_ref->{'content'};
	    }
	}
	foreach my $item_ref (@{$fields_ref->{'0962'}}){
	    if ($item_ref->{'subfield'} eq "e"){
		push @pakete, $item_ref->{'content'};
	    }
	}

	if (@pakete){
	    $paketstring = join('; ',@pakete);
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

    if (defined $fields_ref->{'0020'}){
	$has_isbn = 1;
    }

    my $restricted_access = 0;

    if (defined $fields_ref->{'0998'}){
	foreach my $item_ref (@{$fields_ref->{'0998'}}){
	    if ($item_ref->{'subfield'} eq "z" && $item_ref->{content} =~m/Zugriff nur im Hochschulnetz/){
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
		($has_isbn or $paketstring=~m/(oecd|ZDB-14-DLO|ZDB-57-DVR|ZDB-57-DSG|ZDB-57-DFS)$/)){ # ggf. Bedingung ergaenzen: Hat ISBN der Paralellausgabe in '1586', '1587', '1588', '1590', '1591', '1592', '1594', '1595', '1596'
		$description = "E-Book im Volltext";
		$fields_ref->{'4663'}[$i]{content} = $description;
	    }

	    if ($description =~m/Volltext/ && $restricted_access){
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
	    }
	    # Auswertung Paketinformatione entsprechend:
	    # https://intern.ub.uni-koeln.de/usbwiki/index.php/Anreicherung_von_IMX-Importdateien
	    # OA via ZDB-2-SOB, ZDB-23-GOA ueberschreiben alle anderen Paketinfos
	    elsif ($paketstring =~m/(ZDB-2-SOB|ZDB-23-GOA)/) { # z.B. ID=7807222, ID=6813324
		$fields_ref->{'4662'}[$i]{subfield} = "g"; # green
		$fields_ref->{'4663'}[$i]{content}  = "E-Book im Volltext";
	    }
	    elsif ($paketstring =~m/(ZDB-57-DVR|ZDB-57-DSG|ZDB-57-DFS)/){ # Freie E-Books aus dem Projekt Digi20
		$fields_ref->{'4662'}[$i]{subfield} = "g"; # green Bsp.: ID=6822919		
	    }
	    elsif ($paketstring =~m/(ZDB-2-SWI|ZDB-2-SNA|ZDB-2-STI|ZDB-2-SGR|ZDB-2-SGRSpringer|ZDB-2-SEP|ZDB-2-SBE|ZDB-2-CMS|ZDB-2-PHA|ZDB-2-SMA|ZDB-2-MGE|ZDB-2-SZR|ZDB-2-BUM|ZDB-2-ECF|ZDB-2-SCS|ZDB-2-ESA|ZDB-5-WEB|ZDB-5-WMS|ZDB-5-WMW|ZDB-13-SOC|ZDB-14-DLO|ZDB-18-BEO|ZDB-18-BOH|ZDB-18-BST|ZDB-15-ACM|ZDB-16-Hanser-EBA|hbzebo_ebahanser|ZDB-18-Nomos-NRW|ZDB-18-Nomos-VDI-NRW|hbzebo_nrwnomos|ZDB-149-HCB|ZDB-162-Bloom-EBA|hbz_ebabloomsbury|ZDB-605-Preselect|hbzebo_preselect|ZDB-196-Meiner-EBA|hbzebo_ebameiner|ZDB-23-DGG|ZDB-98-IGB|ZDB-23-DGG-eba|ZDB-54-Duncker-EBA|hbzebo_ebaduncker|ZDB-2-BSP|ZDB-2-SBL|ZDB-2-BUM|ZDB-2-CMS|ZDB-2-SCS|ZDB-2-EES|ZDB-2-ECF|ZDB-2-EDA|ZDB-2-ENE|ZDB-2-ENG|ZDB-2-HTY|ZDB-2-INR|ZDB-2-LCR|ZDB-2-LCM|ZDB-2-SMA|ZDB-2-SME|ZDB-2-PHA|ZDB-2-POS|ZDB-2-CWD|ZDB-2-REP|ZDB-2-SLS|ZDB-41-UTB-EBA|ZDB-7-taylorfra-EBA|ZDB-71-Narr-EBA)/){
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
		$fields_ref->{'4663'}[$i]{content}  = "E-Book im Volltext" if ($description !~m/Verlag/);
		
	    }
	    elsif ($paketstring =~m/(ZDB-185-STD|ZDB-185-SDI)/){ # Statista-Dossiers
		$fields_ref->{'4662'}[$i]{subfield} = "y"; # yellow
		$fields_ref->{'4663'}[$i]{content}  = "Dossier im Volltext";
	    }
	    elsif ($paketstring =~m/ZDB-101-VTB/){ # video2brain
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
