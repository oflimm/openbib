#####################################################################
#
#  OpenBib::ResultLists::Util
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ResultLists::Util;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);

use Log::Log4perl qw(get_logger :levels);

use POSIX();

use Digest::MD5();
use DBI;

use OpenBib::Config;

use Template;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub by_yearofpub {
  my $line1=0;
  my $line2=0;

  ($line1)=$a=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;
  ($line2)=$b=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;

  $line1=0 if ($line1 eq "");
  $line2=0 if ($line2 eq "");

  $line1 <=> $line2;
}

sub by_yearofpub_down {
  my $line1=0;
  my $line2=0;

  ($line1)=$a=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;
  ($line2)=$b=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;

  $line1=0 if ($line1 eq "");
  $line2=0 if ($line2 eq "");

  $line2 <=> $line1;
}


sub by_publisher {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlpublisher.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlpublisher.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_publisher_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlpublisher.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlpublisher.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_signature {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlsignature.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlsignature.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_signature_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlsignature.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlsignature.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_author {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlauthor.>(.*?)</span>!;
  ($line2)=$b=~m!<span id=.rlauthor.>(.*?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_author_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlauthor.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlauthor.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_title {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rltitle.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rltitle.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_title_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rltitle.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rltitle.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub sort_buffer {
  my ($sorttype,$sortorder,$routputbuffer,$rsortedoutputbuffer)=@_;

  if ($sorttype eq "author" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_author @$routputbuffer;
  }
  elsif ($sorttype eq "author" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_author_down @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_yearofpub @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_yearofpub_down @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_publisher @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_publisher_down @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_signature @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_signature_down @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_title @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_title_down @$routputbuffer;
  }
  else {
    @$rsortedoutputbuffer=@$routputbuffer;
  }

  return;
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

1;
