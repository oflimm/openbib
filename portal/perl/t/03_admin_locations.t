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

# Locations
$t->post_ok('/portal/openbib/locations' => json => { 'l' => 'de', 'identifier' => 'DE-38', 'type' => 'ISIL', 'description' => 'Universitäts- und Stadtbibliothek Köln', 'shortdesc' => 'USB Köln' })->status_is(201)->json_is('/description' => 'Universitäts- und Stadtbibliothek Köln');

$t->put_ok("/portal/openbib/locations/id/DE-38" => json => { 'l' => 'de', 'identifier' => 'DE-38', 'type' => 'ISIL', 'description' => 'Universitäts- und Stadtbibliothek Köln', 'shortdesc' => 'USB Köln', fields => { '0010' => [ { 'subfield' => '', mult => '1', content => 'Universitäts- und Stadtbibliothek Köln' } ], '0010' => [ { 'subfield' => '', mult => '1', content => '' } ], '0015' => [ { 'subfield' => '', mult => '1', content => 'usb' } ], '0020' => [ { 'subfield' => '', mult => '1', content => 'Universitätsstr. 33<br /> 50931 Köln' } ], '0040' => [ { 'subfield' => '', mult => '1', content => 'Geben Sie im <a class="exturl" href="http://www.uni-koeln.de/uni/plan/interaktiv/"> Lageplan </a> den Namen des gewünschten Instituts ein.' } ], '0050' => [ { 'subfield' => '', mult => '1', content => 'nein' } ], '0060' => [ { 'subfield' => '', mult => '1', content => 'Anmeldung u. Ausleihe: 0221 / 470 - 3316' } ], '0070' => [ { 'subfield' => '', mult => '1', content => '0221 / 470 - 5166' } ], '0080' => [ { 'subfield' => '', mult => '1', content => '<a class="exturl" href="mailto:sekret@ub.uni-koeln.de">sekret@ub.uni-koeln.de</a>' } ], '0110' => [ { 'subfield' => '', mult => '1', content => 'Lesesäle: Mo - Fr: 9.00-24.00 Uhr;<br /> Sa - So: 9.00-21.00 Uhr<br /> Andere Dienste siehe: <a class="exturl" href="https://ub.uni-koeln.de/die-usb/oeffnungszeiten-adressen" target="_blank">Öffnungszeiten</a>' } ], '0120' => [ { 'subfield' => '', mult => '1', content => 'ca. 3.300.000' } ], '0280' => [ { 'subfield' => '', mult => '1', content => '50.925755,6.928751' } ],  }   })->status_is(200)->json_is('/fields/L0280/0/content' => '50.925755,6.928751');

$t->get_ok('/portal/openbib/admin/locations')->status_is(200)->content_like(qr/Bereits existierende Standorte: \d+/);

# Clear all cookies
$t->reset_session;

done_testing();
