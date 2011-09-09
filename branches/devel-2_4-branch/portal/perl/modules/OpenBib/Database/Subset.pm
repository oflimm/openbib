#####################################################################
#
#  OpenBib::Database::Subset
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 1997-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Database::Subset;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
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

    $self->{config}   = new OpenBib::Config;

    if ($source){
        $self->{source} = $source;
        $self->{dbh}      = DBI->connect("DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}", $self->{config}->{dbuser}, $self->{config}->{dbpasswd}) or $logger->error_die($DBI::errstr);
    }

    if ($destination){
        $self->{destination} = $destination;
    }
    
    $self->{titleid}  = ();

    bless ($self, $class);

    return $self;
}

sub set_source {
    my $self     = shift;
    my $source = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{source} = $source;
    $self->{dbh}      = DBI->connect("DBI:$self->{config}->{dbimodule}:dbname=$source;host=$self->{config}->{dbhost};port=$self->{config}->{dbport}", $self->{config}->{dbuser}, $self->{config}->{dbpasswd}) or $logger->error_die($DBI::errstr);

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
    
    my $request=$self->{dbh}->prepare("select distinct conn.sourceid as titid from conn,holding where holding.category=14 and holding.content rlike ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6") or $logger->error($DBI::errstr);

    my @marks = (ref $mark)?@$mark:($mark);

    foreach my $thismark (@marks){
        $logger->debug("Searching for Mark $thismark");
        
        $request->execute($thismark) or $logger->error($DBI::errstr);;
        
        while (my $result=$request->fetchrow_hashref()){
            $self->{titleid}{$result->{'titid'}} = 1;
        }
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    $self->get_title_hierarchy;

    $self->get_title_normdata;

    $self->{holdingid} = {};

    # Exemplardaten *nur* vom entsprechenden Institut!
    $request=$self->{dbh}->prepare("select distinct id from holding where category=14 and content rlike ?") or $logger->error($DBI::errstr);

    foreach my $thismark (@marks){
        $request->execute($thismark);
    
        while (my $result=$request->fetchrow_hashref()){
            $self->{holdingid}{$result->{'id'}}=1;
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

    my %table_type = (
        'title'          => 1,
        'person'         => 2,
        'corporatebody'  => 3,
        'subject'        => 4,
        'classification' => 5,
    );
    
    my $request=$self->{dbh}->prepare("select distinct id as titleid from $table where category = ? and content rlike ?") or $logger->error($DBI::errstr);

    if ($table ne "title"){
        $request = $self->{dbh}->prepare("select distinct conn.sourceid as titleid from conn,$table where $table.category = ? and $table.content rlike ? and conn.targetid=$table.id and conn.sourcetype=1 and conn.targettype=$table_type{$table}");
    }
    
    foreach my $criteria_ref (@$arg_ref){        
        
        $request->execute($criteria_ref->{category},$criteria_ref->{content}) or $logger->error($DBI::errstr);;
        
        while (my $result=$request->fetchrow_hashref()){
            $self->{titleid}{$result->{'titleid'}} = 1;
        }
    }
    
    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $self->{source} -> $self->{destination}: Gefundene Titel-ID's $count");

    $self->get_title_hierarchy;

    $self->get_title_normdata;

    $self->{holdingid} = {};

    # Exemplardaten
    $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=6") or $logger->error($DBI::errstr);

    foreach my $id (keys %{$self->{titleid}}){
        $request->execute($id);
    
        while (my $result=$request->fetchrow_hashref()){
            $self->{holdingid}{$result->{'targetid'}}=1;
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

    $self->{holdingid} = {};

    # Exemplardaten
    my $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=6") or $logger->error($DBI::errstr);

    foreach my $id (keys %{$self->{titleid}}){
        $request->execute($id);
    
        while (my $result=$request->fetchrow_hashref()){
            $self->{holdingid}{$result->{'targetid'}}=1;
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
            my $request=$self->{dbh}->prepare("select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1") or $logger->error($DBI::errstr);
            $request->execute($titidn) or $logger->error($DBI::errstr);;
            
            while (my $result=$request->fetchrow_hashref()){
                $self->{titleid}{$result->{'targetid'}} = 1;
                if ($titidn != $result->{'targetid'}){ # keine Ringschluesse - ja, das gibt es
                    $found{$result->{'targetid'}}   = 1;
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

    my $subjectid_ref        = {};
    my $personid_ref         = {};
    my $corporatebodyid_ref  = {};
    my $classificationid_ref = {};
    my $holdingid_ref        = {};

    foreach my $id (keys %{$self->{titleid}}){
        
        # Verfasser/Personen
        my $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $personid_ref->{$result->{'targetid'}}=1;
        }
        
        # Urheber/Koerperschaften
        $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $corporatebodyid_ref->{$result->{'targetid'}}=1;
        }
        
        # Notationen
        $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=5") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $classificationid_ref->{$result->{'targetid'}}=1;
        }
        
        # Schlagworte
        $request=$self->{dbh}->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=4") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $subjectid_ref->{$result->{'targetid'}}=1;
        }
    }

    $self->{personid}         = $personid_ref;
    $self->{corporatebodyid}  = $corporatebodyid_ref;
    $self->{subjectid}        = $subjectid_ref;
    $self->{classificationid} = $classificationid_ref;

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
