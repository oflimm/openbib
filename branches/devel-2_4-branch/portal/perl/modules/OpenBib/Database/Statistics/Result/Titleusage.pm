package OpenBib::Database::Statistics::Result::Titleusage;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Titleusage

=cut

__PACKAGE__->table("titleusage");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_nullable: 1

=head2 tstamp

  data_type: 'bigint'
  is_nullable: 1

=head2 tstamp_year

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_month

  data_type: 'tinyint'
  is_nullable: 1

=head2 tstamp_day

  data_type: 'tinyint'
  is_nullable: 1

=head2 isbn

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 dbname

  data_type: 'varchar'
  is_nullable: 1
  size: 25

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 origin

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp_year",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_month",
  { data_type => "tinyint", is_nullable => 1 },
  "tstamp_day",
  { data_type => "tinyint", is_nullable => 1 },
  "isbn",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "dbname",
  { data_type => "varchar", is_nullable => 1, size => 25 },
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "origin",
  { data_type => "integer", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-05-14 11:16:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:iEfj/elQJBKWAK/1Zol/cQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
