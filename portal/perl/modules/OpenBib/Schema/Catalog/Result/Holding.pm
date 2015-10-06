package OpenBib::Schema::Catalog::Result::Holding;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::Holding

=cut

__PACKAGE__->table("holding");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'holding_id_seq'

=head2 import_hash

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "text",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "holding_id_seq",
  },
  "import_hash",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 holding_fields

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::HoldingField>

=cut

__PACKAGE__->has_many(
  "holding_fields",
  "OpenBib::Schema::Catalog::Result::HoldingField",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_holdings

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleHolding>

=cut

__PACKAGE__->has_many(
  "title_holdings",
  "OpenBib::Schema::Catalog::Result::TitleHolding",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-10-06 12:04:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:w5Ctoo6+ylG7WXzxYk4XZw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
