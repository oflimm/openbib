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
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-11-17 15:09:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BhczmjmxCzWLP94WD5AOlA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
