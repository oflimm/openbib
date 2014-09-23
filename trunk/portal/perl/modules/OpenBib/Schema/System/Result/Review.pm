package OpenBib::Schema::System::Result::Review;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Review

=cut

__PACKAGE__->table("review");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'review_id_seq'

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 nickname

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 title

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 reviewtext

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 rating

  data_type: 'smallint'
  default_value: '0)::smallint'
  is_nullable: 0

=head2 dbname

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 titleid

  data_type: 'text'
  default_value: 0
  is_nullable: 0

=head2 titleisbn

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
    sequence          => "review_id_seq",
  },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "nickname",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "title",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "reviewtext",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "rating",
  {
    data_type     => "smallint",
    default_value => "0)::smallint",
    is_nullable   => 0,
  },
  "dbname",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "titleid",
  { data_type => "text", default_value => 0, is_nullable => 0 },
  "titleisbn",
  { data_type => "text", default_value => "", is_nullable => 0 },
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

=head2 reviewratings

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Reviewrating>

=cut

__PACKAGE__->has_many(
  "reviewratings",
  "OpenBib::Schema::System::Result::Reviewrating",
  { "foreign.reviewid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-09-23 11:14:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cqwK9lFgLWkHRMPyo2g2gw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
