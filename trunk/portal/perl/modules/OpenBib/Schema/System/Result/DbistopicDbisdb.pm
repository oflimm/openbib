package OpenBib::Schema::System::Result::DbistopicDbisdb;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::DbistopicDbisdb

=cut

__PACKAGE__->table("dbistopic_dbisdb");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'dbistopic_dbisdb_id_seq'

=head2 dbistopicid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbisdbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 rank

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "dbistopic_dbisdb_id_seq",
  },
  "dbistopicid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbisdbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "rank",
  { data_type => "integer", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbisdbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Dbisdb>

=cut

__PACKAGE__->belongs_to(
  "dbisdbid",
  "OpenBib::Schema::System::Result::Dbisdb",
  { id => "dbisdbid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 dbistopicid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Dbistopic>

=cut

__PACKAGE__->belongs_to(
  "dbistopicid",
  "OpenBib::Schema::System::Result::Dbistopic",
  { id => "dbistopicid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-09-23 11:14:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dteM+lNYK9PiQl6RWTLzeg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
