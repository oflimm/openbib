#!/usr/bin/perl

#####################################################################
#
#  eprints2meta.pl
#
#  Konvertierung des EPrints XML-Formates in des OpenBib
#  Einlade-Metaformat
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

use utf8;

use warnings;
use strict;

use Encode 'decode';
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use XML::Twig::XPath;
use XML::Simple;
use YAML;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

our $mexidn  =  1;

our %have_title = ();
our $subject_ref = {};

my ($help,$titlefile,$subjectfile,$configfile,$logfile,$loglevel);

&GetOptions(
    "titlefile=s"          => \$titlefile,
    "subjectfile=s"        => \$subjectfile,
    "configfile=s"         => \$configfile,
    "logfile=s"            => \$logfile,
    "loglevel=s"           => \$loglevel,
    );

if ($help || !$titlefile || !$subjectfile){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/eprints2meta.log';
$loglevel = ($loglevel)?$loglevel:'INFO';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $twigsubject = XML::Twig::XPath->new(
    output_filter => 'safe',
    TwigHandlers => {
        "//subjects/subject" => \&parse_subject
    }
    );

my $twigtitle = XML::Twig->new(
    output_filter => 'safe',    
    TwigHandlers => {
        "//eprints/eprint" => \&parse_title
    }
 );

$twigsubject->safe_parsefile($subjectfile);

$twigtitle->safe_parsefile($titlefile);

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub parse_subject {
    my($t, $record)= @_;

    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug($record->toString);
    }

    my $id = $record->first_child('subjectid')->text() if $record->first_child('subjectid');    

    my @names = $record->findnodes('//name/item');

    foreach my $thisname (@names){
	if ($thisname->first_child('name')){
	    my $name = $thisname->first_child('name')->text();
	    my $lang = $thisname->first_child('lang')->text();
	    
	    $subject_ref->{$id} = $name if ($lang eq "de");
	}
    }

        # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_title {
    my($t, $record)= @_;
    
    my $title_ref = {
        'fields' => {},
    };

    my $fields_ref = {};
    
    my $mult = 1;
    my $f_idx;

    my $mult_ref = {};
    
    my $id     = $record->first_child('eprintid')->text();
    $title_ref->{id} = $convconfig->{idprefix}.$id;

    unless ($id){
	$logger->debug("Ignored - no ID");
	$t->purge();
	return;
    }

    my $status = $record->first_child('eprint_status')->text();    

    # Nur freigegebene EPrints exportieren
    if ($status ne "archive"){
	$logger->debug("Ignored ID $id - status is not archive");	
	$t->purge();
	return;
    }
    
    my $type = $record->first_child('type')->text();
    
    # Volltexte vorhanden?
    my $have_documents = 0;

    my @docs = $record->findnodes('//documents/document/files/file');

    if (@docs){
	$have_documents = 1;
    }

    # Sonderfall 'Dissertations Abstracts' = nur Abstract als Dokument
    # auch aussondern?
    if ($type eq "thesis_abstract"){
	$have_documents = 0;
    }

    # Dokumente ohne Volltext irrelevant
    unless ($have_documents){
	$logger->debug("Ignored ID $id - no full text");
	$t->purge();
	return;
    }

    $logger->debug("Processing ID $id");
    
    # Titel
    if ($record->first_child('title')) {
	$mult_ref->{'0331'} = 1;
	
	push @{$fields_ref->{'0331'}}, {
	    content  => $record->first_child('title')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0331'}++
	}
    }

    # Jahr
    if ($record->first_child('date')) {
	$mult_ref->{'0425'} = 1;
	
	push @{$fields_ref->{'0425'}}, {
	    content  => $record->first_child('date')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0425'}++
	};
    }

    # Sprache
    if ($record->first_child('language')) {
	$mult_ref->{'0015'} = 1;
	
	push @{$fields_ref->{'0015'}}, {
	    content  => $record->first_child('language')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0015'}++
	};
    }

    # Format
    if ($record->first_child('format')) {
	$mult_ref->{'0435'} = 1;

	my $content = $record->first_child('format')->text();

	if ($content =~m/pdf/){
	    $content = "PDF Datei";
	}
	
	push @{$fields_ref->{'0435'}}, {
	    content  => $record->first_child('format')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0435'}++
	};
    }
    
    # ISSN
    if ($record->first_child('issn')) {
	$mult_ref->{'0543'} = 1;
	
	push @{$fields_ref->{'0543'}}, {
	    content  => $record->first_child('issn')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0543'}++
	};
    }

    # DOI
    if ($record->first_child('id_number')) {
	$mult_ref->{'0552'} = 1;
	
	push @{$fields_ref->{'0552'}}, {
	    content  => $record->first_child('id_number')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0552'}++
	};
    }
    
    # Abstract
    if ($record->first_child('abstract')) {
	$mult_ref->{'0750'} = 1;
	
	push @{$fields_ref->{'0750'}}, {
	    content  => $record->first_child('abstract')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0750'}++
	};
    }

    # Abstract translated
    if ($record->first_child('abstracttranslated')) {
	my @abstracts = $record->findnodes('//abstracttranslated/item');

	foreach my $abstract (@abstracts){

	    if ($abstract->first_child('name')){
		my $content = $abstract->first_child('name')->text();

		$content=~s/\n/<br\/>/g;
		
		push @{$fields_ref->{'0750'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult_ref->{'0750'}++
		};
	    }
	}
    }

    $mult_ref->{'0662'} = 1;
    
    # URL
    if ($have_documents){
	push @{$fields_ref->{'0662'}}, {
	    content  => $convconfig->{baseurl}.$id,
	    subfield => 'g',
	    mult     => $mult_ref->{'0662'},
	};

	push @{$fields_ref->{'4662'}}, {
	    content  => $convconfig->{baseurl}.$id,
	    subfield => 'g',
	    mult     => $mult_ref->{'0662'},
	};
	
	push @{$fields_ref->{'0663'}}, {
	    content  => "Volltext",
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};

	push @{$fields_ref->{'4663'}}, {
	    content  => "Volltext",
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};
	
	push @{$fields_ref->{'4120'}}, {
	    content  => $convconfig->{baseurl}.$id,
	    subfield => 'g',
	    mult     => $mult_ref->{'0662'},
	};
	
	$mult_ref->{'0662'}++;
    }

    # Offizieller URL
    if ($record->first_child('official_url')) {
	push @{$fields_ref->{'0662'}}, {
	    content  => $record->first_child('official_url')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};
	push @{$fields_ref->{'4662'}}, {
	    content  => $record->first_child('official_url')->text(),
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};
	push @{$fields_ref->{'0663'}}, {
	    content  => "Offizieller Link",
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};
	push @{$fields_ref->{'4663'}}, {
	    content  => "Offizieller Link",
	    subfield => '',
	    mult     => $mult_ref->{'0662'},
	};


	$mult_ref->{'0662'}++;
    }

    # Related URLs

    if ($record->first_child('related_url')) {
	my @urls = $record->findnodes('//related_url/item/url');
	
	foreach my $url (@urls){
   	    my $content = $url->text();
	    
	    if ($content){
		push @{$fields_ref->{'0662'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult_ref->{'0662'},
		};
		push @{$fields_ref->{'4662'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult_ref->{'0662'},
		};
		push @{$fields_ref->{'0663'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult_ref->{'0662'},
		};
		push @{$fields_ref->{'4663'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult_ref->{'0662'},
		};
		
		$mult_ref->{'0662'}++;
	    }
	}
    }
    
    my $publication = "";
    if ($record->first_child('publication')){ 
	$publication = $record->first_child('publication')->text();
    }

    my $band = "";
    if ($record->first_child('volume')){
	$band = $record->first_child('volume')->text();
    }
    
    my $heft = "";
    if ($record->first_child('number')){
	$heft = $record->first_child('number')->text();
    }

    my $seiten = "";
    if ($record->first_child('pages')){
	$seiten = $record->first_child('pages')->text();
    }

    my $serie = "";
    if ($record->first_child('local_series')){ 
	$serie = $record->first_child('local_series')->text();
    }
    elsif ($record->first_child('series')){ 
	$serie = $record->first_child('series')->text();
    }

    if ($type =~m/(article)/){
	my $hstquelle = "";
	
	if ($serie){
	    $hstquelle .= $serie;
	}
	elsif ($publication){
	    $hstquelle .= $publication;
	}
	
	if ($band){
	    $hstquelle .= " ($band)";
	}

	if ($heft){
	    $hstquelle .= ", Nr. $heft";
	}
	if ($seiten){
	    $hstquelle .= ", $seiten";
	}

	$mult_ref->{'0590'} = 1;
	
	push @{$fields_ref->{'0590'}}, {
	    content  => $hstquelle,
	    subfield => '',
	    mult     => $mult_ref->{'0590'}++,
	};
	
    }
    else {
	if ($band){
	    $mult_ref->{'0089'} = 1;
	
	    push @{$fields_ref->{'0089'}}, {
		content  => $band,
		subfield => '',
		mult     => $mult_ref->{'0089'}++,
	    };
	}

	if ($serie){
	    $mult_ref->{'0451'} = 1;
	    
	    push @{$fields_ref->{'0451'}}, {
		content  => $serie,
		subfield => '',
		mult     => $mult_ref->{'0451'}++,
	    };
	}

	if ($publication){
	    $mult_ref->{'0451'} = 1;
	    
	    push @{$fields_ref->{'0451'}}, {
		content  => $publication,
		subfield => '',
		mult     => $mult_ref->{'0451'}++,
	    };
	}
	
    }
    
    # Verfasser
    {
	$mult_ref->{'0100'} = 1;
	
	my @creators = $record->findnodes('//creators/item');
	
	foreach my $creator (@creators){
	    my @names = $creator->children('name');
	    
	    my $fullname = "";
	    foreach my $name (@names){
		my $familyname = $name->first_child('family')->text() if ($name->first_child('family'));
		my $givenname  = $name->first_child('given')->text()  if ($name->first_child('given'));
		
		$fullname = "$familyname";
		$fullname .=", $givenname" if ($givenname);
	    }
	    
	    my $orcid = "";
	    
	    if ($creator->first_child('orcid')){ 
		$orcid = $creator->first_child('orcid')->text();
	    }

	    my $new;
	    my $person_id;
	    
	    if ($orcid){
		# Orcid erstes Mal? Dann new=1 und Erzeugung eines Normsatzes
		($person_id,$new)= OpenBib::Conv::Common::Util::get_person_id($orcid);
		$person_id = $orcid;
	    }
	    else {
		($person_id,$new)= OpenBib::Conv::Common::Util::get_person_id($fullname);
	    }
	    
	    if ($new){
		
		my $item_ref = {
		    'fields' => {},
		};
		$item_ref->{id} = $person_id;
		push @{$item_ref->{fields}{'0800'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $fullname,
		};
		
		print PERSON encode_json $item_ref, "\n";
	    }
	    
	    push @{$fields_ref->{'0100'}}, {
		content    => $fullname,
		mult       => $mult_ref->{'0100'}++,
		subfield   => '',
		id         => $person_id,
		supplement => '',
	    };
	    
	    $mult++;
	}
    }

    # Herausgeber
    {
	$mult_ref->{'0101'} = 1;
	
	my @editors = $record->findnodes('//editors/item');
	
	foreach my $editor (@editors){
	    my @names = $editor->children('name');
	    
	    my $fullname = "";
	    foreach my $name (@names){
		my $familyname = $name->first_child('family')->text() if ($name->first_child('family'));
		my $givenname  = $name->first_child('given')->text()  if ($name->first_child('given'));
		
		$fullname = "$familyname";
		$fullname .=", $givenname" if ($givenname);
	    }
	    
	    my $orcid = "";
	    
	    if ($editor->first_child('orcid')){ 
		$orcid = $editor->first_child('orcid')->text();
	    }

	    my $new;
	    my $person_id;
	    
	    if ($orcid){
		# Orcid erstes Mal? Dann new=1 und Erzeugung eines Normsatzes
		($person_id,$new)= OpenBib::Conv::Common::Util::get_person_id($orcid);
		$person_id = $orcid;
	    }
	    else {
		($person_id,$new)= OpenBib::Conv::Common::Util::get_person_id($fullname);
	    }
	    
	    if ($new){
		
		my $item_ref = {
		    'fields' => {},
		};
		$item_ref->{id} = $person_id;
		push @{$item_ref->{fields}{'0800'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $fullname,
		};
		
		print PERSON encode_json $item_ref, "\n";
	    }
	    
	    push @{$fields_ref->{'0101'}}, {
		content    => $fullname,
		mult       => $mult_ref->{'0101'}++,
		subfield   => '',
		id         => $person_id,
		supplement => 'Hrsg.',
	    };
	    
	    $mult++;
	}
    }
    
    # Koerperschaften = Institut
    {
	$mult_ref->{'0201'} = 1;
	    
	my @divisions = $record->findnodes('//divisions/item');
	
	foreach my $division (@divisions){
	    my $code = $division->text();
	    if (defined $subject_ref->{$code}){
		my $content = $subject_ref->{$code};

		next if ($content =~m/Keine Angabe/);
		
		my ($corporatebody_id,$new)=OpenBib::Conv::Common::Util::get_corporatebody_id($content);

		# Immer code als ID (Beschreibungen zum Code sind disjukt)
		$corporatebody_id = $code;
		
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $corporatebody_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $content,
		    };
		    
		    print CORPORATEBODY encode_json $item_ref, "\n";
		}
		
		push @{$fields_ref->{'0201'}}, {
		    content    => $content,
		    mult       => $mult_ref->{'0201'}++,
		    subfield   => '',
		    id         => $corporatebody_id,
		    supplement => '',
		};
	    }
	}
    }
	
    # Notationen 
    {
	$mult_ref->{'0700'} = 1;
	
	my @subjects = $record->findnodes('//subjects/item');
	
	foreach my $subject (@subjects){
	    my $code = $subject->text();
	    if (defined $subject_ref->{$code}){
		my $content = $subject_ref->{$code};
		
		my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($content);

		# Immer code als ID (Beschreibungen zum Code sind disjukt)
		$classification_id = $code;
                
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $classification_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $content,
		    };
		    
		    print CLASSIFICATION encode_json $item_ref, "\n";
		}
		
		push @{$fields_ref->{'0700'}}, {
		    content    => $content,
		    mult       => $mult_ref->{'0700'}++,
		    subfield   => '',
		    id         => $classification_id,
		    supplement => '',
		};
	    }
	}
    }

    # Schlagworte
    {
	my @free_keywords = $record->findnodes('//keywords/item');
	
	my @keywords = ();
	
	foreach my $free_keyword (@free_keywords){
	    
	    if ($free_keyword->first_child('name')){
		my $keyword = $free_keyword->first_child('name')->text();
		
		push @keywords, split('\s+[,;]\s+',$keyword);
	    }
	}

	foreach my $content (@keywords){
	    my ($subject_id,$new)=OpenBib::Conv::Common::Util::get_subject_id($content);
	    
	    if ($new){	  
		my $item_ref = {
		    'fields' => {},
		};
		$item_ref->{id} = $subject_id;
		push @{$item_ref->{fields}{'0800'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $content,
		};
		
		print SUBJECT encode_json $item_ref, "\n";
	    }
	    
	    push @{$fields_ref->{'0710'}}, {
		content    => $content,
		mult       => $mult_ref->{'0710'}++,
		subfield   => '',
		id         => $subject_id,
		supplement => '',
	    };
	}
    }
    
    $title_ref->{fields} = $fields_ref;
    
    print TITLE encode_json $title_ref, "\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();

    return;
}

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}

# Filter

sub filter_junk {
    my ($content) = @_;

    $content=~s/\W/ /g;
    $content=~s/\s+/ /g;
    $content=~s/\s\D\s/ /g;

    
    return $content;
}

sub filter_newline2br {
    my ($content) = @_;

    $content=~s/\n/<br\/>/g;
    
    return $content;
}

sub filter_match {
    my ($content,$regexp) = @_;

    my ($match)=$content=~m/($regexp)/g;
    
    return $match;
}

