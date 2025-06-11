use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use utf8;

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->get_ok('/portal/lbs/search.html?l=de' => form => { 'fs' => 'Schlosser LaTeX' })->status_is(200)->content_like(qr/Wissenschaftliche Arbeiten schreiben mit LaTeX : Leitfaden für Einsteiger/);

$t->get_ok('/portal/lbs/search.json?l=de' => form => { 'fs' => 'Schlosser LaTeX' })->status_is(200)->json_like('/records/0/fields/T0250/0/content' => qr/7., überarbeitete Auflage/);

$t->get_ok('/portal/lbs/search.json?l=de' => form => { 'id' => '991039633169706476'})->status_is(200)->json_like('/records/0/fields/T0250/0/content' => qr/7., überarbeitete Auflage/);

$t->get_ok('/portal/lbs/search.json?l=de' => form => { 'per' => 'Schlosser, Joachim'})->status_is(200)->json_like('/records/0/fields/T0250/0/content' => qr/7., überarbeitete Auflage/);

# Clear all cookies
$t->reset_session;

done_testing();
