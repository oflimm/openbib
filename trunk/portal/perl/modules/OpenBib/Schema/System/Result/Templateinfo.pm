use utf8;
package OpenBib::Schema::System::Result::Templateinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Templateinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<templateinfo>

=cut

__PACKAGE__->table("templateinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'templateinfo_id_seq'

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 templatename

  data_type: 'text'
  is_nullable: 0

=head2 templatetext

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "templateinfo_id_seq",
  },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "templatename",
  { data_type => "text", is_nullable => 0 },
  "templatetext",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 templateinforevisions

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Templateinforevision>

=cut

__PACKAGE__->has_many(
  "templateinforevisions",
  "OpenBib::Schema::System::Result::Templateinforevision",
  { "foreign.templateid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_templateinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserTemplateinfo>

=cut

__PACKAGE__->has_many(
  "user_templateinfos",
  "OpenBib::Schema::System::Result::UserTemplateinfo",
  { "foreign.templateid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2014-09-24 11:40:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:bh8EhnCJUHFhDB08jkCUUA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
