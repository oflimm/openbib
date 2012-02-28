package OpenBib::Database::Enrichment::Result::Search;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Enrichment::Result::Search

=cut

__PACKAGE__->table("search");

=head1 ACCESSORS

=head2 isbn

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 14

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "isbn",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 14 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-02-28 11:58:46
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:SUcT3L+l1ia0slM7SJ4tsw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
