use utf8;
package OpenBib::Schema::Statistics::Result::Sessioninfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Sessioninfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<sessioninfo>

=cut

__PACKAGE__->table("sessioninfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'sessioninfo_id_seq'

=head2 sessionid

  data_type: 'varchar'
  is_nullable: 1
  size: 70

=head2 createtime

  data_type: 'timestamp'
  is_nullable: 1

=head2 viewname

  data_type: 'text'
  is_nullable: 1

=head2 createtime_year

  data_type: 'smallint'
  is_nullable: 1

=head2 createtime_month

  data_type: 'smallint'
  is_nullable: 1

=head2 createtime_day

  data_type: 'smallint'
  is_nullable: 1

=head2 network

  data_type: 'cidr'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "sessioninfo_id_seq",
  },
  "sessionid",
  { data_type => "varchar", is_nullable => 1, size => 70 },
  "createtime",
  { data_type => "timestamp", is_nullable => 1 },
  "viewname",
  { data_type => "text", is_nullable => 1 },
  "createtime_year",
  { data_type => "smallint", is_nullable => 1 },
  "createtime_month",
  { data_type => "smallint", is_nullable => 1 },
  "createtime_day",
  { data_type => "smallint", is_nullable => 1 },
  "network",
  { data_type => "cidr", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 15:16:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Wf8+IeEqIP5sHmOwXRSI/g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
