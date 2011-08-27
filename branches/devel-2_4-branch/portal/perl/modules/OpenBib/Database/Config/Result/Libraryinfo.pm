package OpenBib::Database::Config::Result::Libraryinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Libraryinfo

=cut

__PACKAGE__->table("libraryinfo");

=head1 ACCESSORS

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 category

  data_type: 'smallint'
  is_nullable: 0

=head2 indicator

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "category",
  { data_type => "smallint", is_nullable => 0 },
  "indicator",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 14:20:00
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:UFqD0LuMbkCurYl9+UthfQ
# These lines were loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Libraryinfo.pm' found in @INC.
# They are now part of the custom portion of this file
# for you to hand-edit.  If you do not either delete
# this section or remove that file from @INC, this section
# will be repeated redundantly when you re-create this
# file again via Loader!  See skip_load_external to disable
# this feature.

package OpenBib::Database::Config::Result::Libraryinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Libraryinfo

=cut

__PACKAGE__->table("libraryinfo");

=head1 ACCESSORS

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 category

  data_type: 'smallint'
  is_nullable: 0

=head2 indicator

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "category",
  { data_type => "smallint", is_nullable => 0 },
  "indicator",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 09:00:20
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aOsoI4XHov9MuUZJ1615kg
# These lines were loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Libraryinfo.pm' found in @INC.
# They are now part of the custom portion of this file
# for you to hand-edit.  If you do not either delete
# this section or remove that file from @INC, this section
# will be repeated redundantly when you re-create this
# file again via Loader!  See skip_load_external to disable
# this feature.

package OpenBib::Database::Config::Result::Libraryinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Libraryinfo

=cut

__PACKAGE__->table("libraryinfo");

=head1 ACCESSORS

=head2 dbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 category

  data_type: 'smallint'
  is_nullable: 0

=head2 indicator

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "category",
  { data_type => "smallint", is_nullable => 0 },
  "indicator",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

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


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-08-26 08:52:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cho7pT+P/XLEixiGMRcc9g


# You can replace this text with custom content, and it will be preserved on regeneration
1;
# End of lines loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Libraryinfo.pm' 


# You can replace this text with custom content, and it will be preserved on regeneration
1;
# End of lines loaded from '/usr/local/lib/site_perl/OpenBib/Database/Config/Result/Libraryinfo.pm' 


# You can replace this text with custom content, and it will be preserved on regeneration
1;
