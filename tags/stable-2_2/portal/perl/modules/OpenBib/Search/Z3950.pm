#####################################################################
#
#  OpenBib::Search::Z3950
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

package OpenBib::Search::Z3950;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

# Hier folgen alle verfuegbaren Z3950-Module. Der letzte Teil des
# Methoden-Namens gibt den Datenbanknamen dieses Kataloges in
# der Web-Administration an
use OpenBib::Search::Z3950::USBK;

# Dispatcher-Methode
sub new {
    my ($class,$subclassname) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $subclassname = "OpenBib::Search::Z3950::$subclassname";
    my $subclass = "$subclassname"->new();
    
    return $subclass ;
}

sub to_openbib_list {
    my ($self,$resultstring)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->mab2openbib_list($resultstring);
}

sub to_openbib_full {
    my ($self,$resultstring)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->mab2openbib_full($resultstring);
}

sub mab2openbib_list {
    my ($self,$resultstring)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $listitem_ref = {};
    
    my $config = OpenBib::Config->instance;

    my $convtab_ref = (exists $config->{convtab}{singlepool})?
        $config->{convtab}{singlepool}:$config->{convtab}{default};

    my @record=split("",$resultstring);

    my @autkor = ();

    # id des Satzes bestimmen. Die id ist die letzte Zahl im
    # Header des MAB-Satzes
    ($listitem_ref->{id}) = $record[0] =~m/\s+(\d+)$/;

    $logger->debug("Header-Line: $record[0]");
    
    # Bei der Auswertung der einzelnen Kategorien wird die
    # Header-Zeile uebersprungen
  CATLINE:
    for (my $i=1;$i<$#record;$i++){
        my $line = $record[$i];

        $logger->debug("Line: $line");

        if (length($line) > 5){
            next CATLINE unless ($line=~/^\d\d\d/);
            my $category  = sprintf "%04d", substr($line,0,3);
            my $indicator = substr($line,3,1);
            my $content   = Encode::decode('MAB2',substr($line,4,length($line)-4));

            # Content filtern
            $content=~s/^\s*\|//;
            $content=~s/>/&gt;/g;
            $content=~s/</&lt;/g;

            $logger->debug("Category: $category\nContent: $content\n\n");
            if ($category && $content){
                
                next CATLINE if (exists $convtab_ref->{blacklist_ref}->{$category});
                
                if (exists $convtab_ref->{listitemcat}{$category}){
                    push @{$listitem_ref->{"T".$category}}, {
                        indicator => $indicator,
                        content   => $content,
                    };    
                };

                $listitem_ref->{database}     = "USBK";

                if ($category=~m/^0100/){
                    push @{$listitem_ref->{P0100}}, {
                        type    => 'aut',
                        content => $content,
                    };

                    push @autkor, $content;
                }
                elsif ($category=~m/^0101/){
                    push @{$listitem_ref->{P0101}}, {
                        type       => 'aut',
                        content    => $content,
                    };

                    push @autkor, $content;
                }
                elsif ($category=~m/^0103/){
                    push @{$listitem_ref->{P0103}}, {
                        type       => 'aut',
                        content    => $content,
                    };
                    push @autkor, $content;
                }
                elsif ($category=~m/^0200/){
                    push @{$listitem_ref->{C0200}}, {
                        type       => 'kor',
                        content    => $content,
                    };
                    
                    push @autkor, $content;
                }
                elsif ($category=~m/^0201/){
                    push @{$listitem_ref->{C0201}}, {
                        type       => 'kor',
                        content    => $content,
                    };
                    push @autkor, $content;
                }
                elsif ($category=~m/^0544/){
                    push @{$listitem_ref->{X0014}}, {
                        content    => $content,
                    };
                }
            }
        }
    }
    
    # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung

    if (@autkor){
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
    }
    
    $logger->debug("Item ".YAML::Dump($listitem_ref));
    return $listitem_ref;
}

sub mab2openbib_full {
    my ($self,$resultstring)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $listitem_ref    = {};
    my $mexlistitem_ref = [];
    
    my $targetdbinfo_ref =  $config->get_targetdbinfo();
    
    my $convtab_ref = (exists $config->{convtab}{singlepool})?
        $config->{convtab}{singlepool}:$config->{convtab}{default};

    my @record=split("",$resultstring);

    my @autkor = ();

    # id des Satzes bestimmen. Die id ist die letzte Zahl im
    # Header des MAB-Satzes
    ($listitem_ref->{id}) = $record[0] =~m/\s+(\d+)$/;

    $logger->debug("Header-Line: $record[0]");
    # Bei der Auswertung der einzelnen Kategorien wird die
    # Header-Zeile uebersprungen
  CATLINE:
    for (my $i=1;$i<$#record;$i++){
        my $line = $record[$i];

        $logger->debug("Line: $line");

        if (length($line) > 5){
            next CATLINE unless ($line=~/^\d\d\d/);
            my $category  = sprintf "%04d", substr($line,0,3);
            my $indicator = substr($line,3,1);
            my $content   = Encode::decode('MAB2',substr($line,4,length($line)-4));

            # Content filtern
            $content=~s/^\s*\|//;
            $content=~s/>/&gt;/g;
            $content=~s/</&lt;/g;
            
            $logger->debug("Category: $category\nContent: $content\n\n");
            if ($category && $content){
                
                next CATLINE if (exists $convtab_ref->{blacklist_ref}->{$category});
                
                push @{$listitem_ref->{"T".$category}}, {
                    indicator => $indicator,
                    content   => $content,
                };

                $listitem_ref->{database}     = "USBK";

                if ($category=~m/^0100/){
                    push @{$listitem_ref->{P0100}}, {
                        type    => 'aut',
                        content => $content,
                    };

                    push @autkor, $content;
                }
                elsif ($category=~m/^0101/){
                    push @{$listitem_ref->{P0101}}, {
                        type       => 'aut',
                        content    => $content,
                    };

                    push @autkor, $content;
                }
                elsif ($category=~m/^0103/){
                    push @{$listitem_ref->{P0103}}, {
                        type       => 'aut',
                        content    => $content,
                    };
                    push @autkor, $content;
                }
                elsif ($category=~m/^0200/){
                    push @{$listitem_ref->{C0200}}, {
                        type       => 'kor',
                        content    => $content,
                    };
                    
                    push @autkor, $content;
                }
                elsif ($category=~m/^0201/){
                    push @{$listitem_ref->{C0201}}, {
                        type       => 'kor',
                        content    => $content,
                    };
                    push @autkor, $content;
                }
                elsif ($category=~m/^0544/){
                    my $thismexlistitem_ref = {};

                    # Defaultwerte setzen
                    $thismexlistitem_ref->{X0005}{content}="-";
                    $thismexlistitem_ref->{X0014}{content}="-";
                    $thismexlistitem_ref->{X0016}{content}="-";
                    $thismexlistitem_ref->{X1204}{content}="-";
                    $thismexlistitem_ref->{X4000}{content}="-";
                    $thismexlistitem_ref->{X4001}{content}="";

                    # Katalogname ist USBK (hardcoded)
                    $thismexlistitem_ref->{X0014} = {
                        content => $content
                    }; 

                    # Es wird der Datenbankname zur Findung des Sigels herangezogen
                    my $sigel=$targetdbinfo_ref->{dbases}{"USBK"};
                    if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
                        $thismexlistitem_ref->{X4000}{content}=$targetdbinfo_ref->{sigel}{$sigel};
                    }
                    
                    my $bibinfourl="";
                    
                    # Bestimmung der Bibinfo-Url
                    if (exists $targetdbinfo_ref->{bibinfo}{$sigel}) {
                        $thismexlistitem_ref->{X4001}{content}=$targetdbinfo_ref->{bibinfo}{$sigel};
                    }

                    push @{$mexlistitem_ref}, $thismexlistitem_ref;
                }
            }
        }
    }
    
    # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung

    if (@autkor){
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
    }
    
    $logger->debug("Item ".YAML::Dump($listitem_ref));
    return ($listitem_ref,$mexlistitem_ref);
}

sub DESTROY {
    my $self = shift;

    if (defined $self->{conn}){
        $self->{conn}->destroy();
    }
    
    return;
}

1;

