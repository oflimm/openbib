use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use OpenBib::Config;

my $config = OpenBib::Config->new;

my $adminuser = $config->get('adminuser');
my $adminpw   = $config->get('adminpasswd');

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->ua->max_redirects(5);

my $csrftoken = $t->ua->get( '/portal/openbib/login.html?l=de' )->res->dom->at('input[name=csrf_token]')->{'value'};

$t->post_ok('/portal/openbib/login' => form => { 'l' => 'de', 'authenticatorid' => '1', 'username' => $adminuser, 'password' => 'wrong_password', 'redirect_to' => '%2Fportal%2Fopenbib%2Fhome.html%3Fl%3Dde', 'csrf_token' => $csrftoken })->status_is(200)->content_like(qr/Sie konnten mit Ihrer angegebenen Benutzerkennung und Passwort nicht erfolgreich authentifiziert werden/);

$t->post_ok('/portal/openbib/login' => form => { 'l' => 'de', 'authenticatorid' => '1', 'username' => $adminuser, 'password' => $adminpw, 'redirect_to' => '%2Fportal%2Fopenbib%2Fhome.html%3Fl%3Dde', 'csrf_token' => $csrftoken })->status_is(200)->content_like(qr/Administration/);

$t->get_ok('/portal/openbib/admin/locations/id/DE-38.json' => json => {});

my $locationid = $t->tx->res->json('/id');

# Databases
$t->post_ok('/portal/openbib/databases' => json => { 'l' => 'de', 'dbname' => 'lbs', 'description' => 'USB Köln / Lehrbuchsammlung', 'shortdesc' => 'USBK / LBS', 'system' => 'MARC', 'schema' => 'marc21', searchengines => [ 'xapian', 'elasticsearch' ], 'locationid' => $locationid, 'sigel' => '38', 'active' => 'true', 'host' => 'opendata.ub.uni-koeln.de', 'protocol' => 'https', 'remotepath' => 'dumps/DE-38-USB_Koeln-Lehrbuchsammlung', 'titlefile' => 'meta.title.gz', 'personfile' => 'meta.person.gz', 'corporatebodyfile' => 'meta.corporatebody.gz', 'subjectfile' => 'meta.subject.gz', 'classificationfile' => 'meta.classification.gz', 'holdingfile' => 'meta.holding.gz', 'autoconvert' => 'false'})->status_is(201)->json_is('/titlefile' => 'meta.title.gz');

my $result = $t->tx->res->body;

print $result,"\n";

# Clear all cookies
$t->reset_session;

done_testing();
