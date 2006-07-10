####################################################################
#
#  OpenBib::Connector::DigiBib.pm
#
#  Dieses File ist (C) 2003-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Connector::DigiBib;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Search::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    
    my $r=shift;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();
    
    my $query=Apache::Request->new($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
    
    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
    
    # CGI-Input auslesen
    
    #####################################################################
    #
    # Eingabeparamter
    #
    # Titelliste:
    # verf  = Autor
    # hst   = Titel
    # swt   = Schlagwort
    # kor   = Koerperschaft
    # notation = Notation
    # isbn  = ISBN
    # issn  = ISSN
    # sign  = Signatur
    # ejahr = Erscheinungsjahr
    # maxhits = Maximale Treffer pro Pool
    # listlength = Anzahl angezeigter Gesamttreffer
    # offset = Offset zur Anzahl an Gesamttreffern
    # sorttype = Sortierung (author, yearofpub, title)
    # bool1 = Boolscher Operator zu Titel
    # bool2 = Boolscher Operator zu Schlagwort
    # bool3 = Boolscher Operator zu Koerperschaft
    # bool4 = Boolscher Operator zu Notation
    # bool5 = Boolscher Operator zu ISBN
    # bool6 = Boolscher Operator zu Signatur
    # bool7 = Boolscher Operator zu Erscheinungsjahr (derzeit effektiv nur AND)
    # bool8 = Boolscher Operator zu ISSN
    # bool9 = Boolscher Operator zu Verfasser
    # tosearch = Trefferliste
    #
    # Langanzeige:
    # 
    # idn = Titelidn
    # database = Datenbank
    # tosearch = Langanzeige

    my $autoplus = 1;
    
    my $fs       = $query->param('fs') || '';
    my $verf     = $query->param('verf');
    my $hst      = $query->param('hst');
    my $swt      = $query->param('swt');
    my $kor      = $query->param('kor');
    my $sign     = $query->param('sign');
    my $isbn     = $query->param('isbn');
    my $issn     = $query->param('issn');
    my $notation = $query->param('notation');
    my $hststring= $query->param('hststring') || '';
    my $mart     = $query->param('mart') || '';
    
    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    
  
    my $ejahr      = $query->param('ejahr');
    my $ejahrop    = $query->param('ejahrop');

    my $hitrange   = 20;
    my $idn        = $query->param('idn');
    my $database   = $query->param('database');
    my $maxhits    = ($query->param('maxhits'))?$query->param('maxhits'):200;
    my $offset     = ($query->param('offset'))?$query->param('offset'):1;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):999999999;
    my $sorttype   = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortorder  = $query->param('sortorder');
    my $tosearch   = $query->param('tosearch');
    my $view       = $query->param('view') || 'institute';
    my $serien     = ($query->param('serien'))?$query->param('serien'):0;
    
    # Historisch begruendetes Kompatabilitaetsmapping
    $query->param('boolverf'      => $query->param('bool9'));
    $query->param('boolhst'       => $query->param('bool1'));
    $query->param('boolswt'       => $query->param('bool2'));
    $query->param('boolkor'       => $query->param('bool3'));
    $query->param('boolnotation'  => $query->param('bool4'));
    $query->param('boolisbn'      => $query->param('bool5'));
    $query->param('boolissn'      => $query->param('bool8'));
    $query->param('boolsign'      => $query->param('bool6'));
    $query->param('boolejahr'     => $query->param('bool7'));
    $query->param('boolfs'        => $query->param('bool10'));
    $query->param('boolmart'      => $query->param('bool11'));
    $query->param('boolhststring' => $query->param('bool12'));
    

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);

    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);
    

            
    if (!$sortorder){
        if ($sorttype eq "ejahr"){
            $sortorder="down";
        }
        else {
            $sortorder="up";
        }
    }
    
    
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    
    my @databases=();
    
    my $dbinforesult=$sessiondbh->prepare("select dbname from viewdbs where viewname=? order by dbname") or die "Error -- $DBI::errstr";
    $dbinforesult->execute($view);
    
    while (my $result=$dbinforesult->fetchrow_hashref()){
        my $dbname=$result->{'dbname'};
        push @databases, $dbname;
    }
    

    my $searchmultipleaut=0;
    my $searchmultiplekor=0;
    my $searchmultipleswt=0;
    my $searchmultipletit=0;
    my $rating=0;
    my $bookinfo=0;
    my $searchmode=2;
    
    my $circ=0;
    my $circurl="";
    my $circcheckurl="";
    my $circdb="";
    my $sessionID=-1;
        
    if ($tosearch eq "Trefferliste") {

        # Start der Ausgabe mit korrektem Header
        print $r->send_http_header("text/html");
        
        # Folgende nicht erlaubte Anfragen werden sofort ausgesondert
        
        my $firstsql;
        
        if ($searchquery_ref->{fs  }{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{verf}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{kor }{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{hst }{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{swt}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{notation}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{sign}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{isbn}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{issn}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{mart}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{hststring}{norm}) {
            $firstsql=1;
        }
        
        if ($searchquery_ref->{ejahr}{norm}){
            $firstsql=1;
        }
        
        if ($searchquery_ref->{ejahr}{norm}) {
            my ($ejtest)=$searchquery_ref->{ejahr}{norm}=~/.*(\d\d\d\d).*/;
            if (!$ejtest) {
                $sessiondbh->disconnect();
                return OK;
            }
        }
        
        if ($searchquery_ref->{ejahr}{bool} eq "OR") {
            if ($searchquery_ref->{ejahr}{norm}) {
                $sessiondbh->disconnect();
                return OK;
            }
        }
        
        
        if ($searchquery_ref->{ejahr}{bool} eq "AND") {
            if ($searchquery_ref->{ejahr}{norm}) {
                if (!$firstsql) {
                    $sessiondbh->disconnect();
                    return OK;
                }
            }
        }
        
        if (!$firstsql) {
            $sessiondbh->disconnect();
            return OK;
        }
        
        
        my @ergebnisse;
                
        foreach my $database (@databases){
            my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);

            my $result_ref=OpenBib::Search::Util::initial_search_for_titidns({
                searchquery_ref => $searchquery_ref,

                serien          => $serien,
                dbh             => $dbh,
                maxhits         => $maxhits,

                enrich          => 0,
                enrichkeys_ref  => [],
            });

            my @tidns           = @{$result_ref->{titidns_ref}};
            my $fullresultcount = $result_ref->{fullresultcount};
            
            if ($#tidns >= 0){
                my @outputbuffer=();
                
                foreach my $idn (@tidns){
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        database          => $database,
                        sessionID         => -1,
                        targetdbinfo_ref  => $targetdbinfo_ref,
                    });
                }
                
                my @sortedoutputbuffer=();
                
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
                
                push @ergebnisse, @sortedoutputbuffer;
            }
        }

        
        # Dann den eigenen URL bestimmen
        my $myself="http://".$r->hostname.$r->uri."?".$r->args;
        
        $myself=~s/;/&/g;
        $myself=~s!:8008/!/!;
        
        my $treffercount=$#ergebnisse+1;

        my $starttemplatename=$config{tt_connector_digibib_result_start_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$starttemplatename") {
            $starttemplatename="views/$view/$starttemplatename";
        }
                
        # Ausgabe des ersten HTML-Bereichs
        my $starttemplate = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            #        INCLUDE_PATH   => $config{tt_include_path},
            #        ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        # TT-Data erzeugen
        
        my $startttdata={
            treffercount   => $treffercount,
            myself         => $myself,
        };
        
        $starttemplate->process($starttemplatename, $startttdata) || do {
            $r->log_reason($starttemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe flushen
        $r->rflush();

        $logger->debug(YAML::Dump(\@ergebnisse));
        
        my $liststart = ($offset<= $treffercount)?$offset-1:0;
        my $listend   = ($offset+$listlength-1 <= $treffercount)?$offset+$listlength-2:$treffercount-1;
        
        my $itemtemplatename=$config{tt_connector_digibib_result_item_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$itemtemplatename") {
            $itemtemplatename="views/$view/$itemtemplatename";
        }
        
        my $itemtemplate = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            #                INCLUDE_PATH   => $config{tt_include_path},
            #                ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        
        # TT-Data erzeugen
        my $ttdata={
            targetdbinfo    => $targetdbinfo_ref,
            resultlist      => \@ergebnisse,#[$liststart..$listend],
            config          => \%config,
        };
        
        $itemtemplate->process($itemtemplatename, $ttdata) || do {
            $r->log_reason($itemtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe des letzten HTML-Bereichs
        my $endtemplatename=$config{tt_connector_digibib_result_end_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$endtemplatename") {
            $endtemplatename="views/$view/$endtemplatename";
        }
        
        my $endtemplate = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            #        INCLUDE_PATH   => $config{tt_include_path},
            #        ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        # TT-Data erzeugen
        my $endttdata={
        };
        
        $endtemplate->process($endtemplatename, $endttdata) || do {
            $r->log_reason($endtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
    }
    elsif ($tosearch eq "Langanzeige"){
        
        print $r->send_http_header("text/html");
        
        my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
        
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $idn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => {},
            database           => $database,
        });
        
        
#         my $category_ref    = {};
#         my $mexcategory_ref = {};
        

#         my $hst                = $category_ref->{'HST'}[0];
#         $hst                   = "" if (!defined $hst);
        
#         my $verlag             = $category_ref->{'Verlag'}[0];
#         $verlag                = "" if (!defined $verlag);
        
#         my $fussnote           = $category_ref->{'Fu&szlig;note'}[0];
#         $fussnote              = "" if (!defined $fussnote);
        
#         my $hstzusatz          = $category_ref->{'Zusatz'}[0];
#         $hstzusatz             = "" if (!defined $hstzusatz);
        
#         my $vorlverf           = $category_ref->{'Vorl.Verfasser'}[0];
#         $vorlverf              = "" if (!defined $vorlverf);
        
#         my $verlagsort         = $category_ref->{'Verlagsort'}[0];
#         $verlagsort            = "" if (!defined $verlagsort);
        
#         my $jahr               = $category_ref->{'Ersch. Jahr'}[0];
#         $jahr                  = "" if (!defined $jahr);
        
#         my $quelle             = $category_ref->{'In:'}[0];
#         $quelle                = "" if (!defined $quelle);
        
#         my $zeitschriftentitel = $category_ref->{'IN verkn'}[0];
#         $zeitschriftentitel    = "" if (!defined $zeitschriftentitel);
        
#         my $seitenzahl         = "";
        
#         my $inverknidn="";

#       if ($zeitschriftentitel=~/ ; (S\. *\d+.*)$/){
# 	  $seitenzahl=$1;
#       }

#       my $umfang             = $category_ref->{'Kollation'}[0];
#       $umfang                = "" if (!defined $umfang);

#       my $serie              = $category_ref->{'Gesamttitel'}[0];
#       $serie                 = "" if (!defined $serie);

#       my $ausgabe            = $category_ref->{'Ausgabe'}[0];
#       $ausgabe               = "" if (!defined $ausgabe);

#       my $dbname             = ""; #$category_ref->{};;
#       my $zusatz             = ""; #$category_ref->{};;
#       my $zitatangabe        = ""; #$category_ref->{};;
#       my $abstract           = ""; #$category_ref->{};;
#       my $volltexturl        = ""; #$category_ref->{};;
#       my $autorlink          = ""; #$category_ref->{};;
#       my $titellink          = ""; #$category_ref->{};;

#       my @verfasserarray = ();
#       my @korarray       = ();
#       my @swtarray       = ();
#       my @absarray       = ();
#       my @isbnarray      = ();
#       my @issnarray      = ();
#       my @signarray      = ();
#       my @urlarray       = ();
      
#       push @verfasserarray,  @{$category_ref->{'Verfasser'}} if (exists $category_ref->{'Verfasser'});
#       push @verfasserarray,  @{$category_ref->{'Person'}} if (exists $category_ref->{'Person'});
#       push @korarray,        @{$category_ref->{'K&ouml;rperschaft'}} if (exists $category_ref->{'K&ouml;rperschaft'});
#       push @korarray,        @{$category_ref->{'Urheber'}} if (exists $category_ref->{'Urheber'});
#       push @swtarray,        @{$category_ref->{'Schlagwort'}} if (exists $category_ref->{'Schlagwort'});
#       push @absarray,        @{$category_ref->{'Abstract'}} if (exists $category_ref->{'Abstract'});
#       push @isbnarray,       @{$category_ref->{'ISBN'}} if (exists $category_ref->{'ISBN'});
#       push @issnarray,       @{$category_ref->{'ISSN'}} if (exists $category_ref->{'ISSN'});
#       push @urlarray,        @{$category_ref->{'URL'}} if (exists $category_ref->{'URL'});
      
      
# #       if ($seite[$zeile]=~/^<tr align=center><td><a href=.http:..www.ub.uni-koeln.de.dezkat.bibinfo.+?.html.><strong>(.+?)<\/strong>.*?<span id="rlsignature">(.*?)<\/span>/){
# # 	$dbname=$1;
# # 	push @signarray, $2;
# #       }

#       my $link="";
      
#       foreach my $mexnormset_ref (@$mexnormset){
#           if (!$dbname && exists $mexnormset_ref->{bibliothek}){
#               $dbname = $mexnormset_ref->{bibliothek};
#               $link   = $mexnormset_ref->{bibinfourl};
#           }

#           push @signarray, $mexnormset_ref->{signatur};
#       }
      
#       my $verf     = join(" ; ",@verfasserarray);
#       $verf        = "" if (!defined $verf);

#       my $kor      = join(" ; ",@korarray);
#       $kor         = "" if (!defined $kor);

#       my $swt      = join(" ; ",@swtarray);
#       $swt         = "" if (!defined $swt);
      
#       my $isbn     = join(" ; ",@isbnarray);
#       $isbn        = "" if (!defined $isbn);

#       my $issn     = join(" ; ",@issnarray);
#       $issn        = "" if (!defined $issn);
      
#       my $signatur = join(" ; ",@signarray);
#       $signatur    = "" if (!defined $signatur);
      
#       my $location = "";#$dbinfo{$database};
#       $location    = "" if (!defined $location);
      
#       if ($signatur){
#           $location=$location.": $signatur";
#       }

#       if ($hst && $hstzusatz){
#           $hst="$hst: $hstzusatz";
#       }
      
    
#     # Wenn Quelle besetzt ist, wird nach einer Ueberordnung geforscht.
#     if ($quelle){
#         my $request=$dbh->prepare("select verwidn from tittit where titidn=?");
#         $request->execute($idn);

#         while (my $res=$request->fetchrow_hashref()){
#            # Quellen duerfen nur max. eine Ueberordnung haben
#            $inverknidn=$res->{verwidn};
#         }
#     }

#     if ($inverknidn && 0 == 1){

#       my ($normset,$mexnormset,$circset)=(0,0,0);#OpenBib::Search::Util::get_tit_set_by_idn($inverknidn,"none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);


#       my $category_ref    = {};
#       my $mexcategory_ref = {};

#       foreach my $normset_ref (@$normset){
#           push @{$category_ref->{$normset_ref->{desc}}}, $normset_ref->{contents}." ".$normset_ref->{supplement};
#       }

#       my $hst                = $category_ref->{'HST'}[0];
#       my $verlag             = $category_ref->{'Verlag'}[0];
#       my $fussnote           = $category_ref->{'Fu&szlig;note'}[0];
#       my $hstzusatz          = $category_ref->{'Zusatz'}[0];
#       my $vorlverf           = $category_ref->{'Vorl.Verfasser'}[0];
#       my $verlagsort         = $category_ref->{'Verlagsort'}[0];
#       my $jahr               = $category_ref->{'Ersch. Jahr'}[0];
#       my $zeitschriftentitel = $category_ref->{'IN unverkn'}[0];
#       my $inverknidn         = $category_ref->{'IN verkn'}[0];
#       my $seitenzahl         = "";


#       if ($zeitschriftentitel=~/ ; (S\. *\d+.*)$/){
# 	  $seitenzahl=$1;
#       }

#       my $umfang             = $category_ref->{'Kollation'}[0];
#       my $serie              = $category_ref->{'Gesamttitel'}[0];
#       my $ausgabe            = $category_ref->{'Ausgabe'}[0];
#       my $dbname             = ""; #$category_ref->{};;
#       my $zusatz             = ""; #$category_ref->{};;
#       my $zitatangabe        = ""; #$category_ref->{};;
#       my $quelle             = ""; #$category_ref->{};;
#       my $abstract           = ""; #$category_ref->{};;
#       my $volltexturl        = ""; #$category_ref->{};;
#       my $autorlink          = ""; #$category_ref->{};;
#       my $titellink          = ""; #$category_ref->{};;

#       my @verfasserarray = ();
#       my @korarray       = ();
#       my @swtarray       = ();
#       my @absarray       = ();
#       my @isbnarray      = ();
#       my @issnarray      = ();
#       my @signarray      = ();
#       my @urlarray       = ();
      
#       push @verfasserarray,  @{$category_ref->{'Verfasser'}} if (exists $category_ref->{'Verfasser'});
#       push @verfasserarray,  @{$category_ref->{'Person'}} if (exists $category_ref->{'Person'});
#       push @korarray,        @{$category_ref->{'K&ouml;rperschaft'}} if (exists $category_ref->{'K&ouml;rperschaft'});
#       push @korarray,        @{$category_ref->{'Urheber'}} if (exists $category_ref->{'Urheber'});
#       push @swtarray,        @{$category_ref->{'Schlagwort'}} if (exists $category_ref->{'Schlagwort'});
#       push @absarray,        @{$category_ref->{'Abstract'}} if (exists $category_ref->{'Abstract'});
#       push @isbnarray,       @{$category_ref->{'ISBN'}} if (exists $category_ref->{'ISBN'});
#       push @issnarray,       @{$category_ref->{'ISSN'}} if (exists $category_ref->{'ISSN'});
#       push @urlarray,        @{$category_ref->{'URL'}} if (exists $category_ref->{'URL'});
      
      
#       my $link="";
      
#       foreach my $mexnormset_ref (@$mexnormset){
#           if (!$dbname && exists $mexnormset_ref->{bibliothek}){
#               $dbname = $mexnormset_ref->{bibliothek};
#               $link   = $mexnormset_ref->{bibinfourl};
#           }

#           push @signarray, $mexnormset_ref->{signatur};
#       }
      
#       my $verf     = join(" ; ",@verfasserarray);
#       my $kor      = join(" ; ",@korarray);
#       my $swt      = join(" ; ",@swtarray);
#       my $isbn     = join(" ; ",@isbnarray);
#       my $issn     = join(" ; ",@issnarray);
      
#       my $signatur = join(" ; ",@signarray);

#       my $location  = ""; #$dbinfo{$database};
      
#       if ($signatur){
#           $location=$location.": $signatur";
#       }

#       if ($hst && $hstzusatz){
#           $hst="$hst: $hstzusatz";
#       }
      
#     }

        # Ausgabe des letzten HTML-Bereichs
        my $templatename=$config{tt_connector_digibib_showtitset_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$templatename") {
            $templatename="views/$view/$templatename";
        }
        
        my $template = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            #        INCLUDE_PATH   => $config{tt_include_path},
            #        ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        # TT-Data erzeugen
        my $ttdata={
            item         => $normset,
            itemmex      => $mexnormset,
            targetdbinfo => $targetdbinfo_ref,
        };
        
        $template->process($templatename, $ttdata) || do {
            $r->log_reason($template->error(), $r->filename);
            return SERVER_ERROR;
        };
  } 

  return OK;
}
