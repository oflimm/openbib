use utf8;
package OpenBib::Schema::System::Result::Authenticatorinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Authenticatorinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<authenticatorinfo>

=cut

__PACKAGE__->table("authenticatorinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'authenticatorinfo_id_seq'

=head2 name

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
    sequence          => "authenticatorinfo_id_seq",
  },
  "name",
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

=head2 authenticator_views

Type: has_many

Related object: L<OpenBib::Schema::System::Result::AuthenticatorView>

=cut

__PACKAGE__->has_many(
  "authenticator_views",
  "OpenBib::Schema::System::Result::AuthenticatorView",
  { "foreign.authenticatorid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

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

=head2 userinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->has_many(
  "userinfos",
  "OpenBib::Schema::System::Result::Userinfo",
  { "foreign.authenticatorid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7+tg0GRVTlHdsiOh2QyOHg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
