use utf8;
package OpenBib::Schema::System::Result::DatabaseinfoSearchengine;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::DatabaseinfoSearchengine

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<databaseinfo_searchengine>

=cut

__PACKAGE__->table("databaseinfo_searchengine");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'databaseinfo_searchengine_id_seq'

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 searchengine

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "databaseinfo_searchengine_id_seq",
  },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "searchengine",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "dbid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:lBM6d50dKem9oChn9NQvbw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
