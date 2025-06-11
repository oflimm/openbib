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

$t->get_ok('/portal/openbib/admin/authenticators.json' => json => {});

my $authenticatorid = $t->tx->res->json('/authenticators/0/id');

# Views
$t->post_ok('/portal/openbib/views' => json => { 'l' => 'de', 'viewname' => 'lbs', 'description' => 'USB Köln / Lehrbuchsammlung', profilename => 'unikatalog'})->status_is(201)->json_is('/viewname' => 'lbs');

$t->put_ok('/portal/openbib/views/id/lbs' => json => { 'l' => 'de', 'viewname' => 'lbs', 'description' => 'USB Köln / Lehrbuchsammlung', profilename => 'unikatalog', 'active' => 1, databases => ['lbs'], locations => ['DE-38'], authenticators => [ $authenticatorid ] })->status_is(200)->json_is('/viewname' => 'lbs');

# Clear all cookies
$t->reset_session;

done_testing();
