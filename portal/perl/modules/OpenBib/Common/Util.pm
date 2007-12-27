#####################################################################
#
#  OpenBib::Common::Util
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

package OpenBib::Common::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Digest::MD5();
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX();
use String::Tokenizer;
use Template;
use YAML ();

use OpenBib::Config;
use OpenBib::Template::Provider;
use OpenBib::Session;

my $benchmark;

if ($OpenBib::Config::config{benchmark}) {
    use Benchmark ':hireswallclock';
}

sub get_css_by_browsertype {
    my ($r)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || '';

    $logger->debug("User-Agent: $useragent");

    my $stylesheet="";
  
    if ( $useragent=~/Mozilla.5.0/ || $useragent=~/MSIE [5-9]/ || $useragent=~/Konqueror"/ ) {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-ie.css";
        }
        else {
            $stylesheet="openbib.css";
        }
    }
    else {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-simple-ie.css";
        }
        else {
            $stylesheet="openbib-simple.css";
        }
    }

    return $stylesheet;
}


sub print_warning {
    my ($warning,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $config = new OpenBib::Config();
    
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache::Request->instance($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $session = new OpenBib::Session({
        sessionID => $sessionID,
    });
    
    my $view    = $session->get_viewname();

    my $user    = new OpenBib::User({sessionID => $session->{ID}});

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    my $templatename = $config->{tt_error_tname};
    
    if ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
        $templatename="views/$view/$templatename";
    }

    $logger->debug("Using Template $templatename");
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        loginname  => $loginname,
        sessionID  => $session->{ID},
        errmsg     => $warning,
        config     => $config,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    print $r->send_http_header("text/html");
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return SERVER_ERROR;
    };
  
    return;
}

sub print_info {
    my ($info,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = new OpenBib::Config();
    
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache::Request->instance($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $session = new OpenBib::Session({sessionID => $sessionID});

    my $view    = $session->get_viewname();

    my $user    = new OpenBib::User({sessionID => $session->{ID}});

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }
    
    my $templatename = $config->{tt_info_message_tname};
    
    if ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
        $templatename="views/$view/$templatename";
    }

    $logger->debug("Using Template $templatename");
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        loginname  => $loginname,
        info_msg   => $info,
        config     => $config,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    print $r->send_http_header("text/html");
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return SERVER_ERROR;
    };
  
    return;
}   

sub print_page {
    my ($templatename,$ttdata,$r)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $view      = $ttdata->{'view'};
    my $sessionID = $ttdata->{'sessionID'};

    my $user      = new OpenBib::User({sessionID => $sessionID});

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    $ttdata->{'loginname'} = $loginname;
    
    if ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
        $templatename="views/$view/$templatename";
    }

    # Database-Template ist spezifischer als View-Template und geht vor
    if ($database && -e "$config->{tt_include_path}/database/$database/$templatename") {
        $templatename="database/$database/$templatename";
    }

    $logger->debug("Using Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
         OUTPUT         => $r,    # Output geht direkt an Apache Request
         RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    print $r->send_http_header("text/html");
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return SERVER_ERROR;
    };
  
    return;
}

sub get_searchterms {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $searchquery_ref  = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref}     : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($searchquery_ref));
    
    my $term_ref = [];

    return $term_ref if (!defined %$searchquery_ref);

    my @allterms = ();
    foreach my $cat (keys %$searchquery_ref){
        push @allterms, $searchquery_ref->{$cat}->{val};
    }

    my $alltermsstring = join (" ",@allterms);
    $alltermsstring    =~s/[^\p{Alphabetic}0-9 ]//g;

    my $tokenizer = String::Tokenizer->new();
    $tokenizer->tokenize($alltermsstring);

    my $i = $tokenizer->iterator();

    while ($i->hasNextToken()) {
        my $next = $i->nextToken();
        next if (!$next);
        push @$term_ref, $next;
    }

    return $term_ref;
}

sub get_searchquery_of_queryid {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $queryid   = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}             : "";

    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}           : "";

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return unless ($queryid && $sessionID);

    my $session = new OpenBib::Session({
        sessionID => $sessionID
    });

    my $request = $session->{dbh}->prepare("select query from queries where queryid=? and sessionid=?");
    $request->execute($queryid,$sessionID);

    my $result=$request->fetchrow_hashref;

    my $searchquery_ref=Storable::thaw(pack "H*",$result->{query});

    return $searchquery_ref;
}


sub get_searchquery {
    my ($r)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query=Apache::Request->instance($r);

    # Wandlungstabelle Erscheinungsjahroperator
    my $ejahrop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    my ($fs, $verf, $hst, $hststring, $gtquelle, $swt, $kor, $sign, $inhalt, $isbn, $issn, $mart,$notation,$ejahr,$ejahrop);

    my ($fsnorm, $verfnorm, $hstnorm, $hststringnorm, $gtquellenorm, $swtnorm, $kornorm, $signnorm, $inhaltnorm, $isbnnorm, $issnnorm, $martnorm,$notationnorm,$ejahrnorm);
    
    $fs        = $fsnorm        = decode_utf8($query->param('fs'))            || $query->param('fs')      || '';
    $verf      = $verfnorm      = decode_utf8($query->param('verf'))          || $query->param('verf')    || '';
    $hst       = $hstnorm       = decode_utf8($query->param('hst'))           || $query->param('hst')     || '';
    $hststring = $hststringnorm = decode_utf8($query->param('hststring'))     || $query->param('hststrin')|| '';
    $gtquelle  = $gtquellenorm  = decode_utf8($query->param('gtquelle'))      || $query->param('qtquelle')|| '';
    $swt       = $swtnorm       = decode_utf8($query->param('swt'))           || $query->param('swt')     || '';
    $kor       = $kornorm       = decode_utf8($query->param('kor'))           || $query->param('kor')     || '';
    $sign      = $signnorm      = decode_utf8($query->param('sign'))          || $query->param('sign')    || '';
    $inhalt    = $inhaltnorm    = decode_utf8($query->param('inhalt'))        || $query->param('inhalt')  || '';
    $isbn      = $isbnnorm      = decode_utf8($query->param('isbn'))          || $query->param('isbn')    || '';
    $issn      = $issnnorm      = decode_utf8($query->param('issn'))          || $query->param('issn')    || '';
    $mart      = $martnorm      = decode_utf8($query->param('mart'))          || $query->param('mart')    || '';
    $notation  = $notationnorm  = decode_utf8($query->param('notation'))      || $query->param('notation')|| '';
    $ejahr     = $ejahrnorm     = decode_utf8($query->param('ejahr'))         || $query->param('ejahr')   || '';
    $ejahrop   =                  decode_utf8($query->param('ejahrop'))       || $query->param('ejahrop') || 'eq';

    my $autoplus      = $query->param('autoplus')      || '';
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    #####################################################################
    ## boolX: Verknuepfung der Eingabefelder (leere Felder werden ignoriert)
    ##        AND  - Und-Verknuepfung
    ##        OR   - Oder-Verknuepfung
    ##        NOT  - Und Nicht-Verknuepfung
    my $boolverf      = ($query->param('boolverf'))     ?$query->param('boolverf')
        :"AND";
    my $boolhst       = ($query->param('boolhst'))      ?$query->param('boolhst')
        :"AND";
    my $boolswt       = ($query->param('boolswt'))      ?$query->param('boolswt')
        :"AND";
    my $boolkor       = ($query->param('boolkor'))      ?$query->param('boolkor')
        :"AND";
    my $boolnotation  = ($query->param('boolnotation')) ?$query->param('boolnotation')
        :"AND";
    my $boolisbn      = ($query->param('boolisbn'))     ?$query->param('boolisbn')
        :"AND";
    my $boolissn      = ($query->param('boolissn'))     ?$query->param('boolissn')
        :"AND";
    my $boolsign      = ($query->param('boolsign'))     ?$query->param('boolsign')
        :"AND";
    my $boolinhalt    = ($query->param('boolinhalt'))   ?$query->param('boolinhalt')
        :"AND";
    my $boolejahr     = ($query->param('boolejahr'))    ?$query->param('boolejahr')
        :"AND" ;
    my $boolfs        = ($query->param('boolfs'))       ?$query->param('boolfs')
        :"AND";
    my $boolmart      = ($query->param('boolmart'))     ?$query->param('boolmart')
        :"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring')
        :"AND";
    my $boolgtquelle  = ($query->param('boolgtquelle')) ?$query->param('boolgtquelle')
        :"AND";

    # Sicherheits-Checks

    my $valid_bools_ref = {
        'AND' => 1,
        'OR'  => 1,
        'NOT' => 1,
    };

    $boolverf      = (exists $valid_bools_ref->{$boolverf     })?$boolverf     :"AND";
    $boolhst       = (exists $valid_bools_ref->{$boolhst      })?$boolhst      :"AND";
    $boolswt       = (exists $valid_bools_ref->{$boolswt      })?$boolswt      :"AND";
    $boolkor       = (exists $valid_bools_ref->{$boolkor      })?$boolkor      :"AND";
    $boolnotation  = (exists $valid_bools_ref->{$boolnotation })?$boolnotation :"AND";
    $boolisbn      = (exists $valid_bools_ref->{$boolisbn     })?$boolisbn     :"AND";
    $boolissn      = (exists $valid_bools_ref->{$boolissn     })?$boolissn     :"AND";
    $boolsign      = (exists $valid_bools_ref->{$boolsign     })?$boolsign     :"AND";
    $boolinhalt    = (exists $valid_bools_ref->{$boolinhalt   })?$boolinhalt   :"AND";
    $boolfs        = (exists $valid_bools_ref->{$boolfs       })?$boolfs       :"AND";
    $boolmart      = (exists $valid_bools_ref->{$boolmart     })?$boolmart     :"AND";
    $boolhststring = (exists $valid_bools_ref->{$boolhststring})?$boolhststring:"AND";
    $boolgtquelle  = (exists $valid_bools_ref->{$boolgtquelle })?$boolgtquelle :"AND";

    $boolejahr    = "AND";

    $boolverf      = "AND NOT" if ($boolverf      eq "NOT");
    $boolhst       = "AND NOT" if ($boolhst       eq "NOT");
    $boolswt       = "AND NOT" if ($boolswt       eq "NOT");
    $boolkor       = "AND NOT" if ($boolkor       eq "NOT");
    $boolnotation  = "AND NOT" if ($boolnotation  eq "NOT");
    $boolisbn      = "AND NOT" if ($boolisbn      eq "NOT");
    $boolissn      = "AND NOT" if ($boolissn      eq "NOT");
    $boolsign      = "AND NOT" if ($boolsign      eq "NOT");
    $boolinhalt    = "AND NOT" if ($boolinhalt    eq "NOT");
    $boolfs        = "AND NOT" if ($boolfs        eq "NOT");
    $boolmart      = "AND NOT" if ($boolmart      eq "NOT");
    $boolhststring = "AND NOT" if ($boolhststring eq "NOT");
    $boolgtquelle  = "AND NOT" if ($boolgtquelle  eq "NOT");

    # Setzen der arithmetischen Ejahrop-Operatoren
    if (exists $ejahrop_ref->{$ejahrop}){
        $ejahrop=$ejahrop_ref->{$ejahrop};
    }
    else {
        $ejahrop="=";
    }
    
    # Filter: ISBN und ISSN

    # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
    $fsnorm   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
    $fsnorm   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
    $isbnnorm =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
    $isbnnorm =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;

    # Entfernung der Minus-Zeichen bei der ISSN
    $fsnorm   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8/g;
    $issnnorm =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8/g;

    my $ejtest;
  
    ($ejtest)=$ejahrnorm=~/.*(\d\d\d\d).*/;
    if (!$ejtest) {
        $ejahrnorm="";              # Nur korrekte Jahresangaben werden verarbeitet
    }                           # alles andere wird ignoriert...
    
    # Filter Rest
    $fsnorm        = OpenBib::Common::Util::grundform({
        content   => $fsnorm,
        searchreq => 1,
    });

    $verfnorm      = OpenBib::Common::Util::grundform({
        content   => $verfnorm,
        searchreq => 1,
    });

    $hstnorm       = OpenBib::Common::Util::grundform({
        content   => $hstnorm,
        searchreq => 1,
    });

    $hststringnorm = OpenBib::Common::Util::grundform({
        category  => "0331", # Exemplarisch fuer die Kategorien, bei denen das erste Stopwort entfernt wird
        content   => $hststringnorm,
        searchreq => 1,
    });

    $gtquellenorm  = OpenBib::Common::Util::grundform({
        content   => $gtquellenorm,
        searchreq => 1,
    });

    $swtnorm       = OpenBib::Common::Util::grundform({
        content   => $swtnorm,
        searchreq => 1,
    });

    $kornorm       = OpenBib::Common::Util::grundform({
        content   => $kornorm,
        searchreq => 1,
    });

    $signnorm      = OpenBib::Common::Util::grundform({
        content   => $signnorm,
        searchreq => 1,
    });

    $inhaltnorm    = OpenBib::Common::Util::grundform({
        content   => $inhaltnorm,
        searchreq => 1,
    });
    
    $isbnnorm      = OpenBib::Common::Util::grundform({
        category  => '0540',
        content   => $isbnnorm,
        searchreq => 1,
    });

    $issnnorm      = OpenBib::Common::Util::grundform({
        category  => '0543',
        content   => $issnnorm,
        searchreq => 1,
    });
    
    $martnorm      = OpenBib::Common::Util::grundform({
        content   => $martnorm,
        searchreq => 1,
    });

    $notationnorm  = OpenBib::Common::Util::grundform({
        content   => $notationnorm,
        searchreq => 1,
    });

    $ejahrnorm      = OpenBib::Common::Util::grundform({
        content   => $ejahrnorm,
        searchreq => 1,
    });
    
    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    if ($autoplus eq "1" && !$verfindex && !$korindex && !$swtindex) {
        $fsnorm       = OpenBib::VirtualSearch::Util::conv2autoplus($fsnorm)   if ($fs);
        $verfnorm     = OpenBib::VirtualSearch::Util::conv2autoplus($verfnorm) if ($verf);
        $hstnorm      = OpenBib::VirtualSearch::Util::conv2autoplus($hstnorm)  if ($hst);
        $kornorm      = OpenBib::VirtualSearch::Util::conv2autoplus($kornorm)  if ($kor);
        $swtnorm      = OpenBib::VirtualSearch::Util::conv2autoplus($swtnorm)  if ($swt);
        $isbnnorm     = OpenBib::VirtualSearch::Util::conv2autoplus($isbnnorm) if ($isbn);
        $issnnorm     = OpenBib::VirtualSearch::Util::conv2autoplus($issnnorm) if ($issn);
        $inhaltnorm   = OpenBib::VirtualSearch::Util::conv2autoplus($inhaltnorm) if ($inhalt);
        $gtquellenorm = OpenBib::VirtualSearch::Util::conv2autoplus($gtquellenorm) if ($gtquelle);
    }

    my $searchquery_ref={};

    if ($fs){
      $searchquery_ref->{fs}={
			      val   => $fs,
			      norm  => $fsnorm,
			      bool  => '',			      
			     };
    }

    if ($hst){
      $searchquery_ref->{hst}={
			       val   => $hst,
			       norm  => $hstnorm,
			       bool  => $boolhst,
			      };
    }

    if ($hststring){
      $searchquery_ref->{hststring}={
				     val   => $hststring,
				     norm  => $hststringnorm,
				     bool  => $boolhststring,
				    };
    }

    if ($gtquelle){
      $searchquery_ref->{gtquelle}={
			    val   => $gtquelle,
			    norm  => $gtquellenorm,
			    bool  => $boolgtquelle,
			   };
    }

    if ($inhalt){
      $searchquery_ref->{inhalt}={
			    val   => $inhalt,
			    norm  => $inhaltnorm,
			    bool  => $boolinhalt,
			   };
    }

    if ($verf){
      $searchquery_ref->{verf}={
			    val   => $verf,
			    norm  => $verfnorm,
			    bool  => $boolverf,
			   };
    }

    if ($swt){
      $searchquery_ref->{swt}={
			       val   => $swt,
			       norm  => $swtnorm,
			       bool  => $boolswt,
			      };
    }

    if ($kor){
      $searchquery_ref->{kor}={
			       val   => $kor,
			       norm  => $kornorm,
			       bool  => $boolkor,
			      };
    }

    if ($sign){
      $searchquery_ref->{sign}={
				val   => $sign,
				norm  => $signnorm,
				bool  => $boolsign,
			       };
    }

    if ($isbn){
      $searchquery_ref->{isbn}={
				val   => $isbn,
				norm  => $isbnnorm,
				bool  => $boolisbn,
			     };
    }

    if ($issn){
      $searchquery_ref->{issn}={
				val   => $issn,
				norm  => $issnnorm,
				bool  => $boolissn,
			     };
    }

    if ($mart){
      $searchquery_ref->{mart}={
				val   => $mart,
				norm  => $martnorm,
				bool  => $boolmart,
			       };
    }

    if ($notation){
      $searchquery_ref->{notation}={
				    val   => $notation,
				    norm  => $notationnorm,
				    bool  => $boolnotation,
				   };
    }

    if ($ejahr){
      $searchquery_ref->{ejahr}={
			    val   => $ejahr,
			    norm  => $ejahrnorm,
			    bool  => $boolejahr,
			    arg   => $ejahrop,
			   };
    }

    $logger->debug(YAML::Dump($searchquery_ref));
    
    return $searchquery_ref;
}

sub grundform {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $content   = exists $arg_ref->{content}
        ? $arg_ref->{content}             : "";

    my $category  = exists $arg_ref->{category}
        ? $arg_ref->{category}            : "";

    my $searchreq = exists $arg_ref->{searchreq}
        ? $arg_ref->{searchreq}           : undef;

    my $tagging   = exists $arg_ref->{tagging}
        ? $arg_ref->{tagging}             : undef;

    # Normalisierung auf Kleinschreibung
    $content = lc($content);
    
    # Sonderbehandlung verschiedener Kategorien

    # Datum normalisieren

    if ($category eq '0002'){
        if ($content =~ /^(\d\d)\.(\d\d)\.(\d\d\d\d)$/){
            $content=$3.$2.$1;
        }

	return $content;
    }
    
    # ISBN filtern
    if ($category eq "0540" || $category eq "0553"){
        # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
        $content=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
        return $content;
    }

    # ISSN filtern
    if ($category eq "0543"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8/g;
        return $content;
    }

    $content=~s/¬//g;

    # Stopwoerter fuer versch. Kategorien ausfiltern (Titel-String)

    if ($category eq "0304" || $category eq "0310" || $category eq "0331"
            || $category eq "0341" || $category eq "0370"){

        $content=~s/\s+$//;
        $content=~s/\s+<.*?>//g;

        $content=OpenBib::Common::Stopwords::strip_first_stopword($content);
    }
    
    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;

    # Ausfiltern von Supplements in []
    $content=~s/\[.*?\]//g;
    
    # Fall: C++, C# und .Net
    $content=~s/(?<=(\w|\+))\+/plus/g;
    $content=~s/(c)\#/$1sharp/ig;
    $content=~s/\.(net)\#/dot$1/ig;
    
    if ($searchreq){
        # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: '()"^*_]//g;

        # Verbundene Terme splitten
        $content=~s/(\w)-(\w)/$1 $2/g;
        $content=~s/(\w)'(\w)/$1 $2/g;
    }
    elsif ($tagging){
        $content=~s/[^-+\p{Alphabetic}0-9._]//g;

    }
    else {
        # Ausfiltern nicht akzeptierter Zeichen (Postitivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: ']//g;

        # Verbundene Terme splitten
        $content=~s/(\w)-(\w)/$1 $2/g;
        $content=~s/(\w)'(\w)/$1 $2/g;

	# Sonderbehandlung : fuer die Indexierung (bei der Recherche wird : fuer intitle: usw. benoetigt)
	$content=~s/:/ /g;
    }

    # Zeichenersetzungen
    $content=~s/'/ /g;
    $content=~s/\// /g;
    #$content=~s/:/ /g;
    $content=~s/  / /g;

    # Buchstabenersetzungen
    $content=~s/ü/ue/g;
    $content=~s/ä/ae/g;
    $content=~s/ö/oe/g;
    $content=~s/Ü/Ue/g;
    $content=~s/Ö/Oe/g;
    $content=~s/Ä/Ae/g;
    $content=~s/ß/ss/g;

    $content=~s/é/e/g;
    $content=~s/è/e/g;
    $content=~s/ê/e/g;
    $content=~s/ë/e/g;
    $content=~s/\u0113/e/g; # Kl. e mit Ueberstrich/Macron
    $content=~s/\u0115/e/g; # Kl. e mit Hacek/Breve
    $content=~s/\u011b/e/g; # Kl. e mit Caron
    $content=~s/\u0117/e/g; # Kl. e mit Punkt
    
    $content=~s/É/E/g;
    $content=~s/È/E/g;
    $content=~s/Ê/E/g;
    $content=~s/Ë/E/g;
    $content=~s/\u0112/E/g; # Gr. E mit Ueberstrich/Macron
    $content=~s/\u0114/E/g; # Gr. E mit Hacek/Breve
    $content=~s/\u011a/E/g; # Gr. E mit Caron
    $content=~s/\u0116/E/g; # Gr. E mit Punkt
    
    $content=~s/á/a/g;
    $content=~s/à/a/g;
    $content=~s/â/a/g;
    $content=~s/ã/a/g;
    $content=~s/å/a/g;
    $content=~s/\u0101/a/g; # Kl. a mit Ueberstrich/Macron
    $content=~s/\u0103/a/g; # Kl. a mit Hacek/Breve
    
    $content=~s/Á/A/g;
    $content=~s/À/A/g;
    $content=~s/Â/A/g;
    $content=~s/Ã/A/g;
    $content=~s/Å/A/g;
    $content=~s/\u0100/A/g; # Gr. A mit Ueberstrich/Macron
    $content=~s/\u0102/A/g; # Gr. A mit Hacek/Breve
    
    $content=~s/ó/o/g;
    $content=~s/ò/o/g;
    $content=~s/ô/o/g;
    $content=~s/õ/o/g;
    $content=~s/\u014d/o/g; # Kl. o mit Ueberstrich/Macron
    $content=~s/\u014f/o/g; # Kl. o mit Hacek/Breve
    $content=~s/\u0151/o/g; # Kl. o mit Doppel-Acute
    
    $content=~s/Ó/O/g;
    $content=~s/Ò/O/g;
    $content=~s/Ô/O/g;
    $content=~s/Õ/O/g;
    $content=~s/\u014c/O/g; # Gr. O mit Ueberstrich/Macron
    $content=~s/\u014e/O/g; # Gr. O mit Hacek/Breve
    $content=~s/\u0150/O/g; # Gr. O mit Doppel-Acute
    
    $content=~s/í/i/g;
    $content=~s/ì/i/g;
    $content=~s/î/i/g;
    $content=~s/ï/i/g;
    $content=~s/\u0131/i/g; # Kl. punktloses i
    $content=~s/\u012b/i/g; # Kl. i mit Ueberstrich/Macron
    $content=~s/\u012d/i/g; # Kl. i mit Hacek/Breve

    
    $content=~s/Í/I/g;
    $content=~s/Ì/I/g;
    $content=~s/Î/I/g;
    $content=~s/Ï/I/g;
    $content=~s/\u0130/I/g; # Gr. I mit Punkt
    $content=~s/\u012a/I/g; # Gr. i mit Ueberstrich/Macron
    $content=~s/\u012c/I/g; # Gr. i mit Hacek/Breve

    $content=~s/Ú/U/g;
    $content=~s/Ù/U/g;
    $content=~s/Û/U/g;
    $content=~s/\u0168/U/g; # Gr. U mit Tilde
    $content=~s/\u016a/U/g; # Gr. U mit Ueberstrich/Macron
    $content=~s/\u016c/U/g; # Gr. U mit Hacek/Breve
    $content=~s/\u0170/U/g; # Gr. U mit Doppel-Acute
    $content=~s/\u016e/U/g; # Gr. U mit Ring oben

    $content=~s/ú/u/g;
    $content=~s/ù/u/g;
    $content=~s/û/u/g;
    $content=~s/\u0169/u/g; # Kl. u mit Tilde
    $content=~s/\u016b/u/g; # Kl. u mit Ueberstrich/Macron
    $content=~s/\u016d/u/g; # Kl. u mit Hacek/Breve
    $content=~s/\u0171/u/g; # Kl. u mit Doppel-Acute
    $content=~s/\u016f/u/g; # Kl. u mit Ring oben

    $content=~s/ø/o/g;
    $content=~s/Ø/o/g;

    $content=~s/ñ/n/g;
    $content=~s/\u0144/n/g; # Kl. n mit Acute
    $content=~s/\u0146/n/g; # Kl. n mit Cedille
    $content=~s/\u0148/n/g; # Kl. n mit Caron

    $content=~s/Ñ/N/g;
    $content=~s/\u0143/N/g; # Gr. N mit Acute
    $content=~s/\u0145/N/g; # Gr. N mit Cedille
    $content=~s/\u0147/N/g; # Gr. N mit Caron

    $content=~s/\u0155/r/g; # Kl. r mit Acute
    $content=~s/\u0157/r/g; # Kl. r mit Cedille
    $content=~s/\u0159/r/g; # Kl. r mit Caron

    $content=~s/\u0154/R/g; # Gr. R mit Acute
    $content=~s/\u0156/R/g; # Gr. R mit Cedille
    $content=~s/\u0158/R/g; # Gr. R mit Caron

    $content=~s/\u015b/s/g; # Kl. s mit Acute
    $content=~s/\u015d/s/g; # Kl. s mit Circumflexe
    $content=~s/\u015f/s/g; # Kl. s mit Cedille
    $content=~s/š/s/g; # Kl. s mit Caron

    $content=~s/\u015a/S/g; # Gr. S mit Acute
    $content=~s/\u015c/S/g; # Gr. S mit Circumflexe
    $content=~s/\u015e/S/g; # Gr. S mit Cedille
    $content=~s/Š/S/g; # Gr. S mit Caron

    $content=~s/\u0167/t/g; # Kl. t mit Mittelstrich
    $content=~s/\u0163/t/g; # Kl. t mit Cedille
    $content=~s/\u0165/t/g; # Kl. t mit Caron

    $content=~s/\u0166/T/g; # Gr. T mit Mittelstrich
    $content=~s/\u0162/T/g; # Gr. T mit Cedille
    $content=~s/\u0164/T/g; # Gr. T mit Caron

    $content=~s/\u017a/z/g; # Kl. z mit Acute
    $content=~s/\u017c/z/g; # Kl. z mit Punkt oben
    $content=~s/ž/z/g; # Kl. z mit Caron

    $content=~s/\u0179/Z/g; # Gr. Z mit Acute
    $content=~s/\u017b/Z/g; # Gr. Z mit Punkt oben
    $content=~s/Ž/Z/g; # Gr. Z mit Caron

    $content=~s/ç/c/g;
    $content=~s/\u0107/c/g; # Kl. c mit Acute
    $content=~s/\u0108/c/g; # Kl. c mit Circumflexe
    $content=~s/\u010b/c/g; # Kl. c mit Punkt oben
    $content=~s/\u010d/c/g; # Kl. c mit Caron
    
    $content=~s/Ç/c/g;
    $content=~s/\u0106/C/g; # Gr. C mit Acute
    $content=~s/\u0108/C/g; # Gr. C mit Circumflexe
    $content=~s/\u010a/C/g; # Gr. C mit Punkt oben
    $content=~s/\u010c/C/g; # Gr. C mit Caron

    $content=~s/\u010f/d/g; # Kl. d mit Caron
    $content=~s/\u010e/D/g; # Gr. D mit Caron

    $content=~s/\u0123/g/g; # Kl. g mit Cedille
    $content=~s/\u011f/g/g; # Kl. g mit Breve
    $content=~s/\u011d/g/g; # Kl. g mit Circumflexe
    $content=~s/\u0121/g/g; # Kl. g mit Punkt oben

    $content=~s/\u0122/G/g; # Gr. G mit Cedille
    $content=~s/\u011e/G/g; # Gr. G mit Breve
    $content=~s/\u011c/G/g; # Gr. G mit Circumflexe
    $content=~s/\u0120/G/g; # Gr. G mit Punkt oben

    $content=~s/\u0127/h/g; # Kl. h mit Ueberstrich
    $content=~s/\u0126/H/g; # Gr. H mit Ueberstrich

    $content=~s/\u0137/k/g; # Kl. k mit Cedille
    $content=~s/\u0136/K/g; # Gr. K mit Cedille

    $content=~s/\u013c/l/g; # Kl. l mit Cedille
    $content=~s/\u013a/l/g; # Kl. l mit Acute
    $content=~s/\u013e/l/g; # Kl. l mit Caron
    $content=~s/\u0140/l/g; # Kl. l mit Punkt mittig
    $content=~s/\u0142/l/g; # Kl. l mit Querstrich

    $content=~s/\u013b/L/g; # Gr. L mit Cedille
    $content=~s/\u0139/L/g; # Gr. L mit Acute
    $content=~s/\u013d/L/g; # Gr. L mit Caron
    $content=~s/\u013f/L/g; # Gr. L mit Punkt mittig
    $content=~s/\u0141/L/g; # Gr. L mit Querstrick

    $content=~s/\u20ac/e/g;   # Euro-Zeichen
    $content=~s/\u0152/oe/g;  # OE-Ligatur
    $content=~s/\u0153/oe/g;  # oe-Ligatur
    $content=~s/Æ/ae/g;       # AE-Ligatur
    $content=~s/æ/ae/g;       # ae-Ligatur
    $content=~s/\u0160/s/g;   # S hacek
    $content=~s/\u0161/s/g;   # s hacek
    $content=~s/\u017d/z/g;   # Z hacek
    $content=~s/\u017e/z/g;   # z hacek
    $content=~s/\u0178/y/g;   # Y Umlaut
    $content=~s/¡/i/g;        # i Ueberstrich
    $content=~s/¢/c/g;        # Cent
    $content=~s/£/l/g;        # Pfund
    $content=~s/¥/y/g;        # Yen
    $content=~s/µ/u/g;        # Mikro
    
    $content=~s/Ð/e/g;        # Gr. Islaend. E (durchgestrichenes D)
    $content=~s/\u0111/e/g;   # Kl. Islaend. e ? (durchgestrichenes d)

    $content=~s/Ý/y/g;
    $content=~s/ý/y/g;
    $content=~s/Þ/th/g;       # Gr. Thorn
    $content=~s/þ/th/g;       # kl. Thorn
    $content=~s/ð/eth/g;      # eth

    return $content;
}

sub get_loadbalanced_servername {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $ua=new LWP::UserAgent(timeout => 5);

    # Aktuellen Load der Server holen zur dynamischen Lastverteilung
    my @servertab=@{$config->{loadbalancertargets}};

    my %serverload=();

    foreach my $target (@servertab) {
        $serverload{"$target"}=-1.0;
    }
  
    my $problem=0;
  
    # Fuer jeden Server, auf den verteilt werden soll, wird nun
    # per LWP der Load bestimmt.
    foreach my $targethost (@servertab) {
        my $request  = new HTTP::Request POST => "http://$targethost$config->{serverload_loc}";
        my $response = $ua->request($request);

        if ($response->is_success) {
            $logger->debug("Getting ", $response->content);
        }
        else {
            $logger->error("Getting ", $response->status_line);
        }
    
        my $content=$response->content();
    
        if ($content eq "" || $content=~m/SessionDB: offline/m) {
            $problem=1;
        }
        elsif ($content=~m/^Load: (\d+\.\d+)/m) {
            my $load=$1;
            $serverload{$targethost}=$load;
        }
    
        # Wenn der Load fuer einen Server nicht bestimmt werden kann,
        # dann wird der Admin darueber benachrichtigt
    
        if ($problem == 1) {
            OpenBib::LoadBalancer::Util::benachrichtigung("Es ist der Server $targethost ausgefallen");
            $problem=0;
            next;
        }
    }
  
    my $minload="1000.0";
    my $bestserver="";

    # Nun wird der Server bestimmt, der den geringsten Load hat

    foreach my $targethost (@servertab) {
        if ($serverload{$targethost} > -1.0 && $serverload{$targethost} <= $minload) {
            $bestserver=$targethost;
            $minload=$serverload{$targethost};
        }
    }

    return $bestserver;
}

sub normset2bibtex {
    my ($normset_ref,$utf8)=@_;

    my $bibtex_ref=[];

    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $normset_ref->{$category});
        foreach my $part_ref (@{$normset_ref->{$category}}){
            if ($part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
            else {
                push @$authors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
        }
    }
    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $normset_ref->{$category});
        foreach my $part_ref (@{$normset_ref->{$category}}){
            push @$keywords_ref, utf2bibtex($part_ref->{content},$utf8);
        }
    }
    my $keyword = join(' ; ',@$keywords_ref);
    
    # Auflage
    my $edition   = (exists $normset_ref->{T0403})?utf2bibtex($normset_ref->{T0403}[0]{content},$utf8):'';

    # Verleger
    my $publisher = (exists $normset_ref->{T0412})?utf2bibtex($normset_ref->{T0412}[0]{content},$utf8):'';

    # Verlagsort
    my $address   = (exists $normset_ref->{T0410})?utf2bibtex($normset_ref->{T0410}[0]{content},$utf8):'';

    # Titel
    my $title     = (exists $normset_ref->{T0331})?utf2bibtex($normset_ref->{T0331}[0]{content},$utf8):'';

    # Zusatz zum Titel
    my $titlesup  = (exists $normset_ref->{T0335})?utf2bibtex($normset_ref->{T0335}[0]{content},$utf8):'';

    if ($title && $titlesup){
        $title = "$title : $titlesup";
    }

    # Jahr
    my $year      = (exists $normset_ref->{T0425})?utf2bibtex($normset_ref->{T0425}[0]{content},$utf8):'';

    # ISBN
    my $isbn      = (exists $normset_ref->{T0540})?utf2bibtex($normset_ref->{T0540}[0]{content},$utf8):'';

    # ISSN
    my $issn      = (exists $normset_ref->{T0543})?utf2bibtex($normset_ref->{T0543}[0]{content},$utf8):'';

    # Sprache
    my $language  = (exists $normset_ref->{T0516})?utf2bibtex($normset_ref->{T0516}[0]{content},$utf8):'';

    # Abstract
    my $abstract  = (exists $normset_ref->{T0750})?utf2bibtex($normset_ref->{T0750}[0]{content},$utf8):'';

    # Origin
    my $origin    = (exists $normset_ref->{T0590})?utf2bibtex($normset_ref->{T0590}[0]{content},$utf8):'';

    if ($author){
        push @$bibtex_ref, "author    = \"$author\"";
    }
    if ($editor){
        push @$bibtex_ref, "editor    = \"$editor\"";
    }
    if ($edition){
        push @$bibtex_ref, "edition   = \"$edition\"";
    }
    if ($publisher){
        push @$bibtex_ref, "publisher = \"$publisher\"";
    }
    if ($address){
        push @$bibtex_ref, "address   = \"$address\"";
    }
    if ($title){
        push @$bibtex_ref, "title     = \"$title\"";
    }
    if ($year){
        push @$bibtex_ref, "year      = \"$year\"";
    }
    if ($isbn){
        push @$bibtex_ref, "ISBN      = \"$isbn\"";
    }
    if ($issn){
        push @$bibtex_ref, "ISSN      = \"$issn\"";
    }
    if ($keyword){
        push @$bibtex_ref, "keywords  = \"$keyword\"";
    }
    if ($language){
        push @$bibtex_ref, "language  = \"$language\"";
    }
    if ($abstract){
        push @$bibtex_ref, "abstract  = \"$abstract\"";
    }

    if ($origin){
        # Pages
        if ($origin=~/ ; (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }
        elsif ($origin=~/, (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }

        # Journal and/or Volume
        if ($origin=~/^(.+?) ; (.*?) ; S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), (\d\d\d\d), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;
            my $year    = $3;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?) ; (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.*?) ; S\. *\d+.*$/){
            my $journal = $1;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
        }
    }

    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    my $bibtex="";

    if ($origin){
        unshift @$bibtex_ref, "\@article {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    elsif ($isbn){
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    else {
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }

    
    return $bibtex;
}

sub utf2bibtex {
    my ($string,$utf8)=@_;

    return "" if (!defined $string);
    
    # {} werden von BibTeX verwendet und haben in den Originalinhalten
    # nichts zu suchen
    $string=~s/\{//g;
    $string=~s/\}//g;
    # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
    $string=~s/[^-+\p{Alphabetic}0-9\n\/&;#: '()@<>\\,.="^*[]]//g;
    $string=~s/&lt;/</g;
    $string=~s/&gt;/>/g;
    $string=~s/&amp;/&/g;

    # Wenn utf8 ausgegeben werden soll, dann sind wir hier fertig
    return $string if ($utf8);

    # ... ansonsten muessen weitere Sonderzeichen umgesetzt werden.
    $string=~s/&#172;//g;
    $string=~s/&#228;/{\\"a}/g;
    $string=~s/&#252;/{\\"u}/g;
    $string=~s/&#246;/{\\"o}/g;
    $string=~s/&#223;/{\\"s}/g;
    $string=~s/&#214;/{\\"O}/g;
    $string=~s/&#220;/{\\"U}/g;
    $string=~s/&#196;/{\\"A}/g;
    $string=~s/&auml;/{\\"a}/g;
    $string=~s/&ouml;/{\\"o}/g;
    $string=~s/&uuml;/{\\"u}/g;
    $string=~s/&Auml;/{\\"A}/g;
    $string=~s/&Ouml;/{\\"O}/g;
    $string=~s/&Uuml;/{\\"U}/g;
    $string=~s/&szlig;/{\\"s}/g;
    $string=~s/ä/{\\"a}/g;
    $string=~s/ö/{\\"o}/g;
    $string=~s/ü/{\\"u}/g;
    $string=~s/Ä/{\\"A}/g;
    $string=~s/Ö/{\\"O}/g;
    $string=~s/Ü/{\\"U}/g;
    $string=~s/ß/{\\"s}/g;

    return $string;
}

1;
__END__

=head1 NAME

 OpenBib::Common::Util - Gemeinsame Funktionen der OpenBib-Module

=head1 DESCRIPTION

 In OpenBib::Common::Util sind all jene Funktionen untergebracht, die 
 von mehr als einem mod_perl-Modul verwendet werden. Es sind dies 
 Funktionen aus den Bereichen Session- und User-Management, Ausgabe 
 von Webseiten oder deren Teilen und Interaktionen mit der 
 Katalog-Datenbank.

=head1 SYNOPSIS

 use OpenBib::Common::Util;

 # Stylesheet-Namen aus mod_perl Request-Object (Browser-Typ) bestimmen
 my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

 # eine neue Session erzeugen und Rueckgabe der $sessionID
 my $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);

 # Ist die Session gueltig? Nein, dann Warnung und Ausstieg
 unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
   OpenBib::Search::Util::print_warning("Warnungstext",$r);
   exit;
 }

 # Komplette Seite aus Template $templatename, Template-Daten $ttdata und
 # Request-Objekt $r bilden und ausgeben
 OpenBib::Common::Util::print_page($templatename,$ttdata,$r);

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
