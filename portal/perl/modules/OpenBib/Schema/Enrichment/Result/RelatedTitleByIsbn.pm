package OpenBib::Schema::Enrichment::Result::RelatedTitleByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::RelatedTitleByIsbn

=cut

__PACKAGE__->table("related_titles_by_isbn");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 isbn

  data_type: 'varchar'
  is_nullable: 0
  size: 13

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 13 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:40
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:58iTtL/bHhQGvTVsXZBrcw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
