use utf8;
package OpenBib::Schema::System::Result::Recordhistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Recordhistory

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<recordhistory>

=cut

__PACKAGE__->table("recordhistory");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sVzvkRVHaHM9P23sPktpWw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
