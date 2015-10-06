package OpenBib::Schema::Catalog::Result::Title;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::Title

=cut

__PACKAGE__->table("title");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'title_id_seq'

=head2 tstamp_create

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'timestamp'
  is_nullable: 1

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=head2 popularity

  data_type: 'integer'
  is_nullable: 1

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
    sequence          => "title_id_seq",
  },
  "tstamp_create",
  { data_type => "timestamp", is_nullable => 1 },
  "tstamp_update",
  { data_type => "timestamp", is_nullable => 1 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
  "popularity",
  { data_type => "integer", is_nullable => 1 },
  "import_hash",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 title_classifications

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleClassification>

=cut

__PACKAGE__->has_many(
  "title_classifications",
  "OpenBib::Schema::Catalog::Result::TitleClassification",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_corporatebodies

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleCorporatebody>

=cut

__PACKAGE__->has_many(
  "title_corporatebodies",
  "OpenBib::Schema::Catalog::Result::TitleCorporatebody",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_fields

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleField>

=cut

__PACKAGE__->has_many(
  "title_fields",
  "OpenBib::Schema::Catalog::Result::TitleField",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_holdings

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleHolding>

=cut

__PACKAGE__->has_many(
  "title_holdings",
  "OpenBib::Schema::Catalog::Result::TitleHolding",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_people

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitlePerson>

=cut

__PACKAGE__->has_many(
  "title_people",
  "OpenBib::Schema::Catalog::Result::TitlePerson",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_subjects

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleSubject>

=cut

__PACKAGE__->has_many(
  "title_subjects",
  "OpenBib::Schema::Catalog::Result::TitleSubject",
  { "foreign.titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_title_target_titleids

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleTitle>

=cut

__PACKAGE__->has_many(
  "title_title_target_titleids",
  "OpenBib::Schema::Catalog::Result::TitleTitle",
  { "foreign.target_titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_titles

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleTitle>

=cut

__PACKAGE__->has_many(
  "title_titles",
  "OpenBib::Schema::Catalog::Result::TitleTitle",
  { "foreign.source_titleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-10-06 12:14:31
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ctxfxY+oUQ8C7IpMoqaF3A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
