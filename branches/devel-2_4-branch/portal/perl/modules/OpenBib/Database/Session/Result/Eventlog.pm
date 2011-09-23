package OpenBib::Database::Session::Result::Eventlog;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Session::Result::Eventlog

=cut

__PACKAGE__->table("eventlog");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_nullable: 0

=head2 tstamp

  data_type: 'datetime'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 content

  data_type: 'mediumblob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_nullable => 0 },
  "tstamp",
  { data_type => "datetime", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "content",
  { data_type => "mediumblob", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:05:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rhEwPPXzW499wWyThqZgxw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
