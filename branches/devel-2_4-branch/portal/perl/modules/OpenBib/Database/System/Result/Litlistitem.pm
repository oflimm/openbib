package OpenBib::Database::System::Result::Litlistitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Litlistitem

=cut

__PACKAGE__->table("litlistitem");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 litlistid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=head2 titid

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 titisbn

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 14

=head2 titdb

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titcache

  data_type: 'blob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "litlistid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "titid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "titisbn",
  { data_type => "char", default_value => "", is_nullable => 0, size => 14 },
  "titdb",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titcache",
  { data_type => "blob", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 litlistid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Litlist>

=cut

__PACKAGE__->belongs_to(
  "litlistid",
  "OpenBib::Database::System::Result::Litlist",
  { id => "litlistid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 10:59:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:E0XupP1VgY/+MEUrZhTXdA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
