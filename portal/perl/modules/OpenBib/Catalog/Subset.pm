#####################################################################
#
#  OpenBib::Catalog::Subset
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 1997-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Subset;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use OpenBib::Config;
use OpenBib::Schema::Catalog;
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;

use OpenBib::Config;

sub new {
    my $class       = shift;
    my $source      = shift;
    my $destination = shift;
    
    my $self         = {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    bless ($self, $class);

    $self->{config}   = new OpenBib::Config;
    
    if ($source){
        $self->set_source($source);
    }

    if ($destination){
        $self->{destination} = $destination;
    }
    
    $self->{titleid}          = {};
    $self->{personid}         = {};
    $self->{corporatebodyid}  = {};
    $self->{subjectid}        = {};
    $self->{classificationid} = {};
    $self->{holdingid}        = {};


    return $self;
}

sub set_source {
    my $self     = shift;
    my $source = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{source} = $source;

    if ($self->{config}->{dbimodule} eq "Pg"){
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}", $self->{config}->{dbuser}, $self->{config}->{dbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $source: DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}");
            exit;
        }
    }
    elsif ($self->{config}->{dbimodule} eq "mysql"){
        eval {
            # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
            $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}", $self->{config}->{dbuser}, $self->{config}->{dbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $source: DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}");
            exit;
        }
    }
    
    return $self;
}

sub set_destination {
    my $self        = shift;
    my $destination = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{destination} = $destination;

    return $self;
}

sub set_title_filter {
    my $self          = shift;
    my $title_filter_ref = shift;

    $self->{title_filter} = $title_filter_ref;
}

sub identify_by_mark {
    my $self = shift;
    my $mark = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @marks = (ref $mark)?@$mark:($mark);

    my $config = new OpenBib::Config;
    
    my $regexp_op = ($config->{dbimodule} eq "mysql")?"rlike":
        ($config->{dbimodule} eq "Pg")?"~":"rlike";
    
    foreach my $thismark (@marks){
        $logger->debug("Searching for Mark $thismark");
        
        # DBI: "select distinct conn.sourceid as titid from conn,holding where holding.category=14 and holding.content COLLATE utf8_bin rlike ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6"
        my $titles = $self->{schema}->resultset('TitleHolding')->search_rs(
            {
                'holding_fields.field' => 14,
                'holding_fields.content' => { $regexp_op => $mark },
            },
            {
                select   => ['me.titleid'],
                as       => ['thistitleid'],
                join     => ['holdingid', {'holdingid' => 'holding_fields' }],
                group_by => ['me.titleid'],
            }
        );
        
        foreach my $item ($titles->all){
            my $titleid = $item->get_column('thistitleid');
            
            $self->{titleid}{$titleid} = 1;
        }
    }
    
    my $count=0;
    
    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }
    
    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");
    
    $self->get_title_hierarchy;
    
    $self->get_title_normdata;
    
    foreach my $thismark (@marks){
        # Exemplardaten *nur* vom entsprechenden Institut!
        # DBI: "select distinct id from holding where category=14 and content rlike ?"
        my $holdings = $self->{schema}->resultset('Holding')->search_rs(
            {
                'holding_fields.field' => 14,
                'holding_fields.content' => { $regexp_op => $mark },
            },
            {
                select   => ['me.id'],
                as       => ['thisholdingid'],
                join     => ['holding_fields'],
                group_by => ['me.id'],
            }
        );
        
        foreach my $item ($holdings->all){
            my $holdingid = $item->get_column('thisholdingid');
            
            $self->{holdingid}{$holdingid} = 1;
        }
    }
    
    return $self;
}
        
sub identify_by_category_content {
    my $self    = shift;
    my $table   = shift;
    my $arg_ref = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config;
    
    my %table_type = (
        'person'         => {
            resultset => 'TitlePerson',
            field => 'person_fields.field',
            join => ['personid', { 'personid' => 'person_fields' }]
        },
        'corporatebody'  => {
            resultset => 'TitleCorporatebody',
            field => 'corporatebody_fields.field',
            join => ['corporatebodyid', { 'corporatebodyid' => 'corporatebody_fields' }]
        },
        'subject'        => {
            resultset => 'TitleSubject',
            field => 'subject_fields.field',
            join => ['subjectid', { 'subjectid' => 'subject_fields' }]
        },
        'classification' => {
            resultset => 'TitleClassification',
            field => 'classification_fields.field',
            join => ['classificationid', { 'classificationid' => 'classification_fields' }]
        },
        'holding' => {
            resultset => 'TitleHolding',
            field => 'holding_fields.field',
            join => ['holdingid', { 'holdingid' => 'holding_fields' }]
        },

    );

    my $regexp_op = ($config->{dbimodule} eq "mysql")?"rlike":
        ($config->{dbimodule} eq "Pg")?"~":"rlike";

    foreach my $criteria_ref (@$arg_ref){        
        # DBI: "select distinct id as titleid from $table where category = ? and content rlike ?") or $logger->error($DBI::errstr);
        my $titles = $self->{schema}->resultset('TitleField')->search_rs(
            {
                'field'   => $criteria_ref->{category},
                'content' => { $regexp_op => $criteria_ref->{content} },
            },
            {
                select   => ['titleid'],
                as       => ['thisid'],
            }
        );
        
        if ($table ne "title"){
            # DBI: "select distinct conn.sourceid as titleid from conn,$table where $table.category = ? and $table.content rlike ? and conn.targetid=$table.id and conn.sourcetype=1 and conn.targettype=$table_type{$table}");
            $titles = $self->{schema}->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => $criteria_ref->{category},
                    'content' => { $regexp_op => $criteria_ref->{content} },
                },
                {
                    select   => ['me.titleid'],
                    as       => ['thisid'],
                    join     => $table_type{$table}{join},
                }
            );
        }

        foreach my $item ($titles->all){
            my $thisid = $item->get_column('thisid');
        
            $self->{titleid}{$thisid} = 1;
        }
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    $self->get_title_hierarchy;

    $self->get_title_normdata;

    # Exemplardaten
    # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=6"

    foreach my $id (keys %{$self->{titleid}}){
        my $holdings = $self->{schema}->resultset('TitleHolding')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['holdingid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($holdings->all){
            my $thisid = $item->get_column('thisid');

            $self->{holdingid}{$thisid}=1;
        }    
    }

    return $self;
}

sub identify_by_olws_circulation {
    my $self    = shift;
    my $arg_ref = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $soap = SOAP::Lite
        -> uri($arg_ref->{urn})
            -> proxy($arg_ref->{proxy});
    my $result = $soap->get_idn_of_borrows($arg_ref->{soap_params});
    
    my $circexlist=undef;

    unless ($result->fault) {
        $circexlist=$result->result;
    }
    else {
        $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode,
    $result->faultstring, $result->faultdetail);
        return;
    }

    
    my @circexemplarliste=@$circexlist;
    
    foreach my $singleex_ref (@circexemplarliste) {
        $self->{titleid}{$singleex_ref->{'Katkey'}}=1;
    }

    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    $self->get_title_hierarchy;

    $self->get_title_normdata;

    # Exemplardaten
    # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=6"

    foreach my $id (keys %{$self->{titleid}}){
        my $holdings = $self->{schema}->resultset('TitleHolding')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['holdingid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($holdings->all){
            my $thisid = $item->get_column('thisid');

            $self->{holdingid}{$thisid}=1;
        }    
    }
    
    return $self;
}

sub get_title_hierarchy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->info("### $self->{source} -> $self->{destination}: Bestimme uebergeordnete Titel");

    my %tmp_titleid_super = %{$self->{titleid}};

    my $level = 0;
    
    while (keys %tmp_titleid_super){
        $logger->info("### Ueberordnungen - neuer Durchlauf in Ebene $level");
        
        if ($level > 20){
            print "### Ueberordnungen - Abbbruch ! Ebene $level erreicht\n";
            last;
        }    
        
        my %found = ();
        
        foreach my $titidn (keys %tmp_titleid_super){
            
            # Ueberordnungen
            # DBI: "select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1"
            my $supertitles = $self->{schema}->resultset('TitleTitle')->search_rs(
                {
                    'source_titleid' => $titidn,
                },
                {
                    select   => ['target_titleid'],
                    as       => ['supertitleid'],
                    group_by => ['target_titleid'],
                }
            );

            foreach my $item ($supertitles->all){
                my $supertitleid = $item->get_column('supertitleid');

                $self->{titleid}{$supertitleid} = 1;
                if ($titidn != $supertitleid){ # keine Ringschluesse - ja, das gibt es
                    $found{$supertitleid}   = 1;
                }                
            }            
        }        
        %tmp_titleid_super = %found;

        $level++;
        
        $logger->debug("Verbliebene TitelID's: ".join(',',keys %tmp_titleid_super));
    } 

    return $self;
}

sub get_title_normdata {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # IDN's der Autoren, Koerperschaften, Schlagworte, Notationen bestimmen

    $logger->debug("### $self->{source} -> $self->{destination}: Bestimme Normdaten");

    foreach my $id (keys %{$self->{titleid}}){
        
        # Verfasser/Personen
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=2"
        my $persons = $self->{schema}->resultset('TitlePerson')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['personid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($persons->all){
            my $thisid = $item->get_column('thisid');

            $self->{personid}{$thisid}=1;
        }
        
        # Urheber/Koerperschaften
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=3
        my $corporatebodies = $self->{schema}->resultset('TitleCorporatebody')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['corporatebodyid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($corporatebodies->all){
            my $thisid = $item->get_column('thisid');

            $self->{corporatebodyid}{$thisid}=1;
        }
        
        # Notationen
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=5"
        my $classifications = $self->{schema}->resultset('TitleClassification')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['classificationid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($classifications->all){
            my $thisid = $item->get_column('thisid');

            $self->{classificationid}{$thisid}=1;
        }
        
        # Schlagworte
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=4"
        my $subjects = $self->{schema}->resultset('TitleSubject')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['subjectid'],
                as       => ['thisid'],
            }
        );
        
        foreach my $item ($subjects->all){
            my $thisid = $item->get_column('thisid');

            $self->{subjectid}{$thisid}=1;
        }
    }

    return $self;
}

sub write_set {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->{source} eq $self->{destination}){

        $logger->fatal("Ursprungs- und Zielkatalog muessen verschieden sein.");
        
        return $self;
    }

    if (! keys %{$self->{titleid}}){
        $logger->info("### $self->{source} -> $self->{destination}: Keine Titel vorhanden - Abbruch!");
        return;
    }
    
    $logger->info("### $self->{source} -> $self->{destination}: Schreibe Meta-Daten");

    my $rootdir=$self->{config}->{'autoconv_dir'};
    my $pooldir=$rootdir."/pools";

    my $id;
    
    # Autoren
    {
        open(PERSON,"gzip -dc $pooldir/$self->{source}/meta.person.gz|");
        open(PERSONOUT,"| gzip > $pooldir/$self->{destination}/meta.person.gz");
        
        while (<PERSON>){
            
            if (/^0000:(\S+)/){
                $id=$1;
            }
            
            if (defined $self->{personid}{$id} && $self->{personid}{$id} == 1){
                print PERSONOUT $_;
            }
        }
        
        close(PERSON);
        close(PERSONOUT);
    }

    # Koerperschaften
    {
        open(CORPORATEBODY,"gzip -dc $pooldir/$self->{source}/meta.corporatebody.gz|");
        open(CORPORATEBODYOUT,"| gzip > $pooldir/$self->{destination}/meta.corporatebody.gz");
        
        while (<CORPORATEBODY>){
            
            if (/^0000:(\S+)/){
                $id=$1;
            }
            
            if (defined $self->{corporatebodyid}{$id} && $self->{corporatebodyid}{$id} == 1){
                print CORPORATEBODYOUT $_;
            }
        }
        
        close(CORPORATEBODY);
        close(CORPORATEBODYOUT);
    }
    
    # Notationen
    {
        open(CLASSIFICATION,"gzip -dc $pooldir/$self->{source}/meta.classification.gz|");
        open(CLASSIFICATIONOUT,"| gzip > $pooldir/$self->{destination}/meta.classification.gz");
        
        while (<CLASSIFICATION>){
            
            if (/^0000:(\S+)/){
                $id=$1;
            }
            
            if (defined $self->{classificationid}{$id} && $self->{classificationid}{$id} == 1){
                print CLASSIFICATIONOUT $_;
            }
        }
        
        close(CLASSIFICATION);
        close(CLASSIFICATIONOUT);
    }
    
    # Schlagworte
    {
        open(SUBJECT,"gzip -dc $pooldir/$self->{source}/meta.subject.gz|");
        open(SUBJECTOUT,"| gzip > $pooldir/$self->{destination}/meta.subject.gz");
        
        while (<SUBJECT>){
            
            if (/^0000:(\S+)/){
                $id=$1;
            }
            
            if (defined $self->{subjectid}{$id} && $self->{subjectid}{$id} == 1){
                print SUBJECTOUT $_;
            }
        }
        
        close(SUBJECT);
        close(SUBJECTOUT);
    }
    
    # Titeldaten
    {
        open(TITLE,"gzip -dc $pooldir/$self->{source}/meta.title.gz|");
        open(TITLEOUT,"| gzip > $pooldir/$self->{destination}/meta.title.gz");
        
        while (<TITLE>){
            
            if (/^0000:(\S+)/){
                $id=$1;
            }
            
            if (defined $self->{titleid}{$id} && $self->{titleid}{$id} == 1){
                if (exists $self->{title_filter}){
                    &{$self->{title_filter}}($_,*TITLEOUT);
                }
                print TITLEOUT $_;
            }
        }
        
        close(TITLE);
        close(TITLEOUT);
    }
    
    # Exemplardaten
    {
        open(HOLDING,"gzip -dc $pooldir/$self->{source}/meta.holding.gz|");
        open(HOLDINGOUT,"| gzip > $pooldir/$self->{destination}/meta.holding.gz");
        
        my $mexbuffer="";
        
        while (<HOLDING>){
            if (/^0000:(\d+)/){
                $id=$1;
            }
            
            if (defined $self->{holdingid}{$id} && $self->{holdingid}{$id} == 1){
                print HOLDINGOUT $_;
            }
        }
        
        close(HOLDING);
        close(HOLDINGOUT);
    }    
    
}

1;
