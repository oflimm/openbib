use utf8;
package OpenBib::Schema::Enrichment::Result::EnrichedContentByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Enrichment::Result::EnrichedContentByIsbn

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<enriched_content_by_isbn>

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

  data_type: 'varchar'
  is_nullable: 1
  size: 3

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
  { data_type => "varchar", is_nullable => 1, size => 3 },
  "content",
  { data_type => "text", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-09-06 15:56:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NDZdsXle29clzQQ5UjJjrg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
