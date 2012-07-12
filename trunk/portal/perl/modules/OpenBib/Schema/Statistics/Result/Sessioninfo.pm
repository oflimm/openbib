package OpenBib::Schema::Statistics::Result::Sessioninfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Statistics::Result::Sessioninfo

=cut

__PACKAGE__->table("sessioninfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_nullable: 0

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

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_nullable => 0 },
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
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 eventlogs

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::Eventlog>

=cut

__PACKAGE__->has_many(
  "eventlogs",
  "OpenBib::Schema::Statistics::Result::Eventlog",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 eventlogjsons

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::Eventlogjson>

=cut

__PACKAGE__->has_many(
  "eventlogjsons",
  "OpenBib::Schema::Statistics::Result::Eventlogjson",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchfields

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::Searchfield>

=cut

__PACKAGE__->has_many(
  "searchfields",
  "OpenBib::Schema::Statistics::Result::Searchfield",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchterms

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::Searchterm>

=cut

__PACKAGE__->has_many(
  "searchterms",
  "OpenBib::Schema::Statistics::Result::Searchterm",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 titleusages

Type: has_many

Related object: L<OpenBib::Schema::Statistics::Result::Titleusage>

=cut

__PACKAGE__->has_many(
  "titleusages",
  "OpenBib::Schema::Statistics::Result::Titleusage",
  { "foreign.sid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:29:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:zYoQ/llKkr6PMumsdrxPAw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
