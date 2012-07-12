package OpenBib::Schema::System::Result::Livesearch;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Livesearch

=cut

__PACKAGE__->table("livesearch");

=head1 ACCESSORS

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 searchfield

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 exact

  data_type: 'boolean'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "searchfield",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "exact",
  { data_type => "boolean", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
);

=head1 RELATIONS

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Jrmphve+Z6fFWTE87LDHYg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
