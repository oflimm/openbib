#####################################################################
#
#  OpenBib::Catalog::Subset
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 1997-2020 Oliver Flimm <flimm@openbib.org>
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
use DBIx::Class::ResultClass::HashRefInflator;
use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);

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

    $self->{exclude_titleid}  = {};

    return $self;
}

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }
    else {
        $logger->fatal("No Schema defined!");
    }
    
    return;
}

sub set_source {
    my $self     = shift;
    my $source   = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{source} = $source;

    my $catalog = new OpenBib::Catalog({ database => $source });

    $self->{schema} = $catalog->get_schema;

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

    # Default: Eingrenzung der Exemplare auf genaus diese Signaturen. Daher merken 
    $self->{restrict_marks} = \@marks;
    
    my $config = new OpenBib::Config;
    
    foreach my $thismark (@marks){
        $logger->debug("Searching for Mark $thismark");
        
        # DBI: "select distinct conn.sourceid as titleid from conn,holding where holding.category=14 and holding.content COLLATE utf8_bin rlike ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6"
        my $titles = $self->get_schema->resultset('TitleHolding')->search_rs(
            {
                'holding_fields.field' => 14,
                'holding_fields.content' => { '~*' => $thismark },
            },
            {
                select   => ['titleid.id'],
                as       => ['thistitleid'],
                join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
                group_by => ['titleid.id'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );

	$logger->info("### $self->{source} -> $self->{destination}: ".$titles->count." Titel mit $thismark");
	
        while (my $item = $titles->next){
            my $titleid = $item->{thistitleid};
            
            $self->{titleid}{$titleid} = 1;
        }
    }
    
    my $count=0;
    
    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }
    
    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    if (keys %{$self->{exclude_titleid}}){
	$logger->info("### $self->{source} -> $self->{destination}: Titel ignorieren");
	
	foreach my $key (keys %{$self->{exclude_titleid}}){
	    delete $self->{titleid}{$key};
	}
    }
    
    $self->get_title_hierarchy;
    
    $self->get_title_normdata;
    
    foreach my $thismark (@marks){
        # Exemplardaten *nur* vom entsprechenden Institut!
        # DBI: "select distinct id from holding where category=14 and content rlike ?"
        my $holdings = $self->get_schema->resultset('Holding')->search_rs(
            {
                'holding_fields.field' => 14,
                'holding_fields.content' => { '~*' => $thismark },
            },
            {
                select   => ['me.id'],
                as       => ['thisholdingid'],
                join     => ['holding_fields'],
                group_by => ['me.id'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $holdings->next){
            my $holdingid = $item->{thisholdingid};
            
            $self->{holdingid}{$holdingid} = 1;
        }
    }
    
    return $self;
}
        
sub identify_by_field_content {
    my $self    = shift;
    my $table   = shift;
    my $arg_ref = shift;
    my $mode    = shift || '';
    
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

    my $first_criteria = 1;
    my %title_a = ();
    my %title_b = ();
    
    foreach my $criteria_ref (@$arg_ref){        
        # DBI: "select distinct id as titleid from $table where category = ? and content rlike ?") or $logger->error($DBI::errstr);
        my $titles = $self->get_schema->resultset('TitleField')->search_rs(
            {
                'field'   => $criteria_ref->{field},
                'content' => { '~*' => $criteria_ref->{content} },
            },
            {
                select   => ['titleid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        if ($table ne "title"){
            # DBI: "select distinct conn.sourceid as titleid from conn,$table where $table.category = ? and $table.content rlike ? and conn.targetid=$table.id and conn.sourcetype=1 and conn.targettype=$table_type{$table}");
            $titles = $self->get_schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => $criteria_ref->{field},
                    'content' => { '~*' => $criteria_ref->{content} },
                },
                {
                    select   => ['me.titleid'],
                    as       => ['thisid'],
                    join     => $table_type{$table}{join},
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
        }

        if ($mode eq "all" && $first_criteria){
            $first_criteria = 0;
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                $title_a{$thisid} = 1;
            }            
        }
        elsif ($mode eq "all" && !$first_criteria){
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                if ($title_a{$thisid} == 1){
                    $title_b{$thisid} = 1;
                }
            }
            %title_a = %title_b;
        }
        else {
            foreach my $item ($titles->all){
                my $thisid = $item->{'thisid'};
                
                $self->{titleid}{$thisid} = 1;
            }
        }
    }

    if ($mode eq "all"){
        $self->{titleid} = \%title_a;
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    return $self;
}

sub exclude_by_mark {
    my $self = shift;
    my $mark = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @marks = (ref $mark)?@$mark:($mark);

    my $config = new OpenBib::Config;
    
    foreach my $thismark (@marks){
        $logger->debug("Searching for Mark $thismark");
        
        # DBI: "select distinct conn.sourceid as titleid from conn,holding where holding.category=14 and holding.content COLLATE utf8_bin rlike ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6"
        my $titles = $self->get_schema->resultset('TitleHolding')->search_rs(
            {
                'holding_fields.field' => 14,
                'holding_fields.content' => { '~*' => $thismark },
            },
            {
                select   => ['titleid.id'],
                as       => ['thistitleid'],
                join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
                group_by => ['titleid.id'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );

	$logger->info("### $self->{source} -> $self->{destination}: ".$titles->count." Titel mit $thismark");
	
        while (my $item = $titles->next){
            my $titleid = $item->{thistitleid};
            
            $self->{exclude_titleid}{$titleid} = 1;
        }
    }
    
    my $count=0;
    
    foreach my $key (keys %{$self->{exclude_titleid}}){
        $count++;
    }
    
    $logger->info("### $self->{source} -> $self->{destination}: Ignorierte Titel-ID's $count");
    
    return $self;
}

sub exclude_by_field_content {
    my $self    = shift;
    my $table   = shift;
    my $arg_ref = shift;
    my $mode    = shift || '';
    
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

    my $first_criteria = 1;
    my %title_a = ();
    my %title_b = ();
    
    foreach my $criteria_ref (@$arg_ref){        
        # DBI: "select distinct id as titleid from $table where category = ? and content rlike ?") or $logger->error($DBI::errstr);
        my $titles = $self->get_schema->resultset('TitleField')->search_rs(
            {
                'field'   => $criteria_ref->{field},
                'content' => { '~*' => $criteria_ref->{content} },
            },
            {
                select   => ['titleid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        if ($table ne "title"){
            # DBI: "select distinct conn.sourceid as titleid from conn,$table where $table.category = ? and $table.content rlike ? and conn.targetid=$table.id and conn.sourcetype=1 and conn.targettype=$table_type{$table}");
            $titles = $self->get_schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => $criteria_ref->{field},
                    'content' => { '~*' => $criteria_ref->{content} },
                },
                {
                    select   => ['me.titleid'],
                    as       => ['thisid'],
                    join     => $table_type{$table}{join},
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
        }

        if ($mode eq "all" && $first_criteria){
            $first_criteria = 0;
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                $title_a{$thisid} = 1;
            }            
        }
        elsif ($mode eq "all" && !$first_criteria){
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                if ($title_a{$thisid} == 1){
                    $title_b{$thisid} = 1;
                }
            }
            %title_a = %title_b;
        }
        else {
            foreach my $item ($titles->all){
                my $thisid = $item->{'thisid'};
                
                $self->{exclude_titleid}{$thisid} = 1;
            }
        }
    }

    if ($mode eq "all"){
        $self->{exclude_titleid} = \%title_a;
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{exclude_titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Ignorierte Titel-ID's $count");

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
            print "### Ueberordnungen - Abbbruch ! Ebene $level erreicht fuer Titel ".join(";",keys %tmp_titleid_super)."\n";
            last;
        }    
        
        my %found = ();
        
        foreach my $titleid (keys %tmp_titleid_super){
            
            # Ueberordnungen
            # DBI: "select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1"
            my $supertitles = $self->get_schema->resultset('TitleTitle')->search_rs(
                {
                    'source_titleid' => $titleid,
                },
                {
                    select   => ['target_titleid'],
                    as       => ['supertitleid'],
                    group_by => ['target_titleid'],
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );

            while (my $item = $supertitles->next){
                my $supertitleid = $item->{supertitleid};

                $self->{titleid}{$supertitleid} = 1;
                if ($titleid != $supertitleid){ # keine Ringschluesse - ja, das gibt es
                    $found{$supertitleid}   = 1;
                }                
            }            
        }        
        %tmp_titleid_super = %found;

        $level++;
        
        if ($logger->is_debug){
            $logger->debug("Verbliebene TitelID's: ".join(',',keys %tmp_titleid_super));
        }
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
        my $persons = $self->get_schema->resultset('TitlePerson')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['personid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $persons->next){
            my $thisid = $item->{thisid};

            $self->{personid}{$thisid}=1;
        }
        
        # Urheber/Koerperschaften
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=3
        my $corporatebodies = $self->get_schema->resultset('TitleCorporatebody')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['corporatebodyid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $corporatebodies->next){
            my $thisid = $item->{thisid};

            $self->{corporatebodyid}{$thisid}=1;
        }
        
        # Notationen
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=5"
        my $classifications = $self->get_schema->resultset('TitleClassification')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['classificationid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $classifications->next){
            my $thisid = $item->{thisid};

            $self->{classificationid}{$thisid}=1;
        }
        
        # Schlagworte
        # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=4"
        my $subjects = $self->get_schema->resultset('TitleSubject')->search_rs(
            {
                'titleid' => $id,
            },
            {
                select   => ['subjectid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $subjects->next){
            my $thisid = $item->{thisid};

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

    if (keys %{$self->{exclude_titleid}}){
	$logger->info("### $self->{source} -> $self->{destination}: Titel ignorieren");
	
	foreach my $key (keys %{$self->{exclude_titleid}}){
	    delete $self->{titleid}{$key};
	}
    }
    
    $self->get_title_hierarchy;

    $self->get_title_normdata;

    # Exemplardaten
    # DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=6"

    if (defined $self->{restrict_marks} && @{$self->{restrict_marks}}){
	foreach my $thismark (@{$self->{restrict_marks}}){
	    # Exemplardaten *nur* vom entsprechenden Institut!
	    # DBI: "select distinct id from holding where category=14 and content rlike ?"
	    my $holdings = $self->get_schema->resultset('Holding')->search_rs(
		{
		    'holding_fields.field' => 14,
			'holding_fields.content' => { '~*' => $thismark },
		},
		{
		    select   => ['me.id'],
		    as       => ['thisholdingid'],
		    join     => ['holding_fields'],
		    group_by => ['me.id'],
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
		}
		);
	    
	    while (my $item = $holdings->next){
		my $holdingid = $item->{thisholdingid};
		
		$self->{holdingid}{$holdingid} = 1;
	    }
	}
    }
    else {
	# Exemplardaten
	# DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=6"
	
	foreach my $id (keys %{$self->{titleid}}){
	    my $holdings = $self->get_schema->resultset('TitleHolding')->search_rs(
		{
		    'titleid' => $id,
		},
		{
		    select   => ['holdingid'],
		    as       => ['thisid'],
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
		}
		);
	    
	    while (my $item = $holdings->next){
		my $thisid = $item->{thisid};
		
		$self->{holdingid}{$thisid}=1;
	    }    
	}
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
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};
            
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
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};
            
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
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};

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
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};

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
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};

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
        
        while (<HOLDING>){
            my $record_ref = decode_json $_;
            my $id         = $record_ref->{id};
            
            if (defined $self->{holdingid}{$id} && $self->{holdingid}{$id} == 1){
                print HOLDINGOUT $_;
            }
        }
        
        close(HOLDING);
        close(HOLDINGOUT);
    }    
    
}


sub titleid_by_field_content {
    my $self    = shift;
    my $table   = shift;
    my $arg_ref = shift;
    my $mode    = shift || '';
    
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

    my $first_criteria = 1;
    my %title_a = ();
    my %title_b = ();

    foreach my $criteria_ref (@$arg_ref){
        my $operator = ($criteria_ref->{operator})?$criteria_ref->{operator}:'~*';
        
        # DBI: "select distinct id as titleid from $table where category = ? and content rlike ?") or $logger->error($DBI::errstr);
        my $titles = $self->get_schema->resultset('TitleField')->search_rs(
            {
                'field'   => $criteria_ref->{field},
                'content' => { $operator => $criteria_ref->{'content'} },
            },
            {
                select   => ['titleid'],
                as       => ['thisid'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        if ($table ne "title"){
            # DBI: "select distinct conn.sourceid as titleid from conn,$table where $table.category = ? and $table.content rlike ? and conn.targetid=$table.id and conn.sourcetype=1 and conn.targettype=$table_type{$table}");
            $titles = $self->get_schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => $criteria_ref->{field},
                    'content' => { $operator => $criteria_ref->{'content'} },
                },
                {
                    select   => ['me.titleid'],
                    as       => ['thisid'],
                    join     => $table_type{$table}{join},
		    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
        }

        if ($mode eq "all" && $first_criteria){
            $first_criteria = 0;
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                $title_a{$thisid} = 1;
            }            
        }
        elsif ($mode eq "all" && !$first_criteria){
            while (my $item = $titles->next){
                my $thisid = $item->{thisid};                
                if ($title_a{$thisid} == 1){
                    $title_b{$thisid} = 1;
                }
            }
            %title_a = %title_b;
        }
        else {
            foreach my $item ($titles->all){
                my $thisid = $item->{'thisid'};
                
                $self->{titleid}{$thisid} = 1;
            }
        }
    }

    if ($mode eq "all"){
        $self->{titleid} = \%title_a;
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    return $self;
}

sub get_titleid {
    my $self=shift;

    return $self->{titleid};
}

sub set_titleid {
    my ($self,$titleid_ref) = @_;

    $self->{titleid} = $titleid_ref;

    return;
}

sub get_marks_restriction {
    my $self = shift;
    
    return $self->{restrict_marks};
}

sub set_marks_restriction {
    my ($self,$marks_ref) = @_;
    
    $self->{restrict_marks} = $marks_ref;
}

sub remove_marks_restriction {
    my $self = shift;

    delete $self->{restrict_marks};

    return;
}

1;
