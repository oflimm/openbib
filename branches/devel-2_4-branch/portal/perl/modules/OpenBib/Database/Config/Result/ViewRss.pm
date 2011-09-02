package OpenBib::Database::Config::Result::ViewRss;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::ViewRss

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

Related object: L<OpenBib::Database::Config::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Database::Config::Result::Viewinfo",
  { id => "viewid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 rssid

Type: belongs_to

Related object: L<OpenBib::Database::Config::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssid",
  "OpenBib::Database::Config::Result::Rssinfo",
  { id => "rssid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-08-31 13:46:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BTx/1sm/V8dt0vAJumH3HA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
