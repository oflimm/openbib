package OpenBib::Schema::System::Result::LitlistTopic;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::LitlistTopic

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
__PACKAGE__->set_primary_key("id");

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


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-05-11 15:52:34
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Y20wZlw+8ib2v6P7XMuJYQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
