package OpenBib::Database::System::Result::Litlist;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Litlist

=cut

__PACKAGE__->table("litlist");

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

=head2 title

  data_type: 'text'
  is_nullable: 0

=head2 type

  data_type: 'integer'
  default_value: 1
  is_nullable: 0

=head2 lecture

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

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
  "title",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "integer", default_value => 1, is_nullable => 0 },
  "lecture",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
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

=head2 litlist_subjects

Type: has_many

Related object: L<OpenBib::Database::System::Result::LitlistSubject>

=cut

__PACKAGE__->has_many(
  "litlist_subjects",
  "OpenBib::Database::System::Result::LitlistSubject",
  { "foreign.litlistid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 litlistitems

Type: has_many

Related object: L<OpenBib::Database::System::Result::Litlistitem>

=cut

__PACKAGE__->has_many(
  "litlistitems",
  "OpenBib::Database::System::Result::Litlistitem",
  { "foreign.litlistid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 10:59:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:D7XA5R9lCTB9y6Ds0kqnyA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
