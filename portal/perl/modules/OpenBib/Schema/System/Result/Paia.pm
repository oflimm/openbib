use utf8;
package OpenBib::Schema::System::Result::Paia;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Paia

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<paia>

=cut

__PACKAGE__->table("paia");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'paia_id_seq'

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 1
  original: {default_value => \"now()"}

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 token

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "paia_id_seq",
  },
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "username",
  { data_type => "text", is_nullable => 1 },
  "token",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-01-20 13:11:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EVjehIxzxw0CtIVbmspj2A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
