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

# Profiles
#$t->post_ok('/portal/openbib/profiles' => json => { 'l' => 'de', 'profilename' => 'unikatalog', 'description' => 'Universitätskatalg' })->status_is(201)->json_is('/profilename' => 'unikatalog');

#$t->put_ok('/portal/openbib/profiles/id/unikatalog' => json => { 'l' => 'de', 'profilename' => 'unikatalog', 'description' => 'Universitätskatalog' })->status_is(200)->json_is('/profilename' => 'unikatalog');

$t->post_ok('/portal/openbib/profiles/id/unikatalog/orgunits' => json => { 'l' => 'de', 'orgunitname' => 'books', 'description' => 'Bücher &amp; Mehr' })->status_is(201)->json_is('/orgunitname' => 'books');

$t->put_ok('/portal/openbib/profiles/id/unikatalog/orgunits/id/books' => json => { 'l' => 'de', 'orgunitname' => 'books', 'description' => 'Bücher &amp; Mehr', 'nr' => 1, databases => ['lbs'], 'own_index' => 0  })->status_is(200)->json_is('/orgunitname' => 'books');

print $result,"\n";

# Clear all cookies
$t->reset_session;

done_testing();
