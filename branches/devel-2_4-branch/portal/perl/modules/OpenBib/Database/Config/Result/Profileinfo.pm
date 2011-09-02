package OpenBib::Database::Config::Result::Profileinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Profileinfo

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

Related object: L<OpenBib::Database::Config::Result::Orgunitinfo>

=cut

__PACKAGE__->has_many(
  "orgunitinfos",
  "OpenBib::Database::Config::Result::Orgunitinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewinfos

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Viewinfo>

=cut

__PACKAGE__->has_many(
  "viewinfos",
  "OpenBib::Database::Config::Result::Viewinfo",
  { "foreign.profileid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-08-31 13:46:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+gshg448tJd8h2FrIHwlUQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
