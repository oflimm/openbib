package OpenBib::Schema::Enrichment::Result::EnrichedContentByBibkey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::EnrichedContentByBibkey

=cut

__PACKAGE__->table("enriched_content_by_bibkey");

=head1 ACCESSORS

=head2 bibkey

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
  "bibkey",
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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2016-02-25 15:01:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4vEU3Ai0L93oECXsxm4IpQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
