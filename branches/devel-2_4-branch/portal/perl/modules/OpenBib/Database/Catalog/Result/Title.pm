package OpenBib::Database::Catalog::Result::Title;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Catalog::Result::Title

=cut

__PACKAGE__->table("title");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 tstamp_create

  data_type: 'bigint'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'bigint'
  is_nullable: 1

=head2 titlecache

  data_type: 'blob'
  is_nullable: 1

=head2 popularity

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "tstamp_create",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp_update",
  { data_type => "bigint", is_nullable => 1 },
  "titlecache",
  { data_type => "blob", is_nullable => 1 },
  "popularity",
  { data_type => "integer", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 title_classifications

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleClassification>

=cut

__PACKAGE__->has_many(
  "title_classifications",
  "OpenBib::Database::Catalog::Result::TitleClassification",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_corporatebodies

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleCorporatebody>

=cut

__PACKAGE__->has_many(
  "title_corporatebodies",
  "OpenBib::Database::Catalog::Result::TitleCorporatebody",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_fields

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleField>

=cut

__PACKAGE__->has_many(
  "title_fields",
  "OpenBib::Database::Catalog::Result::TitleField",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_holdings

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleHolding>

=cut

__PACKAGE__->has_many(
  "title_holdings",
  "OpenBib::Database::Catalog::Result::TitleHolding",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_normfields

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleNormfield>

=cut

__PACKAGE__->has_many(
  "title_normfields",
  "OpenBib::Database::Catalog::Result::TitleNormfield",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_people

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitlePerson>

=cut

__PACKAGE__->has_many(
  "title_people",
  "OpenBib::Database::Catalog::Result::TitlePerson",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_subjects

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleSubject>

=cut

__PACKAGE__->has_many(
  "title_subjects",
  "OpenBib::Database::Catalog::Result::TitleSubject",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_title_source_titleids

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleTitle>

=cut

__PACKAGE__->has_many(
  "title_title_source_titleids",
  "OpenBib::Database::Catalog::Result::TitleTitle",
  { "foreign.source_titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_title_target_titleids

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleTitle>

=cut

__PACKAGE__->has_many(
  "title_title_target_titleids",
  "OpenBib::Database::Catalog::Result::TitleTitle",
  { "foreign.target_titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2012-05-28 20:52:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:XXAGTUPNBRbMEP23HuVsXQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
