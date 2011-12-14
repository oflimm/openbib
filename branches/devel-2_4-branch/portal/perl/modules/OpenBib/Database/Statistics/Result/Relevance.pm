package OpenBib::Database::Statistics::Result::Relevance;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Relevance

=cut

__PACKAGE__->table("relevance");

=head1 ACCESSORS

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=head2 id

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 isbn

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 dbname

  data_type: 'varchar'
  is_nullable: 1
  size: 25

=head2 katkey

  data_type: 'integer'
  is_nullable: 1

=head2 origin

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "id",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "isbn",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "dbname",
  { data_type => "varchar", is_nullable => 1, size => 25 },
  "katkey",
  { data_type => "integer", is_nullable => 1 },
  "origin",
  { data_type => "integer", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-12-13 11:06:13
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jja177+kojiNTzUfH3zniw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
