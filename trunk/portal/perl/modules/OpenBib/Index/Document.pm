#####################################################################
#
#  OpenBib::Index::Document.pm
#
#  Dokumenten-Objekt fuer die Indexierung einer Suchmaschine
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Index;
use warnings;
no warnings 'redefine';
use utf8;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    # Set defaults
    my $id              = exists $arg_ref->{id}
        ? $arg_ref->{id}                      : undef;

    my $locationid      = exists $arg_ref->{locationid}
        ? $arg_ref->{locationid}              : undef;

    my $self = { };

    bless ($self, $class);

    $self->{_data}  = {};
    $self->{_index} = {};

    if ($database){
        $self->{_database}               = $database;
        $self->{_index}->{database} = $database;
        push @{$self->{_index}{dbstring}{1}}, ['database',$database];
        push @{$self->{_index}{facet_database}}, $database;
    }

    if ($locationid){
        push @{$self->{_index}{locationstring}}, $locationid;
        push @{$self->{_index}{facet_location}}, $locationid;
    }
    
    if ($id){
        $self->{_id}               = $id;
        $self->{_index}{id} = $id;
        push @{$self->{_index}{id}{1}}, ['id',$id];
    }

    
    return $self;
}

sub get_data {
    my $self = shift;

    return $self->{_data};
};

sub get_index {
    my $self = shift;

    return $self->{_index};
};

sub get_document {
    my $self = shift;
    
    return { record => $self->{_data}, index => $self->{_index} };
}

sub set_data {
    my ($self,$key,$value) = @_;

    $self->{_data}{$key} = $value;

    return;
}

sub add_data {
    my ($self,$key,$value) = @_;

    push @{$self->{_data}{$key}}, $value;

    return;
}

sub set_index {
    my ($self,$key,$weight,$value) = @_;

    $self->{_index}{$key}{$weight} = $value;

    return;
}

sub add_index {
    my ($self,$key,$weight,$value) = @_;

    push @{$self->{_index}{$key}{$weight}}, $value;

    return;
}

sub add_index_array {
    my ($self,$key,$weight,$value) = @_;

    push @{$self->{_index}{$key}{$weight}}, @{$value};

    return;
}

sub set_facet {
    my ($self,$weight,$value) = @_;

    $self->{_index}{$key} = $value;

    return;
}

sub add_facet {
    my ($self,$key,$value) = @_;

    push @{$self->{_index}{$key}}, $value;

    return;
}

sub DESTROY {
    my $self = shift;

    return;
}

1;
