use utf8;
package OpenBib::Schema::System::Result::Templateinforevision;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Templateinforevision

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<templateinforevision>

=cut

__PACKAGE__->table("templateinforevision");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'templateinforevision_id_seq'

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 templateid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 templatetext

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "templateinforevision_id_seq",
  },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "templateid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "templatetext",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 templateid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Templateinfo>

=cut

__PACKAGE__->belongs_to(
  "templateid",
  "OpenBib::Schema::System::Result::Templateinfo",
  { id => "templateid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-01-20 13:11:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gJ0MnZTreUuIKVGM+7Gfqg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
