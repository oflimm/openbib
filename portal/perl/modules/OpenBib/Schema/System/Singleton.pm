#####################################################################
#
#  OpenBib::Schema::System::Singleton
#
#  Singleton fuer den Schema-Zugriff
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
#
#  Idee von brian d foy 'The singleton design pattern', The Perl Review
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

package OpenBib::Schema::System::Singleton;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use OpenBib::Config::File;
use OpenBib::Schema::System;
use Log::Log4perl qw(get_logger :levels);

sub _new_instance {
    my $class = shift;
    my @args  = @_;

    my $logger = get_logger();
    
    my $self = {};

    bless ($self, $class);

    # Ininitalisierung mit Config-Parametern
    my $config = OpenBib::Config::File->instance;

    eval {
        $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) ;
    };

    if ($@){
        $logger->error("Error connecting to System-DB");
    }
    
    return $self;
}

sub get_schema {
    my $self = shift;

    return $self->{schema};
}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{schema}){
        eval {
            $self->{schema}->storage->dbh->disconnect;
        };

        if ($@){
            $logger->error($@);
        }
    }

    return;
}

sub DESTROY {
    my $self = shift;

    $self->disconnectDB;

    return;
}


1;
