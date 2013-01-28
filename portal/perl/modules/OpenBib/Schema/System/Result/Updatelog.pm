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
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
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
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2013-01-28 16:56:17
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Embis9+HX2JQkAxmU8Z/Zw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
