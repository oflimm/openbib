package OpenBib::Schema::Enrichment::Result::AllTitleByWorkkey;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Enrichment::Result::AllTitleByWorkkey

=cut

__PACKAGE__->table("all_titles_by_workkey");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'all_titles_by_workkey_id_seq'

=head2 workkey

  data_type: 'text'
  is_nullable: 0

=head2 edition

  data_type: 'bigint'
  is_nullable: 1

=head2 dbname

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 titleid

  data_type: 'varchar'
  is_nullable: 0
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
    sequence          => "all_titles_by_workkey_id_seq",
  },
  "workkey",
  { data_type => "text", is_nullable => 0 },
  "edition",
  { data_type => "bigint", is_nullable => 1 },
  "dbname",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "titleid",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-11-11 10:23:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oLCk+LKeNwRAGvpLGRNLfA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
