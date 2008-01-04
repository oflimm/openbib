#####################################################################
#
#  OpenBib::RecordList::Title.pm
#
#  Titel-Liste
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

sub new {    
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    $self->{config}         = $config;
    $self->{targetdbinfo}   = $self->{config}->get_targetdbinfo();
    $self->{recordlist}     = [];

    $logger->debug("Title-RecordList-Object created: ".YAML::Dump($self));
    return $self;
}

sub add {
    my ($self,$record)=@_;

    push @{$self->{recordlist}}, $record;
}

sub add_from_storable {
    my ($self,$storable_ref)=@_;

    push @{$self->{recordlist}}, @{$storable_ref};
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

    my $sortedoutputbuffer_ref = [];

    my $atime;
    my $btime;
    my $timeall;

    if ($self->{config}->{benchmark}) {
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
    else {
        @$sortedoutputbuffer_ref=@{$self->{recordlist}};
    }

    if ($self->{config}->{benchmark}) {
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
    my $queryoptions_ref  = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hits              = exists $arg_ref->{hits}
        ? $arg_ref->{hits}              : -1;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : 50;
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

    my $query=Apache::Request->instance($r);

    my @itemlist=@{$self->{recordlist}};

    # Navigationselemente erzeugen
    my %args=$r->args;
    delete $args{offset};
    delete $args{hitrange};
    my @args=();
    while (my ($key,$value)=each %args) {
        push @args,"$key=$value";
    }

    my $baseurl="http://$self->{config}->{servername}$self->{config}->{search_loc}?".join(";",@args);

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
        lang           => $lang,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,
	      
        database       => $database,

        hits           => $hits,
	      
        sessionID      => $sessionID,
	      
        targetdbinfo   => $self->{targetdbinfo},
        itemlist       => \@itemlist,

        baseurl        => $baseurl,

        qopts          => $queryoptions_ref,
        query          => $query,
        hitrange       => $hitrange,
        offset         => $offset,
        nav            => \@nav,

        config         => $self->{config},
        msg            => $msg,
    };

    OpenBib::Common::Util::print_page($self->{config}->{$template},$ttdata,$r);

    return;
}

sub size {
    my ($self,$arg_ref)=@_;

    my @list=@{$self->{recordlist}};
    return $#list+1;
}

sub _by_yearofpub {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline1 <=> $yline2;
}

sub _by_yearofpub_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?_cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?_cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline2 <=> $yline1;
}


sub _by_publisher {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_publisher_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?_cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?_cleanrl($line2{T0412}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_signature {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub _by_signature_down {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_author {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_author_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?_cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?_cleanrl($line2{PC0001}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_title {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line1 cmp $line2;
}

sub _by_title_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?_cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?_cleanrl($line2{T0331}[0]{content}):"";

    $line2 cmp $line1;
}

sub _by_order {
    my %line1=%$a;
    my %line2=%$b;

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

    $line1 cmp $line2;
}

sub _by_order_down {
    my %line1=%$a;
    my %line2=%$b;

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
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line1 <=> $line2;
}

sub _by_popularity_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{popularity} && defined $line1{popularity})?_cleanrl($line1{popularity}):"";
    my $line2=(exists $line2{popularity} && defined $line2{popularity})?_cleanrl($line2{popularity}):"";

    $line1=0 if (!defined $line1 || $line1 eq "");
    $line2=0 if (!defined $line2 || $line2 eq "");

    $line2 <=> $line1;
}

sub _cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
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
