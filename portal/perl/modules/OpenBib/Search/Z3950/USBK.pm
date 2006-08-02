#####################################################################
#
#  OpenBib::Search::Z3950::USBK
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

package OpenBib::Search::Z3950::USBK;

use strict;
use warnings;
use lib '/usr/lib/perl5';

no warnings 'redefine';
use utf8;

use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use ZOOM;
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Search::Z3950::USBK::Config;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config %z39config);

*config    = \%OpenBib::Config::config;
*z39config = \%OpenBib::Search::Z3950::USBK::Config;

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    my $z39config = new OpenBib::Search::Z3950::USBK::Config();
    
    my $conn = new ZOOM::Connection($z39config->{hostname}, $z39config->{port},
                                    databaseName          => $z39config->{databaseName},
                                    user                  => $z39config->{user},
                                    password              => $z39config->{password},
                                    groupid               => $z39config->{groupid},
                                    preferredRecordSyntax => $z39config->{preferredRecordSyntax},
                                    querytype             => $z39config->{querytype},
                                ) or $logger->error_die("Connection Error:".$!);
    $self->{conn} = $conn;

    return $self;
}

sub search {
    my ($self,$searchquery_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $querystring = lc($searchquery_ref->{fs}{norm});

    my $resultset = $self->{conn}->search_pqf('@attr 1=4 '.$querystring) or $logger->error_die("Search Error: ".$self->{conn}->errmsg());

    $self->{rs} = $resultset;
}

sub get_resultlist {
    my ($self,$offset,$hitrange)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $start = $offset+1;
    my $end   = $offset+$hitrange;

    # Pre-Cache Results
    $self->{rs}->records($offset, $hitrange, 0);
    
    my @resultlist=();
    foreach my $i ($start..$end) {
        my $rec  = $self->{rs}->record($i-1);
        
        my $rrec = $rec->raw();

        push @resultlist, $self->mab2openbib($rrec);
    }

    $logger->debug(YAML::Dump(\@resultlist));

    return @resultlist;
}

sub get_singletitle {
    my ($self)=@_;
}

sub mab2openbib {
    my ($self,$resultstring)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $listitem_ref = {};
    
    my $config = new OpenBib::Config();

    my $convtab_ref = (exists $config->{convtab}{singlepool})?
        $config->{convtab}{singlepool}:$config->{convtab}{default};

    my @record=split("",$resultstring);

    my @autkor = ();
    
  CATLINE:
    for (my $i=0;$i<$#record;$i++){
        my $line = $record[$i];

        $logger->debug("Line: $line");

        if (length($line) > 5){
            next CATLINE unless ($line=~/^\d\d\d/);
            my $category  = sprintf "%04d", substr($line,0,3);
            my $indicator = substr($line,3,1);
            my $content   = decode_utf8(substr($line,4,length($line)-4));
#            my $content   = substr($line,4,length($line)-4);

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

                if ($category=~/0010/){
                    $listitem_ref->{id}       = $content;
                }
                elsif ($category=~m/^0100/){
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

sub DESTROY {
    my $self = shift;

    if (defined $self->{conn}){
        $self->{conn}->destroy();
    }
    
    return;
}

1;

