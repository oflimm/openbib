#!/usr/bin/perl

#####################################################################
#
#  gen_zsstlist.pl
#
#  Extrahieren der Zeitschriftenliste eines Instituts
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

#####################################################################
# Einladen der benoetigten Perl-Module 
#####################################################################

use utf8;

use Getopt::Long;
use OpenBib::Config;
use OpenBib::Search::Util;
use OpenBib::Template::Provider;
use OpenBib::Common::Stopwords;

use DBI;
use Encode 'decode_utf8';
use Template;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$sigel,$showall,$mode);

&GetOptions(
	    "help"    => \$help,
	    "sigel=s" => \$sigel,
	    "mode=s"  => \$mode,
	    "showall" => \$showall,
	    );

if ($help){
    print_help();
}

if (!$mode){
  $mode="tex";
}


if ($mode ne "tex" && $mode ne "pdf"){
  print "Mode muss enweder tex oder pdf sein.\n";
  exit;
}

my $config = new OpenBib::Config();

my $targetdbinfo_ref = $config->get_targetdbinfo();

my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=instzs;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

my %titidns = ();

# IDN's der Exemplardaten und daran haengender Titel bestimmen

my $request=$dbh->prepare("select distinct id from mex where category=3300 and content=?") or $logger->error($DBI::errstr);

$request->execute($sigel) or $logger->error($DBI::errstr);;

while (my $result=$request->fetchrow_hashref()){
    $mexidns{$result->{'id'}}=1;
#    $titidns{$result->{'titidn'}}=1;
    #  print $result->{'titidn'};
}

{
    foreach my $mexid (keys %mexidns){
        my $reqstring="select distinct sourceid from conn where targetid= ? and sourcetype=1 and targettype=6";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($mexid) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $result=$request->fetchrow_hashref()){
            $titidns{$result->{'sourceid'}}=1;
        }
        $request->finish();
    }
}

my @titlist = ();

my $externzahl=0;

foreach $titidn (keys %titidns){

  my $normset_ref={};

  $normset_ref->{id      } = $titidn;
  $normset_ref->{database} = "instzs";


  # Titelkategorien
  {

      my $reqstring="select * from tit where id = ?";
      my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
      $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
      
      while (my $res=$request->fetchrow_hashref) {
          my $category  = "T".sprintf "%04d",$res->{category };
          my $indicator =        decode_utf8($res->{indicator});
          my $content   =        decode_utf8($res->{content  });
          
          push @{$normset_ref->{$category}}, {
              indicator => $indicator,
              content   => filterchars($content),
          };
      }
      $request->finish();
  }

  
  # Verknuepfte Normdaten
  {
      my $reqstring="select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)";
      my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
      $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
      
      while (my $res=$request->fetchrow_hashref) {
          my $category   = "T".sprintf "%04d",$res->{category };
          my $targetid   =        decode_utf8($res->{targetid  });
          my $targettype =                    $res->{targettype};
          my $supplement =        decode_utf8($res->{supplement});
          
          # Korrektes UTF-8 Encoding Flag wird in get_*_ans_*
          # vorgenommen
          
          my $content    =
              ($targettype == 2 )?OpenBib::Search::Util::get_aut_ans_by_idn($targetid,$dbh):
                  ($targettype == 3 )?OpenBib::Search::Util::get_kor_ans_by_idn($targetid,$dbh):
                      ($targettype == 4 )?OpenBib::Search::Util::get_swt_ans_by_idn($targetid,$dbh):
                          ($targettype == 5 )?OpenBib::Search::Util::get_not_ans_by_idn($targetid,$dbh):'Error';

          push @{$normset_ref->{$category}}, {
              id         => $targetid,
              content    => filterchars($content),
              supplement => filterchars($supplement),
          };
      }
      $request->finish();
      
  }

  my $is_extern=0;
  
  # Exemplardaten
  my @mexnormset=();
  {
      
      my $reqstring="select distinct targetid from conn where sourceid= ? and sourcetype=1 and targettype=6";
      my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
      $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
      
      my @verknmex=();
      while (my $res=$request->fetchrow_hashref){
          push @verknmex, decode_utf8($res->{targetid});
      }
      $request->finish();
      
      if ($#verknmex >= 0) {
          foreach my $mexsatz (@verknmex) {
              my $mexnormset_ref = OpenBib::Search::Util::get_mex_set_by_idn({
                  mexidn             => $mexsatz,
                  dbh                => $dbh,
                  targetdbinfo_ref   => $targetdbinfo_ref,
                  targetcircinfo_ref => $targetcircinfo_ref,
                  database           => $database,
                  sessionID          => $sessionID,
              });

              if (exists $mexnormset_ref->{X3300}{content}){
                  if ($mexnormset_ref->{X3300}{content} ne $sigel){
                      $is_extern=1;      
                  }
              }
              
              foreach my $category (keys %$mexnormset_ref){
                  if (exists $mexnormset_ref->{$category}{content}){
                      $mexnormset_ref->{$category}{content}=filterchars($mexnormset_ref->{$category}{content});
                  }
              }
              
              push @mexnormset, $mexnormset_ref;
          }
      }
      
  }

  if ($is_extern == 1){
      $externzahl++;
  }

  push @titlist, {
      titset => $normset_ref,
      mexset => \@mexnormset,
  };
  
  #  print YAML::Dump($normset_ref);
  
}

# Sortierung

my @sortedoutputbuffer=sort by_title @titlist;

#print STDERR YAML::Dump(\@sortedoutputbuffer);

my $outputbasename="zsstlist-$sigel";

if ($showall){
    $outputbasename.="-all";
}

my $template = Template->new({
    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    }) ],
    #        INCLUDE_PATH   => $config->{tt_include_path},
    #        ABSOLUTE       => 1,
    OUTPUT_PATH   => '/var/www/zsstlisten',
    OUTPUT        => "$outputbasename.$mode",
});


my $ttdata = {
    sigel        => $sigel,
    targetdbinfo => $targetdbinfo_ref,
    titlist      => \@sortedoutputbuffer,
    showall      => $showall,
    gesamtzahl   => $#titlist+1,
    externzahl   => $externzahl,
};

$template->process("zsstlist_$mode", $ttdata) || do { 
    print $template->error();
};

sub print_help {
    print "gen-zsstlist.pl - Erzeugen von Zeitschiftenlisten pro Sigel\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";
    print "  --sigel=514             : Sigel der Bibliothek\n";
    print "  --mode=[pdf|tex]        : Typ des Ausgabedokumentes\n";
    print "  -showall                : Alle Sigel/Eigentümer anzeigen\n\n";
    
    exit;
}

sub filterchars {
  my ($content)=@_;

  $content=~s/\$/\\\$/g;
  $content=~s/\&gt\;/\$>\$/g;
  $content=~s/\&lt\;/\$<\$/g;
  $content=~s/\{/\\\{/g;
  $content=~s/\}/\\\}/g;


  # Entfernen
  $content=~s/±//g;
  $content=~s/÷//g;
  $content=~s/·//g;
  $content=~s/×//g;
  $content=~s/¾//g;
  $content=~s/¬//g;
  $content=~s/¹//g;
  $content=~s/_//g;
  $content=~s/¸//g;
  $content=~s/þ//g;
  $content=~s/Ð//g;
  $content=~s/\^/\\\^\{\}/g;
  $content=~s/µ/\$µ\$/g;
  $content=~s/\&amp\;/\\&/g;
  $content=~s/\"/\'\'/g;
  $content=~s/\%/\\\%/g;

  # Umlaute
  $content=~s/\&uuml\;/ü/g;
  $content=~s/\&auml\;/ä/g;
  $content=~s/\&Auml\;/Ä/g;
  $content=~s/\&Uuml\;/Ü/g;
  $content=~s/\&ouml\;/ö/g;
  $content=~s/\&Ouml\;/Ö/g;
  $content=~s/\&szlig\;/ß/g;

  # Caron
  $content=~s/\&#353\;/\\v\{s\}/g; # s hacek
  $content=~s/\&#352\;/\\v\{S\}/g; # S hacek
  $content=~s/\&#269\;/\\v\{c\}/g; # c hacek
  $content=~s/\&#268\;/\\v\{C\}/g; # C hacek
  $content=~s/\&#271\;/\\v\{d\}/g; # d hacek
  $content=~s/\&#270\;/\\v\{D\}/g; # D hacek
  $content=~s/\&#283\;/\\v\{e\}/g; # d hacek
  $content=~s/\&#282\;/\\v\{E\}/g; # D hacek
  $content=~s/\&#318\;/\\v\{l\}/g; # l hacek
  $content=~s/\&#317\;/\\v\{L\}/g; # L hacek
  $content=~s/\&#328\;/\\v\{n\}/g; # n hacek
  $content=~s/\&#327\;/\\v\{N\}/g; # N hacek
  $content=~s/\&#345\;/\\v\{r\}/g; # r hacek
  $content=~s/\&#344\;/\\v\{R\}/g; # R hacek
  $content=~s/\&#357\;/\\v\{t\}/g; # t hacek
  $content=~s/\&#356\;/\\v\{T\}/g; # T hacek
  $content=~s/\&#382\;/\\v\{z\}/g; # n hacek
  $content=~s/\&#381\;/\\v\{Z\}/g; # N hacek

  # Macron
  $content=~s/\&#275\;/\\=\{e\}/g; # e oberstrich
  $content=~s/\&#274\;/\\=\{E\}/g; # e oberstrich
  $content=~s/\&#257\;/\\=\{a\}/g; # a oberstrich
  $content=~s/\&#256\;/\\=\{A\}/g; # A oberstrich
  $content=~s/\&#299\;/\\=\{i\}/g; # i oberstrich
  $content=~s/\&#298\;/\\=\{I\}/g; # I oberstrich
  $content=~s/\&#333\;/\\=\{o\}/g; # o oberstrich
  $content=~s/\&#332\;/\\=\{O\}/g; # O oberstrich
  $content=~s/\&#363\;/\\=\{u\}/g; # u oberstrich
  $content=~s/\&#362\;/\\=\{U\}/g; # U oberstrich

  $content=~s/#/\\#/g;
  
  return $content;
}

# sub by_signature {
#     my %line1=%$a;
#     my %line2=%$b;

#     # Sortierung anhand erster Signatur
#     my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"0";
#     my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"0";

#     $line1 cmp $line2;
# }

sub by_title {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{titset}{T0331}[0]{content} && defined $line1{titset}{T0331}[0]{content})?cleanrl($line1{titset}{T0331}[0]{content}):"";
    my $line2=(exists $line2{titset}{T0331}[0]{content} && defined $line2{titset}{T0331}[0]{content})?cleanrl($line2{titset}{T0331}[0]{content}):"";

    $line1=OpenBib::Common::Stopwords::strip_first_stopword($line1);
    $line2=OpenBib::Common::Stopwords::strip_first_stopword($line2);

    $line1 cmp $line2;
}

sub cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}
