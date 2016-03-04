package OpenBib::Schema::Enrichment::Result::LivesearchData;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::LivesearchData

=cut

__PACKAGE__->table("livesearch_data");

=head1 ACCESSORS

=head2 fs

  data_type: 'text'
  is_nullable: 0

=head2 content

  data_type: 'text'
  is_nullable: 0

=head2 type

  data_type: 'smallint'
  is_nullable: 1

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=cut

__PACKAGE__->add_columns(
  "fs",
  { data_type => "text", is_nullable => 0 },
  "content",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "smallint", is_nullable => 1 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2016-02-25 15:01:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pNSbzZ9ba46G4btCWSyvug


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
