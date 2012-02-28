package OpenBib::Database::Enrichment::Result::AllNormdata;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Enrichment::Result::AllNormdata

=cut

__PACKAGE__->table("all_normdata");

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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-02-28 11:58:46
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:nDto8h0/naTtYqXYRzRNJQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
