use utf8;
package OpenBib::Schema::System::Result::Authtoken;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Authtoken

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<authtoken>

=cut

__PACKAGE__->table("authtoken");

=head1 ACCESSORS

=head2 id

  data_type: 'uuid'
  is_nullable: 0
  size: 16

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 type

  data_type: 'text'
  is_nullable: 1

=head2 authkey

  data_type: 'text'
  is_nullable: 1

=head2 mixed_bag

  data_type: 'jsonb'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "uuid", is_nullable => 0, size => 16 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "authkey",
  { data_type => "text", is_nullable => 1 },
  "mixed_bag",
  { data_type => "jsonb", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NUivsUFe2rBnynX5GOUWKg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
