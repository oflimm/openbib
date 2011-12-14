package OpenBib::Database::Statistics::Result::Querycategory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Querycategory

=cut

__PACKAGE__->table("querycategory");

=head1 ACCESSORS

=head2 tstamp

  data_type: 'datetime'
  is_nullable: 1

=head2 viewname

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 fs

  data_type: 'tinyint'
  is_nullable: 1

=head2 hst

  data_type: 'tinyint'
  is_nullable: 1

=head2 verf

  data_type: 'tinyint'
  is_nullable: 1

=head2 kor

  data_type: 'tinyint'
  is_nullable: 1

=head2 swt

  data_type: 'tinyint'
  is_nullable: 1

=head2 notation

  data_type: 'tinyint'
  is_nullable: 1

=head2 isbn

  data_type: 'tinyint'
  is_nullable: 1

=head2 issn

  data_type: 'tinyint'
  is_nullable: 1

=head2 sign

  data_type: 'tinyint'
  is_nullable: 1

=head2 mart

  data_type: 'tinyint'
  is_nullable: 1

=head2 hststring

  data_type: 'tinyint'
  is_nullable: 1

=head2 inhalt

  data_type: 'tinyint'
  is_nullable: 1

=head2 gtquelle

  data_type: 'tinyint'
  is_nullable: 1

=head2 ejahr

  data_type: 'tinyint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "tstamp",
  { data_type => "datetime", is_nullable => 1 },
  "viewname",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "fs",
  { data_type => "tinyint", is_nullable => 1 },
  "hst",
  { data_type => "tinyint", is_nullable => 1 },
  "verf",
  { data_type => "tinyint", is_nullable => 1 },
  "kor",
  { data_type => "tinyint", is_nullable => 1 },
  "swt",
  { data_type => "tinyint", is_nullable => 1 },
  "notation",
  { data_type => "tinyint", is_nullable => 1 },
  "isbn",
  { data_type => "tinyint", is_nullable => 1 },
  "issn",
  { data_type => "tinyint", is_nullable => 1 },
  "sign",
  { data_type => "tinyint", is_nullable => 1 },
  "mart",
  { data_type => "tinyint", is_nullable => 1 },
  "hststring",
  { data_type => "tinyint", is_nullable => 1 },
  "inhalt",
  { data_type => "tinyint", is_nullable => 1 },
  "gtquelle",
  { data_type => "tinyint", is_nullable => 1 },
  "ejahr",
  { data_type => "tinyint", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-12-13 11:06:13
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:D/WvT5RfSZDr3aD+5Nf3SA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
