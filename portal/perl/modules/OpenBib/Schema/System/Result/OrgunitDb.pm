package OpenBib::Schema::System::Result::OrgunitDb;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::OrgunitDb

=cut

__PACKAGE__->table("orgunit_db");

=head1 ACCESSORS

=head2 orgunitid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "orgunitid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 orgunitid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Orgunitinfo>

=cut

__PACKAGE__->belongs_to(
  "orgunitid",
  "OpenBib::Schema::System::Result::Orgunitinfo",
  { id => "orgunitid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "dbid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:U0umo3yB7/9kELaq8KQEvw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
