package OpenBib::Schema::System::Result::UserSession;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::UserSession

=cut

__PACKAGE__->table("user_session");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_session_id_seq'

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 targetid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "user_session_id_seq",
  },
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "targetid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 targetid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Authenticationtarget>

=cut

__PACKAGE__->belongs_to(
  "targetid",
  "OpenBib::Schema::System::Result::Authenticationtarget",
  { id => "targetid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-10-18 16:51:34
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gDvqOsHrzzcoahnAkk975A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
