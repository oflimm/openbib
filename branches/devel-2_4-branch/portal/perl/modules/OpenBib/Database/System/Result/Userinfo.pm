package OpenBib::Database::System::Result::Userinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Userinfo

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

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 password

  data_type: 'text'
  is_nullable: 1

=head2 nachname

  data_type: 'text'
  is_nullable: 1

=head2 vorname

  data_type: 'text'
  is_nullable: 1

=head2 strasse

  data_type: 'text'
  is_nullable: 1

=head2 ort

  data_type: 'text'
  is_nullable: 1

=head2 plz

  data_type: 'integer'
  is_nullable: 1

=head2 soll

  data_type: 'text'
  is_nullable: 1

=head2 gut

  data_type: 'text'
  is_nullable: 1

=head2 avanz

  data_type: 'text'
  is_nullable: 1

=head2 branz

  data_type: 'text'
  is_nullable: 1

=head2 bsanz

  data_type: 'text'
  is_nullable: 1

=head2 vmanz

  data_type: 'text'
  is_nullable: 1

=head2 maanz

  data_type: 'text'
  is_nullable: 1

=head2 vlanz

  data_type: 'text'
  is_nullable: 1

=head2 sperre

  data_type: 'text'
  is_nullable: 1

=head2 sperrdatum

  data_type: 'text'
  is_nullable: 1

=head2 gebdatum

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
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "password",
  { data_type => "text", is_nullable => 1 },
  "nachname",
  { data_type => "text", is_nullable => 1 },
  "vorname",
  { data_type => "text", is_nullable => 1 },
  "strasse",
  { data_type => "text", is_nullable => 1 },
  "ort",
  { data_type => "text", is_nullable => 1 },
  "plz",
  { data_type => "integer", is_nullable => 1 },
  "soll",
  { data_type => "text", is_nullable => 1 },
  "gut",
  { data_type => "text", is_nullable => 1 },
  "avanz",
  { data_type => "text", is_nullable => 1 },
  "branz",
  { data_type => "text", is_nullable => 1 },
  "bsanz",
  { data_type => "text", is_nullable => 1 },
  "vmanz",
  { data_type => "text", is_nullable => 1 },
  "maanz",
  { data_type => "text", is_nullable => 1 },
  "vlanz",
  { data_type => "text", is_nullable => 1 },
  "sperre",
  { data_type => "text", is_nullable => 1 },
  "sperrdatum",
  { data_type => "text", is_nullable => 1 },
  "gebdatum",
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
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("uq_userinfo_username", ["username"]);

=head1 RELATIONS

=head2 collections

Type: has_many

Related object: L<OpenBib::Database::System::Result::Collection>

=cut

__PACKAGE__->has_many(
  "collections",
  "OpenBib::Database::System::Result::Collection",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 litlists

Type: has_many

Related object: L<OpenBib::Database::System::Result::Litlist>

=cut

__PACKAGE__->has_many(
  "litlists",
  "OpenBib::Database::System::Result::Litlist",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 livesearches

Type: has_many

Related object: L<OpenBib::Database::System::Result::Livesearch>

=cut

__PACKAGE__->has_many(
  "livesearches",
  "OpenBib::Database::System::Result::Livesearch",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 reviews

Type: has_many

Related object: L<OpenBib::Database::System::Result::Review>

=cut

__PACKAGE__->has_many(
  "reviews",
  "OpenBib::Database::System::Result::Review",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 reviewratings

Type: has_many

Related object: L<OpenBib::Database::System::Result::Reviewrating>

=cut

__PACKAGE__->has_many(
  "reviewratings",
  "OpenBib::Database::System::Result::Reviewrating",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields

Type: has_many

Related object: L<OpenBib::Database::System::Result::Searchfield>

=cut

__PACKAGE__->has_many(
  "searchfields",
  "OpenBib::Database::System::Result::Searchfield",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tit_tags

Type: has_many

Related object: L<OpenBib::Database::System::Result::TitTag>

=cut

__PACKAGE__->has_many(
  "tit_tags",
  "OpenBib::Database::System::Result::TitTag",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_roles

Type: has_many

Related object: L<OpenBib::Database::System::Result::UserRole>

=cut

__PACKAGE__->has_many(
  "user_roles",
  "OpenBib::Database::System::Result::UserRole",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_searchprofiles

Type: has_many

Related object: L<OpenBib::Database::System::Result::UserSearchprofile>

=cut

__PACKAGE__->has_many(
  "user_searchprofiles",
  "OpenBib::Database::System::Result::UserSearchprofile",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_sessions

Type: has_many

Related object: L<OpenBib::Database::System::Result::UserSession>

=cut

__PACKAGE__->has_many(
  "user_sessions",
  "OpenBib::Database::System::Result::UserSession",
  { "foreign.userid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-27 13:44:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EqNm2Y421ZH7i8ZFA/RtYA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
