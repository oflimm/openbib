#####################################################################
#
#  OpenBib::Conv::Config
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Conv::Config;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton::Process);

use Apache2::Reload;
use YAML::Syck;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $dbname     = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}             : undef;
    
    # Ininitalisierung mit Default Config-Parametern

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    # Ininitalisierung mit Config-Parametern
    my $config = YAML::Syck::LoadFile("/opt/openbib/conf/convert.yml");

    my $self = $config->{convtab}{default};

    if (defined $dbname && exists $config->{convtab}{$dbname}){
        foreach my $type (keys %$self){
            $self->{$type} = $config->{convtab}{$dbname}{$type} if (exists $config->{convtab}{$dbname}{$type});
        }
    }

    bless ($self, $class);

    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $dbname     = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}             : undef;
    
    # Ininitalisierung mit Default Config-Parametern

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    # Ininitalisierung mit Config-Parametern
    my $config = YAML::Syck::LoadFile("/opt/openbib/conf/convert.yml");

    my $self = $config->{convtab}{default};

    if (defined $dbname && exists $config->{convtab}{$dbname}){
        foreach my $type (keys %$self){
            $self->{$type} = $config->{convtab}{$dbname}{$type} if (exists $config->{convtab}{$dbname}{$type});
        }
    }

    bless ($self, $class);

    return $self;
}

1;
