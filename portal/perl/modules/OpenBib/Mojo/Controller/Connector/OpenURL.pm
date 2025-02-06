####################################################################
#
#  OpenBib::Mojo::Controller::Connector::OpenURL.pm
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::OpenURL;

use strict;
use warnings;
no warnings 'redefine';

use Benchmark;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Search::Util;
use OpenBib::Session;
use Data::Dumper;
use JSON::XS;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $query        = $self->query();
    my $r            = $self->stash('r');
    my $config       = $self->stash('config');
    my $session      = $self->stash('session');
    my $user         = $self->stash('user');
    my $msg          = $self->stash('msg');
    my $queryoptions = $self->stash('qopts');
    my $stylesheet   = $self->stash('stylesheet');
    my $useragent    = $self->stash('useragent');
    my $path_prefix  = $self->stash('path_prefix');

    $self->stash('lang','de'); # Setting de als default language

    # CGI Args
    my $input_data_ref = $self->parse_valid_input();

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($input_data_ref));
    }

    my $have_args = 0;

    foreach my $arg (keys %$input_data_ref){
	if ($input_data_ref->{$arg}){
	    $have_args = 1;
	    last;
	}
    }
    
    # OpenURL Informationsseite ausgeben, wenn keine Argumente uebergeben wurden
    unless ($have_args){
	my $ttdata = {
	};
	
	return $self->print_page($config->{tt_connector_openurl_tname},$ttdata);	
    }

    # OpenURL 0.1 or 1.0 args?

    my $openurl_version = "0.1";

    if ($input_data_ref->{url_ver} =~m/Z39.88-2004/){
	$openurl_version = "1.0";
    }

    if ($logger->is_debug){
	$logger->debug("OpenURL Search-Args: ".YAML::Dump($input_data_ref));
    }
    
    my $openbib_searchargs_ref = ($openurl_version eq "1.0")?$self->gen_searchargs_1_0($input_data_ref):$self->gen_searchargs_0_1($input_data_ref);

    if ($logger->is_debug){
	$logger->debug("Internal OpenBib OpenURL Search-Args: ".YAML::Dump($openbib_searchargs_ref));
    }
    
    my $searchargs = "";

    my $searchfield_ref = $config->get('searchfield');
    
    foreach my $field (keys %$openbib_searchargs_ref){
	my @this_searchargs = @{$openbib_searchargs_ref->{$field}}; 
	if ($#this_searchargs == 0 ){
	    $searchargs.=";".$searchfield_ref->{$field}{prefix}."=".$this_searchargs[0];
	}
	else {
	    $searchargs.=";".$searchfield_ref->{$field}{prefix}."=".join(' ',@this_searchargs);
	}
    }

    if ($logger->is_debug){
	$logger->debug("Internal OpenBib OpenURL Search-Args-String: $searchargs");
    }
    
    return $self->redirect("$path_prefix/availability/$config->{search_loc}.html?l=de$searchargs");
}

sub gen_searchargs_1_0 {
    my $self=shift;
    my $input_data_ref=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchargs_ref = {};

    my $genre = $input_data_ref->{'rft.genre'};

    $searchargs_ref->{'person'} = [];
    
    # Author in default fields?   
    foreach my $field ('rft.aulast','rft.aufirst','rft.auinit','rft.auinit1','rft.auinitm'){
	if ($input_data_ref->{$field}){
	    push @{$searchargs_ref->{'person'}}, $input_data_ref->{$field};
	}
    }

    $searchargs_ref->{'title'} = [];
    $searchargs_ref->{'source'} = [];
    $searchargs_ref->{'journal'} = [];
    $searchargs_ref->{'volume'} = [];
    $searchargs_ref->{'issue'} = [];

    push @{$searchargs_ref->{'mediatype'}}, $genre if ($genre);

    # simple: title is title
    if ($genre =~m/^(book|conference|journal)$/){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'rft.title'} if ($input_data_ref->{'rft.title'});
    }
    # more complex
    elsif ($genre =~m/^(article|bookitem|preprint|proceeding)$/){
	# title is title of source 	
	push @{$searchargs_ref->{'journal'}}, $input_data_ref->{'rft.title'} if ($input_data_ref->{'rft.title'});
	# atitle is title of work
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'rft.atitle'} if ($input_data_ref->{'rft.atitle'});

    }
    # perhaps no genre?
    elsif ($input_data_ref->{'rft.title'} && $input_data_ref->{'rft.atitle'}) {
	# title is title of source 	
	push @{$searchargs_ref->{'journal'}}, $input_data_ref->{'rft.title'};
	# atitle is title of work
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'rft.atitle'};
    }
    elsif ($input_data_ref->{'rft.title'}){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'rft.title'};
    }
    elsif ($input_data_ref->{'rft.atitle'}){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'rft.atitle'};
    }

    $searchargs_ref->{'isbn'} = [];
    $searchargs_ref->{'issn'} = [];
    $searchargs_ref->{'year'} = [];
    $searchargs_ref->{'pages'} = [];

    push @{$searchargs_ref->{'isbn'}}, $input_data_ref->{'rft.isbn'} if ($input_data_ref->{'rft.isbn'});

    push @{$searchargs_ref->{'issn'}}, $input_data_ref->{'rft.issn'} if ($input_data_ref->{'rft.issn'});

    push @{$searchargs_ref->{'issn'}}, $input_data_ref->{'rft.eissn'} if ($input_data_ref->{'rft.eissn'});

    push @{$searchargs_ref->{'year'}}, $input_data_ref->{'rft.date'} if ($input_data_ref->{'rft.date'});

    push @{$searchargs_ref->{'volume'}}, $input_data_ref->{'rft.volume'} if ($input_data_ref->{'rft.volume'});

    push @{$searchargs_ref->{'issue'}}, $input_data_ref->{'rft.issue'} if ($input_data_ref->{'rft.issue'});
    
    # Pagerange?
    if ($input_data_ref->{'rft.pages'}){
	push @{$searchargs_ref->{'pages'}}, $input_data_ref->{'rft.pages'}
    }
    elsif ($input_data_ref->{'rft.spage'} || $input_data_ref->{'rft.epage'}){
	my $pages = "";

	$pages = $input_data_ref->{'rft.spage'} if ($input_data_ref->{'rft.spage'});
	$pages.= "=".$input_data_ref->{'rft.epage'} if ($input_data_ref->{'rft.epage'});
						   
	push @{$searchargs_ref->{'pages'}}, $pages;
    }

    if ($logger->is_debug){
	$logger->debug("Search-Args conversion result: ".YAML::Dump($searchargs_ref));
    }

    return $searchargs_ref;    
}

sub gen_searchargs_0_1 {
    my $self=shift;
    my $input_data_ref=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchargs_ref = {};

    my $genre = $input_data_ref->{genre};

    $searchargs_ref->{'person'} = [];
    
    # Author in default fields?   
    foreach my $field ('aulast','aufirst','auinit','auinit1','auinitm'){
	if ($input_data_ref->{$field}){
	    push @{$searchargs_ref->{'person'}}, $input_data_ref->{$field};
	}
    }

    # still not author? then look at pid
    if (!@{$searchargs_ref->{'person'}}){
	if ($input_data_ref->{pid} =~m{<author>(.*)</author>}){
	    push @{$searchargs_ref->{'person'}}, $1;
	}
    }

    push @{$searchargs_ref->{'mediatype'}}, $genre if ($genre);    

    $searchargs_ref->{'title'} = [];
    $searchargs_ref->{'source'} = [];
    $searchargs_ref->{'journal'} = [];
    $searchargs_ref->{'volume'} = [];
    $searchargs_ref->{'issue'} = [];

    # simple: title is title
    if ($genre =~m/^(book|conference|journal)$/){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{title} if ($input_data_ref->{title});
    }
    # more complex
    elsif ($genre =~m/^(article|bookitem|preprint|proceeding)$/){
	# title is title of source 	
	push @{$searchargs_ref->{'journal'}}, $input_data_ref->{'title'} if ($input_data_ref->{title});
	# atitle is title of work
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'atitle'} if ($input_data_ref->{'atitle'});

    }
    # perhaps no genre?
    elsif ($input_data_ref->{title} && $input_data_ref->{atitle}) {
	# title is title of source 	
	push @{$searchargs_ref->{'journal'}}, $input_data_ref->{'title'};
	# atitle is title of work
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'atitle'};
    }
    elsif ($input_data_ref->{title}){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'title'};
    }
    elsif ($input_data_ref->{atitle}){
	push @{$searchargs_ref->{'title'}}, $input_data_ref->{'atitle'};
    }

    $searchargs_ref->{'isbn'} = [];
    $searchargs_ref->{'issn'} = [];
    $searchargs_ref->{'year'} = [];

    push @{$searchargs_ref->{'isbn'}}, $input_data_ref->{'isbn'} if ($input_data_ref->{'isbn'});

    push @{$searchargs_ref->{'issn'}}, $input_data_ref->{'issn'} if ($input_data_ref->{'issn'});

    push @{$searchargs_ref->{'issn'}}, $input_data_ref->{'eissn'} if ($input_data_ref->{'eissn'});

    push @{$searchargs_ref->{'year'}}, $input_data_ref->{'date'} if ($input_data_ref->{'date'});

    push @{$searchargs_ref->{'volume'}}, $input_data_ref->{'volume'} if ($input_data_ref->{'volume'});

    push @{$searchargs_ref->{'issue'}}, $input_data_ref->{'issue'} if ($input_data_ref->{'issue'});
    
    # Pagerange?
    if ($input_data_ref->{'pages'}){
	push @{$searchargs_ref->{'pages'}}, $input_data_ref->{'pages'}
    }
    elsif ($input_data_ref->{'spage'} || $input_data_ref->{'epage'}){
	my $pages = "";

	$pages = $input_data_ref->{'spage'} if ($input_data_ref->{'spage'});
	$pages.= "=".$input_data_ref->{'epage'} if ($input_data_ref->{'epage'});
						   
	push @{$searchargs_ref->{'pages'}}, $pages;
    }

    if ($logger->is_debug){
	$logger->debug("Search-Args conversion result: ".YAML::Dump($searchargs_ref));
    }
    
    return $searchargs_ref;    
}

sub get_input_definition {
    my $self=shift;

    # OpenURL 0.1 Standard
    # see https://oclc-research.github.io/OpenURL-Frozen/docs/pdf/openurl-01.pdf

    # OpenURL 1.0 Standard
    # see https://groups.niso.org/higherlogic/ws/public/download/14833/z39_88_2004_r2010.pdf
    # see https://support.nii.ac.jp/en/cir/r_link_receive
    
    return {
	# OpenURL 0.1
        sid => {
            default  => '',
            encoding => 'none', # no default conversion to utf8
            type     => 'scalar',
        },
        genre => {  # journal | book | conference | article | preprint | proceeding | bookitem
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        aulast => { # first author's last name
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        aufirst => { # first author's first name
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        auinit => { # first author's first and middle initials
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        auinit1 => { # first author's first initial
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        auinitm => { # first author's middle initial
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        pid => {     # URL-Encoded local-identifier-zone information
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	    no_escape => 1
        },
        title => {   # title of journal, book, conference (bundle)
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        atitle => {  # title of an article, preprint, conference, proceeding, part of a book (individual item)

            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        isbn => {    # ISBN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        issn => {    # ISSN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        eissn => {   # electronic ISSN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        date => {    # year
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        volume => {  # volume
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        issue => {   # issue
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        pages => {   # pagerange : spage-epage
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        spage => {   # start page
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        epage => {   # endpage
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

	# OpenURL 1.0

        url_ver => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        ctx_ver => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        rft_val_fmt => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.genre' => {  # journal | book | conference | article | preprint | proceeding | bookitem
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        ctx_enc => {   # Encoding
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        rfr_id => {   # Referrer-ID
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        rft_dat => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        rft_id => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.aulast' => { # first author's last name
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.aufirst' => { # first author's first name
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.auinit' => { # first author's first and middle initials
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.auinit1' => { # first author's first initial
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.auinitm' => { # first author's middle initial
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.au' => { # author's name
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.aucorp' => { # author's affiliation
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.btitle' => {   # title
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.atitle' => {  # title of an article
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.title' => {   # title of journal, book, conference (bundle)
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.jtitle' => {   # journal title
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.publisher' => {   # publisher
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.pub' => {   # publisher
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.inst' => {   # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.date' => {    # year
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.volume' => {  # volume
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.issue' => {   # issue
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.spage' => {   # start page
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.epage' => {   # endpage
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.pages' => {   # pagerange : spage-epage
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.issn' => {    # ISSN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.eissn' => {   # electronic ISSN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.isbn' => {    # ISBN
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

        'rft.degree' => {    # 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
        'rft.place' => {  # place
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

	# Additional

        url_enc => {   # Encoding
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },

    };
}

1;
