#####################################################################
#
#  OpenBib::Importer::JSON::Title.pm
#
#  Titel
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@openbib.org>
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
use Encode qw/decode_utf8/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use YAML ();
use Business::ISBN;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Container;
use OpenBib::Index::Document;

my %char_replacements = (
    
    # Zeichenersetzungen
    "\n"     => "<br\/>",
    "\r"     => "\\r",
    ""     => "",
#    "\x{00}" => "",
#    "\x{80}" => "",
#    "\x{87}" => "",
);

my $chars_to_replace = join '|',
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $storage   = exists $arg_ref->{storage}
        ? $arg_ref->{storage}        : undef;

    my $addsuperpers   = exists $arg_ref->{addsuperpers}
        ? $arg_ref->{addsuperpers}        : 0;
    my $addlanguage    = exists $arg_ref->{addlanguage}
        ? $arg_ref->{addlanguage}         : 0;
    my $addmediatype   = exists $arg_ref->{addmediatype}
        ? $arg_ref->{addmediatype}        : 0;
    my $local_enrichmnt   = exists $arg_ref->{local_enrichmnt}
        ? $arg_ref->{local_enrichmnt}     : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;

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

    if (defined $storage){
        $self->{storage}       = $storage;
        $logger->debug("Setting storage");
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

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    my $record    = exists $arg_ref->{record}
        ? $arg_ref->{record}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);
    my $config      = OpenBib::Config->instance;
    my $storage     = OpenBib::Container->instance;
    my $database    = $self->{database};

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

    if ($json){
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
                    
                    push @{$enrichmnt_isbns_ref}, OpenBib::Common::Util::normalize({
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
                push @{$enrichmnt_issns_ref}, OpenBib::Common::Util::normalize({
                    field    => "T0543",
                    content  => $item_ref->{content},
                });
            }
        }
    }

    # Zentrale Anreicherungsdaten lokal einspielen
    if ($self->{local_enrichmnt} && (@{$enrichmnt_isbns_ref} || @{$enrichmnt_issns_ref})) {
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
            
            if (@{$enrichmnt_data_ref}) {
                my $mult = 1;
                
                foreach my $content (keys %{{ map { $_ => 1 } @${enrichmnt_data_ref} }}) { # unique
                    $content = decode_utf8($content);
                    
                    $logger->debug("Id: $id - Adding $field -> $content");

                    push @{$fields_ref->{$field}}, {
                        mult      => $mult,
                        content   => $content,
                        subfield  => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }

    my $valid_language_available=0;
    my $mult_lang = 1;
    
    if (defined $fields_ref->{'0015'}){
        foreach my $item_ref (@{$fields_ref->{'0015'}}){
            my $valid_lang = OpenBib::Common::Util::normalize_lang($item_ref->{content});
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

        # Sprachcodeanhand 0331 usw. und Linguistischer Spracherkennung
        
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
            
            $langcode = OpenBib::Common::Util::normalize_lang($lang[1]);
            
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
        foreach my $item_ref (@{$fields_ref->{'4410'}}) {
            $have_type_ref->{$item_ref->{content}} = 1;
            $type_mult++;
        }

        # Monographie:
        # Kollation 434 besetzt und enthaelt S. bzw. p.
        if (defined $fields_ref->{'0433'}) {
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
        
        # Zeitschriften/Serien:
        # ISSN und/oder ZDB-ID besetzt
        if (defined $fields_ref->{'0572'} || defined $fields_ref->{'0543'}) {
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Zeitschrift/Serie',
                subfield  => '',
            } unless (defined $have_type_ref->{'Zeitschrift/Serie'});
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
        if ($fields_ref->{'0519'}) {
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Hochschulschrift',
                subfield  => '',
            } unless (defined $have_type_ref->{'Hochschulschrift'});
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
            my $source_titleid   = $id;
            my $supplement       = "";
            my $field            = "0004";
            
            if (defined $inverted_ref->{$field}->{index}) {
                foreach my $searchfield (keys %{$inverted_ref->{$field}->{index}}) {
                    my $weight = $inverted_ref->{$field}->{index}{$searchfield};

                    $index_doc->add_index($searchfield, $weight, ["T$field",$target_titleid]);
                }
            }
            
            push @superids, $target_titleid;
            
            if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && $source_titleid && $target_titleid){
                $supplement = cleanup_content($supplement);
                push @{$self->{_columns_title_title}}, [$self->{title_title_serialid},$field,$source_titleid,$target_titleid,$supplement];
                $self->{title_title_serialid}++;
            }


            if (defined $self->{storage}{listitemdata_superid}{$target_titleid} && %{$self->{storage}{listitemdata_superid}{$target_titleid}}){
                # my $title_super = encode_json($self->{storage}{listitemdata_superid}{$target_titleid});

                # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
                # $title_super = cleanup_content($title_super);

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
    foreach my $field ('0100','0101','0102','0103','1800') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
	        $item_ref->{ignore} = 1;
                
                my $personid   = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = $item_ref->{supplement};
                
                #                 # Feld 1800 wird als 0100 behandelt
                #                 if ($field eq "1800") {
                #                     $field = "0100";   
                #                 }
                
                next unless $personid;
                
                if (defined $self->{storage}{listitemdata_person}{$personid}){
                    $supplement = cleanup_content($supplement);
                    push @{$self->{_columns_title_person}}, [$self->{title_person_serialid},$field,$id,$personid,$supplement];
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
                    }) if (exists $self->{conv_config}{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry;
                    
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
    foreach my $field ('0200','0201','1802') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                my $corporatebodyid = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = "";
                
                #                 # Feld 1802 wird als 0200 behandelt
                #                 if ($field eq "1802") {
                #                     $field = "0200";   
                #                 }
                
                next unless $corporatebodyid;
                
                if (defined $self->{storage}{listitemdata_corporatebody}{$corporatebodyid}){
                    $supplement = cleanup_content($supplement);
                    push @{$self->{_columns_title_corporatebody}}, [$self->{title_corporatebody_serialid},$field,$id,$corporatebodyid,$supplement];
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
                    }) if (exists $self->{conv_config}{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry;
                    
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
                
                my $classificationid = $item_ref->{id};
                my $titleid          = $id;
                my $supplement       = "";
                
                next unless $classificationid;
                
                if (defined $self->{storage}{listitemdata_classification}{$classificationid}){
                    push @{$self->{_columns_title_classification}}, [$self->{title_classification_serialid},$field,$id,$classificationid,$supplement];
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
                    }) if (exists $self->{conv_config}{listitemcat}{$field});
                    
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
    foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                my $subjectid = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = "";
                
                next unless $subjectid;
                
                if (defined $self->{storage}{listitemdata_subject}{$subjectid}){
                    $supplement = cleanup_content($supplement);
                    push @{$self->{_columns_title_subject}}, [$self->{title_subject_serialid},$field,$id,$subjectid,$supplement];
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
                    }) if (exists $self->{conv_config}{listitemcat}{$field});
                    
#                    if (exists $inverted_ref->{$field}->{index}) {                    
                        push @subject, $subjectid;
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
                        # Anreichern fuer Facetten
                        if (defined $inverted_ref->{$field}->{facet}){
                            foreach my $searchfield (keys %{$inverted_ref->{$field}->{facet}}) {
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


    # Bibkey-Kategorie 5050 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel
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

        my $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({ fields => $bibkey_record_ref});

        my $bibkey      = ($bibkey_base)?OpenBib::Common::Util::gen_bibkey({ bibkey_base => $bibkey_base }):"";
        
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

        my @workkeys = OpenBib::Common::Util::gen_workkeys({ fields => $workkey_record_ref});

        my $mult = 1;
        foreach my $workkey (@workkeys) {
            push @{$fields_ref->{'5055'}}, {
                mult      => $mult++,
                content   => $workkey,
                subfield  => '',
            };
        }
    }
    
    # Suchmaschineneintraege mit den Tags, Literaturlisten und Standard-Titelkategorien fuellen
    {
        foreach my $field (keys %{$inverted_ref}){
            # a) Indexierung in der Suchmaschine
            if (exists $inverted_ref->{$field}->{index}){

                my $flag_isbn = 0;
                # Wird dieses Feld als ISBN genutzt, dann zusaetzlicher Inhalt
                foreach my $searchfield (keys %{$inverted_ref->{$field}->{index}}) {
                    if ($searchfield eq "isbn"){
                        $flag_isbn=1;
                    }
                }
                
                foreach my $searchfield (keys %{$inverted_ref->{$field}->{index}}) {
                    my $weight = $inverted_ref->{$field}->{index}{$searchfield};
                    if    ($field eq "tag"){
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
                                $index_doc->add_index($searchfield,$weight, ['litlist',$litlist_ref->{title}]);
                            }
                            
                            $logger->info("### $database: Adding Litlists to ID $id");
                        }
                    }
                    else {
                        next unless (defined $fields_ref->{$field});
                        
                        foreach my $item_ref (@{$fields_ref->{$field}}){
                            next unless $item_ref->{content};

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
            
            # b) Facetten in der Suchmaschine
            if (exists $inverted_ref->{$field}->{facet}){
                foreach my $searchfield (keys %{$inverted_ref->{$field}->{facet}}) {
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
                            $index_doc->add_facet("facet_$searchfield", $item_ref->{content});        
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
        if (defined $self->{conv_config}{listitemcat}{$field}) {
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
        # Ist nichts zu tun
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
                    content => "Kein HST/AST vorhanden",
                });
            }
        }
        
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
    $titlecache = cleanup_content($titlecache);

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
    
    push @{$self->{_columns_title}}, [$id,$create_tstamp,$update_tstamp,$titlecache,$popularity];
    
    # Abhaengige Feldspezifische Saetze erstellen und schreiben
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $blacklist_ref->{$field});
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next if ($item_ref->{ignore});

            if (ref $item_ref->{content} eq "HASH"){
                my $content = decode_utf8(encode_json ($item_ref->{content})); # decode_utf8, um doppeltes Encoding durch encode_json und binmode(:utf8) zu vermeiden
                $item_ref->{content} = cleanup_content($content);
            }

            if ($id && $field && $item_ref->{content}){
                $item_ref->{content} = cleanup_content($item_ref->{content});

#                $logger->error("mult fehlt") if (!defined $item_ref->{mult});
#                $logger->error("subfield fehlt") if (!defined $item_ref->{subfield});
                
                push @{$self->{_columns_title_fields}}, [$self->{serialid},$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];
                $self->{serialid}++;
            }
        }
    }                
    
    # Index-Document speichern;
    
    $self->set_index_document($index_doc);

    return $self;
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

sub cleanup_content {
    my $content = shift;

    # Make PostgreSQL Happy    
    $content =~ s/\\/\\\\/g;
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;
            
    return $content;
}

1;
