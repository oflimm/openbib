use utf8;
package OpenBib::Schema::System::Result::Rsscache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Rsscache

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<rsscache>

=cut

__PACKAGE__->table("rsscache");

=head1 ACCESSORS

=head2 rssinfoid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 id

  data_type: 'text'
  is_nullable: 1

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 content

  data_type: 'text'
  is_nullable: 1

=head2 pid

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'rsscache_pid_seq'

=cut

__PACKAGE__->add_columns(
  "rssinfoid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "id",
  { data_type => "text", is_nullable => 1 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
  "pid",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "rsscache_pid_seq",
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</pid>

=back

=cut

__PACKAGE__->set_primary_key("pid");

=head1 RELATIONS

=head2 rssinfoid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Rssinfo>

=cut

__PACKAGE__->belongs_to(
  "rssinfoid",
  "OpenBib::Schema::System::Result::Rssinfo",
  { id => "rssinfoid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5gwKH3peXd2F5MVa6lqJ6w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
