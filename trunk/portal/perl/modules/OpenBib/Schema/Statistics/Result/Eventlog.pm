use utf8;
package OpenBib::Schema::Statistics::Result::Eventlog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Eventlog

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<eventlog>

=cut

__PACKAGE__->table("eventlog");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_year

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_month

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_day

  data_type: 'smallint'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "tstamp_year",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_month",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_day",
  { data_type => "smallint", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Schema::Statistics::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Schema::Statistics::Result::Sessioninfo",
  { id => "sid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-12-11 15:02:29
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:okU+WMWeORVOs8EsloMx6w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
