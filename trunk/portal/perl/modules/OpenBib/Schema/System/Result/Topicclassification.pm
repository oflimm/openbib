package OpenBib::Schema::System::Result::Topicclassification;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Topicclassification

=cut

__PACKAGE__->table("topicclassification");

=head1 ACCESSORS

=head2 topicid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 classification

  data_type: 'text'
  is_nullable: 0

=head2 type

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "topicid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "classification",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

=head2 topicid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Topic>

=cut

__PACKAGE__->belongs_to(
  "topicid",
  "OpenBib::Schema::System::Result::Topic",
  { id => "topicid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-10-23 10:41:11
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:w4e+tWrWhXaG4seI9dD3hA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
