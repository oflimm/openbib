#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use Business::ISBN;
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::VirtualSearch::Util;

#####################################################################
## get_aut_ans_by_idn(autidn,...): Gebe zu autidn geh"oerende
##                                 Ansetzungsform aus Autorenstammsatz 
##                                 aus
##
## autidn: IDN des Autorenstammsatzes

sub get_aut_ans_by_idn {
    my ($autidn,$dbh)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from aut where id = ? and category=0001";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);
    
    my $res=$request->fetchrow_hashref;
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $ans="Unbekannt";
    if (defined $res->{content}) {
        $ans = decode_utf8($res->{content});
    }

    $request->finish();

    return $ans;
}

sub get_aut_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $autidn            = exists $arg_ref->{autidn}
        ? $arg_ref->{autidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $normset_ref={};

    $normset_ref->{id      } = $autidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from aut where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "P".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=2";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{P5000}}, {
        content => $res->{conncount},
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    return $normset_ref;
}

sub get_kor_ans_by_idn {
    my ($koridn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from kor where id = ? and category=0001";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    my $ans;
    if ($res->{content}) {
        $ans=decode_utf8($res->{content});
    }

    $request->finish();

    return $ans;
}

sub get_kor_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $koridn            = exists $arg_ref->{koridn}
        ? $arg_ref->{koridn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $normset_ref={};

    $normset_ref->{id      } = $koridn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from kor where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "C".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=3";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{C5000}}, {
        content => $res->{conncount},
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    
    $request->finish();

    return $normset_ref;
}

sub get_swt_ans_by_idn {
    my ($swtidn,$dbh)=@_;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from swt where id = ? and category=0001";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
    
    my $schlagwort;
  
    if ($res->{content}) {
        $schlagwort = decode_utf8($res->{content});
    }
  
    $request->finish();
  
    return $schlagwort;
}

sub get_swt_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $swtidn            = exists $arg_ref->{swtidn}
        ? $arg_ref->{swtidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $normset_ref={};

    $normset_ref->{id      } = $swtidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from swt where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "S".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=4";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{S5000}}, {
        content => $res->{conncount},
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    return $normset_ref;
}

sub get_not_ans_by_idn {
    my ($notidn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);
    
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from notation where id = ? and category=0001";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
    
    my $notation;
    
    if ($res->{content}) {
        $notation = decode_utf8($res->{content});
    }

    $request->finish();

    return $notation;
}

#####################################################################
## get_not_set_by_idn(notidn,...): Gebe zu notidn gehoerenden
##                                 Notationsstammsatz + Anzahl
##                                 verknuepfter Titel aus
##
## notidn: IDN des Notationsstammsatzes

sub get_not_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $notidn            = exists $arg_ref->{notidn}
        ? $arg_ref->{notidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $normset_ref={};

    $normset_ref->{id      } = $notidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
    
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from notation where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "N".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=5";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{N5000}}, {
        content => $res->{conncount},
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    return $normset_ref;
}

sub get_tit_listitem_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn            = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $use_titlistitem_table=1;

    if ($database eq "inst006"){
        $use_titlistitem_table=1;
    }

    $logger->debug("Getting ID $titidn");
    
    my $listitem_ref={};
    
    # Titel-ID und zugehoerige Datenbank setzen
    
    $listitem_ref->{id      } = $titidn;
    $listitem_ref->{database} = $database;
    
    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime  = new Benchmark;
    }

    if ($use_titlistitem_table) {
        # Bestimmung des Satzes
        my $request=$dbh->prepare("select listitem from titlistitem where id = ?") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        if (my $res=$request->fetchrow_hashref){
            my $titlistitem     = $res->{listitem};
            
            $logger->debug("Storable::listitem: $titlistitem");

            my $encoding_type="hex";

            if    ($encoding_type eq "base64"){
                $titlistitem = MIME::Base64::decode($titlistitem);
            }
            elsif ($encoding_type eq "hex"){
                $titlistitem = pack "H*",$titlistitem;
            }
            elsif ($encoding_type eq "uu"){
                $titlistitem = unpack "u",$titlistitem;
            }

            my %titlistitem = %{ Storable::thaw($titlistitem) };
            
            $logger->debug("TitlistitemYAML: ".YAML::Dump(\%titlistitem));
            %$listitem_ref=(%$listitem_ref,%titlistitem);

        }
    }
    else {
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime  = new Benchmark;
        }

        # Bestimmung der Titelinformationen
        my $request=$dbh->prepare("select category,indicator,content from tit where id = ? and category in (0310,0331,0403,0412,0424,0425,0451,0455,1203,0089)") or $logger->error($DBI::errstr);
        #    my $request=$dbh->prepare("select category,indicator,content from tit where id = ? ") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "T".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });
            
            push @{$listitem_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        
        $logger->debug("Titel: ".YAML::Dump($listitem_ref));
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Titelinformationen : ist ".timestr($timeall));
        }
        
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        # Bestimmung der Exemplarinformationen
        $request=$dbh->prepare("select mex.category,mex.indicator,mex.content from mex,conn where conn.sourceid = ? and conn.targetid=mex.id and conn.sourcetype=1 and conn.targettype=6 and mex.category=0014") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "X".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });
            
            push @{$listitem_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Exemplarinformationen : ist ".timestr($timeall));
        }
        
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my @autkor=();
        
        # Bestimmung der Verfasser, Personen
        #
        # Bemerkung zur Performance: Mit Profiling (Devel::SmallProf) wurde
        # festgestellt, dass die Bestimmung der Information ueber conn
        # und get_*_ans_by_idn durchschnittlich ungefaehr um den Faktor 30-50
        # schneller ist als ein join ueber conn und aut (!)
        $request=$dbh->prepare("select targetid,category,supplement from conn where sourceid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "P".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $targetid  =        decode_utf8($res->{targetid});
            
            my $supplement="";
            if ($res->{supplement}){
                $supplement=" ".decode_utf8($res->{supplement});
            }
            
            my $content=get_aut_ans_by_idn($targetid,$dbh).$supplement;
            
            # Kategorieweise Abspeichern
            push @{$listitem_ref->{$category}}, {
                id      => $targetid,
                type    => 'aut',
                content => $content,
            };
            
            # Gemeinsam Abspeichern
            push @autkor, $content;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Verfasserinformationen : ist ".timestr($timeall));
        }
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        # Bestimmung der Urheber, Koerperschaften
        $request=$dbh->prepare("select targetid,category,supplement from conn where sourceid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "C".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $targetid  =        decode_utf8($res->{targetid});
            
            my $supplement="";
            if ($res->{supplement}){
                $supplement.=" ".decode_utf8($res->{supplement});
            }
            
            my $content=get_kor_ans_by_idn($targetid,$dbh).$supplement;
            
            # Kategorieweise Abspeichern
            push @{$listitem_ref->{$category}}, {
                id      => $targetid,
                type    => 'kor',
                content => $content,
            };
            
            # Gemeinsam Abspeichern
            push @autkor, $content;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Koerperschaftsinformationen : ist ".timestr($timeall));
        }
        
        # Zusammenfassen von autkor fuer die Sortierung
        
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        
        $request->finish();
        
        $logger->debug("Vor Sonderbehandlung: ".YAML::Dump($listitem_ref));

        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Ist nichts zu tun
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        if (!exists $listitem_ref->{T0331}) {
            # UnterFall 2.1:
            if (exists $listitem_ref->{'T0089'}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content};
            }
            # Unterfall 2.2:
            elsif (exists $listitem_ref->{T0455}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content};
            }
            # Unterfall 2.3:
            elsif (exists $listitem_ref->{T0451}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0451}[0]{content};
            }
            # Unterfall 2.4:
            elsif (exists $listitem_ref->{T1203}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T1203}[0]{content};
            } else {
                $listitem_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
            }
        }

        # Bestimmung der Zaehlung

        # Fall 1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl
        #
        # Fall 2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl

        # Fall 1:
        if (exists $listitem_ref->{'T0089'}) {
            $listitem_ref->{T5100}= [
                {
                    content => $listitem_ref->{T0089}[0]{content}
                }
            ];
        }
        # Fall 2:
        elsif (exists $listitem_ref->{T0455}) {
            $listitem_ref->{T5100}= [
                {
                    content => $listitem_ref->{T0455}[0]{content}
                }
            ];
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der HST-Ueberordnungsinformationen : ist ".timestr($timeall));
        }

                if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        # Bestimmung der Popularitaet des Titels
        $request=$dbh->prepare("select idcount from popularity where id=?") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            $listitem_ref->{popularity} = $res->{idcount};
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Popularitaetsinformation : ist ".timestr($timeall));
        }

    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        my $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung der gesamten Informationen         : ist ".timestr($timeall));
    }

    $logger->debug(YAML::Dump($listitem_ref));
    return $listitem_ref;
}

sub print_tit_list_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $itemlist_ref      = exists $arg_ref->{itemlist_ref}
        ? $arg_ref->{itemlist_ref}      : undef;
    my $targetdbinfo_ref  = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $queryoptions_ref  = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hits              = exists $arg_ref->{hits}
        ? $arg_ref->{hits}              : -1;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : 50;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $template          = exists $arg_ref->{template}
        ? $arg_ref->{template}          : 'tt_search_showtitlist_tname';
    my $location          = exists $arg_ref->{location}
        ? $arg_ref->{location}          : 'search_loc';
    my $lang              = exists $arg_ref->{lang}
        ? $arg_ref->{lang}              : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $query=Apache::Request->instance($r);

    my @itemlist=@$itemlist_ref;

    # Navigationselemente erzeugen
    my %args=$r->args;
    delete $args{offset};
    delete $args{hitrange};
    my @args=();
    while (my ($key,$value)=each %args) {
        push @args,"$key=$value";
    }

    my $baseurl="http://$config->{servername}$config->{$location}?".join(";",@args);

    my @nav=();

    if ($hitrange > 0) {
        for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
            my $active=0;

            if ($i == $offset) {
                $active=1;
            }

            my $item={
		start  => $i+1,
		end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
		url    => $baseurl.";hitrange=$hitrange;offset=$i",
		active => $active,
            };
            push @nav,$item;
        }
    }

    # TT-Data erzeugen
    my $ttdata={
        lang           => $lang,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,
	      
        database       => $database,

        hits           => $hits,
	      
        sessionID      => $sessionID,
	      
        targetdbinfo   => $targetdbinfo_ref,
        itemlist       => \@itemlist,

        baseurl        => $baseurl,

        qopts          => $queryoptions_ref,
        query          => $query,
        hitrange       => $hitrange,
        offset         => $offset,
        nav            => \@nav,

        config         => $config,
        msg            => $msg,
    };
  
    OpenBib::Common::Util::print_page($config->{$template},$ttdata,$r);
#    OpenBib::Common::Util::print_page($config->{tt_search_showtitlist_tname},$ttdata,$r);

    return;
}

sub print_tit_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn             = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}             : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $session            = exists $arg_ref->{session}
        ? $arg_ref->{session}            : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $queryoptions_ref   = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}   : undef;
    my $searchquery_ref    = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref}    : undef;
    my $queryid            = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}            : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $stylesheet         = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}         : undef;
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;
    my $no_log             = exists $arg_ref->{no_log}
        ? $arg_ref->{no_log}             : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    my $user   = new OpenBib::User();

    my $userid        = $user->get_userid_of_session($session->{ID});
    my $loginname     = $user->get_username_for_userid($userid);
    my $logintargetdb = $user->get_targetdb_of_session($session->{ID});

    my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
        titidn             => $titidn,
        dbh                => $dbh,
        targetdbinfo_ref   => $targetdbinfo_ref,
        targetcircinfo_ref => $targetcircinfo_ref,
        database           => $database,
    });

    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
        sessiondbh => $session->{dbh},
        database   => $database,
        titidn     => $titidn,
        sessionID  => $session->{ID},
    });

    my $poolname=$targetdbinfo_ref->{dbnames}{$database};

    # TT-Data erzeugen
    my $ttdata={
        view        => $view,
        stylesheet  => $stylesheet,
        database    => $database,
        poolname    => $poolname,
        prevurl     => $prevurl,
        nexturl     => $nexturl,
        qopts       => $queryoptions_ref,
        queryid     => $queryid,
        sessionID   => $session->{ID},
        titidn      => $titidn,
        normset     => $normset,
        mexnormset  => $mexnormset,
        circset     => $circset,
        searchquery => $searchquery_ref,
        activefeed  => $config->get_activefeeds_of_db($database),

        user          => $user,
        loginname     => $loginname,
        logintargetdb => $logintargetdb,

        highlightquery    => \&highlightquery,
        normset2bibtex    => \&OpenBib::Common::Util::normset2bibtex,
        normset2bibsonomy => \&OpenBib::Common::Util::normset2bibsonomy,

        config      => $config,
        msg         => $msg,
    };

    OpenBib::Common::Util::print_page($config->{tt_search_showtitset_tname},$ttdata,$r);

    # Log Event

    my $isbn;

    if (exists $normset->{T0540}[0]{content}){
        $isbn = $normset->{T0540}[0]{content};
        $isbn =~s/ //g;
        $isbn =~s/-//g;
        $isbn =~s/X/x/g;
    }

    if (!$no_log){
        $session->log_event({
            type      => 10,
            content   => {
                id       => $titidn,
                database => $database,
                isbn     => $isbn,
            },
            serialize => 1,
        });
    }
    
    return;
}

sub print_mult_tit_set_by_idn { 
    my ($arg_ref) = @_;

    # Set defaults
    my $titidns_ref        = exists $arg_ref->{titidns_ref}
        ? $arg_ref->{titidns_ref}        : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $targetdbinfo_ref = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref} : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $queryoptions_ref   = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $stylesheet         = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}         : undef;
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my @titsets=();

    foreach my $titidn (@$titidns_ref) {
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $titidn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            database           => $database,
        });
        
        my $thisset={
            titidn     => $titidn,
            normset    => $normset,
            mexnormset => $mexnormset,
            circset    => $circset,
        };
        push @titsets, $thisset;
    }

    my $poolname=$targetdbinfo_ref->{sigel}{
        $targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        qopts      => $queryoptions_ref,
        sessionID  => $sessionID,
        titsets    => \@titsets,

        config     => $config,
        msg        => $msg,
    };
  
    OpenBib::Common::Util::print_page($config->{tt_search_showmulttitset_tname},$ttdata,$r);

    return;
}

sub get_tit_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn             = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}             : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my @normset=();

    my $normset_ref={};

    $normset_ref->{id      } = $titidn;
    $normset_ref->{database} = $database;

    # Titelkategorien
    {

        my ($atime,$btime,$timeall)=(0,0,0);

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select * from tit where id = ?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category  = "T".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });

            push @{$normset_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        $request->finish();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Verknuepfte Normdaten
    {
        my ($atime,$btime,$timeall)=(0,0,0);

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category   = "T".sprintf "%04d",$res->{category };
            my $targetid   =        decode_utf8($res->{targetid  });
            my $targettype =                    $res->{targettype};
            my $supplement =        decode_utf8($res->{supplement});

	    # Korrektes UTF-8 Encoding Flag wird in get_*_ans_*
	    # vorgenommen

            my $content    =
                ($targettype == 2 )?get_aut_ans_by_idn($targetid,$dbh):
                ($targettype == 3 )?get_kor_ans_by_idn($targetid,$dbh):
                ($targettype == 4 )?get_swt_ans_by_idn($targetid,$dbh):
                ($targettype == 5 )?get_not_ans_by_idn($targetid,$dbh):'Error';

            push @{$normset_ref->{$category}}, {
                id         => $targetid,
                content    => $content,
                supplement => $supplement,
            };
        }
        $request->finish();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Verknuepfte Titel
    {
        my ($atime,$btime,$timeall)=(0,0,0);

        my $reqstring;
        my $request;
        my $res;
        
        # Unterordnungen
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
        $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5001}}, {
                content => $res->{conncount},
            };
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }

        # Ueberordnungen
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
        $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5002}}, {
                content => $res->{conncount},
            };
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }


        $request->finish();
    }

    # Exemplardaten
    my @mexnormset=();
    {

        my $reqstring="select distinct targetid from conn where sourceid= ? and sourcetype=1 and targettype=6";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        my @verknmex=();
        while (my $res=$request->fetchrow_hashref){
            push @verknmex, decode_utf8($res->{targetid});
        }
        $request->finish();

        if ($#verknmex >= 0) {
            foreach my $mexsatz (@verknmex) {
                push @mexnormset, get_mex_set_by_idn({
                    mexidn             => $mexsatz,
                    dbh                => $dbh,
                    targetdbinfo_ref   => $targetdbinfo_ref,
                    targetcircinfo_ref => $targetcircinfo_ref,
                    database           => $database,
                });
            }
        }

    }

    # Ausleihinformationen der Exemplare
    my @circexemplarliste = ();
    {
        my $circexlist=undef;
        
        if (exists $targetcircinfo_ref->{$database}{circ}) {
            
            my $circid=(exists $normset_ref->{'T0001'}[0]{content} && $normset_ref->{'T0001'}[0]{content} > 0 && $normset_ref->{'T0001'}[0]{content} != $titidn )?$normset_ref->{'T0001'}[0]{content}:$titidn;
            
            $logger->debug("Katkey: $titidn - Circ-ID: $circid");

            eval {
                
                my $soap = SOAP::Lite
                    -> uri("urn:/MediaStatus")
                        -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
                my $result = $soap->get_mediastatus(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(katkey   => $circid)->type('string'),
                        SOAP::Data->name(database => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };
            
            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
	    }

        }
        
        # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
        # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
        # titelbasierten Exemplardaten
        
        if (defined($circexlist)) {
            @circexemplarliste = @{$circexlist};
        }
        
        if (exists $targetcircinfo_ref->{$database}{circ}
                && $#circexemplarliste >= 0) {
            for (my $i=0; $i <= $#circexemplarliste; $i++) {
                
                my $bibliothek="-";
                my $sigel=$targetdbinfo_ref->{dbases}{$database};
                
                if (length($sigel)>0) {
                    if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
                        $bibliothek=$targetdbinfo_ref->{sigel}{$sigel};
                    }
                    else {
                        $bibliothek="($sigel)";
                    }
                }
                else {
                    if (exists $targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}}) {
                        $bibliothek=$targetdbinfo_ref->{sigel}{
                            $targetdbinfo_ref->{dbases}{$database}};
                    }
                }
                
                my $bibinfourl=$targetdbinfo_ref->{bibinfo}{
                    $targetdbinfo_ref->{dbases}{$database}};
                
                $circexemplarliste[$i]{'Bibliothek'} = $bibliothek;
                $circexemplarliste[$i]{'Bibinfourl'} = $bibinfourl;
                $circexemplarliste[$i]{'Ausleihurl'} = $targetcircinfo_ref->{$database}{circurl};
            }
        }
        else {
            @circexemplarliste=();
        }
    }

    # Anreicherung mit zentralen Enrichmentdaten
    {
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my @isbn_refs = ();
        push @isbn_refs, @{$normset_ref->{T0540}} if (exists $normset_ref->{T0540});
        push @isbn_refs, @{$normset_ref->{T0553}} if (exists $normset_ref->{T0553});

        $logger->debug(YAML::Dump(\@isbn_refs));
        
        if (@isbn_refs){
            my @isbn_refs_tmp = ();
            # Normierung auf ISBN-13
            
            foreach my $isbn_ref (@isbn_refs){
                my $thisisbn = $isbn_ref->{content};
                
                # Alternative ISBN zur Rechercheanrei
                my $isbn     = Business::ISBN->new($thisisbn);

                if (defined $isbn && $isbn->is_valid){
                    $thisisbn = $isbn->as_isbn13->as_string;
                }

                push @isbn_refs_tmp, OpenBib::Common::Util::grundform({
                    category => '0540',
                    content  => $thisisbn,
                });

            }
            
            # Dubletten Bereinigen
            my %seen_isbns = ();
            
            @isbn_refs = grep { ! $seen_isbns{$_} ++ } @isbn_refs_tmp;

            $logger->debug(YAML::Dump(\@isbn_refs));
        
            foreach my $isbn (@isbn_refs){

                my $reqstring="select category,content from normdata where isbn=? order by category,indicator";
                my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
                while (my $res=$request->fetchrow_hashref) {
                    my $category   = "T".sprintf "%04d",$res->{category };
                    my $content    =        decode_utf8($res->{content});
                    
                    push @{$normset_ref->{$category}}, {
                        content    => $content,
                    };
                }
                $request->finish();
                $logger->debug("Enrich: $isbn -> $reqstring");
            }
            
        }
        $enrichdbh->disconnect();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Normdateninformationen ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }


    }

    return ($normset_ref,\@mexnormset,\@circexemplarliste);
}

sub get_mex_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $mexidn             = exists $arg_ref->{mexidn}
        ? $arg_ref->{mexidn}             : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $normset_ref={};
    
    # Defaultwerte setzen
    $normset_ref->{X0005}{content}="-";
    $normset_ref->{X0014}{content}="-";
    $normset_ref->{X0016}{content}="-";
    $normset_ref->{X1204}{content}="-";
    $normset_ref->{X4000}{content}="-";
    $normset_ref->{X4001}{content}="";

    my ($atime,$btime,$timeall);
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest="select category,content,indicator from mex where id = ?";
    my $result=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $result->execute($mexidn);

    while (my $res=$result->fetchrow_hashref){
        my $category  = "X".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        # Exemplar-Normdaten werden als nicht multipel angenommen
        # und dementsprechend vereinfacht in einer Datenstruktur
        # abgelegt
        $normset_ref->{$category} = {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $sqlrequest : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $sigel      = "";
    # Bestimmung des Bibliotheksnamens
    # Ein im Exemplar-Datensatz gefundenes Sigel geht vor
    if (exists $normset_ref->{X3300}{content}) {
        $sigel=$normset_ref->{X3300}{content};
        if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$targetdbinfo_ref->{sigel}{$sigel};
        }
        else {
            $normset_ref->{X4000}{content}= {
					     full  => "($sigel)",
					     short => "($sigel)",
					    };
        }
    }
    # sonst wird der Datenbankname zur Findung des Sigels herangezogen
    else {
        $sigel=$targetdbinfo_ref->{dbases}{$database};
        if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$targetdbinfo_ref->{sigel}{$sigel};
        }
    }

    my $bibinfourl="";

    # Bestimmung der Bibinfo-Url
    if (exists $targetdbinfo_ref->{bibinfo}{$sigel}) {
        $normset_ref->{X4001}{content}=$targetdbinfo_ref->{bibinfo}{$sigel};
    }

    return $normset_ref;
}

sub get_result_navigation {
    my ($arg_ref) = @_;

    # Set defaults
    my $sessiondbh            = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}            : undef;
    my $database              = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;
    my $titidn                = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}                : undef;
    my $sessionID             = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste
    my $sessionresult=$sessiondbh->prepare("select lastresultset from session where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    my $result=$sessionresult->fetchrow_hashref();
    my $lastresultstring="";
  
    if ($result->{'lastresultset'}) {
        $lastresultstring = decode_utf8($result->{'lastresultset'});
    }
  
    $sessionresult->finish();
  
    my $lasttiturl="";
    my $nexttiturl="";
  
    if ($lastresultstring=~m/(\w+:\d+)\|$database:$titidn/) {
        $lasttiturl=$1;
        my ($lastdatabase,$lastkatkey)=split(":",$lasttiturl);
        $lasttiturl="$config->{search_loc}?sessionID=$sessionID;database=$lastdatabase;searchsingletit=$lastkatkey";
    }
    
    if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/) {
        $nexttiturl=$1;
        my ($nextdatabase,$nextkatkey)=split(":",$nexttiturl);

	$logger->debug("NextDB: $nextdatabase - NextKatkey: $nextkatkey");

        $nexttiturl="$config->{search_loc}?sessionID=$sessionID;database=$nextdatabase;searchsingletit=$nextkatkey";
    }

    return ($lasttiturl,$nexttiturl);
}

sub get_index {
    my ($arg_ref) = @_;

    # Set defaults
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}              : undef;
    my $category          = exists $arg_ref->{category}
        ? $arg_ref->{category}          : undef;
    my $contentreq        = exists $arg_ref->{contentreq}
        ? $arg_ref->{contentreq}        : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $type_ref = {
        tit      => 1,
        aut      => 2,
        kor      => 3,
        swt      => 4,
        notation => 5,
        mex      => 6,
    };
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my @contents=();
    {
        my $sqlrequest;
        # Normdaten-String-Recherche
        if ($contentreq=~/^\^/){
            substr($contentreq,0,1)="";
            $contentreq=~s/\*$/\%/;
            $sqlrequest="select distinct ${type}.content as content from $type, ${type}_string where ${type}.category = ? and ${type}_string.category = ? and ${type}_string.content like ? and ${type}.id=${type}_string.id order by ${type}.content";
        }
        # Normdaten-Volltext-Recherche
        else {
            $sqlrequest="select distinct ${type}.content as content from $type, ${type}_ft where ${type}.category = ? and ${type}_ft.category = ? and match (${type}_ft.content) against (? IN BOOLEAN MODE) and ${type}.id=${type}_ft.id order by ${type}.content";
            $contentreq = OpenBib::VirtualSearch::Util::conv2autoplus($contentreq);
        }
        $logger->info($sqlrequest." - $category, $contentreq");
        my $request=$dbh->prepare($sqlrequest);
        $request->execute($category,$category,$contentreq);

        while (my $res=$request->fetchrow_hashref){
            push @contents, {
                content     => decode_utf8($res->{content}),
            };
        }
        $request->finish();

        $logger->debug("Index-Worte: ".YAML::Dump(\@contents))
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : ".($#contents+1)." Begriffe (Bestimmung): ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    $logger->debug("INDEX-Contents (".($#contents+1)." Begriffe): ".YAML::Dump(\@contents));


    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my @index=();

    foreach my $content_ref (@contents){
        my ($atime,$btime,$timeall);

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my @ids=();
        {
            my $sqlrequest="select distinct id from ${type} where category = ? and content = ?";
            my $request=$dbh->prepare($sqlrequest);
            $request->execute($category,$content_ref->{content});

            while (my $res=$request->fetchrow_hashref){
                push @ids, $res->{id};
            }
            $request->finish();
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : ".($#ids+1)." ID's (Art): ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        {
            my $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=?";
            my $request=$dbh->prepare($sqlrequest);
            
            foreach my $id (@ids){
                $request->execute($id,$type_ref->{$type});
                my $res=$request->fetchrow_hashref;
                my $titcount=$res->{conncount};

                push @index, {
                    content   => $content_ref->{content},
                    id        => $id,
                    titcount  => $titcount,
                };
            }
            $request->finish();
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : ".($#ids+1)." ID's (Anzahl): ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : ".($#index+1)." Begriffe (Vollinformation): ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return \@index;
}

sub print_index_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $swt               = exists $arg_ref->{swt}
        ? $arg_ref->{swt}               : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $sessiondbh        = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}        : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $queryoptions_ref   = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $swtindex=OpenBib::Search::Util::get_index({
        type       => 'swt',
        category   => '0001',
        contentreq => $swt,
        dbh        => $dbh,
    });

    my $poolname=$targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        qopts      => $queryoptions_ref,
        sessionID  => $sessionID,
        swt        => $swt,
        swtindex   => $swtindex,

        config     => $config,
        msg        => $msg,

    };
  
    OpenBib::Common::Util::print_page($config->{tt_search_showswtindex_tname},$ttdata,$r);

    return;
}

sub initial_search_for_titidns {
    my ($arg_ref) = @_;

    # Set defaults
    my $searchquery_ref   = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref} : undef;
    my $serien            = exists $arg_ref->{serien}
        ? $arg_ref->{serien}        : undef;
    my $enrich            = exists $arg_ref->{enrich}
        ? $arg_ref->{enrich}        : undef;
    my $enrichkeys_ref    = exists $arg_ref->{enrichkeys_ref}
        ? $arg_ref->{enrichkeys_ref}: undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}      : 50;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Aufbau des sqlquerystrings
    my $sqlselect = "";
    my $sqlfrom   = "";
    my $sqlwhere  = "";

    my @sqlwhere = ();
    my @sqlfrom  = ('search');
    my @sqlargs  = ();

    my $notfirstsql=0;
    
    if ($searchquery_ref->{fs}{norm}) {	
        push @sqlwhere, $searchquery_ref->{fs}{bool}." match (verf,hst,kor,swt,notation,sign,inhalt,isbn,issn,ejahrft) against (? IN BOOLEAN MODE)";
        push @sqlargs, $searchquery_ref->{fs}{norm};
    }
   
    if ($searchquery_ref->{verf}{norm}) {	
        push @sqlwhere, $searchquery_ref->{verf}{bool}." match (verf) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{verf}{norm};
    }
  
    if ($searchquery_ref->{hst}{norm}) {
        push @sqlwhere, $searchquery_ref->{hst}{bool}." match (hst) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{hst}{norm};
    }
  
    if ($searchquery_ref->{swt}{norm}) {
        push @sqlwhere, $searchquery_ref->{swt}{bool}." match (swt) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{swt}{norm};
    }
  
    if ($searchquery_ref->{kor}{norm}) {
        push @sqlwhere, $searchquery_ref->{kor}{bool}." match (kor) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{kor}{norm};
    }
  
    my $notfrom="";
  
    if ($searchquery_ref->{notation}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{notation}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "notation_string";
        push @sqlfrom,  "conn";
        push @sqlwhere, $searchquery_ref->{notation}{bool}." (notation_string.content like ? and conn.sourcetype=1 and conn.targettype=5 and conn.targetid=notation_string.id and search.verwidn=conn.sourceid)";
        push @sqlargs,  $searchquery_ref->{notation}{norm};
    }
  
    my $signfrom="";
  
    if ($searchquery_ref->{sign}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{sign}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "mex_string";
        push @sqlfrom,  "conn";
        push @sqlwhere, $searchquery_ref->{sign}{bool}." (mex_string.content like ? and mex_string.category=0014 and conn.sourcetype=1 and conn.targettype=6 and conn.targetid=mex_string.id and search.verwidn=conn.sourceid)";
        push @sqlargs,  $searchquery_ref->{sign}{norm};
    }
  
    if ($searchquery_ref->{isbn}{norm}) {
        push @sqlwhere, $searchquery_ref->{isbn}{bool}." match (isbn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{isbn}{norm};
    }
  
    if ($searchquery_ref->{issn}{norm}) {
        push @sqlwhere, $searchquery_ref->{issn}{bool}." match (issn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{issn}{norm};
    }
  
    if ($searchquery_ref->{mart}{norm}) {
        push @sqlwhere, $searchquery_ref->{mart}{bool}."  match (artinh) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{mart}{norm};
    }
  
    if ($searchquery_ref->{hststring}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{hststring}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "tit_string";
        push @sqlwhere, $searchquery_ref->{hststring}{bool}." (tit_string.content like ? and tit_string.category in (0331,0310,0304,0370,0341) and search.verwidn=tit_string.id)";
        push @sqlargs,  $searchquery_ref->{hststring}{norm};
    }

    if ($searchquery_ref->{inhalt}{norm}) {
        push @sqlwhere, $searchquery_ref->{inhalt}{bool}."  match (inhalt) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{inhalt}{norm};
    }
    
    if ($searchquery_ref->{gtquelle}{norm}) {
        push @sqlwhere, $searchquery_ref->{gtquelle}{bool}."  match (gtquelle) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{gtquelle}{norm};
    }
  
    if ($searchquery_ref->{ejahr}{norm}) {
        push @sqlwhere, $searchquery_ref->{ejahr}{bool}." ejahr ".$searchquery_ref->{ejahr}{arg}." ?";
        push @sqlargs,  $searchquery_ref->{ejahr}{norm};
    }

    if ($serien){
        push @sqlfrom,  "conn";
        push @sqlwhere, "and (conn.targetid=search.verwidn and conn.targettype=1 and conn.sourcetype=1)";
    }

    my @tempidns=();
    
    my $sqlwherestring  = join(" ",@sqlwhere);
    $sqlwherestring     =~s/^(?:AND|OR|NOT) //;
    my $sqlfromstring   = join(", ",@sqlfrom);

    if ($offset >= 0){
        $offset=$offset.",";
    }
    
    my $sqlquerystring  = "select distinct verwidn from $sqlfromstring where $sqlwherestring limit $offset$hitrange";

    $logger->debug("QueryString: ".$sqlquerystring);
    my $request         = $dbh->prepare($sqlquerystring);

    $request->execute(@sqlargs);

    while (my $res=$request->fetchrow_arrayref){
        push @tempidns, $res->[0];
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : initital_search_for_titidns / $sqlquerystring -> ".($#tempidns+1)." : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    if ($enrich){
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $request=$dbh->prepare("select id as verwidn from tit_string where tit_string.content = ?");
        foreach my $enrichkey (@$enrichkeys_ref){
            $request->execute($enrichkey);
            while(my $res=$request->fetchrow_arrayref){
                push @tempidns, $res->[0];
            }
        }

        $request->finish();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : enrich -> ".($#tempidns+1)."/".(scalar @$enrichkeys_ref)." : ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }

    # Entfernen mehrfacher verwidn's unter Beruecksichtigung von $hitrange
    my %schon_da=();
    my $count=0;
    my @tidns=grep {! $schon_da{$_}++ } @tempidns;
    @tidns=splice(@tidns,0,$hitrange);
    
    
    my $fullresultcount=$#tidns+1;
    
    $logger->info("Fulltext-Query: $sqlquerystring");
  
    $logger->info("Treffer: ".($#tidns+1)." von ".$fullresultcount);

    # Wenn hitrange Treffer gefunden wurden, ist es wahrscheinlich, dass
    # die wirkliche Trefferzahl groesser ist.
    # Diese wird daher getrennt bestimmt, damit sie dem Benutzer als
    # Hilfestellung fuer eine Praezisierung seiner Suchanfrage
    # ausgegeben werden kann
    if ($#tidns+1 > $hitrange){ # ueberspringen
    #    if ($#tidns+1 == $hitrange){

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $sqlresultcount = "select count(verwidn) as resultcount from $sqlfromstring where $sqlwherestring";
#        my $sqlresultcount = "select verwidn from $sqlfromstring where $sqlwherestring";
        $request         = $dbh->prepare($sqlresultcount);
        
        $request->execute(@sqlargs);
        
        my $fullres         = $request->fetchrow_hashref;
        $fullresultcount = $fullres->{resultcount};

#        $fullresultcount = 0;

#        while ($request->fetchrow_array){
#            $fullresultcount++;
#        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : initital_search_for_titidns / $sqlresultcount -> $fullresultcount : ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }
        
    }

    $request->finish();
    
    return {
        fullresultcount => $fullresultcount,
        titidns_ref     => \@tidns
    };
}

sub get_recent_titids {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select id,content from tit_string where category=2 order by content desc limit $limit");
    $request->execute();

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_aut {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 2 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_kor {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 3 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 4 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_not {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 5 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub highlightquery {
    my ($searchquery_ref,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    my $term_ref = OpenBib::Common::Util::get_searchterms({
        searchquery_ref => $searchquery_ref,
    });

    return $content if (scalar(@$term_ref) <= 0);

    $logger->debug("Terms: ".YAML::Dump($term_ref));

    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
    $logger->debug("Content vor: ".$content);
    
    $content=~s/\b($terms)/<span class="queryhighlight">$1<\/span>/ig unless ($content=~/http/);

    $logger->debug("Content nach: ".$content);

    return $content;
}

1;

