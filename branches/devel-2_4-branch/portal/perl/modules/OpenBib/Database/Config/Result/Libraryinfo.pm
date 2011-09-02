package OpenBib::Database::Config::Result::Libraryinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Libraryinfo

=cut

__PACKAGE__->table("libraryinfo");

=head1 ACCESSORS

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 category

  data_type: 'smallint'
  is_nullable: 0

=head2 indicator

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "category",
  { data_type => "smallint", is_nullable => 0 },
  "indicator",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Database::Config::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Database::Config::Result::Databaseinfo",
  { id => "dbid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-08-31 13:46:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:grJK5R8fRh7SwOYB94vdVQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
