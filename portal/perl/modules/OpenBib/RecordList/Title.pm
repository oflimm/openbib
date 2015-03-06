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

use OpenBib::Common::Util;
use OpenBib::QueryOptions;
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

sub add {
    my ($self,$records)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Adding 1 Record of type ".ref($records));
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

    my $config = OpenBib::Config->new;

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
        my $title = $record->get_field({field => 'T0331'});

        if (ref $title eq "ARRAY"){
            $title=$title->[0];
        }

        my $ast   = $record->get_field({field => 'T0310'});

        if (ref $ast eq "ARRAY"){
            $ast=$ast->[0];
        }

        $title = $ast if ($ast);

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
            link        => "http://".$servername.$path_prefix."/".$config->{databases_loc}."/id/".$record->{database}."/".$config->{titles_loc}."/id/".$record->{id}.".html",
            description => $desc
        );
    }
    
    return $rss->as_string;
}

# sub print_to_handler {
#     my ($self,$arg_ref)=@_;

#     # Set defaults
#     my $database          = exists $arg_ref->{database}
#         ? $arg_ref->{database}          : undef;
#     my $r                 = exists $arg_ref->{apachereq}
#         ? $arg_ref->{apachereq}         : undef;
#     my $stylesheet        = exists $arg_ref->{stylesheet}
#         ? $arg_ref->{stylesheet}        : undef;
#     my $hits              = exists $arg_ref->{hits}
#         ? $arg_ref->{hits}              : -1;
#     my $hitrange          = exists $arg_ref->{hitrange}
#         ? $arg_ref->{hitrange}          : 50;
#     my $sortorder         = exists $arg_ref->{sortorder}
#         ? $arg_ref->{sortorder}         : 'up';
#     my $sorttype          = exists $arg_ref->{sorttype}
#         ? $arg_ref->{sorttype}          : 'author';
#     my $offset            = exists $arg_ref->{offset}
#         ? $arg_ref->{offset}            : undef;
#     my $view              = exists $arg_ref->{view}
#         ? $arg_ref->{view}              : undef;
#     my $template          = exists $arg_ref->{template}
#         ? $arg_ref->{template}          : 'tt_search_tname';
#     my $location          = exists $arg_ref->{location}
#         ? $arg_ref->{location}          : 'search_loc';
#     my $parameter         = exists $arg_ref->{parameter}
#         ? $arg_ref->{parameter}         : {};
#     my $representation     = exists $arg_ref->{representation}
#         ? $arg_ref->{representation}     : undef;
#     my $content_type       = exists $arg_ref->{content_type}
#         ? $arg_ref->{content_type}       : 'text/html';
#     my $lang               = exists $arg_ref->{lang}
#         ? $arg_ref->{lang}              : undef;
#     my $msg                = exists $arg_ref->{msg}
#         ? $arg_ref->{msg}                : undef;

#     my $queryoptions       = exists $arg_ref->{queryoptions}
#         ? $arg_ref->{queryoptions}       : OpenBib::QueryOptions->new;
    
#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $config       = OpenBib::Config->new;
#     my $session      = OpenBib::Session->instance;
#     my $user         = OpenBib::User->instance;

#     my $query         = $r;
#     my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
#     my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

#     my $searchtitofcnt = decode_utf8($query->param('searchtitofcnt'))    || '';

#     $logger->debug("Representation: $representation - Content-Type: $content_type ");
    
#     if ($self->get_size() == 0) {
#         OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg,$representation,$content_type);
#     }
#     elsif ($self->get_size() == 1) {
#         my $record = $self->{recordlist}[0];
#         $record->load_full_record->print_to_handler({
#             representation     => $representation,
#             content_type       => $content_type,
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#             msg                => $msg,
#         });
#     }
#     elsif ($self->get_size() > 1) {
#         my ($atime,$btime,$timeall);
        
#         if ($config->{benchmark}) {
#             $atime=new Benchmark;
#         }

#         # Kurztitelinformationen fuer RecordList laden
#         $self->load_brief_records;
        
#         if ($config->{benchmark}) {
#             $btime   = new Benchmark;
#             $timeall = timediff($btime,$atime);
#             $logger->info("Zeit fuer : ".($self->get_size)." Titel : ist ".timestr($timeall));
#             undef $atime;
#             undef $btime;
#             undef $timeall;
#         }

#         # Anreicherung mit OLWS-Daten
#         if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){            
#             foreach my $record ($self->get_records()){
#                 if (exists $circinfotable->{$record->{database}} && exists $circinfotable->{$record->{database}}{circcheckurl}){
#                     $logger->debug("Endpoint: ".$circinfotable->{$record->{database}}{circcheckurl});
#                     my $soapresult;
#                     eval {
#                         my $soap = SOAP::Lite
#                             -> uri("urn:/Viewer")
#                                 -> proxy($circinfotable->{$record->{database}}{circcheckurl});
                        
#                         my $result = $soap->get_item_info(
#                             SOAP::Data->name(parameter  =>\SOAP::Data->value(
#                                 SOAP::Data->name(collection => $circinfotable->{$record->{database}}{circdb})->type('string'),
#                                 SOAP::Data->name(item       => $record->{id})->type('string'))));
                        
#                         unless ($result->fault) {
#                             $soapresult=$result->result;
#                         }
#                         else {
#                             $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
#                         }
#                     };
                    
#                     if ($@){
#                         $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
#                     }
                    
#                     $record->{olws}=$soapresult;
#                 }
#             }
#         }
        
#         $logger->debug("Sorting $sorttype with order $sortorder");
        
#         $self->sort({order=>$sortorder,type=>$sorttype});
        
#         # Navigationselemente erzeugen
#         my @args=();
#         foreach my $param ($query->param()) {
#             $logger->debug("Adding Param $param with value ".$query->param($param));
#             push @args, $param."=".$query->param($param) if ($param ne "offset" && $param ne "hitrange");
#         }
        
#         my $baseurl="http://$config->{servername}$config->{search_loc}?".join(";",@args);
        
#         my @nav=();
        
#         if ($hitrange > 0) {
#             for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
#                 my $active=0;
                
#                 if ($i == $offset) {
#                     $active=1;
#                 }
                
#                 my $item={
#                     start  => $i+1,
#                     end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
#                     url    => $baseurl.";hitrange=$hitrange;offset=$i",
#                     active => $active,
#                 };
#                 push @nav,$item;
#             }
#         }
        
#         # TT-Data erzeugen
#         my $ttdata={
#             representation => $representation,
#             content_type   => $content_type,
            
#             searchtitofcnt => $searchtitofcnt,
#             lang           => $lang,
#             view           => $view,
#             stylesheet     => $stylesheet,
#             sessionID      => $session->{ID},
            
#             database       => $database,
            
#             hits           => $hits,
            
#             dbinfo         => $dbinfotable,

#             recordlist     => $self,

#             parameter      => $parameter,

#             baseurl        => $baseurl,
            
#             qopts          => $queryoptions->get_options,
#             query          => $query,
#             hitrange       => $hitrange,
#             offset         => $offset,
#             nav            => \@nav,
            
#             config         => $config,
#             user           => $user,
#             msg            => $msg,
#             decode_utf8    => sub {
#                 my $string=shift;
#                 return decode_utf8($string);
#             },
#         };
        
#         OpenBib::Common::Util::print_page($config->{$template},$ttdata,$r);
        
#         $session->updatelastresultset($self->to_ids);
#     }	
    
#     return;
# }

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

sub filter_by_profile {
    my ($self,$profilename) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    my $db_in_profile_ref = {};

    $logger->debug("Checking profile $profilename");
    
    return $self unless $config->profile_exists($profilename);

    $logger->debug("Profile $profilename exists");
    
    foreach my $dbname ($config->get_profiledbs($profilename)){
        $db_in_profile_ref->{$dbname} = 1;
    }

    if ($logger->is_debug){
        $logger->debug("Databases: ".YAML::Dump($db_in_profile_ref));
    }
    
    my $newrecords_ref = [];

    foreach my $record ($self->get_records){
        if (defined $db_in_profile_ref->{$record->get_database}){
            push @$newrecords_ref, $record;
            $logger->debug("Used database: ".$record->get_database);
        }
        else {
            $logger->debug("Ignored database: ".$record->get_database);
        }
    }

    $self->set_records($newrecords_ref);

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

sub _by_signature_asc {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?_cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?_cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub _by_signature_desc {
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
