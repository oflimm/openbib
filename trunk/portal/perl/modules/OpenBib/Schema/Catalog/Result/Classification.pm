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

  data_type: 'text'
  is_nullable: 0

=head2 tstamp_create

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'timestamp'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "text", is_nullable => 0 },
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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2013-05-21 14:45:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:vQUpjPG8hKKH0kCIFplYiw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
