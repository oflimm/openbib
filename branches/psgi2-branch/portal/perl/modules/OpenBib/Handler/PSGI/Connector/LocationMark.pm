####################################################################
#
#  OpenBib::Handler::PSGI::Connector::LocationMark.pm
#
#  ehemals biblio-signatur.pl
#
#  Herausgabe von Titellisten anhand einer Grundsignatur
#
#  Dieses File ist (C) 2000-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Connector::LocationMark;

use strict;
use warnings;
no warnings 'redefine';

use Log::Log4perl qw(get_logger :levels);

use Benchmark ':hireswallclock';
use DBI;
use Encode qw(decode_utf8);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::Search::Factory;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show_via_sql',
#        'show'       => 'show_via_searchengine',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_via_sql {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $base       = $query->param('base')       || undef;
    my $location   = decode_utf8($query->param('location'))   || undef;
    my $range_start= $query->param('start')      || undef;
    my $range_end  = $query->param('end')        || undef;
    my $title      = decode_utf8($query->param('title'))      || '';
    my $database   = $query->param('database')   || '';

    return 200 unless (defined $base); # ok

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    if ($base && $location){
        $logger->debug("Bestimme Titel zur Grundsignatur '$base' und Standort '$location'");

        # my $sql = "select distinct c.sourceid, m1.content from conn as c, mex as m1 left join mex as m2 on m1.id=m2.id where m1.category=14 and m1.content like ? and m1.content != 'bestellt' and m1.content != 'vergriffen' and m1.content != 'storniert' and m2.category = 16 and m2.content = ? and c.targettype=6 and c.targetid=m1.id and c.sourcetype=1";

        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my $locationholdings = $catalog->{schema}->resultset('TitleHolding')->search_rs(
            {
                'holding_fields.field' => 16,
#                'holding_fields.content' => { '~' => $location },
                'holding_fields.content' => $location,
            },
            {
                select   => ['holdingid.id'],
                as       => ['thisholdingid'],
                join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
                group_by => ['holdingid.id'],
            }
        );

        my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
            {
                'holdingid.id' => { -in => $locationholdings->as_query },

                'holding_fields.field' => 14,
                'holding_fields.content' => { '~' => "^$base" },
            },
            {
                select   => ['titleid.id','holding_fields.content'],
                as       => ['thistitleid','thislocmark'],
                join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
                group_by => ['titleid.id','holding_fields.content'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );


        my @filtered_titleids = ();
        
        while (my $item = $titles->next){
            my $titleid = $item->{thistitleid};
            my $locmark = $item->{thislocmark};

            $logger->debug("Found titleid $titleid with location mark $locmark");
            
            if ($locmark=~m/^$base/){
                $logger->debug("Location mark $locmark matches base $base");

                if ($range_start > 0 && $range_end > 0){
                     my ($number)=$locmark=~m/^$base(\d+)/;
                     $logger->debug("Number part is $number");

                     if ($number >= $range_start && $number <= $range_end) {
                        $logger->debug("Location mark $locmark in Range $range_start - $range_end");
                        push @filtered_titleids, {
                            id       => $titleid,
                            locmark  => $locmark,
                            base     => $base,
                        }
                     }
                     else {
                        $logger->debug("Location mark $locmark NOT in Range $range_start - $range_end");
                     }
                 }
                 else {
                        $logger->debug("No range specified for location mark $locmark ");
                     push @filtered_titleids, {
                         id       => $titleid,
                         locmark  => $locmark,
                         base     => $base,
                     };
                 }
             }
        }

        my @sortedtitleids = sort by_signature @filtered_titleids;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for getting title ids is ".timestr($timeall));
        }

        if ($logger->is_debug){
            $logger->debug("Gefundene Titelids: ".YAML::Dump(\@sortedtitleids));
        }
        
        my @outputbuffer = ();

        my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');

        my $hits = $#sortedtitleids + 1;
        
        my $nav = Data::Pageset->new({
            'total_entries'    => $hits,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });

        $logger->debug("Offset: $offset - Num: ".$queryoptions->get_option('num'));
        
        my $endrange = ($offset+$queryoptions->get_option('num') < $#sortedtitleids)?$offset+$queryoptions->get_option('num'):$#sortedtitleids;
        
        for (my $i = $offset ; $i <= $endrange ; $i++){
            my $titleid_ref = $sortedtitleids[$i];
            my $id = $titleid_ref->{id};
            
            my $listitem_ref = OpenBib::Record::Title->new({id => $id, database => $database})->load_brief_record->get_fields;
            
            # Bereinigung der Signaturen. Alle Signaturen, die nicht zur Grundsignatur gehoeren,
            # werden entfernt.
            my $cleansig_ref = [];
            foreach my $sig_ref (@{$listitem_ref->{X0014}}){
                if ($sig_ref->{content}=~m/^$base/){
                    push @$cleansig_ref, $sig_ref;
                }
            }
            $listitem_ref->{X0014}=$cleansig_ref;
            push @outputbuffer, $listitem_ref;
        }

        if ($logger->is_debug){
            $logger->debug("Vollstaendige Titel: ".YAML::Dump(\@outputbuffer));
        }

        # TT-Data erzeugen
        my $ttdata={
            hits         => $hits,
            mark_base    => $base,
            mark_numericrange_start   => $range_start,
            mark_numericrange_end     => $range_end,
            nav          => $nav,
            itemlist     => \@outputbuffer,
            signaturdesc => $title,
            database     => $database,
            view         => $view,
            config       => $config,
        };
        
        return $self->print_page($config->{tt_connector_locationmark_titlist_tname},$ttdata);
        
    }
    else {
        return $self->print_warning("Insufficient Arguments",2);
    }
}

sub show_via_searchengine {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $queryoptions   = $self->param('qopts');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $base       = $query->param('base')       || undef;
    my $location   = decode_utf8($query->param('location'))   || undef;
    my $range_start= $query->param('start')      || undef;
    my $range_end  = $query->param('end')        || undef;
    my $title      = decode_utf8($query->param('title'))      || '';
    my $database   = $query->param('database')   || '';

    return 200 unless (defined $base); # ok

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    my $searchquery = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session});
    $location = OpenBib::Common::Util::normalize({
        content   => $location,
        type      => 'string',
        searchreq => 1,
    });

    $searchquery->set_searchfield('markstring',"${base}*",'');
    $searchquery->set_searchfield('t0016',$location,'');
    $searchquery->set_type('authority');

    $self->param('searchquery',$searchquery);

    my $searcher = OpenBib::Search::Factory->create_searcher({database => $database."_authority", query => $searchquery });

    if ($base && $location){
        $logger->debug("Bestimme Titel zur Grundsignatur '$base' und Standort '$location'");

        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        $searcher->search({options => { 'num'=> 100000, 'page' => 1 } });

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for search is ".timestr($timeall));
        }

        my @filtered_titleids = ();

        my %have_titleid = ();

        my $recordlist = $searcher->get_records_as_json;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for getting records is ".timestr($timeall));
        }


        foreach my $item (@{$recordlist}){
#            $logger->info(YAML::Dump($item));
            my $titleid = $item->{'X0004'}[0]{content};
            my $locmark = $item->{'X0014'}[0]{content};

            next if (defined $have_titleid{$titleid});
            
            $logger->debug("Found titleid $titleid with location mark $locmark");

            if ($locmark=~m/^$base/){
                $logger->debug("Location mark $locmark matches base $base");
                
                if ($range_start > 0 && $range_end > 0){
                    my ($number)=$locmark=~m/^$base(\d+)/;
                    $logger->debug("Number part is $number");
                    
                    if ($number >= $range_start && $number <= $range_end) {
                        $logger->debug("Location mark $locmark in Range $range_start - $range_end");
                        push @filtered_titleids, {
                            id       => $titleid,
                            locmark  => $locmark,
                            base     => $base,
                        }
                    }
                    else {
                        $logger->debug("Location mark $locmark NOT in Range $range_start - $range_end");
                    }
                }
                else {
                    $logger->debug("No range specified for location mark $locmark ");
                    push @filtered_titleids, {
                        id       => $titleid,
                        locmark  => $locmark,
                        base     => $base,
                    };
                }
                # Fertig, wenn entsprechende Signatur gefunden
                $have_titleid{$titleid} = 1;
            }
        }

        my @sortedtitleids = sort by_signature @filtered_titleids;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for getting title ids is ".timestr($timeall));
        }

        if ($logger->is_debug){
            $logger->debug("Gefundene Titelids: ".YAML::Dump(\@sortedtitleids));
        }
        
        my @outputbuffer = ();

        my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');

        my $hits = $#sortedtitleids + 1;
        
        my $nav = Data::Pageset->new({
            'total_entries'    => $hits,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });

        if ($logger->is_debug){
            $logger->debug("Offset: $offset - Num: ".$queryoptions->get_option('num'));
            
            $logger->debug("All titles ".YAML::Dump(@sortedtitleids));
        }
        
        my $endrange = ($offset+$queryoptions->get_option('num') < $#sortedtitleids)?$offset+$queryoptions->get_option('num'):$#sortedtitleids;
        
        for (my $i = $offset ; $i <= $endrange ; $i++){
            my $titleid_ref = $sortedtitleids[$i];
            my $id          = $titleid_ref->{id};
            
            my $listitem_ref = OpenBib::Record::Title->new({id => $id, database => $database})->load_brief_record->get_fields;
            
            # Bereinigung der Signaturen. Alle Signaturen, die nicht zur Grundsignatur gehoeren,
            # werden entfernt.
            my $cleansig_ref = [];
            foreach my $sig_ref (@{$listitem_ref->{X0014}}){
                if ($sig_ref->{content}=~m/^$base/){
                    push @$cleansig_ref, $sig_ref;
                }
            }
            $listitem_ref->{X0014}=$cleansig_ref;
            push @outputbuffer, $listitem_ref;
        }

        if ($logger->is_debug){
            $logger->debug("Vollstaendige Titel: ".YAML::Dump(\@outputbuffer));
        }

        # TT-Data erzeugen
        my $ttdata={
            hits         => $hits,
            mark_base    => $base,
            mark_numericrange_start   => $range_start,
            mark_numericrange_end     => $range_end,
            nav          => $nav,
            itemlist     => \@outputbuffer,
            signaturdesc => $title,
            database     => $database,
            view         => $view,
            config       => $config,
        };
        
        return $self->print_page($config->{tt_connector_locationmark_titlist_tname},$ttdata);
        
    }
    else {
        return $self->print_warning("Insufficient Arguments",2);
    }
}

sub by_signature {
    my %line1=%$a;
    my %line2=%$b;

#    my $logger = get_logger() ;
    
    my $base = $line1{base};
    
    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{locmark} && defined $line1{locmark})?cleanrl($line1{locmark}):"0";
    my $line2=(exists $line2{locmark} && defined $line2{locmark})?cleanrl($line2{locmark}):"0";

#    $logger->debug("1 L1: $line1 / L2: $line2 / Base: $base");
    
    my ($zahl1,$rest1)=$line1=~m/$base(\d+)(.*?)/i;
    my ($zahl2,$rest2)=$line2=~m/$base(\d+)(.*?)/i;

#    $logger->debug("2 Z1: $zahl1 / R1: $rest1 / Z2: $zahl2 / R2: $rest2");
    
    $line1=sprintf "%08d%s", $zahl1, $rest1;
    $line2=sprintf "%08d%s", $zahl2, $rest2;

#    $logger->debug("3 L1: $line1 / L2: $line2");
    
    $line1 cmp $line2;
}

sub cleanrl {
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

1;
