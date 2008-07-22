#####################################################################
#
#  OpenBib::RecordList::Title.pm
#
#  Titel-Liste
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::QueryOptions;
use OpenBib::Session;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->{recordlist}     = [];
    $self->{_size}          = 0;

    $logger->debug("Title-RecordList-Object created: ".YAML::Dump($self));
    return $self;
}

sub add {
    my ($self,$records)=@_;

    # Einzelner Titel
    if    (ref($records) eq "OpenBib::Record::Title"){
        push @{$self->{recordlist}}, $records;
        $self->{_size}=$self->{_size}+1;
    }
    # Titelliste
    elsif (ref($records) eq "OpenBib::RecordList::Title"){
       push @{$self->{recordlist}}, $records->get_records;
       $self->{_size}=$self->{_size}+$records->get_size();
    }
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

    my $config = OpenBib::Config->instance;

    my $sortedoutputbuffer_ref = [];

    my $atime;
    my $btime;
    my $timeall;

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    if ($type eq "author" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_author @{$self->{recordlist}};
    }
    elsif ($type eq "author" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_author_down @{$self->{recordlist}};
    }
    elsif ($type eq "yearofpub" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_yearofpub @{$self->{recordlist}};
    }
    elsif ($type eq "yearofpub" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_yearofpub_down @{$self->{recordlist}};
    }
    elsif ($type eq "publisher" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_publisher @{$self->{recordlist}};
    }
    elsif ($type eq "publisher" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_publisher_down @{$self->{recordlist}};
    }
    elsif ($type eq "signature" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_signature @{$self->{recordlist}};
    }
    elsif ($type eq "signature" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_signature_down @{$self->{recordlist}};
    }
    elsif ($type eq "title" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_title @{$self->{recordlist}};
    }
    elsif ($type eq "title" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_title_down @{$self->{recordlist}};
    }
    elsif ($type eq "order" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_order @{$self->{recordlist}};
    }
    elsif ($type eq "order" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_order_down @{$self->{recordlist}};
    }
    elsif ($type eq "popularity" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_popularity @{$self->{recordlist}};
    }
    elsif ($type eq "popularity" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_popularity_down @{$self->{recordlist}};
    }
    elsif ($type eq "tstamp" && $order eq "up") {
        @$sortedoutputbuffer_ref=sort _by_tstamp @{$self->{recordlist}};
    }
    elsif ($type eq "tstamp" && $order eq "down") {
        @$sortedoutputbuffer_ref=sort _by_tstamp_down @{$self->{recordlist}};
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

sub print_to_handler {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hits              = exists $arg_ref->{hits}
        ? $arg_ref->{hits}              : -1;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : 50;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : 'up';
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : 'author';
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $template          = exists $arg_ref->{template}
        ? $arg_ref->{template}          : 'tt_search_showtitlist_tname';
    my $location          = exists $arg_ref->{location}
        ? $arg_ref->{location}          : 'search_loc';
    my $lang              = exists $arg_ref->{lang}
        ? $arg_ref->{lang}              : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->instance;
    my $session      = OpenBib::Session->instance;
    my $user         = OpenBib::User->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;

    my $query         = Apache::Request->instance($r);
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

    my $searchtitofcnt = decode_utf8($query->param('searchtitofcnt'))    || '';

    if ($self->get_size() == 0) {
        OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
    }
    elsif ($self->get_size() == 1) {
        my $record = $self->{recordlist}[0];
        $record->load_full_record->print_to_handler({
            apachereq          => $r,
            stylesheet         => $stylesheet,
            view               => $view,
            msg                => $msg,
        });
    }
    elsif ($self->get_size() > 1) {
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        # Kurztitelinformationen fuer RecordList laden
        $self->load_brief_records;
        
        if ($config->{benchmark}) {
            $btime   = new Benchmark;
            $timeall = timediff($btime,$atime);
            $logger->info("Zeit fuer : ".($self->get_size)." Titel : ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

        # Anreicherung mit OLWS-Daten
        if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){            
            foreach my $record ($self->get_records()){
                if (exists $circinfotable->{$record->{database}} && exists $circinfotable->{$record->{database}}{circcheckurl}){
                    $logger->debug("Endpoint: ".$circinfotable->{$record->{database}}{circcheckurl});
                    my $soapresult;
                    eval {
                        my $soap = SOAP::Lite
                            -> uri("urn:/Viewer")
                                -> proxy($circinfotable->{$record->{database}}{circcheckurl});
                        
                        my $result = $soap->get_item_info(
                            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                                SOAP::Data->name(collection => $circinfotable->{$record->{database}}{circdb})->type('string'),
                                SOAP::Data->name(item       => $record->{id})->type('string'))));
                        
                        unless ($result->fault) {
                            $soapresult=$result->result;
                        }
                        else {
                            $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                        }
                    };
                    
                    if ($@){
                        $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
                    }
                    
                    $record->{olws}=$soapresult;
                }
            }
        }
        
        $logger->debug("Sorting $sorttype with order $sortorder");
        
        $self->sort({order=>$sortorder,type=>$sorttype});
        
        # Navigationselemente erzeugen
        my %args=$r->args;
        delete $args{offset};
        delete $args{hitrange};
        my @args=();
        while (my ($key,$value)=each %args) {
            push @args,"$key=$value";
        }
        
        my $baseurl="http://$config->{servername}$config->{search_loc}?".join(";",@args);
        
        my @nav=();
        
        if ($hitrange > 0) {
            for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
                my $active=0;
                
                if ($i == $offset) {
                    $active=1;
                }
                
                my $item={
                    start  => $i+1,
                    end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
                    url    => $baseurl.";hitrange=$hitrange;offset=$i",
                    active => $active,
                };
                push @nav,$item;
            }
        }
        
        # TT-Data erzeugen
        my $ttdata={
            searchtitofcnt => $searchtitofcnt,
            lang           => $lang,
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},
            
            database       => $database,
            
            hits           => $hits,
            
            targetdbinfo   => $dbinfotable,

            recordlist     => $self,
            
            baseurl        => $baseurl,
            
            qopts          => $queryoptions->get_options,
            query          => $query,
            hitrange       => $hitrange,
            offset         => $offset,
            nav            => \@nav,
            
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{$template},$ttdata,$r);
        
        $session->updatelastresultset($self->to_ids);
    }	
    
    return;
}

sub get_size {
    my ($self)=@_;

    return $self->{_size};
}

sub load_brief_records {
    my ($self) = @_;

    foreach my $record ($self->get_records) {
        $record->load_brief_record;
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

sub _by_yearofpub {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline1 <=> $yline2;
}

sub _by_yearofpub_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline2 <=> $yline1;
}


sub _by_publisher {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_publisher_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_signature {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub _by_signature_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_author {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_author_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_title {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_title_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_order {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

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

sub _by_order_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{T5100}[0]{content} && defined $line1{T5100}[0]{content})?cleanrl($line1{T5100}[0]{content}):"";
    my $line2=(exists $line2{T5100}[0]{content} && defined $line2{T5100}[0]{content})?cleanrl($line2{T5100}[0]{content}):"";

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

sub _by_popularity {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line1 <=> $line2;
}

sub _by_popularity_down {
    my %line1=%{$a->get_brief_normdata()};
    my %line2=%{$b->get_brief_normdata()};

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line2 <=> $line1;
}

sub _by_tstamp {
    my $line1=(exists $a->{tstamp} && defined $a->{tstamp})?$a->{tstamp}:"";
    my $line2=(exists $b->{tstamp} && defined $b->{tstamp})?$b->{tstamp}:"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line1 cmp $line2;
}

sub _by_tstamp_down {
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
