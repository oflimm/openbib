use utf8;
package OpenBib::Schema::Statistics::Result::Searchfield;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Statistics::Result::Searchfield

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<searchfields>

=cut

__PACKAGE__->table("searchfields");

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

=head2 viewname

  data_type: 'text'
  is_nullable: 1

=head2 freesearch

  data_type: 'boolean'
  is_nullable: 1

=head2 title

  data_type: 'boolean'
  is_nullable: 1

=head2 person

  data_type: 'boolean'
  is_nullable: 1

=head2 corporatebody

  data_type: 'boolean'
  is_nullable: 1

=head2 subject

  data_type: 'boolean'
  is_nullable: 1

=head2 classification

  data_type: 'boolean'
  is_nullable: 1

=head2 isbn

  data_type: 'boolean'
  is_nullable: 1

=head2 issn

  data_type: 'boolean'
  is_nullable: 1

=head2 mark

  data_type: 'boolean'
  is_nullable: 1

=head2 mediatype

  data_type: 'boolean'
  is_nullable: 1

=head2 titlestring

  data_type: 'boolean'
  is_nullable: 1

=head2 content

  data_type: 'boolean'
  is_nullable: 1

=head2 source

  data_type: 'boolean'
  is_nullable: 1

=head2 year

  data_type: 'boolean'
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
  "viewname",
  { data_type => "text", is_nullable => 1 },
  "freesearch",
  { data_type => "boolean", is_nullable => 1 },
  "title",
  { data_type => "boolean", is_nullable => 1 },
  "person",
  { data_type => "boolean", is_nullable => 1 },
  "corporatebody",
  { data_type => "boolean", is_nullable => 1 },
  "subject",
  { data_type => "boolean", is_nullable => 1 },
  "classification",
  { data_type => "boolean", is_nullable => 1 },
  "isbn",
  { data_type => "boolean", is_nullable => 1 },
  "issn",
  { data_type => "boolean", is_nullable => 1 },
  "mark",
  { data_type => "boolean", is_nullable => 1 },
  "mediatype",
  { data_type => "boolean", is_nullable => 1 },
  "titlestring",
  { data_type => "boolean", is_nullable => 1 },
  "content",
  { data_type => "boolean", is_nullable => 1 },
  "source",
  { data_type => "boolean", is_nullable => 1 },
  "year",
  { data_type => "boolean", is_nullable => 1 },
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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aqaedE3znlSjQsVRhDkE+g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
