#####################################################################
#
#  OpenBib::Conv::Common::Util
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 1997-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Conv::Common::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Text::Unidecode;

our (%person,%corporatebody,%subject,%classification);
our ($next_autid,$next_korid,$next_swtid,$next_notid) = (1,1,1,1);

our %german_umlauts = (
    'Ä' => 'Ae',
    'ä' => 'ae',
    'Ö' => 'Oe',
    'ö' => 'oe',
    'Ü' => 'Ue',
    'ü' => 'ue',
    'ß' => 'ss', 
    );

%person         = ();
%corporatebody  = ();
%subject        = ();
%classification = ();

sub get_person_id {
    my ($content)=@_;

    my $new = 0;

    # Verlinkt per GND?
    if ($content =~m/DE-588/){
	$content=~s/\(DE-588\)//;
    }

    my $normalized_id = normalize_id($content);
    
    unless (exists $person{$normalized_id}){
        $person{$normalized_id}=$normalized_id;
        $new = 1;
    }

    return ($person{$normalized_id},$new);
}

sub set_person_id {
    my ($id,$content)=@_;

    $person{$content} = $id;

    return;
}

sub get_corporatebody_id {
    my ($content)=@_;

    my $new = 0;

    # Verlinkt per GND?
    if ($content =~m/DE-588/){
	$content=~s/\(DE-588\)//;
    }

    my $normalized_id = normalize_id($content);
    
    unless (exists $corporatebody{$normalized_id}){
        $corporatebody{$normalized_id}=$normalized_id;
        $new = 1;
    }

    return ($corporatebody{$normalized_id},$new);
}

sub set_corporatebody_id {
    my ($id,$content)=@_;

    $corporatebody{$content} = $id;

    return;
}

sub get_subject_id {
    my ($content)=@_;

    my $new = 0;

    # Verlinkt per GND?
    if ($content =~m/DE-588/){
	$content=~s/\(DE-588\)//;
    }

    my $normalized_id = normalize_id($content);
        
    unless (exists $subject{$normalized_id}){
        $subject{$normalized_id}=$normalized_id;
        $new = 1;
    }

    return ($subject{$normalized_id},$new);
}


sub set_subject_id {
    my ($id,$content)=@_;

    $subject{$content} = $id;

    return;
}

sub get_classification_id {
    my ($content)=@_;

    my $new = 0;

    # Verlinkt per GND?
    if ($content =~m/DE-588/){
	$content=~s/\(DE-588\)//;
    }

    my $normalized_id = normalize_id($content);

    unless (exists $classification{$normalized_id}){
        $classification{$normalized_id}=$normalized_id;
        $new = 1;
    }

    return ($classification{$normalized_id},$new);
}

sub set_classification_id {
    my ($id,$content)=@_;

    $classification{$content} = $id;

    return;
}

sub normalize_id {
    my ($content)=@_;

    $content = lc($content);

    $content=~s/([ÄäÖöÜüß])/$german_umlauts{$1}/g;
    
    $content=~s/\W/_/g;
    $content=~s/__+/_/g;
    $content=~s/_$//;
    
    return unidecode($content);
}

1;
__END__

=head1 NAME

OpenBib::Conv::Common::Util - Zusammenfassung von Funktionen, die von mehreren Datenbackends
verwendet werden

=head1 DESCRIPTION

Dieses Modul enthält Hilfsfunktionen, die von mehreren Datenbackens
verwendet werden.

=head1 SYNOPSIS

 use OpenBib::Conv::Common::Util;

 print OpenBib::Conv::Common::Util::get_person_id("Doe, John")

 => doe_john

 print OpenBib::Conv::Common::Util::get_person_id("Foo, Bar")

 => foo_bar

 print OpenBib::Conv::Common::Util::get_person_id("Baz, Bar")

 => baz_bar

 print OpenBib::Conv::Common::Util::get_autidn("Foo, Bar")

 => foo_bar

=head1 METHODS

=over 4

=item get_person_id($name)

Gibt in der Normdatenart Person die für die Ansetzungsform $name generierte ID
zurück. Wenn $name noch nicht existiert, dann wird eine neue ID generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte ID
zurückgeliefert.

=item get_corporatebody_id($name)

Gibt in der Normdatenart Körperschaft die für die Ansetzungsform $name generierte ID
zurück. Wenn $name noch nicht existiert, dann wird eine neue ID generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte ID
zurückgeliefert.

=item get_subject_id($name)

Gibt in der Normdatenart Schlagwort die für die Ansetzungsform $name generierte ID
zurück. Wenn $name noch nicht existiert, dann wird eine neue ID generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte ID
zurückgeliefert.


=item get_classification_id($name)

Gibt in der Normdatenart Notation die für die Ansetzungsform $name generierte ID
zurück. Wenn $name noch nicht existiert, dann wird eine neue ID generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte ID
zurückgeliefert.

=item normalize($name)

Hilfsmethode, die fuer einen gegebenen Namen eine daraus abgeleitete eindeutige ID generiert

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
