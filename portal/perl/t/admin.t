use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use OpenBib::Config;

my $config = OpenBib::Config->new;

my $adminuser = $config->get('adminuser');
my $adminpw   = $config->get('adminpasswd');

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->ua->max_redirects(5);

$t->post_ok('/portal/unikatalog/login' => form => { 'l' => 'de', 'authenticatorid' => '4', 'username' => $adminuser, 'password' => 'wrong_password', 'redirect_to' => '%2Fportal%2Funikatalog%2Fhome.html%3Fl%3Dde' })->status_is(200)->content_like(qr/Sie konnten mit Ihrer angegebenen Benutzerkennung und Passwort nicht erfolgreich authentifiziert werden/);

$t->post_ok('/portal/unikatalog/login' => form => { 'l' => 'de', 'authenticatorid' => '4', 'username' => $adminuser, 'password' => $adminpw, 'redirect_to' => '%2Fportal%2Funikatalog%2Fhome.html%3Fl%3Dde' })->status_is(200)->content_like(qr/Administration/);

$t->get_ok('/portal/unikatalog/admin/clusters')->status_is(200)->content_like(qr/Bereits existierende Cluster/);

$t->get_ok('/portal/unikatalog/admin/servers')->status_is(200)->content_like(qr/Bereits existierende Rechner zur Lastverteilung/);

$t->get_ok('/portal/unikatalog/admin/locations')->status_is(200)->content_like(qr/Bereits existierende Standorte: \d+/);

$t->get_ok('/portal/unikatalog/admin/databases')->status_is(200)->content_like(qr/Bereits existierende Kataloge: \d+/);

$t->get_ok('/portal/unikatalog/admin/profiles')->status_is(200)->content_like(qr/Bereits existierende Katalog-Profile: \d+/);

$t->get_ok('/portal/unikatalog/admin/profiles/id/unikatalog/edit.html?l=de')->status_is(200)->content_like(qr/Bereits existierende Organisationseinheiten/);

$t->get_ok('/portal/unikatalog/admin/profiles/id/unikatalog/orgunits/id/books/edit.html?l=de')->status_is(200)->content_like(qr/Organisationseinheit bearbeiten/);
$t->get_ok('/portal/unikatalog/admin/views')->status_is(200)->content_like(qr/Bereits existierende Views: \d+/);

$t->get_ok('/portal/unikatalog/admin/views.json')->status_is(200)->json_is('/views/0/id' => 'abgleich_ebookpda');


done_testing();
