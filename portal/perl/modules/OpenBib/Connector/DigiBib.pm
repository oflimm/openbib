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
    
    if ($fs){
        # UTF-8 nach ISO8859-1
        $fs=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
    
    if ($verf){
        # UTF-8 nach ISO8859-1
        $verf=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
    
    if ($hst){
        # UTF-8 nach ISO8859-1
        $hst=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
  
    if ($swt){
        # UTF-8 nach ISO8859-1
        $swt=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
  
    if ($kor){
        # UTF-8 nach ISO8859-1
        $kor=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
  
    if ($sign){
        # UTF-8 nach ISO8859-1
        $sign=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
  
    if ($isbn){
        # UTF-8 nach ISO8859-1
        $isbn=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
    
    if ($issn){
        # UTF-8 nach ISO8859-1
        $issn=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
    
    if ($notation){
        # UTF-8 nach ISO8859-1
        $notation=~s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
    }
  
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


    #####################################################################
    ## boolX: Verkn"upfung der Eingabefelder (leere Felder werden ignoriert)
    ##        AND  - Und-Verkn"upfung
    ##        OR   - Oder-Verkn"upfung
    ##        NOT  - Und Nicht-Verknuepfung
    
    my $boolverf      = ($query->param('bool9'))?$query->param('bool9'):"AND";
    my $boolhst       = ($query->param('bool1'))?$query->param('bool1'):"AND";
    my $boolswt       = ($query->param('bool2'))?$query->param('bool2'):"AND";
    my $boolkor       = ($query->param('bool3'))?$query->param('bool3'):"AND";
    my $boolnotation  = ($query->param('bool4'))?$query->param('bool4'):"AND";
    my $boolisbn      = ($query->param('bool5'))?$query->param('bool5'):"AND";
    my $boolissn      = ($query->param('bool8'))?$query->param('bool8'):"AND";
    my $boolsign      = ($query->param('bool6'))?$query->param('bool6'):"AND";
    my $boolejahr     = ($query->param('bool7'))?$query->param('bool7'):"AND";
    my $boolfs        = ($query->param('bool10'))?$query->param('bool10'):"AND";
    my $boolmart      = ($query->param('bool11'))?$query->param('bool11'):"AND";
    my $boolhststring = ($query->param('bool12'))?$query->param('bool12'):"AND";
            
    if (!$sortorder){
        if ($sorttype eq "ejahr"){
            $sortorder="down";
        }
        else {
            $sortorder="up";
        }
    }
    
    
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
    
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or die "Error -- $DBI::errstr";
    $dbinforesult->execute();


    my %sigel=();
    my %bibinfo=();
    my %dbinfo=();
    my %dbases=();
    my %dbnames=();
    
    while (my $result=$dbinforesult->fetchrow_hashref()){
        my $dbname=$result->{'dbname'};
        my $sigel=$result->{'sigel'};
        my $url=$result->{'url'};
        my $description=$result->{'description'};
        
        ##################################################################### 
        ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname
        
        $sigel{"$sigel"}="$description";
        
        #####################################################################
        ## Wandlungstabelle Bibliothekssigel <-> Informations-URL
        
        $bibinfo{"$sigel"}="$url";
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo
        
        # Wenn ein URL fuer die Datenbankinformation definiert ist, dann wird
        # damit verlinkt
        
        if ($url ne ""){
            $dbinfo{"$dbname"}="<a href=\"$url\" target=_blank>$description</a>";
        }
        else {
            $dbinfo{"$dbname"}="$description";
        }
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
        
        $dbases{"$dbname"}="$sigel";
        
        $dbnames{"$dbname"}=$description;
    }
    
    $sigel{''}="Unbekannt";
    $bibinfo{''}="http://www.ub.uni-koeln.de/";
    $dbases{''}="Unbekannt";

    my %titeltyp=(
        '1' => 'Einb&auml;ndige Werke und St&uuml;cktitel',
        '2' => 'Gesamtaufnahme fortlaufender Sammelwerke',
        '3' => 'Gesamtaufnahme mehrb&auml;ndig begrenzter Werke',
        '4' => 'Bandauff&uuml;hrung',
        '5' => 'Unselbst&auml;ndiges Werk',
        '6' => 'Allegro-Daten',
        '7' => 'Lars-Daten',
        '8' => 'Sisis-Daten',
        '9' => 'Sonstige Daten'  
    );
    
    
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    
    my @databases=();
    
    $dbinforesult=$sessiondbh->prepare("select dbname from viewdbs where viewname=? order by dbname") or die "Error -- $DBI::errstr";
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

        # Sicherheits-Checks
        
        if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT"){
            $boolverf="AND";
        }
        
        if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT"){
            $boolhst="AND";
        }
        
        if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT"){
            $boolswt="AND";
        }
        
        if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT"){
            $boolkor="AND";
        }
        
        if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT"){
            $boolnotation="AND";
        }
        
        if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT"){
            $boolisbn="AND";
        }
        
        if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT"){
            $boolissn="AND";
        }
        
        if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT"){
            $boolsign="AND";
        }
        
        if ($boolejahr ne "AND"){
            $boolejahr="AND";
        }
        
        if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT"){
            $boolfs="AND";
        }
        
        if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT"){
            $boolmart="AND";
        }
        
        if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT"){
            $boolhststring="AND";
        }
        
        $boolverf      = "AND NOT" if ($boolverf eq "NOT");
        $boolhst       = "AND NOT" if ($boolhst eq "NOT");
        $boolswt       = "AND NOT" if ($boolswt eq "NOT");
        $boolkor       = "AND NOT" if ($boolkor eq "NOT");
        $boolnotation  = "AND NOT" if ($boolnotation eq "NOT");
        $boolisbn      = "AND NOT" if ($boolisbn eq "NOT");
        $boolissn      = "AND NOT" if ($boolissn eq "NOT");
        $boolsign      = "AND NOT" if ($boolsign eq "NOT");
        $boolfs        = "AND NOT" if ($boolfs eq "NOT");
        $boolmart      = "AND NOT" if ($boolmart eq "NOT");
        $boolhststring = "AND NOT" if ($boolhststring eq "NOT");
                
        # Filter: ISBN und ISSN
        
        # Entfernung der Minus-Zeichen bei der ISBN
        $fs   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
        $isbn =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
        
        # Entfernung der Minus-Zeichen bei der ISSN
        $fs   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8/g;
        $issn =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8/g;
        
        $fs   = OpenBib::VirtualSearch::Util::cleansearchterm($fs);
        
        # Filter Rest
        
        $verf      = OpenBib::VirtualSearch::Util::cleansearchterm($verf);
        $hst       = OpenBib::VirtualSearch::Util::cleansearchterm($hst);
        $hststring = OpenBib::VirtualSearch::Util::cleansearchterm($hststring);
        
        # Bei hststring zusaetzlich normieren durch Weglassung des ersten
        # Stopwortes
        
        $hststring = OpenBib::Common::Stopwords::strip_first_stopword($hststring);
        
        $swt       = OpenBib::VirtualSearch::Util::cleansearchterm($swt);
        $kor       = OpenBib::VirtualSearch::Util::cleansearchterm($kor);
        #$sign     = OpenBib::VirtualSearch::Util::cleansearchterm($sign);
        $isbn      = OpenBib::VirtualSearch::Util::cleansearchterm($isbn);
        $issn      = OpenBib::VirtualSearch::Util::cleansearchterm($issn);
        $mart      = OpenBib::VirtualSearch::Util::cleansearchterm($mart);
        #$notation = OpenBib::VirtualSearch::Util::cleansearchterm($notation);
        $ejahr     = OpenBib::VirtualSearch::Util::cleansearchterm($ejahr);
        $ejahrop   = OpenBib::VirtualSearch::Util::cleansearchterm($ejahrop);
        
        
        # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
        
        if ($autoplus eq "1"){
            
            $fs   = OpenBib::VirtualSearch::Util::conv2autoplus($fs) if ($fs);
            $verf = OpenBib::VirtualSearch::Util::conv2autoplus($verf) if ($verf);
            $hst  = OpenBib::VirtualSearch::Util::conv2autoplus($hst) if ($hst);
            $kor  = OpenBib::VirtualSearch::Util::conv2autoplus($kor) if ($kor);
            $swt  = OpenBib::VirtualSearch::Util::conv2autoplus($swt) if ($swt);
            $isbn = OpenBib::VirtualSearch::Util::conv2autoplus($isbn) if ($isbn);
            $issn = OpenBib::VirtualSearch::Util::conv2autoplus($issn) if ($issn);
            
        }

        print $r->send_http_header("text/html");

        print << "HEADTL";
<HTML>
<HEAD>
<TITLE>Trefferliste</TITLE>
</HEAD>
<BODY>

<!-- begin result -->

<OL>

HEADTL

        # Folgende nicht erlaubte Anfragen werden sofort ausgesondert 
        
        my $firstsql;
        if ($fs){
            $firstsql=1;
        }
        if ($verf){
            $firstsql=1;
        }
        if ($kor){
            $firstsql=1;
        }
        if ($hst){
            $firstsql=1;
        }
        if ($swt){
            $firstsql=1;
        }
        if ($notation){
            $firstsql=1;
        }
        
        if ($sign){
            $firstsql=1;
        }
        
        if ($isbn){
            $firstsql=1;
        }
        
        if ($issn){
            $firstsql=1;
        }
        
        if ($mart){
            $firstsql=1;
        }
        
        if ($hststring){
            $firstsql=1;
        }
        
        if ($ejahr){
            my ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
            if (!$ejtest){
                $sessiondbh->disconnect();
                return OK;
            }        
        }
        
        if ($boolejahr eq "OR"){
            if ($ejahr){
                $sessiondbh->disconnect();
                return OK;
            }
        }
        
        if ($boolejahr eq "AND"){
            if ($ejahr){
                if (!$firstsql){
                    $sessiondbh->disconnect();
                    return OK;
                }
            }
        }
        
        if (!$firstsql){
            $sessiondbh->disconnect();
            return OK;
        }
        
        
        my @ergebnisse;
                
        $verf  =~s/%2B(\w+)/$1/g;
        $hst   =~s/%2B(\w+)/$1/g;
        $kor   =~s/%2B(\w+)/$1/g;
        $ejahr =~s/%2B(\w+)/$1/g;
        $isbn  =~s/%2B(\w+)/$1/g;
        $issn  =~s/%2B(\w+)/$1/g;


        foreach my $database (@databases){
            my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
            
            my @tidns = OpenBib::Search::Util::initital_search_for_titidns($fs,$verf,$hst,$hststring,$swt,$kor,$notation,$isbn,$issn,$sign,$ejahr,$ejahrop,$mart,$boolfs,$boolverf,$boolhst,$boolhststring,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolissn,$boolsign,$boolejahr,$boolmart,$dbh,$maxhits);
            
            if ($#tidns >= 0){
                my @outputbuffer=();
                my $outidx=0;
                
                foreach my $idn (@tidns){
                    
                    # Zuerst in Resultset eintragen zur spaeteren Navigation
                    
                    if (length($idn)>0){
                        $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
                    }
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

        print << "META";
<LI><UL>
<LI> META
<LI> DB=KVIK
<LI> HITS=$treffercount
<LI> QUERY=$myself
</UL>

META

        my $liststart = ($offset<= $treffercount)?$offset-1:0;
        my $listend   = ($offset+$listlength-1 <= $treffercount)?$offset+$listlength-2:$treffercount-1;
    
        foreach my $treffer_ref (@ergebnisse[$liststart..$listend]){
            $logger->debug(YAML::Dump($treffer_ref));

            my $idn       = $treffer_ref->{idn};
            my $verf      = $treffer_ref->{verfasser};
            my $hst       = $treffer_ref->{title};
            my $year      = $treffer_ref->{erschjahr};
            my $signatur  = $treffer_ref->{signatur};
            my $publisher = $treffer_ref->{publisher};
            my $database  = $treffer_ref->{database};
            my $langurl   = "database=$database&idn=$idn&tosearch=Langanzeige";
            my $location  = $dbinfo{$database};

            if ($signatur){
                $location=$location.": $signatur";
            }
            
            print << "TITEL";
<LI><UL>
<LI> DB=KVIK
<LI> AU=$verf
<LI> TI=$hst
<LI> YR=$year
<LI> URL=$langurl
<LI> LO=$location
<LI> LNK=
</UL>

TITEL
        }

    print << "FOOTTL";
</OL>

<!-- end result -->

</BODY>
</HTML>
FOOTTL

  }
  elsif ($tosearch eq "Langanzeige"){

      print $r->send_http_header("text/html");

      print << "HEADLA";
<HTML>
<HEAD>
<TITLE>Langanzeige</TITLE>
</HEAD>
<BODY>

<!-- begin result -->

<OL>

HEADLA

      
      my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);

      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($idn,"none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);


      my $category_ref    = {};
      my $mexcategory_ref = {};

      foreach my $normset_ref (@$normset){
          my $supplement = (defined $normset_ref->{supplement})?$normset_ref->{supplement}:"";
          my $contents   = (defined $normset_ref->{contents}  )?$normset_ref->{contents}  :"";
          push @{$category_ref->{$normset_ref->{desc}}}, $contents." ".$supplement;
      }

      my $hst                = $category_ref->{'HST'}[0];
      $hst                   = "" if (!defined $hst);

      my $verlag             = $category_ref->{'Verlag'}[0];
      $verlag                = "" if (!defined $verlag);

      my $fussnote           = $category_ref->{'Fu&szlig;note'}[0];
      $fussnote              = "" if (!defined $fussnote);

      my $hstzusatz          = $category_ref->{'Zusatz'}[0];
      $hstzusatz             = "" if (!defined $hstzusatz);

      my $vorlverf           = $category_ref->{'Vorl.Verfasser'}[0];
      $vorlverf              = "" if (!defined $vorlverf);

      my $verlagsort         = $category_ref->{'Verlagsort'}[0];
      $verlagsort            = "" if (!defined $verlagsort);
      
      my $jahr               = $category_ref->{'Ersch. Jahr'}[0];
      $jahr                  = "" if (!defined $jahr);
      
      my $quelle             = $category_ref->{'In:'}[0];
      $quelle                = "" if (!defined $quelle);

      my $zeitschriftentitel = $category_ref->{'IN verkn'}[0];
      $zeitschriftentitel    = "" if (!defined $zeitschriftentitel);

      my $seitenzahl         = "";

      my $inverknidn="";

      if ($zeitschriftentitel=~/ ; (S\. *\d+.*)$/){
	  $seitenzahl=$1;
      }

      my $umfang             = $category_ref->{'Kollation'}[0];
      $umfang                = "" if (!defined $umfang);

      my $serie              = $category_ref->{'Gesamttitel'}[0];
      $serie                 = "" if (!defined $serie);

      my $ausgabe            = $category_ref->{'Ausgabe'}[0];
      $ausgabe               = "" if (!defined $ausgabe);

      my $dbname             = ""; #$category_ref->{};;
      my $zusatz             = ""; #$category_ref->{};;
      my $zitatangabe        = ""; #$category_ref->{};;
      my $abstract           = ""; #$category_ref->{};;
      my $volltexturl        = ""; #$category_ref->{};;
      my $autorlink          = ""; #$category_ref->{};;
      my $titellink          = ""; #$category_ref->{};;

      my @verfasserarray = ();
      my @korarray       = ();
      my @swtarray       = ();
      my @absarray       = ();
      my @isbnarray      = ();
      my @issnarray      = ();
      my @signarray      = ();
      my @urlarray       = ();
      
      push @verfasserarray,  @{$category_ref->{'Verfasser'}} if (exists $category_ref->{'Verfasser'});
      push @verfasserarray,  @{$category_ref->{'Person'}} if (exists $category_ref->{'Person'});
      push @korarray,        @{$category_ref->{'K&ouml;rperschaft'}} if (exists $category_ref->{'K&ouml;rperschaft'});
      push @korarray,        @{$category_ref->{'Urheber'}} if (exists $category_ref->{'Urheber'});
      push @swtarray,        @{$category_ref->{'Schlagwort'}} if (exists $category_ref->{'Schlagwort'});
      push @absarray,        @{$category_ref->{'Abstract'}} if (exists $category_ref->{'Abstract'});
      push @isbnarray,       @{$category_ref->{'ISBN'}} if (exists $category_ref->{'ISBN'});
      push @issnarray,       @{$category_ref->{'ISSN'}} if (exists $category_ref->{'ISSN'});
      push @urlarray,        @{$category_ref->{'URL'}} if (exists $category_ref->{'URL'});
      
      
#       if ($seite[$zeile]=~/^<tr align=center><td><a href=.http:..www.ub.uni-koeln.de.dezkat.bibinfo.+?.html.><strong>(.+?)<\/strong>.*?<span id="rlsignature">(.*?)<\/span>/){
# 	$dbname=$1;
# 	push @signarray, $2;
#       }

      my $link="";
      
      foreach my $mexnormset_ref (@$mexnormset){
          if (!$dbname && exists $mexnormset_ref->{bibliothek}){
              $dbname = $mexnormset_ref->{bibliothek};
              $link   = $mexnormset_ref->{bibinfourl};
          }

          push @signarray, $mexnormset_ref->{signatur};
      }
      
      my $verf     = join(" ; ",@verfasserarray);
      $verf        = "" if (!defined $verf);

      my $kor      = join(" ; ",@korarray);
      $kor         = "" if (!defined $kor);

      my $swt      = join(" ; ",@swtarray);
      $swt         = "" if (!defined $swt);
      
      my $isbn     = join(" ; ",@isbnarray);
      $isbn        = "" if (!defined $isbn);

      my $issn     = join(" ; ",@issnarray);
      $issn        = "" if (!defined $issn);
      
      my $signatur = join(" ; ",@signarray);
      $signatur    = "" if (!defined $signatur);
      
      my $location = $dbinfo{$database};
      $location    = "" if (!defined $location);
      
      if ($signatur){
          $location=$location.": $signatur";
      }

      if ($hst && $hstzusatz){
          $hst="$hst: $hstzusatz";
      }
      
    print << "LANGTITEL";
<LI><UL>
<LI> DB=KVIK
<LI> AU=$verf
<LI> RE=$vorlverf
<LI> TI=$hst
<LI> CO=$kor
<LI> KY=$swt
<LI> PB=$verlag
<LI> PBO=$verlagsort
<LI> AG=$ausgabe
<LI> UM=$umfang
<LI> SE=$serie
<LI> CT=$zitatangabe
<LI> ZT=$zeitschriftentitel
<LI> SZ=$seitenzahl
<LI> SO=$quelle
<LI> AB=$abstract
<LI> YR=$jahr
<LI> IB=$isbn
<LI> IS=$issn
<LI> LO=$location
<LI> FN=$fussnote
<LI> OLL=$volltexturl
<LI> AUH=$autorlink
<LI> TIH=$titellink
LANGTITEL

    
    # Wenn Quelle besetzt ist, wird nach einer Ueberordnung geforscht.
    if ($quelle){
        my $request=$dbh->prepare("select verwidn from tittit where titidn=?");
        $request->execute($idn);

        while (my $res=$request->fetchrow_hashref()){
           # Quellen duerfen nur max. eine Ueberordnung haben
           $inverknidn=$res->{verwidn};
        }
    }

    if ($inverknidn){

      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($inverknidn,"none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);


      my $category_ref    = {};
      my $mexcategory_ref = {};

      foreach my $normset_ref (@$normset){
          push @{$category_ref->{$normset_ref->{desc}}}, $normset_ref->{contents}." ".$normset_ref->{supplement};
      }

      my $hst                = $category_ref->{'HST'}[0];
      my $verlag             = $category_ref->{'Verlag'}[0];
      my $fussnote           = $category_ref->{'Fu&szlig;note'}[0];
      my $hstzusatz          = $category_ref->{'Zusatz'}[0];
      my $vorlverf           = $category_ref->{'Vorl.Verfasser'}[0];
      my $verlagsort         = $category_ref->{'Verlagsort'}[0];
      my $jahr               = $category_ref->{'Ersch. Jahr'}[0];
      my $zeitschriftentitel = $category_ref->{'IN unverkn'}[0];
      my $inverknidn         = $category_ref->{'IN verkn'}[0];
      my $seitenzahl         = "";


      if ($zeitschriftentitel=~/ ; (S\. *\d+.*)$/){
	  $seitenzahl=$1;
      }

      my $umfang             = $category_ref->{'Kollation'}[0];
      my $serie              = $category_ref->{'Gesamttitel'}[0];
      my $ausgabe            = $category_ref->{'Ausgabe'}[0];
      my $dbname             = ""; #$category_ref->{};;
      my $zusatz             = ""; #$category_ref->{};;
      my $zitatangabe        = ""; #$category_ref->{};;
      my $quelle             = ""; #$category_ref->{};;
      my $abstract           = ""; #$category_ref->{};;
      my $volltexturl        = ""; #$category_ref->{};;
      my $autorlink          = ""; #$category_ref->{};;
      my $titellink          = ""; #$category_ref->{};;

      my @verfasserarray = ();
      my @korarray       = ();
      my @swtarray       = ();
      my @absarray       = ();
      my @isbnarray      = ();
      my @issnarray      = ();
      my @signarray      = ();
      my @urlarray       = ();
      
      push @verfasserarray,  @{$category_ref->{'Verfasser'}} if (exists $category_ref->{'Verfasser'});
      push @verfasserarray,  @{$category_ref->{'Person'}} if (exists $category_ref->{'Person'});
      push @korarray,        @{$category_ref->{'K&ouml;rperschaft'}} if (exists $category_ref->{'K&ouml;rperschaft'});
      push @korarray,        @{$category_ref->{'Urheber'}} if (exists $category_ref->{'Urheber'});
      push @swtarray,        @{$category_ref->{'Schlagwort'}} if (exists $category_ref->{'Schlagwort'});
      push @absarray,        @{$category_ref->{'Abstract'}} if (exists $category_ref->{'Abstract'});
      push @isbnarray,       @{$category_ref->{'ISBN'}} if (exists $category_ref->{'ISBN'});
      push @issnarray,       @{$category_ref->{'ISSN'}} if (exists $category_ref->{'ISSN'});
      push @urlarray,        @{$category_ref->{'URL'}} if (exists $category_ref->{'URL'});
      
      
      my $link="";
      
      foreach my $mexnormset_ref (@$mexnormset){
          if (!$dbname && exists $mexnormset_ref->{bibliothek}){
              $dbname = $mexnormset_ref->{bibliothek};
              $link   = $mexnormset_ref->{bibinfourl};
          }

          push @signarray, $mexnormset_ref->{signatur};
      }
      
      my $verf     = join(" ; ",@verfasserarray);
      my $kor      = join(" ; ",@korarray);
      my $swt      = join(" ; ",@swtarray);
      my $isbn     = join(" ; ",@isbnarray);
      my $issn     = join(" ; ",@issnarray);
      
      my $signatur = join(" ; ",@signarray);

      my $location  = $dbinfo{$database};
      
      if ($signatur){
          $location=$location.": $signatur";
      }

      if ($hst && $hstzusatz){
          $hst="$hst: $hstzusatz";
      }
      
      print << "SBTITEL";
<LI> SBAU=$verf
<LI> SBTI=$hst
<LI> SBPB=$verlag
<LI> SBPBO=$verlagsort
<LI> SBSE=$serie
<LI> SBYR=$jahr
<LI> SBIB=$isbn
<LI> SBIS=$issn
SBTITEL

    }

    print << "ENDE";
</UL>
ENDE



  print << "FOOTLA";
</OL>

<!-- end result -->

</BODY>
</HTML>
FOOTLA

  } 


  return OK;
}
