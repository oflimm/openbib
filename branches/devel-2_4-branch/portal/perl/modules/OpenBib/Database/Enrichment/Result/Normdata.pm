package OpenBib::Database::Enrichment::Result::Normdata;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Enrichment::Result::Normdata

=cut

__PACKAGE__->table("normdata");

=head1 ACCESSORS

=head2 isbn

  data_type: 'varchar'
  is_nullable: 0
  size: 32

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=head2 category

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=head2 indicator

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 32 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
  "category",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "indicator",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-02-28 11:58:46
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:bmXJvnQv3vJcKaFVkzWRoA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
