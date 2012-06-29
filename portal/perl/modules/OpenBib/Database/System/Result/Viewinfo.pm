package OpenBib::Database::System::Result::Viewinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Viewinfo

=cut

__PACKAGE__->table("viewinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'viewinfo_id_seq'

=head2 viewname

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 rssid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 start_loc

  data_type: 'text'
  is_nullable: 1

=head2 servername

  data_type: 'text'
  is_nullable: 1

=head2 profileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 stripuri

  data_type: 'boolean'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "viewinfo_id_seq",
  },
  "viewname",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "rssid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "start_loc",
  { data_type => "text", is_nullable => 1 },
  "servername",
  { data_type => "text", is_nullable => 1 },
  "profileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "stripuri",
  { data_type => "boolean", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("uq_viewinfo_viewname", ["viewname"]);

=head1 RELATIONS

=head2 view_dbs

Type: has_many

Related object: L<OpenBib::Database::System::Result::ViewDb>

=cut

__PACKAGE__->has_many(
  "view_dbs",
  "OpenBib::Database::System::Result::ViewDb",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 rssid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssid",
  "OpenBib::Database::System::Result::Rssinfo",
  { id => "rssid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Profileinfo>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Database::System::Result::Profileinfo",
  { id => "profileid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 view_rsses

Type: has_many

Related object: L<OpenBib::Database::System::Result::ViewRss>

=cut

__PACKAGE__->has_many(
  "view_rsses",
  "OpenBib::Database::System::Result::ViewRss",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-27 13:44:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:CgGu2yzolXIfns0jV/xb3g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
