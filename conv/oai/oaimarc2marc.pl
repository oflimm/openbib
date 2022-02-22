#!/usr/bin/perl

#####################################################################
#
#  oaimarc2marc.pl
#
#  Konvertierung des via OAI gelieferten MARC21 XML-Formates in eine
#  Standard MARC21-Datei
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

use 5.008001;

use utf8;
use warnings;
use strict;

use XML::Twig::XPath;
use MARC::Record;
use MARC::Field;
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use MARC::File::XML;
use Getopt::Long;
use YAML::Syck;
use JSON::XS;
use Encode qw /decode_utf8 encode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $counter  =  1;

my ($inputfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
	    );

if (!$inputfile){
    print << "HELP";
oaimarc2marc.pl - Aufrufsyntax

    oaimarc2marc.pl --inputfile=xxx
HELP
exit;
}

open (MARC21,  ,"> pool.mrc");

binmode(MARC21);

my $twig= XML::Twig->new(
    map_xmlns => {'http://www.loc.gov/MARC21/slim' => "marc"},
    TwigHandlers => {
        "/recordlist/record" => \&parse_titset
    },
 );


$twig->safe_parsefile($inputfile);

close(MARC21);

sub parse_titset {
    my($t, $titset)= @_;


    # Get OAI ID

    my $id = "";
    my @elements = $titset->findnodes('//oaiProvenance:identifier');

    foreach my $element (@elements){
	$id = $element->text();
	last;
    }

    # Get MARC Record

    my $marc_record = "";
    
    @elements = $titset->findnodes('//metadata/marc:record');

    foreach my $element (@elements){
	# Get element subtree as string
	$marc_record = join '', map { $_->sprint } $element;
	$marc_record = encode_utf8($marc_record);

	# Cleanup

	$marc_record=~s/marc\:leader/leader/g;
	$marc_record=~s/marc\:controlfield/controlfield/g;
	$marc_record=~s/marc\:record/record/g;
	$marc_record=~s/marc\:subfield/subfield/g;
	$marc_record=~s/marc\:datafield/datafield/g;
	last;
    }
    
    
    unless ($id && $marc_record){
	$t->purge();
	return;
    }

    eval {
	open(my $fh, "<", \$marc_record);
	my $batch = MARC::Batch->new( 'XML', $fh );
	# Fallback to UTF8
	
	# Recover from errors
	$batch->strict_off();
	$batch->warnings_off();
	
	# Fallback to UTF8
	MARC::Charset->assume_unicode(1);
	# Ignore Encoding Errors
	MARC::Charset->ignore_errors(1);
	
	while (my $record = $batch->next() ){
	    # Delete Record ID if available
	    my $id_field = $record->field('001');
	    $record->delete_field($id_field) if ($id_field);
	    
	    # Set OAI ID as Record ID
	    my $field = MARC::Field->new('001',$id);
	    $record->insert_fields_ordered($field);
	    
	    print MARC21 $record->as_usmarc();
	}
	
	close($fh);
    };
    
    if ($@){
	print STDERR "Error: $@\n"; 
    }

    if ($counter % 10000 == 0){
	print STDERR "$counter records done\n";
    }

    $counter++;
    # Release memory of processed tree
    # up to here
    $t->purge();
}

