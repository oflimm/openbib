#!/usr/bin/perl

open(PS,"/bin/ps -eao \"cmd pid rss\"|grep apache-perl |");

while(<PS>){
  my ($cmd,$pid,$rss)=$_=~m/^(.+) +(\d+) +(\d+)/;

  # Jeder Apache-Prozess mit mehr als 200 MB wird gekillt
  if ($rss > 200000){
     print STDERR "Big Apache-perl: Pid $pid RSS $rss\n";
     system("/bin/date ; /bin/kill $pid ; /bin/kill $pid ; sleep 5 ; /bin/kill -9 $pid ; /bin/kill -9 $pid");
  }
}


close(PS);
