use utf8;
package OpenBib::Schema::Statistics::Result::Titleusage;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Titleusage

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<titleusage>

=cut

__PACKAGE__->table("titleusage");

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

=head2 isbn

  data_type: 'text'
  is_nullable: 1

=head2 dbname

  data_type: 'text'
  is_nullable: 0

=head2 id

  data_type: 'text'
  is_nullable: 0

=head2 origin

  data_type: 'smallint'
  is_nullable: 1

=head2 viewname

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
  "isbn",
  { data_type => "text", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 0 },
  "id",
  { data_type => "text", is_nullable => 0 },
  "origin",
  { data_type => "smallint", is_nullable => 1 },
  "viewname",
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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2013-01-07 17:04:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/OniqaJIi4XvsOvjXd9FNQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
