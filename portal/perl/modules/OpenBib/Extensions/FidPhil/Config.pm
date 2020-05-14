####################################################################
#
#  OpenBib::Extensions::FidPhil::Config
#
#  Dieses File ist (C) 2004-2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Extensions::FidPhil::Config;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base 'OpenBib::Config';

sub new {
    my ($class,$arg_ref) = @_;

    my $self = { };

    bless ($self, $class);
    
    return $self;
}

sub get_viewusers {
    my $self     = shift;
    my $viewname = shift;
    # Log4perl logger erzeugen
    my $logger = get_logger();
    my ($atime,$btime,$timeall);
    
    if ($self->{benchmark}) {
        $atime=new Benchmark;
    }

    my $users = $self->get_schema->resultset('Userinfo')->search(
        {
            'me.viewname' => $viewname,
        },
        {
            order_by => 'email',
        }
    );

    my @userdata=();

    while (my $item = $users->next){
        push @userdata, $item->{email};
    }

    return @userdata;
}
