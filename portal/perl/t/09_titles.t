use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use utf8;

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->get_ok('/portal/lbs/databases/id/lbs/titles/id/991039633169706476.html?l=de' => form => { 'l' => 'de' })->status_is(200)->content_like(qr/Titel.*Wissenschaftliche Arbeiten schreiben mit LaTeX : Leitfaden für Einsteiger/);

$t->get_ok('/portal/lbs/databases/id/lbs/titles/id/991039633169706476.json?l=de' => form => { 'l' => 'de' })->status_is(200)->json_is('/fields/T0250/0/content' => '7., überarbeitete Auflage');

# Clear all cookies
$t->reset_session;

done_testing();
