use utf8;
package OpenBib::Schema::Enrichment::Result::AllTitleByWorkkey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Enrichment::Result::AllTitleByWorkkey

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<all_titles_by_workkey>

=cut

__PACKAGE__->table("all_titles_by_workkey");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'all_titles_by_workkey_tmp_id_seq'

=head2 workkey

  data_type: 'text'
  is_nullable: 0

=head2 edition

  data_type: 'text'
  is_nullable: 1

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 location

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "all_titles_by_workkey_tmp_id_seq",
  },
  "workkey",
  { data_type => "text", is_nullable => 0 },
  "edition",
  { data_type => "text", is_nullable => 1 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "location",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-09-06 15:56:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/R7A17zM84X2O1xQbADiJQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
