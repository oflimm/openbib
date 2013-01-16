use utf8;
package OpenBib::Schema::System::Result::SessionCartitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::SessionCartitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<session_cartitem>

=cut

__PACKAGE__->table("session_cartitem");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'session_cartitem_id_seq'

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 cartitemid

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
    sequence          => "session_cartitem_id_seq",
  },
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "cartitemid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 cartitemid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Cartitem>

=cut

__PACKAGE__->belongs_to(
  "cartitemid",
  "OpenBib::Schema::System::Result::Cartitem",
  { id => "cartitemid" },
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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2013-01-16 16:01:20
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:CltLj0+BGjb9YugCZ2t1NA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
