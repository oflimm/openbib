package OpenBib::Database::Session::Result::Query;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Session::Result::Query

=cut

__PACKAGE__->table("queries");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 queryid

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 query

  data_type: 'text'
  is_nullable: 1

=head2 hitrange

  data_type: 'integer'
  is_nullable: 1

=head2 hits

  data_type: 'integer'
  is_nullable: 1

=head2 dbases

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "queryid",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "query",
  { data_type => "text", is_nullable => 1 },
  "hitrange",
  { data_type => "integer", is_nullable => 1 },
  "hits",
  { data_type => "integer", is_nullable => 1 },
  "dbases",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("queryid");

=head1 RELATIONS

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Database::Session::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Database::Session::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:36:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:F9uT3GL3+tkNHTjynMmpIQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
