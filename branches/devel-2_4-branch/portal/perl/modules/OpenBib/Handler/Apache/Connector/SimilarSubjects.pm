####################################################################
#
#  OpenBib::Handler::Apache::Connector::SimilarSubjects
#
#  Dieses File ist (C) 2008-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::SimilarSubjects;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Business::ISBN;
use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use YAML;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
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
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $type           = $query->param('type')            || 'swt'; # oder tit
    my $id             = $query->param('id')              || '';
    my $content        = $query->param('content')         || '';
    my $isbn           = $query->param('isbn')            || '';
    my $database       = $query->param('db')        || '';
    my $format         = $query->param('format')          || 'ajax';

    if (!$database || !$type){
        OpenBib::Common::Util::print_warning($msg->maketext("Fehler."),$r,$msg);
        return Apache2::Const::OK;
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
            my $request = $dbh->prepare("select distinct c2.targetid as id from conn as c1 left join conn as c2 on c1.sourceid=c2.sourceid where c1.sourcetype=1 and c2.sourcetype=1 and c1.targettype=4 and c2.targettype=4 and c1.targetid=? and c2.targetid != ?");
            $request->execute($id,$id);

            while (my $result=$request->fetchrow_hashref){
                my $similarid = $result->{id};
                
                my $record=OpenBib::Record::Subject->new({database=>$database});
                $record->load_name({dbh => $dbh, id=>$similarid});
                my $content=$record->name_as_string;
                
                # Ausgabe der Anzahl verk"upfter Titel
                my $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=4";
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

    if ($type eq "notation" && $id){
        $logger->debug("Getting similar Subject Headings for classification $id");

        my $request = $dbh->prepare("select distinct targetid as id from conn where sourcetype=1 and targettype= and sourceid=?");
        $request->execute($id);

        my @swtids=();
        my $swtid_lookup_ref = {}; 
        while (my $result=$request->fetchrow_hashref){
            $swtid_lookup_ref->{$result->{id}}=1;
            push @swtids, $result->{id};
        }

        my %similar_done = ();
        foreach my $swtid (@swtids){
            my $record=OpenBib::Record::Subject->new({database=>$database});
            $record->load_name({dbh => $dbh, id=>$swtid});
            my $content=$record->name_as_string;
            
            push @{$similar_subjects_ref}, {
                        id      => $swtid,
                        item    => $content,
                        #                    count   => $count,
            };            
            


            
            #$request = $dbh->prepare("select distinct targetid as id from conn where sourcetype=1 and targettype=4 and targetid != ? and sourceid in (select sourceid from conn where sourcetype=1 and targettype=4 and targetid = ?)");
            $request = $dbh->prepare("select distinct c2.targetid as id, count(c2.sourceid) as titcount from conn as c1 left join conn as c2 on c1.sourceid=c2.sourceid where c1.sourcetype=1 and c2.sourcetype=1 and c1.targettype=4 and c2.targettype=4 and c1.targetid=? and c2.targetid != ? group by c2.sourceid");
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

        if ($type eq "tit" && $id){
        $logger->debug("Getting similar Subject Headings for Titleid $id");

        my $request = $dbh->prepare("select distinct targetid as id from conn where sourcetype=1 and targettype=4 and sourceid=?");
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
                $request = $dbh->prepare("select distinct c2.targetid as id, count(c2.sourceid) as titcount from conn as c1 left join conn as c2 on c1.sourceid=c2.sourceid where c1.sourcetype=1 and c2.sourcetype=1 and c1.targettype=4 and c2.targettype=4 and c1.targetid=? and c2.targetid != ? group by c2.sourceid");
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
        record           => OpenBib::Record::Title->new,
        format           => $format,
        similar_subjects => $sorted_similar_subjects_ref,
        database         => $database,
    };

    $self->print_page($config->{tt_connector_similarsubjects_tname},$ttdata);

    return Apache2::Const::OK;
}

1;
