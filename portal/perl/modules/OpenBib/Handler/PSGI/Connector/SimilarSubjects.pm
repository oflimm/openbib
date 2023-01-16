####################################################################
#
#  OpenBib::Handler::PSGI::Connector::SimilarSubjects
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

package OpenBib::Handler::PSGI::Connector::SimilarSubjects;

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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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

	my $sql_statement = << 'SQL';
select title_subject.subjectid as thisid, content, count(*) as thiscount from title_subject
INNER JOIN subject_fields ON title_subject.subjectid = subject_fields.subjectid
where subject_fields.field = 800 and title_subject.subjectid IN
(select distinct c2.subjectid
from title_subject as c1
left join title_subject as c2
on c1.titleid=c2.titleid
where c1.subjectid IN (select distinct subjectid from title_subject where titleid = ?) and
c2.subjectid not in (select distinct subjectid from title_subject where titleid = ?))
group by title_subject.subjectid, content
having count(*) < 100
order by count(*) DESC
limit 15;
SQL
        my $request = $dbh->prepare($sql_statement);
	
	$request->execute($id,$id);

	while (my $result=$request->fetchrow_hashref){
	    my $similarid       = $result->{thisid};
	    my $similartitcount = $result->{thiscount};
	    
	    my $content = $result->{content};
                    
	    push @{$similar_subjects_ref}, {
		id      => $similarid,
		item    => $content,
		count => $similartitcount,
	    };            
            
        }
    }
    
    my $sorted_similar_subjects_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $similar_subjects_ref, 
        max   => $similar_subjects_ref->[0]->{count}, 
        min   => $similar_subjects_ref->[-1]->{count}, 
        type  => 'log'});
    
    my $ttdata = {
        record           => OpenBib::Record::Title->new({config => $config}),
        format           => $format,
        similar_subjects => $sorted_similar_subjects_ref,
        database         => $database,
    };
    return $self->print_page($config->{tt_connector_similarsubjects_tname},$ttdata);
}

1;
