#!/usr/bin/perl

#####################################################################
#
#  ksta2meta.pl
#
#  Konvertierung der KStA-Daten in das OpenBib
#  Einlade-Metaformat
#
#  Entstanden aus repec2meta.pl
#
#  Dieses File ist (C) 2025 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;

use utf8;
use warnings;
use strict;

use Encode 'decode';
use File::Find;
use File::Slurp;
use Getopt::Long;
use JSON::XS;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML::Syck;
use DB_File;
use Encode qw /decode_utf8 decode find_encoding/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our ($inputdir);

&GetOptions(
	    "inputdir=s"           => \$inputdir,
	    );

if (!$inputdir){
    print << "HELP";
ksta2meta.pl - Aufrufsyntax

    ksta2meta.pl --inputdir=xxx > meta.title

HELP
exit;
}

find(\&process_file, $inputdir);

sub process_file {
    return unless ($File::Find::name =~m{KoelnerStadtAnzeiger_J_\d\d\d\d});
    return unless ($File::Find::name=~m{_ARTIKEL/.+?.xml$} || $File::Find::name=~m{_ILLUSTRATIONEN/.+?.xml$});
		   
    my $title_ref = {
        'fields' => {},
    };

    my $item_fullpath = $File::Find::name;
    my $item_path     = $File::Find::dir;
    my $item_filename = $_;
 
    my $multcount_ref = {};
    
    my ($id) = $item_filename =~m{^(.+?).xml$};

    $title_ref->{id} = $id;

    if ($item_fullpath =~/_ARTIKEL/){	
	my ($pdf_path,$pdf_dir) = $item_path =~m{^(.+?)/([^/]+?)/_ARTIKEL};

	$pdf_path =~s/^.+?KoelnerStadtAnzeiger_J_/KoelnerStadtAnzeiger_J_/; 
	
	my $pdf_filename = $pdf_path."/".$pdf_dir."/".$pdf_dir.".pdf";
	
	my ($day,$month,$year,$issue) = $item_path =~m/_A_(\d+)-(\d+)-(\d\d\d\d)_N_(\d+)\//;

	my $slurped_file = read_file($item_fullpath);

	my ($title)            = $slurped_file =~m{<HTI>(.+?)</HTI>};	
	my ($dtitle)           = $slurped_file =~m{<DTI>(.+?)</DTI>};
	my ($subtitle)         = $slurped_file =~m{<UTI>(.+?)</UTI>};
	my ($rubriktitle)      = $slurped_file =~m{<GTI>(.+?)</GTI>};	
	my ($body)             = $slurped_file =~m{<body>(.+?)</BODY>}ism;
	my ($pdfpage_filename) = $slurped_file =~m{<pdfFile>(.+?)</pdfFile>};
	my ($encoding)         = $slurped_file =~m{<\?xml version="1.0" encoding="(.+?)"\?>};

	my ($page) = $pdfpage_filename =~m{_A_\d\d-\d\d-\d\d\d\d_N_\d+_(\d+)};
	
	$pdfpage_filename = $pdf_path."/".$pdf_dir."/".$pdfpage_filename;
	
	my ($publication_date) = $slurped_file =~m{<publicationDate>(.+?)</publicationDate>};
	
	my $enc = find_encoding($encoding);

	push @{$title_ref->{fields}{'4410'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => 'Artikel',
	};

	if ($dtitle){
	    my $mult = ++$multcount_ref->{'0310'};

	    push @{$title_ref->{fields}{'0310'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($dtitle),
	    };
	}
	
	if ($title){
	    my $mult = ++$multcount_ref->{'0331'};

	    push @{$title_ref->{fields}{'0331'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($title),
	    };
	}

	if ($subtitle){
	    my $mult = ++$multcount_ref->{'0335'};

	    push @{$title_ref->{fields}{'0335'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($subtitle),
	    };
	}

	if ($rubriktitle){
	    my $mult = ++$multcount_ref->{'0451'};

	    push @{$title_ref->{fields}{'0451'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($rubriktitle),
	    };
	}
	
	if ($page){
	    $page =~s/^0+//;
	    
	    my $mult = ++$multcount_ref->{'0433'};

	    push @{$title_ref->{fields}{'0433'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $page,
	    };
	}
	
	if ($pdfpage_filename){
	    my $mult = ++$multcount_ref->{'0662'};

	    push @{$title_ref->{fields}{'0662'}}, {
		mult     => $mult,
		subfield => '',
		content  => $pdfpage_filename,
	    };

	    push @{$title_ref->{fields}{'0663'}}, {
		mult     => $mult,
		subfield => '',
		content  => "Zum PDF der Seite des Artikels",
	    };
	    
	}
	
	if ($pdf_filename){
	    my $mult = ++$multcount_ref->{'4120'};

	    push @{$title_ref->{fields}{'4120'}}, {
		mult     => $mult,
		subfield => 'y',
		content  => $pdf_filename,
	    };
	}

	if ($year){
	    my $mult = ++$multcount_ref->{'0425'};

	    push @{$title_ref->{fields}{'0425'}}, {
		mult     => $mult,
		subfield => '',
		content  => $year,
	    };
	}

	if ($issue){
	    my $mult = ++$multcount_ref->{'0089'};

	    push @{$title_ref->{fields}{'0089'}}, {
		mult     => $mult,
		subfield => '',
		content  => $issue,
	    };
	}

	if ($publication_date){
	    my $mult = ++$multcount_ref->{'0595'};

	    push @{$title_ref->{fields}{'0595'}}, {
		mult     => $mult,
		subfield => '',
		content  => $publication_date,
	    };
	}

	if ($body){
	    my $mult = ++$multcount_ref->{'0750'};
	    push @{$title_ref->{fields}{'0750'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($body),
	    };
	}
	
    }
    elsif ($item_fullpath =~/_ILLUSTRATIONEN/){	
	my ($image_path,$image_dir) = $item_path =~m{^(.+?)/([^/]+?)/_ILLUSTRATIONEN};

	$image_path =~s/^.+?KoelnerStadtAnzeiger_J_/KoelnerStadtAnzeiger_J_/; 

	my $pdf_filename = $image_path."/".$image_dir."/".$image_dir.".pdf";
	
	my ($day,$month,$year,$issue) = $item_path =~m/_A_(\d+)-(\d+)-(\d\d\d\d)_N_(\d+)\//;

	my $slurped_file = read_file($item_fullpath);

	my ($title)              = $slurped_file =~m{<captionText>(.+?)</captionText>};
	my ($imagepage_filename) = $slurped_file =~m{<illustrationFile>(.+?)</illustrationFile>};
	my ($pdfpage_filename)   = $slurped_file =~m{<pdfFile>(.+?)</pdfFile>};
	my ($encoding)           = $slurped_file =~m{<\?xml version="1.0" encoding="(.+?)"\?>};

	my ($page) = $pdfpage_filename =~m{_A_\d\d-\d\d-\d\d\d\d_N_\d+_(\d+)};

	
	$pdfpage_filename = $image_path."/".$image_dir."/".$pdfpage_filename;

	$imagepage_filename = $image_path."/".$image_dir."/_ILLUSTRATIONEN/".$imagepage_filename;
	
	my ($publication_date) = $slurped_file =~m{<publicationDate>(.+?)</publicationDate>};

	#next if ($title =~m/Untitled/i);

	my $enc = find_encoding($encoding);

	push @{$title_ref->{fields}{'4410'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => 'Illustration',
	};
	
	if ($title){
	    my $mult = ++$multcount_ref->{'0331'};

	    push @{$title_ref->{fields}{'0331'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $enc->decode($title),
	    };
	}

	if ($page){
	    $page =~s/^0+//;
	    
	    my $mult = ++$multcount_ref->{'0433'};

	    push @{$title_ref->{fields}{'0433'}}, {
		mult       => $mult,
		subfield   => '',
		content    => $page,
	    };
	}
	
	if ($imagepage_filename){
	    my $mult = ++$multcount_ref->{'0662'};

	    push @{$title_ref->{fields}{'0662'}}, {
		mult     => $mult,
		subfield => '',
		content  => $imagepage_filename,
	    };

	    push @{$title_ref->{fields}{'0663'}}, {
		mult     => $mult,
		subfield => '',
		content  => "Zur Illustration",
	    };
	    
	}

	if ($pdfpage_filename){
	    my $mult = ++$multcount_ref->{'0662'};

	    push @{$title_ref->{fields}{'0662'}}, {
		mult     => $mult,
		subfield => '',
		content  => $pdfpage_filename,
	    };

	    push @{$title_ref->{fields}{'0663'}}, {
		mult     => $mult,
		subfield => '',
		content  => "Zum PDF der Seite des Artikels",
	    };	
	}

	if ($pdf_filename){
	    my $mult = ++$multcount_ref->{'4120'};

	    push @{$title_ref->{fields}{'4120'}}, {
		mult     => $mult,
		subfield => 'y',
		content  => $pdf_filename,
	    };
	}
	
	if ($year){
	    my $mult = ++$multcount_ref->{'0425'};

	    push @{$title_ref->{fields}{'0425'}}, {
		mult     => $mult,
		subfield => '',
		content  => $year,
	    };
	}

	if ($issue){
	    my $mult = ++$multcount_ref->{'0089'};

	    push @{$title_ref->{fields}{'0089'}}, {
		mult     => $mult,
		subfield => '',
		content  => $issue,
	    };
	}

	if ($publication_date){
	    my $mult = ++$multcount_ref->{'0595'};

	    push @{$title_ref->{fields}{'0595'}}, {
		mult     => $mult,
		subfield => '',
		content  => $publication_date,
	    };
	}
    }
    
    print encode_json $title_ref, "\n";
}
