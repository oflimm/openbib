package OpenBib::Schema::System::Result::Profileinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Profileinfo

=cut

__PACKAGE__->table("profileinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'profileinfo_id_seq'

=head2 profilename

  data_type: 'text'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "profileinfo_id_seq",
  },
  "profilename",
  { data_type => "text", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("uq_profileinfo_profilename", ["profilename"]);

=head1 RELATIONS

=head2 orgunitinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Orgunitinfo>

=cut

__PACKAGE__->has_many(
  "orgunitinfos",
  "OpenBib::Schema::System::Result::Orgunitinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->has_many(
  "viewinfos",
  "OpenBib::Schema::System::Result::Viewinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-11-17 15:09:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:H4E2WLuOzoCiTrIHwyXEMw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
