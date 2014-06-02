package OpenBib::Schema::Catalog::Result::TitleTitle;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::TitleTitle

=cut

__PACKAGE__->table("title_title");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'title_title_id_seq'

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 source_titleid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 target_titleid

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
    sequence          => "title_title_id_seq",
  },
  "field",
  { data_type => "smallint", is_nullable => 1 },
  "source_titleid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "target_titleid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 target_titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "target_titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "target_titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 source_titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "source_titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "source_titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2013-05-21 14:45:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7JHkapyO6IkWxrIvHdOjrA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
