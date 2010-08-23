#!/usr/bin/perl

#####################################################################
#
#  file2xapian.pl
#
#  Dieses File ist (C) 2007-2010 Oliver Flimm <flimm@openbib.org>
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

BEGIN {
    $ENV{XAPIAN_PREFER_FLINT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = '200000';
}

use Benchmark ':hireswallclock';
use DB_File;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use String::Tokenizer;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withfields,$withsorting,$withpositions);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "with-fields"     => \$withfields,
            "with-sorting"    => \$withsorting,
            "with-positions"  => \$withpositions,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2xapian.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

my $FLINT_BTREE_MAX_KEY_LEN = 240;
my $DRILLDOWN_MAX_KEY_LEN   = 100;

my %normdata                = ();

tie %normdata,                'MLDBM', "./normdata.db"
    or die "Could not tie normdata.\n";

$logger->info("### POOL $database");

my %xapian_idmapping;

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

open(SEARCH,      "<:utf8","search.mysql"      ) || die "SEARCH konnte nicht geoeffnet werden";
open(TITLISTITEM, "<:utf8","titlistitem.mysql" ) || die "TITLISTITEM konnte nicht geoeffnet werden";

my $dbbasedir=$config->{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
my $thistmpdbpath="$dbbasedir/$database.temp";

if (! -d "$thistmpdbpath"){
    mkdir "$thistmpdbpath";
}

$logger->info("Loeschung des alten temporaeren Index fuer Datenbank $database");

system("rm -f $thistmpdbpath/*");

$logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");

my $atime = new Benchmark;

{
    
    my $db = Search::Xapian::WritableDatabase->new( $thistmpdbpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";
    
    my $stopword_ref={};
    
    if (exists $config->{stopword_filename}){
        open(SW,$config->{stopword_filename});
        while (my $stopword=<SW>){
            chomp $stopword ;
            $stopword = OpenBib::Common::Util::grundform({
                content  => $stopword,
            });
            
            $stopword_ref->{$stopword}=1;
        }
        close(SW);
    }
    
    my $tokenizer = String::Tokenizer->new();
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;
    {
        my $atime = new Benchmark;
        while (my $search=<SEARCH>, my $titlistitem=<TITLISTITEM>) {
            my ($s_id,$verf,$hst,$kor,$swt,$notation,$sign,$ejahrint,$ejahr,$gtquelle,$inhalt,$isbn,$issn,$artinh)=split("",$search);
            my ($t_id,$listitem)=split ("",$titlistitem);
            if ($s_id ne $t_id) {
                $logger->fatal("Id's stimmen nicht ueberein ($s_id != $t_id)!");
                next;
            }
            
            #        next unless ($t_id == 243909);
            
            my $tokinfos_ref=[
                {
                    prefix  => "X1",
                    content => $verf,
                    type    => 'index',
                },
                {
                    prefix  => "X2",
                    content => $hst,
                    type    => 'index',
                },
                {
                    prefix  => "X3",
                    content => $kor,
                    type    => 'index',
                },
                {
                    prefix  => "X4",
                    content => $swt,
                    type    => 'index',
                },
                {
                    prefix  => "X5",
                    content => $notation,
                    type    => 'index',
                },
                {
                    prefix  => "X6",
                    content => $sign,
                    type    => 'index',
                },
                {
                    prefix  => "X7",
                    content => $ejahr,
                    type    => 'index',
                },
                {
                    prefix  => "X8",
                    content => $isbn,
                    type    => 'index',
                },
                {
                    prefix  => "X9",
                    content => $issn,
                    type    => 'index',
                },
                {
                    prefix  => "Y1",
                    content => $artinh,
                    type    => 'index',
                },
                {
                    prefix  => "Y2",
                    content => $inhalt,
                    type    => 'index',
                },
                {
                    # Schlagwort
                    prefix  => "D1",
                    type    => "drilldown",
                    cat     => 'swt',
                },
                {
                    # Notation
                    prefix  => "D2",
                    type    => "drilldown",
                    cat     => 'notation',
                },
                {
                    # Person
                    prefix  => "D3",
                    type    => "drilldown",
                    cat     => 'verf',
                },
                {
                    # Medientyp
                    prefix  => "D4",
                    type    => "drilldown",
                    cat     => 'mart',
                },
                {
                    # Jahr
                    prefix  => "D5",
                    type    => "drilldown",
                    cat     => 'year',
                },
                {
                    # Sprache
                    prefix  => "D6",
                    type    => "drilldown",
                    cat     => 'spr',
                },
                {
                    # Koerperschaft
                    prefix  => "D7",
                    type    => "drilldown",
                    cat     => 'kor',
                },
            ];
            
            my $seen_token_ref = {};
            
            my $doc=Search::Xapian::Document->new();
            
            # ID des Satzes recherchierbar machen
            $doc->add_term("Q".$s_id);
            
            # Katalogname des Satzes recherchierbar machen
            $doc->add_term("D8".$database);
            
            my $k = 0;
            
            foreach my $tokinfo_ref (@$tokinfos_ref) {
                
                if ($tokinfo_ref->{type} eq 'index'){
                    # Tokenize
                    next if (! $tokinfo_ref->{content});
                    
                    $tokenizer->tokenize($tokinfo_ref->{content});
                    
                    my $i = $tokenizer->iterator();
                    
                    my @saved_tokens=();
                    while ($i->hasNextToken()) {
                        my $next = $i->nextToken();
                        
                        # Naechstes, wenn kein Token
                        next if (!$next);
                        # Naechstes, wenn keine Zahl oder einstellig
                        # next if (length($next) < 2 && $next !~ /\d/);
                        # Naechstes, wenn Stopwort
                        next if (exists $config->{stopword_filename} && exists $stopword_ref->{$next});
                        
                        # Begrenzung der keys auf FLINT_BTREE_MAX_KEY_LEN Zeichen
                        
                        my $next_octet = encode_utf8($next); 
                        $next=(length($next_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($next_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$next;
                        
                        # Wenn noch nicht gesehen, dann Term indexieren
                        if (!exists $seen_token_ref->{$next}){
                            # Token generell einfuegen
                            $doc->add_term($next);
                        }
                        
                        $seen_token_ref->{$next}=1;
                        
                        if ($withpositions){
                            $doc->add_posting($next,$k);
                            $k++;
                        }
                        
                        push @saved_tokens, $next;
                    }
                    
                    if ($withfields) {
                        foreach my $token (@saved_tokens) {
                            # Token in Feld einfuegen            
                            my $fieldtoken=$tokinfo_ref->{prefix}.$token;
                            
                            # Begrenzung der keys auf FLINT_BTREE_MAX_KEY_LEN=252 Zeichen
                            
                            my $fieldtoken_octet = encode_utf8($fieldtoken); 
                            $fieldtoken=(length($fieldtoken_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($fieldtoken_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$fieldtoken;
                            
                            $doc->add_term($fieldtoken);
                            
                            if ($withpositions){
                                $doc->add_posting($fieldtoken,$k);
                                $k++;
                            }
                            
                        }
                    }
                }
                elsif ($tokinfo_ref->{type} eq 'drilldown'){
                    next if (!exists $normdata{$s_id}->{$tokinfo_ref->{cat}});
                    
                    my %seen_terms = ();
                    my @unique_terms = grep { ! $seen_terms{$_} ++ } @{$normdata{$s_id}->{$tokinfo_ref->{cat}}}; 
                    
                    foreach my $unique_term (@unique_terms){
                        # Kategorie in Feld einfuegen            
                        my $field = OpenBib::Common::Util::grundform({
                            content   => $unique_term,
                            searchreq => 1,
                        });
                        
                        $field=~s/\W/_/g;
                        
                        $field="$tokinfo_ref->{prefix}$field";
                        
                        # Begrenzung der keys auf FLINT_BTREE_MAX_KEY_LEN Zeichen
                        if (length($field) > $DRILLDOWN_MAX_KEY_LEN){
                            $field=substr($field,0,$DRILLDOWN_MAX_KEY_LEN);
                        }
                        
                        $doc->add_term($field);
                    }
                }
            }
            
            my $value_type_ref = [
                {
                    # Schlagwort
                    id     => 1,
                    type   => 'swt',
                },
                {
                    # Notation
                    id   => 2,
                    type => 'notation',
                },
                {
                    # Person
                    id   => 3,
                    type => 'verf',
                },
                {
                    # Medientyp
                    id   => 4,
                    type => 'mart',
                },
                {
                    # Jahr
                    id   => 5,
                    type => 'year',
                },
                {
                    # Sprache
                    id   => 6,
                    type => 'spr',
                },
                {
                    # Koerperschaft
                    id   => 7,
                    type => 'kor',
                },
                {
                    # Katalog
                    id   => 8,
                    type => 'database',
                },
                
            ];
            
            foreach my $type_ref (@{$value_type_ref}){
                # Datenbankname
                $doc->add_value($type_ref->{id},encode_utf8($database)) if ($type_ref->{type} eq "database" && $database);
                
                next if (!exists $normdata{$s_id}->{$type_ref->{type}});
                
                my %seen_terms = ();
                my @unique_terms = grep { ! $seen_terms{$_} ++ } @{$normdata{$s_id}->{$type_ref->{type}}}; 
                
                my $multstring = join("\t",@unique_terms);
                
                $doc->add_value($type_ref->{id},encode_utf8($multstring)) if ($multstring);
            }
            
            if ($withsorting){
                my $sorting_ref = [
                    {
                        # Verfasser/Koepeschaft
                        id         => 20,
                        category   => 'PC0001',
                        type       => 'stringcategory',
                    },
                    {
                        # Titel
                        id         => 21,
                        category   => 'T0331',
                        type       => 'stringcategory',
                    },
                    {
                        # Zaehlung
                        id         => 22,
                        category   => 'T5100',
                        type       => 'integercategory',
                    },
                    {
                        # Jahr
                        id         => 23,
                        category   => 'T0425',
                        type       => 'integercategory',
                    },
                    {
                        # Verlag
                        id         => 24,
                        category   => 'T0412',
                        type       => 'stringcategory',
                    },
                    {
                        # Signatur
                        id         => 25,
                        category   => 'X0014',
                        type       => 'stringcategory',
                    },
                    {
                        # Popularitaet
                        id         => 26,
                        category   => 'popularity',
                        type       => 'integervalue',
                    },
                    
                ];
                
                my $titlistitem_raw = pack "H*", $listitem;
                my $titlistitem_ref = Storable::thaw($titlistitem_raw);
                
                #            $logger->debug(YAML::Dump($titlistitem_ref));
                
                foreach my $this_sorting_ref (@{$sorting_ref}){
                    
                    if ($this_sorting_ref->{type} eq "stringcategory"){
                        my $content = (exists $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content})?$titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}:"";
                        $content = OpenBib::Common::Util::grundform({
                            content   => $content,
                        });
                        
                        #                    $logger->debug("Adding $content as sortvalue");
                        
                        $doc->add_value($this_sorting_ref->{id},$content);
                    }
                    elsif ($this_sorting_ref->{type} eq "integercategory"){
                        my $content = 0;
                        if (exists $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}){
                            ($content) = $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}=~m/^(\d+)/;
                        }
                        $content = sprintf "%08d", $content;
                        #                    $logger->debug("Adding $content as sortvalue");
                        $doc->add_value($this_sorting_ref->{id},$content);
                    }
                    elsif ($this_sorting_ref->{type} eq "integervalue"){
                        my $content = 0 ;
                        if (exists $titlistitem_ref->{$this_sorting_ref->{category}}){
                            ($content) = $titlistitem_ref->{$this_sorting_ref->{category}}=~m/^(\d+)/;
                        }
                        $content = sprintf "%08d",$content;
                        #                    $logger->debug("Adding $content as sortvalue");
                        $doc->add_value($this_sorting_ref->{id},$content);
                    }
                }
            }
            
            $doc->set_data($listitem);
            
            my $docid=$db->add_document($doc);
            
            # Abspeichern des Mappings der SQL-ID zur Xapian-Doc-ID
            $xapian_idmapping{$s_id} = $docid;
            
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                $atime         = new Benchmark;
                $logger->info("$count Saetze indexiert in $resulttime Sekunden");
            }
            
            $count++;
        }
    }
    
}

$logger->info("Aktiviere temporaeren Suchindex");

if ($thisdbpath && $thistmpdbpath){
    system("rm $thisdbpath/* ; rmdir $thisdbpath ; mv  $thistmpdbpath $thisdbpath");
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

untie(%xapian_idmapping);

sub print_help {
    print << "ENDHELP";
file2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Aufbau von einzelnen Suchfeldern (nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
