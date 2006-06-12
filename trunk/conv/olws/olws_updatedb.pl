#!/usr/bin/perl

#####################################################################
#
#  olws_updatedb.pl
#
#  Inkrementelles Update einer Datenbank ueber OLWS
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

# Todo:
#
# - mex
# - UTF8
# - titlistitem TEST?
# - search TEST?
# - Schlagwortketten aufbrechen?

use 5.008001;
use utf8;
use strict;
use warnings;

use Encode qw();
use Getopt::Long;
use MIME::Base64 ();
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config = \%OpenBib::Config::config;

my ($singlepool,$fromdate,$todate);

&GetOptions(
    "single-pool=s" => \$singlepool,
    "from-date=s"   => \$fromdate,
    "to-date=s"     => \$todate,
);

Log::Log4perl->init_once($OpenBib::Config::config{log4perl_path});

# Log4perl logger erzeugen
my $logger = get_logger();

our $convtab_ref = (exists $config{convtab}{singlepool})?
    $config{convtab}{singlepool}:$config{convtab}{default};

# Verbindung zur SQL-Datenbank herstellen
my $sessiondbh
    = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
    or $logger->error_die($DBI::errstr);

#my $dbh
#    = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
#    or $logger->error_die($DBI::errstr);

my $dbh
    = DBI->connect("DBI:$config{dbimodule}:dbname=$singlepool;host=localhost;port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
    or $logger->error_die($DBI::errstr);

my $targetcircinfo_ref
    = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);


my $relevant_titids_ref= get_relevant_titids({
    sessiondbh         => $sessiondbh,
    database           => $singlepool,
    targetcircinfo_ref => $targetcircinfo_ref,
});

foreach my $titid (@{$relevant_titids_ref}){
    process_raw_title({
        dbh                => $dbh,
        sessiondbh         => $sessiondbh,
        database           => $singlepool,
        targetcircinfo_ref => $targetcircinfo_ref,
        titid              => $titid,
    });
}


########################################################################

sub get_relevant_titids {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $relevant_ids_ref = [];
    
    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});

        my $result = $soap->get_title_katkeys_by_date(
            $targetcircinfo_ref->{$database}{circdb},$fromdate,$todate);
        
        unless ($result->fault) {
            $relevant_ids_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }
    
    return $relevant_ids_ref;
}

sub process_raw_title {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $titid              = exists $arg_ref->{titid}
        ? $arg_ref->{titid}              : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @verf      = ();
    my @kor       = ();
    my @swt       = ();
    my @notation  = ();
    my @hst       = ();
    my @sign      = ();
    my @isbn      = ();
    my @issn      = ();
    my @artinh    = ();
    my @ejahr     = ();
    my @titverf   = ();
    my @titkor    = ();
    my @titswt    = ();
    my @autkor    = ();

    my %listitemdata_aut = ();
    my %listitemdata_kor = ();
    my %listitemdata_swt = ();
    my %listitemdata_not = ();
    my %listitemdata_mex = ();
    
    my $listitem_ref = {};
    
    my $raw_title_ref = {};

    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});

        my $result = $soap->get_raw_tit_by_katkey(
            $targetcircinfo_ref->{$database}{circdb},$titid);
        
        unless ($result->fault) {
            $raw_title_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }


    my $categories_aut_ref = {
        '0100' => 1,
        '0101' => 1,
        '0103' => 1,
    };

    my $categories_kor_ref = {
        '200'  => 1,
        '201'  => 1,
    };

    my $categories_sys_ref = {
        '700'  => 1,
    };

    my $categories_swt_ref = {
        '710'  => 1,
        '902'  => 1,
        '907'  => 1,
        '912'  => 1,
        '917'  => 1,
        '922'  => 1,
        '927'  => 1,
        '932'  => 1,
        '937'  => 1,
        '942'  => 1,
        '947'  => 1,
    };

    my $categories_mex_ref = {
        '0005'  => 1,
        '0014'  => 1,
        '0016'  => 1,
        '1203'  => 1,
        '1204'  => 1,
        '3330'  => 1,
    };


    # Loeschen aller Normdatenverknuepfungen zu diesem Titel.
    # Diese werden im Folgenden wieder aufgebaut

    my $request=$dbh->prepare("delete from conn where sourceid=?");
    $request->execute($titid);

    $request=$dbh->prepare("delete from tit        where id=?");
    $request->execute($titid);
    $request=$dbh->prepare("delete from tit_string where id=?");
    $request->execute($titid);
    $request=$dbh->prepare("delete from tit_ft     where id=?");
    $request->execute($titid);

  CATLINE:
    foreach my $multcategory (keys %{$raw_title_ref}){
        my ($category,$indicator,$content);

        if    ($multcategory=~m/^(\d\d\d\d)\.(\d\d\d)$/){
            ($category,$indicator)=($1,$2);
        }
        elsif ($multcategory=~m/^(\d\d\d\d)$/){
            ($category,$indicator)=($1,"");
        }

        $content = $raw_title_ref->{$multcategory};

        next CATLINE if (exists $convtab_ref->{blacklist_tit}{$category});

        if (exists $convtab_ref->{listitemcat}{$category}){
            push @{$listitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };
            
        };
        
        print "Mult: $multcategory Cat $category - Mult $indicator\n";

        # Verfasser
        if    (exists $categories_aut_ref->{$category}){
            my ($id,$supplement);
            if ($content=~m/^(\d+) ; *(.+)$/){
                ($id,$supplement)=($1,$2);
            }
            elsif ($content=~m/^(\d+)$/) {
                $id=$1;
            }
            
            my $listitemdata_aut_ref = process_raw_aut({
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                database           => $database,
                targetcircinfo_ref => $targetcircinfo_ref,
                listitemdata_aut   => \%listitemdata_aut,
                id                 => $id,
            });

            %listitemdata_aut=%{$listitemdata_aut_ref};
            
            $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,2,?)");
            $request->execute($category,$titid,$id,$supplement);

            push @verf, $id;
        }

        # Koerperschaften
        elsif (exists $categories_kor_ref->{$category}){
            my ($id,$supplement);
            if ($content=~m/^(\d+) ; *(.+)$/){
                ($id,$supplement)=($1,$2);
            }
            elsif ($content=~m/^(\d+)$/) {
                $id=$1;
            }

            my $listitemdata_kor_ref = process_raw_kor({
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                database           => $database,
                targetcircinfo_ref => $targetcircinfo_ref,
                listitemdata_kor   => \%listitemdata_kor,
                id                 => $id,
            });

            %listitemdata_kor=%{$listitemdata_kor_ref};

            $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,3,?)");
            $request->execute($category,$titid,$id,$supplement);
            
            push @kor, $id;
        }

        # Notationen
        elsif (exists $categories_sys_ref->{$category}){
            my $listitemdata_not_ref = process_raw_sys({
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                database           => $database,
                targetcircinfo_ref => $targetcircinfo_ref,
                listitemdata_not   => \%listitemdata_not,
                id                 => $content,
            });

            %listitemdata_not=%{$listitemdata_not_ref};
            
            $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,5,'')");
            $request->execute($category,$titid,$content);

            push @notation, $content;
        }       

        # Schlagworte
        elsif (exists $categories_swt_ref->{$category}){
            my $listitemdata_swt_ref = process_raw_swt({
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                database           => $database,
                targetcircinfo_ref => $targetcircinfo_ref,
                listitemdata_swt   => \%listitemdata_swt,
                id                 => $content,
            });

            %listitemdata_swt=%{$listitemdata_swt_ref};
            
            $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,4,'')");
            $request->execute($category,$titid,$content);

            push @notation, $content;
        }       

        # Exemplardaten
        elsif (exists $categories_mex_ref->{$category}){
            process_raw_mex();

            $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,6,'')");
            $request->execute($category,$titid,$content);

        }

        # Titeldaten
        else {
            if ($category eq "0004"){
                $request=$dbh->prepare("insert into conn (category,sourceid,sourcetype,targetid,targettype,supplement) values (?,?,1,?,1,'')");
                $request->execute($category,$titid,$content);
            }   
            else {
                my $contentnorm   = "";
                my $contentnormft = "";
                
                if (exists $convtab_ref->{inverted_tit}{$category}){
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                    
                    if ($convtab_ref->{inverted_tit}{$category}{string}){
                        $contentnorm   = $contentnormtmp;
                    }
                    
                    if ($convtab_ref->{inverted_tit}{$category}{ft}){
                        $contentnormft = $contentnormtmp;
                    }
                }


                if (   exists $convtab_ref->{search_category}{ejahr    }{$category}){
                    push @ejahr, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{hst      }{$category}){
                    push @hst, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{isbn     }{$category}){
                    push @isbn,      OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{issn     }{$category}){
                    push @issn,      OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{artinh   }{$category}){
                    push @artinh, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{verf     }{$category}){
                    push @titverf, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{kor      }{$category}){
                    push @titkor, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                elsif (exists $convtab_ref->{search_category}{swt      }{$category}){
                    push @titswt, OpenBib::Common::Util::grundform({
                        category => $category,
                        content  => $content,
                    });
                }
                
                $request=$dbh->prepare("insert into tit (id,category,indicator,content) values (?,?,?,?)");
                $request->execute($titid,$category,$indicator,$content);
                
                if ($contentnorm){
                    $request=$dbh->prepare("insert into tit_string (id,category,content) values (?,?,?)");
                    $request->execute($titid,$category,$contentnorm);
                }
                
                if ($contentnormft){
                    $request=$dbh->prepare("insert into tit_ft (id,category,content) values (?,?,?)");
                    $request->execute($titid,$category,$contentnormft);
                }
            }
        }
        
    }   

    my @temp=();
    foreach my $item (@verf){
        push @temp, join(" ",@{$listitemdata_aut{$item}{data}});
    }
    push @temp, join(" ",@titverf);
    my $verf     = join(" ",@temp);
    
    @temp=();
    foreach my $item (@kor){
        push @temp, join(" ",@{$listitemdata_kor{$item}{data}});
    }
    push @temp, join(" ",@titkor);
    my $kor      = join(" ",@temp);
    
    @temp=();
    foreach my $item (@swt){
        push @temp, join(" ",@{$listitemdata_swt{$item}{data}});
    }
    push @temp, join(" ",@titswt);
    my $swt      = join(" ",@temp);
    
    @temp=();
    foreach my $item (@notation){
        push @temp, join(" ",@{$listitemdata_not{$item}{data}});
    }
    my $notation = join(" ",@temp);
    
#    @temp=();
#    push @temp, join(" ",@{$listitemdata_mex{$titid}{data}});
#    my $mex = join(" ",@temp);

    my $mex ="TODO";
    
    my $hst       = join(" ",@hst);
    my $isbn      = join(" ",@isbn);
    my $issn      = join(" ",@issn);
    my $artinh    = join(" ",@artinh);
    my $ejahr     = join(" ",@ejahr);

    # Loeschen und Zurueckschreiben der Search-Tabelle
    $request=$dbh->prepare("delete from search where verwidn=?");
    $request->execute($titid);
    
    $request=$dbh->prepare("insert into search values (?,?,?,?,?,?,?,?,?,?,?)");
    $request->execute($titid,$verf,$hst,$kor,$swt,$notation,$mex,$ejahr,$isbn,$issn,$artinh);
    
    # Listitem zusammensetzen
    
    # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
    # der Kurztitelliste:
    #
    # 1. Fall: Es existiert ein HST
    #
    # Dann:
    #
    # Unterfall 1.1: Es existiert eine (erste) Bandzahl(089)
    #
    # Dann: Setze diese Bandzahl vor den AST/HST
    #
    # Unterfall 1.2: Es existiert keine Bandzahl(089), aber eine (erste)
    #                Bandzahl(455)
    #
    # Dann: Setze diese Bandzahl vor den AST/HST
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
    if (exists $listitem_ref->{T0331}){
        # UnterFall 1.1:
        if (exists $listitem_ref->{'T0089'}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
        }
        # Unterfall 1.2:
        elsif (exists $listitem_ref->{T0455}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
        }
    }
    else {
        # UnterFall 2.1:
        if (exists $listitem_ref->{'T0089'}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content};
        }
        # Unterfall 2.2:
        elsif (exists $listitem_ref->{T0455}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content};
        }
        # Unterfall 2.3:
        elsif (exists $listitem_ref->{T0451}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0451}[0]{content};
        }
        # Unterfall 2.4:
        elsif (exists $listitem_ref->{T1203}){
            $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T1203}[0]{content};
        }
        else {
            $listitem_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
        }
    }
    
    # Exemplardaten-Hash zu listitem-Hash hinzufuegen
    
    foreach my $content (@{$listitemdata_mex{$titid}}){
        push @{$listitem_ref->{X0014}}, {
            content => $content,
        };
    }
    
    # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
    push @{$listitem_ref->{'PC0001'}}, {
        content   => join(" ; ",@autkor),
    };
    # Hinweis: Weder das verpacken via pack "u" noch Base64 koennten
    # eventuell fuer die Recherche schnell genug sein. Allerdings
    # funktioniert es sehr gut.
    # Moegliche Alternativen
    # - Binaere Daten mit load data behandeln koennen
    # - Data::Dumper verwenden, da hier ASCII herauskommt
    # - in MLDB auslagern
    # - Kategorien als eigene Spalten
    
    
    my $listitem = Storable::freeze($listitem_ref);
    
    my $encoding_type="hex";
    
    if    ($encoding_type eq "base64"){
        $listitem = MIME::Base64::encode_base64($listitem,"");
    }
    elsif ($encoding_type eq "hex"){
        $listitem = unpack "H*",$listitem;
    }

    # Listitem loeschen und schreiben

    $request=$dbh->prepare("delete from titlistitem where id=?");
    $request->execute($titid);

    $request=$dbh->prepare("insert into titlistitem values (?,?)");
    $request->execute($titid,$listitem);
    
    print YAML::Dump($raw_title_ref);
    return;
}

sub process_raw_aut {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref   = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database             = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh           = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $id                   = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;
    my $dbh                  = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $listitemdata_aut_ref = exists $arg_ref->{listitemdata_aut}
        ? $arg_ref->{listitemdata_aut}   : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $raw_aut_ref = {};
    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
        
        my $result = $soap->get_raw_aut_by_katkey(
            $targetcircinfo_ref->{$database}{circdb},$id);
        
        unless ($result->fault) {
            $raw_aut_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }

    # Zuerst loeschen
    my $request;

    $request=$dbh->prepare("delete from aut        where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from aut_string where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from aut_ft     where id=?");
    $request->execute($id);

    # Dann einfuegen

  CATLINE:
    foreach my $multcategory (keys %{$raw_aut_ref}){
        my ($category,$indicator,$content);
        
        if    ($multcategory=~m/^(\d\d\d\d)\.(\d\d\d)$/){
            ($category,$indicator)=($1,$2);
        }
        elsif ($multcategory=~m/^(\d\d\d\d)$/){
            ($category,$indicator)=($1,"");
        }
       
        $content = $raw_aut_ref->{$multcategory};

        next CATLINE if (exists $convtab_ref->{blacklist_aut}{$category});

        # Ansetzungsform fuer listitem merken
        if ($category == 1){
            $listitemdata_aut_ref->{$id}{content}=$content;
        }

        my $contentnorm   = "";
        my $contentnormft = "";
        if (exists $convtab_ref->{inverted_aut}{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });
            
            if ($convtab_ref->{inverted_aut}{$category}{string}){
                $contentnorm   = $contentnormtmp;
            }
            
            if ($convtab_ref->{inverted_aut}{$category}{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($convtab_ref->{inverted_aut}{$category}{init}){
                push @{$listitemdata_aut_ref->{$id}{data}}, $contentnormtmp;
            }
        }
        
        print "Mult: $multcategory Cat $category - Mult $indicator\n";
        
        $request=$dbh->prepare("insert into aut (id,category,indicator,content) values (?,?,?,?)");
        $request->execute($id,$category,$indicator,$content);

        if ($contentnorm){
            $request=$dbh->prepare("insert into aut_string (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnorm);
        }

        if ($contentnormft){
            $request=$dbh->prepare("insert into aut_ft (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnormft);
        }
        

    }        

    print "Got Aut\n";
    print YAML::Dump($raw_aut_ref),"\n";
    
    return $listitemdata_aut_ref;
}

sub process_raw_kor {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $id                 = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $listitemdata_kor_ref = exists $arg_ref->{listitemdata_kor}
        ? $arg_ref->{listitemdata_kor}   : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $raw_kor_ref = {};
    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
        
        my $result = $soap->get_raw_kor_by_katkey(
            $targetcircinfo_ref->{$database}{circdb},$id);
        
        unless ($result->fault) {
            $raw_kor_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }

    # Zuerst loeschen
    my $request;

    $request=$dbh->prepare("delete from kor        where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from kor_string where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from kor_ft     where id=?");
    $request->execute($id);

    # Dann einfuegen

  CATLINE:
    foreach my $multcategory (keys %{$raw_kor_ref}){
        my ($category,$indicator,$content);
        
        if    ($multcategory=~m/^(\d\d\d\d)\.(\d\d\d)$/){
            ($category,$indicator)=($1,$2);
        }
        elsif ($multcategory=~m/^(\d\d\d\d)$/){
            ($category,$indicator)=($1,"");
        }
       
        $content = $raw_kor_ref->{$multcategory};

        next CATLINE if (exists $convtab_ref->{blacklist_kor}{$category});

        # Ansetzungsform fuer listitem merken
        if ($category == 1){
            $listitemdata_kor_ref->{$id}=$content;
        }
        
        my $contentnorm   = "";
        my $contentnormft = "";
        if (exists $convtab_ref->{inverted_kor}{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });
            
            if ($convtab_ref->{inverted_kor}{$category}{string}){
                $contentnorm   = $contentnormtmp;
            }
            
            if ($convtab_ref->{inverted_kor}{$category}{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($convtab_ref->{inverted_kor}{$category}{init}){
                push @{$listitemdata_kor_ref->{$id}{data}}, $contentnormtmp;
            }
        }
        
        print "Mult: $multcategory Cat $category - Mult $indicator\n";
        
        $request=$dbh->prepare("insert into kor (id,category,indicator,content) values (?,?,?,?)");
        $request->execute($id,$category,$indicator,$content);

        if ($contentnorm){
            $request=$dbh->prepare("insert into kor_string (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnorm);
        }

        if ($contentnormft){
            $request=$dbh->prepare("insert into kor_ft (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnormft);
        }
        

    }        
    
    print "Got Kor\n";
    print YAML::Dump($raw_kor_ref),"\n";

    return $listitemdata_kor_ref;
}

sub process_raw_sys {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $id                 = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $listitemdata_not_ref = exists $arg_ref->{listitemdata_not}
        ? $arg_ref->{listitemdata_not}   : undef;

    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $raw_sys_ref = {};
    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
        
        my $result = $soap->get_raw_not_by_katkey(
            $targetcircinfo_ref->{$database}{circdb},$id);
        
        unless ($result->fault) {
            $raw_sys_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }

    # Zuerst loeschen
    my $request;

    $request=$dbh->prepare("delete from notation        where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from notation_string where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from notation_ft     where id=?");
    $request->execute($id);

    # Dann einfuegen

  CATLINE:
    foreach my $multcategory (keys %{$raw_sys_ref}){
        my ($category,$indicator,$content);
        
        if    ($multcategory=~m/^(\d\d\d\d)\.(\d\d\d)$/){
            ($category,$indicator)=($1,$2);
        }
        elsif ($multcategory=~m/^(\d\d\d\d)$/){
            ($category,$indicator)=($1,"");
        }
       
        $content = $raw_sys_ref->{$multcategory};

        next CATLINE if (exists $convtab_ref->{blacklist_not}{$category});
        
        my $contentnorm   = "";
        my $contentnormft = "";
        if (exists $convtab_ref->{inverted_not}{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });
            
            if ($convtab_ref->{inverted_not}{$category}{string}){
                $contentnorm   = $contentnormtmp;
            }
            
            if ($convtab_ref->{inverted_not}{$category}{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($convtab_ref->{inverted_not}{$category}{init}){
                push @{$listitemdata_not_ref->{$id}{data}}, $contentnormtmp;
            }

        }
        
        print "Mult: $multcategory Cat $category - Mult $indicator\n";
        
        $request=$dbh->prepare("insert into notation (id,category,indicator,content) values (?,?,?,?)");
        $request->execute($id,$category,$indicator,$content);

        if ($contentnorm){
            $request=$dbh->prepare("insert into notation_string (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnorm);
        }

        if ($contentnormft){
            $request=$dbh->prepare("insert into notation_ft (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnormft);
        }
        

    }        
    
    print "Got Sys\n";
    print YAML::Dump($raw_sys_ref),"\n";

    return $listitemdata_not_ref;
}

sub process_raw_swt {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $id                 = exists $arg_ref->{id}
        ? $arg_ref->{titid}              : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $listitemdata_swt_ref = exists $arg_ref->{listitemdata_swt}
        ? $arg_ref->{listitemdata_swt}   : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $raw_swt_ref = {};
    if (exists $targetcircinfo_ref->{$database}{circ}) {
        my $soap = SOAP::Lite
            -> uri("urn:/Media")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
        
        my $result = $soap->get_raw_swt_by_katkey(
            $targetcircinfo_ref->{$database}{circdb},$id);
        
        unless ($result->fault) {
            $raw_swt_ref=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }

    # Zuerst loeschen
    my $request;

    $request=$dbh->prepare("delete from swt        where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from swt_string where id=?");
    $request->execute($id);
    $request=$dbh->prepare("delete from swt_ft     where id=?");
    $request->execute($id);

    # Dann einfuegen

  CATLINE:
    foreach my $multcategory (keys %{$raw_swt_ref}){
        my ($category,$indicator,$content);
        
        if    ($multcategory=~m/^(\d\d\d\d)\.(\d\d\d)$/){
            ($category,$indicator)=($1,$2);
        }
        elsif ($multcategory=~m/^(\d\d\d\d)$/){
            ($category,$indicator)=($1,"");
        }
       
        $content = $raw_swt_ref->{$multcategory};

        next CATLINE if (exists $convtab_ref->{blacklist_swt}{$category});

        # Ansetzungsform fuer listitem merken
        if ($category == 1){
            $listitemdata_swt_ref->{$id}{content}=$content;
        }

        my $contentnorm   = "";
        my $contentnormft = "";
        if (exists $convtab_ref->{inverted_swt}{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });
            
            if ($convtab_ref->{inverted_swt}{$category}{string}){
                $contentnorm   = $contentnormtmp;
            }
            
            if ($convtab_ref->{inverted_swt}{$category}{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($convtab_ref->{inverted_swt}{$category}{init}){
                push @{$listitemdata_swt_ref->{$id}{data}}, $contentnormtmp;
            }

        }
        
        print "Mult: $multcategory Cat $category - Mult $indicator\n";
        
        $request=$dbh->prepare("insert into swt (id,category,indicator,content) values (?,?,?,?)");
        $request->execute($id,$category,$indicator,$content);

        if ($contentnorm){
            $request=$dbh->prepare("insert into swt_string (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnorm);
        }

        if ($contentnormft){
            $request=$dbh->prepare("insert into swt_ft (id,category,content) values (?,?,?)");
            $request->execute($id,$category,$contentnormft);
        }
        

    }        

    print "Got Swt\n";
    print YAML::Dump($raw_swt_ref),"\n";
    
    return $listitemdata_swt_ref;
}

sub process_raw_mex {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $titid              = exists $arg_ref->{titid}
        ? $arg_ref->{titid}              : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return;
}
