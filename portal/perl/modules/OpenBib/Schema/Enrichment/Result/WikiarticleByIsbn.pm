use utf8;
package OpenBib::Schema::Enrichment::Result::WikiarticleByIsbn;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Enrichment::Result::WikiarticleByIsbn

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<wikiarticles_by_isbn>

=cut

__PACKAGE__->table("wikiarticles_by_isbn");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'wikiarticles_by_isbn_id_seq'

=head2 article

  data_type: 'text'
  is_nullable: 1

=head2 isbn

  data_type: 'varchar'
  is_nullable: 0
  size: 13

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "wikiarticles_by_isbn_id_seq",
  },
  "article",
  { data_type => "text", is_nullable => 1 },
  "isbn",
  { data_type => "varchar", is_nullable => 0, size => 13 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-09-06 14:47:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:F0mx0irCWcx9+6dAeRTMDQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
