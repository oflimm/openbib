use utf8;
package OpenBib::Schema::Statistics::Result::Eventlogjson;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Eventlogjson

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<eventlogjson>

=cut

__PACKAGE__->table("eventlogjson");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'eventlogjson_id_seq'

=head2 sid

  data_type: 'bigint'
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 0

=head2 tstamp_year

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_month

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_day

  data_type: 'smallint'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "eventlogjson_id_seq",
  },
  "sid",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 0 },
  "tstamp_year",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_month",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_day",
  { data_type => "smallint", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=item * L</tstamp>

=back

=cut

__PACKAGE__->set_primary_key("id", "tstamp");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:48:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5ZHtrSiiMgJkfGXuxGEdXQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
