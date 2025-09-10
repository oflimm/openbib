use utf8;
package OpenBib::Schema::System::Result::Topic;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Topic

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<topic>

=cut

__PACKAGE__->table("topic");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'topic_id_seq'

=head2 name

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 description

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "topic_id_seq",
  },
  "name",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "description",
  { data_type => "text", default_value => "", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 litlist_topics

Type: has_many

Related object: L<OpenBib::Schema::System::Result::LitlistTopic>

=cut

__PACKAGE__->has_many(
  "litlist_topics",
  "OpenBib::Schema::System::Result::LitlistTopic",
  { "foreign.topicid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 topicclassifications

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Topicclassification>

=cut

__PACKAGE__->has_many(
  "topicclassifications",
  "OpenBib::Schema::System::Result::Topicclassification",
  { "foreign.topicid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wx0ZTWTU18mTUM7OifUirw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
