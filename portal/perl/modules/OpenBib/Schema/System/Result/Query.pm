package OpenBib::Schema::System::Result::Query;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Query

=cut

__PACKAGE__->table("queries");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 queryid

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'queries_queryid_seq'

=head2 query

  data_type: 'text'
  is_nullable: 1

=head2 hits

  data_type: 'integer'
  is_nullable: 1

=head2 searchprofileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "queryid",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "queries_queryid_seq",
  },
  "query",
  { data_type => "text", is_nullable => 1 },
  "hits",
  { data_type => "integer", is_nullable => 1 },
  "searchprofileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
);
__PACKAGE__->set_primary_key("queryid");

=head1 RELATIONS

=head2 searchprofileid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Searchprofile>

=cut

__PACKAGE__->belongs_to(
  "searchprofileid",
  "OpenBib::Schema::System::Result::Searchprofile",
  { id => "searchprofileid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Schema::System::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-11-17 15:09:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3N12P3YWt4tuApYZPoI4tg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
