#!/usr/bin/perl
#####################################################################
#
#  analyze_relevances.pl
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

use DBI;
use OpenBib::Config;

my $config=new OpenBib::Config();

# Verbindung zu SQL-Datenbanken herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd});

my $enrichmntdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd});

my $request=$statisticsdbh->prepare("select distinct isbn from relevances");

$request->execute();

# Bestimme Nutzungsinformationen fuer jede ISBN
while (my $result=$request->fetchrow_hashref){
    my $isbn = $result->{isbn};

    # Bestimme alle Nutzer, die diese ISBN ausgeliehen haben
    my $request=$statisticsdbh->prepare("select distinct id from relevances where isbn=?");
    $request->execute($isbn);

    my @ids=();
    while (my $result=$request->fetchrow_hashref){
        my $id = $result->{id};
        $id=~s/'//g;
        push @ids, "'$id'";
    }

    my $idstring=join(",",@ids);
    
    # Bestimme alle ISBNs, die diese Nutzer ausgeliehen haben und erzeuge
    # daraus ein Nutzungshistogramm

    my $request=$statisticsdbh->prepare("select isbn,content from relevances where isbn != ? and id in ($idstring)");
    $request->execute($isbn);

    my %isbnhist=();
    while (my $result=$request->fetchrow_hashref){
        my $isbn = $result->{isbn};
        my $hst  = $result->{content};
        if (!exists $isbnhist{$isbn}){
            $isbnhist{$isbn}={
                count => 0,
                hst   => $hst,
            };
        }
        $isbnhist{$isbn}{count}=$isbnhist{$isbn}{count}+1;
    }

    my @histo=();
    foreach my $isbn (keys %isbnhist){
        push @{$histo[$isbnhist{$isbn}{count}]}, {
            isbn => $isbn,
            hst  => $isbnhist{$isbn}{hst},
        };
    }

    # Es werden nur Titel mit einer Relevanz von >= 4 (Nutzern/Sessions)
    # beruecksichtigt
    if ($#histo >= 4){
        my $i=$#histo;

        my @references=();
        while ($i > 2){
            push @references, {
                references => $histo[$i],
                count      => $i,
            } if $histo[$i];
            last if ($#references > 5);
            $i--;
        }

        my $count=0;
        $i=0;
        # 5 References werden bestimmt
        my $request1=$enrichmntdbh->prepare('delete from normdata where category=? and isbn=?');
        my $request2=$enrichmntdbh->prepare('insert into normdata values (?,?,?,?,?)');

        $request1->execute(4000,$isbn);
        $request1->execute(4001,$isbn);
        foreach my $references_ref (@references){
            foreach my $item_ref (@{$references_ref->{references}}){
                $count++;
                next if (!$item_ref->{hst});
                
                $request2->execute($isbn,50,4000,$count,$item_ref->{isbn});
                $request2->execute($isbn,50,4001,$count,$item_ref->{hst});

                last if ($count > 5);
            }
        }       
    }
}
