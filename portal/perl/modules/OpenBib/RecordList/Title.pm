#####################################################################
#
#  OpenBib::RecordList::Title.pm
#
#  Titel-Liste
#
#  Dieses File ist (C) 2007-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::RecordList::Title;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use XML::RSS;
use YAML ();

use Mojo::Base -base, -strict, -signatures;
use Mojo::Promise;
use Mojo::IOLoop;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Template::Provider;
use OpenBib::Session;

sub new {
    my ($class, $arg_ref) = @_;

    my $generic_attributes = exists $arg_ref->{generic_attributes}
        ? $arg_ref->{generic_attributes}   : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $generic_attributes){
        $self->{generic_attributes}   = $generic_attributes;
    }

    $self->{recordlist}     = [];
    $self->{_size}          = 0;

    if ($logger->is_debug){
        $logger->debug("Title-RecordList-Object created: ".YAML::Dump($self));
    }
    
    return $self;
}

sub get_generic_attribute {
    my ($self,$attribute)=@_;

    return (defined $self->{generic_attributes}{$attribute})?$self->{generic_attributes}{$attribute}:undef;
}

sub add {
    my ($self,$records)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Adding 1 Record of type ".ref($records));
    # Einzelner Titel
    if    (ref($records) eq "OpenBib::Record::Title"){
	$logger->debug("Adding single record");
        push @{$self->{recordlist}}, $records;
        $self->{_size}=$self->{_size}+1;
    }
    # Titelliste
    elsif (ref($records) eq "OpenBib::RecordList::Title"){
	$logger->debug("Adding recordlist");
       push @{$self->{recordlist}}, $records->get_records;
       $self->{_size}=$self->{_size}+$records->get_size();
    }

    $logger->debug("Actual size ".$self->get_size());
}

sub sort {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $order             = exists $arg_ref->{order}
        ? $arg_ref->{order}                : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    my $sortedoutputbuffer_ref = [];

    my $atime;
    my $btime;
    my $timeall;

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    if ($type eq "person" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_person_asc @{$self->{recordlist}};
    }
    elsif ($type eq "person" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_person_desc @{$self->{recordlist}};
    }
    elsif ($type eq "year" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_year_asc @{$self->{recordlist}};
    }
    elsif ($type eq "year" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_year_desc @{$self->{recordlist}};
    }
    elsif ($type eq "publisher" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_publisher_asc @{$self->{recordlist}};
    }
    elsif ($type eq "publisher" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_publisher_desc @{$self->{recordlist}};
    }
    elsif ($type eq "mark" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_mark_asc @{$self->{recordlist}};
    }
    elsif ($type eq "signature" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_mark_desc @{$self->{recordlist}};
    }
    elsif ($type eq "title" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_title_asc @{$self->{recordlist}};
    }
    elsif ($type eq "title" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_title_desc @{$self->{recordlist}};
    }
    elsif ($type eq "order" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_order_asc @{$self->{recordlist}};
    }
    elsif ($type eq "order" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_order_desc @{$self->{recordlist}};
    }
    elsif ($type eq "popularity" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_popularity_asc @{$self->{recordlist}};
    }
    elsif ($type eq "popularity" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_popularity_desc @{$self->{recordlist}};
    }
    elsif ($type eq "tstamp" && $order eq "asc") {
        @$sortedoutputbuffer_ref=sort _by_tstamp_asc @{$self->{recordlist}};
    }
    elsif ($type eq "tstamp" && $order eq "desc") {
        @$sortedoutputbuffer_ref=sort _by_tstamp_desc @{$self->{recordlist}};
    }
    # Default der Suchmaschine ist Sortierung nach Relevanz
    elsif ($type eq "relevance" && $order eq "asc") {
        @$sortedoutputbuffer_ref=@{$self->{recordlist}};
    }
    elsif ($type eq "relevance" && $order eq "desc") {
        @$sortedoutputbuffer_ref=reverse @{$self->{recordlist}};
    }
    else {
        @$sortedoutputbuffer_ref=@{$self->{recordlist}};
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->debug("Zeit fuer : sort by $type / $order : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    $self->{recordlist} = $sortedoutputbuffer_ref;
    return $self;
}

sub to_ids {
    my ($self)=@_;

    my $idlist_ref = [];
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
    foreach my $item_ref (@{$self->{recordlist}}){
        push @$idlist_ref, { id       => $item_ref->{id},
                             database => $item_ref->{database},
                         };
    }
    return $idlist_ref;
}

sub to_list {
    my ($self)=@_;

    return $self->{recordlist};
}

sub to_rss {
    my ($self,$arg_ref) = @_;
    
    # Set defaults
    my $channel_title     = exists $arg_ref->{channel_title}
        ? $arg_ref->{channel_title}        : '';
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}                 : 'openbib';
    my $scheme            = exists $arg_ref->{scheme}
        ? $arg_ref->{scheme}               : 'https';
    my $servername        = exists $arg_ref->{servername}
        ? $arg_ref->{servername}           : '127.0.0.1';
    my $path_prefix       = exists $arg_ref->{path_prefix}
        ? $arg_ref->{path_prefix}          : '';
    my $channel_description       = exists $arg_ref->{channel_description}
        ? $arg_ref->{channel_description}  : '';
    my $channel_link              = exists $arg_ref->{channel_link}
        ? $arg_ref->{channel_link}         : '';
    my $channel_language          = exists $arg_ref->{channel_language}
        ? $arg_ref->{channel_language}     : 'de';
    my $msg               = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                  : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;

    my $rss = new XML::RSS ( version => '1.0' );
        
    $rss->channel(
        title         => $channel_title,
        link          => $channel_link,
        language      => $channel_language,
        description   => $channel_description,
    );

    my $sysprofile= $config->get_profilename_of_view($view);

    foreach my $record ($self->get_records){
        my $desc  = "";
	my $fields_ref = $record->to_abstract_fields;
	
        my $title = $fields_ref->{title} || $msg->maketext("Keine Titelangabe vorhanden");

        my $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
            view         => $view,
            profile      => $sysprofile,
            templatename => $config->{tt_connector_rss_item_tname},
        });

        my $itemtemplate = Template->new({
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config->{tt_include_path},
                    ABSOLUTE       => 1,
                }) ],
                RECURSION      => 1,
                OUTPUT         => \$desc,
            });

        # TT-Data erzeugen
        my $ttdata={
                record          => $record,
                msg             => $msg,
            };

        $itemtemplate->process($itemtemplatename, $ttdata) || do {
            $logger->error($itemtemplate->error());
        };
        
        $logger->debug("Adding $title / $desc") if (defined $title && defined $desc);
        
        $rss->add_item(
            title       => $title,
            link        => "$scheme://".$servername.$path_prefix."/".$config->{databases_loc}."/id/".$record->{database}."/".$config->{titles_loc}."/id/".$record->{id}.".html",
            description => $desc
        );
    }
    
    return $rss->as_string;
}

sub set_from_storable {
    my ($self,$storable_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (exists $self->{_exists} && exists $self->{recordlist}){
        $self->{recordlist} = $storable_ref->{recordlist};
        $self->{_size}      = $storable_ref->{_size};
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self));
    }

    return $self;
}

sub get_size {
    my ($self)=@_;

    return $self->{_size};
}

sub load_brief_records {
    my ($self) = @_;

    foreach my $record ($self->get_records) {
        my $record_p = $record->load_brief_record_p;

	$record_p->then( sub {
	    my $this_record = shift;

	    $record->set_fields($this_record->get_fields);
	    $record->set_locations($this_record->get_locations);
	    $record->set_type('brief');
	    $record->set_record_exists;
			 })->wait;
    }

    return $self;
}

sub load_full_records {
    my ($self) = @_;

    foreach my $record ($self->get_records) {
        $record->load_full_record;
    }

    return $self;
}

sub get_records {
    my ($self) = @_;

    return @{$self->{recordlist}};
}

sub set_records {
    my ($self,$recordlist_ref) = @_;

    $self->{recordlist} = $recordlist_ref;

    return $self;
}

sub to_serialized_reference {
    my ($self) = @_;

    my $recordlist_ref = [];
    
    foreach my $record ($self->get_records) {
        push @$recordlist_ref, $record->to_hash;
    }

    return $recordlist_ref;
}

sub from_serialized_reference {
    my ($self,$recordlist_ref)=@_;

    foreach my $record_ref (@$recordlist_ref){
        $self->add(OpenBib::Record::Title->new->from_hash($record_ref));
    }

    return $self;
}


sub get_titlecount_per_db {
    my ($self) = @_;

    my $count_per_db_ref = {};
    foreach my $record ($self->get_records) {
        if (!exists $count_per_db_ref->{$record->{database}}){
            $count_per_db_ref->{$record->{database}}=1;
        }
        else {
            $count_per_db_ref->{$record->{database}}++;
        }
    }
    
    return $count_per_db_ref;
}

sub _by_year_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline1 <=> $yline2;
}

sub _by_year_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline2 <=> $yline1;
}


sub _by_publisher_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_publisher_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_mark_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub _by_mark_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_person_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_person_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_title_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_title_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_order_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T5100}[0]{content} && defined $line1{T5100}[0]{content})?_cleanrl($line1{T5100}[0]{content}):"";
    my $line2=(exists $line2{T5100}[0]{content} && defined $line2{T5100}[0]{content})?_cleanrl($line2{T5100}[0]{content}):"";

    # Intelligentere Sortierung nach numerisch beginnenden Zaehlungen
    my ($zahl1,$zahl2,$rest1,$rest2);

    if ($line1 =~m/^(\d+)(.*?)/i){
        $zahl1=$1;
        $rest1=$2;
    }
    else {
        $zahl1=0;
        $rest1=$line1;
    }

    if ($line2 =~m/^(\d+)(.*?)/i){
        $zahl2=$1;
        $rest2=$2;
    }
    else {
        $zahl2=0;
        $rest2=$line2;
    }

    $line1=sprintf "%08d%s", (defined $zahl1)?$zahl1:"", (defined $rest1)?$rest1:"";
    $line2=sprintf "%08d%s", (defined $zahl2)?$zahl2:"", (defined $rest2)?$rest2:"";

    $line1 cmp $line2;
}

sub _by_order_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T5100}[0]{content} && defined $line1{T5100}[0]{content})?_cleanrl($line1{T5100}[0]{content}):"";
    my $line2=(exists $line2{T5100}[0]{content} && defined $line2{T5100}[0]{content})?_cleanrl($line2{T5100}[0]{content}):"";

    # Intelligentere Sortierung nach numerisch beginnenden Zaehlungen
    my ($zahl1,$zahl2,$rest1,$rest2);
    
    if ($line1 =~m/^(\d+)(.*?)/i){
        $zahl1=$1;
        $rest1=$2;
    }
    else {
        $zahl1=0;
        $rest1=$line1;
    }

    if ($line2 =~m/^(\d+)(.*?)/i){
        $zahl2=$1;
        $rest2=$2;
    }
    else {
        $zahl2=0;
        $rest2=$line2;
    }

    $line1=sprintf "%08d%s", (defined $zahl1)?$zahl1:"", (defined $rest1)?$rest1:"";
    $line2=sprintf "%08d%s", (defined $zahl2)?$zahl2:"", (defined $rest2)?$rest2:"";

    $line2 cmp $line1;
}

sub _by_popularity_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line1 <=> $line2;
}

sub _by_popularity_desc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line2 <=> $line1;
}

sub _by_tstamp_asc {
    my $line1=(exists $a->{tstamp} && defined $a->{tstamp})?$a->{tstamp}:"";
    my $line2=(exists $b->{tstamp} && defined $b->{tstamp})?$b->{tstamp}:"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line1 cmp $line2;
}

sub _by_tstamp_desc {
    my $line1=(exists $a->{tstamp} && defined $a->{tstamp})?$a->{tstamp}:"";
    my $line2=(exists $b->{tstamp} && defined $b->{tstamp})?$b->{tstamp}:"";
 
    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line2 cmp $line1;
}

sub _cleanrl {
    my ($line)=@_;

    $line=lc($line);
    $line=~s/ü/ue/g;
    $line=~s/ä/ae/g;
    $line=~s/ö/oe/g;
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}

sub DESTROY {
    my $self = shift;
    return;
}

1;
