package OpenBib::Database::User::Fieldchoice;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("fieldchoice");
__PACKAGE__->add_columns(
    "userid",
    {
        data_type => "BIGINT",
        default_value => 0,
        is_nullable => 0,
        size => 20
    },
    "fs",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "hst",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "verf",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "kor",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "swt",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1 },
    "notation",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "isbn",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "issn",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "sign",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "mart",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "hststring",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "inhalt",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "gtquelle",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
    "ejahr",
    {
        data_type => "TINYINT",
        default_value => undef,
        is_nullable => 1,
        size => 1
    },
);

1;
