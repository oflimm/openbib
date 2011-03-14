#####################################################################
#
#  OpenBib::SearchQuery
#
#  Dieses File ist (C) 2008-2011 Oliver Flimm <flimm@openbib.org>
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
#use base qw(Class::Singleton);

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
        _filter                => [],
        _results               => {},
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

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $self = {
        _databases             => [],
        _filter                => [],
        _results               => {},
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

    my ($yearop,$indexterm,$indextermnorm);

    # Wandlungstabelle Erscheinungsjahroperator
    my $yearop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    my $legacy_bool_op_ref = {
        'btit'          => 'bool1',
        'bsubj'         => 'bool2',
        'bcorp'         => 'bool3',
        'bcln'          => 'bool4',
        'bisbn'         => 'bool5',
        'bmark'         => 'bool6',
        'byear'         => 'bool7',
        'bissn'         => 'bool8',
        'bpers'         => 'bool9',
        'bfs'           => 'bool10',
        'btyp'          => 'bool11',
        'btitstring'    => 'bool12',
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
        my $searchfieldprefix=$config->{searchfield}{$searchfield}{prefix};
        my ($searchfield_content, $searchfield_norm_content,$searchfield_bool_op);
        $searchfield_content = $searchfield_norm_content = decode_utf8($query->param("$searchfieldprefix")) || $query->param("$searchfieldprefix")      || '';
        $searchfield_bool_op = ($query->param("b$searchfieldprefix"))?$query->param("b$searchfieldprefix"):
            ($query->param($legacy_bool_op_ref->{"b$searchfieldprefix"}))?$query->param($legacy_bool_op_ref->{"b$searchfieldprefix"}):"AND";
        
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

            if ($searchfield eq "freesearch" || $searchfield_norm_content=~/:|.+?|/){
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

    # Filter einlesen
    foreach my $filter ($query->param('filter')) {
        if ($filter=~m/^([^\|]+):\|([^\|]+)\|.*$/){
            my $facet = $1;
            my $term = $2;

            my $string = $term;
            
            $string = OpenBib::Common::Util::grundform({
                content   => $string,
                searchreq => 1,
            });
            
            $string=~s/\W/_/g;
            
            $logger->debug("Facet: $facet Norm: $string Term: $term");
            
            push @{$self->{_filter}}, {
                val    => $filter,
                term   => $term,
                norm   => $string,
                facet  => $facet,
            };            
        }
    }
    
    # Parameter einlesen
    $yearop    =                  decode_utf8($query->param('yearop'))       || $query->param('yearop') || 'eq';    
    $indexterm = $indextermnorm = decode_utf8($query->param('indexterm'))     || $query->param('indexterm')|| '';

    my $autoplus      = $query->param('autoplus')      || '';
    my $persindex     = $query->param('persindex')     || '';
    my $corpindex     = $query->param('corpindex')      || '';
    my $subjindex     = $query->param('subjindex')      || '';
    my $clnindex      = $query->param('clnindex')      || '';

    # Setzen der arithmetischen yearop-Operatoren
    if (exists $yearop_ref->{$yearop}){
        $yearop=$yearop_ref->{$yearop};
    }
    else {
        $yearop="=";
    }

    if (exists $self->{_searchquery}->{year}){
       $self->{_searchquery}->{year}->{arg}= $yearop;
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

    my $idnresult=$dbh->prepare("select queryid,query from queries where sessionID = ? and queryid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID,$queryid) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();

    $self->from_json($res->{query});
    $self->set_id($res->{queryid});
    
    $idnresult->finish();

    return $self;
}

sub save  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sessionID              = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    unless ($sessionID){
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
        $query_obj_string = $self->to_json;
    }
    else {
        $query_obj_string = unpack "H*", Storable::freeze($self);
    }

    $logger->debug("Query Object: ".$query_obj_string);

    my $request=$dbh->prepare("select queryid from queries where query = ? and sessionid = ?") or $logger->error($DBI::errstr);
    $request->execute($query_obj_string,$sessionID) or $logger->error($DBI::errstr);
    my $result  = $request->fetchrow_hashref;
    my $queryid = $result->{queryid};
        

    # Wenn noch nicht vorhanden, dann eintragen
    if (!$queryid){
        $request=$dbh->prepare("insert into queries (queryid,sessionid,query) values (NULL,?,?)") or $logger->error($DBI::errstr);
        $request->execute($sessionID,$query_obj_string) or $logger->error($DBI::errstr);

        $logger->debug("Saving SearchQuery: sessionid,query_obj_string = $sessionID,$query_obj_string");
    }
    else {
        $logger->debug("Query already exists with ID $queryid: $query_obj_string");
    }
    
    $request->finish();

    return $self;
}


sub get_searchquery {
    my ($self)=@_;

    return $self->{_searchquery};
}

sub get_filter {
    my ($self)=@_;

    return $self->{_filter};
}

sub to_cgi_params {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];

    my $exclude_ref = {};

    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }
    
    my $config = OpenBib::Config->instance;

    my @cgiparams = ();

    foreach my $param (keys %{$self->{_searchquery}}){
        if ($self->{_searchquery}->{$param}{val} && !exists $exclude_ref->{$param}){
            my $searchparam = $config->{searchfield}{$param}{prefix};
            push @cgiparams, "b$searchparam=".$self->{_searchquery}->{$param}{bool};
            push @cgiparams, "$searchparam=".$self->{_searchquery}->{$param}{val};
        }
    }

    foreach my $filter (@{$self->{_filter}}){
        push @cgiparams, "filter=$filter->{val}";
    }
    
    return join(";",@cgiparams);
}

sub get_results {
    my ($self)=@_;

    return $self->{_results};
}

sub set_results {
    my ($self,$result_ref)=@_;

    $self->{_results} = $result_ref;
}

sub get_hits {
    my ($self)=@_;

    return $self->{_hits};
}

sub set_hits {
    my ($self,$hits)=@_;

    $self->{_hits} = $hits;
}

sub get_id {
    my ($self)=@_;

    return $self->{_id};
}

sub set_id {
    my ($self,$id)=@_;

    $self->{_id}=$id;
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

    # Aufbau des xapianfilterstrings
    my @xapianfilterstrings = ();
    my $xapianfilterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND ',
        'AND NOT' => 'NOT ',
        'OR'      => 'OR ',
    };

    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $self->{_searchquery}->{$field}->{norm})?$self->{_searchquery}->{$field}->{norm}:'';
        my $searchtermop     = (defined $self->{_searchquery}->{$field}->{bool} && defined $ops_ref->{$self->{_searchquery}->{$field}->{bool}})?$ops_ref->{$self->{_searchquery}->{$field}->{bool}}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if ($field eq "freesearch" && $searchtermstring) {
#                 my @searchterms = split('\s+',$searchtermstring);
                
#                 # Inhalte von @searchterms mit Suchprefix bestuecken
#                 foreach my $searchterm (@searchterms){                    
#                     $searchterm="+".$searchtermstring if ($searchtermstring=~/^\w/);
#                 }
#                 $searchtermstring = "(".join(' ',@searchterms).")";

                push @xapianquerystrings, $searchtermstring;
            }
            # Titelstring mit _ ersetzten
            elsif (($field eq "titlestring" || $field eq "mark") && $searchtermstring) {
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

    # Filter
    foreach my $filter_ref (@{$self->get_filter}){
        push @xapianfilterstrings, "$filter_ref->{facet}:$filter_ref->{norm}";
    }
    
    $xapianquerystring  = join(" ",@xapianquerystrings);
    $xapianfilterstring = join(" ",@xapianfilterstrings);

    $xapianquerystring=~s/^AND //;
    $xapianquerystring=~s/^OR //;
    $xapianquerystring=~s/^NOT //;

#    $xapianquerystring=~s/^OR /FALSE OR /;
#    $xapianquerystring=~s/^NOT /TRUE NOT /;
    
    $logger->debug("Xapian-Querystring: $xapianquerystring - Xapian-Filterstring: $xapianfilterstring");
    return {
        query  => $xapianquerystring,
        filter => $xapianfilterstring
    };
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
    
    return JSON::XS->new->utf8->canonical->encode($tmp_ref);
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
