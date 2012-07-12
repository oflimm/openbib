package OpenBib::Schema::System::Result::ViewDb;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::ViewDb

=cut

__PACKAGE__->table("view_db");

=head1 ACCESSORS

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:koBmg7RoPNOWwldWiTJYXA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
