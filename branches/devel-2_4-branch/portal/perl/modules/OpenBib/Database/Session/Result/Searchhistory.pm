package OpenBib::Database::Session::Result::Searchhistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Session::Result::Searchhistory

=cut

__PACKAGE__->table("searchhistory");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'datetime'
  is_nullable: 1

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 offset

  data_type: 'integer'
  is_nullable: 1

=head2 hitrange

  data_type: 'integer'
  is_nullable: 1

=head2 searchresult

  data_type: 'longtext'
  is_nullable: 1

=head2 hits

  data_type: 'integer'
  is_nullable: 1

=head2 queryid

  data_type: 'bigint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "datetime", is_nullable => 1 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "offset",
  { data_type => "integer", is_nullable => 1 },
  "hitrange",
  { data_type => "integer", is_nullable => 1 },
  "searchresult",
  { data_type => "longtext", is_nullable => 1 },
  "hits",
  { data_type => "integer", is_nullable => 1 },
  "queryid",
  { data_type => "bigint", is_nullable => 1 },
);

=head1 RELATIONS

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Database::Session::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Database::Session::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:36:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rSBUxZnWpdkPnJINGPHt/w


# You can replace this text with custom content, and it will be preserved on regeneration
1;
