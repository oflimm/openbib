package OpenBib::Schema::Enrichment::Result::EnrichedContentByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::EnrichedContentByIsbn

=cut

__PACKAGE__->table("enriched_content_by_isbn");

=head1 ACCESSORS

=head2 isbn

  data_type: 'varchar'
  is_nullable: 0
  size: 13

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=head2 field

  data_type: 'smallint'
  is_nullable: 0

=head2 subfield

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 13 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
  "field",
  { data_type => "smallint", is_nullable => 0 },
  "subfield",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:40
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3uPm/yEI8d/kHgTEKArRcw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
