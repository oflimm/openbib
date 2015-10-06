package OpenBib::Schema::Catalog::Result::TitleHolding;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::TitleHolding

=cut

__PACKAGE__->table("title_holding");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'title_holding_id_seq'

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 holdingid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 supplement

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "title_holding_id_seq",
  },
  "field",
  { data_type => "smallint", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "holdingid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 holdingid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Holding>

=cut

__PACKAGE__->belongs_to(
  "holdingid",
  "OpenBib::Schema::Catalog::Result::Holding",
  { id => "holdingid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-10-06 12:14:31
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ZCJtbsC+FgqGVWZ5jNQtTA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
