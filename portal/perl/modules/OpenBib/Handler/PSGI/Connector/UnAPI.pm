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

        my $uniform_title_list     = [];
        my $personlist             = [];
        my $rswk_keyword_list      = [];
        my $corporation_list       = [];
        my $place_list             = [];
        my $uniform_publisher_list = [];
        my $date_values = undef;
        if ($unapiid) {
            my ( $database, $idn, $record );

            if ( $unapiid =~ /^(\w+):(\d+)$/ ) {
                $database = $1;
                $idn      = $2;

                $logger->debug("Database: $database - ID: $idn");

                $record = new OpenBib::Record::Title(
                    { database => $database, id => $idn } )->load_full_record;
                $uniform_title_list =
                  $self->collect_title_data( $record, $database );
                $personlist = $self->collect_person_data( $record, $database );
                $corporation_list =
                  $self->collect_corporation_data( $record, $database );
                $place_list = $self->collect_place_data( $record, $database );
                $uniform_publisher_list =
                  $self->collect_publisher_data( $record, $database );
                $rswk_keyword_list = 
                    $self->collect_rswk_data( $record, $database );
                $date_values = $self->get_date_values($record, $database);

            }

            if ( !$record->record_exists ) {
                $self->header_add( 'Status', 404 );    # not found
                return;
            }

            my $ttdata = {
                record                 => $record,
                uniform_title_list     => $uniform_title_list,
                personlist             => $personlist,
                corporation_list       => $corporation_list,
                place_list             => $place_list,
                uniform_publisher_list => $uniform_publisher_list,
                rswk_keyword_list      => $rswk_keyword_list,
                date_values            => $date_values,

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

sub collect_title_data {
    my $self          = shift;
    my $record        = shift;
    my $database      = shift;
    my $already_added = [];
    my $title_list    = [];

    if ( length( $record->get_fields->{T7304} ) ) {
        my $rda_collection =
          $self->process_title_rda( $record->get_fields->{T7304}, "T7304" );
        push( @{$title_list}, $rda_collection );
    }

    if ( $record->get_fields->{T0304} ) {
        foreach my $title_item ( @{ $record->get_fields->{T0304} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0304"
            };
            push( @{$title_list}, $title_item );
        }
    }

    if ( $record->get_fields->{T0306} ) {
        foreach my $title_item ( @{ $record->get_fields->{T0306} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0306"
            };
            push( @{$title_list}, $title_item );
        }
    }

    if ( $record->get_fields->{T0310} ) {
        foreach my $title_item ( @{ $record->get_fields->{T0310} } ) {
            my $title_item = {
                title => $title_item->{content},
                field => "T0310"
            };
            push( @{$title_list}, $title_item );
        }
    }

    return $title_list;
}

sub process_title_rda {
    my $self           = shift;
    my $rda_field_data = shift;
    my $field_name     = shift;
    my $rda_collection = [];
    my $mult_values    = $self->get_all_mult_values($rda_field_data);
    foreach my $mult_value ( @{$mult_values} ) {
        my $currentObject = {};
        foreach my $title ( @{$rda_field_data} ) {
            if ( $title->{mult} == $mult_value ) {
                if ( $title->{subfield} eq "g" ) {
                    $currentObject->{title} = $title->{content};
                    $currentObject->{title} =~ s/^\s+//;
                }
                elsif ( $title->{subfield} eq "9"
                    and index( $title->{content}, "DE-588" ) != -1 )
                {
                    $currentObject->{gnd} = $title->{content};
                    $currentObject->{gnd} =~ s/\(DE-588\)//;
                    $currentObject->{gnd} =~ s/^\s+//;
                    $currentObject->{field} = $field_name;
                }
            }
        }
        push( @{$rda_collection}, $currentObject );
    }
    return $rda_collection;
}

sub collect_rswk_data {
    my $self          = shift;
    my $record        = shift;
    my $database      = shift;
    my $rswk_data = [];
    
    if (length( $record->get_fields->{T0902} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0902} );
    };
    if (length( $record->get_fields->{T0907} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0907} );
    };
    if (length( $record->get_fields->{T0912} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0912} );
    };
    if (length( $record->get_fields->{T0917} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0917} );
    };
    if (length( $record->get_fields->{T0922} ) ) {
        push( @{$rswk_data}, $record->get_fields->{T0922} );
    };
    return $rswk_data;
}

sub get_date_values() {
    my $self       = shift;
    my $record     = shift;
    my $database   = shift;
    my $date_values = {};
    if ($record->get_fields->{T0422}) {
        $date_values->{"start_date"} =$record->get_fields->{T0422}[0]->{content};
    }
    if ($record->get_fields->{T0423}) {
        $date_values->{"end_date"} =$record->get_fields->{T0423}[0]->{content};
    }
    if ($record->get_fields->{T0424}){
             $date_values->{"date"} =$record->get_fields->{T0424}[0]->{content}; 
    }if ($record->get_fields->{T0425}){
             $date_values->{"date_norm"} =$record->get_fields->{T0425}[0]->{content};; 
    }
    unless ($record->get_fields->{T0425}){
        if ($record->get_fields->{T0089} ){
            my $date_value = undef;
            if(index($record->get_fields->{T0089}[0]->{content}, ".") != -1){
                my @splitted_string = split('\.', $record->get_fields->{T0089}[0]->{content});
                $date_value = $splitted_string[-1];
            }else{
                $date_value = $record->get_fields->{T0089}[0]->{content};
            }
            if (index($date_value, "\/") != -1){
                unless ($date_values->{"start_date"} || index($date_value, "(") != -1){ 
                        my @splitted_date = split('\/', $date_value);
                        $date_values->{"start_date"} =$splitted_date[0];
                        $date_values->{"end_date"} =$splitted_date[1];
                        if (length($date_values->{"start_date"}) == 4 && length($date_values->{"end_date"}) == 2){
                            $date_values->{"end_date"} = substr($date_values->{"start_date"}, 0,2) . $date_values->{"end_date"} ;
                        }}
                #special cases like 10,10(1771/2003)1994 1594159
                unless (index($date_value, "(") != -1){ 
                    $date_values->{"date_norm"} = $date_value;
                }else {
                     if ($record->get_fields->{T0024}[0]->{content} && length($record->get_fields->{T0024}[0]->{content}) == 4){
                        $date_values->{"date_norm"} = $record->get_fields->{T0024}[0]->{content};
                     }
                }
            }
        }
        }
    if ($date_values->{"date"} eq $date_values->{"date_norm"} ){
            delete($date_values->{"date"});
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
    if (scalar @{$persondata} ==0) {
        #wie kann JSON geparst werden
        #http://localhost:8008/portal/openbib/connector/unapi?id=rheinabt:84411&format=oai_mods
        if ($record->get_fields->{T5005}){
            my $super_field = $record->get_field({field => "T5005"})->[0]->{"content"};
            #my $decoded = decode_json(encode_utf8($super_field)); 
            #evtl. ecnode_utf8 rausnehmen 
            my $decoded = {};
            $super_field=~s/\\"/"/g;
            eval {
                $decoded = decode_json encode_utf8($super_field);
            };
            if ($decoded->{"fields"}->{"0100"}){
                my $person_item = {
                values => $decoded->{"0100"},
                field  => "T0100"
                };
            push( @{$persondata}, $person_item );
            }
             if ($decoded->{"fields"}->{"0101"}){
                my $person_item = {
                values => $decoded->{"fields"}->{"0101"},
                field  => "T0101"
                };
            push( @{$persondata}, $person_item );
            }
            if ($decoded->{"0102"}){
                my $person_item = {
                values => $decoded->{"fields"}->{"0102"},
                field  => "T0102"
                };
            push( @{$persondata}, $person_item );
            }
            if ($decoded->{"0103"}){
                my $person_item = {
                values =>  $decoded->{"fields"}->{"0103"},
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
                gnd   => $self->get_gnd_for_person( $person->{id}, $database ),
                field => $person_sub_list->{field},
                supplement => $person->{supplement}
            };
            push( @{$personlist}, $person_item );
        }
    }
    return $personlist;

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
    #rda place data
    if ( length( $record->get_fields->{T7676} ) ) {
        my $rda_collection =
          $self->process_place_rda( $record->get_fields->{T7676}, "T7676" );
        push( @{$place_list}, @{$rda_collection} );

    }
    unless (length( $record->get_fields->{T7676} )) {
        if ( length( $record->get_fields->{T0410} ) ) {
            foreach my $place ( @{ $record->get_fields->{T0410} } ) {
                my $place_data = {
                    place_name => $place->{content},
                    field      => "T0410"
                };
                push( @{$place_list}, $place_data );
            }
        }
        else {
        if ( length( $record->get_fields->{T0673} ) ) {
            foreach my $place ( @{ $record->get_fields->{T0673} } ) {
                my $place_data = {
                    place_name => $place->{content},
                    field      => "T0673"
                };
                push( @{$place_list}, $place_data );
            }

        }
    }
    }
   
    return $place_list;
}

sub process_place_rda {
    my $self           = shift;
    my $rda_field_data = shift;
    my $field_name     = shift;
    my $rda_collection = [];
    my $mult_values    = $self->get_all_mult_values($rda_field_data);
    foreach my $mult_value ( @{$mult_values} ) {
        my $currentObject = {};
        foreach my $place ( @{$rda_field_data} ) {
            if ( $place->{mult} == $mult_value ) {
                if ( $place->{subfield} eq "g" ) {
                    $currentObject->{place_name} = $place->{content};
                    $currentObject->{place_name} =~ s/^\s+|\s+$//g;
                }
                elsif ( $place->{subfield} eq "9"
                    and index( $place->{content}, "DE-588" ) != -1 )
                {
                    $currentObject->{gnd} = $place->{content};
                    $currentObject->{gnd} =~ s/\(DE-588\)//;
                    $currentObject->{gnd} =~ s/^\s+|\s+$//g;
                    $currentObject->{field} = $field_name;
                }
            }
        }
        push( @{$rda_collection}, $currentObject );
    }
    return $rda_collection;

}

sub get_all_mult_values {
    my $self           = shift;
    my $rda_field_data = shift;
    my @mult_values    = ();
    foreach my $rda_field ( @{$rda_field_data} ) {
        my $mult_value = $rda_field->{mult};
        if (grep( /^$mult_value$/, @mult_values ) ) {
        }else {
          push( @mult_values, $mult_value );
        }

    }
    return \@mult_values;
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
                    $currentObject->{publisher_name} =~ s/^\s+|\s+$//g
                }
                if ( $publisher->{subfield} eq "h" ) {
                        $currentObject->{publisher_place} = $publisher->{content};
                        $currentObject->{publisher_place} =~ s/^\s+|\s+$//g
                }
                elsif ( $publisher->{subfield} eq "9"
                    and index( $publisher->{content}, "DE-588" ) != -1 )
                {
                    $currentObject->{gnd} = $publisher->{content};
                    $currentObject->{gnd} =~ s/\(DE-588\)//;
                    $currentObject->{gnd} =~ s/^\s+|\s+$//g
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
        if (index( $content_field, "&lt;")) {
           @full_name_array = split( "&lt;", $content_field ); 
        }else {
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
    return $namedata;

}

1;
