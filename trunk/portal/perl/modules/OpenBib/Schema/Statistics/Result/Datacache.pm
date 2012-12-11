use utf8;
package OpenBib::Schema::Statistics::Result::Datacache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Datacache

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<datacache>

=cut

__PACKAGE__->table("datacache");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 subkey

  data_type: 'text'
  is_nullable: 1

=head2 data

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "text", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "subkey",
  { data_type => "text", is_nullable => 1 },
  "data",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-12-11 15:02:29
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:2zjxfKvD2ZcN2Qst6lRTEA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
