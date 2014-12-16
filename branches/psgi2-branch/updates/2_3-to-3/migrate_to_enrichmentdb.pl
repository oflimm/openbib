#!/usr/bin/perl

# Migrationsprogramm von EnrichmentDB-Inhalten aus v2.3 nach v3

use warnings;
use strict;
use utf8;

use DBI;
use Encode qw/encode_utf8 decode_utf8/;
use JSON::XS qw(encode_json decode_json);
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::Enrichment;

my $host   = $ARGV[0];
my $passwd = $ARGV[1];

# Hier anpassen, denn:
# Das Config-Objekt kann nicht verwendet werden, da es selbst eine Verbindung zur System-DB
# oeffnet und damit eine Entfernung der DB nicht moeglich ist!!!

my $enrichmntdbimodule = "Pg";
my $enrichmntdbhost    = "peterhof.ub.uni-koeln.de";
my $enrichmntdbname    = "openbib_enrichmnt";
my $enrichmntdbuser    = "root";
my $enrichmntdbpasswd  = $passwd; # oder fest ala "StrengGeheim"
my $enrichmntdbport    = "5432";

my $dbdesc_dir      = "/opt/openbib/db";

my $mysqlexe      = "/usr/bin/mysql -u $enrichmntdbuser --password=$enrichmntdbpasswd -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $enrichmntdbuser --password=$enrichmntdbpasswd -f";

system("echo \"*:*:*:$enrichmntdbuser:$enrichmntdbpasswd\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
system("/usr/bin/dropdb -U $enrichmntdbuser $enrichmntdbname");
system("/usr/bin/createdb -U $enrichmntdbuser -E UTF-8 -O $enrichmntdbuser $enrichmntdbname");

print STDERR "### Datendefinition einlesen\n";

system("/usr/bin/psql -U $enrichmntdbuser -f '$dbdesc_dir/postgresql/enrichmnt.sql' $enrichmntdbname");

my $oldenrichmntdbh = DBI->connect("DBI:mysql:dbname=enrichmnt;host=$host;port=3306", 'root', $passwd);

my $newschema;
        
eval {
    $newschema = OpenBib::Schema::Enrichment->connect("DBI:$enrichmntdbimodule:dbname=$enrichmntdbname;host=$enrichmntdbhost;port=$enrichmntdbport", $enrichmntdbuser, $enrichmntdbpasswd);
};
        
if ($@){
    print STDERR "Unable to connect schema to database openbib_enrichmnt: $@";
    exit;
}

# Migration EnrichmntDB

# normdata

my $enriched_content_by_isbn_ref = [];
my $enriched_content_by_issn_ref = [];
my $enriched_content_by_bibkey_ref = [];

my $request = $oldenrichmntdbh->prepare("select * from normdata");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $isbn        = $result->{isbn};
    my $origin      = $result->{origin};
    my $field       = $result->{category};
    my $subfield    = $result->{indicator};
    my $content     = $result->{content};

    push @$enriched_content_by_isbn_ref, {
        isbn     => $isbn,
        origin   => $origin,
        field    => $field,
        subfield => $subfield,
        content  => $result->{content},
    } if (length($isbn) == 13 );
    
    push @$enriched_content_by_issn_ref, {
        issn     => $isbn,
        origin   => $origin,
        field    => $field,
        subfield => $subfield,
        content  => $content,
    } if (length($isbn) == 8) ;
    
    push @$enriched_content_by_bibkey_ref, {
        bibkey    => $isbn,
        origin    => $origin,
        field     => $field,
        subfield  => $subfield,
        content   => $content,
    } if (length($isbn) > 30) ;

}

$newschema->resultset('EnrichedContentByIsbn')->populate($enriched_content_by_isbn_ref);
$newschema->resultset('EnrichedContentByIssn')->populate($enriched_content_by_issn_ref);
$newschema->resultset('EnrichedContentByBibkey')->populate($enriched_content_by_bibkey_ref);

# similar_isbn -> work_by_isbn via ThingISBN-XML-Datei
print STDERR "### similar_isbn -> work_by_isbn via ThingISBN-XML-Datei \n";

system("/usr/bin/psql -U $enrichmntdbuser -f '$dbdesc_dir/postgresql/enrichmnt_create_index.sql' $enrichmntdbname");

print STDERR "### ENDE der Migration \n";

