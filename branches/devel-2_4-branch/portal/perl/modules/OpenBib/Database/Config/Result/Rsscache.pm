package OpenBib::Database::Config::Result::Rsscache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Config::Result::Rsscache

=cut

__PACKAGE__->table("rsscache");

=head1 ACCESSORS

=head2 rssid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=head2 type

  data_type: 'tinyint'
  is_nullable: 0

=head2 subtype

  data_type: 'smallint'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "rssid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "type",
  { data_type => "tinyint", is_nullable => 0 },
  "subtype",
  { data_type => "smallint", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JtN5pVJeUFwoFPHZ0r6miw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
