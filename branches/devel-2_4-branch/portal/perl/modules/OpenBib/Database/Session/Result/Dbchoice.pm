package OpenBib::Database::Session::Result::Dbchoice;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Session::Result::Dbchoice

=cut

__PACKAGE__->table("dbchoice");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_nullable: 0

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_nullable => 0 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:05:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:WQKvqWMtrNUya55RlAm3Lw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
