####################################################################
#
#  OpenBib::Mojo::Controller::Connector::SimilarPersons
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::SimilarPersons;

use strict;
use warnings;
no warnings 'redefine';

use Business::ISBN;
use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Record::Person;
use OpenBib::Record::Title;
use OpenBib::Search::Util;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my $type           = $r->param('type')            || 'aut'; # oder tit
    my $id             = $r->param('id')              || '';
    my $content        = $r->param('content')         || '';
    my $isbn           = $r->param('isbn')            || '';
    my $database       = $r->param('db')        || '';
    my $format         = $r->param('format')          || 'ajax';

    if (!$database || !$type){
        return $self->print_warning($msg->maketext("Fehler."));
    }

#     my $schema;
    
#     eval {
#         # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
#         $schema = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
#     };
    
#     if ($@){
#         $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
#         return;
#     }

    my $dbh   = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

    my $similar_persons_ref = [];
    my $tit_aut_count_ref = {};
   
    my $maxcount=0;
    my $mincount=999999999;

    if ($type eq "aut" && $id){
        $logger->debug("Getting similar Persons for Personid $id");

        my $titcount = OpenBib::Record::Person->new({database=>$database, id => $id})->get_number_of_titles;

        # Nur 'praezisere' Verfasser werden analysiert
        if ($titcount < 100){
            my $request = $dbh->prepare("select distinct c2.personid as id from title_person as c1 left join title_person as c2 on c1.titleid=c2.titleid where c1.personid=? and c2.personid != ?");
            $request->execute($id,$id);
            
            while (my $result=$request->fetchrow_hashref){
                my $similarid = $result->{id};
                
                my $record=OpenBib::Record::Person->new({database=>$database});
                $record->load_name({dbh => $dbh, id=>$similarid});
                my $content=$record->name_as_string;
                
                # Ausgabe der Anzahl verk"upfter Titel
                my $sqlrequest="select count(distinct titleid) as conncount from title_person where personid=?";
                my $request2=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
                $request2->execute($similarid);
                my $result2=$request2->fetchrow_hashref;
                my $count = $result2->{conncount};
                
                if ($maxcount < $count){
                    $maxcount = $count;
                }
                
                if ($mincount > $count){
                    $mincount = $count;
                }
                
                push @{$similar_persons_ref}, {
                    id      => $similarid,
                    item    => $content,
                    count   => $count,
                };
            }
        }
    }

    if ($type eq "tit" && $id){
        $logger->debug("Getting similar Persons for Titleid $id");

        my $request = $dbh->prepare("select distinct personid as id from title_person where titleid=?");
        $request->execute($id);

        my @autids=();
        my $autid_lookup_ref = {}; 
        while (my $result=$request->fetchrow_hashref){
            $autid_lookup_ref->{$result->{id}}=1;
            push @autids, $result->{id};
        }

        if ($logger->is_debug){
            $logger->debug("Gefundene Personen-ID's: ".YAML::Dump(\@autids));
        }
        
        my %similar_done = ();
        foreach my $autid (@autids){

            my $titcount = OpenBib::Record::Subject->new({database=>$database, id => $autid})->get_number_of_titles;

            # Nur 'praezisere' Autoren werden analysiert
            if ($titcount < 100){
                
                #$request = $dbh->prepare("select distinct targetid as id from conn where sourcetype=1 and targettype=2 and targetid != ? and sourceid in (select sourceid from conn where sourcetype=1 and targettype =2 and targetid = ?)");
                $request = $dbh->prepare("select distinct c2.personid as id, count(c2.titleid) as titcount from title_person as c1 left join title_person as c2 on c1.titleid=c2.titleid where c1.personid=? and c2.personid != ? group by c2.titleid,c2.personid");
                
                $request->execute($autid,$autid);
                
                while (my $result=$request->fetchrow_hashref){
                    my $similarid       = $result->{id};
                    my $similartitcount = $result->{titcount};
                    #my $similartitcount = OpenBib::Record::Person->new({database=>$database, id => $similarid})->get_number_of_titles;
                    
                    # Wenn das zu einer Person eine andere gefundene Person schon im
                    # aktuellen Titel enthalten ist, dann ignorieren
                    next if (exists $autid_lookup_ref->{$similarid});
                    
                    # Counts bzgl verschiedener Schlagworte des aktuellen Titels werden alle gezaehlt
                    if (!exists $tit_aut_count_ref->{$similarid}){
                        $tit_aut_count_ref->{$similarid}=$similartitcount;
                    }
                    else {
                        $tit_aut_count_ref->{$similarid}+=$similartitcount;
                    }
                    
                    # Jetzt wurde gezaehlt, aber ein Eintrag muss nicht angelegt werden.
                    if (exists $similar_done{$similarid}){
                        next;
                    }
                    else {
                        $similar_done{$similarid}=1;
                    }
                
                    my $record=OpenBib::Record::Person->new({database=>$database});
                    $record->load_name({dbh => $dbh, id=>$similarid});
                    my $content=$record->name_as_string;
                    
                    push @{$similar_persons_ref}, {
                        id      => $similarid,
                        item    => $content,
                        #                    count   => $count,
                    };            
                }
            }
        }
        
        foreach my $single_person_ref (@{$similar_persons_ref}){
            my $count=$tit_aut_count_ref->{$single_person_ref->{id}}/2;
            
            $single_person_ref->{count} = $count;
            
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            if ($mincount > $count){
                $mincount = $count;
            }
        }
    }

    $similar_persons_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $similar_persons_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => 'log'});
    
    my $sorted_similar_persons_ref ;
    @{$sorted_similar_persons_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$similar_persons_ref};

    if ($logger->is_debug){
        $logger->debug("Verwandte Personen: ".YAML::Dump($sorted_similar_persons_ref));
    }    
    
    my $ttdata = {
        record          => OpenBib::Record::Title->new({config => $config}),
        format          => $format,
        similar_persons => $sorted_similar_persons_ref,
        database        => $database,
    };

    return $self->print_page($config->{tt_connector_similarpersons_tname},$ttdata);
}

1;
