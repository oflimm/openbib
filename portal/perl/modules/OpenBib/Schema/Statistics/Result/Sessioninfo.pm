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

=head2 createtime_year

  data_type: 'smallint'
  is_nullable: 1

=head2 createtime_month

  data_type: 'smallint'
  is_nullable: 1

=head2 createtime_day

  data_type: 'smallint'
  is_nullable: 1

=head2 viewname

  data_type: 'text'
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
  "createtime_year",
  { data_type => "smallint", is_nullable => 1 },
  "createtime_month",
  { data_type => "smallint", is_nullable => 1 },
  "createtime_day",
  { data_type => "smallint", is_nullable => 1 },
  "viewname",
  { data_type => "text", is_nullable => 1 },
  "network",
  { data_type => "cidr", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 eventlog_y2007m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2007m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2007m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2007m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2007m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2008m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2008m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2008m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2008m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2009m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2009m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2009m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2009m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2010m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2010m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2010m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2010m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2011m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2011m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2011m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2011m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2012m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2012m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2012m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2012m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2013m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2013m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2013m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2013m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2014m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2014m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2014m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2014m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2015m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2015m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2015m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2015m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2016m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2016m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2016m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2016m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2017m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2017m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2017m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2017m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2018m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2018m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2018m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2018m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2019m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2019m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2019m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2019m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2020m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2020m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2020m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2020m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2021m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2021m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2021m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2021m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2022m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2022m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2022m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2022m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2023m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2023m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2023m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2023m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2024m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2024m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2024m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2024m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2025m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2025m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2025m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2025m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2026m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2026m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2026m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2026m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2027m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2027m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2027m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2027m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2028m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2028m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2028m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2028m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m01>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m01s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m02>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m02s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m03>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m03s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m04>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m04s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m05>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m05s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m06>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m06s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m07>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m07s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m08>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m08s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m09>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m09s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m10>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m10s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m11>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m11s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlog_y2029m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogY2029m12>

=cut

__PACKAGE__->has_many(
  "eventlog_y2029m12s",
  "OpenBib::Schema::Statistics::Result::EventlogY2029m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2007m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2007m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2007m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2007m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2008m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2008m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2008m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2008m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2009m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2009m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2009m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2009m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2010m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2010m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2010m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2010m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2011m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2011m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2011m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2011m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2012m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2012m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2012m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2012m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2013m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2013m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2013m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2013m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2014m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2014m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2014m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2014m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2015m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2015m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2015m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2015m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2016m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2016m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2016m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2016m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2017m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2017m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2017m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2017m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2018m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2018m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2018m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2018m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2019m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2019m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2019m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2019m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2020m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2020m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2020m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2020m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2021m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2021m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2021m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2021m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2022m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2022m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2022m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2022m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2023m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2023m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2023m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2023m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2024m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2024m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2024m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2024m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2025m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2025m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2025m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2025m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2026m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2026m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2026m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2026m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2027m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2027m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2027m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2027m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2028m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2028m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2028m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2028m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m01>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m01s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m02>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m02s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m03>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m03s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m04>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m04s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m05>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m05s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m06>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m06s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m07>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m07s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m08>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m08s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m09>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m09s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m10>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m10s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m11>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m11s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjson_y2029m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::EventlogjsonY2029m12>

=cut

__PACKAGE__->has_many(
  "eventlogjson_y2029m12s",
  "OpenBib::Schema::Statistics::Result::EventlogjsonY2029m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2007m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2007m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2007m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2007m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2008m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2008m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2008m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2008m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2009m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2009m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2009m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2009m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2010m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2010m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2010m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2010m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2011m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2011m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2011m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2011m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2012m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2012m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2012m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2012m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2013m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2013m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2013m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2013m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2014m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2014m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2014m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2014m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2015m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2015m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2015m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2015m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2016m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2016m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2016m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2016m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2017m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2017m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2017m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2017m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2018m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2018m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2018m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2018m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2019m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2019m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2019m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2019m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2020m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2020m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2020m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2020m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2021m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2021m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2021m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2021m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2022m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2022m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2022m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2022m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2023m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2023m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2023m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2023m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2024m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2024m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2024m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2024m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2025m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2025m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2025m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2025m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2026m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2026m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2026m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2026m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2027m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2027m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2027m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2027m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2028m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2028m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2028m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2028m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m01>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m01s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m02>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m02s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m03>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m03s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m04>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m04s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m05>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m05s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m06>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m06s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m07>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m07s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m08>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m08s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m09>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m09s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m10>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m10s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m11>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m11s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields_y2029m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchfieldsY2029m12>

=cut

__PACKAGE__->has_many(
  "searchfields_y2029m12s",
  "OpenBib::Schema::Statistics::Result::SearchfieldsY2029m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2007m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2007m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2007m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2007m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2008m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2008m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2008m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2008m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2009m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2009m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2009m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2009m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2010m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2010m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2010m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2010m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2011m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2011m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2011m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2011m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2012m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2012m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2012m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2012m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2013m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2013m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2013m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2013m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2014m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2014m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2014m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2014m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2015m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2015m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2015m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2015m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2016m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2016m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2016m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2016m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2017m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2017m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2017m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2017m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2018m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2018m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2018m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2018m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2019m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2019m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2019m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2019m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2020m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2020m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2020m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2020m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2021m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2021m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2021m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2021m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2022m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2022m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2022m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2022m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2023m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2023m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2023m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2023m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2024m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2024m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2024m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2024m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2025m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2025m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2025m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2025m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2026m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2026m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2026m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2026m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2027m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2027m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2027m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2027m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2028m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2028m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2028m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2028m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m01>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m01s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m02>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m02s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m03>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m03s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m04>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m04s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m05>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m05s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m06>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m06s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m07>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m07s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m08>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m08s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m09>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m09s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m10>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m10s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m11>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m11s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms_y2029m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::SearchtermsY2029m12>

=cut

__PACKAGE__->has_many(
  "searchterms_y2029m12s",
  "OpenBib::Schema::Statistics::Result::SearchtermsY2029m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2007m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2007m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2007m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2007m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2008m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2008m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2008m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2008m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2009m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2009m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2009m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2009m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2010m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2010m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2010m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2010m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2011m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2011m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2011m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2011m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2012m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2012m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2012m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2012m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2013m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2013m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2013m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2013m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2014m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2014m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2014m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2014m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2015m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2015m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2015m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2015m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2016m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2016m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2016m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2016m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2017m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2017m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2017m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2017m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2018m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2018m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2018m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2018m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2019m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2019m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2019m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2019m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2020m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2020m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2020m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2020m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2021m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2021m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2021m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2021m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2022m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2022m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2022m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2022m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2023m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2023m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2023m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2023m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2024m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2024m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2024m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2024m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2025m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2025m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2025m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2025m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2026m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2026m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2026m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2026m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2027m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2027m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2027m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2027m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2028m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2028m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2028m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2028m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m01s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m01>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m01s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m01",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m02s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m02>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m02s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m02",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m03s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m03>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m03s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m03",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m04s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m04>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m04s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m04",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m05s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m05>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m05s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m05",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m06s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m06>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m06s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m06",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m07s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m07>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m07s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m07",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m08s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m08>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m08s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m08",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m09s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m09>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m09s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m09",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m10s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m10>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m10s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m10",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m11s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m11>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m11s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m11",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusage_y2029m12s

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::TitleusageY2029m12>

=cut

__PACKAGE__->has_many(
  "titleusage_y2029m12s",
  "OpenBib::Schema::Statistics::Result::TitleusageY2029m12",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 13:18:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hz4nAwj0Geg7cnudLuEl5A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
