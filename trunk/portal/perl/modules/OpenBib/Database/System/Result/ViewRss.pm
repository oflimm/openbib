package OpenBib::Database::System::Result::ViewRss;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::ViewRss

=cut

__PACKAGE__->table("view_rss");

=head1 ACCESSORS

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 rssid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "rssid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Database::System::Result::Viewinfo",
  { id => "viewid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 rssid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssid",
  "OpenBib::Database::System::Result::Rssinfo",
  { id => "rssid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-27 13:44:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Vb1xU1LE6crCJcYGh5rR9g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
