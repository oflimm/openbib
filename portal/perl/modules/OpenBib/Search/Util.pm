#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use YAML ();

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config %msg);

*config = \%OpenBib::Config::config;
*msg    = OpenBib::Config::get_msgs($config{msg_path});

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

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
    
    my ($atime,$btime,$timeall);

    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from aut where id = ? and category='0001'";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);
    
    my $res=$request->fetchrow_hashref;
    
    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $ans;
    if ($res->{content}) {
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

    my $normset_ref={};

    $normset_ref->{id      } = $autidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);

    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from aut where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "P".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='aut'";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($autidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{P5000}}, {
        content => $res->{conncount},
    };

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
#     if (exists $config{categorymapping}{$database}) {
#         for (my $i=0; $i<=$#normset; $i++) {
#             my $normdesc=$normset[$i]{desc};
      
#             # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#             if (exists $config{categorymapping}{$database}{$normdesc}) {
#                 $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#             }
#         }
#     }

    return $normset_ref;
}

sub get_kor_ans_by_idn {
    my ($koridn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from kor where id = ? and category='0001'";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config{benchmark}) {
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

    my $normset_ref={};

    $normset_ref->{id      } = $koridn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from kor where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "C".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='kor'";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($koridn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{C5000}}, {
        content => $res->{conncount},
    };

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    
    $request->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
#     if (exists $config{categorymapping}{$database}) {
#         for (my $i=0; $i<=$#normset; $i++) {
#             my $normdesc=$normset[$i]{desc};
      
#             # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#             if (exists $config{categorymapping}{$database}{$normdesc}) {
#                 $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#             }
#         }
#     }
  
     return $normset_ref;
}

sub get_swt_ans_by_idn {
    my ($swtidn,$dbh)=@_;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from swt where id = ? and category='0001'";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config{benchmark}) {
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

    my $normset_ref={};

    $normset_ref->{id      } = $swtidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from swt where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "S".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='swt'";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($swtidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{S5000}}, {
        content => $res->{conncount},
    };

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss
    # dieses angewendet werden
#     if (exists $config{categorymapping}{$database}) {
#         for (my $i=0; $i<=$#normset; $i++) {
#             my $normdesc=$normset[$i]{desc};
      
#             # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#             if (exists $config{categorymapping}{$database}{$normdesc}) {
#                 $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#             }
#         }
#     }
    
    return $normset_ref;
}

sub get_not_ans_by_idn {
    my ($notidn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
    
    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from notation where id = ? and category='0001'";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config{benchmark}) {
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

    my $normset_ref={};

    $normset_ref->{id      } = $notidn;
    $normset_ref->{database} = $database;

    my ($atime,$btime,$timeall);
    
    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from notation where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "N".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='not'";
    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($notidn);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{N5000}}, {
        content => $res->{conncount},
    };

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
#     if (exists $config{categorymapping}{$database}) {
#         for (my $i=0; $i<=$#normset; $i++) {
#             my $normdesc=$normset[$i]{desc};
      
#             # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#             if (exists $config{categorymapping}{$database}{$normdesc}) {
#                 $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#             }
#         }
#     }

    return $normset_ref;
}

sub get_tit_listitem_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn            = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $sessiondbh        = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}        : undef;
    my $targetdbinfo_ref  = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $listitem_ref={};

    # Titel-ID und zugehoerige Datenbank setzen

    $listitem_ref->{id      } = $titidn;
    $listitem_ref->{database} = $database;
    
    # Bestimmung der Titelinformationen
    my $request=$dbh->prepare("select category,indicator,content from tit where id = ? and category in ('0014','0310','0331','0412','0424','0425','1203')") or $logger->error($DBI::errstr);
    $request->execute($titidn);

    while (my $res=$request->fetchrow_hashref){
        my $category  = "T".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });

        push @{$listitem_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    my @autkor=();
    
    # Bestimmung der Verfasser, Personen
    $request=$dbh->prepare("select targetid,category,supplement from connection where sourceid=? and sourcetype='tit' and targettype='aut'") or $logger->error($DBI::errstr);
    $request->execute($titidn);

    while (my $res=$request->fetchrow_hashref){
        my $category  = "P".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $targetid  =     decode_utf8($res->{targetid});

        my $supplement="";
        if ($res->{supplement}){
            $supplement.=" ".decode_utf8($res->{supplement});
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

    
    
    # Bestimmung der Urheber, Koerperschaften
    $request=$dbh->prepare("select targetid,category,supplement from connection where sourceid=? and sourcetype='tit' and targettype='kor'") or $logger->error($DBI::errstr);
    $request->execute($titidn);

    while (my $res=$request->fetchrow_hashref){
        my $category  = "C".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $targetid  =     decode_utf8($res->{targetid});

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

    # Zusammenfassen von autkor

    push @{$listitem_ref->{'PC0001'}}, {
        content   => join(" ; ",@autkor),
    };

    
    # Bestimmung der Exemplardaten
    $request=$dbh->prepare("select distinct id from mex where category='0004' and content=?") or $logger->error($DBI::errstr);
    $request->execute($titidn);

    my @verknmex=();
    while (my $res=$request->fetchrow_hashref){
        push @verknmex, decode_utf8($res->{id});
    }

    my @mexnormset=();

    if ($#verknmex >= 0) {
        foreach my $mexsatz (@verknmex) {
            push @mexnormset, get_mex_set_by_idn({
                mexidn             => $mexsatz,
                dbh                => $dbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                database           => $database,
                sessionID          => $sessionID,
            });
        }
    }

    foreach my $mexitem_ref (@mexnormset){
       foreach my $category (keys %$mexitem_ref){
           my $content=(exists $mexitem_ref->{$category}{content})?$mexitem_ref->{$category}{content}:'';
           $logger->info($category."::".$content);
           
           push @{$listitem_ref->{$category}}, {
               content => $content,
           };
        }
    }
    


    $request->finish();

    # Ab jetzt hochhangeln zum uebergeordneten Titel, wenn im lokalen keine
    # AST bzw. HST vorhanden
    if ((!exists $listitem_ref->{0310}{content}) && (!exists $listitem_ref->{0331}{content})){
        my @superids=();

        # Bestimmung der uebergeordneten Titel
        $request=$dbh->prepare("select targetid,category,supplement from connection where sourceid=? and sourcetype='tit' and targettype='tit'") or $logger->error($DBI::errstr);
        $request->execute($titidn);
        
        while (my $res=$request->fetchrow_hashref){
            push @superids, decode_utf8($res->{targetid});
        }

      HSTSEARCH:
        foreach my $superid (@superids){
            # Bestimmung der Titelinformationen
            my $superrequest=$dbh->prepare("select * from tit where id = ? and category in ('0331','0310')") or $logger->error($DBI::errstr);
            $superrequest->execute($titidn);

            my $superitem_ref={};
            while (my $superres=$superrequest->fetchrow_hashref){
                my $category  = "T".decode_utf8($superres->{category });
                my $indicator =     decode_utf8($superres->{indicator});
                my $content   =     decode_utf8($superres->{content  });
                
                push @{$superitem_ref->{$category}}, {
                    indicator => $indicator,
                    content   => $content,
                };
            }

            if (exists $superitem_ref->{T0331}){
                $listitem_ref->{T0331}=$superitem_ref->{T0331};
                last HSTSEARCH;
            }
            elsif (exists $superitem_ref->{T0310}){
                $listitem_ref->{T0331}=$superitem_ref->{T0310};
                last HSTSEARCH;
            }
        }

        if (! exists $listitem_ref->{T0331}){
            $listitem_ref->{T0331}{content}="Kein HST/AST vorhanden";
        }
    }

    $logger->info(YAML::Dump($listitem_ref));
    return $listitem_ref;
}

sub print_tit_list_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $itemlist_ref      = exists $arg_ref->{itemlist_ref}
        ? $arg_ref->{itemlist_ref}      : undef;
    my $targetdbinfo_ref  = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $lang              = exists $arg_ref->{lang}
        ? $arg_ref->{lang}              : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @itemlist=@$itemlist_ref;

    my $hits=$#itemlist;

    # Navigationselemente erzeugen
    my %args=$r->args;
    delete $args{offset};
    delete $args{hitrange};
    my @args=();
    while (my ($key,$value)=each %args) {
        push @args,"$key=$value";
    }

    my $baseurl="http://$config{servername}$config{search_loc}?".join(";",@args);

    my @nav=();

    if ($hitrange > 0) {
        for (my $i=1; $i <= $hits; $i+=$hitrange) {
            my $active=0;

            if ($i == $offset) {
                $active=1;
            }

            my $item={
		start  => $i,
		end    => ($i+$hitrange>$hits)?$hits+1:$i+$hitrange-1,
		url    => $baseurl.";hitrange=$hitrange;offset=$i",
		active => $active,
            };
            push @nav,$item;
        }
    }

    my $hostself="http://".$r->hostname.$r->uri;

    my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'',0);

    # TT-Data erzeugen
    my $ttdata={
        lang           => $lang,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,
	      
        database       => $database,

        hits           => $hits,
	      
        searchmode     => $searchmode,
        rating         => $rating,
        bookinfo       => $bookinfo,
        sessionID      => $sessionID,
	      
        dbinfo         => $targetdbinfo_ref->{dbinfo},
        itemlist       => \@itemlist,
        hostself       => $hostself,
        queryargs      => $queryargs,
        baseurl        => $baseurl,
        thissortstring => $thissortstring,
        sortselect     => $sortselect,
	      
        hitrange       => $hitrange,
        offset         => $offset,
        nav            => \@nav,

        utf2iso        => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
	      
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config         => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showtitlist_tname},$ttdata,$r);

    return;
}

sub print_tit_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn             = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}             : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
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

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
        titidn             => $titidn,
        dbh                => $dbh,
        targetdbinfo_ref   => $targetdbinfo_ref,
        targetcircinfo_ref => $targetcircinfo_ref,
        database           => $database,
    });

    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
        sessiondbh => $sessiondbh,
        database   => $database,
        titidn     => $titidn,
        sessionID  => $sessionID,
    });

    my $poolname=$targetdbinfo_ref->{sigel}{
        $targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        prevurl    => $prevurl,
        nexturl    => $nexturl,
        qopts      => $queryoptions_ref,
        sessionID  => $sessionID,
        titidn     => $titidn,
        normset    => $normset,
        mexnormset => $mexnormset,
        circset    => $circset,

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },

        config     => \%config,
        msg        => \%msg,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showtitset_tname},$ttdata,$r);

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

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my @titsets=();

    foreach my $titidn (@$titidns_ref) {
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $titidn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            database           => $database,
            sessionID          => $sessionID
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

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },

        config     => \%config,
        msg        => \%msg,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showmulttitset_tname},$ttdata,$r);

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
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my @normset=();

    my $normset_ref={};

    $normset_ref->{id      } = $titidn;
    $normset_ref->{database} = $database;

    # Titelkategorien
    {

        my ($atime,$btime,$timeall)=(0,0,0);

        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select * from tit where id = ?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category  = "T".decode_utf8($res->{category });
            my $indicator =     decode_utf8($res->{indicator});
            my $content   =     decode_utf8($res->{content  });

            push @{$normset_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        $request->finish();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Verknuepfte Normdaten
    {
        my ($atime,$btime,$timeall)=(0,0,0);

        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select category,targetid,targettype,supplement from connection where sourceid=? and sourcetype='tit' and targettype IN ('aut','kor','not','swt')";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category   = "T".decode_utf8($res->{category  });
            my $targetid   =     decode_utf8($res->{targetid  });
            my $targettype =     decode_utf8($res->{targettype});
            my $supplement =     decode_utf8($res->{supplement});

            my $content    =
                ($targettype eq 'aut')?get_aut_ans_by_idn($targetid,$dbh):
                ($targettype eq 'kor')?get_kor_ans_by_idn($targetid,$dbh):
                ($targettype eq 'swt')?get_swt_ans_by_idn($targetid,$dbh):
                ($targettype eq 'not')?get_not_ans_by_idn($targetid,$dbh):'Error';

            $content       = decode_utf8($content);

            push @{$normset_ref->{$category}}, {
                id         => $targetid,
                content    => $content,
                supplement => $supplement,
            };
        }
        $request->finish();

        if ($config{benchmark}) {
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
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct targetid) as conncount from connection where sourceid=? and sourcetype='tit' and targettype='tit'";
        $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5001}}, {
                content => $res->{conncount},
            };
        }
        
        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }

        # Ueberordnungen
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='tit'";
        $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5002}}, {
                content => $res->{conncount},
            };
        }
        
        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }


        $request->finish();
    }

    # Exemplardaten
    my @mexnormset=();
    {

        my $reqstring="select distinct id from mex where category='0004' and content=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        my @verknmex=();
        while (my $res=$request->fetchrow_hashref){
            push @verknmex, decode_utf8($res->{id});
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
                    sessionID          => $sessionID,
                });
            }
        }

    }

    # Ausleihinformationen der Exemplare

    my @circexemplarliste = ();
    {
        my $circexlist=undef;
        
        if (exists $targetcircinfo_ref->{$database}{circ}) {
            
            my $soap = SOAP::Lite
                -> uri("urn:/MediaStatus")
                    -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
            my $result = $soap->get_mediastatus(
                $titidn,$targetcircinfo_ref->{$database}{circdb});
            
            unless ($result->fault) {
                $circexlist=$result->result;
            }
            else {
                $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
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
#             $circexemplarliste[$i]{'Standort' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
#             $circexemplarliste[$i]{'Signatur' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
#             $circexemplarliste[$i]{'Status'   }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
#             $circexemplarliste[$i]{'Rueckgabe'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
#             $circexemplarliste[$i]{'Exemplar' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	
                # Zusammensetzung von Signatur und Exemplar
                
                $circexemplarliste[$i]{'Signatur'}=$circexemplarliste[$i]{'Signatur'}.$circexemplarliste[$i]{'Exemplar'};
                
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
                $circexemplarliste[$i]{'Bibliothek'}=$bibliothek;
                
                my $bibinfourl=$targetdbinfo_ref->{bibinfo}{
                    $targetdbinfo_ref->{dbases}{$database}};
                
                $circexemplarliste[$i]{'Bibinfourl'}=$bibinfourl;
                
                my $ausleihstatus=$circexemplarliste[$i]{'Ausleihstatus'};
                
                my $ausleihstring;
                if ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar") {
                    $ausleihstring="ausleihen?";
                }
                elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellt") {
                    $ausleihstring="vormerken?";
                }
                elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "entliehen") {
                    $ausleihstring="vormerken/verlängern?";
                }
                elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar") {
                    $ausleihstring="ausleihen?";
                }
                else {
                    $ausleihstring="WebOPAC?";
                }
                
                $circexemplarliste[$i]{'Ausleihstring'}=$ausleihstring;
                
                if ($circexemplarliste[$i]{'Standort'}=~/Erziehungswiss/ || $circexemplarliste[$i]{'Standort'}=~/Heilp.*?dagogik-Magazin/) {
                    $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&branch=4&KatKeySearch=$titidn";
                }
                else {
                    if ($database eq "inst001" || $database eq "poetica") {
                        $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&branch=0&KatKeySearch=$titidn";
                    }
                    else {
                        $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&KatKeySearch=$titidn";
                    }
                }
            }
        }
        else {
            @circexemplarliste=();
        }
    }
    
#     # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
#     # dieses angewendet werden
#     if (exists $config{categorymapping}{$database}) {
#         for (my $i=0; $i<=$#normset; $i++) {
#             my $normdesc=$normset[$i]{desc};

#             # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#             if (exists $config{categorymapping}{$database}{$normdesc}) {
#                 $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#             }
#         }
#     }
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
  
    my $normset_ref={};
    
    # Defaultwerte setzen
    $normset_ref->{X0005}{content}="-";
    $normset_ref->{X0014}{content}="-";
    $normset_ref->{X0016}{content}="-";
    $normset_ref->{X1204}{content}="-";
    $normset_ref->{X4000}{content}="-";
    $normset_ref->{X4001}{content}="";

    my ($atime,$btime,$timeall);
    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest="select category,content,indicator from mex where id = ?";
    my $result=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $result->execute($mexidn);

    while (my $res=$result->fetchrow_hashref){
        my $category  = "X".decode_utf8($res->{category });
        my $indicator =     decode_utf8($res->{indicator});
        my $content   =     decode_utf8($res->{content  });
        
        $normset_ref->{$category} = {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config{benchmark}) {
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
            $normset_ref->{X4000}{content}="($sigel)";
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

#####################################################################
## get_number(rreqarray): Suche anhand der in reqarray enthaltenen
##                       SQL-Statements, fasse die Ergebnisse zusammen
##                       und liefere deren Anzahl zur"uck
##

sub get_number {
    my ($rreqarray,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %metaidns;
    my @idns;

    my ($atime,$btime,$timeall);
    
    my @reqarray=@$rreqarray;

    foreach my $numberrequest (@reqarray) {
	if ($config{benchmark}) {
	    $atime=new Benchmark;
	}

	my $numberresult=$dbh->prepare("$numberrequest") or $logger->error($DBI::errstr);
	$numberresult->execute() or $logger->error("Request: $numberrequest - ".$DBI::errstr);

	while (my @numberres=$numberresult->fetchrow) {
	    $metaidns{$numberres[0]}=1;
	}
	$numberresult->execute();
	$numberresult->finish();
	if ($config{benchmark}) {
	    $btime   = new Benchmark;
	    $timeall = timediff($btime,$atime);
	    $logger->info("Zeit fuer Nummer zu : $numberrequest : ist ".timestr($timeall));
	}
	
    }
    my $i=0;
    while (my ($key,$value)=each %metaidns) {
	$idns[$i++]=$key;
    }
    
    return $#idns+1;
}

#####################################################################
## input2sgml(line,initialsearch): Wandle die Eingabe line
##                   nach SGML um.Wwenn die
##                   Anfangs-Suche via SQL-Datenbank stattfindet
##                   Keine Umwandlung bei Anfangs-Suche

sub input2sgml {
    my ($line,$initialsearch)=@_;

    # Bei der initialen Suche via Volltext wird eine Normierung auf
    # ausgeschriebene Umlaute und den Grundbuchstaben bei Diakritika
    # vorgenommen
    if ($initialsearch) {
        $line=~s/ü/ue/g;
        $line=~s/ä/ae/g;
        $line=~s/ö/oe/g;
        $line=~s/Ü/Ue/g;
        $line=~s/Ä/Ae/g;
        $line=~s/Ö/Oe/g;
        $line=~s/ß/ss/g;
    
        # Weitere Diakritika
        $line=~s/è/e/g;
        $line=~s/à/a/g;
        $line=~s/ò/o/g;
        $line=~s/ù/u/g;
        $line=~s/È/e/g;
        $line=~s/À/a/g;
        $line=~s/Ò/o/g;
        $line=~s/Ù/u/g;
        $line=~s/é/e/g;
        $line=~s/É/E/g;
        $line=~s/á/a/g;
        $line=~s/Á/a/g;
        $line=~s/í/i/g;
        $line=~s/Í/I/g;
        $line=~s/ó/o/g;
        $line=~s/Ó/O/g;
        $line=~s/ú/u/g;
        $line=~s/Ú/U/g;
        $line=~s/ý/y/g;
        $line=~s/Ý/Y/g;
    
        if ($line=~/\"/) {
            $line=~s/`/ /g;
        }
        else {
            $line=~s/`/ +/g;
        }
        return $line;
    }
  
    $line=~s/ü/\&uuml\;/g;	
    $line=~s/ä/\&auml\;/g;
    $line=~s/ö/\&ouml\;/g;
    $line=~s/Ü/\&Uuml\;/g;
    $line=~s/Ä/\&Auml\;/g;
    $line=~s/Ö/\&Ouml\;/g;
    $line=~s/ß/\&szlig\;/g;
  
    $line=~s/É/\&Eacute\;/g;	
    $line=~s/È/\&Egrave\;/g;	
    $line=~s/Ê/\&Ecirc\;/g;	
    $line=~s/Á/\&Aacute\;/g;	
    $line=~s/À/\&Agrave\;/g;	
    $line=~s/Â/\&Acirc\;/g;	
    $line=~s/Ó/\&Oacute\;/g;	
    $line=~s/Ò/\&Ograve\;/g;	
    $line=~s/Ô/\&Ocirc\;/g;	
    $line=~s/Ú/\&Uacute\;/g;	
    $line=~s/Ù/\&Ugrave\;/g;	
    $line=~s/Û/\&Ucirc\;/g;	
    $line=~s/Í/\&Iacute\;/g;
    $line=~s/Ì/\&Igrave\;/g;	
    $line=~s/Î/\&Icirc\;/g;	
    $line=~s/Ñ/\&Ntilde\;/g;	
    $line=~s/Õ/\&Otilde\;/g;	
    $line=~s/Ã/\&Atilde\;/g;	
  
    $line=~s/é/\&eacute\;/g;	
    $line=~s/è/\&egrave\;/g;	
    $line=~s/ê/\&ecirc\;/g;	
    $line=~s/á/\&aacute\;/g;	
    $line=~s/à/\&agrave\;/g;	
    $line=~s/â/\&acirc\;/g;	
    $line=~s/ó/\&oacute\;/g;	
    $line=~s/ò/\&ograve\;/g;	
    $line=~s/ô/\&ocirc\;/g;	
    $line=~s/ú/\&uacute\;/g;	
    $line=~s/ù/\&ugrave\;/g;	
    $line=~s/û/\&ucirc\;/g;	
    $line=~s/í/\&iacute\;/g;
    $line=~s/ì/\&igrave\;/g;	
    $line=~s/î/\&icirc\;/g;	
    $line=~s/ñ/\&ntilde\;/g;	
    $line=~s/õ/\&otilde\;/g;	
    $line=~s/ã/\&atilde\;/g;	
  
    $line=~s/\"u/\&uuml\;/g;
    $line=~s/\"a/\&auml\;/g;
    $line=~s/\"o/\&ouml\;/g;
    $line=~s/\"U/\&Uuml\;/g;
    $line=~s/\"A/\&Auml\;/g;
    $line=~s/\"O/\&Ouml\;/g;
    $line=~s/\"s/\&szlig\;/g;
    $line=~s/\'/\\'/g;
    $line=~s/\*/\%/g;
    return $line;
}

sub get_global_contents {
    my ($globalcontents)=@_;

    $globalcontents=~s/<\/a>//;
    $globalcontents=~s/¬//g;
    $globalcontents=~s/\"//g;

    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;

    # Caron
    $globalcontents=~s/\&#353\;/s/g;  # s hacek
    $globalcontents=~s/\&#352\;/S/g;  # S hacek
    $globalcontents=~s/\&#269\;/c/g;  # c hacek
    $globalcontents=~s/\&#268\;/C/g;  # C hacek
    $globalcontents=~s/\&#271\;/d/g;  # d hacek
    $globalcontents=~s/\&#270\;/D/g;  # D hacek
    $globalcontents=~s/\&#283\;/e/g;  # e hacek
    $globalcontents=~s/\&#282\;/E/g;  # E hacek
    $globalcontents=~s/\&#318\;/l/g;  # l hacek
    $globalcontents=~s/\&#317\;/L/g;  # L hacek
    $globalcontents=~s/\&#328\;/n/g;  # n hacek
    $globalcontents=~s/\&#327\;/N/g;  # N hacek
    $globalcontents=~s/\&#345\;/r/g;  # r hacek
    $globalcontents=~s/\&#344\;/R/g;  # R hacek
    $globalcontents=~s/\&#357\;/t/g;  # t hacek
    $globalcontents=~s/\&#356\;/T/g;  # T hacek
    $globalcontents=~s/\&#382\;/n/g;  # n hacek
    $globalcontents=~s/\&#381\;/N/g;  # N hacek
  
    # Macron
    $globalcontents=~s/\&#275\;/e/g;  # e oberstrich
    $globalcontents=~s/\&#274\;/E/g;  # e oberstrich
    $globalcontents=~s/\&#257\;/a/g;  # a oberstrich
    $globalcontents=~s/\&#256\;/A/g;  # A oberstrich
    $globalcontents=~s/\&#299\;/i/g;  # i oberstrich
    $globalcontents=~s/\&#298\;/I/g;  # I oberstrich
    $globalcontents=~s/\&#333\;/o/g;  # o oberstrich
    $globalcontents=~s/\&#332\;/O/g;  # O oberstrich
    $globalcontents=~s/\&#363\;/u/g;  # u oberstrich
    $globalcontents=~s/\&#362\;/U/g;  # U oberstrich
  
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/,/%2C/g;
    $globalcontents=~s/\[.+?\]//;
    $globalcontents=~s/ $//g;
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/ /%20/g;

    return $globalcontents;
}

sub set_simple_category {
    my ($desc,$contents)=@_;

    # UTF8-Behandlung
    $desc     =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    # Sonderbehandlung fuer bestimmte Kategorien
    if ($desc eq "ISSN") {
        my $ezbquerystring=$config{ezb_exturl}."&jq_term1=".$contents;

        $contents="$contents (<a href=\"$ezbquerystring\" title=\"Verfügbarkeit in der Elektronischen Zeitschriften Bibliothek (EZB) überprüfen\" target=ezb>als E-Journal der Uni-Köln verfügbar?</a>)";
    }

    my %kat=();
    $kat{'type'}     = "simple_category";
    $kat{'desc'}     = $desc;
    $kat{'contents'} = $contents;
  
    return \%kat;
}

sub set_url_category {
    my ($arg_ref) = @_;

    # Set defaults
    my $desc            = exists $arg_ref->{desc}
        ? $arg_ref->{desc}            : undef;
    my $url             = exists $arg_ref->{url}
        ? $arg_ref->{url}             : undef;
    my $contents        = exists $arg_ref->{contents}
        ? $arg_ref->{contents}        : undef;
    my $supplement      = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}      : undef;

    # UTF8-Behandlung
    $desc       =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $url        =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents   =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $supplement =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    my %kat=();
    $kat{'type'}       = "url_category";
    $kat{'desc'}       = $desc;
    $kat{'url'}        = $url;
    $kat{'contents'}   = $contents;
    $kat{'supplement'} = $supplement;

    return \%kat;
}

sub set_url_category_global {
    my ($arg_ref) = @_;

    # Set defaults
    my $desc            = exists $arg_ref->{desc}
        ? $arg_ref->{desc}            : undef;
    my $url             = exists $arg_ref->{url}
        ? $arg_ref->{url}             : undef;
    my $contents        = exists $arg_ref->{contents}
        ? $arg_ref->{contents}        : undef;
    my $supplement      = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}      : '';
    my $type            = exists $arg_ref->{type}
        ? $arg_ref->{type}            : undef;
    my $sorttype        = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}        : undef;
    my $sessionID       = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}       : undef;

    # UTF8-Behandlung

    $desc       =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $url        =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents   =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $supplement =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    my $globalcontents=$contents;

    $globalcontents=~s/<\/a>//;
    $globalcontents=~s/¬//g;
    $globalcontents=~s/\"//g;
    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;

    # Sonderzeichen

    # Caron
    $globalcontents=~s/\&#353\;/s/g;  # s hacek
    $globalcontents=~s/\&#352\;/S/g;  # S hacek
    $globalcontents=~s/\&#269\;/c/g;  # c hacek
    $globalcontents=~s/\&#268\;/C/g;  # C hacek
    $globalcontents=~s/\&#271\;/d/g;  # d hacek
    $globalcontents=~s/\&#270\;/D/g;  # D hacek
    $globalcontents=~s/\&#283\;/e/g;  # e hacek
    $globalcontents=~s/\&#282\;/E/g;  # E hacek
    $globalcontents=~s/\&#318\;/l/g;  # l hacek
    $globalcontents=~s/\&#317\;/L/g;  # L hacek
    $globalcontents=~s/\&#328\;/n/g;  # n hacek
    $globalcontents=~s/\&#327\;/N/g;  # N hacek
    $globalcontents=~s/\&#345\;/r/g;  # r hacek
    $globalcontents=~s/\&#344\;/R/g;  # R hacek
    $globalcontents=~s/\&#357\;/t/g;  # t hacek
    $globalcontents=~s/\&#356\;/T/g;  # T hacek
    $globalcontents=~s/\&#382\;/n/g;  # n hacek
    $globalcontents=~s/\&#381\;/N/g;  # N hacek
  
    # Macron
    $globalcontents=~s/\&#275\;/e/g;  # e oberstrich
    $globalcontents=~s/\&#274\;/E/g;  # e oberstrich
    $globalcontents=~s/\&#257\;/a/g;  # a oberstrich
    $globalcontents=~s/\&#256\;/A/g;  # A oberstrich
    $globalcontents=~s/\&#299\;/i/g;  # i oberstrich
    $globalcontents=~s/\&#298\;/I/g;  # I oberstrich
    $globalcontents=~s/\&#333\;/o/g;  # o oberstrich
    $globalcontents=~s/\&#332\;/O/g;  # O oberstrich
    $globalcontents=~s/\&#363\;/u/g;  # u oberstrich
    $globalcontents=~s/\&#362\;/U/g;  # U oberstrich
  
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/,/%2C/g;
    $globalcontents=~s/\[.+?\]//;
    $globalcontents=~s/ $//g;
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/ /%20/g;

    my $globalurl="";

    if ($type eq "swt") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=%22$globalcontents%22;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
    }

    if ($type eq "kor") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=;kor=%22$globalcontents%22;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In%20allen%20Katalogen%20suchen";
    }

    if ($type eq "verf") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=%22$globalcontents%22;hst=;swt=;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
    }

    my %kat=();
    $kat{'type'}       = "url_category_global";
    $kat{'desc'}       = $desc;
    $kat{'url'}        = $url;
    $kat{'globalurl'}  = $globalurl;
    $kat{'contents'}   = $contents;
    $kat{'supplement'} = $supplement;

    return \%kat;
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
    my $searchmode            = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}            : undef;
    my $rating                = exists $arg_ref->{rating}
        ? $arg_ref->{rating}                : undef;
    my $bookinfo              = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}              : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
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
        $lasttiturl="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$lastdatabase;searchsingletit=$lastkatkey";
    }
    
    if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/) {
        $nexttiturl=$1;
        my ($nextdatabase,$nextkatkey)=split(":",$nexttiturl);
        $nexttiturl="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$nextdatabase;searchsingletit=$nextkatkey";
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

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    $contentreq=$contentreq."%";
    
    my @contents=();
    {
        my $sqlrequest="select distinct content from $type where category = ? and content like ? order by content";

        $logger->info($sqlrequest." - $category, $contentreq");
        my $request=$dbh->prepare($sqlrequest);
        $request->execute($category,$contentreq);

        while (my $res=$request->fetchrow_hashref){
            push @contents, $res->{content};
        }
        $request->finish();
        
    }
    
    my @index=();

    foreach my $content (@contents){

        my @ids=();
        {
            my $sqlrequest="select distinct id from $type where category = ? and content = ?";
            my $request=$dbh->prepare($sqlrequest);
            $request->execute($category,$content);

            while (my $res=$request->fetchrow_hashref){
                push @ids, $res->{id};
            }
            $request->finish();
        }

        {
            my $sqlrequest="select count(distinct sourceid) as conncount from connection where targetid=? and sourcetype='tit' and targettype='$type'";
            my $request=$dbh->prepare($sqlrequest);
            
            foreach my $id (@ids){
                $request->execute($id);
                my $res=$request->fetchrow_hashref;
                my $titcount=$res->{conncount};

                push @index, {
                    content   => $content,
                    id        => $id,
                    titcount  => $titcount,
                };
            }
            $request->finish();
        }
    }
    
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $#index Begriffe : ist ".timestr($timeall));
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

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
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

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
            return $string;
        },

        config     => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showswtindex_tname},$ttdata,$r);

    return;
}

sub initial_search_for_titidns {
    my ($arg_ref) = @_;

    # Set defaults
    my $fs                = exists $arg_ref->{fs}
        ? $arg_ref->{fs}            : undef;
    my $verf              = exists $arg_ref->{verf}
        ? $arg_ref->{verf}          : undef;
    my $hst               = exists $arg_ref->{hst}
        ? $arg_ref->{hst}           : undef;
    my $hststring         = exists $arg_ref->{hststring}
        ? $arg_ref->{hststring}     : undef;
    my $swt               = exists $arg_ref->{swt}
        ? $arg_ref->{swt}           : undef;
    my $kor               = exists $arg_ref->{kor}
        ? $arg_ref->{kor}           : undef;
    my $notation          = exists $arg_ref->{notation}
        ? $arg_ref->{notation}      : undef;
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}          : undef;
    my $issn              = exists $arg_ref->{issn}
        ? $arg_ref->{issn}          : undef;
    my $sign              = exists $arg_ref->{sign}
        ? $arg_ref->{sign}          : undef;
    my $ejahr             = exists $arg_ref->{ejahr}
        ? $arg_ref->{ejahr}         : undef;
    my $ejahrop           = exists $arg_ref->{ejahrop}
        ? $arg_ref->{ejahrop}       : undef;
    my $mart              = exists $arg_ref->{mart}
        ? $arg_ref->{mart}          : undef;
    my $boolfs            = exists $arg_ref->{boolfs}
        ? $arg_ref->{boolfs}        : 'AND';
    my $boolverf          = exists $arg_ref->{boolverf}
        ? $arg_ref->{boolverf}      : 'AND';
    my $boolhst           = exists $arg_ref->{boolhst}
        ? $arg_ref->{boolhst}       : 'AND';
    my $boolhststring     = exists $arg_ref->{boolhststring}
        ? $arg_ref->{boolhststring} : 'AND';
    my $boolswt           = exists $arg_ref->{boolswt}
        ? $arg_ref->{boolswt}       : 'AND';
    my $boolkor           = exists $arg_ref->{boolkor}
        ? $arg_ref->{boolkor}       : 'AND';
    my $boolnotation      = exists $arg_ref->{boolnotation}
        ? $arg_ref->{boolnotation}  : 'AND';
    my $boolisbn          = exists $arg_ref->{boolisbn}
        ? $arg_ref->{boolisbn}      : 'AND';
    my $boolissn          = exists $arg_ref->{boolissn}
        ? $arg_ref->{boolissn}      : 'AND';
    my $boolsign          = exists $arg_ref->{boolsign}
        ? $arg_ref->{boolsign}      : 'AND';
    my $boolejahr         = exists $arg_ref->{boolejahr}
        ? $arg_ref->{boolejahr}     : 'AND';
    my $boolmart          = exists $arg_ref->{boolmart}
        ? $arg_ref->{boolmart}      : 'AND';
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $maxhits           = exists $arg_ref->{maxhits}
        ? $arg_ref->{maxhits}       : 50;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Sicherheits-Checks
    if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT") {
        $boolverf="AND";
    }

    if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT") {
        $boolhst="AND";
    }

    if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT") {
        $boolswt="AND";
    }

    if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT") {
        $boolkor="AND";
    }

    if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT") {
        $boolnotation="AND";
    }

    if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT") {
        $boolisbn="AND";
    }

    if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT") {
        $boolissn="AND";
    }

    if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT") {
        $boolsign="AND";
    }

    if ($boolejahr ne "AND") {
        $boolejahr="AND";
    }

    if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT") {
        $boolfs="AND";
    }

    if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT") {
        $boolmart="AND";
    }

    if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT") {
        $boolhststring="AND";
    }

    $boolverf      = "AND NOT" if ($boolverf      eq "NOT");
    $boolhst       = "AND NOT" if ($boolhst       eq "NOT");
    $boolswt       = "AND NOT" if ($boolswt       eq "NOT");
    $boolkor       = "AND NOT" if ($boolkor       eq "NOT");
    $boolnotation  = "AND NOT" if ($boolnotation  eq "NOT");
    $boolisbn      = "AND NOT" if ($boolisbn      eq "NOT");
    $boolissn      = "AND NOT" if ($boolissn      eq "NOT");
    $boolsign      = "AND NOT" if ($boolsign      eq "NOT");
    $boolfs        = "AND NOT" if ($boolfs        eq "NOT");
    $boolmart      = "AND NOT" if ($boolmart      eq "NOT");
    $boolhststring = "AND NOT" if ($boolhststring eq "NOT");
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    # Abfangen der eingeschraenkten Suche mit Erscheinungsjahr (noch notwendig, oder
    # duch limit entschaerft?)
  
    if (($ejahr) && ($boolejahr eq "OR")) {
        OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verständnis für diese Ma&szlig;nahme");
        goto LEAVEPROG;
    }
    
    # Aufbau des sqlquerystrings
    my $sqlselect = "";
    my $sqlfrom   = "";
    my $sqlwhere  = "";

    my @sqlwhere = ();
    my @sqlfrom  = ('search');
    my @sqlargs  = ();

    my $notfirstsql=0;
    
    if ($fs) {	
        $fs=OpenBib::Search::Util::input2sgml($fs,1);
        push @sqlwhere, "$boolfs match (verf,hst,kor,swt,notation,sign,isbn,issn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $fs;
    }

   
    if ($verf) {	
        $verf=OpenBib::Search::Util::input2sgml($verf,1);
        push @sqlwhere, "$boolverf match (verf) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $verf;
    }
  
    if ($hst) {
        $hst=OpenBib::Search::Util::input2sgml($hst,1);
        push @sqlwhere, "$boolhst match (hst) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $hst;
    }
  
    if ($swt) {
        $swt=OpenBib::Search::Util::input2sgml($swt,1);
        push @sqlwhere, "$boolswt match (swt) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $swt;
    }
  
    if ($kor) {
        $kor=OpenBib::Search::Util::input2sgml($kor,1);
        push @sqlwhere, "boolkor match (kor) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $kor;
    }
  
    my $notfrom="";
  
    # TODO: SQL-Statement fuer Notationssuche optimieren und an neues
    #       Kategorienschema anpassen!!!
    if ($notation) {
        $notation=OpenBib::Search::Util::input2sgml($notation,1);
        push @sqlfrom,  "notation";
        push @sqlfrom,  "titnot";
        push @sqlwhere, "$boolnotation ((notation.notation like ? or notation.benennung like '$notation%') and search.verwidn=titnot.titidn and notation.idn=titnot.notidn)";
        push @sqlargs,  $notation."%";
    }
  
    my $signfrom="";
  
    if ($sign) {
        $sign=OpenBib::Search::Util::input2sgml($sign,1);
        push @sqlfrom,  "mex";
        push @sqlfrom,  "mexsign";
        push @sqlwhere, "$boolsign (search.verwidn=mex.titidn and mex.idn=mexsign.mexidn and mexsign.signlok like ?)";
        push @sqlargs,  $sign."%";
    }
  
    if ($isbn) {
        $isbn=OpenBib::Search::Util::input2sgml($isbn,1);
        $isbn=~s/-//g;
        push @sqlwhere, "$boolisbn match (isbn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $isbn;
    }
  
    if ($issn) {
        $issn=OpenBib::Search::Util::input2sgml($issn,1);
        $issn=~s/-//g;
        push @sqlwhere, "$boolissn match (issn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $issn;
    }
  
    if ($mart) {
        $mart=OpenBib::Search::Util::input2sgml($mart,1);
        push @sqlwhere, "match (artinh) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $mart;
    }
  
    if ($hststring) {
        $hststring=OpenBib::Search::Util::input2sgml($hststring,1);
        push @sqlwhere, "$boolhststring (search.hststring = ?)";
        push @sqlargs,  $hststring;
    }
  
    my $ejtest;
  
    ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
    if (!$ejtest) {
        $ejahr="";              # Nur korrekte Jahresangaben werden verarbeitet
    }                           # alles andere wird ignoriert...
  
    if ($ejahr) {	   
        push @sqlwhere, "$boolejahr ejahr $ejahrop ?";
        push @sqlargs,  $ejahr;
    }


    # TODO...
#     if ($ejahr) {
#         if ($sqlquerystring eq "") {
#             OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verständnis für diese Ma&szlig;nahme");
#             goto LEAVEPROG;
#         }
#         else {
#             $sqlquerystring="$sqlquerystring $ejahr";
#         }
#     }

    my $sqlwherestring = join(" ",@sqlwhere);
    $sqlwherestring    =~s/^(?:AND|OR|NOT) //;
    my $sqlfromstring  = join(", ",@sqlfrom);
    my $sqlquerystring = "select verwidn from $sqlfromstring where $sqlwherestring limit $maxhits";
    my $request        = $dbh->prepare($sqlquerystring);

    $request->execute(@sqlargs);

    my @tidns=();
    while (my $res=$request->fetchrow_hashref){
        push @tidns, $res->{verwidn};
    }

    $logger->info("Fulltext-Query: $sqlquerystring");
  
    $logger->info("Treffer: ".$#tidns);

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : initital_search_for_titidns / $sqlquerystring -> $#tidns : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    return @tidns;
}

1;

