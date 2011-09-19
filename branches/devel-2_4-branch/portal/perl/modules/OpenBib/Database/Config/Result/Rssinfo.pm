package OpenBib::Database::Config::Result::Rssinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Rssinfo

=cut

__PACKAGE__->table("rssinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 type

  data_type: 'smallint'
  is_nullable: 1

=head2 subtype

  data_type: 'smallint'
  is_nullable: 1

=head2 subtypedesc

  data_type: 'text'
  is_nullable: 1

=head2 active

  data_type: 'tinyint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "type",
  { data_type => "smallint", is_nullable => 1 },
  "subtype",
  { data_type => "smallint", is_nullable => 1 },
  "subtypedesc",
  { data_type => "text", is_nullable => 1 },
  "cache_tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "cache_content",
  { data_type => "text", is_nullable => 1 },

  "active",
  { data_type => "tinyint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 rsscaches

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Rsscache>

=cut

__PACKAGE__->has_many(
  "rsscaches",
  "OpenBib::Database::Config::Result::Rsscache",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Database::Config::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Database::Config::Result::Databaseinfo",
  { id => "dbid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 view_rsses

Type: has_many

Related object: L<OpenBib::Database::Config::Result::ViewRss>

=cut

__PACKAGE__->has_many(
  "view_rsses",
  "OpenBib::Database::Config::Result::ViewRss",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 viewinfos

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Viewinfo>

=cut

__PACKAGE__->has_many(
  "viewinfos",
  "OpenBib::Database::Config::Result::Viewinfo",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-08-31 13:46:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:w5wRkLVRSFGrml9peVPIng


# You can replace this text with custom content, and it will be preserved on regeneration
1;
