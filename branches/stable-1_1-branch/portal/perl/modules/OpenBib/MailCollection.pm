#####################################################################
#
#  OpenBib::MailCollection
#
#  Dieses File ist (C) 2001-2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::MailCollection;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;

use POSIX;

use Digest::MD5;
use DBI;
use Email::Valid;                           # EMail-Adressen testen
use MIME::Lite;                             # MIME-Mails verschicken

use OpenBib::Common::Util;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {

  my $r=shift;

  my $query=Apache::Request->new($r);

  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

  my %endnote=(
	       'Verfasser' => '%A', # Author 
	       'Urheber' => '%C', # Corporate Author
	       'HST' => '%T', # Title of the article or book
	       '1' => '%S', # Title of the serie
	       '2' => '%J', # Journal containing the article
	       '3' => '%B', # Journal Title (refer: Book containing article)
	       '4' => '%R', # Report, paper, or thesis type
	       '5' => '%V', # Volume 
	       '6' => '%N', # Number with volume
	       '7' => '%E', # Editor of book containing article
	       '8' => '%P', # Page number(s)
	       'Verlag' => '%I', # Issuer. This is the publisher
	       'Verlagsort' => '%C', # City where published. This is the publishers address
	       'Ersch. Jahr' => '%D', # Date of publication
	       '11' => '%O', # Other information which is printed after the reference
	       '12' => '%K', # Keywords used by refer to help locate the reference
	       '13' => '%L', # Label used to number references when the -k flag of refer is used
	       '14' => '%X', # Abstract. This is not normally printed in a reference
	       '15' => '%W', # Where the item can be found (physical location of item)
	       'Kollation' => '%Z', # Pages in the entire document. Tib reserves this for special use
	       'Ausgabe' => '%7', # Edition 
	       '17' => '%Y' # Series Editor 
	       );

  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen

  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
  my $sessionID=$query->param('sessionID');
  my $email=($query->param('email'))?$query->param('email'):'';
  my $subject=($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
#my $subject=$query->param('subject');
  my $singleidn=$query->param('singleidn');
  my $mail=$query->param('mail');
  my $database=$query->param('database');
  my $type=$query->param('type')||'HTML';
  
  # Haben wir eine authentifizierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
  # die Session nicht authentifiziert ist

  OpenBib::Common::Util::print_extended_header("KUG - K&ouml;lner Universit&auml;tsGesamtkatalog",$r);
  
  if ($email eq ""){
    print << "KEINEMAIL";
<table width="100%">
<tr><th>Fehlerbeschreibung</th></tr>
<tr><td class="boxedclear" style="font-size:12pt">
Sie haben keine Mailadresse eingegeben.
</td></tr>
</table>
<p />
KEINEMAIL
    OpenBib::Common::Util::print_footer();

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }

  unless (Email::Valid->address($email)) {
    print << "FALSCHEMAIL";
<table width="100%">
<tr><th>Fehlerbeschreibung</th></tr>
<tr><td class="boxedclear" style="font-size:12pt">
Sie haben eine ung&uuml;ltige Mailadresse eingegeben.
</td></tr>
</table>
<p />
FALSCHEMAIL
    OpenBib::Common::Util::print_footer();

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }	

  if ($singleidn){
    my $befehlsurl="http://$config{servername}$config{search_loc}";
    
    my $suchstring="sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&casesensitive=0&hitrange=-1&sorttype=author&database=$database&dbms=mysql&searchsingletit=$singleidn";
    
    my $gesamttreffer="";
    my $ua=new LWP::UserAgent;
      
    my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
    
    my $response=$ua->request($request);
    
    my $ergebnis=$response->content();

    my ($treffer)=$ergebnis=~/^(<!-- Title begins here -->.+?^<!-- Title ends here -->)/ms;
    
    # Herausfiltern der HTML-Tags der Titel
    
    $treffer=~s/<a .*?">//g;
    $treffer=~s/<.a>//g;
    $treffer=~s/<span .*?>G<.span>//g;
    $treffer=~s/<td>&nbsp;/<td>/g;
      
      
    if ($type eq "Text"){
      my @titelbuf=();
	
      # Treffer muss in Text umgewandelt werden
	
      $treffer=~s/^<.*?>$//g;
      $treffer=~s/&lt;/</g;
      $treffer=~s/&gt;/>/g;
	
      my @trefferbuf=split("\n",$treffer);
      my $i=0;
      my $j=1;
      while ($i < $#trefferbuf){
	  
        # Titelinformationen
	  
        if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
          my $kategorie=$1;
          my $inhalt=$2;
	    
          $kategorie=~s/<.+?>//g;
          $inhalt=~s/<.+?>//g;
          while (length($kategorie) < 24){
            $kategorie.=" ";
          }
          push @titelbuf, "$kategorie: $inhalt";
        }
        
        # Bestandsinformationen
	  
        elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){
	    
          my $bibliothek=$1;
          my $standort=$2;
          my $invnr=$3;
          my $signatur=$4;
          my $erschverl=$5;
	    
          $bibliothek=~s/<.+?>//g;
          $standort=~s/<.+?>//g;
          $invnr=~s/<.+?>//g;
          $signatur=~s/<.+?>//g;
          $erschverl=~s/<.+?>//g;
          my $bestandsinfo= << "ENDE";
Besitzende Bibliothek $j : $bibliothek
Standort              $j : $standort
Inventarnummer        $j : $invnr
Lokale Signatur       $j : $signatur
Erscheinungsverlauf   $j : $erschverl
ENDE
          push @titelbuf, $bestandsinfo;
          $j++;
        }
        
        $i++;
      } 
	
      $treffer=join ("\n", @titelbuf);
      $gesamttreffer.="------------------------------------------\n$treffer";
    }
    elsif ($type eq "EndNote"){
      # Treffer muss in Text umgewandelt werden
	
      my @titelbuf=();
	
      $treffer=~s/^<.*?>$//g;
      $treffer=~s/&lt;/</g;
      $treffer=~s/&gt;/>/g;
      
      my @trefferbuf=split("\n",$treffer);
      my $i=0;
      my $j=1;
      while ($i < $#trefferbuf){
	  
        # Titelinformationen
	  
        if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
          my $kategorie=$1;
          my $inhalt=$2;
	    
          $kategorie=~s/<.+?>//g;
          $inhalt=~s/<.+?>//g;

          if (defined($endnote{$kategorie})){
            push @titelbuf, $endnote{$kategorie}." $inhalt";
          }

        }
	  
        # Bestandsinformationen
	  
        elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){
	    
          my $bibliothek=$1;
          my $standort=$2;
          my $invnr=$3;
          my $signatur=$4;
          my $erschverl=$5;
	    
          $bibliothek=~s/<.+?>//g;
          $standort=~s/<.+?>//g;
          $invnr=~s/<.+?>//g;
          $signatur=~s/<.+?>//g;
          $erschverl=~s/<.+?>//g;
          my $bestandsinfo="%W $bibliothek / $standort / $signatur / $erschverl";
          push @titelbuf, $bestandsinfo;
          $j++;
        }
	  
        $i++;
      } 
	
      $treffer=join ("\n", @titelbuf);
      $gesamttreffer.="\n\n$treffer";
    }
    else {
      $gesamttreffer.="<hr>\n$treffer";
    }


    my $stylesheet=get_css_by_browsertype($r);

    my $htmlpre= << "HTMLPRE";
<HTML>
<HEAD>
  <meta http-equiv="pragma" content="no-cache">
  $stylesheet
  <TITLE>Zugemailte Merkliste</TITLE>
</HEAD>
<BODY>

<h1>Zugemailte Merkliste</h1>
HTMLPRE

    my $htmlpost= << "HTMLPOST";
</BODY>
</HTML>
HTMLPOST

    my $mimetype="text/html";
    my $filename="kug-merkliste";

    if ($type ne "HTML"){
      $htmlpre="";
      $htmlpost="";
      $mimetype="text/plain";
      $filename.=".txt";
    }
    else {
      $filename.=".html";
    }

    my $anschreiben = << "ANSCHREIBEN";
Sehr geehrte Damen und Herren,

anbei Ihre Merkliste aus dem KUG.

Mit freundlichen Grüßen

Ihr KUG Team
ANSCHREIBEN

    my $msg = MIME::Lite->new(
			      From            => $config{contact_email},
			      To              => $email,
			      Subject         => $subject,
			      Type            => 'multipart/mixed'
			     );


    $msg->attach(
		 Type            => 'TEXT',
		 Encoding        => '8bit',
		 Data            => $anschreiben
		);

    $msg->attach(
		 Type            => $mimetype,
		 Encoding        => '8bit',
                 Filename        => $filename,
		 Data            => $htmlpre.$gesamttreffer.$htmlpost,
		);

    $msg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config{contact_email}")
  }
  else {
    my $befehlsurl="http://$config{servername}$config{search_loc}";
  
    # Schleife ueber alle Treffer

    my $idnresult="";
  
    if ($userid){
      $idnresult=$userdbh->prepare("select * from treffer where userid=$userid order by dbname");
      $idnresult->execute();
    }
    else {
      $idnresult=$sessiondbh->prepare("select * from treffer where sessionid='$sessionID' order by dbname");
      $idnresult->execute();
    }

    my $gesamttreffer="";
    my $ua=new LWP::UserAgent;
  
    while (my $result=$idnresult->fetchrow_hashref()){
      $database=$result->{'dbname'};
      $singleidn=$result->{'singleidn'};
    
      my $suchstring="sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&casesensitive=0&hitrange=-1&sorttype=author&database=$database&dbms=mysql&searchsingletit=$singleidn";
    
    
      my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
    
      my $response=$ua->request($request);
    
      my $ergebnis=$response->content();
    
      my ($treffer)=$ergebnis=~/^(<!-- Title begins here -->.+?^<!-- Title ends here -->)/ms;
    
      # Herausfiltern der HTML-Tags der Titel


      $treffer=~s/<a .*?">//g;
      $treffer=~s/<.a>//g;
      $treffer=~s/<span .*?>G<.span>//g;
      $treffer=~s/<td>&nbsp;/<td>/g;
      
      if ($type eq "Text"){
	
	my @titelbuf=();
	
	# Treffer muss in Text umgewandelt werden
	
	$treffer=~s/^<.*?>$//g;
	$treffer=~s/&lt;/</g;
	$treffer=~s/&gt;/>/g;
	
	my @trefferbuf=split("\n",$treffer);
	my $i=0;
	my $j=1;
	while ($i < $#trefferbuf){
	  
	  # Titelinformationen
	  
	  if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
	    my $kategorie=$1;
	    my $inhalt=$2;
	    
	    $kategorie=~s/<.+?>//g;
	    $inhalt=~s/<.+?>//g;
	    while (length($kategorie) < 24){
	      $kategorie.=" ";
	    }
	    push @titelbuf, "$kategorie: $inhalt";
	  }
	  
	  # Bestandsinformationen
	  
	  elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){
	    
	    my $bibliothek=$1;
	    my $standort=$2;
	    my $invnr=$3;
	    my $signatur=$4;
	    my $erschverl=$5;
	    
	    $bibliothek=~s/<.+?>//g;
	    $standort=~s/<.+?>//g;
	    $invnr=~s/<.+?>//g;
	    $signatur=~s/<.+?>//g;
	    $erschverl=~s/<.+?>//g;
	    my $bestandsinfo= << "ENDE";
Besitzende Bibliothek $j : $bibliothek
Standort              $j : $standort
Inventarnummer        $j : $invnr
Lokale Signatur       $j : $signatur
Erscheinungsverlauf   $j : $erschverl
ENDE
            push @titelbuf, $bestandsinfo;
	    $j++;
	  }
	  
	  $i++;
	} 
	
	$treffer=join ("\n", @titelbuf);
	$gesamttreffer.="------------------------------------------\n$treffer";
      }
      elsif ($type eq "EndNote"){
	# Treffer muss in Text umgewandelt werden
	
	my @titelbuf=();
	
	$treffer=~s/^<.*?>$//g;
	$treffer=~s/&lt;/</g;
	$treffer=~s/&gt;/>/g;
	
	my @trefferbuf=split("\n",$treffer);
	my $i=0;
	my $j=1;
	while ($i < $#trefferbuf){
	  
	  # Titelinformationen
	  
	  if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
	    my $kategorie=$1;
	    my $inhalt=$2;
	    
	    $kategorie=~s/<.+?>//g;
	    $inhalt=~s/<.+?>//g;
	    
	    if (defined($endnote{$kategorie})){
	      push @titelbuf, $endnote{$kategorie}." $inhalt";
	    }
	  }
	  
	  # Bestandsinformationen
	  
	  elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){
	    
	    my $bibliothek=$1;
	    my $standort=$2;
	    my $invnr=$3;
	    my $signatur=$4;
	    my $erschverl=$5;
	    
	    $bibliothek=~s/<.+?>//g;
	    $standort=~s/<.+?>//g;
	    $invnr=~s/<.+?>//g;
	    $signatur=~s/<.+?>//g;
	    $erschverl=~s/<.+?>//g;
	    my $bestandsinfo="%W $bibliothek / $standort / $signatur / $erschverl";
	    push @titelbuf, $bestandsinfo;
	    $j++;
	  }
	  
	  $i++;
	} 
	
	$treffer=join ("\n", @titelbuf);
	$gesamttreffer.="\n\n$treffer";
      }
      else {
	$gesamttreffer.="<hr>\n$treffer";
      }
    }

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $htmlpre= << "HTMLPRE";
<HTML>
<HEAD>
  <meta http-equiv="pragma" content="no-cache">
  $stylesheet
  <TITLE>Zugemailte Merkliste</TITLE>
</HEAD>
<BODY>

<h1>Zugemailte Merkliste</h1>
HTMLPRE

    my $htmlpost= << "HTMLPOST";
</BODY>
</HTML>
HTMLPOST

    my $mimetype="text/html";
    my $filename="kug-merkliste";

    if ($type ne "HTML"){
      $htmlpre="";
      $htmlpost="";
      $mimetype="text/plain";
      $filename.=".txt";
    }
    else {
      $filename.=".html";
    }

    my $anschreiben = << "ANSCHREIBEN";
Sehr geehrte Damen und Herren,

anbei Ihre Merkliste aus dem KUG.

Mit freundlichen Grüßen

Ihr KUG Team
ANSCHREIBEN

    my $msg = MIME::Lite->new(
			      From            => $config{contact_email},
			      To              => $email,
			      Subject         => $subject,
			      Type            => 'multipart/mixed'
			     );


    $msg->attach(
		 Type            => 'TEXT',
		 Encoding        => '8bit',
		 Data            => $anschreiben
		);

    $msg->attach(
		 Type            => $mimetype,
		 Encoding        => '8bit',
                 Filename        => $filename,
		 Data            => $htmlpre.$gesamttreffer.$htmlpost,
		);

    $msg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config{contact_email}")
  }

  print << "ENDE6";
<table width="100%">
<tr><th>Erfolgreiche Aktion</th></tr>
<tr><td class="boxedclear" style="font-size:12pt">
Ihre Merkliste wurde an Sie per Mail versendet.
</td></tr>
</table>
<p />
ENDE6

  OpenBib::Common::Util::print_footer();

  $sessiondbh->disconnect();
  $userdbh->disconnect();

  return OK;
}

1;
