package OpenBib::Database::Enrichment::Result::Borrow;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Enrichment::Result::Borrow

=cut

__PACKAGE__->table("borrows");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=head2 isbn

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "isbn",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "content",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-02-28 11:58:46
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ktJl7BKsatoUxeReaDrXIw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
