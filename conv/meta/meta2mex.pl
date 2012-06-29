#!/usr/bin/perl

#####################################################################
#
#  meta2mex.pl
#
#  Copyright 2005 Oliver Flimm <flimm@openbib.org>
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

my $mexidn=1;

while (<>){
    if (/^0000:(\d+)/){
        $katkey = $1;
        $maxmex=0;
    }

    if (/^0016.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $standortbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
        }
    }
    
    if (/^0014\.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $signaturbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
        }
    }
    
    # Zeitschriftensignaturen USB Koeln
    
    if (/^1203\.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $signaturbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
        }
    }
    
    if (/^1204\.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $erschverlbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
       	    $maxmex=$zaehlung;
        }
    }
    
    if (/^3330\.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $besbibbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
            $maxmex=$zaehlung
        }
    }
    
    if (/^0005\.(\d\d\d):(.*$)/){
        $zaehlung = $1;
        $inhalt   = $2;
        $inventarbuf{$zaehlung}=$inhalt;
        if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
        }
    }

    if (/9999/){
        # Exemplardaten abarbeiten Anfang
        
        my $k=1;
        while ($k <= $maxmex) {
            
            $key=sprintf "%03d",$k;
            
            $signatur  = $signaturbuf {$key};
            $standort  = $standortbuf {$key};
            $inventar  = $inventarbuf {$key};
            $sigel     = $besbibbuf   {$key};
            $sigel     =~s!^38/!!;
            $erschverl = $erschverlbuf{$key};
            
            
            $mexbuffer[$mexidx++]="0000:".$mexidn;
            $mexbuffer[$mexidx++]="0004:".$katkey;
            $mexbuffer[$mexidx++]="0005:".$inventar if ($inventar);
            $mexbuffer[$mexidx++]="0014:".$signatur if ($signatur);
            $mexbuffer[$mexidx++]="0016:".$standort if ($standort);
            $mexbuffer[$mexidx++]="1204:".$erschverl if ($erschverl);
            $mexbuffer[$mexidx++]="3330:".$sigel if ($sigel);
            
            $mexbuffer[$mexidx++]="9999:\n";
            
            $mexidn++;
            $k++;
        }
        %inventarbuf=();
        %signaturbuf=();
        %standortbuf=();
        %besbibbuf=();
        %erschverlbuf=();
        undef $inventar;
        undef $maxmex;
        undef $maxpos;
        undef $bandangvorl;
    }
    
}
      
&ausgabemexfile;

#######################################################################
########################################################################

sub ausgabemexfile {
  open(MEX,"| gzip > unload.MEX.gz");
  $i=0;
  while ($i < $#mexbuffer) {
    print MEX $mexbuffer[$i],"\n";
    $i++;
  }
  print MEX "ENDE\n";
  close(MEX);
}

