use utf8;
package OpenBib::Schema::System::Result::Databaseinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Databaseinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<databaseinfo>

=cut

__PACKAGE__->table("databaseinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'databaseinfo_id_seq'

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

  data_type: 'text'
  is_nullable: 1

=head2 sigel

  data_type: 'text'
  is_nullable: 1

=head2 url

  data_type: 'text'
  is_nullable: 1

=head2 profileid

  data_type: 'bigint'
  is_nullable: 1

=head2 active

  data_type: 'boolean'
  is_nullable: 1

=head2 locationid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 protocol

  data_type: 'text'
  is_nullable: 1

=head2 host

  data_type: 'text'
  is_nullable: 1

=head2 remotepath

  data_type: 'text'
  is_nullable: 1

=head2 remoteuser

  data_type: 'text'
  is_nullable: 1

=head2 remotepassword

  data_type: 'text'
  is_nullable: 1

=head2 titlefile

  data_type: 'text'
  is_nullable: 1

=head2 personfile

  data_type: 'text'
  is_nullable: 1

=head2 corporatebodyfile

  data_type: 'text'
  is_nullable: 1

=head2 subjectfile

  data_type: 'text'
  is_nullable: 1

=head2 classificationfile

  data_type: 'text'
  is_nullable: 1

=head2 holdingfile

  data_type: 'text'
  is_nullable: 1

=head2 autoconvert

  data_type: 'boolean'
  is_nullable: 1

=head2 circ

  data_type: 'boolean'
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

=head2 parentdbid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 schema

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=head2 circtype

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "databaseinfo_id_seq",
  },
  "description",
  { data_type => "text", is_nullable => 1 },
  "shortdesc",
  { data_type => "text", is_nullable => 1 },
  "system",
  { data_type => "text", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "sigel",
  { data_type => "text", is_nullable => 1 },
  "url",
  { data_type => "text", is_nullable => 1 },
  "profileid",
  { data_type => "bigint", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "locationid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "protocol",
  { data_type => "text", is_nullable => 1 },
  "host",
  { data_type => "text", is_nullable => 1 },
  "remotepath",
  { data_type => "text", is_nullable => 1 },
  "remoteuser",
  { data_type => "text", is_nullable => 1 },
  "remotepassword",
  { data_type => "text", is_nullable => 1 },
  "titlefile",
  { data_type => "text", is_nullable => 1 },
  "personfile",
  { data_type => "text", is_nullable => 1 },
  "corporatebodyfile",
  { data_type => "text", is_nullable => 1 },
  "subjectfile",
  { data_type => "text", is_nullable => 1 },
  "classificationfile",
  { data_type => "text", is_nullable => 1 },
  "holdingfile",
  { data_type => "text", is_nullable => 1 },
  "autoconvert",
  { data_type => "boolean", is_nullable => 1 },
  "circ",
  { data_type => "boolean", is_nullable => 1 },
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
  "parentdbid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "schema",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "circtype",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<uq_databaseinfo_dbname>

=over 4

=item * L</dbname>

=back

=cut

__PACKAGE__->add_unique_constraint("uq_databaseinfo_dbname", ["dbname"]);

=head1 RELATIONS

=head2 databaseinfo_searchengines

Type: has_many

Related object: L<OpenBib::Schema::System::Result::DatabaseinfoSearchengine>

=cut

__PACKAGE__->has_many(
  "databaseinfo_searchengines",
  "OpenBib::Schema::System::Result::DatabaseinfoSearchengine",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 databaseinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->has_many(
  "databaseinfos",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { "foreign.parentdbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 locationid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Locationinfo>

=cut

__PACKAGE__->belongs_to(
  "locationid",
  "OpenBib::Schema::System::Result::Locationinfo",
  { id => "locationid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 orgunit_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::OrgunitDb>

=cut

__PACKAGE__->has_many(
  "orgunit_dbs",
  "OpenBib::Schema::System::Result::OrgunitDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 parentdbid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->belongs_to(
  "parentdbid",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { id => "parentdbid" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 rssinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Rssinfo>

=cut

__PACKAGE__->has_many(
  "rssinfos",
  "OpenBib::Schema::System::Result::Rssinfo",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchprofile_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::SearchprofileDb>

=cut

__PACKAGE__->has_many(
  "searchprofile_dbs",
  "OpenBib::Schema::System::Result::SearchprofileDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 updatelogs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Updatelog>

=cut

__PACKAGE__->has_many(
  "updatelogs",
  "OpenBib::Schema::System::Result::Updatelog",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserDb>

=cut

__PACKAGE__->has_many(
  "user_dbs",
  "OpenBib::Schema::System::Result::UserDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewDb>

=cut

__PACKAGE__->has_many(
  "view_dbs",
  "OpenBib::Schema::System::Result::ViewDb",
  { "foreign.dbid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-01-20 13:11:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NgAxrxgxcA7fxjIEbpuRhw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
