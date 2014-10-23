package OpenBib::Schema::System::Result::Dbrtopic;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Dbrtopic

=cut

__PACKAGE__->table("dbrtopic");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'dbrtopic_id_seq'

=head2 topic

  data_type: 'text'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "dbrtopic_id_seq",
  },
  "topic",
  { data_type => "text", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 dbrtopic_dbistopics

Type: has_many

Related object: L<OpenBib::Schema::System::Result::DbrtopicDbistopic>

=cut

__PACKAGE__->has_many(
  "dbrtopic_dbistopics",
  "OpenBib::Schema::System::Result::DbrtopicDbistopic",
  { "foreign.dbrtopicid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2014-10-23 10:41:11
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yuGAqrOAad9O7Q/L6l5J4Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
