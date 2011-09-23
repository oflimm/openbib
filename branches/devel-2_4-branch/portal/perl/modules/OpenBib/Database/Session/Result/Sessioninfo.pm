package OpenBib::Database::Session::Result::Sessioninfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Session::Result::Sessioninfo

=cut

__PACKAGE__->table("sessioninfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 sessionid

  data_type: 'char'
  is_nullable: 0
  size: 33

=head2 createtime

  data_type: 'datetime'
  is_nullable: 1

=head2 lastresultset

  data_type: 'blob'
  is_nullable: 1

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 userpassword

  data_type: 'text'
  is_nullable: 1

=head2 queryoptions

  data_type: 'text'
  is_nullable: 1

=head2 returnurl

  data_type: 'text'
  is_nullable: 1

=head2 searchform

  data_type: 'text'
  is_nullable: 1

=head2 searchprofile

  data_type: 'text'
  is_nullable: 1

=head2 bibsonomy_user

  data_type: 'text'
  is_nullable: 1

=head2 bibsonomy_key

  data_type: 'text'
  is_nullable: 1

=head2 bibsonomy_sync

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "sessionid",
  { data_type => "char", is_nullable => 0, size => 33 },
  "createtime",
  { data_type => "datetime", is_nullable => 1 },
  "lastresultset",
  { data_type => "blob", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "userpassword",
  { data_type => "text", is_nullable => 1 },
  "queryoptions",
  { data_type => "text", is_nullable => 1 },
  "returnurl",
  { data_type => "text", is_nullable => 1 },
  "searchform",
  { data_type => "text", is_nullable => 1 },
  "searchprofile",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_user",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_key",
  { data_type => "text", is_nullable => 1 },
  "bibsonomy_sync",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-09-23 11:05:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:J9pnvAp4eyT+sNTdFgWhmQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
