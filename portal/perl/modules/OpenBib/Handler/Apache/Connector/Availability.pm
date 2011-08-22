####################################################################
#
#  OpenBib::Handler::Apache::Connector::Availability
#
#  Dieses File ist (C) 2008-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::Availability;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::URI ();
use APR::URI ();
use APR::Table ;

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
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'  => 'show_collection', # Obsolete, to be removed
        'isbn'             => 'show_collection_by_isbn',
        'bibkey'           => 'show_collection_by_bibkey',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $client_ip="";
    
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $viewdb_lookup_ref = {};
    foreach my $viewdb ($config->get_viewdbs($view)){
        $viewdb_lookup_ref->{$viewdb}=1;
    }

    my $id_type = $self->identify_type_of_id;

    if ($id_type eq "isbn"){
        $self->show_collection_by_isbn;
    }
    elsif ($id_type eq "bibkey"){
        $self->show_collection_by_bibkey;
    }

    return;
}

sub show_collection_by_isbn {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $client_ip="";
    
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $viewdb_lookup_ref = {};
    foreach my $viewdb ($config->get_viewdbs($view)){
        $viewdb_lookup_ref->{$viewdb}=1;
    }
    
    $id =~s/^(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)$/$1$2$3$4$5$6$7$8$9$10/g;
    $id =~s/^(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)$/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
    
    # Normierung auf ISBN13
    my $isbnXX     = Business::ISBN->new($id);
    
    if (defined $isbnXX && $isbnXX->is_valid){
        $id = $isbnXX->as_isbn13->as_string;
    }
    else {
        return Apache2::Const::OK;
    }
    
    my $isbn = OpenBib::Common::Util::grundform({
        category => '0540',
        content  => $id,
    });
    
    # Verbindung zur SQL-Datenbank herstellen
    my $enrichdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    # 1.) Ist dieser Titel im KUG vorhanden? ja/nein
    # 2.) Wo ist er vorhanden (Katalogname/ID/PermaLink)
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    my $reqstring="select distinct id,dbname from all_isbn where isbn=?";
    my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    while (my $res=$request->fetchrow_hashref) {
        my $id         = $res->{id};
        my $database   = $res->{dbname};
        
        # Verfuegbarkeit ist immer im Kontext des Views zu sehen!
        if ($viewdb_lookup_ref->{$database}){
            $logger->debug("Adding Title with ID $id in DB $database");
            $recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
        }
    }
    
    $recordlist->load_brief_records;
    
    # 3.) Gibt es andere Ausgaben, die im KUG vorhanden sind? (Katalogname/ID/PermaLink)
    
    # Anreicherung mit 'aehnlichen' (=andere Auflage, Sprache) Titeln aus allen Katalogen
    my $similar_recordlist = new OpenBib::RecordList::Title();
    
    $reqstring="select isbn from similar_isbn where match (isbn) against (?)";
    $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    my $similar_isbn_ref = {};
    while (my $res=$request->fetchrow_hashref) {
        my $similarisbnstring = $res->{isbn};
        foreach my $similarisbn (split(':',$similarisbnstring)){
            $similar_isbn_ref->{$similarisbn}=1 if ($similarisbn ne $isbn);
        }
    }
    
    my @similar_args = keys %$similar_isbn_ref;
    
    if (@similar_args){
        my $in_select_string = join(',',map {'?'} @similar_args);
        
        $logger->debug("InSelect $in_select_string");
        
        $reqstring="select distinct id,dbname from all_isbn where isbn in ($in_select_string) order by dbname";
        
        $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute(@similar_args) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $id         = $res->{id};
            my $database   = $res->{dbname};
            
            if (exists $viewdb_lookup_ref->{$database}){
                $similar_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
            }
        }
    }
    
    $similar_recordlist->load_brief_records;
    $request->finish();
    $logger->debug("Enrich: $isbn -> $reqstring");
    
    my $ttdata = {
        dbinfo               => $dbinfotable,
        key                  => $id,
        available_recordlist => $recordlist,
        similar_recordlist   => $similar_recordlist,
    };

    $self->print_page($config->{tt_connector_availability_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_collection_by_bibkey {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $client_ip="";
    
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $viewdb_lookup_ref = {};
    foreach my $viewdb ($config->get_viewdbs($view)){
        $viewdb_lookup_ref->{$viewdb}=1;
    }

    # Verbindung zur SQL-Datenbank herstellen
    my $enrichdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    # 1.) Ist dieser Titel im KUG vorhanden? ja/nein
    # 2.) Wo ist er vorhanden (Katalogname/ID/PermaLink)
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    my $reqstring="select distinct id,dbname from all_isbn where isbn=?";
    my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($id) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    my $this_id;
    my $this_database;
    while (my $res=$request->fetchrow_hashref) {
        my $id         = $res->{id};
        my $database   = $res->{dbname};
        
        if (exists $viewdb_lookup_ref->{$database}){
            ($this_id,$this_database)=($id,$database);
            $recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
        }
    }
    
    $recordlist->load_brief_records;
    
    # 3.) Gibt es andere Ausgaben, die im KUG vorhanden sind? (Katalogname/ID/PermaLink)
    #     Das ist nur mit ISBN moeglich. Daher bestimmen, welche ISBN dem bibkey zugeordnet ist.
    
    $reqstring="select distinct isbn from all_isbn where  id=? and dbname=?";
    $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($this_id,$this_database) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    my $isbn = "";
    while (my $res=$request->fetchrow_hashref) {
        $isbn       = $res->{isbn};
    }
    
    # Anreicherung mit 'aehnlichen' (=andere Auflage, Sprache) Titeln aus allen Katalogen
    my $similar_recordlist = new OpenBib::RecordList::Title();
    
    $reqstring="select isbn from similar_isbn where match (isbn) against (?)";
    $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    my $similar_isbn_ref = {};
    while (my $res=$request->fetchrow_hashref) {
        my $similarisbnstring = $res->{isbn};
        foreach my $similarisbn (split(':',$similarisbnstring)){
            $similar_isbn_ref->{$similarisbn}=1 if ($similarisbn ne $isbn);
        }
    }
    
    my @similar_args = keys %$similar_isbn_ref;
    
    if (@similar_args){
        my $in_select_string = join(',',map {'?'} @similar_args);
        
        $logger->debug("InSelect $in_select_string");
        
        $reqstring="select distinct id,dbname from all_isbn where isbn in ($in_select_string) order by dbname";
        
        $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute(@similar_args) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $id         = $res->{id};
            my $database   = $res->{dbname};
            
            if (exists $viewdb_lookup_ref->{$database}){
                $similar_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
            }
        }
    }
    
    $similar_recordlist->load_brief_records;
    $request->finish();
    $logger->debug("Enrich: $isbn -> $reqstring");
    
    my $ttdata = {
        dbinfo               => $dbinfotable,
        have_bibkey          => 1,
        key                  => $id,
        available_recordlist => $recordlist,
        similar_recordlist   => $similar_recordlist,
    };

    $self->print_page($config->{tt_connector_availability_tname},$ttdata);

    return Apache2::Const::OK;
}

sub identify_type_of_id {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    if    ($id =~m/^(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/ || $id=~m/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)$/){
        $logger->debug("$id is of type ISBN");
        return 'isbn';
    }
    elsif ($id =~m/^1[0-9a-f]{32}$/){
        $logger->debug("$id is of type Bibkey");
        return 'bibkey';
    }

    return '';
}

1;
