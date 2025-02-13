use utf8;
package OpenBib::Schema::System::Result::Updatelog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Updatelog

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<updatelog>

=cut

__PACKAGE__->table("updatelog");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'updatelog_id_seq'

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 serverid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 tstamp_start

  data_type: 'timestamp'
  is_nullable: 1

=head2 duration

  data_type: 'interval'
  is_nullable: 1

=head2 title_count

  data_type: 'integer'
  is_nullable: 1

=head2 title_journalcount

  data_type: 'integer'
  is_nullable: 1

=head2 title_articlecount

  data_type: 'integer'
  is_nullable: 1

=head2 title_digitalcount

  data_type: 'integer'
  is_nullable: 1

=head2 person_count

  data_type: 'integer'
  is_nullable: 1

=head2 corporatebody_count

  data_type: 'integer'
  is_nullable: 1

=head2 classification_count

  data_type: 'integer'
  is_nullable: 1

=head2 subject_count

  data_type: 'integer'
  is_nullable: 1

=head2 holding_count

  data_type: 'integer'
  is_nullable: 1

=head2 is_incremental

  data_type: 'integer'
  is_nullable: 1

=head2 duration_stage_collect

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_unpack

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_convert

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_load_db

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_load_index

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_load_authorities

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_switch

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_update_enrichment

  data_type: 'interval'
  is_nullable: 1

=head2 duration_stage_analyze

  data_type: 'interval'
  is_nullable: 1

=head2 title_count_xapian

  data_type: 'integer'
  is_nullable: 1

=head2 title_count_es

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "updatelog_id_seq",
  },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "serverid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "tstamp_start",
  { data_type => "timestamp", is_nullable => 1 },
  "duration",
  { data_type => "interval", is_nullable => 1 },
  "title_count",
  { data_type => "integer", is_nullable => 1 },
  "title_journalcount",
  { data_type => "integer", is_nullable => 1 },
  "title_articlecount",
  { data_type => "integer", is_nullable => 1 },
  "title_digitalcount",
  { data_type => "integer", is_nullable => 1 },
  "person_count",
  { data_type => "integer", is_nullable => 1 },
  "corporatebody_count",
  { data_type => "integer", is_nullable => 1 },
  "classification_count",
  { data_type => "integer", is_nullable => 1 },
  "subject_count",
  { data_type => "integer", is_nullable => 1 },
  "holding_count",
  { data_type => "integer", is_nullable => 1 },
  "is_incremental",
  { data_type => "integer", is_nullable => 1 },
  "duration_stage_collect",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_unpack",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_convert",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_load_db",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_load_index",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_load_authorities",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_switch",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_update_enrichment",
  { data_type => "interval", is_nullable => 1 },
  "duration_stage_analyze",
  { data_type => "interval", is_nullable => 1 },
  "title_count_xapian",
  { data_type => "integer", is_nullable => 1 },
  "title_count_es",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "dbid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 serverid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Serverinfo>

=cut

__PACKAGE__->belongs_to(
  "serverid",
  "OpenBib::Schema::System::Result::Serverinfo",
  { id => "serverid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kJk32O5l8Jfw/ZhvMUsOrQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
