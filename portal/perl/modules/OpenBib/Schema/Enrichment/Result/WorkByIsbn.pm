use utf8;
package OpenBib::Schema::Enrichment::Result::WorkByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Enrichment::Result::WorkByIsbn

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<work_by_isbn>

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


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-09-06 15:56:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Lmz3U4gpNar9psZTjTK/FQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
