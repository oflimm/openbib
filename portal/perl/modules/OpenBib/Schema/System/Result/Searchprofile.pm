package OpenBib::Schema::System::Result::Searchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Searchprofile

=cut

__PACKAGE__->table("searchprofile");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'searchprofile_id_seq'

=head2 databases_as_json

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "searchprofile_id_seq",
  },
  "databases_as_json",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 queries

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Query>

=cut

__PACKAGE__->has_many(
  "queries",
  "OpenBib::Schema::System::Result::Query",
  { "foreign.searchprofileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchprofile_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::SearchprofileDb>

=cut

__PACKAGE__->has_many(
  "searchprofile_dbs",
  "OpenBib::Schema::System::Result::SearchprofileDb",
  { "foreign.searchprofileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 session_searchprofiles

Type: has_many

Related object: L<OpenBib::Schema::System::Result::SessionSearchprofile>

=cut

__PACKAGE__->has_many(
  "session_searchprofiles",
  "OpenBib::Schema::System::Result::SessionSearchprofile",
  { "foreign.searchprofileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_searchprofiles

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSearchprofile>

=cut

__PACKAGE__->has_many(
  "user_searchprofiles",
  "OpenBib::Schema::System::Result::UserSearchprofile",
  { "foreign.searchprofileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-05-11 15:52:34
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:xKbPVbXH+CGNfUZD67wlFg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
