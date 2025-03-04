use utf8;
package OpenBib::Schema::System::Result::Viewinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Viewinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<viewinfo>

=cut

__PACKAGE__->table("viewinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'viewinfo_id_seq'

=head2 viewname

  data_type: 'text'
  is_nullable: 0

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

=head2 own_index

  data_type: 'boolean'
  is_nullable: 1

=head2 force_login

  data_type: 'boolean'
  default_value: false
  is_nullable: 1

=head2 restrict_intranet

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=head2 searchengine

  data_type: 'text'
  default_value: (empty string)
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
  { data_type => "text", is_nullable => 0 },
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
  "own_index",
  { data_type => "boolean", is_nullable => 1 },
  "force_login",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "restrict_intranet",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "searchengine",
  { data_type => "text", default_value => "", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<uq_viewinfo_viewname>

=over 4

=item * L</viewname>

=back

=cut

__PACKAGE__->add_unique_constraint("uq_viewinfo_viewname", ["viewname"]);

=head1 RELATIONS

=head2 authenticator_views

Type: has_many

Related object: L<OpenBib::Schema::System::Result::AuthenticatorView>

=cut

__PACKAGE__->has_many(
  "authenticator_views",
  "OpenBib::Schema::System::Result::AuthenticatorView",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 authtokens

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Authtoken>

=cut

__PACKAGE__->has_many(
  "authtokens",
  "OpenBib::Schema::System::Result::Authtoken",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Profileinfo>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Schema::System::Result::Profileinfo",
  { id => "profileid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 registrations

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Registration>

=cut

__PACKAGE__->has_many(
  "registrations",
  "OpenBib::Schema::System::Result::Registration",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 role_viewadmins

Type: has_many

Related object: L<OpenBib::Schema::System::Result::RoleViewadmin>

=cut

__PACKAGE__->has_many(
  "role_viewadmins",
  "OpenBib::Schema::System::Result::RoleViewadmin",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 role_views

Type: has_many

Related object: L<OpenBib::Schema::System::Result::RoleView>

=cut

__PACKAGE__->has_many(
  "role_views",
  "OpenBib::Schema::System::Result::RoleView",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 rssid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssid",
  "OpenBib::Schema::System::Result::Rssinfo",
  { id => "rssid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 templateinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Templateinfo>

=cut

__PACKAGE__->has_many(
  "templateinfos",
  "OpenBib::Schema::System::Result::Templateinfo",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 userinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->has_many(
  "userinfos",
  "OpenBib::Schema::System::Result::Userinfo",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewDb>

=cut

__PACKAGE__->has_many(
  "view_dbs",
  "OpenBib::Schema::System::Result::ViewDb",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_locations

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewLocation>

=cut

__PACKAGE__->has_many(
  "view_locations",
  "OpenBib::Schema::System::Result::ViewLocation",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_rsses

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewRss>

=cut

__PACKAGE__->has_many(
  "view_rsses",
  "OpenBib::Schema::System::Result::ViewRss",
  { "foreign.viewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pXaukYOWTmpXrBx+Bzhrsw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
