#####################################################################
#
#  OpenBib::SearchQuery
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::SearchQuery;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use Apache2::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use JSON::XS qw(encode_json decode_json);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use String::Tokenizer;
use Text::Aspell;
use Search::Xapian;
use YAML;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Database::DBI;
use OpenBib::VirtualSearch::Util;

sub _new_instance {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $self = {
        _databases             => [],
        _have_searchterms      => 0,
    };

    foreach my $searchfield (keys %{$config->{searchfield}}){
        $self->{_searchquery}{$searchfield} = {
            norm => '',
            val  => '',
            bool => '',
        };
    }

    bless ($self, $class);

    return $self;
}

sub set_from_apache_request {
    my ($self,$r,$dbases_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query = Apache2::Request->new($r);

    my ($ejahrop,$indexterm,$indextermnorm);

    # Wandlungstabelle Erscheinungsjahroperator
    my $ejahrop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    my $legacy_bool_op_ref = {
        'boolhst'       => 'bool1',
        'boolswt'       => 'bool2',
        'boolkor'       => 'bool3',
        'boolnotation'  => 'bool4',
        'boolisbn'      => 'bool5',
        'boolsign'      => 'bool6',
        'boolejahr'     => 'bool7',
        'boolissn'      => 'bool8',
        'boolverf'      => 'bool9',
        'boolfs'        => 'bool10',
        'boolmart'      => 'bool11',
        'boolhststring' => 'bool12',
    };

    # Sicherheits-Checks

    my $valid_bools_ref = {
        'AND' => 'AND',
        'OR'  => 'OR',
        'NOT' => 'AND NOT',
    };

    # (Re-)Initialisierung
    delete $self->{_hits}          if (exists $self->{_hits});
    delete $self->{_searchquery}   if (exists $self->{_searchquery});
    delete $self->{_id}            if (exists $self->{_id});

    $self->{_searchquery} = {};

    # Suchfelder einlesen
    foreach my $searchfield (keys %{$config->{searchfield}}){
        my ($searchfield_content, $searchfield_norm_content,$searchfield_bool_op);
        $searchfield_content = $searchfield_norm_content = decode_utf8($query->param("$searchfield")) || $query->param("$searchfield")      || '';
        $searchfield_bool_op = ($query->param("bool$searchfield"))?$query->param("bool$searchfield"):
            ($query->param($legacy_bool_op_ref->{"bool$searchfield"}))?$query->param($legacy_bool_op_ref->{"bool$searchfield"}):"AND";
        
        # Inhalts-Check
        $searchfield_bool_op = (exists $valid_bools_ref->{$searchfield_bool_op})?$valid_bools_ref->{$searchfield_bool_op}:"AND";
        
        #####################################################################
        ## searchfield_content: Inhalt der Suchfelder des Nutzers

        $self->{_searchquery}->{$searchfield}->{val}  = $searchfield_content;

        #####################################################################
        ## searchfield_bool_op: Verknuepfung der Eingabefelder (leere Felder werden ignoriert)
        ##        AND  - Und-Verknuepfung
        ##        OR   - Oder-Verknuepfung
        ##        NOT  - Und Nicht-Verknuepfung

        $self->{_searchquery}->{$searchfield}->{bool} = $searchfield_bool_op;

        if ($searchfield_norm_content){
            # Zuerst Stringsuchen in der Freie Suche

            if ($searchfield eq "fs" || $searchfield_norm_content=~/:|.+?|/){
                while ($searchfield_norm_content=~m/^([^\|]+)\|([^\|]+)\|(.*)$/){
                    my $first = $1;
                    my $string = $2;
                    my $last = $3;

                    $string = OpenBib::Common::Util::grundform({
                        content   => $string,
                        searchreq => 1,
                    });

                    $string=~s/\W/_/g;
                    
                    $logger->debug("1: $first String: $string 3: $last");
                    
                    $searchfield_norm_content=$first.$string.$last;
                }
            }
            
            if ($config->{'searchfield'}{$searchfield}{option} eq "filter_isbn"){
                $searchfield_norm_content = lc($searchfield_norm_content);
                # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
                $searchfield_norm_content =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
                $searchfield_norm_content =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
            }

            # Entfernung der Minus-Zeichen bei der ISSN
            if ($config->{'searchfield'}{$searchfield}{option} eq "filter_issn"){
                $searchfield_norm_content = lc($searchfield_norm_content);
                $searchfield_norm_content =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8/g;
            }

            if ($config->{'searchfield'}{$searchfield}{option} eq "strip_first_stopword"){
                 $searchfield_norm_content = OpenBib::Common::Util::grundform({
                     category  => "0331", # Exemplarisch fuer die Kategorien, bei denen das erste Stopwort entfernt wird
                     content   => $searchfield_norm_content,
                     searchreq => 1,
                 });
            }
            else {
                 $searchfield_norm_content = OpenBib::Common::Util::grundform({
                     content   => $searchfield_norm_content,
                     searchreq => 1,
                 });
            }

            if ($config->{'searchfield'}{$searchfield}{type} eq "string"){
                $searchfield_norm_content =~s/\W/_/g;
            }
            
            if ($searchfield_norm_content){
                $self->{_have_searchterms} = 1;
                $self->{_searchquery}{$searchfield}{norm} = $searchfield_norm_content;
            }

            $logger->debug("Added searchterm $searchfield_bool_op - $searchfield_content - $searchfield_norm_content");
        }
        
    }

    # Parameter einlesen
    $ejahrop   =                  decode_utf8($query->param('ejahrop'))       || $query->param('ejahrop') || 'eq';    
    $indexterm = $indextermnorm = decode_utf8($query->param('indexterm'))     || $query->param('indexterm')|| '';

    my $autoplus      = $query->param('autoplus')      || '';
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    # Setzen der arithmetischen Ejahrop-Operatoren
    if (exists $ejahrop_ref->{$ejahrop}){
        $ejahrop=$ejahrop_ref->{$ejahrop};
    }
    else {
        $ejahrop="=";
    }

    if (exists $self->{_searchquery}->{ejahr}){
       $self->{_searchquery}->{ejahr}->{arg}= $ejahrop;
    }

    if ($indexterm){
        $indextermnorm  = OpenBib::Common::Util::grundform({
           content   => $indextermnorm,
           searchreq => 1,
        });

        $self->{_searchquery}->{indexterm}={
	    val   => $indexterm,
	    norm  => $indextermnorm,
        };
    }

    my %seen_dbases = ();

    if (defined $dbases_ref){
        @{$self->{_databases}} = grep { ! $seen_dbases{$_} ++ } @{$dbases_ref};
    }

    $logger->debug("SearchQuery from Apache-Request ".YAML::Dump($self));
    
    return $self;
}


sub set {
    my ($self,$r,$dbases_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query = Apache2::Request->new($r);

    # Wandlungstabelle Erscheinungsjahroperator
    my $ejahrop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    my ($fs, $verf, $hst, $hststring, $gtquelle, $swt, $kor, $sign, $inhalt, $isbn, $issn, $mart,$notation,$ejahr,$ejahrop);

    my ($fsnorm, $verfnorm, $hstnorm, $hststringnorm, $gtquellenorm, $swtnorm, $kornorm, $signnorm, $inhaltnorm, $isbnnorm, $issnnorm, $martnorm,$notationnorm,$ejahrnorm,$indexterm,$indextermnorm);
    
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

    $indexterm = $indextermnorm = decode_utf8($query->param('indexterm'))     || $query->param('indexterm')|| '';

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
        :($query->param('bool9'))?$query->param('bool9'):"AND";
    my $boolhst       = ($query->param('boolhst'))      ?$query->param('boolhst')
        :($query->param('bool1'))?$query->param('bool1'):"AND";
    my $boolswt       = ($query->param('boolswt'))      ?$query->param('boolswt')
        :($query->param('bool2'))?$query->param('bool2'):"AND";
    my $boolkor       = ($query->param('boolkor'))      ?$query->param('boolkor')
        :($query->param('bool3'))?$query->param('bool3'):"AND";
    my $boolnotation  = ($query->param('boolnotation')) ?$query->param('boolnotation')
        :($query->param('bool4'))?$query->param('bool4'):"AND";
    my $boolisbn      = ($query->param('boolisbn'))     ?$query->param('boolisbn')
        :($query->param('bool5'))?$query->param('bool5'):"AND";
    my $boolissn      = ($query->param('boolissn'))     ?$query->param('boolissn')
        :($query->param('bool8'))?$query->param('bool8'):"AND";
    my $boolsign      = ($query->param('boolsign'))     ?$query->param('boolsign')
        :($query->param('bool6'))?$query->param('bool6'):"AND";
    my $boolinhalt    = ($query->param('boolinhalt'))   ?$query->param('boolinhalt')
        :"AND";
    my $boolejahr     = ($query->param('boolejahr'))    ?$query->param('boolejahr')
        :($query->param('bool7'))?$query->param('bool7'):"AND";
    my $boolfs        = ($query->param('boolfs'))       ?$query->param('boolfs')
        :($query->param('bool10'))?$query->param('bool10'):"AND";
    my $boolmart      = ($query->param('boolmart'))     ?$query->param('boolmart')
        :($query->param('bool11'))?$query->param('bool11'):"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring')
        :($query->param('bool12'))?$query->param('bool12'):"AND";
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

    $indextermnorm  = OpenBib::Common::Util::grundform({
        content   => $indextermnorm,
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

    # (Re-)Initialisierung
    delete $self->{_hits}          if (exists $self->{_hits});
    delete $self->{_searchquery}   if (exists $self->{_searchquery});
    delete $self->{_id}            if (exists $self->{_id});

    $self->{_searchquery} = {};
        
    if ($fs){
      $self->{_searchquery}->{fs}={
			      val   => $fs,
			      norm  => $fsnorm,
			      bool  => '',
			     };
    }

    if ($hst){
      $self->{_searchquery}->{hst}={
			       val   => $hst,
			       norm  => $hstnorm,
			       bool  => $boolhst,
			      };
    }

    if ($hststring){
      $self->{_searchquery}->{hststring}={
				     val   => $hststring,
				     norm  => $hststringnorm,
				     bool  => $boolhststring,
				    };
    }

    if ($gtquelle){
      $self->{_searchquery}->{gtquelle}={
			    val   => $gtquelle,
			    norm  => $gtquellenorm,
			    bool  => $boolgtquelle,
			   };
    }

    if ($inhalt){
      $self->{_searchquery}->{inhalt}={
			    val   => $inhalt,
			    norm  => $inhaltnorm,
			    bool  => $boolinhalt,
			   };
    }

    if ($verf){
      $self->{_searchquery}->{verf}={
			    val   => $verf,
			    norm  => $verfnorm,
			    bool  => $boolverf,
			   };
    }

    if ($swt){
      $self->{_searchquery}->{swt}={
			       val   => $swt,
			       norm  => $swtnorm,
			       bool  => $boolswt,
			      };
    }

    if ($kor){
      $self->{_searchquery}->{kor}={
			       val   => $kor,
			       norm  => $kornorm,
			       bool  => $boolkor,
			      };
    }

    if ($sign){
      $self->{_searchquery}->{sign}={
				val   => $sign,
				norm  => $signnorm,
				bool  => $boolsign,
			       };
    }

    if ($isbn){
      $self->{_searchquery}->{isbn}={
				val   => $isbn,
				norm  => $isbnnorm,
				bool  => $boolisbn,
			     };
    }

    if ($issn){
      $self->{_searchquery}->{issn}={
				val   => $issn,
				norm  => $issnnorm,
				bool  => $boolissn,
			     };
    }

    if ($mart){
      $self->{_searchquery}->{mart}={
				val   => $mart,
				norm  => $martnorm,
				bool  => $boolmart,
			       };
    }

    if ($notation){
      $self->{_searchquery}->{notation}={
				    val   => $notation,
				    norm  => $notationnorm,
				    bool  => $boolnotation,
				   };
    }

    if ($ejahr){
      $self->{_searchquery}->{ejahr}={
			    val   => $ejahr,
			    norm  => $ejahrnorm,
			    bool  => $boolejahr,
			    arg   => $ejahrop,
			   };
    }

    if ($indexterm){
      $self->{_searchquery}->{indexterm}={
			    val   => $indexterm,
			    norm  => $indextermnorm,
			   };
    }

    if (defined $dbases_ref){
        $self->{_databases}=$dbases_ref;
    }

    $logger->debug(YAML::Dump($self));
    
    return $self;
}

sub load  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sessionID              = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}           : undef;
    my $queryid                = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select query,hits,dbases from queries where sessionID = ? and queryid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID,$queryid) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();

    $self->from_json($res->{query});

    $logger->debug("Stored Databases as string: ".$res->{dbases});
    
    my @databases         = split('\|\|',$res->{dbases});

    $logger->debug("Stored Databases: ".join(',',@databases));
    $self->{_databases}   = \@databases;
    
    $idnresult->finish();

    return $self;
}

sub save  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sessionID              = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}           : undef;
    my $hitrange               = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}            : 50;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    unless ($sessionID && $self->{_id}){
        return $self;
    }
    
    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $query_obj_string = "";
    
    if ($config->{internal_serialize_type} eq "packed_storable"){
        $query_obj_string = unpack "H*", Storable::freeze($self);
    }
    elsif ($config->{internal_serialize_type} eq "json"){
        $query_obj_string = encode_json $self;
    }
    else {
        $query_obj_string = unpack "H*", Storable::freeze($self);
    }

    my $databases_string = join('\|\|',@{$self->{_databases}});

    $logger->debug("Query Object: ".$query_obj_string);
    $logger->debug("Query Databases: ".$databases_string);
    
    my $request=$dbh->prepare("delete from queries where queryid=? and sessionid=?") or $logger->error($DBI::errstr);
    $request->execute($self->{_id},$sessionID) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into queries (queryid,sessionid,query,hitrange,hits,dbases) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{_id},$sessionID,$query_obj_string,$hitrange,$self->{_hits},$databases_string) or $logger->error($DBI::errstr);

    $logger->debug("Saving SearchQuery: queryid,sessionid,query_obj_string,hitrange,hits,dbases = $self->{_id},$sessionID,$query_obj_string,$hitrange,$self->{_hits},$databases_string");
    $request->finish();

    return $self;
}


sub get_searchquery {
    my ($self)=@_;

    return $self->{_searchquery};
}

sub to_cgi_params {
    my ($self)=@_;

    my @cgiparams = ();

    foreach my $param (keys %{$self->{_searchquery}}){
        push @cgiparams, "bool$param=".$self->{_searchquery}->{$param}{bool};
        push @cgiparams, "$param=".$self->{_searchquery}->{$param}{val};
    }
    
    return join(";",@cgiparams);
}

sub get_hits {
    my ($self)=@_;

    return $self->{_hits};
}

sub get_id {
    my ($self)=@_;

    return $self->{_id};
}

sub get_databases {
    my ($self)=@_;

    return $self->{_databases};
}

sub get_searchfield {
    my ($self,$fieldname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug($fieldname);

    $logger->debug(YAML::Dump($self));
    return (exists $self->{_searchquery}->{$fieldname})?$self->{_searchquery}->{$fieldname}:{val => '', norm => '', bool => '', args => ''};
}

sub get_searchterms {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $term_ref = [];

    my @allterms = ();
    foreach my $cat (keys %{$self->{_searchquery}}){
        push @allterms, $self->{_searchquery}->{$cat}->{val} if ($self->{_searchquery}->{$cat}->{val});
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

sub to_xapian_querystring {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Aufbau des xapianquerystrings
    my @xapianquerystrings = ();
    my $xapianquerystring  = "";

    my $ops_ref = {
        'AND'     => '+',
        'AND NOT' => '-',
        'OR'      => '',
    };

    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $self->{_searchquery}->{$field}->{norm})?$self->{_searchquery}->{$field}->{norm}:'';
        my $searchtermop     = (defined $self->{_searchquery}->{$field}->{bool} && defined $ops_ref->{$self->{_searchquery}->{$field}->{bool}})?$ops_ref->{$self->{_searchquery}->{$field}->{bool}}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if ($field eq "fs" && $searchtermstring) {
#                 my @searchterms = split('\s+',$searchtermstring);
                
#                 # Inhalte von @searchterms mit Suchprefix bestuecken
#                 foreach my $searchterm (@searchterms){                    
#                     $searchterm="+".$searchtermstring if ($searchtermstring=~/^\w/);
#                 }
#                 $searchtermstring = "(".join(' ',@searchterms).")";

                push @xapianquerystrings, $searchtermstring;
            }
            # Titelstring mit _ ersetzten
            elsif (($field eq "hststring" || $field eq "sign") && $searchtermstring) {
                my @chars = split("",$searchtermstring);
                my $newsearchtermstring = "";
                foreach my $char (@chars){
                    if ($char ne "*"){
                        $char=~s/\W/_/g;
                    }
                    $newsearchtermstring.=$char;
                }
                    
                $searchtermstring=$searchtermop.$config->{searchfield}{$field}{prefix}.":$newsearchtermstring";
                push @xapianquerystrings, $searchtermstring;                
            }
            # Sonst Operator und Prefix hinzufuegen
            elsif ($searchtermstring) {
                $searchtermstring=$searchtermop.$config->{searchfield}{$field}{prefix}.":($searchtermstring)";
                push @xapianquerystrings, $searchtermstring;                
            }

            # Innerhalb einer freien Suche wird Standardmaessig UND-Verknuepft
            # Nochmal explizites Setzen von +, weil sonst Wildcards innerhalb mehrerer
            # Suchterme ignoriert werden.

        }
    }

    $xapianquerystring = join(" ",@xapianquerystrings);

    $logger->debug("Xapian-Querystring: $xapianquerystring");
    return $xapianquerystring;
}

sub get_spelling_suggestion {
    my ($self,$lang) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $suggestions_ref = {};
    my $searchterms_ref = $self->get_searchterms;

    my $speller = Text::Aspell->new;

    $speller->set_option('lang','de_DE');
    $speller->set_option('sug-mode','normal');
    $speller->set_option('ignore-case','true');
    
    # Kombinierter Datenbank-Handle fuer Xapian generieren, um spaeter damit Term-Frequenzen abfragen zu koennen
    my $dbh;            
    foreach my $database (@{$self->{_databases}}) {
        $logger->debug("Adding Xapian DB-Object for database $database");
        
        if (!defined $dbh){
            # Erstes Objekt erzeugen,
            
            $logger->debug("Creating Xapian DB-Object for database $database");                
            
            eval {
                $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
            };
            
            if ($@){
                $logger->error("Database: $database - :".$@." falling back to sql Backend");
            }
        }
        else {
            $logger->debug("Adding database $database");
            
            eval {
                $dbh->add_database(new Search::Xapian::Database( $config->{xapian_index_base_path}."/".$database));
            };
            
            if ($@){
                $logger->error("Database: $database - :".$@);
            }                        
        }
    }
                          
    my $atime=new Benchmark;
                          
    # Bestimmung moeglicher Rechtschreibvorschlaege fuer die einzelnen Begriffe
    foreach my $term (@{$searchterms_ref}){
        # Nur Vorschlaege sammeln, wenn der Begriff nicht im Woerterbuch vorkommt
        my @aspell_suggestions = ($speller->check($term))?():$speller->suggest( $term );

        $logger->debug("Aspell suggestions".YAML::Dump(\@aspell_suggestions));

        my $valid_suggestions_ref  = [];
        my $sorted_suggestions_ref = [];

        if (defined $dbh){
            my $this_term = OpenBib::Common::Util::grundform({
                content   => $term,
                searchreq => 1,
            });
            
            my $this_termfreq = $dbh->get_termfreq($this_term);            

            # Verwende die 5 besten Vorschlaege
            foreach my $suggested_term (@aspell_suggestions[0..4]){
                next unless ($suggested_term);
                my $suggested_term = OpenBib::Common::Util::grundform({
                    content   => $suggested_term,
                    searchreq => 1,
                });

                my $termfreq = $dbh->get_termfreq($suggested_term);            

                # Nur Worte, die haeufiger als der Suchbegriff vorkommen, werden beruecksichtigt
                push @{$valid_suggestions_ref}, {
                    val  => $suggested_term,
                    freq => $termfreq,
                } if ($termfreq > $this_termfreq);                
            }
            
            $logger->info(YAML::Dump($valid_suggestions_ref));
            
             @{$sorted_suggestions_ref} =
                 map { $_->[0] }
                     sort { $b->[1] <=> $a->[1] }
                         map { [$_, $_->{freq}] } @{$valid_suggestions_ref};

            $suggestions_ref->{$term} = $sorted_suggestions_ref;
#            $suggestions_ref->{$term} = $valid_suggestions_ref;
        }        
    }

    # Suchvorschlag nur dann, wenn mindestens einer der Begriffe
    # a) nicht im Woerterbuch ist *und*
    # b) seine Termfrequest nicht hoeher als die Vorschlaege sind
    my $have_suggestion = 0;
    foreach my $term (@{$searchterms_ref}){
        # Mindestens ein Suchvorschlag?
        if (exists $suggestions_ref->{$term}[0]){
            $have_suggestion = 1;
        }
    }

    my $suggestion_string="";
    if ($have_suggestion){
        my @tmpsuggestions = ();
        foreach my $term (@{$searchterms_ref}){
            if (exists $suggestions_ref->{$term}[0]{val}){
                push @tmpsuggestions, $suggestions_ref->{$term}[0]{val};
            }
            else {
                push @tmpsuggestions, $term;
            }
        }
        $suggestion_string = join(' ',@tmpsuggestions);
    }
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("Spelling suggestions took $resulttime seconds");

    return $suggestion_string;
}

sub have_searchterms {
    my ($self) = @_;

    return $self->{_have_searchterms};
}

sub to_json {
    my ($self) = @_;

    my $tmp_ref = {};
    foreach my $property (sort keys %{$self}){
        $tmp_ref->{$property} = $self->{$property};
    }
    
    return encode_json $tmp_ref;
}

sub from_json {
    my ($self,$json) = @_;

    return unless ($json);
    
    my $tmp_ref = decode_json $json;
    foreach my $property (keys %{$tmp_ref}){
        $self->{$property} = $tmp_ref->{$property};
    }

    return $self;
}
    
1;
__END__

=head1 NAME

OpenBib::SearchQuery - Apache-Singleton der vom Nutzer eingegebenen
Suchanfrage

=head1 DESCRIPTION

Dieses Apache-Singleton verwaltet die vom Nutzer eingegebene Suchanfrage.

=head1 SYNOPSIS

 use OpenBib::SearchQuery;

 my $searchquery   = OpenBib::SearchQuery->instance;

=head1 METHODS

=over 4

=item instance

Instanziierung des Apache-Singleton. Zu jedem Suchbegriff lässt sich
neben der eingegebenen Form vol auch die Normierung norm, der
zugehörige Bool'sche Verknüpfungsparameter bool sowie die ausgewählten
Datenbanken speichern.

=item set_from_apache_request($r,$dbases_ref)

Setzen der Suchbegriffe direkt aus dem Apache-Request samt übergebener
Suchoptionen und zusätzlicher Normierung der Suchbegriffe.

=item load({ sessionID => $sessionID, queryid => $queryid })

Laden der Suchanfrage zu $queryid in der Session $sessionID

=item get_searchquery

Liefert die Suchanfrage zurück.

=item to_cgi_params

Liefert einen CGI-Teilstring der Suchbegriffe mit ihren Bool'schen Operatoren zurück.

=item get_hits

Liefert die Treffferzahl der aktuellen Suchanfrage zurück.

=item get_id

Liefert die zugehörige Query-ID zurück.

=item get_databases

Liefert die ausgewählten Datenbanken zur Suchanfrage zurück.

=item get_searchfield($fieldname)

Liefert den Inhalt des Suchfeldes $fieldname zurück.

=item get_searchterms

Liefert Listenreferenz auf alle tokenizierten Suchbegriffe zurück.

=item to_sql_querystring

Liefert den SQL-Anfragestring zur Suchanfrage zurück

=item to_sql_queryargs

Liefert die zum SQL-Anfragestring zugehörigen Parameterwerte(= Begriffe pro Suchfeld) als Liste zurück.

=item to_xapian_querystring

Liefert den Xapian-Anfragestring zur Suchanfrage zurück

=item get_spelling_suggestion

Liefert entsprechend der Suchbegriffe, des Aspell-Wörterbuchs der
Sprache de_DE sowie des Vorkommens im Xapian-Index den relevantesten
Rechschreibvorschlag zurück.

=item from_json($json_string)

Speichert die im JSON-Format übergebenen Attribute  im Objekt ab.

=item to_json

Liefert die im Objekt gespeicherten Attribute im JSON-Format zurück.

=item have_searchterms

Liefert einen nicht Null-Wert zurück, wenn mindestens ein Suchfeld der Anfrage einen Suchterm enthält.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
