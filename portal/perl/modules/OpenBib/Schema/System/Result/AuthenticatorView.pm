use utf8;
package OpenBib::Schema::System::Result::AuthenticatorView;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::AuthenticatorView

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<authenticator_view>

=cut

__PACKAGE__->table("authenticator_view");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'authenticator_view_id_seq'

=head2 authenticatorid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "authenticator_view_id_seq",
  },
  "authenticatorid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 authenticatorid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Authenticatorinfo>

=cut

__PACKAGE__->belongs_to(
  "authenticatorid",
  "OpenBib::Schema::System::Result::Authenticatorinfo",
  { id => "authenticatorid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wsSlw4+wSoL6/GX3474RpA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
