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
  { data_type => "bigint", is_nullable => 0 },
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


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:05:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:u8cy7lcniipJlsQP49oMsQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
