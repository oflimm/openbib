use utf8;
package OpenBib::Schema::System::Result::Searchfield;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Searchfield

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<searchfield>

=cut

__PACKAGE__->table("searchfield");

=head1 ACCESSORS

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 searchfield

  data_type: 'text'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "searchfield",
  { data_type => "text", is_nullable => 1 },
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
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-06-23 13:29:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1UPjvaU36Og5XY4Gmq5Sdw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
