package OpenBib::Schema::System::Result::Dbisdb;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Dbisdb

=cut

__PACKAGE__->table("dbisdb");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 0

=head2 url

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 0 },
  "url",
  { data_type => "text", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbistopic_dbisdbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::DbistopicDbisdb>

=cut

__PACKAGE__->has_many(
  "dbistopic_dbisdbs",
  "OpenBib::Schema::System::Result::DbistopicDbisdb",
  { "foreign.dbisdbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-09-23 11:14:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:N3j4umWrpObjMs+b0SGwTg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
