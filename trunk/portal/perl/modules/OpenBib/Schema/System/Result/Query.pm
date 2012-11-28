use utf8;
package OpenBib::Schema::System::Result::Query;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Query

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<queries>

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
  { data_type => "bigint", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</queryid>

=back

=cut

__PACKAGE__->set_primary_key("queryid");

=head1 RELATIONS

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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-28 16:00:38
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pkkhiVOI7KnjrHC8BXx2MA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
