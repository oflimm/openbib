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

=head2 viewname

  data_type: 'varchar'
  is_nullable: 1
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

  data_type: 'tinyint'
  is_nullable: 1

=head2 active

  data_type: 'tinyint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "viewname",
  { data_type => "varchar", is_nullable => 1, size => 20 },
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
  { data_type => "tinyint", is_nullable => 1 },
  "active",
  { data_type => "tinyint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("viewname", ["viewname"]);

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

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Profileinfo>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Database::System::Result::Profileinfo",
  { id => "profileid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 rssid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssid",
  "OpenBib::Database::System::Result::Rssinfo",
  { id => "rssid" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-01-06 13:01:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+9JH5gEyOCBt5rfwm7WUCw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
