use utf8;
package OpenBib::Schema::System::Result::LitlistTopic;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::LitlistTopic

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<litlist_topic>

=cut

__PACKAGE__->table("litlist_topic");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'litlist_topic_id_seq'

=head2 litlistid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 topicid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "litlist_topic_id_seq",
  },
  "litlistid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "topicid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 litlistid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Litlist>

=cut

__PACKAGE__->belongs_to(
  "litlistid",
  "OpenBib::Schema::System::Result::Litlist",
  { id => "litlistid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2014-09-25 11:06:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:N7/g3rKmOJbBudAapTZQkQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
