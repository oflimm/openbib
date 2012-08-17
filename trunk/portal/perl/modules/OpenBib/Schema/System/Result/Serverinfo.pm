package OpenBib::Schema::System::Result::Serverinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Serverinfo

=cut

__PACKAGE__->table("serverinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'serverinfo_id_seq'

=head2 host

  data_type: 'text'
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
    sequence          => "serverinfo_id_seq",
  },
  "host",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-08-17 09:44:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dTVvthrw7oQs3GT1aGlLlw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
