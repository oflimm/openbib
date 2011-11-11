package OpenBib::Database::System::Result::TitTag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::TitTag

=cut

__PACKAGE__->table("tit_tag");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 tagid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 titleisbn

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 14

=head2 titlecache

  data_type: 'blob'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "tagid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "titleisbn",
  { data_type => "char", default_value => "", is_nullable => 0, size => 14 },
  "titlecache",
  { data_type => "blob", is_nullable => 1 },
  "type",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 tagid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Tag>

=cut

__PACKAGE__->belongs_to(
  "tagid",
  "OpenBib::Database::System::Result::Tag",
  { id => "tagid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Database::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-11 11:51:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NmiQTVKoD4B5elUr8vTRRg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
