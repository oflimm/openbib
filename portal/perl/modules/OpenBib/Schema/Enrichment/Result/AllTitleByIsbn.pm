package OpenBib::Schema::Enrichment::Result::AllTitleByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::AllTitleByIsbn

=cut

__PACKAGE__->table("all_titles_by_isbn");

=head1 ACCESSORS

=head2 isbn

  data_type: 'varchar'
  is_nullable: 0
  size: 13

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 location

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 13 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "location",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2016-02-25 15:01:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:PKOpefJPgNaRoqp33ud/AQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
