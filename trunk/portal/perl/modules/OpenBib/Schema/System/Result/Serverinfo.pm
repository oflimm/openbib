use utf8;
package OpenBib::Schema::System::Result::Serverinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Serverinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<serverinfo>

=cut

__PACKAGE__->table("serverinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'serverinfo_id_seq'

=head2 hostip

  data_type: 'text'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=head2 status

  data_type: 'text'
  is_nullable: 1

=head2 clusterid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

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
    sequence          => "serverinfo_id_seq",
  },
  "hostip",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "clusterid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "description",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 clusterid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Clusterinfo>

=cut

__PACKAGE__->belongs_to(
  "clusterid",
  "OpenBib::Schema::System::Result::Clusterinfo",
  { id => "clusterid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-28 16:00:38
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MUXpYM2wAPEd3KTOe/jk1w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
