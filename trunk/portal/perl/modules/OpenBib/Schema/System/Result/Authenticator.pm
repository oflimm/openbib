use utf8;
package OpenBib::Schema::System::Result::Authenticator;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Authenticator

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<authenticator>

=cut

__PACKAGE__->table("authenticator");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'authenticator_id_seq'

=head2 hostname

  data_type: 'text'
  is_nullable: 1

=head2 port

  data_type: 'text'
  is_nullable: 1

=head2 remoteuser

  data_type: 'text'
  is_nullable: 1

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 type

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "authenticator_id_seq",
  },
  "hostname",
  { data_type => "text", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "remoteuser",
  { data_type => "text", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 user_sessions

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSession>

=cut

__PACKAGE__->has_many(
  "user_sessions",
  "OpenBib::Schema::System::Result::UserSession",
  { "foreign.authenticatorid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2014-09-24 11:40:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7rcpjCHRwc5l55BeljieHQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
