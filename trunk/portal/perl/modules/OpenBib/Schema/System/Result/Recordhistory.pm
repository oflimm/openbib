package OpenBib::Schema::System::Result::Recordhistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Recordhistory

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

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "titleid",
  { data_type => "varchar", is_nullable => 1, size => 255 },
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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-08-09 15:06:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:u7nKEsgrIP7fCIQkrIn0EQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
