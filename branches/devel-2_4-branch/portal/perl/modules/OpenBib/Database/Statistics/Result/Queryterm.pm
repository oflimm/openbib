package OpenBib::Database::Statistics::Result::Queryterm;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Queryterm

=cut

__PACKAGE__->table("queryterm");

=head1 ACCESSORS

=head2 tstamp

  data_type: 'datetime'
  is_nullable: 1

=head2 viewname

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 content

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=cut

__PACKAGE__->add_columns(
  "tstamp",
  { data_type => "datetime", is_nullable => 1 },
  "viewname",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "content",
  { data_type => "varchar", is_nullable => 1, size => 40 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-12-13 11:06:13
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:p9mKS5FqTVH+CXnpy+jDLA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
