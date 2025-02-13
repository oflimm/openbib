use utf8;
package OpenBib::Schema::Statistics::Result::Loan;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Loan

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<loans>

=cut

__PACKAGE__->table("loans");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'loans_id_seq'

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 0

=head2 tstamp_year

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_month

  data_type: 'smallint'
  is_nullable: 1

=head2 tstamp_day

  data_type: 'smallint'
  is_nullable: 1

=head2 anon_userid

  data_type: 'varchar'
  is_nullable: 1
  size: 33

=head2 groupid

  data_type: 'varchar'
  is_nullable: 1
  size: 1

=head2 isbn

  data_type: 'varchar'
  is_nullable: 1
  size: 13

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "loans_id_seq",
  },
  "tstamp",
  { data_type => "timestamp", is_nullable => 0 },
  "tstamp_year",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_month",
  { data_type => "smallint", is_nullable => 1 },
  "tstamp_day",
  { data_type => "smallint", is_nullable => 1 },
  "anon_userid",
  { data_type => "varchar", is_nullable => 1, size => 33 },
  "groupid",
  { data_type => "varchar", is_nullable => 1, size => 1 },
  "isbn",
  { data_type => "varchar", is_nullable => 1, size => 13 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=item * L</tstamp>

=back

=cut

__PACKAGE__->set_primary_key("id", "tstamp");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 13:38:33
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eBphFR01D+rdSnGQ3LfSOg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
