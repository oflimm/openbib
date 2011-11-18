package OpenBib::Database::System::Result::SessionSearchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::SessionSearchprofile

=cut

__PACKAGE__->table("session_searchprofile");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 profileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "profileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Database::System::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Searchprofile>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Database::System::Result::Searchprofile",
  { id => "profileid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-18 10:20:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cjP9LllxaDTha8XMBqlOOA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
