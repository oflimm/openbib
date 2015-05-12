package OpenBib::Schema::System::Result::Rsscache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Rsscache

=cut

__PACKAGE__->table("rsscache");

=head1 ACCESSORS

=head2 rssinfoid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 id

  data_type: 'text'
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "rssinfoid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "id",
  { data_type => "text", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 rssinfoid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssinfoid",
  "OpenBib::Schema::System::Result::Rssinfo",
  { id => "rssinfoid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-05-11 15:52:34
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oVTh8FrLR8mDOxAuSnd1RQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
