package OpenBib::Schema::Catalog::Result::Classification;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::Classification

=cut

__PACKAGE__->table("classification");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 tstamp_create

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'timestamp'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "tstamp_create",
  { data_type => "timestamp", is_nullable => 1 },
  "tstamp_update",
  { data_type => "timestamp", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 classification_fields

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::ClassificationField>

=cut

__PACKAGE__->has_many(
  "classification_fields",
  "OpenBib::Schema::Catalog::Result::ClassificationField",
  { "foreign.classificationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_classifications

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleClassification>

=cut

__PACKAGE__->has_many(
  "title_classifications",
  "OpenBib::Schema::Catalog::Result::TitleClassification",
  { "foreign.classificationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-21 12:51:30
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:zryy0zsj9eSx/ByKPVAgaA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
