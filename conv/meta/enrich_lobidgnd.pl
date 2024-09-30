#!/usr/bin/perl

#####################################################################
#
#  enrich_lobidgnd.pl
#
#  Anreichern der Normdaten im JSON-Metaformat mit JSONL-Daten aus Lobid-GND
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;
use utf8;

use DB_File;
use Encode qw(decode_utf8 encode_utf8);
use Getopt::Long;
use JSON::XS;
use List::MoreUtils qw/ uniq /;
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

my ($gndfile,$filename,$type,$dbfile);

&GetOptions(
    "gnd-file=s" => \$gndfile,
    "db-file=s"  => \$dbfile,    
    "type=s"     => \$type,
    "filename=s" => \$filename,
    );

$gndfile=($gndfile)?$gndfile:"/opt/openbib/autoconv/pools/lobidgnd/gnd.json.gz";
$dbfile=($dbfile)?$dbfile:"/opt/openbib/autoconv/pools/lobidgnd/gnd.db";

exit unless ($type);

my $rebuild_db = 0;

if (!-f $dbfile){
    $rebuild_db = 1;
}

my %gnd = ();

tie %gnd,             'MLDBM', $dbfile
    or die "Could not tie gnd.\n";


if ($rebuild_db){
    print STDERR "Building GND-DB\n";
    open(GND,"zcat $gndfile |");
    binmode(GND);
    
    while (<GND>){
	my $record_ref = decode_json $_;
	
	my $id = $record_ref->{id};
	($id) = $id =~m{https://d-nb.info/gnd/(.+)$};
	next unless ($id);
	
	my $gnd_ref = {};
	
	if (defined $record_ref->{variantName}){
	    foreach my $item (@{$record_ref->{variantName}}){	    
		push @{$gnd_ref->{variant}}, encode_utf8($item);
	    }
	}
	
	if (defined $record_ref->{relatedTerm}){
	    foreach my $item_ref (@{$record_ref->{relatedTerm}}){
		push @{$gnd_ref->{related}}, encode_utf8($item_ref->{label});	    
	    }
	}
	
	if (defined $record_ref->{relatedSubjectHeading}){
	    foreach my $item_ref (@{$record_ref->{relatedSubjectHeading}}){
		push @{$gnd_ref->{related}}, encode_utf8($item_ref->{label});	    
	    }
	}
	
	if (defined $record_ref->{broaderTermPartitive}){
	    foreach my $item_ref (@{$record_ref->{broaderTermPartitive}}){
		push @{$gnd_ref->{broader}}, encode_utf8($item_ref->{label});  
	    }
	}
	
	if (defined $record_ref->{broaderTermGeneral}){
	    foreach my $item_ref (@{$record_ref->{broaderTermGeneral}}){
		push @{$gnd_ref->{broader}}, encode_utf8($item_ref->{label});   
	    }
	}
	
	if (defined $record_ref->{broaderTermGeneric}){
	    foreach my $item_ref (@{$record_ref->{broaderTermGeneric}}){
		push @{$gnd_ref->{broader}}, encode_utf8($item_ref->{label});
	    }
	}
	
	if (defined $record_ref->{gndSubjectCategory}){
	    foreach my $item_ref (@{$record_ref->{gndSubjectCategory}}){
		push @{$gnd_ref->{category}}, encode_utf8($item_ref->{label});	    
	    }
	}

	if (defined $record_ref->{abbreviatedNameForTheCorporateBody}){
	    foreach my $item (@{$record_ref->{abbreviatedNameForTheCorporateBody}}){
		push @{$gnd_ref->{abbreviation}}, encode_utf8($item);	    
	    }
	}
	
	$gnd{$id} = $gnd_ref;
    }
    print STDERR "Building GND-DB done\n";	
}

open (IN,$filename);

my $idx = 1;
while (<IN>){
    my $record_ref = decode_json $_;

    my $id = $record_ref->{id};

    if ($id =~m/DE-588/){
	
	$id=~s/.DE-588.//;
	
	next unless (exists $gnd{$id});
	
	my $gnd_ref = $gnd{$id};
	
	if ($type eq "person"){
	    my $variant_mult = 1;
	    
	    if (defined $gnd_ref->{variant}){
		foreach my $item (@{$gnd_ref->{variant}}){
		    push @{$record_ref->{fields}{'0830'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $variant_mult++,
		    };
		}
	    }	    
	}
	
	if ($type eq "corporatebody"){
	    my $variant_mult      = 1;
	    my $abbreviation_mult = 1;	    
	    
	    if (defined $gnd_ref->{variant}){
		foreach my $item (@{$gnd_ref->{variant}}){
		    push @{$record_ref->{fields}{'0810'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $variant_mult++,
		    };
		}
	    }	    

	    if (defined $gnd_ref->{abbreviation}){
		foreach my $item (@{$gnd_ref->{abbreviation}}){
		    push @{$record_ref->{fields}{'0881'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $abbreviation_mult++,
		    };
		}
	    }	    
	}

	if ($type eq "subject"){
	    my $variant_mult = 1;
	    my $related_mult = 1;
	    my $broader_mult = 1;
	    my $subject_mult = 1;

	    if (defined $gnd_ref->{variant}){
		foreach my $item (@{$gnd_ref->{variant}}){
		    push @{$record_ref->{fields}{'0830'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $variant_mult++,
		    };
		}
	    }
	    
	    if (defined $gnd_ref->{related}){
		foreach my $item (@{$gnd_ref->{related}}){
		    push @{$record_ref->{fields}{'0860'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $related_mult++,
		    };
		}
	    }
	    
	    if (defined $gnd_ref->{broader}){
		foreach my $item (@{$gnd_ref->{broader}}){
		    push @{$record_ref->{fields}{'0850'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $broader_mult++,
		    };
		}
	    }
	    
	    if (defined $gnd_ref->{category}){
		foreach my $item (@{$gnd_ref->{category}}){
		    push @{$record_ref->{fields}{'0810'}}, {
			content => decode_utf8($item),
			subfield => "e",
			mult => $subject_mult++,
		    };
		}
	    }
	    
	}
	if ($idx % 1000 == 0){
	    print STDERR ".";
	}

	
	$idx++;
    }
    
    print encode_json $record_ref, "\n";
}

close(IN);

print STDERR "\n";
