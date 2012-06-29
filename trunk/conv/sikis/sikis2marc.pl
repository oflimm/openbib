#!/usr/bin/perl

#####################################################################
#
#  sikis2marc.pl
#
#  Generierung von MARC21-Saetzen aus dem Sikis-Format
#
#  Dieses File ist (C) 2011 Oliver Flimm <flimm@openbib.org>
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
use strict;
use warnings;

use Business::ISBN;
use DB_File;
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use MARC::Record;
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Statistics;

my ($titlefile,$personfile,$corporatebodyfile,$subjectfile,$classificationfile,$holdingfile,$configfile,$database,$reducemem,$logfile,$loglevel,$count);

&GetOptions("reduce-mem"    => \$reducemem,

	    "database=s"    => \$database,

            "configfile=s"  => \$configfile,

            "titlefile=s"          => \$titlefile,
            "personfile=s"         => \$personfile,
            "corporatebodyfile=s"  => \$corporatebodyfile,
            "subjectfile=s"        => \$subjectfile,
            "classificationfile=s" => \$classificationfile,
            "holdingfile=s"        => \$holdingfile,

            "logfile=s"     => \$logfile,
            "loglevel=s"    => \$loglevel,
	    );

if (!$configfile){
    print << "HELP";
sikis2marc.pl - Aufrufsyntax

    sikis2marc.pl --configfile=yyy
HELP
exit;
}

# Default-Filenamen
$titlefile          = $titlefile          || 'meta.title';
$personfile         = $personfile         || 'meta.person';
$corporatebodyfile  = $corporatebodyfile  || 'meta.corporatebody';
$subjectfile        = $subjectfile        || 'meta.subject';
$classificationfile = $classificationfile || 'meta.classification';
$holdingfile        = $holdingfile        || 'meta.holding';

my $config      = OpenBib::Config->instance;

# Ininitalisierung mit Config-Parametern
our $convconfig = YAML::Syck::LoadFile($configfile);

$logfile=($logfile)?$logfile:"/var/log/openbib/sikis2marc-$database.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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

my $dir=`pwd`;
chop $dir;

my %data_person           = ();
my %data_corporatebody    = ();
my %data_classification   = ();
my %data_subject          = ();
my %data_holding          = ();
my %data_superid          = ();

if ($reducemem){
    tie %data_person,        'MLDBM', "./data_person.db"
        or die "Could not tie data_person.\n";
    
    tie %data_corporatebody,        'MLDBM', "./data_corporatebody.db"
        or die "Could not tie data_corporatebody.\n";

    tie %data_classification,        'MLDBM', "./data_classification.db"
        or die "Could not tie data_classification.\n";
 
    tie %data_subject,        'MLDBM', "./data_subject.db"
        or die "Could not tie data_subject.\n";

    tie %data_holding,        'MLDBM', "./data_holding.db"
        or die "Could not tie data_holding.\n";

    tie %data_superid,    "DB_File", "./data_superid.db"
        or die "Could not tie data_superid.\n";
}

my $stammdateien_ref = {
    person         => {
        filename => $personfile,
        data     => \%data_person,
    },
    corporatebody  => {
        filename => $corporatebodyfile,
        data     => \%data_corporatebody,
    },
    subject        => {
        filename => $subjectfile,
        data     => \%data_subject,
    },
    
    classification => {
        filename  => $classificationfile,
        data      => \%data_classification,
    },

    holding => {
        filename  => $holdingfile,
        data      => \%data_holding,
    },

};


foreach my $type (keys %{$stammdateien_ref}){
    $logger->info("Bearbeite $stammdateien_ref->{$type}{filename}");
    
    open(IN ,       "<:utf8",$stammdateien_ref->{$type}{filename} )        || die "IN konnte nicht geoeffnet werden";
    
    my $id;
  CATLINE:
    while (my $line=<IN>){
        my ($category,$indicator,$content);
        if ($line=~m/^0000:(.+)$/){
            $id=$1;
            next CATLINE;
        }
        elsif ($line=~m/^9999:/){
            next CATLINE;
        }
        elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
            ($category,$indicator,$content)=($1,$2,$3);
        }
        elsif ($line=~m/^(\d+):(.*?)$/){
            ($category,$indicator,$content)=($1,'',$2);
        }
        
        if ($category && $content){
            chomp($content);

            
#             if ($type eq "person"){
#                 my $item_ref=(exists $data_person{$id})?$data_person{$id}:{};

#             }
            
#             if ($type eq "corporatebody"){
#                 if (exists $data_corporatebody{$id}){
#                     $item_ref=$data_corporatebody{$id}:
#                 }
#             }
            
#                         ($type eq "subject" && exists $data_subject{$id})?$data_subject{$id}:
#                             ($type eq "classification" && exists $data_classification{$id})?$data_classification{$id}:
#                                 ($type eq "holding" && exists $data_holding{$id})?$data_holding{$id}:{};

#             my %data =  %$stammdateien_ref->{$type}{data};

            my $item_ref = (exists $stammdateien_ref->{$type}{data}{$id})?$stammdateien_ref->{$type}{data}{$id}:{};
                
            $item_ref->{$category}{$indicator}=$content;
            
            $stammdateien_ref->{$type}{data}{$id}=$item_ref;
        }
    }   
    
    close(IN);
}

# Jetzt Titeldaten

$logger->info("Bearbeite $titlefile");

open(IN ,           "<:utf8",$titlefile         ) || die "IN konnte nicht geoeffnet werden";

my $thisitem_ref={};

$count=0;
my ($id,$type,$content,$cat);

CATLINE:
while (my $line=<IN>){
    my $searchfield_ref = {};
    
    my ($category,$indicator,$content);
    
    if ($line=~m/^0000:(.+)$/){
        $id=$1;
        $count++;
        
        $thisitem_ref={};
    }
    elsif ($line=~m/^9999:/){

        process_title($thisitem_ref);
        
        if ($count % 1000 == 0) {
	     $logger->debug("$count Titelsaetze bearbeitet");
        } 
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,'',$2);
    }

    if ($category && $content){
        chomp($content);
        
        
        # Alle Kategorien werden gemerkt
        $thisitem_ref->{$category}{$indicator}=$content;
    }
}

sub process_title {
    my $title_ref = shift;

    my $record=MARC::Record->new();
    
    foreach my $category (sort keys %{$title_ref}){
        foreach my $indicator (sort keys %{$title_ref->{$category}}){
            my $catind = "$category.$indicator";

            if (exists $convconfig->{'title'}{$catind}){
                my $ind1  = $convconfig->{'title'}{$catind}{ind1};
                my $ind2  = $convconfig->{'title'}{$catind}{ind2};
                my $field = $convconfig->{'title'}{$catind}{field};

                my $subfields_ref = {};
                my $new = 1;
                
                # Informationen aus anderen Normdaten
                if (exists $convconfig->{'title'}{$catind}{'ref'}){
                    my ($refid) = $title_ref->{$category}{$indicator}=~/IDN: (.+)$/;

                    my $ref          = $convconfig->{'title'}{$catind}{'ref'};
                    my $item_cat      = $convconfig->{'title'}{$catind}{'refcat'};
                    my $item_ind      = $convconfig->{'title'}{$catind}{'refind'};
                    my $item_ref      = $stammdateien_ref->{$ref}{data}{$refid};
                    my $subfield      = $convconfig->{'title'}{$catind}{'subfield'};
                    my $refidsubfield = $convconfig->{'title'}{$catind}{'refidsubfield'};
                    
#                    print YAML::Dump($item_ref);

                    $subfields_ref->{$subfield}      = $item_ref->{$item_cat}{$item_ind};
                    $subfields_ref->{$refidsubfield} = $refid;
                }
                # Titeldaten
                else {
                    my $subfield = $convconfig->{'title'}{$catind}{'subfield'};
                    my $type     = $convconfig->{'title'}{$catind}{'type'};                    
                    $subfields_ref->{$subfield} = $title_ref->{$category}{$indicator} if (defined $title_ref->{$category} && defined $title_ref->{$category}{$indicator});                


                    if ($type eq "n:1"){
                        my $this_field = $record->field($field);
                        
                        if ($this_field){
                            my @subfields = $this_field->subfields;

                            push @subfields, ($subfield,$subfields_ref->{$subfield});
#                            print YAML::Dump(\@subfields);

                            my $new_field = MARC::Field->new(
                                $this_field->tag,
                                $this_field->indicator(1),
                                $this_field->indicator(2),
                                @subfields
                            );
                                                    
                            $this_field->replace_with($new_field);
                        }
                        $new=0;
                    }
                    
                }
                
                if ($new){
                    $record->append_fields(MARC::Field->new($field,$ind1,$ind2,%$subfields_ref));
                }

                #                print "$field - $ind1 - $ind2 - ".YAML::Dump($subfields_ref)."\n";

            }
            elsif (exists $convconfig->{'title'}{$category}){
                print "x\n";
            }
        }
    }

    print "-----------------------------\n".$record->as_formatted."\n--------------------------\n";
    
    return;
}

close(IN);

if ($reducemem){
    untie %data_person;
    untie %data_corporatebody;
    untie %data_classification;
    untie %data_subject;
    untie %data_holding;
    untie %data_superid;
}

1;

__END__

=head1 NAME

 meta2sql.pl - Generierung von SQL-Einladedateien aus dem Meta-Format

=head1 DESCRIPTION

 Mit dem Programm meta2sql.pl werden Daten, die im MAB2-orientierten
 Meta-Format vorliegen, in Einlade-Dateien fuer das MySQL-Datenbank-
 system umgewandelt. Bei dieser Umwandlung kann durch geeignete
 Aenderung in diesem Programm lenkend eingegriffen werden.

=head1 SYNOPSIS

 In $stammdateien_ref werden die verschiedenen Normdatentypen, ihre
 zugehoerigen Namen der Ein- und Ausgabe-Dateien, sowie die zu
 invertierenden Kategorien.

 Folgende Normdatentypen existieren:

 Titel                 (title)      -> numerische Typentsprechung: 1
 Verfasser/Person      (person)      -> numerische Typentsprechung: 2
 Koerperschaft/Urheber (corporatebody)      -> numerische Typentsprechung: 3
 Schlagwort            (subject)      -> numerische Typentsprechung: 4
 Notation/Systematik   (classification) -> numerische Typentsprechung: 5
 Exemplardaten         (holding)      -> numerische Typentsprechung: 6


 Die numerische Entsprechung wird bei der Verknuepfung einzelner Saetze
 zwischen den Normdaten in der Tabelle conn verwendet.

 Der Speicherverbrauch kann ueber die Option -reduce-mem durch
 Auslagerung der fuer den Aufbau der Kurztitel-Tabelle benoetigten
 Informationen reduziert werden.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
