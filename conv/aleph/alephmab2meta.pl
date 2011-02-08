#!/usr/bin/perl

#####################################################################
#
#  alephmab2meta.pl
#
#  Konvertierung von Aleph MAB2-Daten in das Meta-Format
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use Data::Dumper;
use YAML;

######################################################################
# Personen-Daten

my $perdefs_ref = {
    '001'  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002'  => {
        newcat => '0100', # SDN
        mut => 0,
    },
    '800' => {
        newcat => '0001', # Ansetzung
        mult => 0,
    },
    '820' => {
        newcat => '0102', # ansetzungsform nach einem weiteren regelwerk => verweisungsform
        mult => 1,
    },
    '830' => {
        newcat => '0102', # verweisungsform 
        mult => 1,
    },

};

print "Bearbeite Personen\n";

if (-e "tmp.PER"){
    open(PEROUT,'>:utf8','unload.PER');
    
    tie @mab2perdata, 'Tie::MAB2::Recno', file => "tmp.PER";
    
    foreach my $rawrec (@mab2perdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $perdefs_ref->{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$perdefs_ref->{$category}{mult}){
                $indicator="";
            }
            
            if (exists $perdefs_ref->{$category}{newcat}){
                $newcategory = $perdefs_ref->{$category}{newcat};
            }
            
            if ($newcategory && $perdefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print PEROUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print PEROUT "$newcategory:$content\n";
            }
        }
        print PEROUT "9999:\n\n";
    }
    
    close(PEROUT);
}
else {
    print STDERR "Keine Persoenendaten vorhanden\n";
}

######################################################################
# Koerperschafts-Daten

my $kordefs_ref = {
    '001'  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002'  => {
        newcat => '0100', # SDN
        mut => 0,
    },
    '800' => {
        newcat => '0001', # Ansetzung
        mult => 0,
    },
    '801' => {
        newcat => '0110', # Abkuerzung der Ansetzung
        mult => 0,
    },
    '810' => {            # 1. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '811' => {            # zusaetzliche angaben zur 1. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '812' => {            # 2. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '813' => {            # zusaetzliche angaben zur 2. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '814' => {            # 3. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '815' => {            # zusaetzliche angaben zur 3. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '816' => {            # 4. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '817' => {            # zusaetzliche angaben zur 4. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '818' => {            # 5. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '819' => {            # zusaetzliche angaben zur 5. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '820' => {            # 6. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '821' => {            # zusaetzliche angaben zur 6. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '822' => {            # 7. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '823' => {            # zusaetzliche angaben zur 7. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '824' => {            # 8. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '825' => {            # zusaetzliche angaben zur 8. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '826' => {            # 9. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '827' => {            # zusaetzliche angaben zur 9. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '828' => {            # 10. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '829' => {            # zusaetzliche angaben zur 10. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '830' => {            # 11. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '831' => {            # zusaetzliche angaben zur 11. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '832' => {            # 12. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '833' => {            # zusaetzliche angaben zur 12. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '834' => {            # 13. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '835' => {            # zusaetzliche angaben zur 13. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '836' => {            # 14. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '837' => {            # zusaetzliche angaben zur 14. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '838' => {            # 15. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '839' => {            # zusaetzliche angaben zur 15. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '840' => {            # 16. verweisungsform zum namen der koerperschaft
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '841' => {            # zusaetzliche angaben zur 16. verweisungsform
        newcat => '0102', # Verweisung
        mult => 1,
    },
    '850' => {            # 1. frueherer, zeitweiser oder spaeterer name der koerperschaft
        newcat => '0111', # Frueher/Spaeter
        mult => 1,
    },
    '853' => {            # 2. frueherer, zeitweiser oder spaeterer name der koerperschaft
        newcat => '0111', # Frueher/Spaeter
        mult => 1,
    },
    '856' => {            # 3. frueherer, zeitweiser oder spaeterer name der koerperschaft
        newcat => '0111', # Frueher/Spaeter
        mult => 1,
    },

};

print "Bearbeite Koerperschaften\n";

if (-e "tmp.KOE"){
    open(KOROUT,'>:utf8','unload.KOE');
    
    tie @mab2kordata, 'Tie::MAB2::Recno', file => "tmp.KOE";
    
    foreach my $rawrec (@mab2kordata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $kordefs_ref->{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$kordefs_ref->{$category}{mult}){
                $indicator="";
            }
            
            if (exists $kordefs_ref->{$category}{newcat}){
                $newcategory = $kordefs_ref->{$category}{newcat};
            }
            
            if ($newcategory && $kordefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print KOROUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print KOROUT "$newcategory:$content\n";
            }
        }
        print KOROUT "9999:\n\n";
    }
    
    close(KOROUT);
}
else {
    print "Keine Koerperschaftsdaten vorhanden\n";
}

######################################################################
# Schlagwort-Daten

my $swtdefs_ref = {
    '001'  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002'  => {
        newcat => '0100', # SDN
        mut    => 0,
    },
    '800' => {            # hauptschlagwort
        newcat => '0001', # Ansetzung
        mult   => 1,
    },
    '820' => {            # alternativform zum hauptschlagwort
        newcat => '0102', # verweisungsform 
        mult   => 1,
    },
    '830' => {            # aequivalente bezeichnung
        newcat => '0102', # verweisungsform 
        mult   => 1,
    },
    '850' => {            # uebergeordnetes schlagwort
        newcat => '0113', # uebergeordnet
        mult   => 1,
    },
    '860' => {            # verwandtes schlagwort
        newcat => '0113', # assoziiert
        mult   => 1,
    },
    '870' => {            # schlagwort fuer eine fruehere benennung
        newcat => '0117', # frueher
        mult   => 1,
    },
    '880' => {            # schlagwort fuer eine spaetere benennung
        newcat => '0119', # spaeter
        mult   => 1,
    },

};

print "Bearbeite Schlagworte\n";

if (-e "tmp.SWD"){
    open(SWTOUT,'>:utf8','unload.SWD');
    
    tie @mab2swtdata, 'Tie::MAB2::Recno', file => "tmp.SWD";
    
  SWTLOOP: foreach my $rawrec (@mab2swtdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #    print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $swtdefs_ref->{$category}){
                next;
            }
            
            # Vorabfilterung
            #        if ($category =~ /^001$/){
            #            $content=~s/\D//g;
            #            $content = sprintf "%d", $content;
            #            next SWTLOOP if ($content > 10000000);
            #        }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$swtdefs_ref->{$category}{mult}){
                $indicator="";
            }
            
            if (exists $swtdefs_ref->{$category}{newcat}){
                $newcategory = $swtdefs_ref->{$category}{newcat};
            }
            
            if ($newcategory && $swtdefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print SWTOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print SWTOUT "$newcategory:$content\n";
            }
        }
        print SWTOUT "9999:\n\n";
    }
    
    close(SWTOUT);
}
else {
    print "Keine Schlagwortdaten vorhanden\n";
}


######################################################################
# Systematik-Daten

my $notdefs_ref = {
    '001'  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002'  => {
        newcat => '0100', # SDN
        mut    => 0,
    },
    '800' => {            # hauptschlagwort
        newcat => '0001', # Ansetzung
        mult   => 0,
    },
    '820' => {            # alternativform zum hauptschlagwort
        newcat => '0102', # verweisungsform 
        mult   => 1,
    },
    '830' => {            # aequivalente bezeichnung
        newcat => '0102', # verweisungsform 
        mult   => 1,
    },
    '850' => {            # uebergeordnetes schlagwort
        newcat => '0113', # uebergeordnet
        mult   => 1,
    },
    '860' => {            # verwandtes schlagwort
        newcat => '0113', # assoziiert
        mult   => 1,
    },
    '870' => {            # schlagwort fuer eine fruehere benennung
        newcat => '0117', # frueher
        mult   => 1,
    },
    '880' => {            # schlagwort fuer eine spaetere benennung
        newcat => '0119', # spaeter
        mult   => 1,
    },

};


print "Bearbeite Systematik\n";

if (-e "tmp.SYS"){
    open(NOTOUT,'>:utf8','unload.SYS');

    tie @mab2notdata, 'Tie::MAB2::Recno', file => "tmp.SYS";
    
    foreach my $rawrec (@mab2notdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
            my $newcategory = "";
            
            if (!exists $notdefs_ref->{$category}){
                next;
            }
            
            # Vorabfilterung
            #         if ($category =~ /^001$/){
            #             $content=~s/\D//g;
            #         }
            
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }
            
            # Standard-Konvertierung mit perkonv
            
            if (!$notdefs_ref->{$category}{mult}){
                $indicator="";
            }
            
            if (exists $notdefs_ref->{$category}{newcat}){
                $newcategory = $notdefs_ref->{$category}{newcat};
            }
            
            if ($newcategory && $notdefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print NOTOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print NOTOUT "$newcategory:$content\n";
            }
        }
        print NOTOUT "9999:\n\n";
    }
    
    close(NOTOUT);
}
else {
    print STDERR "Keine Systemaitkdaten vorhanden\n";
}

######################################################################
# Titel-Daten

my $titdefs_ref = {
    '001 '  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002a'  => {
        newcat => '0002', # SDN
        mut    => 0,
    },
    '010'  => {           # identifikationsnummer des direkt uebergeordneten datensatzes
        newcat => '0004', # Uebergeordn. Satz
        mut    => 1,
    },
    '026 ' => {            # ZDBID
        newcat => '0572', # ZDBID
        mult   => 1,
    },
    '036a' => {            # Erschland
        newcat => '0035', # Erschland
        mult   => 1,
    },
    '037b'  => {           # Sprache
        newcat => '0015', # Sprache
        mut    => 1,
    },
    '089' => {            # bandangaben in vorlageform
        newcat => '0089', # bandangaben in vorlageform
        mult   => 1,
    },
    '310 ' => {            # ansetzungssachtitel
        newcat => '0310' , # ansetzungssachtitel
        mult   => 1,
    },    
    '331 ' => {            # hauptsachtitel in vorlageform oder mischform
        newcat => '0331', # hauptsachtitel in vorlageform oder mischform
        mult   => 1,
    },
    '333 ' => {            # Zu erg. URH
        newcat => '0333', # Zu erg. URH
        mult   => 1,
    },
    '335 ' => {            # zusaetze zum hauptsachtitel
        newcat => '0335', # zusaetze zum hauptsachtitel
        mult   => 1,
    },
    '359 ' => {            # Vorl. Verf/Koerp
        newcat => '0359', # Vorl. Verf/Koerp
        mult   => 1,
    },
    '370a' => {            # WST
        newcat => '0370', # WST
        mult   => 1,
    },
    '403' => {            # ausgabebezeichnung in vorlageform
        newcat => '0403', # ausgabebezeichnung in vorlageform
        mult   => 1,
    },
    '405 ' => {            # Erschverlauf
        newcat => '0405', # Erschverlauf
        mult   => 1,
    },
    '410 ' => {            # ort(e) des 1. verlegers, druckers usw.
        newcat => '0410', # ort(e) des 1. verlegers, druckers usw.
        mult   => 1,
    },
    '412 ' => {            # name des 1. verlegers, druckers usw.
        newcat => '0412', # name des 1. verlegers, druckers usw.
        mult   => 1,
    },
    '425c' => {            # erscheinungsjahr(e)
        newcat => '0425', # erscheinungsjahr(e)
        mult   => 1,
    },
    '433' => {            # umfangsangabe
        newcat => '0433', # umfangsangabe
        mult   => 1,
    },
    '451' => {            # 1. gesamttitel in vorlageform
        newcat => '0451', # 1. gesamttitel in vorlageform
        mult   => 1,
    },
    '507 ' => {            # Titelangaben
        newcat => '0507', # Titelangaben
        mult   => 1,
    },
    '523 ' => {            # Erscheinungsweise
        newcat => '0523', # Erscheinungsweise
        mult   => 1,
    },
    '527z' => {            # Parallele Ausg.
        newcat => '0527', # Parallele Ausg.
        mult   => 1,
    },
    '529z' => {            # Tit beilage
        newcat => '0529', # Tit beilage
        mult   => 1,
    },
    '530z' => {            # Bezugswerk
        newcat => '0530', # Bezugswerk
        mult   => 1,
    },
    '531z' => {            # FruehAusg.
        newcat => '0531', # FruehAusg.
        mult   => 1,
    },
    '532z' => {            # FruehTit.
        newcat => '0532', # FruehTit.
        mult   => 1,
    },
    '533z' => {            # SpaetAusg.
        newcat => '0533', # SpaetAusg.
        mult   => 1,
    },
    '534' => {            # Titelkonk.
        newcat => '0534', # Titelkonk.
        mult   => 1,
    },
    '540' => {            # internationale standardbuchnummer (isbn)
        newcat => '0540', # internationale standardbuchnummer (isbn)
        mult   => 1,
    },
    '542a' => {            # ISSN
        newcat => '0543', # ISSN
        mult   => 1,
    },
    
#     '710' => {            # schlagwoerter und schlagwortketten
#         newcat => '0710', # schlagwoerter und schlagwortketten
#         mult   => 1,
#         ref    => 1,
#     },
    '902k' => {            # schlagwoerter mit ID's
         newcat => '0710', # schlagwoerter und schlagwortketten
         mult   => 1,
         ref    => 1,
     },
    '902g' => {            # schlagwoerter mit ID's
         newcat => '0710', # schlagwoerter und schlagwortketten
         mult   => 1,
         ref    => 1,
     },
    '902s' => {            # schlagwoerter mit ID's
         newcat => '0710', # schlagwoerter und schlagwortketten
         mult   => 1,
         ref    => 1,
     },
#     '100' => {            # name der 1. person in ansetzungsform
#         newcat => '0100', # verfasser
#         mult   => 1,
#         ref    => 1,
#     },
    '102' => {            # ID der 1. person
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 1,
    },
#     '104' => {            # name der 2. person in ansetzungsform
#         newcat => '0100', # verfasser
#         mult   => 1,
#         ref    => 1,
#     },
    '106' => {            # ID der 2. person
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 1,
    },
#     '108' => {            # name der 3. person in ansetzungsform
#         newcat => '0100', # verfasser
#         mult   => 1,
#         ref    => 1,
#     },
    '110' => {            # ID der 3. person
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 1,
    },
#    '200' => {            # name der 1. koerperschaft in ansetzungsform
#        newcat => '0200', # koerperschaft
#        mult   => 1,
#    },
    '202a' => {            # ID der 1. koerperschaft
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 1,
    },
#     '204' => {            # name der 2. koerperschaft in ansetzungsform
#         newcat => '0200', # koerperschaft
#         mult   => 1,
#         ref    => 1,
#     },
    '206a' => {            # ID der 2. koerperschaft
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 1,
    },
#     '208' => {            # name der 3. koerperschaft in ansetzungsform
#         newcat => '0200', # koerperschaft
#         mult   => 1,
#         ref    => 1,
#     },
    '210a' => {            # ID der 3. koerperschaft
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 1,
    },

};

print "Bearbeite Titel\n";

if (-e "tmp.TIT"){
    open(TITOUT,'>:utf8','unload.TIT');
    
    tie @mab2titdata, 'Tie::MAB2::Recno', file => "tmp.TIT";
    
    foreach my $rawrec (@mab2titdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #print $rec->readable."\n----------------------\n";    
        my $multcount_ref = {};
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = konv($category_ref->[2]);
            
#            print "$category - $indicator - $content\n";

            $category = $category.$indicator;
            
            my $newcategory = "";
            
            if (!exists $titdefs_ref->{$category}){
                next;
            }
            
            # Vorabfilterung
            
#             # Titel-ID sowie Ueberordnungs-ID
#             if ($category =~ /^001$/ || $category =~ /^010$/){
#                 $content=~s/\D//g;
#             }
            
            if ($category =~ /^002a$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }

            if ($category =~ /^026 $/){
                $content=~s/^\D+//;
            }
            
            if ($category =~ /^542a$/){
                $content=~s/^\D+//;
            }

            if ($category =~ /^52[79]z$/  || $category =~ /^53[0123]z$/){
                $content=substr($content,20);
            }

            
            # Standard-Konvertierung mit perkonv
            
            if (!$titdefs_ref->{$category}{mult}){
                $indicator="";
            }
            
            if (exists $titdefs_ref->{$category}{newcat}){
                $newcategory = $titdefs_ref->{$category}{newcat};
            }
            
            if (exists $titdefs_ref->{$category}{ref}){
                
                if ($category =~/^9[0123][27][kgs]/){
                    my $tmpcontent=$content;
                    ($content)=$tmpcontent=~m/(\d+-.)/;
                }
                #            print "REF: Category $category Content $content\n";
                #            my $tmpcontent=$content;
                #            ($content)=$tmpcontent=~m/^(\d+.*)/;
                $content="IDN: $content" if ($content);
            }
            
            if ($newcategory && $titdefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print TITOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print TITOUT "$newcategory:$content\n";
            }
        }
        print TITOUT "9999:\n\n";
    }
    
    close(TITOUT);
}
else {
    print "Keine Titeldaten vorhanden. EXIT!!!!\n";
    exit;
}

######################################################################
# Exemplar-Daten

my $mexdefs_ref = {
    '001 '  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '012 '  => {
        newcat => '0004', # TitelID
        mut => 0,
    },
    '200 ' => {
         # Bestandsverlauf
        mult => 0,
        subfields => {
            '1204' => [ 'b', 'c'],
            '0014' => [ 'f' ],
        }
    },
    '071 ' => {
        newcat => '3330', # Bestandsverlauf
        mult => 0,
    },

};

print "Bearbeite Exemplare\n";
open(MEXOUT,'>:utf8','unload.MEX');

tie @mab2mexdata, 'Tie::MAB2::Recno', file => "tmp.MEX";

foreach my $rawrec (@mab2mexdata){
    my $rec = MAB2::Record::Base->new($rawrec);
    #print $rec->readable."\n----------------------\n";    
    my $multcount_ref = {};
    
    foreach my $category_ref (@{$rec->_struct->[1]}){
        my $category  = $category_ref->[0];
        my $indicator = $category_ref->[1];
        my $content   = $category_ref->[2];

#        print "$category - $indicator - $content\n";
        
        $category = $category.$indicator;

        my %subfield=();        
        if (exists $mexdefs_ref->{$category}{subfields}){
            foreach my $item (split("",$content)){
                if ($item=~/^(.)(.+)/){
                    $subfield{$1}=$2;
                }
            }
        }
        
        my $newcategory = "";
        
        if (!exists $mexdefs_ref->{$category}){
            next;
        }
        
        # Vorabfilterung
#         if ($category =~ /^001$/){
#             $content=~s/\D//g;
#         }

        
        if ($category =~ /^002 $/){
            $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
        }

        if ($category =~ /^071 $/){
            $content=~s/^38\///;
        }

        # Standard-Konvertierung mit perkonv

        if (!$mexdefs_ref->{$category}{mult}){
            $indicator="";
        }

#        print YAML::Dump(\%subfield);
        
        if (exists $mexdefs_ref->{$category}{subfields}){
            foreach my $newcategory (keys %{$mexdefs_ref->{$category}{subfields}}){
                my @newcontent=();
                foreach my $thissubfield (@{$mexdefs_ref->{$category}{subfields}{$newcategory}}){
                    if ($subfield{$thissubfield}){
                        push @newcontent,$subfield{$thissubfield};
                    }
                }

                $content=konv(join(" ",@newcontent));
                
                if ($newcategory && $mexdefs_ref->{$category}{mult} && $content){
                    my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                    print MEXOUT "$newcategory.$multcount:$content\n";
                }
                elsif ($newcategory && $content){
                    print MEXOUT "$newcategory:$content\n";
                }
            }
        }
        else {
            $content=konv($content);
            if (exists $mexdefs_ref->{$category}{newcat}){
                $newcategory = $mexdefs_ref->{$category}{newcat};
            }
            
            if ($newcategory && $mexdefs_ref->{$category}{mult} && $content){
                my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
                print MEXOUT "$newcategory.$multcount:$content\n";
            }
            elsif ($newcategory && $content){
                print MEXOUT "$newcategory:$content\n";
            }
        }
        
    }
    print MEXOUT "9999:\n\n";
}

close(MEXOUT);

sub konv {
  my ($line)=@_;

  $line=~s/\&/&amp;/g;
  $line=~s/>/&gt;/g;
  $line=~s/</&lt;/g;
  $line=~s/\x{0088}//g;
  $line=~s/\x{0089}//g;
  $line=~s/‡/ /g;
  $line=~s/^\|//;
  return $line;
}
