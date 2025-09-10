use utf8;
package OpenBib::Schema::System::Result::Clusterinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Clusterinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<clusterinfo>

=cut

__PACKAGE__->table("clusterinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'clusterinfo_id_seq'

=head2 clustername

  data_type: 'text'
  is_nullable: 1

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 status

  data_type: 'text'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "clusterinfo_id_seq",
  },
  "clustername",
  { data_type => "text", is_nullable => 1 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 serverinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Serverinfo>

=cut

__PACKAGE__->has_many(
  "serverinfos",
  "OpenBib::Schema::System::Result::Serverinfo",
  { "foreign.clusterid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8nkHcXbY4hfM18+kiAYltg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
