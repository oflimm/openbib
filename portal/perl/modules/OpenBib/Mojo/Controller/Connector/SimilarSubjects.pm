####################################################################
#
#  OpenBib::Mojo::Controller::Connector::SimilarSubjects
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

package OpenBib::Mojo::Controller::Connector::SimilarSubjects;

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
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

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
    my $type           = $r->param('type')            || 'swt'; # oder tit
    my $id             = $r->param('id')              || '';
    my $content        = $r->param('content')         || '';
    my $isbn           = $r->param('isbn')            || '';
    my $database       = $r->param('db')        || '';
    my $format         = $r->param('format')          || 'ajax';

    if (!$database || !$type){
        return $self->print_warning($msg->maketext("Fehler."));
    }

    my $dbh   = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

    my $similar_subjects_ref = [];
    my $tit_swt_count_ref = {};
   
    my $maxcount=0;
    my $mincount=999999999;

    if ($type eq "swt" && $id){
        $logger->debug("Getting similar Subject Headings for Subjectid $id");

        my $titcount = OpenBib::Record::Subject->new({database=>$database, id => $id})->get_number_of_titles;

        # Nur 'praezisere' Schlagworte werden analysiert
        if ($titcount < 100){
            my $request = $dbh->prepare("select distinct c2.subjectid as id from title_subject as c1 left join title_subject as c2 on c1.titleid=c2.titleid where c1.subjectid=? and c2.subjectid != ?");
            $request->execute($id,$id);

            while (my $result=$request->fetchrow_hashref){
                my $similarid = $result->{id};
                
                my $record=OpenBib::Record::Subject->new({database=>$database});
                $record->load_name({dbh => $dbh, id=>$similarid});
                my $content=$record->name_as_string;
                
                # Ausgabe der Anzahl verk"upfter Titel
                my $sqlrequest="select count(distinct titleid) as conncount from title_subject where subjectid=?";
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
                
                push @{$similar_subjects_ref}, {
                    id      => $similarid,
                    item    => $content,
                    count   => $count,
                };            
            }
        }
    }

    if ($type eq "tit" && $id){
        $logger->debug("Getting similar Subject Headings for Titleid $id");

        my $request = $dbh->prepare("select distinct subjectid as id from title_subject where titleid=?");
        $request->execute($id);

        my @swtids=();
        my $swtid_lookup_ref = {}; 
        while (my $result=$request->fetchrow_hashref){
            $swtid_lookup_ref->{$result->{id}}=1;
            push @swtids, $result->{id};
        }

        my %similar_done = ();
        foreach my $swtid (@swtids){
            
            my $titcount = OpenBib::Record::Subject->new({database=>$database, id => $swtid})->get_number_of_titles;

            # Nur 'praezisere' Schlagworte werden analysiert
            if ($titcount < 100){
                #$request = $dbh->prepare("select distinct targetid as id from conn where sourcetype=1 and targettype=4 and targetid != ? and sourceid in (select sourceid from conn where sourcetype=1 and targettype=4 and targetid = ?)");
                $request = $dbh->prepare("select distinct c2.subjectid as id, count(c2.titleid) as titcount from title_subject as c1 left join title_subject as c2 on c1.titleid=c2.titleid where c1.subjectid=? and c2.subjectid != ? group by c2.titleid,c2.subjectid");
                $request->execute($swtid,$swtid);
                
                while (my $result=$request->fetchrow_hashref){
                    my $similarid       = $result->{id};
                    my $similartitcount = $result->{titcount};
                    #my $similartitcount = OpenBib::Record::Subject->new({database=>$database, id => $similarid})->get_number_of_titles;
                    
                    # Wenn das zu einem Schlagwort benachbarte Schlagwort schon im
                    # aktuellen Titel enthalten ist, dann ignorieren
                    next if (exists $swtid_lookup_ref->{$similarid});
                    
                    # Counts bzgl verschiedener Schlagworte des aktuellen Titels werden alle gezaehlt
                    if (!exists $tit_swt_count_ref->{$similarid}){
                        $tit_swt_count_ref->{$similarid}=$similartitcount;
                    }
                    else {
                        $tit_swt_count_ref->{$similarid}+=$similartitcount;
                    }
                    
                    # Jetzt wurde gezaehlt, aber ein Eintrag muss nicht angelegt werden.
                    if (exists $similar_done{$similarid}){
                        next;
                    }
                    else {
                        $similar_done{$similarid}=1;
                    }
                    
                    my $record=OpenBib::Record::Subject->new({database=>$database});
                    $record->load_name({dbh => $dbh, id=>$similarid});
                    my $content=$record->name_as_string;
                    
                    push @{$similar_subjects_ref}, {
                        id      => $similarid,
                        item    => $content,
                        #                    count   => $count,
                    };            
                }
            }
            
            foreach my $single_subject_ref (@{$similar_subjects_ref}){
                my $count=$tit_swt_count_ref->{$single_subject_ref->{id}}/2;
                
                $single_subject_ref->{count} = $count;
                
                if ($maxcount < $count){
                    $maxcount = $count;
                }
                
                if ($mincount > $count){
                    $mincount = $count;
                }
            }
        }
    }

    $similar_subjects_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $similar_subjects_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => 'log'});
    
    my $sorted_similar_subjects_ref ;
    @{$sorted_similar_subjects_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$similar_subjects_ref};

    my $ttdata = {
        record           => OpenBib::Record::Title->new({config => $config}),
        format           => $format,
        similar_subjects => $sorted_similar_subjects_ref,
        database         => $database,
    };

    return $self->print_page($config->{tt_connector_similarsubjects_tname},$ttdata);
}

1;
