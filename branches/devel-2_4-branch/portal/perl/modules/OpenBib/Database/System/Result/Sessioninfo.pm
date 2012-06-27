package OpenBib::Database::System::Result::Sessioninfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Sessioninfo

=cut

__PACKAGE__->table("sessioninfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'sessioninfo_id_seq'

=head2 sessionid

  data_type: 'char'
  is_nullable: 0
  size: 33

=head2 createtime

  data_type: 'timestamp'
  is_nullable: 1

=head2 lastresultset

  data_type: 'text'
  is_nullable: 1

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 userpassword

  data_type: 'text'
  is_nullable: 1

=head2 queryoptions

  data_type: 'text'
  is_nullable: 1

=head2 searchform

  data_type: 'text'
  is_nullable: 1

=head2 searchprofile

  data_type: 'text'
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
    sequence          => "sessioninfo_id_seq",
  },
  "sessionid",
  { data_type => "char", is_nullable => 0, size => 33 },
  "createtime",
  { data_type => "timestamp", is_nullable => 1 },
  "lastresultset",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userpassword",
  { data_type => "text", is_nullable => 1 },
  "queryoptions",
  { data_type => "text", is_nullable => 1 },
  "searchform",
  { data_type => "text", is_nullable => 1 },
  "searchprofile",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_user",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_key",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_sync",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 eventlogs

Type: has_many

Related object: L<OpenBib::Database::System::Result::Eventlog>

=cut

__PACKAGE__->has_many(
  "eventlogs",
  "OpenBib::Database::System::Result::Eventlog",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjsons

Type: has_many

Related object: L<OpenBib::Database::System::Result::Eventlogjson>

=cut

__PACKAGE__->has_many(
  "eventlogjsons",
  "OpenBib::Database::System::Result::Eventlogjson",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 queries

Type: has_many

Related object: L<OpenBib::Database::System::Result::Query>

=cut

__PACKAGE__->has_many(
  "queries",
  "OpenBib::Database::System::Result::Query",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 recordhistories

Type: has_many

Related object: L<OpenBib::Database::System::Result::Recordhistory>

=cut

__PACKAGE__->has_many(
  "recordhistories",
  "OpenBib::Database::System::Result::Recordhistory",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchhistories

Type: has_many

Related object: L<OpenBib::Database::System::Result::Searchhistory>

=cut

__PACKAGE__->has_many(
  "searchhistories",
  "OpenBib::Database::System::Result::Searchhistory",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 sessioncollections

Type: has_many

Related object: L<OpenBib::Database::System::Result::Sessioncollection>

=cut

__PACKAGE__->has_many(
  "sessioncollections",
  "OpenBib::Database::System::Result::Sessioncollection",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 session_searchprofiles

Type: has_many

Related object: L<OpenBib::Database::System::Result::SessionSearchprofile>

=cut

__PACKAGE__->has_many(
  "session_searchprofiles",
  "OpenBib::Database::System::Result::SessionSearchprofile",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_sessions

Type: has_many

Related object: L<OpenBib::Database::System::Result::UserSession>

=cut

__PACKAGE__->has_many(
  "user_sessions",
  "OpenBib::Database::System::Result::UserSession",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-27 13:44:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BN5VIIxJv3h9T+anjlGzfw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
