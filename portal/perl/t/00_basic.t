use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $location_is = sub {
    my ($t, $value, $desc) = @_;
    $desc ||= "Location: $value";
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return $t->success(like($t->tx->res->headers->location, qr|$value|, $desc));
};

my $t = Test::Mojo->new('OpenBib::Mojo');

$t->get_ok('/portal/openbib/home')->status_is(303)->$location_is('home.html\?l=de');

$t->get_ok('/portal/openbib/home.html')->status_is(303)->$location_is('home.html\?l=de');

$t->get_ok('/portal/openbib/home.html?l=de')->status_is(200)->content_like(qr/OpenBib Testkatalog/i);

done_testing();
