#!/usr/bin/perl

#####################################################################
#
#  id3tag2meta.pl
#
#  Konvertierung eines Verzeichnisses mit mp3-Dateien in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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
use YAML::Syck;
use JSON::XS qw(encode_json);
use MP3::Tag;
use DB_File;
use Encode qw /decode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $titleid   = 1;
our $holdingid = 1;
our $fileidx   = 0;

my ( $inputdir, $idmappingfile );

&GetOptions( "inputdir=s" => \$inputdir, );

if ( !$inputdir ) {
	print << "HELP";
id3tag2meta.pl - Aufrufsyntax

    id3tag2meta.pl --inputdir=xxx
HELP
	exit;
}

our $have_titleid_ref = {};

open( TITLE,,         "|buffer | gzip > meta.title.gz" );
open( PERSON,,        "|buffer | gzip > meta.person.gz" );
open( CORPORATEBODY,, "|buffer | gzip > meta.corporatebody.gz" );
open( CLASSIFICATION, "|buffer | gzip > meta.classification.gz" );
open( SUBJECT,,       "|buffer | gzip > meta.subject.gz" );
open( HOLDING,,       "|buffer | gzip > meta.holding.gz" );

binmode(TITLE);
binmode(PERSON);
binmode(CORPORATEBODY);
binmode(CLASSIFICATION);
binmode(SUBJECT);
binmode(HOLDING);

sub process_file {
	return unless ( -f $File::Find::name && $File::Find::name =~ /.mp3$/ );

	print "Processing " . $File::Find::name . "\n";

	# Workaround: XPATH-Problem mit Default-Namespace. Daher alle
	# Namespaces entfernen.

	my $mp3 = MP3::Tag->new($File::Find::name);

	$mp3->get_tags;

	unless ( exists $mp3->{ID3v1} ) {                  # print track information
		print "No ID3v1 info\n";
		return;
	}

	#######################################################################
	# Header

	my $id = $titleid++;

	my $title_ref = { 'fields' => {}, };

	$title_ref->{id} = $id;

	# Interpret
	{

		# Interpret -> Verfasser
		my $content = $mp3->{ID3v1}->artist;
		if ($content) {
			my ( $person_id, $new ) =
			  OpenBib::Conv::Common::Util::get_person_id($content);

			if ($new) {
				my $item_ref = { 'fields' => {}, };
				$item_ref->{id} = $person_id;
				push @{ $item_ref->{fields}{'0800'} },
				  {
					mult     => 1,
					subfield => '',
					content  => $content,
				  };

				print PERSON encode_json $item_ref, "\n";
			}

			push @{ $title_ref->{fields}{'0100'} },
			  {
				mult       => 1,
				subfield   => '',
				id         => $person_id,
				supplement => '',
			  };
		}

	}

	{

		# Titel
		my $content = $mp3->{ID3v1}->title;
		if ($content) {
			push @{ $title_ref->{fields}{'0331'} },
			  {
				content  => $content,
				subfield => '',
				mult     => 1,
			  };
		}
	}

	{

		# Track
		my $content = $mp3->{ID3v1}->track;
		if ($content) {
			push @{ $title_ref->{fields}{'0089'} },
			  {
				content  => $content,
				subfield => '',
				mult     => 1,
			  };
		}
	}

	{

		# Jahr
		my $content = $mp3->{ID3v1}->year;
		if ($content) {
			push @{ $title_ref->{fields}{'0425'} },
			  {
				content  => $content,
				subfield => '',
				mult     => 1,
			  };
		}
	}

	{

		# Genre -> Schlagworte
		my $content = $mp3->{ID3v1}->genre;
		if ($content) {
			my ( $subject_id, $new ) =
			  OpenBib::Conv::Common::Util::get_subject_id($content);
			if ($new) {
				my $item_ref = { 'fields' => {}, };
				$item_ref->{id} = $subject_id;
				push @{ $item_ref->{fields}{'0800'} },
				  {
					mult     => 1,
					subfield => '',
					content  => $content
				  };

				print SUBJECT encode_json $item_ref, "\n";
			}

			push @{ $title_ref->{fields}{'0710'} },
			  {
				mult       => 1,
				subfield   => '',
				id         => $subject_id,
				supplement => '',
			  };
		}
	}

	{

		# Genre -> Schlagworte
		my $content = $mp3->{ID3v1}->album;
		if ($content) {
			my ( $corporatebody_id, $new ) =
			  OpenBib::Conv::Common::Util::get_corporatebody_id($content);
			if ($new) {
				my $item_ref = { 'fields' => {}, };
				$item_ref->{id} = $corporatebody_id;
				push @{ $item_ref->{fields}{'0800'} },
				  {
					mult     => 1,
					subfield => '',
					content  => $content
				  };

				print CORPORATEBODY encode_json $item_ref, "\n";
			}

			push @{ $title_ref->{fields}{'0200'} },
			  {
				mult       => 1,
				subfield   => '',
				id         => $corporatebody_id,
				supplement => '',
			  };
		}
	}

	{

		# Genre -> Schlagworte
		my $content = $mp3->{ID3v1}->genre;
		if ($content) {
			my ( $subject_id, $new ) =
			  OpenBib::Conv::Common::Util::get_subject_id($content);
			if ($new) {
				my $item_ref = { 'fields' => {}, };
				$item_ref->{id} = $subject_id;
				push @{ $item_ref->{fields}{'0800'} },
				  {
					mult     => 1,
					subfield => '',
					content  => $content
				  };

				print SUBJECT encode_json $item_ref, "\n";
			}

			push @{ $title_ref->{fields}{'0710'} },
			  {
				mult       => 1,
				subfield   => '',
				id         => $subject_id,
				supplement => '',
			  };
		}
	}

	print TITLE encode_json $title_ref, "\n";

	$fileidx++;

	if ( $fileidx % 1000 == 0 ) {
		print STDERR "$fileidx Saetze indexiert\n";

	}
}

find( \&process_file, $inputdir );

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub konv {
	my ($content) = @_;

	#    $content=~s/\&/&amp;/g;
	$content =~ s/>/&gt;/g;
	$content =~ s/</&lt;/g;

	return $content;
}

