#####################################################################
#
#  OpenBib::Enrichment
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Enrichment;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Class::Singleton);

use DB_File ;
use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use MLDBM qw(DB_File Storable);
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Schema::Enrichment::Singleton;
use OpenBib::Record::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB($arg_ref);
    
    return $self;
}

sub get_db_histogram_of_occurence {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $content           = exists $arg_ref->{content}
        ? $arg_ref->{content}        : undef;
    my $category          = exists $arg_ref->{category}
        ? $arg_ref->{category}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);

    return () unless (defined $content && defined $category && defined $dbh);
    
    my $request=$dbh->prepare("select dbname,count(id) as idcount from all_isbn as i,normdata as n where n.category=? and n.content=? and n.isbn=i.isbn group by dbname order by idcount DESC") or $logger->error($DBI::errstr);
    $request->execute($category,$content) or $logger->error($DBI::errstr);

    my $histogram_ref = {
        content => $content,
    };
    
    while (my $result=$request->fetchrow_hashref){
        my $count  = $result->{idcount};
        my $dbname = $result->{dbname};
        push @{$histogram_ref->{histogram}}, {
            dbname => $dbname ,
            count  => $count,
        };

        $histogram_ref->{count}=$histogram_ref->{count}+1;
    }

    $dbh->disconnect;
    
    return $histogram_ref;
}

sub get_enriched_content {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;
    my $issn              = exists $arg_ref->{issn}
        ? $arg_ref->{issn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    return {} unless (defined $isbn || defined $issn);

    $issn = OpenBib::Common::Util::to_issn($issn);

    # Normierung auf ISBN13
    $isbn = OpenBib::Common::Util::to_isbn13($isbn);

    my $normset_ref = {};

    my $titles;
    
    if ($isbn){
        $titles = $self->{schema}->resultset('EnrichedContentByIsbn')->search(
            {
                isbn => $isbn,
            },
            {
                select => ['field','content'],
                group_by => ['field','content','subfield','origin'],
                order_by => ['field','subfield'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
    }
    elsif ($issn){
        $titles = $self->{schema}->resultset('EnrichedContentByIsbn')->search(
            {
                issn => $issn,
            },
            {
                select => ['field','content'],
                group_by => ['field','content','mult','subfield','origin'],
                order_by => ['field','subfield'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
    }

    # Anreicherung der Normdaten
    while (my $title=$titles->next()) {
        my $field      = "E".sprintf "%04d",$title->{field};
        my $content    =                    $title->{content};

        push @{$normset_ref->{$field}}, $content;
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($normset_ref));
    }

    return $normset_ref;

}

sub get_similar_isbns {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn          = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} unless (defined $isbn && defined $dbh);

    # Normierung auf ISBN13
    $isbn = OpenBib::Common::Util::to_isbn13($isbn);

    my $reqstring="select isbn from similar_isbn where match (isbn) against (?)";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
    my $similar_isbn_ref = {};
    while (my $res=$request->fetchrow_hashref) {
        my $similarisbnstring = $res->{isbn};
        foreach my $similarisbn (split(':',$similarisbnstring)){
            $similar_isbn_ref->{$similarisbn}=1 if ($similarisbn ne $isbn);
        }
    }

    $dbh->disconnect;
    
    return $similar_isbn_ref;
}

sub get_all_holdings {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn          = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} unless (defined $isbn && defined $dbh);

    # Normierung auf ISBN13
    $isbn = OpenBib::Common::Util::to_isbn13($isbn);

    my $reqstring="select isbn from all_isbn where isbn=?";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
    my $all_isbn_ref = [] ;
    while (my $res=$request->fetchrow_hashref) {
        push @{$all_isbn_ref}, {
            $res->{dbname},
            $res->{id},
        };
    }

    $dbh->disconnect;
    
    return $all_isbn_ref;
}

sub check_availability_by_isbn {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn_ref       = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}             : [];

    my $databases_ref  = exists $arg_ref->{databases}
        ? $arg_ref->{databases}        : [];

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Checking ISBNs ".join(' ',@$isbn_ref)." in databases ".join(' ',@$databases_ref));
    
    return 0 unless ($isbn_ref && $databases_ref);

    my $is_available =  0;

    my $dbname_args = [];

    foreach my $dbname (@$databases_ref){
        push @$dbname_args, {
            dbname => $dbname,
        };
    }
    
    foreach my $isbn (@$isbn_ref){
        # Normierung auf ISBN13
        my $isbn13 = OpenBib::Common::Util::to_isbn13($isbn);

        my $title_count = $self->{schema}->resultset('AllTitleByIsbn')->search_rs(
            {
                isbn => $isbn13,
                -or => $dbname_args,
                    
            }
        )->count;

        $is_available+=$title_count;
    }

    return $is_available;
}

sub enriched_content_to_bdb {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $filename       = exists $arg_ref->{filename}
        ? $arg_ref->{filename}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Ininitalisierung mit Default Config-Parametern

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    # Ininitalisierung mit Config-Parametern
    my $conv_config = YAML::Syck::LoadFile("/opt/openbib/conf/convert.yml");

    my $local_fields_ref = {};

    foreach my $thisconfig (keys %$conv_config){
        if (defined $conv_config->{$thisconfig}{local_enrichmnt}){
            foreach my $field (keys %{$conv_config->{$thisconfig}{local_enrichmnt}}){
                $local_fields_ref->{$field} = 1;
            }
        }
    }

    my $in_string = join "','", keys %{$local_fields_ref};

        
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} unless (defined $filename && defined $dbh);

    my %enrichmntdata;

    unlink $filename;
    
    tie %enrichmntdata,           'MLDBM', $filename,
        or die "Could not tie enrichment data.\n";

    my $sql_request = "select * from enriched_content_by_isbn";

    $sql_request.=" where field in ('$in_string')" if ($in_string);
    
    my $request = $dbh->prepare($sql_request);
    $request->execute();

    while (my $result = $request->fetchrow_hashref){
        my $isbn     = $result->{isbn};
        my $field    = $result->{field};
        my $content  = $result->{content};

        if (! defined $enrichmntdata{$isbn}){
            $enrichmntdata{$isbn} = {
                "$field" => [ $content ],
            } ;
#            print "adding new field $field with content $content\n";
            next;
        }

        if (! defined $enrichmntdata{$isbn}{$field}){
            my $old_content_ref = $enrichmntdata{$isbn};

#            print YAML::Dump($old_content_ref),":\n";
            $old_content_ref->{$field} = [ $content ];

            $enrichmntdata{$isbn} = $old_content_ref;
            
#            print "adding new content $content to field $field;\n";
            next;
        }

        my $old_content_ref = $enrichmntdata{$isbn};

        push @{$old_content_ref->{$field}}, $content;

        $enrichmntdata{$isbn} = $old_content_ref;

#        print "adding content $content to existing field $field;\n";
    }

#    print YAML::Dump(\%enrichmntdata);
    
    $dbh->disconnect;

    return;
}

sub get_common_holdings {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $selector            = exists $arg_ref->{selector}
        ? $arg_ref->{selector}         : "ISBN13";

    my $databases_ref       = exists $arg_ref->{databases}
        ? $arg_ref->{databases}        : ();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or $logger->error_die($DBI::errstr);

    return () unless (@{$databases_ref} && defined $dbh);

    my $common_holdings_ref = [];

    my %all_by_matchkey             = ();

    my $in_select_string = join(',',map {'?'} @{$databases_ref});
    
    my $sql_string = ($selector eq "ISBN13")?"select * from all_titles_by_isbn where dbname in ($in_select_string)":
        ($selector eq "ISSN")?"select * from all_titles_by_issn where dbname in ($in_select_string)":
            ($selector eq "BibKey")?"select * from all_titles_by_bibkey where dbname in ($in_select_string)":"select * from all_titles_by_isbn where dbname in ($in_select_string)";
    
    $logger->debug($sql_string);
    
    my $request=$dbh->prepare($sql_string) or $logger->error($DBI::errstr);
    
    $request->execute(@{$databases_ref}) or $logger->error($DBI::errstr);;

    my $matchkey_column = ($selector eq "ISBN13")?'isbn':
        ($selector eq "ISSN")?'issn':
            ($selector eq "BibKey")?'bibkey':'isbn';

    $logger->debug("Matchkey Column for Selector $selector is $matchkey_column");
    
    while (my $result=$request->fetchrow_hashref){
            
        if ($result->{titleid} && !defined $all_by_matchkey{$result->{$matchkey_column}}{$result->{dbname}} ){
            $all_by_matchkey{$result->{$matchkey_column}}{$result->{dbname}} = [ $result->{titleid} ];
        }
        elsif ($result->{titleid}) {
            push @{$all_by_matchkey{$result->{$matchkey_column}}{$result->{dbname}}}, $result->{titleid};
        }
    }
    
    # Einzelbestaende entfernen
    foreach my $matchkey (keys %all_by_matchkey){
        my @owning_dbs = keys %{$all_by_matchkey{$matchkey}};

        if ($#owning_dbs > 0){
            $logger->debug("$matchkey - $#owning_dbs - ".join(" ; ",@owning_dbs));
        }
        
        if ($#owning_dbs < 1){
            delete($all_by_matchkey{$matchkey});
        }
    }

    foreach my $matchkey (keys %all_by_matchkey){
        my $this_item_ref = {};
        
        my $persons = "";
        my $title   = "";
        foreach my $database (@{$databases_ref}){
            if (exists $all_by_matchkey{$matchkey}{$database}){
                my @signaturen = ();
                foreach my $id (@{$all_by_matchkey{$matchkey}{$database}}){
                    my $record=OpenBib::Record::Title->new({database => $database, id => $id})->load_brief_record->get_fields;
                    if (!$persons){
                        $persons=$record->{PC0001}[0]{content};
                    }
                    
                    if (!$title){
                        $title=$record->{T0331}[0]{content};
                    }
                    foreach my $signature_ref (@{$record->{X0014}}){
                        push @signaturen, $signature_ref->{content};
                    }
                }
                $this_item_ref->{$database}{loc_mark} = join(" ; ",@signaturen);
            }
            else {
                $this_item_ref->{$database}{loc_mark} = "";
            }
        }

        $this_item_ref->{$selector}  = $matchkey;
        $this_item_ref->{persons}    = $persons;
        $this_item_ref->{title}      = $title;

        if ($logger->is_debug){
            $logger->debug(YAML::Dump($this_item_ref));
        }
        
        push @{$common_holdings_ref}, $this_item_ref;
    }

    $dbh->disconnect;
    
    return $common_holdings_ref;
}

sub connectDB {
    my $self = shift;
    my $arg_ref = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if (defined $arg_ref->{enrichmntdbname} && $arg_ref->{enrichmntdbname}){
        $config->{enrichmntdbname} = $arg_ref->{enrichmntdbname};
    }

    if ($self->{'enrichmntdbsingleton'}){
        eval {        
            $self->{schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd}) or $logger->error_die($DBI::errstr);
#            $self->{schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $self->{enrichmntdbname}");
        }
    }
    else {
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            #        $self->{schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},{'pg_enable_utf8'    => 1 }) or $logger->error_die($DBI::errstr);
            $self->{schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $config->{enrichmntdbname}: DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}");
        }

    }
    
    return;    
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{schema}){
        eval {
            $self->{schema}->storage->dbh->disconnect;
        };

        if ($@){
            $logger->error($@);
        }
    }

    return;
}

1;
__END__

=head1 NAME

OpenBib::Enrichment - Singleton für den Zugriff auf
Informationen in der zugehörigen Anreicherungs-Datenbank.

=head1 DESCRIPTION

Dieses Singleton bietet einen Zugriff auf die Informationen in
der Anreicherungsdatenbank. Diese lassen sich z.B. in den Templates
über $config->get_enrichmnt_object verwenden.

=head1 SYNOPSIS

 use OpenBib::Enrichment;

 my $enrich = OpenBib::Enrichment->new;

 my $enriched_normdata_ref = $enrich->get_additional_normdata({ isbn => '3-540-43645-6'})

 my $histogram_ref         = $enrich->get_db_histogram_of_occurence({ field => '4200', content => 'Perl'});

 my $similar_isbn_ref      = $enrich->get_similar_isbns({ isbn => '3-540-43645-6' })

 my $commons_holdings_ref  = $enrich->get_common_holdings({ selector => 'ISBN13' databases => ['inst103','inst106'] });

=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=item get_additional_normdata({ isbn => $isbn})

Liefert eine Hashreferenz nach Kategorienummern auf alle
Anreicherungsinhalte zur ISBN $isbn.

=item get_similar_isbns({ isbn => $isbn })

Liefert eine Listenreferenz auf alle ähnliche Ausgaben (andere
Sprache, Auflage, ...) des Werkes mit der ISBN $isbn.

=item get_db_histogram_of_occurence({ field => $field, content => $content })

Entsprechend das Anreicherungsinhaltes $content in der Kategorie
$field wird entsprechen der ISBN eine Abgleich mit allen Titeln in
allen Datenbanken und ein Histogram in Form einer Hashreferenz auf den
Inhalt content sowie eine Listenreferenz histogram mit den
Informationen über die Datenbank dbname und der dortigen Anzahl count.

=item get_common_holdings({ selector => $selector, databases => $databases_ref })

Entsprechend des Kriteriums $selector (Werte: ISBN13, ISSN, BibKey) werden die Datenbanken
$databases_ref miteinander abgeglichen, um gemeinsamen Besitz zu ermitteln. Hat mehr als eine
Datenbank einen Titel, so werden die Informationen "Wert des Selektor", Signaturen pro
Datenbank, Personen und Titel als Hash-Referenz in einer Array-Referenz abgelegt. Diese
Array-Referenz wird als Ergebnis zurückgeliefert.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
