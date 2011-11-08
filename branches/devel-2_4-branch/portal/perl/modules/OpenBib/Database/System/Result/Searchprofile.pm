package OpenBib::Database::System::Result::Searchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Searchprofile

=cut

__PACKAGE__->table("searchprofile");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 databases_as_json

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "databases_as_json",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 user_profiles

Type: has_many

Related object: L<OpenBib::Database::System::Result::UserProfile>

=cut

__PACKAGE__->has_many(
  "user_profiles",
  "OpenBib::Database::System::Result::UserProfile",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 10:59:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dmc5s9/98eHkfmL4XhxtFA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
