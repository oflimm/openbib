use utf8;
package OpenBib::Schema::System::Result::UserDb;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::UserDb

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<user_db>

=cut

__PACKAGE__->table("user_db");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_db_id_seq'

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbid

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
    sequence          => "user_db_id_seq",
  },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "dbid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2014-09-24 11:40:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:2ogL464HmQVJ5Mu+6bhN7g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
