package OpenBib::Schema::System::Result::Rssinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Rssinfo

=cut

__PACKAGE__->table("rssinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'rssinfo_id_seq'

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 type

  data_type: 'smallint'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "rssinfo_id_seq",
  },
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "type",
  { data_type => "smallint", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 rsscaches

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Rsscache>

=cut

__PACKAGE__->has_many(
  "rsscaches",
  "OpenBib::Schema::System::Result::Rsscache",
  { "foreign.rssinfoid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 dbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "dbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "dbid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 viewinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->has_many(
  "viewinfos",
  "OpenBib::Schema::System::Result::Viewinfo",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_rsses

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewRss>

=cut

__PACKAGE__->has_many(
  "view_rsses",
  "OpenBib::Schema::System::Result::ViewRss",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-09-23 11:14:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:jyxpyL9AgM9KpgLEEFEGdw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
