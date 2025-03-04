use utf8;
package OpenBib::Schema::System::Result::Networkinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Networkinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<networkinfo>

=cut

__PACKAGE__->table("networkinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'networkinfo_id_seq'

=head2 network

  data_type: 'cidr'
  is_nullable: 0

=head2 country

  data_type: 'text'
  is_nullable: 1

=head2 country_name

  data_type: 'text'
  is_nullable: 1

=head2 continent

  data_type: 'text'
  is_nullable: 1

=head2 subdivision

  data_type: 'text'
  is_nullable: 1

=head2 subsubdivision

  data_type: 'text'
  is_nullable: 1

=head2 city

  data_type: 'text'
  is_nullable: 1

=head2 is_eu

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "networkinfo_id_seq",
  },
  "network",
  { data_type => "cidr", is_nullable => 0 },
  "country",
  { data_type => "text", is_nullable => 1 },
  "country_name",
  { data_type => "text", is_nullable => 1 },
  "continent",
  { data_type => "text", is_nullable => 1 },
  "subdivision",
  { data_type => "text", is_nullable => 1 },
  "subsubdivision",
  { data_type => "text", is_nullable => 1 },
  "city",
  { data_type => "text", is_nullable => 1 },
  "is_eu",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:z1IBS/9HnnV/psTun65BeA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
