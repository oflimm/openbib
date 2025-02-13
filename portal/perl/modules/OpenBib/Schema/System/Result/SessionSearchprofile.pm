use utf8;
package OpenBib::Schema::System::Result::SessionSearchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::SessionSearchprofile

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<session_searchprofile>

=cut

__PACKAGE__->table("session_searchprofile");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 searchprofileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "searchprofileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 searchprofileid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Searchprofile>

=cut

__PACKAGE__->belongs_to(
  "searchprofileid",
  "OpenBib::Schema::System::Result::Searchprofile",
  { id => "searchprofileid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Schema::System::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:lNVYse7vAUlrfVtLjmYrtQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
