#!/usr/bin/perl

#####################################################################
#
#  db2xapian.pl
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

use strict;
use warnings;
use utf8;

use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Search::Xapian;
use String::Tokenizer;
use OpenBib::Config;

use vars qw(%config);

*config = \%OpenBib::Config::config;

my $database=$ARGV[0];

my $dbh
    = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
    or die "$DBI::errstr";


my $dbbasedir=$config{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
if (! -d "$thisdbpath"){
    mkdir "$thisdbpath";
}

print "Building Index for Database $database\n";

my $db = Search::Xapian::WritableDatabase->new( $thisdbpath, Search::Xapian::DB_CREATE_OR_OPEN ) || die "Couldn't open/create Xapian DB $!\n";

# my $stopword_ref={};

# my @stopwordfiles=(
# 		  '/usr/db/ft/wortlisten/top1000de.txt',
# 		  '/usr/db/ft/wortlisten/top1000en.txt',
# 		  '/usr/db/ft/wortlisten/top1000fr.txt',
# 		  '/usr/db/ft/wortlisten/top1000nl.txt',
# 		 );

# foreach my $stopwordfile (@stopwordfiles){
#     open(SW,$stopwordfile);
#     while (<SW>){
#         chomp;
#         $stopword_ref->{$_}=1;
#     }
#     close(SW);
# }

my $tokenizer = String::Tokenizer->new();

my $request=$dbh->prepare("select b.id, a.verf, a.hst, a.kor, a.swt, a.notation, a.sign, a.ejahr, a.isbn, a.issn, b.listitem from search as a, titlistitem b where a.verwidn=b.id");
$request->execute();

my $count=1;
while (my $res=$request->fetchrow_hashref){
    my $id       = decode_utf8($res->{id});
    my $listitem = decode_utf8($res->{listitem});
    my $verf     = lc(decode_utf8($res->{verf}));
    my $hst      = lc(decode_utf8($res->{hst}));
    my $kor      = lc(decode_utf8($res->{kor}));
    my $swt      = lc(decode_utf8($res->{swt}));
    my $notation = lc(decode_utf8($res->{notation}));
    my $ejahr    = lc(decode_utf8($res->{ejahr}));
    my $sign     = lc(decode_utf8($res->{sign}));
    my $isbn     = lc(decode_utf8($res->{isbn}));
    my $issn     = lc(decode_utf8($res->{issn}));

    print "$count sets indexed\n" if ($count % 1000 == 0);

    my $tokinfos_ref=[
        {
            prefix  => "X1",
            content => $verf,
        },
        {
            prefix  => "X2",
            content => $hst,
        },
        {
            prefix  => "X3",
            content => $kor,
        },
        {
            prefix  => "X4",
            content => $swt,
        },
        {
            prefix  => "X5",
            content => $notation,
        },
        {
            prefix  => "X6",
            content => $sign,
        },
        {
            prefix  => "X7",
            content => $ejahr,
        },
        {
            prefix  => "X8",
            content => $isbn,
        },
        {
            prefix  => "X9",
            content => $issn,
        },
        
    ];
    
    my $doc=Search::Xapian::Document->new();
    
    foreach my $tokinfo_ref (@$tokinfos_ref){
        # Tokenize
        next if (! $tokinfo_ref->{content});
        
        $tokenizer->tokenize($tokinfo_ref->{content});
        
        my $i = $tokenizer->iterator();
        while ($i->hasNextToken()) {
            my $next = $i->nextToken();
            next if (!$next);
            next if (length($next) < 3);
            #next if ($stopword_ref->{$next});

            # Token generell einfuegen
            $doc->add_term($next);

            # Token in Feld einfuegen            
            my $fieldtoken=$tokinfo_ref->{prefix}.$next;
            #print "$fieldtoken\n";
            $doc->add_term($fieldtoken);
        }
    }
    
    $doc->set_data(encode_utf8($listitem));
    
    $db->add_document($doc);

    $count++;
}
