package OpenBib::Schema::Enrichment::Result::AllTitleByIssn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::AllTitleByIssn

=cut

__PACKAGE__->table("all_titles_by_issn");

=head1 ACCESSORS

=head2 issn

  data_type: 'varchar'
  is_nullable: 0
  size: 8

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

=cut

__PACKAGE__->add_columns(
  "issn",
  { data_type => "varchar", is_nullable => 0, size => 8 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:40
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ImN78rPj/L1Zzyh5bYP0bQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
