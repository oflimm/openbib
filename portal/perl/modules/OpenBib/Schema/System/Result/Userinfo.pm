use utf8;
package OpenBib::Schema::System::Result::Userinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Userinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<userinfo>

=cut

__PACKAGE__->table("userinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'userinfo_id_seq'

=head2 lastlogin

  data_type: 'timestamp'
  is_nullable: 1

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 password

  data_type: 'text'
  is_nullable: 1

=head2 nachname

  data_type: 'text'
  is_nullable: 1

=head2 vorname

  data_type: 'text'
  is_nullable: 1

=head2 sperre

  data_type: 'text'
  is_nullable: 1

=head2 sperrdatum

  data_type: 'text'
  is_nullable: 1

=head2 email

  data_type: 'text'
  is_nullable: 1

=head2 masktype

  data_type: 'text'
  is_nullable: 1

=head2 autocompletiontype

  data_type: 'text'
  is_nullable: 1

=head2 spelling_as_you_type

  data_type: 'boolean'
  is_nullable: 1

=head2 spelling_resultlist

  data_type: 'boolean'
  is_nullable: 1

=head2 bibsonomy_user

  data_type: 'text'
  is_nullable: 1

=head2 bibsonomy_key

  data_type: 'text'
  is_nullable: 1

=head2 bibsonomy_sync

  data_type: 'text'
  is_nullable: 1

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 authenticatorid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 locationid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 creationdate

  data_type: 'timestamp'
  is_nullable: 1

=head2 mixed_bag

  data_type: 'jsonb'
  is_nullable: 1

=head2 token

  data_type: 'text'
  is_nullable: 1

=head2 login_failure

  data_type: 'bigint'
  default_value: 0
  is_nullable: 1

=head2 status

  data_type: 'text'
  is_nullable: 1

=head2 external_id

  data_type: 'text'
  is_nullable: 1

=head2 external_group

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "userinfo_id_seq",
  },
  "lastlogin",
  { data_type => "timestamp", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "password",
  { data_type => "text", is_nullable => 1 },
  "nachname",
  { data_type => "text", is_nullable => 1 },
  "vorname",
  { data_type => "text", is_nullable => 1 },
  "sperre",
  { data_type => "text", is_nullable => 1 },
  "sperrdatum",
  { data_type => "text", is_nullable => 1 },
  "email",
  { data_type => "text", is_nullable => 1 },
  "masktype",
  { data_type => "text", is_nullable => 1 },
  "autocompletiontype",
  { data_type => "text", is_nullable => 1 },
  "spelling_as_you_type",
  { data_type => "boolean", is_nullable => 1 },
  "spelling_resultlist",
  { data_type => "boolean", is_nullable => 1 },
  "bibsonomy_user",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_key",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_sync",
  { data_type => "text", is_nullable => 1 },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "authenticatorid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "locationid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "creationdate",
  { data_type => "timestamp", is_nullable => 1 },
  "mixed_bag",
  { data_type => "jsonb", is_nullable => 1 },
  "token",
  { data_type => "text", is_nullable => 1 },
  "login_failure",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "external_id",
  { data_type => "text", is_nullable => 1 },
  "external_group",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<uq_userinfo_username>

=over 4

=item * L</username>

=item * L</viewid>

=item * L</authenticatorid>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "uq_userinfo_username",
  ["username", "viewid", "authenticatorid"],
);

=head1 RELATIONS

=head2 authenticatorid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Authenticatorinfo>

=cut

__PACKAGE__->belongs_to(
  "authenticatorid",
  "OpenBib::Schema::System::Result::Authenticatorinfo",
  { id => "authenticatorid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 litlists

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Litlist>

=cut

__PACKAGE__->has_many(
  "litlists",
  "OpenBib::Schema::System::Result::Litlist",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 livesearches

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Livesearch>

=cut

__PACKAGE__->has_many(
  "livesearches",
  "OpenBib::Schema::System::Result::Livesearch",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 locationid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Locationinfo>

=cut

__PACKAGE__->belongs_to(
  "locationid",
  "OpenBib::Schema::System::Result::Locationinfo",
  { id => "locationid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 reviewratings

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Reviewrating>

=cut

__PACKAGE__->has_many(
  "reviewratings",
  "OpenBib::Schema::System::Result::Reviewrating",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 reviews

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Review>

=cut

__PACKAGE__->has_many(
  "reviews",
  "OpenBib::Schema::System::Result::Review",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Searchfield>

=cut

__PACKAGE__->has_many(
  "searchfields",
  "OpenBib::Schema::System::Result::Searchfield",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tit_tags

Type: has_many

Related object: L<OpenBib::Schema::System::Result::TitTag>

=cut

__PACKAGE__->has_many(
  "tit_tags",
  "OpenBib::Schema::System::Result::TitTag",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_cartitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserCartitem>

=cut

__PACKAGE__->has_many(
  "user_cartitems",
  "OpenBib::Schema::System::Result::UserCartitem",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserDb>

=cut

__PACKAGE__->has_many(
  "user_dbs",
  "OpenBib::Schema::System::Result::UserDb",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_roles

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserRole>

=cut

__PACKAGE__->has_many(
  "user_roles",
  "OpenBib::Schema::System::Result::UserRole",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_searchlocations

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSearchlocation>

=cut

__PACKAGE__->has_many(
  "user_searchlocations",
  "OpenBib::Schema::System::Result::UserSearchlocation",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_searchprofiles

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSearchprofile>

=cut

__PACKAGE__->has_many(
  "user_searchprofiles",
  "OpenBib::Schema::System::Result::UserSearchprofile",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_sessions

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSession>

=cut

__PACKAGE__->has_many(
  "user_sessions",
  "OpenBib::Schema::System::Result::UserSession",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_templates

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserTemplate>

=cut

__PACKAGE__->has_many(
  "user_templates",
  "OpenBib::Schema::System::Result::UserTemplate",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BUIhYPmlYRlTdNpWkD6rVw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
