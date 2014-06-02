package OpenBib::Schema::Enrichment::Result::AllTitleByBibkey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::AllTitleByBibkey

=cut

__PACKAGE__->table("all_titles_by_bibkey");

=head1 ACCESSORS

=head2 bibkey

  data_type: 'varchar'
  is_nullable: 0
  size: 33

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "bibkey",
  { data_type => "varchar", is_nullable => 0, size => 33 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2013-05-31 15:08:06
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gFoJ/rw58HxTJ9byz7JGHA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
