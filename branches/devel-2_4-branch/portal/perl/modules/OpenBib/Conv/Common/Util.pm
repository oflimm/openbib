#####################################################################
#
#  OpenBib::Conv::Common::Util
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();

sub id2int {
    my ($id)=@_;

    $id=lc($id);
    $id=~s/\W//g;

    my $bin = "";
    
    foreach my $item (reverse split(//,$id)){
        my $part=(ord($item) >= 48 && ord($item) <= 57)?ord($item)-48:ord($item)-87;
        my ($binpart) = unpack("B32", pack("N", $part))=~/(\d\d\d\d\d\d)$/;;
        $bin ="$binpart$bin";
    }

    return $bin;
    return unpack("N", pack("B32", substr("0" x 32 . $bin, -32)));
}

sub get_autidn {
    my ($autans)=@_;

    my $autdubidx=1;
    my $autdubidn=0;

    while ($autdubidx <= $#autdubbuf){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdubidx]=$autans;
        $autdubidn=$autdubidx;
    }

    return $autdubidn;
}

sub get_swtidn {
    my ($swtans)=@_;

    my $swtdubidx=1;
    my $swtdubidn=0;

    while ($swtdubidx <= $#swtdubbuf){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdubidx]=$swtans;
        $swtdubidn=$swtdubidx;
    }

    return $swtdubidn;
}

sub get_koridn {
    my ($korans)=@_;
    
    my $kordubidx=1;
    my $kordubidn=0;
    
    while ($kordubidx <= $#kordubbuf){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordubidx]=$korans;
        $kordubidn=$kordubidx;
    }
    
    return $kordubidn;
}

sub get_notidn {
    my ($notans)=@_;
    
    my $notdubidx=1;
    my $notdubidn=0;
    
    while ($notdubidx <= $#notdubbuf){
        if ($notans eq $notdubbuf[$notdubidx]){
            $notdubidn=(-1)*$notdubidx;
        }
        $notdubidx++;
    }
    if (!$notdubidn){
        $notdubbuf[$notdubidx]=$notans;
        $notdubidn=$notdubidx;
    }
    
    return $notdubidn;
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

 my $id="urn:nbn:de:hbz:38-13363";

 print "Katkey: ",id2int($id),"\n";

=head1 METHODS

=over 4

=item id2int

Wandelt einen String-Identifier eindeutig einem Integer-Wert zu, der
intern zur Referenzierung genutzt werden kann. Dazu wird ein einfacher
Block-Code verwendet. Zunaechst erfolgt jedoch eine Normierung auf
ASCII-Kleinbuchstaben und Zahlen. Alle anderen Zeichen werden
entfernt. Diesen Zeichen werden dann binäre 6-bit Repräsentationen
zugeordnet. Diese binären Repräsentationen werden dann entsprechend
der Gesamtzeichenkette zu einer Gesamt-Binärzahl
zusammengefasst. Diese wird dann als Integer interpretiert.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
