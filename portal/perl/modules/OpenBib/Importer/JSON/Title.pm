#####################################################################
#
#  OpenBib::Importer::JSON::Title.pm
#
#  Titel
#
#  Dieses File ist (C) 2014-2022 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Importer::JSON::Title;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Date::Calc qw/check_date/;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use JSON::XS;
use Lingua::Identify::CLD;
use Log::Log4perl qw(get_logger :levels);
use YAML ();
use Business::ISBN;
use List::MoreUtils qw{uniq};
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Container;
use OpenBib::Index::Document;
use OpenBib::Normalizer;

use base 'OpenBib::Importer::JSON';

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $storage   = exists $arg_ref->{storage}
        ? $arg_ref->{storage}        : undef;

    my $scheme    = exists $arg_ref->{scheme}
        ? $arg_ref->{scheme}         : ""; # eg. marc
    
    my $addsuperpers   = exists $arg_ref->{addsuperpers}
        ? $arg_ref->{addsuperpers}        : 0;
    my $addlanguage    = exists $arg_ref->{addlanguage}
        ? $arg_ref->{addlanguage}         : 0;
    my $addmediatype   = exists $arg_ref->{addmediatype}
        ? $arg_ref->{addmediatype}        : 0;
    my $local_enrichmnt   = exists $arg_ref->{local_enrichmnt}
        ? $arg_ref->{local_enrichmnt}     : 0;
    my $normalizer       = exists $arg_ref->{normalizer}
        ? $arg_ref->{normalizer}          : OpenBib::Normalizer->new();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->new;

    my $conv_config = OpenBib::Conv::Config->instance({dbname => $database}); 

    my $self = { };

    bless ($self, $class);

    $logger->debug("Creating Importer-Object");

    my $cld = Lingua::Identify::CLD->new();

    $self->{cld} = $cld;

    # Options
    $self->{local_enrichmnt} = $local_enrichmnt;
    $self->{addsuperpers}    = $addsuperpers;
    $self->{addlanguage}     = $addlanguage;
    $self->{addmediatype}    = $addmediatype;

    my $locationid = $config->get_locationid_of_database($database);

    $self->{locationid} = $locationid;
    
    if (defined $database){
        $self->{database} = $database;
        $logger->debug("Setting database: $database");
    }

    if (defined $conv_config){
        $self->{conv_config}       = $conv_config;
    }

    if (defined $scheme){
        $self->{scheme}           = $scheme;
    }
    
    if (defined $storage){
        $self->{storage}       = $storage;
        $logger->debug("Setting storage");
    }

    if ($normalizer){
	$self->{_normalizer} =  $normalizer;
    }
    
    # Serials
    $self->{'stats_enriched_language'} = 0;
    $self->{'title_title_serialid'} = 1;
    $self->{'title_person_serialid'} = 1;
    $self->{'title_corporatebody_serialid'} = 1;
    $self->{'title_classification_serialid'} = 1;
    $self->{'title_subject_serialid'} = 1;
    $self->{'serialid'} = 1;
    
    return $self;
}

sub process {
    my ($self,$arg_ref) = @_;

    if (defined $self->{scheme} && $self->{scheme} eq "marc"){
	return $self->process_marc($arg_ref);
    }
    else {
	return $self->process_mab($arg_ref);
    }    
}

sub enrich {
    my ($self,$arg_ref) = @_;

    if (defined $self->{scheme} && $self->{scheme} eq "marc"){
	return $self->enrich_marc($arg_ref);
    }
    else {
	return $self->enrich_mab($arg_ref);
    }    
}

sub process_mab {
    my ($self,$arg_ref) = @_;

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    my $record    = exists $arg_ref->{record}
        ? $arg_ref->{record}         : undef;


    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);
#    my $config      = OpenBib::Config->new;
#    my $storage     = OpenBib::Container->instance;
    my $database    = $self->{database};
    my $normalizer  = $self->{_normalizer};

    $logger->debug("Processing JSON: $json");

    # Cleanup
    $self->{_columns_title_title}          = [];
    $self->{_columns_title_person}         = [];
    $self->{_columns_title_corporatebody}  = [];
    $self->{_columns_title_subject}        = [];
    $self->{_columns_title_classification} = [];
    $self->{_columns_title}                = [];
    $self->{_columns_title_fields}         = [];
    
#     my %listitemdata_person         = %{$storage->get('listitemdata_person')};
#     my %listitemdata_person_date    = %{$storage->get('listitemdata_person_date')};
#     my %listitemdata_corporatebody  = %{$storage->get('listitemdata_corporatebody')};
#     my %listitemdata_classification = %{$storage->get('listitemdata_classification')};
#     my %listitemdata_subject        = %{$storage->get('listitemdata_subject')};
#     my %listitemdata_holding        = %{$storage->get('listitemdata_holding')};
#     my %listitemdata_superid        = %{$storage->get('listitemdata_superid')};
#     my %listitemdata_popularity     = %{$storage->get('listitemdata_popularity')};
#     my %listitemdata_tags           = %{$storage->get('listitemdata_tags')};
#     my %listitemdata_litlists       = %{$storage->get('listitemdata_litlists')};
#     my %listitemdata_enriched_years = %{$storage->get('listitemdata_enriched_years')};
#     my %enrichmntdata               = %{$storage->get('enrichmntdata')};
#     my %indexed_person              = %{$storage->get('indexed_person')};
#     my %indexed_corporatebody       = %{$storage->get('indexed_corporatebody')};
#     my %indexed_subject             = %{$storage->get('indexed_subject')};
#     my %indexed_classification      = %{$storage->get('indexed_classification')};
#     my %indexed_holding             = %{$storage->get('indexed_holding')};

    my $inverted_ref  = $self->{conv_config}{inverted_title};
    my $blacklist_ref = $self->{conv_config}{blacklist_title};
    
    my $record_ref;

    my $import_hash = "";

    if ($json){
        $import_hash = md5_hex($json);

        eval {
            $record_ref = decode_json $json;
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }
    }
    elsif ($record){
        eval {
            $record_ref = {
                id     => $record->get_id,
                fields => $record->get_fields,
            };
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }        
    }

    $logger->debug("JSON decoded");
    my $id            = $record_ref->{id};
    my $fields_ref    = $record_ref->{fields};

    $self->{id}       = $id;
    
    my $locations_ref; 

    if (defined $record_ref->{locations}){
	foreach my $locationid (@{$record_ref->{locations}}){
	    push @{$locations_ref}, $locationid;
	}
    }
    else {
        push @{$locations_ref}, $self->{locationid};
    }
    
    my $titlecache_ref   = {}; # Inhalte fuer den Titel-Cache
    my $searchengine_ref = {}; # Inhalte fuer die Suchmaschinen

    my $enrichmnt_isbns_ref = [];
    my $enrichmnt_issns_ref = [];

    # Initialisieren und Basisinformationen setzen
    my $index_doc = OpenBib::Index::Document->new({ database => $self->{database}, id => $id, locations => $locations_ref });

    # Locations abspeichern

    $index_doc->set_data("locations",$locations_ref);

    # Popularitaet, Tags und Literaturlisten verarbeiten fuer Index-Data
    {
        if (exists $self->{storage}{listitemdata_popularity}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{popularity}) {
                $index_doc->set_data('popularity',$self->{storage}{listitemdata_popularity}{$id});
            }
            
            $index_doc->add_index('popularity',1, $self->{storage}{listitemdata_popularity}{$id});
        }
        
        if (exists $self->{storage}{listitemdata_tags}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{tags}) {
                $index_doc->set_data('tag',$self->{storage}{listitemdata_tags}{$id});
            }
        }
        
        if (exists $self->{storage}{listitemdata_litlists}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{litlists}) {
                $index_doc->set_data('litlist',$self->{storage}{listitemdata_litlists}{$id});
            }
        }        
    }
    
    my @superids               = (); # IDs der Ueberordnungen fuer Schiller-Raeuber-Anreicherung
    
    my @person                 = ();
    my @corporatebody          = ();
    my @subject                = ();
    my @classification         = ();
    my @isbn                   = ();
    my @issn                   = ();
    my @personcorporatebody    = ();

    # Anreicherungs-IDs bestimmen

    # ISBN
    foreach my $field ('0540','0553') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

                # Alternative ISBN zur Rechercheanreicherung erzeugen
                my $isbn = Business::ISBN->new($item_ref->{content});
                
                if (defined $isbn && $isbn->is_valid) {
                    
                    # ISBN13 fuer Anreicherung merken
                    
                    push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
                        field    => "T0540",
                        content  => $isbn->as_isbn13->as_string,
                    });
                }
            }
        }
    }

    # ISSN
    foreach my $field ('0543') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                push @{$enrichmnt_issns_ref}, $normalizer->normalize({
                    field    => "T0543",
                    content  => $item_ref->{content},
                });
            }
        }
    }

    # Originalsprachliche Schrift
    foreach my $field ('0671') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                my ($newfield,$mult,$content)=$item_ref->{content}=~m/^(\d\d\d\d)(\d\d\d\d)..........(.+)$/;
                
                push @{$fields_ref->{$newfield}}, {
                    mult     => $mult,
                    subfield => '',
                    content  => $content,
                };
            }
        }
    }

    # Locations in Kategorie 4230 ablegen

    foreach my $location (@$locations_ref){
        my $mult = 1;
        push @{$fields_ref->{'4230'}}, {
            mult     => $mult++,
            subfield => '',
            content  => $location,
        };
    }
    
    my $valid_language_available=0;
    my $mult_lang = 1;

    if (defined $fields_ref->{'0015'}){

	# First cleanup multiple Languages
	my $single_lang_ref = {};
	foreach my $item_ref (@{$fields_ref->{'0015'}}){
	    if ($item_ref->{content} =~m/\;/){
		my @langs=split(';',$item_ref->{content});
		foreach my $lang (@langs){
		    $single_lang_ref->{$lang} = 1;
		}
	    }
	    else {
		  $single_lang_ref->{$item_ref->{content}} = 1;
	    }
	}

	my $new_lang_ref = [];
	foreach my $lang (keys %$single_lang_ref){
	    push @$new_lang_ref, {
		mult      => $mult_lang++,
		content   => $lang,
		subfield  => '',
	    };
	}

	$fields_ref->{'0015'} = $new_lang_ref;
	
	$mult_lang = 1;
        foreach my $item_ref (@{$fields_ref->{'0015'}}){
            my $valid_lang = $normalizer->normalize_lang($item_ref->{content});
            if (defined $valid_lang){
                $valid_language_available = 1;
                push @{$fields_ref->{'4301'}}, {
                    mult      => $mult_lang++,
                    content   => $valid_lang,
                    subfield  => 'a', # erfasst
                };

            }
        }
    }
    
    # Sprachcode erkennen und anreichern
    if ($self->{addlanguage} && !$valid_language_available) {

        my $langcode= "";

        # Sprachcode anhand 0331 usw. und Linguistischer Spracherkennung
        
        my @langtexts = ();
        if (defined $fields_ref->{'0331'}){
            foreach my $item_ref (@{$fields_ref->{'0331'}}) {
                push @langtexts, $item_ref->{content};
            }            
        }
        if (defined $fields_ref->{'0451'}){
            foreach my $item_ref (@{$fields_ref->{'0451'}}) {
                push @langtexts, $item_ref->{content};
            }            
        }
        if (defined $fields_ref->{'0335'}){
            foreach my $item_ref (@{$fields_ref->{'0335'}}) {
                push @langtexts, $item_ref->{content};
            }            
        }
        
        my $langtext = join(" ",@langtexts);
        $langtext =~s/\W/ /g;
        $langtext =~s/\s+/ /g;
        
        my @lang = $self->{cld}->identify($langtext);
        
        if ($logger->is_debug){
            $logger->debug("Sprachanreicherung fuer $langtext");
            $logger->debug("Sprachname  : $lang[0]");
            $logger->debug("Sprachid    : $lang[1]");
            $logger->debug("Sicherheit  : $lang[2]");
            $logger->debug("Zuverlaessig: $lang[3]");
        }
        
        if ($lang[3]){ # reliable!
            
            $langcode = $normalizer->normalize_lang($lang[1]);
            
        }

        if (!$langcode){
            # Sprachcode anhand der ISBN zuordnen
            if (@{$enrichmnt_isbns_ref}) {
                foreach my $isbn13 (@{$enrichmnt_isbns_ref}) {
                    if ($isbn13 =~m/^978[01]/){
                        $langcode = "eng";
                        last;
                    }
                    elsif ($isbn13 =~m/^9782/){
                        $langcode = "fre";
                        last;
                    }
                    elsif ($isbn13 =~m/^9783/){
                        $langcode = "ger";
                        last;
                    }
                    elsif ($isbn13 =~m/^9784/){
                        $langcode = "jpn";
                        last;
                    }
                    elsif ($isbn13 =~m/^9785/){
                        $langcode = "rus";
                        last;
                    }
                    elsif ($isbn13 =~m/^978605/ || $isbn13 =~m/^978975/){
                        $langcode = "tur";
                        last;
                    }
                    elsif ($isbn13 =~m/^9787/){
                        $langcode = "chi";
                        last;
                    }
                    elsif ($isbn13 =~m/^97880/){
                        $langcode = "cze";
                        last;
                    }
                    elsif ($isbn13 =~m/^97884/){
                        $langcode = "spa";
                        last;
                    }
                    elsif ($isbn13 =~m/^97888/){
                        $langcode = "ita";
                        last;
                    }
                    elsif ($isbn13 =~m/^97890/){
                        $langcode = "dut";
                        last;
                    }
                    elsif ($isbn13 =~m/^97891/){
                        $langcode = "swe";
                        last;
                    }
                }
            }
        }

        if ($langcode){
            push @{$fields_ref->{'4301'}}, {
                mult      => $mult_lang++,
                content   => $langcode,
                subfield  => 'e', # enriched
            };
            
            $self->{stats_enriched_language}++;
        }
    }
    
    # Medientypen erkennen und anreichern
    if ($self->{addmediatype}) {
        my $type_mult = 1;

        my $have_type_ref = {};

	# Schon vergebene Medientypen in 4410 merken, damit keine doppelte
	# Vergabe stattfindet
        foreach my $item_ref (@{$fields_ref->{'4410'}}) {
            $have_type_ref->{$item_ref->{content}} = 1;
            $type_mult++;
        }

        # Aufsatz
        # HSTQuelle besetzt
        if ($fields_ref->{'0590'}) {
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Aufsatz',
                subfield  => '',
            } unless (defined $have_type_ref->{'Aufsatz'});
        }   
        # Hochschulschrift
        # HSSvermerk besetzt
        elsif ($fields_ref->{'0519'}) {
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Hochschulschrift',
                subfield  => '',
            } unless (defined $have_type_ref->{'Hochschulschrift'});
        }           
        # Zeitschriften/Serien:
        # ISSN und/oder ZDB-ID besetzt
        elsif (defined $fields_ref->{'0572'} || defined $fields_ref->{'0543'}) {
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Zeitschrift/Serie',
                subfield  => '',
            } unless (defined $have_type_ref->{'Zeitschrift/Serie'});
        }   

	# Monographie:
        # Kollation 434 besetzt und enthaelt S. bzw. p.
        elsif (defined $fields_ref->{'0433'}) {
            my $is_mono   = 0;

            foreach my $item_ref (@{$fields_ref->{'0433'}}) {
                if ($item_ref->{'content'} =~m/[Sp]\./){
                    $is_mono = 1;
                }
            }
            
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Monographie',
                subfield  => '',
            } if ($is_mono && !defined $have_type_ref->{'Monographie'});
        }   


        # Elektronisches Medium mit Online-Zugriff
        # werden vorher katalogspezifisch per pre_unpack.pl angereichert
    } 

    # Jahreszahlen umwandeln
    if (defined $fields_ref->{'0425'}) {        
        my $array_ref=[];

        if (exists $self->{storage}{listitemdata_enriched_years}{$id}){
            $array_ref = $self->{storage}{listitemdata_enriched_years}{$id};
        }

        foreach my $item_ref (@{$fields_ref->{'0425'}}){
            my $date = $item_ref->{content};
            
            if ($date =~/^(-?\d+)\s*-\s*(-?\d+)/) {
                my $startyear = $1;
                my $endyear   = $2;
                
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear; $year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }
            }
            else {
                $logger->debug("Not expanding $date, just adding year");
                push @$array_ref, $date;
            }
        }
        
        $self->{storage}{listitemdata_enriched_years}{$id}=$array_ref;
    }

    # Verknuepfungskategorien bearbeiten    
    if (defined $fields_ref->{'0004'}) {
        foreach my $item_ref (@{$fields_ref->{'0004'}}) {
            my $target_titleid   = $item_ref->{content};
            my $mult             = $item_ref->{mult};
	    my $subfield         = ($item_ref->{subfield})?$item_ref->{subfield}:'';
            my $source_titleid   = $id;
            my $supplement       = "";
            my $field            = "0004";

	    # Keine Verlinkungen zu nicht existierenden Titelids
	    next if (!defined $self->{storage}{titleid_exists}{$target_titleid} || ! $self->{storage}{titleid_exists}{$target_titleid});
	    
            if (defined $inverted_ref->{$field}{$subfield}->{index}) {
                foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
                    my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};

                    $index_doc->add_index($searchfield, $weight, ["T$field",$target_titleid]);
                }
            }
            
            push @superids, $target_titleid;
            
            if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && $source_titleid && $target_titleid){
                $supplement = $self->cleanup_content($supplement);
                push @{$self->{_columns_title_title}}, [$self->{title_title_serialid},$field,$mult,$source_titleid,$target_titleid,$supplement];
                #push @{$self->{_columns_title_title}}, ['',$field,$mult,$source_titleid,$target_titleid,$supplement];
                $self->{title_title_serialid}++;
            }


            if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && %{$self->{storage}{listitemdata_superid}{$target_titleid}}){
                # my $title_super = encode_json($self->{storage}{listitemdata_superid}{$target_titleid});

                # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
                # $title_super = $self->cleanup_content($title_super);

                # Anreicherungen mit 5005 (Titelinformationen der Ueberordnung)
                push @{$fields_ref->{'5005'}}, {
                    mult      => $mult,
                    subfield  => '',
                    content   => $self->{storage}{listitemdata_superid}{$target_titleid},
                  #  content   => $title_super,
                };
            }
        }
    }
    

    # Verfasser/Personen
    foreach my $field ('0100','0101','0102','0103','1800','4308') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                my $mult       = $item_ref->{mult};
                my $personid   = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = $item_ref->{supplement};
                
                #                 # Feld 1800 wird als 0100 behandelt
                #                 if ($field eq "1800") {
                #                     $field = "0100";   
                #                 }
                
                next unless $personid;
                
                # Verknuepfungsfelder werden ignoriert
	        $item_ref->{ignore} = 1;

                if (defined $self->{storage}{listitemdata_person}{$personid}){
                    $supplement = $self->cleanup_content($supplement);
                    push @{$self->{_columns_title_person}}, [$self->{title_person_serialid},$field,$mult,$id,$personid,$supplement];
                    #push @{$self->{_columns_title_person}}, ['',$field,$mult,$id,$personid,$supplement];
                    $self->{title_person_serialid}++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $self->{storage}{listitemdata_person}{$personid}) {
                    my $mainentry = $self->{storage}{listitemdata_person}{$personid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;

                    $index_doc->add_data("P$field",{
                        id      => $personid,
                        type    => 'person',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry  unless ($field eq "4308");
                    
#                    if (exists $inverted_ref->{$field}->{index}) {
                    push @person, $personid;
#                    }
                }
                else {
                    $logger->error("PER ID $personid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Bei 1800 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
    if (defined $fields_ref->{'1800'}) {
        foreach my $item_ref (@{$fields_ref->{'1800'}}) {
            unless (defined $item_ref->{id}) {
                push @personcorporatebody, $item_ref->{content};
            }
        }
    }
    
    #Koerperschaften/Urheber
    foreach my $field ('0200','0201','1802','4307') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                my $mult            = $item_ref->{mult};
                my $corporatebodyid = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = $item_ref->{supplement};
                
                #                 # Feld 1802 wird als 0200 behandelt
                #                 if ($field eq "1802") {
                #                     $field = "0200";   
                #                 }
                
                next unless $corporatebodyid;

                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                if (defined $self->{storage}{listitemdata_corporatebody}{$corporatebodyid}){
                    $supplement = $self->cleanup_content($supplement);
                    push @{$self->{_columns_title_corporatebody}}, [$self->{title_corporatebody_serialid},$field,$mult,$id,$corporatebodyid,$supplement];
                    #push @{$self->{_columns_title_corporatebody}}, ['',$field,$mult,$id,$corporatebodyid,$supplement];
                    $self->{title_corporatebody_serialid}++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $self->{storage}{listitemdata_corporatebody}{$corporatebodyid}) {                        
                    my $mainentry = $self->{storage}{listitemdata_corporatebody}{$corporatebodyid};
                    

                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;

                    $index_doc->add_data("C$field", {
                        id      => $corporatebodyid,
                        type    => 'corporatebody',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry unless ($field eq "4307");
                    
#                    if (exists $inverted_ref->{$field}->{index}) {                    
                        push @corporatebody, $corporatebodyid;
#                    }
                }
                else {
                    $logger->error("CORPORATEBODY ID $corporatebodyid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Bei 1802 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
    if (defined $fields_ref->{'1802'}) {
        foreach my $item_ref (@{$fields_ref->{'1802'}}) {
            # Verknuepfungsfelder werden ignoriert
            $item_ref->{ignore} = 1;
            
            unless ($item_ref->{id}) {
                my $field = '1802';
                
                push @personcorporatebody, $item_ref->{content};
            }
        }
    }
    
    # Klassifikation
    foreach my $field ('0700') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;

                my $mult             = $item_ref->{mult};                
                my $classificationid = $item_ref->{id};
                my $titleid          = $id;
                my $supplement       = "";
                
                next unless $classificationid;
                
                if (defined $self->{storage}{listitemdata_classification}{$classificationid}){
                    push @{$self->{_columns_title_classification}}, [$self->{title_classification_serialid},$field,$mult,$id,$classificationid,$supplement];
                    #push @{$self->{_columns_title_classification}}, ['',$field,$mult,$id,$classificationid,$supplement];
                    $self->{title_classification_serialid}++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $self->{storage}{listitemdata_classification}{$classificationid}) {
                    my $mainentry = $self->{storage}{listitemdata_classification}{$classificationid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;
                    
                    $index_doc->add_data("N$field", {
                        id      => $classificationid,
                        type    => 'classification',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
#                    if (exists $inverted_ref->{$field}->{index}) {                    
                        push @classification, $classificationid;
#                    }        
                }
                else {
                    $logger->error("SYS ID $classificationid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Schlagworte
    foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947','4306') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                my $mult       = $item_ref->{mult};                
                my $subjectid  = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = "";
                
                next unless $subjectid;

                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                if (defined $self->{storage}{listitemdata_subject}{$subjectid}){
                    $supplement = $self->cleanup_content($supplement);
                    push @{$self->{_columns_title_subject}}, [$self->{title_subject_serialid},$field,$mult,$id,$subjectid,$supplement];
                    #push @{$self->{_columns_title_subject}}, ['',$field,$mult,$id,$subjectid,$supplement];
                    $self->{title_subject_serialid}++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $self->{storage}{listitemdata_subject}{$subjectid}) {
                    my $mainentry = $self->{storage}{listitemdata_subject}{$subjectid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;
                    
                    $index_doc->add_data("S$field", {
                        id      => $subjectid,
                        type    => 'subject',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
#                    if (exists $inverted_ref->{$field}->{index}) {                    
                        push @subject, $subjectid unless ($field eq "4306");
#                    }
                } 
                else {
                    $logger->error("SUBJECT ID $subjectid doesn't exist in TITLE ID $id");
                }
            }
        }
    }

    # Personen der Ueberordnung anreichern (Schiller-Raeuber). Wichtig: Vor der Erzeugung der Suchmaschineneintraege, da sonst nicht ueber
    # die Personen der Ueberordnung facettiert wird. Das ist wegen der Vereinheitlichung auf Endnutzerebene sinnvoll.

    if ($self->{addsuperpers}) {
        foreach my $superid (@superids) {
            if ($superid && exists $self->{storage}{listitemdata_superid}{$superid}) {
                my $super_ref = $self->{storage}{listitemdata_superid}{$superid};
                foreach my $field ('0100','0101','0102','0103','1800') {
                    if (defined $super_ref->{fields}{$field}) {
			foreach my $subfield (keys %{$inverted_ref->{$field}}){
			
			    # Anreichern fuer Facetten
			    if (defined $inverted_ref->{$field}{$subfield}->{facet}){
				foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{facet}}) {
				    foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
					$index_doc->add_facet("facet_".$searchfield, $item_ref->{content});
				    }
				}
			    }

			    # Anreichern fuer Recherche
			    foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
				push @person, $item_ref->{id};
			    }
			}
                    }
                }
            }
        }
    }

    # Anreicherungen in $self->enrich ausgelagert
    
    # Suchmaschineneintraege mit den Tags, Literaturlisten und Standard-Titelkategorien fuellen
    {
        if ($logger->is_debug){
            $logger->info("### $database: Configuration ".YAML::Dump($inverted_ref));
        }
        
        foreach my $field (keys %{$inverted_ref}){
	    foreach my $subfield (keys %{$inverted_ref->{$field}}){
		# a) Indexierung in der Suchmaschine
		if (exists $inverted_ref->{$field}{$subfield}->{index}){
		    
		    my $flag_isbn = 0;
		    # Wird dieses Feld als ISBN genutzt, dann zusaetzlicher Inhalt
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			if ($searchfield eq "isbn"){
			    $flag_isbn=1;
			}
		    }
		    
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};
			
			$logger->debug("### $database: Indexing field $field with subfield '$subfield' to searchfield $searchfield with weight $weight for id $id");
			
			if ($field eq "tag"){
			    if (exists $self->{storage}{listitemdata_tags}{$id}) {
				
				foreach my $tag_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_index($searchfield,$weight, ['tag',$tag_ref->{tag}]);
				}
				
				
				$logger->info("### $database: Adding Tags to ID $id");
			    }
			    
			}
			elsif ($field eq "litlist"){
			    if (exists $self->{storage}{listitemdata_litlists}{$id}) {
				foreach my $litlist_ref (@{$self->{storage}{listitemdata_litlists}{$id}}) {
				    if ($searchfield eq "litlistid"){
					$index_doc->add_index($searchfield,$weight, ['litlistid',$litlist_ref->{id}]);
				    }
				    else {
					$index_doc->add_index($searchfield,$weight, ['litlist',$litlist_ref->{title}]);
				    }
				}
				
				$logger->info("### $database: Adding Litlists to ID $id");
			    }
			}
			elsif ($field eq "id"){
			    $index_doc->add_index($searchfield,$weight, ['id',$id]);
			    $logger->debug("### $database: Adding searchable ID $id");
			}
			else {
			    next unless (defined $fields_ref->{$field});
			    
			    foreach my $item_ref (@{$fields_ref->{$field}}){
				# Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
				$item_ref->{subfield} = '' if (!defined $item_ref->{subfield});
				next unless (defined $item_ref->{content} && length($item_ref->{content}) > 0 && $item_ref->{subfield} eq $subfield);
				
				$index_doc->add_index($searchfield,$weight, ["T$field",$item_ref->{content}]);
				
				# Wird diese Kategorie als isbn verwendet?
				if ($flag_isbn) {
				    # Alternative ISBN zur Rechercheanreicherung erzeugen
				    my $isbn = Business::ISBN->new($item_ref->{content});
				    
				    if (defined $isbn && $isbn->is_valid) {
					my $isbnXX;
					if (!$isbn->prefix) { # ISBN10 haben kein Prefix
					    $isbnXX = $isbn->as_isbn13;
					} else {
					    $isbnXX = $isbn->as_isbn10;
					}
					
					if (defined $isbnXX) {
					    my $enriched_isbn = $isbnXX->as_string;
					    
					    $enriched_isbn = lc($enriched_isbn);
					    $enriched_isbn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
					    $enriched_isbn=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
					    
					    $index_doc->add_index($searchfield,$weight, ["T$field",$enriched_isbn]);
					}
				    }
				}
			    }
			}
		    }
		}
		
		# b) Collapse keys in der Suchmaschine
		if (defined $inverted_ref->{$field}{$subfield}->{collapse}){
		    foreach my $collapsefield (keys %{$inverted_ref->{$field}{$subfield}->{collapse}}) {
			next unless (defined $fields_ref->{$field});
			
			foreach my $item_ref (@{$fields_ref->{$field}}) {
			    # Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
			    $item_ref->{subfield} = '' if (!defined $item_ref->{subfield});
			    next unless ($item_ref->{subfield} eq $subfield);
			    $index_doc->add_collapse("collapse_$collapsefield", $item_ref->{content});        
			}
		    }
		}
		
		# c) Facetten in der Suchmaschine
		if (exists $inverted_ref->{$field}{$subfield}->{facet}){
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{facet}}) {
			if ($field eq "tag"){
			    if (exists $self->{storage}{listitemdata_tags}{$id}) {
				foreach my $tag_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_facet("facet_$searchfield", $tag_ref->{tag});
				}
			    }
			}
			elsif ($field eq "litlist"){
			    if (exists $self->{storage}{listitemdata_litlists}{$id}) {
				foreach my $litlist_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_facet("facet_$searchfield", $litlist_ref->{title});
				}
			    }
			}            
			else {
			    next unless (defined $fields_ref->{$field});
			    
			    foreach my $item_ref (@{$fields_ref->{$field}}) {
				# Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
				$item_ref->{subfield} = '' if (!defined $item_ref->{subfield});
				next unless ($item_ref->{subfield} eq $subfield);
				$index_doc->add_facet("facet_$searchfield", $item_ref->{content});        
			    }
			}
		    }
		}
            }        
	}
    }
            
    # Indexierte Informationen aus anderen Normdateien fuer Suchmaschine
    {
        # Im Falle einer Personenanreicherung durch Ueberordnungen mit
        # -add-superpers sollen Dubletten entfernt werden.
        my %seen_person=();
        foreach my $item (@person) {
            next if (exists $seen_person{$item});
            
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('personid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_person}{$item}) {
                my $thisperson = $self->{storage}{indexed_person}{$item};
                foreach my $searchfield (keys %{$thisperson}) {		    
                    foreach my $weight (keys %{$thisperson->{$searchfield}}) {                        
                        $index_doc->add_index_array($searchfield,$weight, $thisperson->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
            
            $seen_person{$item}=1;
        }
        
        foreach my $item (@corporatebody) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('corporatebodyid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_corporatebody}{$item}) {
                my $thiscorporatebody = $self->{storage}{indexed_corporatebody}{$item};
                
                foreach my $searchfield (keys %{$thiscorporatebody}) {
                    foreach my $weight (keys %{$thiscorporatebody->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thiscorporatebody->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@subject) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('subjectid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_subject}{$item}) {
                my $thissubject = $self->{storage}{indexed_subject}{$item};
                
                foreach my $searchfield (keys %{$thissubject}) {
                    foreach my $weight (keys %{$thissubject->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thissubject->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@classification) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('classificationid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_classification}{$item}) {
                my $thisclassification = $self->{storage}{indexed_classification}{$item};
                
                foreach my $searchfield (keys %{$thisclassification}) {
                    foreach my $weight (keys %{$thisclassification->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thisclassification->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
    }
    
    if (exists $self->{storage}{indexed_holding}{$id}) {
        my $thisholding = $self->{storage}{indexed_holding}{$id};
        
        foreach my $searchfield (keys %{$thisholding}) {
            foreach my $weight (keys %{$thisholding->{$searchfield}}) {
                $index_doc->add_index_array($searchfield,$weight, $thisholding->{$searchfield}{$weight}); # value is arrayref
            }
        }
    }
    
    # Automatische Anreicherung mit Bestands- oder Jahresverlaeufen
    {
        if (exists $self->{storage}{listitemdata_enriched_years}{$id}) {
            foreach my $year (@{$self->{storage}{listitemdata_enriched_years}{$id}}) {
                $logger->debug("Enriching year $year to Title-ID $id");
                $index_doc->add_index('year',1, ['T0425',$year]);
                $index_doc->add_index('freesearch',1, ['T0425',$year]);
            }
        }
    }
    
    # Index-Data mit Titelfeldern fuellen
    foreach my $field (keys %{$fields_ref}) {            
        # Kategorien in listitemcat werden fuer die Kurztitelliste verwendet
        if ($self->{conv_config}{store_full_record} || defined $self->{conv_config}{listitemcat}{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                unless (defined $item_ref->{ignore}){
                    $index_doc->add_data("T".$field, $item_ref);
                }
            }
        }
    }

    # Potentiell fehlender Titel fuer Index-Data zusammensetzen
    {
        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Es ist nichts zu tun
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        if (!defined $fields_ref->{'0331'}) {
            # UnterFall 2.1:
            if (defined $fields_ref->{'0089'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0089'}[0]{content}
				     });
            }
            # Unterfall 2.2:
            elsif (defined $fields_ref->{'0455'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0455'}[0]{content}
				     });
            }
            # Unterfall 2.3:
            elsif (defined $fields_ref->{'0451'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0451'}[0]{content}
				     });
            }
            # Unterfall 2.4:
            elsif (defined $fields_ref->{'1203'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'1203'}[0]{content}
				     });
            }
            else {
                $index_doc->add_data('T0331',{
                    content => "Keine Titelangabe vorhanden",
				     });
            }
        }
    }

    {        
        # Bestimmung der Zaehlung
        
        # Fall 1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl
        #
        # Fall 2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl
        
        # Fall 1:
        if (defined $fields_ref->{'0089'}) {
            $index_doc->set_data('T5100', [
                {
                    content => $fields_ref->{'0089'}[0]{content}
                }
            ]);
        }
        # Fall 2:
        elsif (defined $fields_ref->{'0455'}) {
            $index_doc->set_data('T5100', [
                {
                    content => $fields_ref->{'0455'}[0]{content}
                }
            ]);
        }
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen
        if (exists $self->{storage}{listitemdata_holding}{$id}){
            my $thisholdings = $self->{storage}{listitemdata_holding}{$id};
            foreach my $content (@{$thisholdings}) {
                # $content = decode_utf8($content);

                $index_doc->add_data('X0014', {
                    content => $content,
                });
            }
        }
        
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        $index_doc->add_data('PC0001', {
            content   => join(" ; ",@personcorporatebody),
        });
    }
    
    
    my $titlecache = encode_json $index_doc->get_data;
    
   # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
    $titlecache = $self->cleanup_content($titlecache);

   # $titlecache = decode_utf8($titlecache); # UTF8 anstelle Octets(durch encode_json).
    
    my $create_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
        $create_tstamp = $fields_ref->{'0002'}[0]{content};
        if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $create_tstamp=$3."-".$2."-".$1." 12:00:00";
        }
    }
    
    my $update_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0003'} && defined $fields_ref->{'0003'}[0]) {
        $update_tstamp = $fields_ref->{'0003'}[0]{content};
        if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $update_tstamp=$3."-".$2."-".$1." 12:00:00";
        }
        
    }
    
    # Primaeren Normdatensatz erstellen und schreiben
    my $popularity = (exists $self->{storage}{listitemdata_popularity}{$id})?$self->{storage}{listitemdata_popularity}{$id}:0;
    
    push @{$self->{_columns_title}}, [$id,$create_tstamp,$update_tstamp,$titlecache,$popularity,$import_hash];
    
    # Abhaengige Feldspezifische Saetze erstellen und schreiben
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $blacklist_ref->{$field});
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next if ($item_ref->{ignore});

            if (ref $item_ref->{content} eq "HASH"){
                my $content = decode_utf8(encode_json ($item_ref->{content})); # decode_utf8, um doppeltes Encoding durch encode_json und binmode(:utf8) zu vermeiden
                $item_ref->{content} = $self->cleanup_content($content);
            }

            if ($id && $field && defined $item_ref->{content}  && length($item_ref->{content}) > 0){

		# Mult, Subfield und Indikator immer defined		
		$item_ref->{mult}     = $item_ref->{mult}     || 1; 
                $item_ref->{subfield} = ($item_ref->{subfield} || $item_ref->{subfield} eq "0")?$item_ref->{subfield}:'';
                $item_ref->{ind}      = $item_ref->{ind}      || '';

		unless ($item_ref->{subfield} =~m/^.?$/ && $item_ref->{ind} =~m/^.?.?$/){
		    $logger->fatal("Subfield or indicators too long for titleid $id");
		    next;
		}
		
		$item_ref->{ind}      =~ s/\\/\\\\/g;		
		$item_ref->{subfield} =~ s/\\/\\\\/g;		
                $item_ref->{content} = $self->cleanup_content($item_ref->{content});

#                $logger->error("mult fehlt") if (!defined $item_ref->{mult});
#                $logger->error("subfield fehlt") if (!defined $item_ref->{subfield});



		push @{$self->{_columns_title_fields}}, [$self->{serialid},$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{ind},$item_ref->{content}];

                #push @{$self->{_columns_title_fields}}, ['',$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];
                $self->{serialid}++;
            }
        }
    }                
    
    # Index-Document speichern;
    
    $self->set_index_document($index_doc);

    return $self;
}

sub process_marc {
    my ($self,$arg_ref) = @_;

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    my $record    = exists $arg_ref->{record}
        ? $arg_ref->{record}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);
#    my $config      = OpenBib::Config->new;
#    my $storage     = OpenBib::Container->instance;
    my $database    = $self->{database};
    my $normalizer  = $self->{_normalizer};

    $logger->debug("Processing JSON: $json");

    # Cleanup
    $self->{_columns_title_title}          = [];
    $self->{_columns_title_person}         = [];
    $self->{_columns_title_corporatebody}  = [];
    $self->{_columns_title_subject}        = [];
    $self->{_columns_title_classification} = [];
    $self->{_columns_title}                = [];
    $self->{_columns_title_fields}         = [];
    
#     my %listitemdata_person         = %{$storage->get('listitemdata_person')};
#     my %listitemdata_person_date    = %{$storage->get('listitemdata_person_date')};
#     my %listitemdata_corporatebody  = %{$storage->get('listitemdata_corporatebody')};
#     my %listitemdata_classification = %{$storage->get('listitemdata_classification')};
#     my %listitemdata_subject        = %{$storage->get('listitemdata_subject')};
#     my %listitemdata_holding        = %{$storage->get('listitemdata_holding')};
#     my %listitemdata_superid        = %{$storage->get('listitemdata_superid')};
#     my %listitemdata_popularity     = %{$storage->get('listitemdata_popularity')};
#     my %listitemdata_tags           = %{$storage->get('listitemdata_tags')};
#     my %listitemdata_litlists       = %{$storage->get('listitemdata_litlists')};
#     my %listitemdata_enriched_years = %{$storage->get('listitemdata_enriched_years')};
#     my %enrichmntdata               = %{$storage->get('enrichmntdata')};
#     my %indexed_person              = %{$storage->get('indexed_person')};
#     my %indexed_corporatebody       = %{$storage->get('indexed_corporatebody')};
#     my %indexed_subject             = %{$storage->get('indexed_subject')};
#     my %indexed_classification      = %{$storage->get('indexed_classification')};
#     my %indexed_holding             = %{$storage->get('indexed_holding')};

    my $inverted_ref  = $self->{conv_config}{inverted_title};
    my $blacklist_ref = $self->{conv_config}{blacklist_title};
    
    my $record_ref;

    my $import_hash = "";

    if ($json){
        $import_hash = md5_hex($json);

        eval {
            $record_ref = decode_json $json;
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }
    }
    elsif ($record){
        eval {
            $record_ref = {
                id     => $record->get_id,
                fields => $record->get_fields,
            };
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }        
    }

    $logger->debug("JSON decoded");
    my $id            = $record_ref->{id};
    my $fields_ref    = $record_ref->{fields};

    $self->{id}       = $id;
    
    my $locations_ref; 

    if (defined $record_ref->{locations}){
	foreach my $locationid (@{$record_ref->{locations}}){
	    push @{$locations_ref}, $locationid;
	}
    }
    else {
        push @{$locations_ref}, $self->{locationid};
    }
    
    my $titlecache_ref   = {}; # Inhalte fuer den Titel-Cache
    my $searchengine_ref = {}; # Inhalte fuer die Suchmaschinen

    my $enrichmnt_isbns_ref = [];
    my $enrichmnt_issns_ref = [];

    # Initialisieren und Basisinformationen setzen
    my $index_doc = OpenBib::Index::Document->new({ database => $self->{database}, id => $id, locations => $locations_ref });

    # Locations abspeichern

    $index_doc->set_data("locations",$locations_ref);

    # Popularitaet, Tags und Literaturlisten verarbeiten fuer Index-Data
    {
        if (exists $self->{storage}{listitemdata_popularity}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{popularity}) {
                $index_doc->set_data('popularity',$self->{storage}{listitemdata_popularity}{$id});
            }
            
            $index_doc->add_index('popularity',1, $self->{storage}{listitemdata_popularity}{$id});
        }
        
        if (exists $self->{storage}{listitemdata_tags}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{tags}) {
                $index_doc->set_data('tag',$self->{storage}{listitemdata_tags}{$id});
            }
        }
        
        if (exists $self->{storage}{listitemdata_litlists}{$id}) {
            if (exists $self->{conv_config}{'listitemcat'}{litlists}) {
                $index_doc->set_data('litlist',$self->{storage}{listitemdata_litlists}{$id});
            }
        }        
    }
    
    my @superids               = (); # IDs der Ueberordnungen fuer Schiller-Raeuber-Anreicherung
    
    my @person                 = ();
    my @corporatebody          = ();
    my @subject                = ();
    my @classification         = ();
    my @isbn                   = ();
    my @issn                   = ();
    my @personcorporatebody    = ();

    # Anreicherungs-IDs bestimmen

    # ISBN
    foreach my $field ('0020') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

		if ($item_ref->{subfield} eq "a"){
		    # Alternative ISBN zur Rechercheanreicherung erzeugen
		    my $isbn = Business::ISBN->new($item_ref->{content});
		    
		    if (defined $isbn && $isbn->is_valid) {
			
			# ISBN13 fuer Anreicherung merken
			
			push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
			    field    => "T0540",
			    content  => $isbn->as_isbn13->as_string,
										       });
		    }
		}
            }
        }
    }

    foreach my $field ('0776') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

		if ($item_ref->{subfield} eq "z"){

		    my $this_isbn = $normalizer->normalize({
			    field    => "isbn",
			    content  =>	$item_ref->{content},
							   });
		    # Alternative ISBN zur Rechercheanreicherung erzeugen
		    my $isbn = Business::ISBN->new($this_isbn);
		    
		    if (defined $isbn && $isbn->is_valid) {
			
			# ISBN13 fuer Anreicherung merken
			
			push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
			    field    => "isbn",
			    content  => $isbn->as_isbn13->as_string,
									     });
		    }
		}
            }
        }
    }
    
    # ISSN
    foreach my $field ('0022') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
		if ($item_ref->{subfield} eq "a"){
		    push @{$enrichmnt_issns_ref}, $normalizer->normalize({
			field    => "T0543",
			content  => $item_ref->{content},
										   });
		}
            }
        }
    }

    # Analyse von Leader-Felder und Duplizierung in eigene Felder
    
    # Locations in Kategorie 4230 ablegen

    foreach my $location (@$locations_ref){
        my $mult = 1;
        push @{$fields_ref->{'4230'}}, {
            mult     => $mult++,
            subfield => 'a',
            content  => $location,
        };
    }
    
    my $valid_language_available=0;
    my $mult_lang = 1;

    if (defined $fields_ref->{'0041'}){

	# First cleanup multiple Languages
	my $single_lang_ref = {};
	foreach my $item_ref (@{$fields_ref->{'0041'}}){
	    if ($item_ref->{subfield} eq "a"){
		if ($item_ref->{content} =~m/\;/){
		    my @langs=split(';',$item_ref->{content});
		    foreach my $lang (@langs){
			$single_lang_ref->{$lang} = 1;
		    }
		}
		else {
		    $single_lang_ref->{$item_ref->{content}} = 1;
		}
	    }
	}

	my $new_lang_ref = [];
	foreach my $lang (keys %$single_lang_ref){
	    push @$new_lang_ref, {
		mult      => $mult_lang++,
		content   => $lang,
		subfield  => 'a', # erfasst
	    };
	}

	$fields_ref->{'0041'} = $new_lang_ref;
	
	$mult_lang = 1;
        foreach my $item_ref (@{$fields_ref->{'0041'}}){
            my $valid_lang = $normalizer->normalize_lang($item_ref->{content});
            if (defined $valid_lang){
                $valid_language_available = 1;
                push @{$fields_ref->{'4301'}}, {
                    mult      => $mult_lang++,
                    content   => $valid_lang,
                    subfield  => 'a', # erfasst
                };

            }
        }
    }
    
    # Sprachcode erkennen und anreichern
    if ($self->{addlanguage} && !$valid_language_available) {

        my $langcode= "";

        # Sprachcode anhand 245 usw. und Linguistischer Spracherkennung
        
        my @langtexts = ();
	# HST und Zusatz
        if (defined $fields_ref->{'0245'}){
            foreach my $item_ref (@{$fields_ref->{'0245'}}) {
                push @langtexts, $item_ref->{content} if ($item_ref->{subfield} =~m/^(a|b)$/);
	    }            
	}
	# GT
        if (defined $fields_ref->{'0490'}){
            foreach my $item_ref (@{$fields_ref->{'0490'}}) {
                push @langtexts, $item_ref->{content} if ($item_ref->{subfield} =~m/^(a|b)$/);
            }            
        }
        
        my $langtext = join(" ",@langtexts);
        $langtext =~s/\W/ /g;
        $langtext =~s/\s+/ /g;
        
        my @lang = $self->{cld}->identify($langtext);
        
        if ($logger->is_debug){
            $logger->debug("Sprachanreicherung fuer $langtext");
            $logger->debug("Sprachname  : $lang[0]");
            $logger->debug("Sprachid    : $lang[1]");
            $logger->debug("Sicherheit  : $lang[2]");
            $logger->debug("Zuverlaessig: $lang[3]");
        }
        
        if ($lang[3]){ # reliable!
            
            $langcode = $normalizer->normalize_lang($lang[1]);
            
        }

        if (!$langcode){
            # Sprachcode anhand der ISBN zuordnen
            if (@{$enrichmnt_isbns_ref}) {
                foreach my $isbn13 (@{$enrichmnt_isbns_ref}) {
                    if ($isbn13 =~m/^978[01]/){
                        $langcode = "eng";
                        last;
                    }
                    elsif ($isbn13 =~m/^9782/){
                        $langcode = "fre";
                        last;
                    }
                    elsif ($isbn13 =~m/^9783/){
                        $langcode = "ger";
                        last;
                    }
                    elsif ($isbn13 =~m/^9784/){
                        $langcode = "jpn";
                        last;
                    }
                    elsif ($isbn13 =~m/^9785/){
                        $langcode = "rus";
                        last;
                    }
                    elsif ($isbn13 =~m/^978605/ || $isbn13 =~m/^978975/){
                        $langcode = "tur";
                        last;
                    }
                    elsif ($isbn13 =~m/^9787/){
                        $langcode = "chi";
                        last;
                    }
                    elsif ($isbn13 =~m/^97880/){
                        $langcode = "cze";
                        last;
                    }
                    elsif ($isbn13 =~m/^97884/){
                        $langcode = "spa";
                        last;
                    }
                    elsif ($isbn13 =~m/^97888/){
                        $langcode = "ita";
                        last;
                    }
                    elsif ($isbn13 =~m/^97890/){
                        $langcode = "dut";
                        last;
                    }
                    elsif ($isbn13 =~m/^97891/){
                        $langcode = "swe";
                        last;
                    }
                }
            }
        }

        if ($langcode){
            push @{$fields_ref->{'4301'}}, {
                mult      => $mult_lang++,
                content   => $langcode,
                subfield  => 'e', # enriched
            };
            
            $self->{stats_enriched_language}++;
        }
    }
    
    # Medientypen erkennen und anreichern
    if ($self->{addmediatype}) {
        my $type_mult = 1;

        my $have_type_ref = {};

	# Schon vergebene Medientypen in 4410 merken, damit keine doppelte
	# Vergabe stattfindet
        foreach my $item_ref (@{$fields_ref->{'4410'}}) {
            $have_type_ref->{$item_ref->{content}} = 1;
            $type_mult++;
        }

        # Aufsatz
        # HSTQuelle besetzt
        if ($fields_ref->{'0773'}) {
	    foreach my $item_ref (@{$fields_ref->{'0773'}}) {

		if ($item_ref->{'subfield'} eq "i" && $item_ref->{'content'} =~m{Enthalten in}i){
		    unless (defined $have_type_ref->{'Aufsatz'}){
			push @{$fields_ref->{'4410'}}, {
			    mult      => $type_mult++,
			    content   => 'Aufsatz',
			    subfield  => 'e', # enriched
			};
		    }
		}
	    }
        }   
        # Hochschulschrift
        # HSSvermerk besetzt
        elsif ($fields_ref->{'0502'}) {	    
	    foreach my $item_ref (@{$fields_ref->{'0502'}}) {
		unless (defined $have_type_ref->{'Hochschulschrift'}){
		    push @{$fields_ref->{'4410'}}, {
			mult      => $type_mult++,
			content   => 'Hochschulschrift',
			subfield  => 'e', # enriched
		    } if (defined $item_ref->{subfield} =~m/^a$/);
		}
	    }
        }           
        # Zeitschriften/Serien:
        # ISSN und/oder ZDB-ID besetzt
        elsif (defined $fields_ref->{'0035'} || defined $fields_ref->{'0022'}) {
	    my $is_zsst_serie = 0;
	    
	    foreach my $item_ref (@{$fields_ref->{'0035'}}) {
		if ($item_ref->{subfield} =~m/^a$/ && $item_ref->{content} =~m/DE-600/){ # DE-600 = ZDB
		    $is_zsst_serie = 1;
		}
	    }
	    
	    foreach my $item_ref (@{$fields_ref->{'0022'}}) {
		if ($item_ref->{subfield} =~m/^a$/) {
		    $is_zsst_serie = 1;
		}
	    }
	    
	    push @{$fields_ref->{'4410'}}, {
		mult      => $type_mult++,
		content   => 'Zeitschrift/Serie',
		subfield  => 'e', # enriched
	    } if ($is_zsst_serie && !defined $have_type_ref->{'Zeitschrift/Serie'});
	    
	}
	# Monographie:
        # Kollation 300a besetzt und enthaelt S. bzw. p.
        elsif (defined $fields_ref->{'0300'}) {
            my $is_mono   = 0;

            foreach my $item_ref (@{$fields_ref->{'0300'}}) {
                if ($item_ref->{'content'} =~m/[Sp]\./ && $item_ref->{subfield} =~m/^a$/){
                    $is_mono = 1;
                }
            }
            
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Monographie',
                subfield  => 'e', # enriched
            } if ($is_mono && !defined $have_type_ref->{'Monographie'});
        }   
	
	
        # Elektronisches Medium mit Online-Zugriff
        # werden vorher katalogspezifisch per pre_unpack.pl angereichert
    }

    # Jahreszahlen umwandeln
    if (defined $fields_ref->{'0260'} || defined $fields_ref->{'0264'} || defined $fields_ref->{'1008'}) {        
        my $array_ref=[];

        if (exists $self->{storage}{listitemdata_enriched_years}{$id}){
            $array_ref = $self->{storage}{listitemdata_enriched_years}{$id};
        }

	my $current_year = (localtime)[5] + 1900;
	my $date1 = 0;
	my $date2 = 0;
	
	foreach my $item_ref (@{$fields_ref->{'1008'}}){
	    if ($item_ref->{subfield} eq "a"){
		$date1 = $item_ref->{content};
	    }
	    elsif ($item_ref->{subfield} eq "b"){
		$date2 = $item_ref->{content};
	    }
	}

	if ($date1 && $date2 && $date1 < $date2){
	    $date2 = $current_year if ($date2 eq "9999" || $date2 eq "uuuu");

	    $logger->debug("Expanding year in 008/1008 from $date1 to $date2");
	    for (my $year=$date1;$year<=$date2; $year++) {
		$logger->debug("Adding year $year");
		push @$array_ref, $year;
	    }
	}
	else {
	    foreach my $field ('0260','0264'){
		foreach my $item_ref (@{$fields_ref->{$field}}){
		    if ($item_ref->{subfield} eq "c"){
			my $date = $item_ref->{content};
			
			if ($date =~/^(-?\d+)\s*-\s*(-?\d+)/) {
			    my $startyear = $1;
			    my $endyear   = $2;
			    
			    $logger->debug("Expanding yearstring $date in 26x from $startyear to $endyear");
			    for (my $year=$startyear;$year<=$endyear; $year++) {
				$logger->debug("Adding year $year");
				push @$array_ref, $year;
			    }
			}
			else {
			    $logger->debug("Not expanding $date, just adding year");
			    push @$array_ref, $date;
			}
		    }
		}
	    }
        }
        $self->{storage}{listitemdata_enriched_years}{$id}=$array_ref;
    }

    # Verknuepfungskategorien zwischen Titeln bearbeiten    
    if (defined $fields_ref->{'0830'}) {
        foreach my $item_ref (@{$fields_ref->{'0830'}}) {
	    if ($item_ref->{subfield} eq "w"){
		my $target_titleid   = $item_ref->{content};
		my $mult             = $item_ref->{mult};
		my $subfield         = ($item_ref->{subfield})?$item_ref->{subfield}:'';
		my $source_titleid   = $id;
		my $supplement       = "";
		my $field            = "0830";
		
		# Keine Verlinkungen zu nicht existierenden Titelids
		next if (!defined $self->{storage}{titleid_exists}{$target_titleid} || ! $self->{storage}{titleid_exists}{$target_titleid});
		
		if (defined $inverted_ref->{$field}{$subfield}->{index}) {
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};
			
			$index_doc->add_index($searchfield, $weight, ["T$field",$target_titleid]);
		    }
		}
		
		push @superids, $target_titleid;
		
		if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && $source_titleid && $target_titleid){
		    $supplement = $self->cleanup_content($supplement);
		    push @{$self->{_columns_title_title}}, [$self->{title_title_serialid},$field,$mult,$source_titleid,$target_titleid,$supplement];
		    #push @{$self->{_columns_title_title}}, ['',$field,$mult,$source_titleid,$target_titleid,$supplement];
		    $self->{title_title_serialid}++;
		}
		
		
		if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && %{$self->{storage}{listitemdata_superid}{$target_titleid}}){
		    # my $title_super = encode_json($self->{storage}{listitemdata_superid}{$target_titleid});
		    
		    # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
		    # $title_super = $self->cleanup_content($title_super);
		    
		    # Anreicherungen mit 5005 (Titelinformationen der Ueberordnung)
		    push @{$fields_ref->{'5005'}}, {
			mult      => $mult,
			subfield  => 'e',
			content   => $self->{storage}{listitemdata_superid}{$target_titleid},
			#  content   => $title_super,
		    };
		}
	    }
        }
    }

    # Bandverlinkungen durch 0773$w    
    if (defined $fields_ref->{'0773'}){
	my $exclude_mult_ref = {}; # Ignoriere Verlinkungen von Bindeeinheiten
	foreach my $item_ref (@{$fields_ref->{'0773'}}){
	    if ($item_ref->{subfield} eq "p" && $item_ref->{content} eq "AngebundenAn"){ 
		$exclude_mult_ref->{$item_ref->{mult}} = 1;
	    }
	}

	foreach my $item_ref (@{$fields_ref->{'0773'}}){
	    if ($item_ref->{subfield} eq "w"){
		my $target_titleid   = $item_ref->{content};
		my $mult             = $item_ref->{mult};
		my $subfield         = ($item_ref->{subfield})?$item_ref->{subfield}:'';
		my $source_titleid   = $id;
		my $supplement       = "";
		my $field            = "0773";

		next if (defined $exclude_mult_ref->{$mult} && $exclude_mult_ref->{$mult});
		
		# Keine Verlinkungen zu nicht existierenden Titelids
		next if (!defined $self->{storage}{titleid_exists}{$target_titleid} || ! $self->{storage}{titleid_exists}{$target_titleid});
		
		if (defined $inverted_ref->{$field}{$subfield}->{index}) {
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};
			
			$index_doc->add_index($searchfield, $weight, ["T$field",$target_titleid]);
		    }
		}
		
		push @superids, $target_titleid;
		
		if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && $source_titleid && $target_titleid){
		    $supplement = $self->cleanup_content($supplement);
		    push @{$self->{_columns_title_title}}, [$self->{title_title_serialid},$field,$mult,$source_titleid,$target_titleid,$supplement];
		    #push @{$self->{_columns_title_title}}, ['',$field,$mult,$source_titleid,$target_titleid,$supplement];
		    $self->{title_title_serialid}++;
		}
		
		
		if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && %{$self->{storage}{listitemdata_superid}{$target_titleid}}){
		    # my $title_super = encode_json($self->{storage}{listitemdata_superid}{$target_titleid});
		    
		    # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
		    # $title_super = $self->cleanup_content($title_super);
		    
		    # Anreicherungen mit 5005 (Titelinformationen der Ueberordnung)
		    push @{$fields_ref->{'5005'}}, {
			mult      => $mult,
			subfield  => 'e',
			content   => $self->{storage}{listitemdata_superid}{$target_titleid},
			#  content   => $title_super,
		    };
		}
	    }
	    
	}
    }
    
    # Verfasser/Personen Normdaten verknuepfen
    foreach my $field ('0100','0700') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
	        #$item_ref->{ignore} = 1;

		if ($item_ref->{subfield} eq "a"){ # Ansetzung
		    push @personcorporatebody, $item_ref->{content};
		}
		
		if ($item_ref->{subfield} eq "6"){ # Linkage
		    my $mult       = $item_ref->{mult};
		    my $personid   = $item_ref->{content};
		    my $titleid    = $id;
		    my $supplement = $item_ref->{supplement};
		    
		    # Eine m:n Verknuepfung zum Personen-Normdatensatz wird nur vorgenommen, wenn
		    # der Normdatensatz mit der ID existiert.
		    if ($personid && defined $self->{storage}{listitemdata_person}{$personid}){
			$supplement = $self->cleanup_content($supplement);
			push @{$self->{_columns_title_person}}, [$self->{title_person_serialid},$field,$mult,$id,$personid,$supplement];
			#push @{$self->{_columns_title_person}}, ['',$field,$mult,$id,$personid,$supplement];
			$self->{title_person_serialid}++;
		    }

		    push @person, $personid;		    
		}
		
		# if ($item_ref->{subfield} eq "a"){ # Main Entry
		#     if ($item_ref->{content}) {
		# 	# Um Ansetzungsform erweitern
		# 	my $mainentry = $item_ref->{content} ;
			
		# 	$index_doc->add_data("P$field",{
		# 	    id      => $personid,
		# 	    type    => 'person',
		# 	    content => $mainentry,
		# 	    supplement => $supplement,
		# 			     }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
			
		# 	push @personcorporatebody, $mainentry  unless ($field eq "4308");
			
		# 	#                    if (exists $inverted_ref->{$field}->{index}) {

		# 	#                    }
		#     }
		#     else {
		# 	$logger->error("PER ID $personid doesn't exist in TITLE ID $id");
		#     }
		# }
            }
        }
    }
        
    # Koerperschaften/Urheber Normdaten Verknuepfen
    foreach my $field ('0110','0111','0710') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                #$item_ref->{ignore} = 1;

		if ($item_ref->{subfield} eq "a"){ # Ansetzung
		    push @personcorporatebody, $item_ref->{content};
		}
		
		if ($item_ref->{subfield} eq "6"){ # Linkage		
		    my $mult            = $item_ref->{mult};
		    my $corporatebodyid = $item_ref->{content};
		    my $titleid    = $id;
		    my $supplement = "";
		    
		    #                 # Feld 1802 wird als 0200 behandelt
		    #                 if ($field eq "1802") {
		    #                     $field = "0200";   
		    #                 }
		    
		    if ($corporatebodyid && defined $self->{storage}{listitemdata_corporatebody}{$corporatebodyid}){
			$supplement = $self->cleanup_content($supplement);
			push @{$self->{_columns_title_corporatebody}}, [$self->{title_corporatebody_serialid},$field,$mult,$id,$corporatebodyid,$supplement];
			#push @{$self->{_columns_title_corporatebody}}, ['',$field,$mult,$id,$corporatebodyid,$supplement];
			$self->{title_corporatebody_serialid}++;
		    }
                }
		
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
#                 if (exists $self->{storage}{listitemdata_corporatebody}{$corporatebodyid}) {                        
#                     my $mainentry = $self->{storage}{listitemdata_corporatebody}{$corporatebodyid};
                    

#                     # Um Ansetzungsform erweitern
#                     $item_ref->{content} = $mainentry;

#                     $index_doc->add_data("C$field", {
#                         id      => $corporatebodyid,
#                         type    => 'corporatebody',
#                         content => $mainentry,
#                         supplement => $supplement,
#                     }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
#                     push @personcorporatebody, $mainentry unless ($field eq "4307");
                    
# #                    if (exists $inverted_ref->{$field}->{index}) {                    
#                         push @corporatebody, $corporatebodyid;
# #                    }
#                 }
#                 else {
#                     $logger->error("CORPORATEBODY ID $corporatebodyid doesn't exist in TITLE ID $id");
#                 }
            }
        }
    }
        
    # Klassifikation
    foreach my $field ('0082','0084') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                #$item_ref->{ignore} = 1;

		if ($item_ref->{subfield} eq "6"){ # Linkage		
		    my $mult             = $item_ref->{mult};                
		    my $classificationid = $item_ref->{content};
		    my $titleid          = $id;
		    my $supplement       = "";
		    
		    next unless $classificationid;
		    
		    if (defined $self->{storage}{listitemdata_classification}{$classificationid}){
			push @{$self->{_columns_title_classification}}, [$self->{title_classification_serialid},$field,$mult,$id,$classificationid,$supplement];
			#push @{$self->{_columns_title_classification}}, ['',$field,$mult,$id,$classificationid,$supplement];
			$self->{title_classification_serialid}++;
		    }
                }
		
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
#                 if (exists $self->{storage}{listitemdata_classification}{$classificationid}) {
#                     my $mainentry = $self->{storage}{listitemdata_classification}{$classificationid};
                    
#                     # Um Ansetzungsform erweitern
#                     $item_ref->{content} = $mainentry;
                    
#                     $index_doc->add_data("N$field", {
#                         id      => $classificationid,
#                         type    => 'classification',
#                         content => $mainentry,
#                         supplement => $supplement,
#                     }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
# #                    if (exists $inverted_ref->{$field}->{index}) {                    
#                         push @classification, $classificationid;
# #                    }        
#                 }
#                 else {
#                     $logger->error("SYS ID $classificationid doesn't exist in TITLE ID $id");
#                 }
            }
        }
    }
    
    # Schlagworte
    foreach my $field ('0600','0610','0648','0650','0651','0655','0688','0689') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                #$item_ref->{ignore} = 1;

		if ($item_ref->{subfield} eq "6"){ # Linkage		
		    my $mult       = $item_ref->{mult};                
		    my $subjectid  = $item_ref->{content};
		    my $titleid    = $id;
		    my $supplement = "";
		    
		    next unless $subjectid;
                
		    if (defined $self->{storage}{listitemdata_subject}{$subjectid}){
			$supplement = $self->cleanup_content($supplement);
			push @{$self->{_columns_title_subject}}, [$self->{title_subject_serialid},$field,$mult,$id,$subjectid,$supplement];
			#push @{$self->{_columns_title_subject}}, ['',$field,$mult,$id,$subjectid,$supplement];
			$self->{title_subject_serialid}++;
		    }
                }
		
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
#                 if (exists $self->{storage}{listitemdata_subject}{$subjectid}) {
#                     my $mainentry = $self->{storage}{listitemdata_subject}{$subjectid};
                    
#                     # Um Ansetzungsform erweitern
#                     $item_ref->{content} = $mainentry;
                    
#                     $index_doc->add_data("S$field", {
#                         id      => $subjectid,
#                         type    => 'subject',
#                         content => $mainentry,
#                         supplement => $supplement,
#                     }) if ($self->{conv_config}{store_full_record} || exists $self->{conv_config}{listitemcat}{$field});
                    
# #                    if (exists $inverted_ref->{$field}->{index}) {                    
#                         push @subject, $subjectid unless ($field eq "4306");
# #                    }
#                 } 
#                 else {
#                     $logger->error("SUBJECT ID $subjectid doesn't exist in TITLE ID $id");
#                 }
            }
        }
    }

    # Personen der Ueberordnung anreichern (Schiller-Raeuber). Wichtig: Vor der Erzeugung der Suchmaschineneintraege, da sonst nicht ueber
    # die Personen der Ueberordnung facettiert wird. Das ist wegen der Vereinheitlichung auf Endnutzerebene sinnvoll.

    if ($self->{addsuperpers}) {
        foreach my $superid (@superids) {
            if ($superid && exists $self->{storage}{listitemdata_superid}{$superid}) {
                my $super_ref = $self->{storage}{listitemdata_superid}{$superid};
                foreach my $field ('0100','0700') {
                    if (defined $super_ref->{fields}{$field}) {
			foreach my $subfield (keys %{$inverted_ref->{$field}}){
			
			    # Anreichern fuer Facetten
			    if (defined $inverted_ref->{$field}{$subfield}->{facet}){
				foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{facet}}) {
				    foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
					$index_doc->add_facet("facet_".$searchfield, $item_ref->{content}) if ($item_ref->{subfield} eq $subfield);
				    }
				}
			    }

			    # Anreichern fuer Recherche
			    foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
				push @person, $item_ref->{content} if ($item_ref->{subfield} eq "6"); # Linkage
			    }
			}
                    }
                }
            }
        }
    }

    # Anreicherungen in $self->enrich ausgelagert
        
    # Suchmaschineneintraege mit den Tags, Literaturlisten und Standard-Titelkategorien fuellen
    {
        if ($logger->is_debug){
            $logger->info("### $database: Configuration ".YAML::Dump($inverted_ref));
        }
        
        foreach my $field (keys %{$inverted_ref}){
	    foreach my $subfield (keys %{$inverted_ref->{$field}}){
		# a) Indexierung in der Suchmaschine
		if (exists $inverted_ref->{$field}{$subfield}->{index}){
		    
		    my $flag_isbn = 0;
		    # Wird dieses Feld als ISBN genutzt, dann zusaetzlicher Inhalt
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			if ($searchfield eq "isbn"){
			    $flag_isbn=1;
			}
		    }
		    
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
			my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};
			
			$logger->debug("### $database: Indexing field $field with subfield '$subfield' to searchfield $searchfield with weight $weight for id $id");
			
			if ($field eq "tag"){
			    if (exists $self->{storage}{listitemdata_tags}{$id}) {
				
				foreach my $tag_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_index($searchfield,$weight, ['tag',$tag_ref->{tag}]);
				}
				
				
				$logger->info("### $database: Adding Tags to ID $id");
			    }
			    
			}
			elsif ($field eq "litlist"){
			    if (exists $self->{storage}{listitemdata_litlists}{$id}) {
				foreach my $litlist_ref (@{$self->{storage}{listitemdata_litlists}{$id}}) {
				    if ($searchfield eq "litlistid"){
					$index_doc->add_index($searchfield,$weight, ['litlistid',$litlist_ref->{id}]);
				    }
				    else {
					$index_doc->add_index($searchfield,$weight, ['litlist',$litlist_ref->{title}]);
				    }
				}
				
				$logger->info("### $database: Adding Litlists to ID $id");
			    }
			}
			elsif ($field eq "id"){
			    $index_doc->add_index($searchfield,$weight, ['id',$id]);
			    $logger->debug("### $database: Adding searchable ID $id");
			}
			else {
			    next unless (defined $fields_ref->{$field});
			    
			    foreach my $item_ref (@{$fields_ref->{$field}}){
				# Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
				$item_ref->{subfield} = ' ' if (!defined $item_ref->{subfield});
				next unless (defined $item_ref->{content} && length($item_ref->{content}) > 0 && $item_ref->{subfield} eq $subfield);
				
				$index_doc->add_index($searchfield,$weight, ["T$field",$item_ref->{content}]);
				
				# Wird diese Kategorie als isbn verwendet?
				if ($flag_isbn) {
				    # Alternative ISBN zur Rechercheanreicherung erzeugen
				    my $isbn = Business::ISBN->new($item_ref->{content});
				    
				    if (defined $isbn && $isbn->is_valid) {
					my $isbnXX;
					if (!$isbn->prefix) { # ISBN10 haben kein Prefix
					    $isbnXX = $isbn->as_isbn13;
					} else {
					    $isbnXX = $isbn->as_isbn10;
					}
					
					if (defined $isbnXX) {
					    my $enriched_isbn = $isbnXX->as_string;
					    
					    $enriched_isbn = lc($enriched_isbn);
					    $enriched_isbn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
					    $enriched_isbn=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
					    
					    $index_doc->add_index($searchfield,$weight, ["T$field",$enriched_isbn]);
					}
				    }
				}
			    }
			}
		    }
		}
		
		# b) Collapse keys in der Suchmaschine
		if (defined $inverted_ref->{$field}{$subfield}->{collapse}){
		    foreach my $collapsefield (keys %{$inverted_ref->{$field}{$subfield}->{collapse}}) {
			next unless (defined $fields_ref->{$field});
			
			foreach my $item_ref (@{$fields_ref->{$field}}) {
			    # Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
			    $item_ref->{subfield} = ' ' if (!defined $item_ref->{subfield});
			    next unless ($item_ref->{subfield} eq $subfield);
			    $index_doc->add_collapse("collapse_$collapsefield", $item_ref->{content});        
			}
		    }
		}
		
		# c) Facetten in der Suchmaschine
		if (exists $inverted_ref->{$field}{$subfield}->{facet}){
		    foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{facet}}) {
			if ($field eq "tag"){
			    if (exists $self->{storage}{listitemdata_tags}{$id}) {
				foreach my $tag_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_facet("facet_$searchfield", $tag_ref->{tag});
				}
			    }
			}
			elsif ($field eq "litlist"){
			    if (exists $self->{storage}{listitemdata_litlists}{$id}) {
				foreach my $litlist_ref (@{$self->{storage}{listitemdata_tags}{$id}}) {
				    $index_doc->add_facet("facet_$searchfield", $litlist_ref->{title});
				}
			    }
			}            
			else {
			    next unless (defined $fields_ref->{$field});
			    
			    foreach my $item_ref (@{$fields_ref->{$field}}) {
				# Potentiell fehlende subfield-Information mit Default-Wert ergaenzen
				$item_ref->{subfield} = ' ' if (!defined $item_ref->{subfield});
				next unless ($item_ref->{subfield} eq $subfield);
				$index_doc->add_facet("facet_$searchfield", $item_ref->{content});        
			    }
			}
		    }
		}
            }        
	}
    }
            
    # Indexierte Informationen aus anderen Normdateien fuer Suchmaschine
    {
        # Im Falle einer Personenanreicherung durch Ueberordnungen mit
        # -add-superpers sollen Dubletten entfernt werden.
        my %seen_person=();
        foreach my $item (@person) {
            next if (exists $seen_person{$item});
            
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('personid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_person}{$item}) {
                my $thisperson = $self->{storage}{indexed_person}{$item};
                foreach my $searchfield (keys %{$thisperson}) {		    
                    foreach my $weight (keys %{$thisperson->{$searchfield}}) {                        
                        $index_doc->add_index_array($searchfield,$weight, $thisperson->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
            
            $seen_person{$item}=1;
        }
        
        foreach my $item (@corporatebody) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('corporatebodyid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_corporatebody}{$item}) {
                my $thiscorporatebody = $self->{storage}{indexed_corporatebody}{$item};
                
                foreach my $searchfield (keys %{$thiscorporatebody}) {
                    foreach my $weight (keys %{$thiscorporatebody->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thiscorporatebody->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@subject) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('subjectid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_subject}{$item}) {
                my $thissubject = $self->{storage}{indexed_subject}{$item};
                
                foreach my $searchfield (keys %{$thissubject}) {
                    foreach my $weight (keys %{$thissubject->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thissubject->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@classification) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('classificationid',1, ['id',$item]);
            
            if (exists $self->{storage}{indexed_classification}{$item}) {
                my $thisclassification = $self->{storage}{indexed_classification}{$item};
                
                foreach my $searchfield (keys %{$thisclassification}) {
                    foreach my $weight (keys %{$thisclassification->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thisclassification->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
    }
    
    if (exists $self->{storage}{indexed_holding}{$id}) {
        my $thisholding = $self->{storage}{indexed_holding}{$id};
        
        foreach my $searchfield (keys %{$thisholding}) {
            foreach my $weight (keys %{$thisholding->{$searchfield}}) {
                $index_doc->add_index_array($searchfield,$weight, $thisholding->{$searchfield}{$weight}); # value is arrayref
            }
        }
    }
    
    # Automatische Anreicherung mit Bestands- oder Jahresverlaeufen
    {
        if (exists $self->{storage}{listitemdata_enriched_years}{$id}) {
            foreach my $year (@{$self->{storage}{listitemdata_enriched_years}{$id}}) {
                $logger->debug("Enriching year $year to Title-ID $id");
                $index_doc->add_index('year',1, ['T260c',$year]);
                $index_doc->add_index('freesearch',1, ['T260c',$year]);
            }
        }
    }
    
    # Index-Data immer mit ALLEN Titelfeldern fuellen
    foreach my $field (keys %{$fields_ref}) {            
        # Kategorien in listitemcat werden fuer die Kurztitelliste verwendet
        if ($self->{conv_config}{store_full_record} || defined $self->{conv_config}{listitemcat}{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
#                unless (defined $item_ref->{ignore}){
		$index_doc->add_data("T".$field, $item_ref);
#                }
            }
        }
    }

    # Potentiell fehlender Titel fuer Index-Data zusammensetzen
#    {
        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Es ist nichts zu tun
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        # if (!defined $fields_ref->{'0331'}) {
        #     # UnterFall 2.1:
        #     if (defined $fields_ref->{'0089'}) {
        #         $index_doc->add_data('T0331',{
        #             content => $fields_ref->{'0089'}[0]{content}
	# 			     });
        #     }
        #     # Unterfall 2.2:
        #     elsif (defined $fields_ref->{'0455'}) {
        #         $index_doc->add_data('T0331',{
        #             content => $fields_ref->{'0455'}[0]{content}
	# 			     });
        #     }
        #     # Unterfall 2.3:
        #     elsif (defined $fields_ref->{'0451'}) {
        #         $index_doc->add_data('T0331',{
        #             content => $fields_ref->{'0451'}[0]{content}
	# 			     });
        #     }
        #     # Unterfall 2.4:
        #     elsif (defined $fields_ref->{'1203'}) {
        #         $index_doc->add_data('T0331',{
        #             content => $fields_ref->{'1203'}[0]{content}
	# 			     });
        #     }
        #     else {
        #         $index_doc->add_data('T0331',{
        #             content => "Keine Titelangabe vorhanden",
	# 			     });
        #     }
        # }
#    }

    {        
        # Bestimmung der Zaehlung
        
        # Fall 1: Es existiert eine (erste) Bandbenennung-/zaehlung(245n)
        #
        # Dann: Setze diese Bandbenennung
        #
        # Fall 2: Es existiert keine Bandbenennung(245n), aber eine (erste)
        #                Bandangabe in Sortierform (773q)
        #
        # Dann: Setze diese Bandangabe
        
        # Fall 1:
        if (defined $fields_ref->{'0245'}) {
	    foreach my $item_ref (@{$fields_ref->{'0245'}}){
		if ($item_ref->{subfield} eq "n"){
		    $index_doc->set_data('T5100', [
					     {
						 subfield => 'a',
						 mult => 1,
						 content => $item_ref->{content}
					     }
					 ]);
		}
	    }
        }
        # Fall 2:
        elsif (defined $fields_ref->{'0773'}) {
	    foreach my $item_ref (@{$fields_ref->{'0773'}}){
		if ($item_ref->{subfield} eq "q"){
		    $index_doc->set_data('T5100', [
					     {
						 subfield => 'a',
						 mult => 1,
						 content => $item_ref->{content}
					     }
					 ]);
		}
	    }
        }
	
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen
        if (exists $self->{storage}{listitemdata_holding}{$id}){
            my $thisholdings = $self->{storage}{listitemdata_holding}{$id};
	    my $mult0014 = 1;
            foreach my $content (@{$thisholdings}) {
                # $content = decode_utf8($content);

                $index_doc->add_data('X0014', {
		    subfield  => 'a',
		    mult      => $mult0014++,
                    content => $content,
                });
            }
        }

	if ($logger->is_debug){
	    $logger->debug("PC0001: ".YAML::Dump(\@personcorporatebody));
	}
	
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        $index_doc->add_data('PC0001', {
	    subfield  => 'a',
	    mult      => 1,
            content   => join(" ; ",@personcorporatebody),
        });
    }
    
    
    my $titlecache = encode_json $index_doc->get_data;
    
   # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
    $titlecache = $self->cleanup_content($titlecache);

   # $titlecache = decode_utf8($titlecache); # UTF8 anstelle Octets(durch encode_json).
    
    my $create_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0008'} && defined $fields_ref->{'0008'}[0]) {
	my $date      = substr($fields_ref->{'0008'}[0]{content},0,6);
	
	my ($year,$month,$day) = $date =~m/^(\d\d)(\d\d)(\d\d)$/;
	if ($day && $month && $year){
	    $year = ($year < 70)?$year + 2000:$year + 1900;
	    $month  = "01"   if ($month < 1 || $month > 12);
	    $day    = "01"   if ($day < 1 || $day > 32);
	    
	    $create_tstamp = "$year-$month-$day 12:00:00" if (check_date($year,$month,$day));
	}
    }

    my $update_tstamp = "1970-01-01 12:00:00"; 
    
    if (defined $fields_ref->{'0005'} && defined $fields_ref->{'0005'}[0]) {
	my $date = $fields_ref->{'0005'}[0]{content};
	my ($year,$month,$day,$hour,$minute,$second) = $date =~m/^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;

	if ($year && $month && $day && $hour && $minute && $second){
	    # Abfangen von Datenfehlern
	    $hour   = "12"   if ($hour > 23);
	    $minute = "00"   if ($minute > 59);
	    $second = "00"   if ($second > 59);
	    
	    $year   = "1970" if ($year < 1970);
	    $month  = "01"   if ($month < 1 || $month > 12);
	    $day    = "01"   if ($day < 1 || $day > 32);
	    
	    $update_tstamp = "$year-$month-$day $hour:$minute:$second" if (check_date($year,$month,$day));
	}
    }
    
    # Primaeren Normdatensatz erstellen und schreiben
    my $popularity = (exists $self->{storage}{listitemdata_popularity}{$id})?$self->{storage}{listitemdata_popularity}{$id}:0;
    
    push @{$self->{_columns_title}}, [$id,$create_tstamp,$update_tstamp,$titlecache,$popularity,$import_hash];
    
    # Abhaengige Feldspezifische Saetze erstellen und schreiben
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $blacklist_ref->{$field});
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next if ($item_ref->{ignore});

            if (ref $item_ref->{content} eq "HASH"){
                my $content = decode_utf8(encode_json ($item_ref->{content})); # decode_utf8, um doppeltes Encoding durch encode_json und binmode(:utf8) zu vermeiden
                $item_ref->{content} = $self->cleanup_content($content);
            }

            if ($id && $field && defined $item_ref->{content}  && length($item_ref->{content}) > 0){

		# Mult, Subfield und Indikator immer defined		
		$item_ref->{mult}     = $item_ref->{mult}     || 1; 
                $item_ref->{subfield} = ($item_ref->{subfield} || $item_ref->{subfield} eq "0")?$item_ref->{subfield}:'';
                $item_ref->{ind}      = $item_ref->{ind}      || '';

		unless ($item_ref->{subfield} =~m/^.?$/ && $item_ref->{ind} =~m/^.?.?$/){
		    $logger->fatal("Subfield or indicators too long for titleid $id");
		    next;
		}
		
		$item_ref->{ind}      =~ s/\\/\\\\/g;
		$item_ref->{subfield} =~ s/\\/\\\\/g;		
                $item_ref->{content}  = $self->cleanup_content($item_ref->{content});

#                $logger->error("mult fehlt") if (!defined $item_ref->{mult});
		#                $logger->error("subfield fehlt") if (!defined $item_ref->{subfield});

		
                push @{$self->{_columns_title_fields}}, [$self->{serialid},$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{ind},$item_ref->{content}] if ($item_ref->{content});
                #push @{$self->{_columns_title_fields}}, ['',$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];
                $self->{serialid}++;
            }
        }
    }                
    
    # Index-Document speichern;
    
    $self->set_index_document($index_doc);

    return $self;
}

sub enrich_mab {
    my ($self,$arg_ref) = @_;

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);
    my $database    = $self->{database};
    my $normalizer  = $self->{_normalizer};

    $logger->debug("Processing JSON: $json");

    my $record_ref = {};
    
    eval {
	$record_ref = decode_json $json;
    };
    
    if ($@){
	$logger->error("Skipping record: $@");
	return;
    }

    $logger->debug("JSON decoded");
    
    my $id            = $record_ref->{id};
    my $fields_ref    = $record_ref->{fields};
    
    my $enrichmnt_isbns_ref = [];
    my $enrichmnt_issns_ref = [];

    my @isbn                   = ();
    my @issn                   = ();

    # Anreicherungs-IDs bestimmen

    # ISBN
    foreach my $field ('0540','0553') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

                # Alternative ISBN zur Rechercheanreicherung erzeugen
                my $isbn = Business::ISBN->new($item_ref->{content});
                
                if (defined $isbn && $isbn->is_valid) {
                    
                    # ISBN13 fuer Anreicherung merken
                    
                    push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
                        field    => "T0540",
                        content  => $isbn->as_isbn13->as_string,
                    });
                }
            }
        }
    }

    # ISSN
    foreach my $field ('0543') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                push @{$enrichmnt_issns_ref}, $normalizer->normalize({
                    field    => "T0543",
                    content  => $item_ref->{content},
                });
            }
        }
    }

    # Bibkey-Kategorie 5050 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel

    my $bibkey = "";

    if ((defined $fields_ref->{'0100'} || defined $fields_ref->{'0101'}) && defined $fields_ref->{'0331'} && (defined $fields_ref->{'0424'} || defined $fields_ref->{'0425'})){

        my $bibkey_record_ref = {
            'T0100' => $fields_ref->{'0100'},
            'T0101' => $fields_ref->{'0101'},
            'T0331' => $fields_ref->{'0331'},
            'T0425' => $fields_ref->{'0425'},
        };

        if ($fields_ref->{'0424'} && !$fields_ref->{'0425'}){
            $bibkey_record_ref->{'T0425'} = $fields_ref->{'0424'};
        }

        my $bibkey_base = $normalizer->gen_bibkey_base({ fields => $bibkey_record_ref});

        $bibkey      = ($bibkey_base)?$normalizer->gen_bibkey({ bibkey_base => $bibkey_base }):"";
        
        if ($bibkey) {
            push @{$fields_ref->{'5050'}}, {
                mult      => 1,
                content   => $bibkey,
                subfield  => '',
            };
                
            push @{$fields_ref->{'5051'}}, {
                mult      => 1,
                content   => $bibkey_base,
                subfield   => '',
            };
        }
    }

    # Workkey-Kategorie 5055 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel
    if ((defined $fields_ref->{'0100'} || defined $fields_ref->{'0101'}) && defined $fields_ref->{'0331'} && (defined $fields_ref->{'0424'} || defined $fields_ref->{'0425'}) && defined $fields_ref->{'0412'}){
        # Erscheinungsjahr muss existieren, damit nur 'ordentliche' Titel untersucht werden
        
        my $workkey_record_ref = {
            'T0100' => $fields_ref->{'0100'}, # Verfasser
            'T0101' => $fields_ref->{'0101'}, # Person
            'T0331' => $fields_ref->{'0331'}, # HST
            'T0412' => $fields_ref->{'0412'}, # Verlag
            'T0424' => $fields_ref->{'0424'}, # Jahr
            'T0425' => $fields_ref->{'0425'}, # Jahr
            'T0304' => $fields_ref->{'0304'}, # EST
            'T0403' => $fields_ref->{'0403'}, # Auflage als Suffix
            'T4301' => $fields_ref->{'4301'}, # Angereicherte Sprache
            'T4400' => $fields_ref->{'4400'}, # Zugriff: online
        };

        my @workkeys = $normalizer->gen_workkeys({ fields => $workkey_record_ref});

        my $mult = 1;
        foreach my $workkey (@workkeys) {
            push @{$fields_ref->{'5055'}}, {
                mult      => $mult++,
                content   => $workkey,
                subfield  => '',
            };
        }
    }

    my $title_matchkey = "$database:$id";
    
    # Zentrale Anreicherungsdaten lokal einspielen
    if ($self->{local_enrichmnt} && (@{$enrichmnt_isbns_ref} || @{$enrichmnt_issns_ref} || $bibkey || $title_matchkey)) {
        @{$enrichmnt_isbns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_isbns_ref} }}; # Only unique
        @{$enrichmnt_issns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_issns_ref} }}; # Only unique
        
        foreach my $field (keys %{$self->{conv_config}{local_enrichmnt}}) {
            my $enrichmnt_data_ref = [];
            
            if (@{$enrichmnt_isbns_ref}) {
                foreach my $isbn13 (@{$enrichmnt_isbns_ref}) {
                    my $lookup_ref = $self->{storage}{enrichmntdata}{$isbn13};
                    $logger->debug("Testing ISBN $isbn13 for field $field");
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISBN $isbn13 with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            elsif (@{$enrichmnt_issns_ref}) {
                foreach my $issn (@{$enrichmnt_issns_ref}) {
                    my $lookup_ref = $self->{storage}{enrichmntdata}{$issn};
                    
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISSN $issn with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            elsif ($bibkey){
                my $lookup_ref = $self->{storage}{enrichmntdata}{$bibkey};
                    
                foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                    $logger->debug("Enrich field $field for Bibkey $bibkey with $enrich_content for id $id");
                    push @$enrichmnt_data_ref, $enrich_content;
                }
            }

	    # Anreicherung mit spezifischer Titel-ID und Datenbank

	    {
		my $lookup_ref = $self->{storage}{enrichmntdata}{$title_matchkey};
		
                foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                    $logger->debug("Enrich field $field for title matchkey $title_matchkey with $enrich_content for id $id");
                    push @$enrichmnt_data_ref, $enrich_content;
                }
	    }
            
            if (@{$enrichmnt_data_ref}) {
                my $mult = 1;
                
                foreach my $content (uniq @{$enrichmnt_data_ref}) { # unique
                    $logger->debug("Id: $id - Adding $field -> $content");

                    push @{$fields_ref->{$field}}, {
                        mult      => $mult,
                        content   => $content,
                        subfield  => 'e',
                    };
                    
                    $mult++;
                }
            }
        }
    }

    my $enriched_jsonline = encode_json $record_ref;

    return $enriched_jsonline;
}

sub enrich_marc {
    my ($self,$arg_ref) = @_;

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);
    my $database    = $self->{database};
    my $normalizer  = $self->{_normalizer};

    $logger->debug("Processing JSON: $json");

    my $record_ref = {};

    eval {
	$record_ref = decode_json $json;
    };
    
    if ($@){
	$logger->error("Skipping record: $@");
	return;
    }

    $logger->debug("JSON decoded");
    
    my $id            = $record_ref->{id};
    my $fields_ref    = $record_ref->{fields};

    my $enrichmnt_isbns_ref = [];
    my $enrichmnt_issns_ref = [];

    my @isbn                   = ();
    my @issn                   = ();

    # Anreicherungs-IDs bestimmen

    # ISBN
    foreach my $field ('0020') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

		if ($item_ref->{subfield} eq "a"){

		    my $this_isbn = $normalizer->normalize({
			    field    => "isbn",
			    content  =>	$item_ref->{content},
						      });
		    # Alternative ISBN zur Rechercheanreicherung erzeugen
		    my $isbn = Business::ISBN->new($this_isbn);
		    
		    if (defined $isbn && $isbn->is_valid) {
			
			# ISBN13 fuer Anreicherung merken
			
			push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
			    field    => "isbn",
			    content  => $isbn->as_isbn13->as_string,
										       });
		    }
		}
            }
        }
    }

    foreach my $field ('0776') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

		if ($item_ref->{subfield} eq "z"){

		    my $this_isbn = $normalizer->normalize({
			    field    => "isbn",
			    content  =>	$item_ref->{content},
							   });
		    # Alternative ISBN zur Rechercheanreicherung erzeugen
		    my $isbn = Business::ISBN->new($this_isbn);
		    
		    if (defined $isbn && $isbn->is_valid) {
			
			# ISBN13 fuer Anreicherung merken
			
			push @{$enrichmnt_isbns_ref}, $normalizer->normalize({
			    field    => "isbn",
			    content  => $isbn->as_isbn13->as_string,
									     });
		    }
		}
            }
        }
    }
    
    # ISSN
    foreach my $field ('0022') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
		if ($item_ref->{subfield} eq "a"){
		    push @{$enrichmnt_issns_ref}, $normalizer->normalize({
			field    => "T0543",
			content  => $item_ref->{content},
										   });
		}
            }
        }
    }

    # Bibkey-Generierung mit MARC-Records
	    
    # Bibkey-Kategorie 5050 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel

    my $bibkey = "";

    if ((defined $fields_ref->{'0100'} || defined $fields_ref->{'0700'}) && defined $fields_ref->{'0245'} && (defined $fields_ref->{'0264'})){

	my $bibkey_record_ref = {
	    'T0100' => $fields_ref->{'0100'},
		'T0700' => $fields_ref->{'0700'},
		'T0245' => $fields_ref->{'0245'},
		'T0264' => $fields_ref->{'0264'},
	};
	
        my $bibkey_base = $normalizer->gen_bibkey_base({ fields => $bibkey_record_ref, scheme => 'marc'});
	
        $bibkey      = ($bibkey_base)?$normalizer->gen_bibkey({ bibkey_base => $bibkey_base }):"";

	if ($logger->is_debug){
	    $logger->debug("Generating bibkey for ".YAML::Dump($bibkey_record_ref)." Got base $bibkey_base and bibkey $bibkey");
	}
        
        if ($bibkey) {
            push @{$fields_ref->{'5050'}}, {
                mult      => 1,
                content   => $bibkey,
                subfield  => '',
            };
                
            push @{$fields_ref->{'5051'}}, {
                mult      => 1,
                content   => $bibkey_base,
                subfield   => '',
            };

            # Bibkey merken fuer Recherche ueber Suchmaschine
#            $index_doc->add_index('bkey',1, ['T5050',$bibkey]);
#            $index_doc->add_index('bkey',1, ['T5051',$bibkey_base]);
        }
    }

    # Workkey-Kategorie 5055 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel
    if ((defined $fields_ref->{'0100'} || defined $fields_ref->{'0700'}) && defined $fields_ref->{'0245'} && defined $fields_ref->{'0264'}){
        # Erscheinungsjahr muss existieren, damit nur 'ordentliche' Titel untersucht werden
        
        my $workkey_record_ref = {
            'T0100' => $fields_ref->{'0100'}, # Verfasser
            'T0700' => $fields_ref->{'0101'}, # Weitere Personen
            'T0245' => $fields_ref->{'0245'}, # HST
            'T0264' => $fields_ref->{'0264'}, # Jahr, Verlag
            'T0130' => $fields_ref->{'0130'}, # EST
            'T0240' => $fields_ref->{'0240'}, # EST
            'T0250' => $fields_ref->{'0250'}, # Auflage als Suffix
            'T4301' => $fields_ref->{'4301'}, # Angereicherte Sprache
            'T4400' => $fields_ref->{'4400'}, # Zugriff: online
        };

        my @workkeys = $normalizer->gen_workkeys({ fields => $workkey_record_ref, scheme => 'marc'});

	if ($logger->is_debug){
	    $logger->debug("Got workkeys: ".YAML::Dump(\@workkeys));
	}

        my $mult = 1;
        foreach my $workkey (@workkeys) {
            push @{$fields_ref->{'5055'}}, {
                mult      => $mult++,
                content   => $workkey,
                subfield  => '',
            };
        }
    }

    my $title_matchkey = "$database:$id";
    
    # Zentrale Anreicherungsdaten lokal einspielen
    if ($self->{local_enrichmnt} && (@{$enrichmnt_isbns_ref} || @{$enrichmnt_issns_ref} || $bibkey || $title_matchkey )) {
        @{$enrichmnt_isbns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_isbns_ref} }}; # Only unique
        @{$enrichmnt_issns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_issns_ref} }}; # Only unique
        
        foreach my $field (keys %{$self->{conv_config}{local_enrichmnt}}) {
            my $enrichmnt_data_ref = [];
            
            if (@{$enrichmnt_isbns_ref}) {
                foreach my $isbn13 (@{$enrichmnt_isbns_ref}) {
                    my $lookup_ref = $self->{storage}{enrichmntdata}{$isbn13};
                    $logger->debug("Testing ISBN $isbn13 for field $field");
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISBN $isbn13 with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            elsif (@{$enrichmnt_issns_ref}) {
                foreach my $issn (@{$enrichmnt_issns_ref}) {
                    my $lookup_ref = $self->{storage}{enrichmntdata}{$issn};
                    
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISSN $issn with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            # elsif ($bibkey){
            #     my $lookup_ref = $self->{storage}{enrichmntdata}{$bibkey};
                    
            #     foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
            #         $logger->debug("Enrich field $field for Bibkey $bibkey with $enrich_content for id $id");
            #         push @$enrichmnt_data_ref, $enrich_content;
            #     }
            # }

	    # Anreicherung mit spezifischer Titel-ID und Datenbank

	    {
		my $lookup_ref = $self->{storage}{enrichmntdata}{$title_matchkey};
		
                foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                    $logger->debug("Enrich field $field for title matchkey $title_matchkey with $enrich_content for id $id");
                    push @$enrichmnt_data_ref, $enrich_content;
                }
	    }
            
            if (@{$enrichmnt_data_ref}) {
                my $mult = 1;
                
                foreach my $content (keys %{{ map { $_ => 1 } @${enrichmnt_data_ref} }}) { # unique
                    $logger->debug("Id: $id - Adding $field -> $content");

                    push @{$fields_ref->{$field}}, {
                        mult      => $mult,
                        content   => $content,
                        subfield  => 'e', # enriched
                    };
                    
                    $mult++;
                }
            }
        }
    }

    my $enriched_jsonline = encode_json $record_ref;

    return $enriched_jsonline;
}

sub get_columns_title_title {
    my $self = shift;

    return $self->{_columns_title_title};
}

sub get_columns_title_person {
    my $self = shift;

    return $self->{_columns_title_person};
}

sub get_columns_title_corporatebody {
    my $self = shift;

    return $self->{_columns_title_corporatebody};
}

sub get_columns_title_classification {
    my $self = shift;

    return $self->{_columns_title_classification};
}

sub get_columns_title_subject {
    my $self = shift;

    return $self->{_columns_title_subject};
}

sub get_columns_title {
    my $self = shift;

    return $self->{_columns_title};
}

sub get_columns_title_fields {
    my $self = shift;

    return $self->{_columns_title_fields};
}

sub get_fields {
}

sub add_fields {
}

sub set_record {
}

sub get_record {
}

sub get_index_document {
    my ($self)=@_;

    return (defined $self->{_index_doc})? $self->{_index_doc}:undef;
}

sub set_index_document {
    my ($self,$index_doc)=@_;

    $self->{_index_doc} = $index_doc;

    return $self;
}


1;
