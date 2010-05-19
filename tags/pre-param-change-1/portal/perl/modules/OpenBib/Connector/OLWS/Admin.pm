####################################################################
#
#  OpenBib::Connector::OLWS::Admin.pm
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Connector::OLWS::Admin;

use strict;
use warnings;
no warnings 'redefine';

use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Admin;
use OpenBib::Config;

sub create_db {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    # Parameter
    my $username         = $args{ 'username'        } || '';
    my $password         = $args{ 'password'        } || '';
    my $dbinfo_ref       = $args{ 'dbinfo'          } || '';

    if (!defined $username || !defined $password || !defined $dbinfo_ref->{dbname}){
        return {
            error => "not enough parameters"
        };
    }

    if (! ($username eq $config->{adminuser} && $password eq $config->{adminpasswd})){
        return {
            error => "couldn't authenticate"
        };
    }

    OpenBib::Admin::editcat_new($dbinfo_ref);
    
    return {
        success => "Database created"
    };
}

sub change_dbinfo {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    # Parameter
    my $username         = $args{ 'username'        } || '';
    my $password         = $args{ 'password'        } || '';
    my $dbinfo_ref       = $args{ 'dbinfo'          } || '';
    my $dboptions_ref    = $args{ 'dboptions'       } || '';

    if (!defined $username || !defined $password || !defined $dbinfo_ref->{dbname}){
        return {
            error => "not enough parameters"
        };
    }

    if (! ($username eq $config->{adminuser} && $password eq $config->{adminpasswd})){
        return {
            error => "couldn't authenticate"
        };
    }

    OpenBib::Admin::editcat_change($dbinfo_ref,$dboptions_ref);
    
    return {
        success => "Database Infos and Options change"
    };
}

sub remove_db {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    # Parameter
    my $username         = $args{ 'username'        } || '';
    my $password         = $args{ 'password'        } || '';
    my $dbname           = $args{ 'dbname'          } || '';

    if (!defined $username || !defined $password || !defined $dbname){
        return {
            error => "not enough parameters"
        };
    }

    if (! ($username eq $config->{adminuser} && $password eq $config->{adminpasswd})){
        return {
            error => "couldn't authenticate"
        };
    }

    OpenBib::Admin::editcat_del($dbname);

    return {
        success => "DB $dbname deleted"
    };
}

1;
