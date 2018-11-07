use utf8;
package OpenBib::Schema::System::Result::Registration;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Registration

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<registration>

=cut

__PACKAGE__->table("registration");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 password

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "text", is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "password",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07046 @ 2018-11-07 15:47:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:XfSpml5f7zyGf96vUmhyAQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
