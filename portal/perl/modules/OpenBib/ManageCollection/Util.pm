#####################################################################
#
#  OpenBib::ManageCollection::Util
#
#  Dieses File ist (C) 2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ManageCollection::Util;

use strict;
use warnings;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub sgml2umlaut {
    my ($line)=@_;
  
    $line=~s/&uuml;/ü/g;
    $line=~s/&auml;/ä/g;
    $line=~s/&ouml;/ö/g;
    $line=~s/&Uuml;/Ü/g;
    $line=~s/&Auml;/Ä/g;
    $line=~s/&Ouml;/Ö/g;
    $line=~s/&szlig;/ß/g;
  
    $line=~s/\&Eacute\;/É/g;	
    $line=~s/\&Egrave\;/È/g;	
    $line=~s/\&Ecirc\;/Ê/g;	
    $line=~s/\&Aacute\;/Á/g;	
    $line=~s/\&Agrave\;/À/g;	
    $line=~s/\&Acirc\;/Â/g;	
    $line=~s/\&Oacute\;/Ó/g;	
    $line=~s/\&Ograve\;/Ò/g;	
    $line=~s/\&Ocirc\;/Ô/g;	
    $line=~s/\&Uacute\;/Ú/g;	
    $line=~s/\&Ugrave\;/Ù/g;	
    $line=~s/\&Ucirc\;/Û/g;	
    $line=~s/\&Iacute\;/Í/g;
    $line=~s/\&Igrave\;/Ì/g;	
    $line=~s/\&Icirc\;/Î/g;	
    $line=~s/\&Ntilde\;/Ñ/g;	
    $line=~s/\&Otilde\;/Õ/g;	
    $line=~s/\&Atilde\;/Ã/g;	
  
    $line=~s/\&eacute\;/é/g;	
    $line=~s/\&egrave\;/è/g;	
    $line=~s/\&ecirc\;/ê/g;	
    $line=~s/\&aacute\;/á/g;	
    $line=~s/\&agrave\;/à/g;	
    $line=~s/\&acirc\;/â/g;	
    $line=~s/\&oacute\;/ó/g;	
    $line=~s/\&ograve\;/ò/g;	
    $line=~s/\&ocirc\;/ô/g;	
    $line=~s/\&uacute\;/ú/g;	
    $line=~s/\&ugrave\;/ù/g;	
    $line=~s/\&ucirc\;/û/g;	
    $line=~s/\&iacute\;/í/g;
    $line=~s/\&igrave\;/ì/g;	
    $line=~s/\&icirc\;/î/g;	
    $line=~s/\&ntilde\;/ñ/g;	
    $line=~s/\&otilde\;/õ/g;	
    $line=~s/\&atilde\;/ã/g;	
  
    $line=~s/<.?strong>//g;
    return $line;		# 
}

sub titset_to_text {
    my ($normset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    foreach my $item_ref (@$normset_ref) {
        $item_ref->{desc}     = sgml2umlaut($item_ref->{desc});
        $item_ref->{contents} = sgml2umlaut($item_ref->{contents});
        while (length($item_ref->{desc}) < 24) {
            $item_ref->{desc}.=" ";
        }
    }

    return $normset_ref;
}

sub titset_to_endnote {
    my ($normset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %endnote=(
        'Verfasser'   => '%A',    # Author 
        'Urheber'     => '%C',    # Corporate Author
        'HST'         => '%T',    # Title of the article or book
        '1'           => '%S',    # Title of the serie
        '2'           => '%J',    # Journal containing the article
        '3'           => '%B',    # Journal Title (refer: Book containing article)
        '4'           => '%R',    # Report, paper, or thesis type
        '5'           => '%V',    # Volume 
        '6'           => '%N',    # Number with volume
        '7'           => '%E',    # Editor of book containing article
        '8'           => '%P',    # Page number(s)
        'Verlag'      => '%I',    # Issuer. This is the publisher
        'Verlagsort'  => '%C',    # City where published. This is the publishers address
        'Ersch. Jahr' => '%D',    # Date of publication
        '11'          => '%O',    # Other information which is printed after the reference
        '12'          => '%K',    # Keywords used by refer to help locate the reference
        '13'          => '%L',    # Label used to number references when the -k flag of refer is used
        '14'          => '%X',    # Abstract. This is not normally printed in a reference
        '15'          => '%W',    # Where the item can be found (physical location of item)
        'Kollation'   => '%Z',    # Pages in the entire document. Tib reserves this for special use
        'Ausgabe'     => '%7',    # Edition
        '17'          => '%Y',    # Series Editor
    );

    my @tempset=();
    foreach my $item_ref (@$normset_ref) {
        if (exists $endnote{$item_ref->{desc}}) {
            $item_ref->{desc}     = $endnote{$item_ref->{desc}};
            $item_ref->{contents} = sgml2umlaut($item_ref->{contents});
            push @tempset, $item_ref;
        }
    }

    return \@tempset;
}

1;
