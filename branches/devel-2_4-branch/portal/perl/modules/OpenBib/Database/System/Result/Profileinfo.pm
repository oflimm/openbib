package OpenBib::Database::System::Result::Profileinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Profileinfo

=cut

__PACKAGE__->table("profileinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 profilename

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 description

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "profilename",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "description",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("profilename", ["profilename"]);

=head1 RELATIONS

=head2 orgunitinfos

Type: has_many

Related object: L<OpenBib::Database::System::Result::Orgunitinfo>

=cut

__PACKAGE__->has_many(
  "orgunitinfos",
  "OpenBib::Database::System::Result::Orgunitinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewinfos

Type: has_many

Related object: L<OpenBib::Database::System::Result::Viewinfo>

=cut

__PACKAGE__->has_many(
  "viewinfos",
  "OpenBib::Database::System::Result::Viewinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-01-06 13:01:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:T5Ajy232rPgpXpMr1+eVlw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
