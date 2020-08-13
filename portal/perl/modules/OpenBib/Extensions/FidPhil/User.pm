#####################################################################
#
#  OpenBib::User
#
#  Dieses File ist (C) 2006-2019 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

package OpenBib::Extensions::FidPhil::User;

use strict;
use warnings;
no warnings 'redefine';
use utf8;
use OpenBib::User;

use base 'OpenBib::User';

# sub new {
#     my ($class,$arg_ref) = @_;

#     my $self = { };

#     bless ($self, $class);
    
#     return $self;
# }

sub showUsersForView {
    my ($self,$arg_ref) = @_;
    my @found_userids = ();
    my $userlist_ref = [];
    my $view                 = $arg_ref->{view};
    my $where_ref = {};
    $where_ref->{viewid} = { '=' => 2 };
    my $users = $self->get_schema->resultset('Userinfo')->search(
        {
            'viewid' => 2,
        });
    foreach my $user ($users->all){
            my $userid = $user->get_column('id');
            push @found_userids, $userid;
        }
    foreach my $userid (@found_userids){
       # $logger->debug("Found ID $userid");
        my $single_user = new OpenBib::User({ID => $userid});
        push @$userlist_ref, $single_user->get_info;
    }
    return $userlist_ref;
}

1;
