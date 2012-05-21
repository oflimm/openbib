package OpenBib::Database::Statistics::Result::Eventlogjson;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Eventlogjson

=cut

__PACKAGE__->table("eventlogjson");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_nullable: 0

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

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 content

  data_type: 'mediumblob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_nullable => 0 },
  "tstamp",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp_year",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_month",
  { data_type => "tinyint", is_nullable => 1 },
  "tstamp_day",
  { data_type => "tinyint", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "content",
  { data_type => "mediumblob", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-05-14 11:16:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rCk4O33VXKih72JSHlH0dA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
