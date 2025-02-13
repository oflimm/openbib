use utf8;
package OpenBib::Schema::System::Result::DbrtopicDbistopic;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::DbrtopicDbistopic

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<dbrtopic_dbistopic>

=cut

__PACKAGE__->table("dbrtopic_dbistopic");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'dbrtopic_dbistopic_id_seq'

=head2 dbrtopicid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbistopicid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "dbrtopic_dbistopic_id_seq",
  },
  "dbrtopicid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbistopicid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbistopicid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Dbistopic>

=cut

__PACKAGE__->belongs_to(
  "dbistopicid",
  "OpenBib::Schema::System::Result::Dbistopic",
  { id => "dbistopicid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 dbrtopicid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Dbrtopic>

=cut

__PACKAGE__->belongs_to(
  "dbrtopicid",
  "OpenBib::Schema::System::Result::Dbrtopic",
  { id => "dbrtopicid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:FzjG1YUeA4GrAOoGz2hyMw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
