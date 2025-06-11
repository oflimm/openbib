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

$t->get_ok('/portal/openbib/admin/servers.json' => json => {});

my $serverid  = $t->tx->res->json('/servers/0/id');
my $clusterid = $t->tx->res->json('/servers/0/cluster/id');

$t->delete_ok("/portal/openbib/servers/id/$serverid" => json => {} )->status_is(200)->json_is('/success' => '1')->json_is('/id' => $serverid);

$t->delete_ok("/portal/openbib/clusters/id/$clusterid" => json => {} )->status_is(200)->json_is('/success' => '1')->json_is('/id' => $clusterid);

# Clear all cookies
$t->reset_session;

done_testing();
