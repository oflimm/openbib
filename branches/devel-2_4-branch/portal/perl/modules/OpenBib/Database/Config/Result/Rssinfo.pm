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
  { on_delete => "CASCADE", on_update => "CASCADE" },
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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 14:20:00
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Y+zlzhnGKbKqcNgGaDDrlA
# These lines were loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Rssinfo.pm' found in @INC.
# They are now part of the custom portion of this file
# for you to hand-edit.  If you do not either delete
# this section or remove that file from @INC, this section
# will be repeated redundantly when you re-create this
# file again via Loader!  See skip_load_external to disable
# this feature.

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
  { on_delete => "CASCADE", on_update => "CASCADE" },
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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 09:00:20
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:RnJ1GW1htGLoWRgbYgygbw
# These lines were loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Rssinfo.pm' found in @INC.
# They are now part of the custom portion of this file
# for you to hand-edit.  If you do not either delete
# this section or remove that file from @INC, this section
# will be repeated redundantly when you re-create this
# file again via Loader!  See skip_load_external to disable
# this feature.

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
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 viewrssfeeds

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Viewrssfeed>

=cut

__PACKAGE__->has_many(
  "viewrssfeeds",
  "OpenBib::Database::Config::Result::Viewrssfeed",
  { "foreign.rssid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 08:52:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:undxfElUPu6u9d64cAwxhA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
# End of lines loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Rssinfo.pm' 


# You can replace this text with custom content, and it will be preserved on regeneration
1;
# End of lines loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Rssinfo.pm' 


# You can replace this text with custom content, and it will be preserved on regeneration
1;
