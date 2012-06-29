package OpenBib::Database::Enrichment::Result::WorkByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Enrichment::Result::WorkByIsbn

=cut

__PACKAGE__->table("work_by_isbn");

=head1 ACCESSORS

=head2 workid

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
  "workid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 13 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-06-06 13:07:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8r8CevqlkL1Tfw/6/8wp8g


# You can replace this text with custom content, and it will be preserved on regeneration
1;
