package OpenBib::Schema::System::Result::Litlist;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Litlist

=cut

__PACKAGE__->table("litlist");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'litlist_id_seq'

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 title

  data_type: 'text'
  is_nullable: 0

=head2 type

  data_type: 'smallint'
  default_value: '1::smallint'
  is_nullable: 0

=head2 lecture

  data_type: 'boolean'
  default_value: false
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "litlist_id_seq",
  },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "title",
  { data_type => "text", is_nullable => 0 },
  "type",
  {
    data_type     => "smallint",
    default_value => "1::smallint",
    is_nullable   => 0,
  },
  "lecture",
  { data_type => "boolean", default_value => \"false", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 litlistitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Litlistitem>

=cut

__PACKAGE__->has_many(
  "litlistitems",
  "OpenBib::Schema::System::Result::Litlistitem",
  { "foreign.litlistid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 litlist_topics

Type: has_many

Related object: L<OpenBib::Schema::System::Result::LitlistTopic>

=cut

__PACKAGE__->has_many(
  "litlist_topics",
  "OpenBib::Schema::System::Result::LitlistTopic",
  { "foreign.litlistid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-11-26 11:21:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aV/0RbZmI/BslzabZ5sp0A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
