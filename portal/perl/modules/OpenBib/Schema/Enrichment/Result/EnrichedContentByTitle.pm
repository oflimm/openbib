use utf8;
package OpenBib::Schema::Enrichment::Result::EnrichedContentByTitle;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Enrichment::Result::EnrichedContentByTitle

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<enriched_content_by_title>

=cut

__PACKAGE__->table("enriched_content_by_title");

=head1 ACCESSORS

=head2 titleid

  data_type: 'text'
  is_nullable: 0

=head2 dbname

  data_type: 'text'
  is_nullable: 0

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=head2 field

  data_type: 'smallint'
  is_nullable: 0

=head2 subfield

  data_type: 'varchar'
  is_nullable: 1
  size: 3

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "titleid",
  { data_type => "text", is_nullable => 0 },
  "dbname",
  { data_type => "text", is_nullable => 0 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
  "field",
  { data_type => "smallint", is_nullable => 0 },
  "subfield",
  { data_type => "varchar", is_nullable => 1, size => 3 },
  "content",
  { data_type => "text", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-09-06 15:56:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:r4/XgA2gKD1RJO3cG/v16g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
