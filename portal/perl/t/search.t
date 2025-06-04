use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->get_ok('/portal/openbib/search.html?l=de' => form => { 'fs' => 'The LaTeX companion'})->status_is(200)->content_like(qr/Goossens, Michel ; Mittelbach, Frank ; Samarin, Alexander/);

$t->get_ok('/portal/openbib/search.json?l=de' => form => { 'fs' => 'The LaTeX companion'})->status_is(200)->json_like('/records/0/fields/PC0001/0/content' => qr/Goossens, Michel ; Mittelbach, Frank ; Samarin, Alexander/);

$t->get_ok('/portal/openbib/search.json?l=de' => form => { 'fs' => 'id:1'})->status_is(200)->json_like('/records/0/fields/PC0001/0/content' => qr/Goossens, Michel ; Mittelbach, Frank ; Samarin, Alexander/);

$t->get_ok('/portal/openbib/search.json?l=de' => form => { 'id' => '1'})->status_is(200)->json_like('/records/0/fields/PC0001/0/content' => qr/Goossens, Michel ; Mittelbach, Frank ; Samarin, Alexander/);

done_testing();
