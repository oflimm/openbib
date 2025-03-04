#####################################################################
#
#  OpenBib::SearchQuery
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use HTML::Entities;
use HTML::Escape qw/escape_html/;
use JSON::XS qw(encode_json decode_json);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use String::Tokenizer;
use Text::Aspell;
use Search::Xapian;
use YAML::Syck;
use LWP::UserAgent;
use URI::Escape;
use XML::LibXML;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Schema::DBI;
use OpenBib::Schema::System;
use OpenBib::Normalizer;

sub new {
    my ($class,$arg_ref) = @_;

    my $view        = exists $arg_ref->{view}
        ? $arg_ref->{view}                  : undef;

    my $r           = exists $arg_ref->{r}
        ? $arg_ref->{r}                     : undef;

    my $session     = exists $arg_ref->{session}
        ? $arg_ref->{session}               : undef;

    my $config      = exists $arg_ref->{config}
        ? $arg_ref->{config}                : OpenBib::Config->new();
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = {
        _searchprofile         => 0,
        _filter                => [],
        _results               => {},
        _have_searchterms      => 0,
        _config                => $config,
    };

    if ($logger->is_debug){    
	$logger->debug("Creating");
	
	$logger->debug(ref($self->{_config}));
	$logger->debug($self->{_config});
    }
    
    foreach my $searchfield (keys %{$config->{searchfield}}){
        $self->{_searchquery}{$searchfield} = {
            norm => '',
            val  => '',
            bool => '',
        };
    }
    
    bless ($self, $class);

    if (defined $session){
        $self->set_session($session);
    }

    if ($view){
        $self->{view} = $view;
    }

    if ($r){
        $self->{r} = $r;
        $self->set_from_psgi_request;
    }

    $logger->debug("Object created");
    
    return $self;
}

sub get_config {
    my $self = shift;
    
    return $self->{_config};
}

sub set_from_psgi_request {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $query = $self->{r};

    my $normalizer = new OpenBib::Normalizer;
    
    my ($indexterm,$indextermnorm,$indextype);

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

    if ($logger->is_debug){
#	$logger->debug("Paramstring: ".$self->{r}->args);
	$logger->debug("Paramstring: ".$self->{r}->url->query);
    }

    my @param_names = $query->param;

    if ($logger->is_debug){
        $logger->debug("CGI-Parameters: ".YAML::Dump(@param_names));
    }
    
    # Suchfelder einlesen
    foreach my $searchfield (keys %{$config->{searchfield}}){
        my $searchfieldtype   = $config->{searchfield}{$searchfield}{type};

        my @available_searchfields = ({ name => $searchfield, prefix => $config->{searchfield}{$searchfield}{prefix} });

        # Fuer Suchfelder des Typs integer existieren immer auch davon abgeleitete Bereichs-Suchfelder <suchfeld>_from und <suchfeld>_to
        if ($searchfieldtype eq "integer"){
            push @available_searchfields, { name => "${searchfield}_from", prefix => "${searchfield}_from" };
            push @available_searchfields, { name => "${searchfield}_to",   prefix => "${searchfield}_to" }; 
        }

        foreach my $thissearchfield (@available_searchfields){
            my $prefix = $thissearchfield->{prefix};
            my $name   = $thissearchfield->{name};
            my ($thissearchfield_content, $thissearchfield_norm_content,$thissearchfield_bool_op);

	    # Process and escape Input
	    $thissearchfield_norm_content = decode_utf8(uri_unescape($self->_html_unescape($query->param("$prefix")))) || '';
            $thissearchfield_content      = escape_html($thissearchfield_norm_content);

	    # Anpassung/Ausnahme fuer " Phrasensuche wieder entfernt wg. XSS
	    # $thissearchfield_content =~s/&quot;/"/g;

	    if ($logger->is_debug){
		$logger->debug("Escaped content for searchfield $prefix: ".$thissearchfield_content);
	    }
	    
	    # Process Bools, escaping with allowlist
            $thissearchfield_bool_op = (defined $query && $query->param("b\[$prefix\]"))?$query->param("b\[$prefix\]"):
                (defined $legacy_bool_op_ref->{"b\[$prefix\]"} && $query->param($legacy_bool_op_ref->{"b\[$prefix\]"}))?$query->param($legacy_bool_op_ref->{"b\[$prefix\]"}):"AND";
            
            # escaping
            $thissearchfield_bool_op = (exists $valid_bools_ref->{$thissearchfield_bool_op})?$valid_bools_ref->{$thissearchfield_bool_op}:"AND";

            #####################################################################
            ## searchfield_content: Inhalt der Suchfelder des Nutzers
            
            $self->{_searchquery}->{$name}->{val}  = $thissearchfield_content;
            
            #####################################################################
            ## searchfield_bool_op: Verknuepfung der Eingabefelder (leere Felder werden ignoriert)
            ##        AND  - Und-Verknuepfung
            ##        OR   - Oder-Verknuepfung
            ##        NOT  - Und Nicht-Verknuepfung
            
            $self->{_searchquery}->{$name}->{bool} = $thissearchfield_bool_op;
            
            if ($thissearchfield_norm_content){
                # Zuerst Stringsuchen in der Freie Suche

                $logger->debug("Stage1: $thissearchfield_norm_content");

                if ($name eq "freesearch" || $thissearchfield_norm_content=~/:|.+?|/){
                    while ($thissearchfield_norm_content=~m/^([^\|]+)\|([^\|]+)\|(.*)$/){
                        my $first  = $1;
                        my $string = $2;
                        my $last   = $3;
                        
                        #                    $logger->debug("Fullstring IN: $string");
                        my $string_norm = $normalizer->normalize({
                            content   => $string,
                            type      => 'string',
                        });
                        
                        $string_norm=~s/\W/_/g;
                        
                        #                    $logger->debug("1: $first String: $string_norm 3: $last");
                        
                        #                    $logger->debug("Fullstring OUT: $string_norm");
                        $thissearchfield_norm_content=$first.$string_norm.$last;
                    }
                }

                # Filter fuer Suchfeld und gegebenenfalls davon abgeleitete Felder (_from/_to). Daher $searchfield und nicht $name!

                if ($logger->is_debug){
                    $logger->debug("Filter Option: ".YAML::Dump($config->{'searchfield'}{$searchfield}{option}));
                }
                
                $thissearchfield_norm_content = $normalizer->normalize({
                    option    => $config->{'searchfield'}{$searchfield}{option},
                    content   => $thissearchfield_norm_content,
                    type      => $config->{'searchfield'}{$searchfield}{type},
                    searchreq => 1,
                });

                if ($thissearchfield_norm_content){
                    $self->{_have_searchterms} = 1;
                    $self->{_searchquery}->{$name}->{norm} = $thissearchfield_norm_content;
                }

                $logger->debug("Added searchterm $thissearchfield_bool_op - $thissearchfield_content - $thissearchfield_norm_content");
            }
        }
    }

    # Filter einlesen f[<searchfield prefix>]
    # Problem: Filter ist bei der Integration in bestimmte Systeme (z.B. CMS)
    # bereits vorbelegt. Daher sowie zur besseren Strukturierung f[...]

    my %seen_filter = ();
    my @available_filters = grep { /^f\[/ } $query->param;

    foreach my $filter (@available_filters) {
        next if ($seen_filter{$filter} ++);

        $self->{_have_searchterms} = 1;
        
        my ($field) = $filter =~m/^f\[(.+)\]/;
        my @terms   = ($query->param($filter))? $query->param($filter) : ();

        if ($logger->is_debug){
            $logger->debug("Filter: $filter with terms ".YAML::Dump(\@terms));
        }
        
        foreach my $term (@terms){
	    $logger->debug("Native filter Term: $term");
#            $term = decode_utf8(uri_unescape($self->_html_unescape($term)));
	    $term = escape_html(decode_utf8(uri_unescape($self->_html_unescape($term))));
	    
            my $string  = $term;
            
            $string = $normalizer->normalize({
                content   => $string,
                type      => 'string',
            });
            	    
            $logger->debug("Field: $field Norm: $string Term: $term");
	    
            push @{$self->{_filter}}, {
                val    => "$field:$term",
                term   => $term,
                norm   => $string,
                field  => $field,
            };
        }
    }

    $self->{autoplus}            = ($query->param('autoplus'))?escape_html($query->param('autoplus')):'';
    $self->{searchtype}          = ($query->param('st'))?escape_html($query->param('st')):'';    # Search type (1=simple,2=complex)
    $self->{drilldown}           = ($query->param('dd'))?escape_html($query->param('dd')):1;     # Drilldown ?

    # Index zusammen mit Eingabefelder
    $self->{authority}           = ($query->param('authority'))?escape_html($query->param('authority')):'';
    $self->{personindex}         = ($query->param('personindex'))?escape_html($query->param('personindex')):'';
    $self->{corporatebodyindex}  = ($query->param('corporatebodyindex'))?escape_html($query->param('corporatebodyindex')):'';
    $self->{subjectindex}        = ($query->param('subjectindex'))?escape_html($query->param('subjectindex')):'';
    $self->{classificationindex} = ($query->param('classificationindex'))?escape_html($query->param('classificationindex')):'';

    # oder Index als Separate Funktion
    $indexterm = $indextermnorm  = ($query->param('indexterm'))?escape_html(decode_utf8($query->param('indexterm'))):''; #    || escape_html($query->param('indexterm')) || '';

    $self->{indextype}           = ($query->param('indextype'))?escape_html(decode_utf8($query->param('indextype'))):''; #    || escape_html($query->param('indextype')) || '';
    $self->{searchindex}         = ($query->param('searchindex'))?escape_html($query->param('searchindex')):'';
    
    if ($indexterm){
        $indextermnorm  = $normalizer->normalize({
           content   => $indextermnorm,
           searchreq => 1,
        });

        $self->{_searchquery}->{indexterm}={
	    val   => $indexterm,
	    norm  => $indextermnorm,
        };
    }

    if ($indextype){
        $self->{indextype} = $indextype;
    }

    $self->{_is_authority} =(defined $self->{authority})?1:0;
    
    $self->{_searchprofile}  = $self->_get_searchprofile;

    my $searchterms_ref = $self->get_searchquery;
    foreach my $key (keys %$searchterms_ref){
	if (!$searchterms_ref->{$key}{val}){
	    delete $searchterms_ref->{$key};
	}
    }
	
    if ($logger->is_debug){
	$logger->debug("Searchquery-Terms: ".YAML::Dump($searchterms_ref));
    }
    
    return $self;
}


sub is_authority {
    my ($self)=@_;

    return $self->{_is_authority};
}

sub get_searchquery {
    my ($self)=@_;

    return $self->{_searchquery};
}

# sub get_searchfield {
#     my ($self,$field)=@_;

#     return $self->{_searchquery}->{$field};
# }

sub get_searchtype {
    my ($self)=@_;

    return $self->{searchtype};
}

sub get_filter {
    my ($self)=@_;

    return $self->{_filter};
}

sub set_filter {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $field        = exists $arg_ref->{field}
        ? $arg_ref->{field}         : undef;
    my $term        = exists $arg_ref->{term}
        ? $arg_ref->{term}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $normalizer = new OpenBib::Normalizer;
    
    if ($field && $term){

	my $string  = $term;
	
	$string = $normalizer->normalize({
	    content   => $string,
	    type      => 'string',
						   });
            	    
	$logger->debug("Field: $field Norm: $string Term: $term");

	push @{$self->{_filter}}, {
	    val    => "$field:$term",
	    term   => $term,
	    norm   => $string,
	    field  => $field,
	};

	$self->{_have_searchterms} = 1;
    }

    return $self;
}

sub to_cgi_params {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $exclude_array_ref        = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}         : [];

    my $exclude_filter_array_ref = exists $arg_ref->{exclude_filter}
        ? $arg_ref->{exclude_filter}  : [];

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $exclude_ref        = {};
    my $exclude_filter_ref = {};

    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }

    my $no_filter = 0;
    foreach my $content (@{$exclude_filter_array_ref}){
        if ($content eq "all"){
            $no_filter = 1;
        }
        $exclude_filter_ref->{$content} = 1;
    }

    my $config = $self->get_config;

    my @cgiparams = ();

    if ($logger->is_debug){
        $logger->debug("_searchquery: ".YAML::Dump($self->{_searchquery}));
    }
    
    foreach my $param (keys %{$self->{_searchquery}}){

        if ($self->{_searchquery}->{$param}{val} && !exists $exclude_ref->{$param}){

            my $base_param   = $param;
            my $param_suffix = "";
            # Automatisch abgeleitete Suchfelder auf Basis-Suchfeld reduzieren
            if ($param =~/^(.+?)(_from)/ || $param =~/^(.+?)(_to)/){
                $base_param   = $1;
                $param_suffix = $2;
            }

            my $base_prefix = $config->{searchfield}{$base_param}{prefix};

            push @cgiparams, {
                param  => "b".$base_prefix.$param_suffix,
                val    => $self->{_searchquery}->{$param}{bool}
            };

	    if ($logger->is_debug){
		$logger->debug("Unescaped: ".$self->{_searchquery}->{$param}{val});
		$logger->debug("Escaped: ".uri_escape_utf8($self->{_searchquery}->{$param}{val}));
	    }

            # Kein Escaping notwendig, da Parameter bereits beim Erzeugen des SearchQuery-Objektes
            # escaped werden.									
            push @cgiparams, {
                param  => $base_prefix.$param_suffix,
#                val    => uri_escape_utf8($self->{_searchquery}->{$param}{val}),
                val    => $self->{_searchquery}->{$param}{val},
            };
        }
    }

    if (!$no_filter){
        foreach my $filter (@{$self->{_filter}}){
            push @cgiparams, {
                param => "f\[$filter->{field}\]",
                val   => $self->_html_escape($filter->{term}),
            } if (!$exclude_filter_ref->{$filter->{val}});
        }
    }

    # Wo wird gesucht? => Searchprofileid
    push @cgiparams, {
        param => "profile",
        val   => $self->get_searchprofile,
    } if (!exists $exclude_ref->{'profile'});
        
    return @cgiparams;
}

sub to_cgi_querystring {
    my ($self,$arg_ref)=@_;

    my @cgiparams = ();
    
    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "$arg_ref->{param}=$arg_ref->{val}";
    }   

    return join('&',@cgiparams);
}

sub to_cgi_hidden_input {
    my ($self,$arg_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Querystring as hidden input");
    
    if ($logger->is_debug){
        $logger->debug("Args".YAML::Dump($arg_ref));
    }

    my @cgiparams = ();

    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
#        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"".decode_utf8(uri_unescape($arg_ref->{val}))."\" />";
        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"".uri_unescape($arg_ref->{val})."\" />";

    }   

    return join("\n",@cgiparams);
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

sub get_type {
    my ($self)=@_;

    return $self->{_type};
}

sub set_type {
    my ($self,$type)=@_;

    $self->{_type} = $type;
}

sub get_id {
    my ($self)=@_;

    return $self->{_id};
}

sub set_id {
    my ($self,$id)=@_;

    $self->{_id}=$id;
}

sub set_tstamp {
    my ($self,$tstamp)=@_;

    $self->{_tstamp}=$tstamp;
}

sub get_tstamp {
    my ($self)=@_;

    return $self->{_tstamp};
}

sub set_searchprofile {
    my ($self,$searchprofile)=@_;

    $self->{_searchprofile} = $searchprofile;
    return;
}

sub get_searchprofile {
    my ($self)=@_;

    return $self->{_searchprofile};
}

sub get_searchfield {
    my ($self,$fieldname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

#    $logger->debug($fieldname);

#    $logger->debug(YAML::Dump($self));
    return (exists $self->{_searchquery}->{$fieldname})?$self->{_searchquery}->{$fieldname}:{val => '', norm => '', bool => '', args => ''};
}

sub set_searchfield {
    my ($self,$fieldname,$content,$bool)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $normalizer = new OpenBib::Normalizer;
    
    my $contentnorm  = $normalizer->normalize({
	field     => $fieldname,
        content   => $content,
        searchreq => 1,
    });

    $logger->debug($fieldname);

    $self->{_searchquery}->{$fieldname} = {
        val => $content, norm => $contentnorm, bool => $bool
    };

    return;
}

sub get_searchterms {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $term_ref = [];

    if ($logger->is_debug){
        $logger->debug("_searchquery is: ".YAML::Dump($self->{_searchquery}));
    }
    
    return $term_ref unless (defined $self->{_searchquery} && exists $self->{_searchquery});

    my @allterms = ();
    foreach my $cat (keys %{$self->{_searchquery}}){
        push @allterms, $self->{_searchquery}->{$cat}->{val} if (ref $self->{_searchquery}->{$cat} eq "HASH" && $self->{_searchquery}->{$cat}->{val});
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

sub get_searchtermstring {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $term_ref = [];

    if ($logger->is_debug){
        $logger->debug("_searchquery is: ".YAML::Dump($self->{_searchquery}));
    }
    
    return $term_ref unless (defined $self->{_searchquery} && exists $self->{_searchquery});

    my @allterms = ();
    foreach my $cat (keys %{$self->{_searchquery}}){
        push @allterms, $self->{_searchquery}->{$cat}->{val} if (ref $self->{_searchquery}->{$cat} eq "HASH" && $self->{_searchquery}->{$cat}->{val});
    }
    
    return join (" ",@allterms);
}

sub get_dbis_recommendations {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $atime;
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my @allterms = ();
    foreach my $cat (keys %{$self->{_searchquery}}){
        push @allterms, $self->{_searchquery}->{$cat}->{val} if (ref $self->{_searchquery}->{$cat} eq "HASH" && $self->{_searchquery}->{$cat}->{val});
    }
    my $alltermsstring = join (" ",@allterms);

    $logger->debug("Terms: $alltermsstring");
    my $url="https://suche.suub.uni-bremen.de/cgi-bin/CiXbase/brewis/CiXbase_search?act=search&LAN=DE&CLUSTER=3&index=L&n_dtyp=1L&n_rtyp=ceEdX&PRECISION=220&RELEVANCE=45&dtyp=DE&term=$alltermsstring";

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(5);
    
    my $response = $ua->get($url);

    if (!$response->is_success){
	return [];
    }

    my $content = $response->decoded_content(charset => 'utf8');
    
    $logger->debug("Response: $content");

    if ($config->{benchmark}){
       my $btime      = new Benchmark;
       my $timeall    = timediff($btime,$atime);
       my $resulttime = timestr($timeall,"nop");
       $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
       $logger->info("Request to elib took $resulttime seconds");
    }

    my $dbr_ref = [];
    

    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($content);
    my $root   = $tree->getDocumentElement;

    my $have_topic_ref = {};
    
    foreach my $cluster_node ($root->findnodes('/ListRecords/Cluster')) {
        my $frequency = $cluster_node->findvalue('@freq');
        my $rank      = $cluster_node->findvalue('@rank');
        my $dbrtopic  = $cluster_node->textContent;

        $logger->debug("$dbrtopic - $rank - $frequency");

        my $databases_ref = $config->get_dbisdbs_of_dbrtopic($dbrtopic);

        my $dbistopic     = $config->get_dbistopic_of_dbrtopic($dbrtopic);
        
        if (defined $dbistopic->{topic} && @$databases_ref && !defined $have_topic_ref->{$dbistopic->{topic}}){
            push @$dbr_ref, {
                dbistopic  => $dbistopic->{description},
                rank       => $rank,
                frequency  => $frequency,
                databases  => $databases_ref,
            };
        }
        
        $have_topic_ref->{$dbistopic->{topic}} = 1;
    }
    
    if ($config->{benchmark}){
       my $btime      = new Benchmark;
       my $timeall    = timediff($btime,$atime);
       my $resulttime = timestr($timeall,"nop");
       $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
       $logger->info("elib database recommendation took $resulttime seconds");
    }

    return $dbr_ref;
}

sub get_spelling_suggestion {
    my ($self,$lang) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $suggestions_ref = {};
    my $searchterms_ref = $self->get_searchterms;

    my $speller = Text::Aspell->new;

    $speller->set_option('lang','de_DE');
    $speller->set_option('sug-mode','normal');
    $speller->set_option('ignore-case','true');
    
    # Kombinierter Datenbank-Handle fuer Xapian generieren, um spaeter damit Term-Frequenzen abfragen zu koennen
    my $dbh;
    foreach my $database ($config->get_databases_of_searchprofile($self->{_searchprofile})) {
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

    my $normalizer = new OpenBib::Normalizer;
    
    # Bestimmung moeglicher Rechtschreibvorschlaege fuer die einzelnen Begriffe
    foreach my $term (@{$searchterms_ref}){
        # Nur Vorschlaege sammeln, wenn der Begriff nicht im Woerterbuch vorkommt
        my @aspell_suggestions = ($speller->check($term))?():$speller->suggest( $term );

        if ($logger->is_debug){
            $logger->debug("Aspell suggestions".YAML::Dump(\@aspell_suggestions));
        }

        my $valid_suggestions_ref  = [];
        my $sorted_suggestions_ref = [];

        if (defined $dbh){
            my $this_term = $normalizer->normalize({
                content   => $term,
                searchreq => 1,
            });
            
            my $this_termfreq = $dbh->get_termfreq($this_term);            

            # Verwende die 5 besten Vorschlaege
            foreach my $suggested_term (@aspell_suggestions[0..4]){
                next unless ($suggested_term);
                my $suggested_term = $normalizer->normalize({
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
            
            if ($logger->is_debug){
                $logger->info(YAML::Dump($valid_suggestions_ref));
            }
            
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

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $tmp_ref = {};
    foreach my $property (sort keys %{$self}){
        next if ($property eq "_config"); # Config-Objekt wird nicht gewandelt
        next if ($property eq "_session"); # Session-Objekt wird nicht gewandelt
        next if ($property eq "schema"); # DBIx::Class wird nicht gewandelt
        next if ($property eq "r");      # OpenBib::Request wird nicht gewandelt

        $logger->debug("Getting property $property");

        $tmp_ref->{$property} = $self->{$property};
    }

    my $json_out = "";

    eval {
        $json_out = JSON::XS->new->utf8->canonical->encode($tmp_ref);
    };

    if ($@){
        $logger->error($@);
    }
    
    return $json_out; 
}

sub from_json {
    my ($self,$json) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return unless ($json);

    $logger->debug("Decoding $json");

    eval {
        my $tmp_ref = decode_json $json;
        foreach my $property (keys %{$tmp_ref}){
            $self->{$property} = $tmp_ref->{$property};
        }
    };

    if ($@){
        $logger->error("JSON decoding: ".$@);
    }
    
    return $self;
}

sub single_db_in_searchprofile {
   my $self = shift;

   my $config = $self->get_config;
   my @dbs = $config->get_databases_of_searchprofile($self->{_searchprofile});
   return ($#dbs == 0)?1:0;
}

sub _html_escape {
    my ($self,$content)=@_;

#    return encode_entities($content);
    return escape_html($content);
}

sub _html_unescape {
    my ($self,$content)=@_;

    return decode_entities($content) if (defined $content);

    return '';									
}

sub _get_searchprofile {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query = $self->{r};
    my $view  = $self->{'view'}                      || '';

    my $config         = $self->get_config;
    my $session        = $self->get_session;

    # CGI Args
    my @databases     = ($query->param('db'))?$query->param('db'):();
    my $profile       = $query->param('profile')       || '';

    # BEGIN DB-Bestimmung
    ####################################################################
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    ####################################################################

    # Wenn Datenbanken uebergeben werden, dann wird nur
    # in diesen gesucht.
    if ($#databases != -1) {
        $logger->debug("Selecting databases received via CGI");
        # Wenn Datenbanken explizit ueber das Suchformular uebergeben werden,
        # dann werden diese als neue Datenbankauswahl gesetzt
        
        # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
        $session->set_dbchoice(\@databases);
        
        # Neue Datenbankauswahl ist voreingestellt
        $session->set_profile('dbchoice');
    }
    # Wenn ein Suchprofil uebergeben wird, dann wird nur dort gesucht
    elsif ($profile) {
        $logger->debug("Selecting all databases for profile $profile");
        @databases = $config->get_databases_of_searchprofile($profile);
        $session->set_profile($profile);
    }
    # Sonst wird in der Datenbankvorauswahl der Sicht
    # recherchiert.    
    else {
        $logger->debug("Selecting databases of view");
        @databases = $config->get_dbs_of_view($view);
        if ($logger->is_debug){
           $logger->debug("Selecting databases of view: ".($#databases + 1));
        }
    }

    # Dublette Datenbanken filtern
    my %seen_dbases = ();
    @databases = grep { ! $seen_dbases{$_} ++ } @databases;

    # Nur Datenbanken sind erlaubt, die fuer den View definiert wurden
    # Damit: Katalogweise Abschottung der Views bei Recherchen
    @databases = $config->restrict_databases_to_view({ databases => \@databases, view => $view }) if ($view);

    if ($logger->is_debug){
       $logger->debug("Final databases: ".($#databases + 1));
    }
									
    my $searchprofile = $config->get_searchprofile_or_create(\@databases);
    
    if ($logger->is_debug){
        $logger->debug("Database List: ".join(",", sort @databases));
        $logger->debug("Searchprofile : $searchprofile");
    }
    
    return $searchprofile;
}

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }

    if (defined $self->{_config}){
        $logger->debug("Reusing Config-Schema ".$self->get_config);
        return $self->get_config->get_schema;        
    }
    
    $logger->debug("Creating new Schema $self");    
    
    $self->connectDB;
    
    return $self->{schema};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # UTF8: {'pg_enable_utf8'    => 1}
    if ($config->{'systemdbsingleton'}){
        eval {        
            my $schema = OpenBib::Schema::System::Singleton->instance;
            $self->{schema} = $schema->get_schema;
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
    else {
        eval {        
            $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
        
    
    return;
}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from System-DB $self");
    
    if (defined $self->{schema}){
        eval {
            $logger->debug("Disconnect from System-DB now $self");
            $self->{schema}->storage->dbh->disconnect;
            delete $self->{schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub load  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sid                    = exists $arg_ref->{sid}
        ? $arg_ref->{sid}                 : undef;
    my $queryid                = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($thisquery,$thiststamp);
    
    eval {
	# DBI: "select queryid,query from queries where sessionID = ? and queryid = ?"
	my $query = $self->get_schema->resultset('Query')->search(
	    {
		'sid.id'        => $sid,
		    'me.queryid'    => $queryid,
	    },
	    {
		select => ['me.tstamp','me.query'],
		as     => ['thiststamp','thisquery'],
		join => ['sid'],
	    }
	    )->single;
	
	if ($query){
	    $thisquery  = scalar $query->get_column('thisquery');
	    $thiststamp = scalar $query->get_column('thiststamp');
	}
    };

    if ($@){
	$logger->error($@);
    }
    
    $logger->debug("$sid/$queryid -> $thisquery");
    $self->from_json("$thisquery");
    $self->set_id($queryid);
    $self->set_tstamp($thiststamp);
    
    return $self;
}

sub save  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sid               = exists $arg_ref->{sid}
        ? $arg_ref->{sid}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    unless ($sid){
        return $self;
    }

    my $config = $self->get_config;
    
    $logger->debug("sid: $sid");
    
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

    if ($logger->is_debug){    
	$logger->debug("Query Object: ".$query_obj_string);
    }
    
    # DBI: "select queryid from queries where query = ? and sessionid = ?"
    my $searchquery = $self->get_schema->resultset('Query')->search(
        {
            'sid.id'        => $sid,
            'me.query'      => $query_obj_string,
        },
        {
            select => 'me.queryid',
            as     => 'thisqueryid',
            join => 'sid'
        }
    );

    my $searchquery_exists = $searchquery->count;
    # Wenn noch nicht vorhanden, dann eintragen

    if (!$searchquery_exists){
        # DBI: "insert into queries (queryid,sessionid,query) values (NULL,?,?)"
        my $new_query = $self->get_schema->resultset('Query')->create({ sid => $sid, query => $query_obj_string , searchprofileid => $self->get_searchprofile, tstamp => \'NOW()' });

        my $new_queryid = scalar $new_query->get_column('queryid');
        
        $self->set_id($new_queryid);
        
         $logger->debug("Saving SearchQuery: sessionid,query_obj_string = $sid,$query_obj_string to id ".$self->get_id);
    }
    else {
        my $this_queryid = scalar $searchquery->get_column('thisqueryid');
        
        $self->set_id($this_queryid);
        $logger->debug("Query already exists: $query_obj_string");
    }

    if ($logger->is_debug){
      $logger->debug("SearchQuery has id ".$self->get_id) if (defined $self->get_id);
    }
  
    return $self;
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying Config-Object $self");

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    return;
}


sub get_session {
    my ($self)=@_;
    
    return $self->{_session};
}

sub set_session {
    my ($self,$session)=@_;
    
    $self->{_session} = $session;
    return;
}

1;
__END__

=head1 NAME

OpenBib::SearchQuery - Objekt der vom Nutzer eingegebenen
Suchanfrage

=head1 DESCRIPTION

Dieses Singleton verwaltet die vom Nutzer eingegebene Suchanfrage.

=head1 SYNOPSIS

 use OpenBib::SearchQuery;

 my $searchquery   = OpenBib::SearchQuery->new;

=head1 METHODS

=over 4

=item instance

Instanziierung des Singleton. Zu jedem Suchbegriff lässt sich
neben der eingegebenen Form vol auch die Normierung norm, der
zugehörige Bool'sche Verknüpfungsparameter bool sowie die ausgewählten
Datenbanken speichern.

=item set_from_psgi_request($r,$searchprofile)

Setzen der Suchbegriffe direkt aus dem PSGI-Request samt übergebener
Suchoptionen und zusätzlicher Normierung der Suchbegriffe.

=item load({ sid => $sid, queryid => $queryid })

Laden der Suchanfrage zu $queryid in der Session $sid

=item get_searchquery

Liefert die Suchanfrage zurück.

=item to_cgi_params

Liefert einen CGI-Teilstring der Suchbegriffe mit ihren Bool'schen Operatoren zurück.

=item get_hits

Liefert die Treffferzahl der aktuellen Suchanfrage zurück.

=item get_id

Liefert die zugehörige Query-ID zurück.

=item get_searchprofile

Liefert die ID des Suchprofils zur Suchanfrage zurück.

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
