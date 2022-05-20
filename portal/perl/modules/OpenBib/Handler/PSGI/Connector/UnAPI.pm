####################################################################
#
#  OpenBib::Handler::PSGI::Connector::UnAPI.pm
#
#  Dieses File ist (C) 2007-2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Connector::UnAPI;

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
use utf8;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'                       => 'show',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
    #    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $query        = $self->query();
    my $r            = $self->param('r');
    my $config       = $self->param('config');
    my $session      = $self->param('session');
    my $user         = $self->param('user');
    my $msg          = $self->param('msg');
    my $queryoptions = $self->param('qopts');
    my $stylesheet   = $self->param('stylesheet');
    my $useragent    = $self->param('useragent');
    my $path_prefix  = $self->param('path_prefix');

    # CGI Args
    my $unapiid = $query->param('id')     || '';
    my $format  = $query->param('format') || '';

    if ($format) {

        unless ( exists $config->{unAPI_formats}->{$format} ) {
            $logger->error("Format $format not acceptable");
            $self->header_add( 'Status', 406 );    # not acceptable
            return;
        }

        my $title_list             = [];
        my $personlist             = [];
        my $rswk_keyword_list      = [];
        my $corporation_list       = [];
        my $place_list             = [];
        my $uniform_publisher_list = [];
        my $contained_works        = [];
        my $provenance_data        = [];
        my $date_values            = undef;
        my $main_title_data        = undef;
        if ($unapiid) {
            my ( $database, $idn, $record );

            if ( $unapiid =~ /^(\w+):(\d+)$/ ) {
                $database = $1;
                $idn      = $2;

                $logger->debug("Database: $database - ID: $idn");

                $record = new OpenBib::Record::Title(
                    { database => $database, id => $idn } )->load_full_record;
                $main_title_data =
                  $self->get_main_title_data( $record, $database );

                $title_list = $self->collect_title_data( $record, $database );
                $contained_works =
                  $self->collect_contained_works( $record, $database );
                $personlist = $self->collect_person_data( $record, $database );
                $corporation_list =
                  $self->collect_corporation_data( $record, $database );
                $place_list = $self->collect_place_data( $record, $database );
                $uniform_publisher_list =
                  $self->collect_publisher_data( $record, $database );
                $rswk_keyword_list =
                  $self->collect_rswk_data( $record, $database );
                $provenance_data = undef;
                my $provenance_elements =
                  $self->collect_provenance_data( $record, $database );

                if ( @{$provenance_elements} != 0 ) {
                    $provenance_data =
                      JSON::XS->new->latin1->encode($provenance_elements);
                }
                $date_values = $self->get_date_values( $record, $database );

            }

            if ( !$record->record_exists ) {
                $self->header_add( 'Status', 404 );    # not found
                return;
            }

            my $ttdata = {
                record                 => $record,
                main_title_data        => $main_title_data,
                title_list             => $title_list,
                personlist             => $personlist,
                corporation_list       => $corporation_list,
                place_list             => $place_list,
                uniform_publisher_list => $uniform_publisher_list,
                rswk_keyword_list      => $rswk_keyword_list,
                date_values            => $date_values,
                provenance_data        => $provenance_data,
                contained_works        => $contained_works,

                config => $config,
                msg    => $msg,
            };

            $ttdata = $self->add_default_ttdata($ttdata);

            my $templatename =
              ($format)
              ? "tt_connector_unapi_" . $format . "_tname"
              : "tt_unapi_formats_tname";

            $logger->debug("Using Template $templatename");

            my $content = "";

            my $template = Template->new(
                {
                    LOAD_TEMPLATES => [
                        OpenBib::Template::Provider->new(
                            {
                                INCLUDE_PATH => $config->{tt_include_path},
                                ABSOLUTE     => 1,
                            }
                        )
                    ],
                    OUTPUT    => \$content,
                    RECURSION => 1,
                }
            );

            my %format_info = ( bibtex => 'text/plain', );

            # Dann Ausgabe des neuen Headers
            my $is_valid_title = 0;
            foreach my $val ( values %{ $record->get_fields } ) {
                if ( @{$val} ) {
                    $is_valid_title = 1;
                }
            }

            # if (!$is_valid_title){
            #     $self->header_add( 'Status', 400 );    # server error
            #     return "Der Katkey $idn existiert nicht";
            # }
            if ( $format_info{$format} ) {
                $self->header_add( 'Content-Type', $format_info{$format} );
            }
            else {
                $self->header_add( 'Content-Type', 'application/xml' );
            }
            $template->process( $config->{$templatename}, $ttdata ) || do {
                $logger->error( $template->error() );
                $self->header_add( 'Status', 400 );    # server error
                return;
            };

            eval {
                # PSGI-Spezifikation erwartet UTF8 bytestream
                $content = encode_utf8($content);
            };

            if ($@) {
                $logger->fatal($@);
            }

            $logger->debug( "Template-Output: " . $content );

            return $content;
        }
        else {
        }
    }
    else {
        my $ttdata = {
            unapiid => $unapiid,
            config  => $config,
            msg     => $msg,
        };

        $ttdata = $self->add_default_ttdata($ttdata);

        my $templatename = $config->{tt_connector_unapi_formats_tname};

        $logger->debug("Using Template $templatename");

        my $content = "";

        my $template = Template->new(
            {
                LOAD_TEMPLATES => [
                    OpenBib::Template::Provider->new(
                        {
                            INCLUDE_PATH => $config->{tt_include_path},
                            ABSOLUTE     => 1,
                        }
                    )
                ],
                OUTPUT    => \$content,
                RECURSION => 1,
            }
        );

        # Dann Ausgabe des neuen Headers
        $self->header_add( 'Content-Type', 'application/xml' );

        $template->process( $templatename, $ttdata ) || do {
            $logger->error( $template->error() );
            $self->header_add( 'Status', 400 );    # server error
        };

        return $content;
    }
}

sub get_main_title_data {
    my $self       = shift;
    my $record     = shift;
    my $database   = shift;
    my $title_data = {};
    if ( length( $record->get_fields->{T0331} ) ) {
        my $title_content = $record->get_fields->{T0331}[0]->{content};
        if ( rindex( $title_content, decode_utf8("¬"), 0 ) != -1 ) {
            ( my $first, my $rest ) = split( ' ', $title_content, 2 );
            $title_data->{"main_title"} = $rest;
            $title_data->{"non_sort"}   = $first;
        }
        else {
            my $title_content = $record->get_fields->{T0331}[0]->{content};
            $title_data->{"main_title"} = $title_content;
        }
        return $title_data;
    }
    return undef;

}

sub collect_title_data {
    my $self          = shift;
    my $record        = shift;
    my $database      = shift;
    my $already_added = [];
    my $title_list    = [];

    #Weiterer/Alternativer Titel
    if ( length( $record->get_fields->{T0370} ) ) {
        foreach my $title_item ( @{ $record->get_fields->{T0370} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0370"
            };
            push( @{$title_list}, $title_item );
        }
    }

    #Weiterer/Alternativer Titel
    if ( $record->get_fields->{T0306} ) {
        foreach my $title_item ( @{ $record->get_fields->{T0306} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0306"
            };
            push( @{$title_list}, $title_item );
        }
    }

    #Übersetzter Titel
    if ( $record->get_fields->{T0341} ) {
        foreach my $title_item ( @{ $record->get_fields->{T0341} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0341"
            };
            push( @{$title_list}, $title_item );
        }
    }

    #Einheitstitel
    if ( length( $record->get_fields->{T7303} ) ) {
        my $rda_collection =
          $self->process_title_rda( $record->get_fields->{T7303},
            "T7303", $title_list );
    }
    unless ( length( $record->get_fields->{T7303} ) ) {

        #Einheitstitel
        if ( $record->get_fields->{T0304} ) {
            foreach my $title_item ( @{ $record->get_fields->{T0304} } ) {
                my $title_item = {
                    title => $title_item->{content},
                    field => "T0304"
                };
                push( @{$title_list}, $title_item );
            }
        }

        #Einheitstitel
        if ( $record->get_fields->{T0310} ) {
            foreach my $title_item ( @{ $record->get_fields->{T0310} } ) {
                my $title_item = {
                    title => $title_item->{content},
                    field => "T0310"
                };
                push( @{$title_list}, $title_item );
            }
        }
    }
    return $title_list;
}

sub process_title_rda {
    my $self           = shift;
    my $rda_field_data = shift;
    my $field_name     = shift;
    my $title_list     = shift;
    my $mult_values    = $self->get_all_mult_values($rda_field_data);
    foreach my $mult_value ( @{$mult_values} ) {
        my $currentObject = {};
        foreach my $title ( @{$rda_field_data} ) {
            if ( $title->{mult} == $mult_value ) {
                if ( $title->{subfield} eq "t" ) {
                    $currentObject->{title} = $title->{content};
                    $currentObject->{title} =~ s/^\s+|\s+$//g;
                }
                elsif ( $title->{subfield} eq "p" || $title->{subfield} eq "a" )
                {
                    $currentObject->{person} = $title->{content};
                    $currentObject->{person} =~ s/^\s+|\s+$//g;
                }
                elsif ( $title->{subfield} eq "9"
                    and index( $title->{content}, "DE-588" ) != -1 )
                {
                    $currentObject->{gnd} = $title->{content};
                    $currentObject->{gnd} =~ s/\(DE-588\)//;
                    $currentObject->{gnd} =~ s/^\s+|\s+$//g;
                    $currentObject->{field} = $field_name;
                }
            }
        }
        $currentObject->{field} = $field_name;
        push( @{$title_list}, $currentObject );
    }
    my @filtered_title_list = grep( defined, @{$title_list} );
    return \@filtered_title_list;
}

sub collect_contained_works {
    my $self            = shift;
    my $record          = shift;
    my $database        = shift;
    my $contained_works = [];

    #Angebundenes Werk RDA
    if ( length( $record->get_fields->{T7304} ) ) {
        my $rda_collection =
          $self->process_title_rda( $record->get_fields->{T7304}, "T7304" );
        foreach my $title_item ( @{$rda_collection} ) {
            push( @{$contained_works}, $title_item );
        }

    }

    #Angebundenes Werk RAK
    unless ( length( $record->get_fields->{T7304} ) ) {
        if ( length( $record->get_fields->{T0361} ) ) {
            foreach my $title_item ( @{ $record->get_fields->{T0361} } ) {
                my $title_item = {
                    title => $title_item->{content},
                    field => "T0361"
                };
                push( @{$contained_works}, $title_item );
            }
        }
    }
    return $contained_works;
}

sub collect_rswk_data {
    my $self      = shift;
    my $record    = shift;
    my $database  = shift;
    my $rswk_data = [];

    if ( length( $record->get_fields->{T0902} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0902} );
    }
    if ( length( $record->get_fields->{T0907} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0907} );
    }
    if ( length( $record->get_fields->{T0912} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0912} );
    }
    if ( length( $record->get_fields->{T0917} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0917} );
    }
    if ( length( $record->get_fields->{T0922} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0922} );
    }
    return $rswk_data;
}

sub get_date_values() {
    my $self        = shift;
    my $record      = shift;
    my $database    = shift;
    my $date_values = {};
    if ( $record->get_fields->{T0422} ) {
        $date_values->{"start_date"} =
          $record->get_fields->{T0422}[0]->{content};
    }
    if ( $record->get_fields->{T0423} ) {
        $date_values->{"end_date"} = $record->get_fields->{T0423}[0]->{content};
    }
    if ( $record->get_fields->{T0424} ) {
        $date_values->{"date"} = $record->get_fields->{T0424}[0]->{content};
    }
    if ( $record->get_fields->{T0425} ) {
        $date_values->{"date_norm"} =
          $record->get_fields->{T0425}[0]->{content};
    }

  #this is probably not necessary since we do no process dates of volumes
  # unless ( $record->get_fields->{T0425} ) {
  #     if ( $record->get_fields->{T0089} ) {
  #         my $date_value = undef;
  #         if (
  #             index( $record->get_fields->{T0089}[0]->{content}, "." ) != -1 )
  #         {
  #             my @splitted_string =
  #               split( '\.', $record->get_fields->{T0089}[0]->{content} );
  #             $date_value = $splitted_string[-1];
  #         }
  #         else {
  #             $date_value = $record->get_fields->{T0089}[0]->{content};
  #         }
  #         if ( index( $date_value, "\/" ) != -1 ) {
  #             unless ( $date_values->{"start_date"} ) {

    #                 if ( index( $date_value, "(" ) == -1 ) {
    #                     my @splitted_date = split( '\/', $date_value );
    #                     $date_values->{"start_date"} = $splitted_date[0];
    #                     $date_values->{"end_date"}   = $splitted_date[1];
    #                     if (   length( $date_values->{"start_date"} ) == 4
    #                         && length( $date_values->{"end_date"} ) == 2 )
    #                     {
    #                         $date_values->{"end_date"} =
    #                           substr( $date_values->{"start_date"}, 0, 2 )
    #                           . $date_values->{"end_date"};
    #                     }
    #                 }
    #             }
    #         }

   #         #special cases like 10,10(1771/2003)1994 1594159
   #         unless ( $date_values->{"date_norm"} ) {
   #             unless ( index( $date_value, "(" ) != -1 ) {
   #                 $date_values->{"date_norm"} = $date_value;
   #             }
   #             else {
   #                 if ( $record->get_fields->{T0024}[0]->{content}
   #                     && length( $record->get_fields->{T0024}[0]->{content} )
   #                     == 4 )
   #                 {
   #                     $date_values->{"date_norm"} =
   #                       $record->get_fields->{T0024}[0]->{content};
   #                 }
   #             }
   #         }
   #     }
   # }

    if ( $date_values->{"date"} eq $date_values->{"date_norm"} ) {
        delete( $date_values->{"date"} );
    }

    return $date_values;
}

sub collect_person_data {
    my $self       = shift;
    my $record     = shift;
    my $database   = shift;
    my $persondata = [];
    my $personlist = [];
    if ( $record->get_fields->{T0100} ) {
        my $person_item = {
            values => $record->get_fields->{T0100},
            field  => "T0100"
        };
        push( @{$persondata}, $person_item );
    }
    if ( $record->get_fields->{T0101} ) {
        my $person_item = {
            values => $record->get_fields->{T0101},
            field  => "T0101"
        };
        push( @{$persondata}, $person_item );
    }
    if ( $record->get_fields->{T0102} ) {
        my $person_item = {
            values => $record->get_fields->{T0102},
            field  => "T0102"
        };
        push( @{$persondata}, $person_item );
    }
    if ( $record->get_fields->{T0103} ) {
        my $person_item = {
            values => $record->get_fields->{T0103},
            field  => "T0103"
        };
        push( @{$persondata}, $person_item );
    }

    #Personendaten aus der Überordnung ziehen
    if ( scalar @{$persondata} == 0 ) {

#wie kann JSON geparst werden
#http://localhost:8008/portal/openbib/connector/unapi?id=rheinabt:84411&format=oai_mods
        if ( $record->get_fields->{T5005} ) {
            my $super_field =
              $record->get_field( { field => "T5005" } )->[0]->{"content"};

            #my $decoded = decode_json(encode_utf8($super_field));
            #evtl. ecnode_utf8 rausnehmen
            my $decoded = {};
            $super_field =~ s/\\"/"/g;
            eval { $decoded = decode_json encode_utf8($super_field); };
            if ( $decoded->{"fields"}->{"0100"} ) {
                my $person_item = {
                    values => $decoded->{"0100"},
                    field  => "T0100"
                };
                push( @{$persondata}, $person_item );
            }
            if ( $decoded->{"fields"}->{"0101"} ) {
                my $person_item = {
                    values => $decoded->{"fields"}->{"0101"},
                    field  => "T0101"
                };
                push( @{$persondata}, $person_item );
            }
            if ( $decoded->{"0102"} ) {
                my $person_item = {
                    values => $decoded->{"fields"}->{"0102"},
                    field  => "T0102"
                };
                push( @{$persondata}, $person_item );
            }
            if ( $decoded->{"0103"} ) {
                my $person_item = {
                    values => $decoded->{"fields"}->{"0103"},
                    field  => "T0103"
                };
                push( @{$persondata}, $person_item );
            }
        }
    }

    foreach my $person_sub_list ( @{$persondata} ) {
        foreach my $person ( @{ $person_sub_list->{values} } ) {
            my $person_item = {
                namedata => $self->generate_name_data( $person->{content} ),
                gnd => $self->get_gnd_for_person( $person->{id}, $database ),
                role_codes => $self->get_role_codes_for_person(
                    $person->{supplement}, $person_sub_list->{field}
                ),
                field      => $person_sub_list->{field},
                supplement => $person->{supplement}
            };
            push( @{$personlist}, $person_item );
        }
    }
    return $personlist;

}

sub get_role_codes_for_person {
    my $self       = shift;
    my $supplement = shift;
    my $field      = shift;
    my @role_codes = ();
    my @roles      = ();
    if ( defined $supplement ) {
        @roles = split('] ', $supplement );
    }
    if ( !@roles && $field eq "T0100" ) {
        push( @role_codes, "aut" );
    }
    if ( @roles ) {
  
        foreach my $role (@roles) {
            $role =~ s/^\s+|\s+$//g;
            if ($role =~ m/\]$/){
            }else {
                $role = $role .']';
            }

            if ( $role =~ m/Hrsg.]/ || $role =~ m/Herausgeber/ ) {
                push( @role_codes, "edt" );
            }
            elsif ( $role =~ m/Autor]/ || $role =~ m/Verfasser]/ ) {
                push( @role_codes, "aut" );
            }

            # Dubious author [dub]
            elsif ( $role =~ m/Angebl. Verf.]/ ) { return "dub"; }
            elsif ( $role =~ m/Übers.]/ || $role =~ m/Übersetzer/ ) {
                push( @role_codes, "trl" );
            }
            elsif ( $role =~ m/Adressat]/ ) { push( @role_codes, "rcp" ); }

            #elsif ($supplement =~m/Bearb/) { return "edt";}
            #elsif ($supplement =~m/Begr/) { return "edt";}
            elsif ( $role =~ m/Drehbuchautor]/ ) { push( @role_codes, "aus" ); }
            elsif ( $role =~ m/Erzähler]/ )     { push( @role_codes, "nrt" ); }
            elsif ( $role =~ m/Erzähler]/ )     { push( @role_codes, "nrt" ); }
            elsif ( $role =~ m/Filmregisseur]/ ) { push( @role_codes, "fmd" ); }
            elsif ( $role =~ m/Gefeierter]/ )    { push( @role_codes, "hnr" ); }
            elsif ( $role =~ m/Gutachter]/ )     { push( @role_codes, "rev" ); }
            elsif ( $role =~ m/Ill.]/ || $role =~ m/Illustrator]/ ) {
                push( @role_codes, "aut" );
                return "ill";
            }
            elsif ( $role =~ m/Interviewer]/ )  { push( @role_codes, "ivr" ); }
            elsif ( $role =~ m/Interviewter]/ ) { push( @role_codes, "ive" ); }
            elsif ( $role =~ m/Kartograph]/ )   { push( @role_codes, "ctg" ); }
            elsif ($role =~ m/Kommentator]/
                || $role =~ m/Kommentarverfasser]/ )
            {
                push( @role_codes, "aut" );
                return "cmm";
            }
            elsif ( $role =~ m/Komponist]/ )    { push( @role_codes, "cmp" ); }
            elsif ( $role =~ m/Mitwirkender]/ ) { push( @role_codes, "ctb" ); }

            #elsif ($supplement =~m/Mutmaßl. Verf/) { return "trl";}
            elsif ( $role =~ m/Red.]/ )          { push( @role_codes, "red" ); }
            elsif ( $role =~ m/Produzent]/ )    { push( @role_codes, "pro" ); }
            elsif ( $role =~ m/Schauspieler]/ ) { push( @role_codes, "act" ); }

            #elsif ($supplement =~m/Stecher/) { return "red";}
            elsif ( $role =~ m/Übers.]/ || $role =~ m/Übersetzer]/ ) {
                push( @role_codes, "trl" );
            }
            elsif ( $role =~ m/Veranstalter]/ ) {
                push( @role_codes, "orm" );
            }
            elsif ( $role =~ m/Verfasser einer Einleitung]/ ) {
                push( @role_codes, "win" );
            }
            elsif ( $role =~ m/Verfasser eines Nachworts]/ ) {
                push( @role_codes, "aft" );
            }
            elsif ( $role =~ m/Verfasser eines Geleitwortes]/ ) {
                push( @role_codes, "aut" );
            }
            elsif ( $role =~ m/Verfasser eines Postscriptums]/ ) {
                push( @role_codes, "aut" );
            }
            elsif ( $role =~ m/Verfasser eines Vorworts]/ ) {
                push( @role_codes, "wpr" );
            }
            elsif ( $role =~ m/Verfasser von ergänzendem Text]/ ) {
                push( @role_codes, "wst" );
            }
            elsif ( $role =~ m/Widmender]/ ) {
                push( @role_codes, "dto" );
            }
            elsif ( $role =~ m/Widmungsempfänger]/ ) {
                push( @role_codes, "dte" );
            }
            elsif ( $role =~ m/Zusammenstellender]/ ) {
                push( @role_codes, "com" );
            }

            #elsif ($supplement =~m/Zeichner/) { return "red";}
            else {
                push( @role_codes, $role );
            }
        }

    }
    return \@role_codes;

}

sub get_gnd_for_person {
    my $self      = shift;
    my $person_id = shift;
    my $database  = shift;
    my $record    = OpenBib::Record::Person->new(
        { database => $database, id => $person_id } )->load_full_record;
    if ( length( $record->{_fields}->{P0010} ) ) {
        my $gnd_entry = $record->{_fields}->{P0010}->[0]->{content};
        $gnd_entry =~ s/\(DE-588\)//;
        $gnd_entry =~ s/^\s+|\s+$//g;
        return $gnd_entry;
    }
    return "";

}

sub collect_corporation_data {
    my $self             = shift;
    my $record           = shift;
    my $database         = shift;
    my $corp_data        = [];
    my $corporation_list = [];
    if ( $record->get_fields->{T0200} ) {
        my $corp_item = {
            values => $record->get_fields->{T0200},
            field  => "T0200"
        };
        push( @{$corp_data}, $corp_item );
    }
    if ( $record->get_fields->{T0201} ) {
        my $corp_item = {
            values => $record->get_fields->{T0201},
            field  => "T0201"
        };
        push( @{$corp_data}, $corp_item );
    }

    foreach my $corp_sub_list ( @{$corp_data} ) {
        foreach my $corp ( @{ $corp_sub_list->{values} } ) {
            my $corp_item = {
                namedata => $corp->{content},
                gnd => $self->get_gnd_for_corporation( $corp->{id}, $database ),
                field      => $corp_sub_list->{field},
                supplement => $corp->{supplement}
            };
            push( @{$corporation_list}, $corp_item );
        }
    }
    return $corporation_list;
}

sub get_gnd_for_corporation {
    my $self     = shift;
    my $corp_id  = shift;
    my $database = shift;
    my $record   = OpenBib::Record::CorporateBody->new(
        { database => $database, id => $corp_id } )->load_full_record;
    if ( length( $record->{_fields}->{C0010} ) ) {
        my $gnd_entry = $record->{_fields}->{C0010}->[0]->{content};
        $gnd_entry =~ s/\(DE-588\)//;
        $gnd_entry =~ s/^\s+|\s+$//g;
        return $gnd_entry;
    }
    return "";

}

sub collect_place_data {
    my $self       = shift;
    my $record     = shift;
    my $place_list = [];
    my $mult_values =
      $self->get_all_mult_values( $record->get_fields->{T0410} );

    foreach my $mult_value ( @{$mult_values} ) {
        my $currentPlaceObject = {};
        if ( length( $record->get_fields->{T7676} ) ) {
            foreach my $place_rda_data ( @{ $record->get_fields->{T7676} } ) {
                if ( $place_rda_data->{mult} == $mult_value ) {
                    if ( $place_rda_data->{subfield} eq "g" ) {
                        $currentPlaceObject->{"place_rda"}->{place_name} =
                          $place_rda_data->{content};
                        $currentPlaceObject->{"place_rda"}->{place_name} =~
                          s/^\s+|\s+$//g;
                    }
                    elsif ( $place_rda_data->{subfield} eq "9"
                        and index( $place_rda_data->{content}, "DE-588" ) !=
                        -1 )
                    {
                        $currentPlaceObject->{"place_rda"}->{gnd} =
                          $place_rda_data->{content};
                        $currentPlaceObject->{"place_rda"}->{gnd} =~
                          s/\(DE-588\)//;
                        $currentPlaceObject->{"place_rda"}->{gnd} =~
                          s/^\s+|\s+$//g;
                    }
                }

            }

        }
        if ( length( $record->get_fields->{T0410} ) ) {
            foreach my $place ( @{ $record->get_fields->{T0410} } ) {
                if ( $place->{mult} == $mult_value ) {
                    $currentPlaceObject->{"place_free"}->{place_name} =
                      $place->{content},;
                }
            }
        }

        if ( length( $record->get_fields->{T0673} ) ) {
            foreach my $place ( @{ $record->get_fields->{T0673} } ) {
                if ( $place->{mult} == $mult_value ) {
                    $currentPlaceObject->{"place_norm"}->{place_name} =
                      $place->{content},;
                }
            }
        }

        $place_list->[$mult_value] = $currentPlaceObject;
    }

    my @filtered_place_list = grep( defined, @{$place_list} );
    return \@filtered_place_list;

}

sub get_all_mult_values {
    my $self           = shift;
    my $rda_field_data = shift;
    my @mult_values    = ();
    foreach my $rda_field ( @{$rda_field_data} ) {
        my $mult_value = $rda_field->{mult};
        if ( grep( /^$mult_value$/, @mult_values ) ) {
        }
        else {
            push( @mult_values, $mult_value );
        }

    }
    return \@mult_values;
}

sub collect_provenance_data {
    my $self            = shift;
    my $record          = shift;
    my $database        = shift;
    my $provenance_data = [];
    foreach my $prov_field ( @{ $record->get_fields->{T4310} } ) {
        my $prov_data = {};
        $prov_data->{"prov_text"} = $prov_field->{content};
        $provenance_data->[ $prov_field->{mult} ] = $prov_data;
    }
    foreach my $prov_field ( @{ $record->get_fields->{T4309} } ) {
        $provenance_data->[ $prov_field->{mult} ]->{"prov_signatur"} =
          $prov_field->{content};
    }
    foreach my $prov_field ( @{ $record->get_fields->{T4308} } ) {
        $provenance_data->[ $prov_field->{mult} ]->{"prov_person"} =
          $prov_field->{content};
        if ( $prov_field->{id} ) {
            $provenance_data->[ $prov_field->{mult} ]->{"prov_gnd"} =
              $self->get_gnd_for_person( $prov_field->{id}, $database );
        }
    }
    foreach my $prov_field ( @{ $record->get_fields->{T4307} } ) {
        $provenance_data->[ $prov_field->{mult} ]->{"prov_corp"} =
          $prov_field->{content};
        if ( $prov_field->{id} ) {
            $provenance_data->[ $prov_field->{mult} ]->{"prov_gnd"} =
              $self->get_gnd_for_corporation( $prov_field->{id}, $database );
        }
    }
    my @filtered_list = grep( defined, @{$provenance_data} );
    return \@filtered_list;
}

sub collect_publisher_data {
    my $self   = shift;
    my $record = shift;
    my $mult_values =
      $self->get_all_mult_values( $record->get_fields->{T7677} );
    my $uniform_publisher_list = [];
    foreach my $mult_value ( @{$mult_values} ) {
        my $currentObject = {};
        foreach my $publisher ( @{ $record->get_fields->{T7677} } ) {
            if ( $publisher->{mult} == $mult_value ) {
                if ( $publisher->{subfield} eq "k" ) {
                    $currentObject->{publisher_name} = $publisher->{content};
                    $currentObject->{publisher_name} =~ s/^\s+|\s+$//g;
                }
                if ( $publisher->{subfield} eq "p" ) {
                    $currentObject->{publisher_name} = $publisher->{content};
                    $currentObject->{publisher_name} =~ s/^\s+|\s+$//g;
                }
                if ( $publisher->{subfield} eq "h" ) {
                    $currentObject->{publisher_place} = $publisher->{content};
                    $currentObject->{publisher_place} =~ s/^\s+|\s+$//g;
                }
                if ( $publisher->{subfield} eq "9"
                    and index( $publisher->{content}, "DE-588" ) != -1 )
                {
                    $currentObject->{gnd} = $publisher->{content};
                    $currentObject->{gnd} =~ s/\(DE-588\)//;
                    $currentObject->{gnd} =~ s/^\s+|\s+$//g;
                }
            }
        }
        push( @{$uniform_publisher_list}, $currentObject );
    }

    return $uniform_publisher_list;

}

sub generate_name_data {
    my $self          = shift;
    my $content_field = shift;
    my $namedata      = {};
    my $displayname   = $content_field;
    $namedata->{displayname}    = $content_field;
    $namedata->{family_name}    = "";
    $namedata->{given_name}     = "";
    $namedata->{termsOfAddress} = "";
    if (   index( $content_field, "&lt;" ) != -1
        || index( $content_field, "<" ) != -1 )
    {
        my @full_name_array = ();
        if ( index( $content_field, "&lt;" ) ) {
            @full_name_array = split( "&lt;", $content_field );
        }
        else {
            @full_name_array = split( "<", $content_field );
        }
        $displayname = $full_name_array[0];
        $displayname =~ s/^\s+//;
        $namedata->{termsOfAddress} = $full_name_array[1];
        $namedata->{termsOfAddress} =~ s/\&gt;//;
        $namedata->{termsOfAddress} =~ s/^\s+//;
    }
    if ( index( $displayname, "," ) != -1 ) {
        my @name_array = split( ",", $displayname );
        $namedata->{family_name} = $name_array[0];
        $namedata->{family_name} =~ s/^\s+|\s+$//g;
        $namedata->{given_name} = $name_array[1];
        $namedata->{given_name} =~ s/^\s+|\s+$//g;
    }
    else {
        $namedata->{given_name} = $displayname;
        $namedata->{given_name} =~ s/^\s+|\s+$//g;
    }
    $namedata->{displayname} = $namedata->{given_name};
    " " . $namedata->{termsOfAddress};
    if ( $namedata->{family_name} ) {
        $namedata->{displayname} .= " " . $namedata->{family_name};
    }
    if ( $namedata->{termsOfAddress} ) {
        $namedata->{displayname} .=
          " &lt;" . $namedata->{termsOfAddress} . "&gt;";
    }
    return $namedata;

}

1;
