package OpenBib::Database::System::Result::Review;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Review

=cut

__PACKAGE__->table("review");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=head2 nickname

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 30

=head2 title

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 100

=head2 reviewtext

  data_type: 'mediumtext'
  is_nullable: 0

=head2 rating

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 dbname

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  default_value: 0
  is_nullable: 0
  size: 255

=head2 titleisbn

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 14

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "nickname",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 30 },
  "title",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 100 },
  "reviewtext",
  { data_type => "mediumtext", is_nullable => 0 },
  "rating",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "dbname",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", default_value => 0, is_nullable => 0, size => 255 },
  "titleisbn",
  { data_type => "char", default_value => "", is_nullable => 0, size => 14 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

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

=head2 reviewratings

Type: has_many

Related object: L<OpenBib::Database::System::Result::Reviewrating>

=cut

__PACKAGE__->has_many(
  "reviewratings",
  "OpenBib::Database::System::Result::Reviewrating",
  { "foreign.reviewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-11 11:51:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aMuMOcFAgzfw1BRwSisLyg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
