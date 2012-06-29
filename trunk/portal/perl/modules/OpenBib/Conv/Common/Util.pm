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

our (%autdubbuf,%kordubbuf,%swtdubbuf,%notdubbuf);
our (%person,%corporatebody,%subject,%classification);
our ($next_autid,$next_korid,$next_swtid,$next_notid) = (1,1,1,1);
our ($next_person_id,$next_corporatebody_id,$next_subject_id,$next_classification_id) = (1,1,1,1);

%autdubbuf = ();
%kordubbuf = ();
%swtdubbuf = ();
%notdubbuf = ();

%person         = ();
%corporatebody  = ();
%subject        = ();
%classification = ();

sub get_autidn {
    my ($content)=@_;

    if ($content=~/^\d+$/){
        if (exists $autdubbuf{$content}){
            return (-1)*$autdubbuf{$content};
        }
        else {
            $autdubbuf{$content}=$next_autid;
            $next_autid++;
            return $autdubbuf{$content};
        }
    }
    else {
        return $autdubbuf{$content};
    }   
                              
}

sub get_person_id {
    my ($content)=@_;

    my $new = 0;
    
    if (exists $person{$content}){

    }
    else {
        $person{$content}=$next_person_id;
        $next_person_id++;
        $new = 1;
    }

    return ($person{$content},$new);
}

sub set_person_id {
    my ($id,$content)=@_;

    $person{$content} = $id;

    return;
}

sub get_corporatebody_id {
    my ($content)=@_;

    my $new = 0;
    
    if (exists $corporatebody{$content}){

    }
    else {
        $corporatebody{$content}=$next_corporatebody_id;
        $next_corporatebody_id++;
        $new = 1;
    }

    return ($corporatebody{$content},$new);
}

sub set_corporatebody_id {
    my ($id,$content)=@_;

    $corporatebody{$content} = $id;

    return;
}

sub get_subject_id {
    my ($content)=@_;

    my $new = 0;
    
    if (exists $subject{$content}){

    }
    else {
        $subject{$content}=$next_subject_id;
        $next_subject_id++;
        $new = 1;
    }

    return ($subject{$content},$new);
}

sub set_subject_id {
    my ($id,$content)=@_;

    $subject{$content} = $id;

    return;
}

sub get_classification_id {
    my ($content)=@_;

    my $new = 0;
    
    if (exists $classification{$content}){

    }
    else {
        $classification{$content}=$next_classification_id;
        $next_classification_id++;
        $new = 1;
    }

    return ($classification{$content},$new);
}

sub set_classification_id {
    my ($id,$content)=@_;

    $classification{$content} = $id;

    return;
}


sub get_koridn {
    my ($content)=@_;

    if (exists $kordubbuf{$content}){
        return (-1)*$kordubbuf{$content};
    }
    else {
        $kordubbuf{$content}=$next_korid;
        $next_korid++;
        return $kordubbuf{$content};
    }
}

sub get_swtidn {
    my ($content)=@_;

    if (exists $swtdubbuf{$content}){
        return (-1)*$swtdubbuf{$content};
    }
    else {
        $swtdubbuf{$content}=$next_swtid;
        $next_swtid++;
        return $swtdubbuf{$content};
    }
}

sub get_notidn {
    my ($content)=@_;

    if (exists $notdubbuf{$content}){
        return (-1)*$notdubbuf{$content};
    }
    else {
        $notdubbuf{$content}=$next_notid;
        $next_notid++;
        return $notdubbuf{$content};
    }
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

 print OpenBib::Conv::Common::Util::get_autidn("Doe, John")

 => 1

 print OpenBib::Conv::Common::Util::get_autidn("Foo, Bar")

 => 2

 print OpenBib::Conv::Common::Util::get_autidn("Baz, Bar")

 => 3

 print OpenBib::Conv::Common::Util::get_autidn("Foo, Bar")

 => 2

=head1 METHODS

=over 4

=item get_autid($name)

Gibt in der Normdatenart Person die für die Ansetzungsform $name generierte numerische Identifikationsnummer
zurück. Wenn $name noch nicht existiert, dann wird eine neue Nummer generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte Nummer
zurückgeliefert.

=item kor_autid($name)

Gibt in der Normdatenart Körperschaft die für die Ansetzungsform $name generierte numerische Identifikationsnummer
zurück. Wenn $name noch nicht existiert, dann wird eine neue Nummer generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte Nummer
zurückgeliefert.

=item get_swtid($name)

Gibt in der Normdatenart Schlagwort die für die Ansetzungsform $name generierte numerische Identifikationsnummer
zurück. Wenn $name noch nicht existiert, dann wird eine neue Nummer generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte Nummer
zurückgeliefert.

=item get_notid($name)

Gibt in der Normdatenart Notation die für die Ansetzungsform $name generierte numerische Identifikationsnummer
zurück. Wenn $name noch nicht existiert, dann wird eine neue Nummer generiert und
zurückgeliefert. Wenn $name bereits existiert, dann wird die gespeicherte Nummer
zurückgeliefert.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
