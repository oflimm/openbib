#####################################################################
#
#  OpenBib::Enrichment
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Enrichment;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use Business::ISBN;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable ();

use OpenBib::Config;
use OpenBib::Database::DBI;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    return $self;
}

sub get_db_histogram_of_occurence {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $content           = exists $arg_ref->{content}
        ? $arg_ref->{content}        : undef;
    my $category          = exists $arg_ref->{category}
        ? $arg_ref->{category}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);

    return () unless (defined $content && defined $category && defined $dbh);
    
    my $request=$dbh->prepare("select dbname,count(id) as idcount from all_isbn as i,normdata as n where n.category=? and n.content=? and n.isbn=i.isbn group by dbname order by idcount DESC") or $logger->error($DBI::errstr);
    $request->execute($category,$content) or $logger->error($DBI::errstr);

    my $histogram_ref = {
        content => $content,
    };
    
    while (my $result=$request->fetchrow_hashref){
        my $count  = $result->{idcount};
        my $dbname = $result->{dbname};
        push @{$histogram_ref->{histogram}}, {
            dbname => $dbname ,
            count  => $count,
        };

        $histogram_ref->{count}=$histogram_ref->{count}+1;
    }

    return $histogram_ref;
}

sub get_additional_normdata {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} unless (defined $isbn && defined $dbh);

    # Normierung auf ISBN13
    $isbn = OpenBib::Common::Util::to_isbn13($isbn);
    
    my $reqstring="select category,content from normdata where isbn=? order by category,indicator";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

    my $normset_ref = {};
    
    # Anreicherung der Normdaten
    while (my $res=$request->fetchrow_hashref) {
        my $category   = "E".sprintf "%04d",$res->{category };
        my $content    =        decode_utf8($res->{content});

        push @{$normset_ref->{$category}}, $content;
    }

    $logger->debug(YAML::Dump($normset_ref));

    return $normset_ref;

}

sub get_similar_isbns {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $isbn          = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} unless (defined $isbn && defined $dbh);

    # Normierung auf ISBN13
    $isbn = OpenBib::Common::Util::to_isbn13($isbn);

    my $reqstring="select isbn from similar_isbn where match (isbn) against (?)";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
    my $similar_isbn_ref = {};
    while (my $res=$request->fetchrow_hashref) {
        my $similarisbnstring = $res->{isbn};
        foreach my $similarisbn (split(':',$similarisbnstring)){
            $similar_isbn_ref->{$similarisbn}=1 if ($similarisbn ne $isbn);
        }
    }

    return $similar_isbn_ref;
}

1;
