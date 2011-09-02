package OpenBib::Database::Config::Result::Databaseinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Databaseinfo

=cut

__PACKAGE__->table("databaseinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 shortdesc

  data_type: 'text'
  is_nullable: 1

=head2 system

  data_type: 'text'
  is_nullable: 1

=head2 dbname

  data_type: 'varchar'
  is_nullable: 1
  size: 25

=head2 sigel

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 url

  data_type: 'text'
  is_nullable: 1

=head2 use_libinfo

  data_type: 'tinyint'
  is_nullable: 1

=head2 active

  data_type: 'tinyint'
  is_nullable: 1

=head2 protocol

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 host

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 remotepath

  data_type: 'text'
  is_nullable: 1

=head2 remoteuser

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 remotepassword

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 titlefile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 personfile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 corporatebodyfile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 subjectfile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 classificationfile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 holdingfile

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 autoconvert

  data_type: 'tinyint'
  is_nullable: 1

=head2 circ

  data_type: 'tinyint'
  is_nullable: 1

=head2 circurl

  data_type: 'text'
  is_nullable: 1

=head2 circwsurl

  data_type: 'text'
  is_nullable: 1

=head2 circdb

  data_type: 'text'
  is_nullable: 1

=head2 allcount

  data_type: 'bigint'
  default_value: 0
  is_nullable: 1

=head2 journalcount

  data_type: 'bigint'
  default_value: 0
  is_nullable: 1

=head2 articlecount

  data_type: 'bigint'
  default_value: 0
  is_nullable: 1

=head2 digitalcount

  data_type: 'bigint'
  default_value: 0
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "shortdesc",
  { data_type => "text", is_nullable => 1 },
  "system",
  { data_type => "text", is_nullable => 1 },
  "dbname",
  { data_type => "varchar", is_nullable => 1, size => 25 },
  "sigel",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "url",
  { data_type => "text", is_nullable => 1 },
  "use_libinfo",
  { data_type => "tinyint", is_nullable => 1 },
  "active",
  { data_type => "tinyint", is_nullable => 1 },
  "protocol",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "host",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "remotepath",
  { data_type => "text", is_nullable => 1 },
  "remoteuser",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "remotepassword",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "titlefile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "personfile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "corporatebodyfile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "subjectfile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "classificationfile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "holdingfile",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "autoconvert",
  { data_type => "tinyint", is_nullable => 1 },
  "circ",
  { data_type => "tinyint", is_nullable => 1 },
  "circurl",
  { data_type => "text", is_nullable => 1 },
  "circwsurl",
  { data_type => "text", is_nullable => 1 },
  "circdb",
  { data_type => "text", is_nullable => 1 },
  "allcount",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "journalcount",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "articlecount",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
  "digitalcount",
  { data_type => "bigint", default_value => 0, is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("dbname", ["dbname"]);

=head1 RELATIONS

=head2 libraryinfos

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Libraryinfo>

=cut

__PACKAGE__->has_many(
  "libraryinfos",
  "OpenBib::Database::Config::Result::Libraryinfo",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 orgunit_dbs

Type: has_many

Related object: L<OpenBib::Database::Config::Result::OrgunitDb>

=cut

__PACKAGE__->has_many(
  "orgunit_dbs",
  "OpenBib::Database::Config::Result::OrgunitDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 rssinfos

Type: has_many

Related object: L<OpenBib::Database::Config::Result::Rssinfo>

=cut

__PACKAGE__->has_many(
  "rssinfos",
  "OpenBib::Database::Config::Result::Rssinfo",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_dbs

Type: has_many

Related object: L<OpenBib::Database::Config::Result::ViewDb>

=cut

__PACKAGE__->has_many(
  "view_dbs",
  "OpenBib::Database::Config::Result::ViewDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-08-31 13:46:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dFTMF9UZa9C9fXn6fmXzeA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
