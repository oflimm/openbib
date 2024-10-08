#!/usr/bin/perl

use warnings;
use strict;

use OpenBib::Config;
use OpenBib::User;

my $db_map_ref = {
    'inst001' => 'inst001',
	'kapsel' => 'kapsel',
	'usbsab' => 'inst001',
	'usbhwa' => 'inst001',
	'inst900' => 'inst900',
	'inst007' => 'inst007',
	'inst137' => 'inst137',	
	'inst226' => 'inst226',
	'inst301' => 'inst301',	
	'inst303' => 'inst301',	
	'inst304' => 'inst301',	
	'inst305' => 'inst301',	
	'inst306' => 'inst301',	
	'inst307' => 'inst301',	
	'inst308' => 'inst301',	
	'inst309' => 'inst301',	
	'inst310' => 'inst301',	
	'inst311' => 'inst301',	
	'inst312' => 'inst301',	
	'inst313' => 'inst301',	
	'inst314' => 'inst301',	
	'inst315' => 'inst301',	
	'inst316' => 'inst301',	
	'inst317' => 'inst301',	
	'inst318' => 'inst301',	
	'inst319' => 'inst301',	
	'inst320' => 'inst301',	
	'inst321' => 'inst301',	
	'inst324' => 'inst301',	
	'inst325' => 'inst301',	
	'inst327' => 'inst301',	
	'openlibrary' => 'openlibrary',
	'zbmed' => 'zbmed',
	'spoho' => 'spoho',
	'inst171' => 'inst171',
	'kups' => 'kups',
	'digitalis' => 'digitalis',
	'inst420master' => 'inst420master',
	'lehrbuchsmlg' => 'inst001',
	'lesesaal' => 'inst001',
	'inst403' => 'inst403',
	'inst326' => 'inst326',
	'inst422' => 'inst420master',
	'inst209' => 'inst209',
	'inst005' => 'inst005',
	'wiso'    => 'inst001',
	'wikisource_de' => 'wikisource_de',
	'inst450' => 'inst450',
	'inst219' => 'inst219',

	'econbiz' => 'econbiz',
	'edz' => 'inst001',
	'einbaende' => 'einbaende',
	'gutenberg' => 'gutenberg',
	'inst009' => 'inst009',
	'inst104' => 'inst104',
	'inst106' => 'inst106',
	'inst107' => 'inst107',
	'inst109' => 'inst109',
	'inst117' => 'inst117',
	'inst127' => 'inst127',
	'inst132alt' => 'inst132alt',
	'inst140' => 'inst140',
	'inst155' => 'inst155',
	'inst158' => 'inst158',
	'inst159' => 'inst159',
	'inst160' => 'inst160',
	'inst164' => 'inst164',
	'inst204' => 'inst204',
	'inst205' => 'inst205',
	'inst206' => 'inst206',
	'inst210' => 'inst210',
	'inst211' => 'inst211',
	'inst212' => 'inst212',
	'inst214' => 'inst214',
	'inst215' => 'inst215',
	'inst216' => 'inst216',
	'inst217' => 'inst217',
	'inst220' => 'inst220',
	'inst222' => 'inst222',
	'inst223' => 'inst223',
	'inst224' => 'inst224',
	'inst225' => 'inst225',
	'inst231' => 'inst231',
	'inst234' => 'inst234',
	'inst402' => 'inst402',
	'inst423' => 'inst423',
	'inst459' => 'inst459',
	'inst502' => 'inst502',
	'inst509' => 'inst509',
	'inst517' => 'inst517',
	'instzs' => 'instzs',
	'koelnzeitung' => 'koelnzeitung',
	'nationallizenzen' => 'nationallizenzen',
	'rheinabt' => 'inst001',	
	'inst006' => 'inst006master',
	'inst102' => 'inst102master',
	'inst103' => 'inst103master',
	'inst105' => 'inst105master',
	'inst108' => 'inst108master',
	'inst110' => 'inst110master',
	'inst112' => 'inst112master',
	'inst113' => 'inst113master',
	'inst118' => 'inst118master',
	'inst119' => 'inst119master',
	'inst123' => 'inst123master',
	'inst125' => 'inst125master',
	'inst128' => 'inst128master',
	'inst132' => 'inst132master',
	'inst134' => 'inst134master',
	'inst136' => 'inst136master',
	'inst146' => 'inst146master',
	'inst156' => 'inst156master',
	'inst157' => 'inst157master',
	'inst166' => 'inst166master',
	'inst201' => 'inst201master',
	'inst207' => 'inst207master',
	'inst208' => 'inst208master',
	'inst218' => 'inst218master',
	'inst302' => 'inst302master',
	'inst309' => 'inst309master',
	'inst323' => 'inst323master',
	'inst401' => 'inst401master',
	'inst404' => 'inst404master',
	'inst405' => 'inst405master',
	'inst406' => 'inst406master',
	'inst407' => 'inst407master',
	'inst409' => 'inst409master',
	'inst410' => 'inst410master',
	'inst411' => 'inst411master',
	'inst412' => 'inst412master',
	'inst413' => 'inst413master',
	'inst414' => 'inst414master',
	'inst416' => 'inst416master',
	'inst418' => 'inst418master',
	'inst419' => 'inst419master',
	'inst420' => 'inst420master',
	'inst425' => 'inst425master',
	'inst426' => 'inst426master',
	'inst427' => 'inst427master',
	'inst428' => 'inst428master',
	'inst429' => 'inst429master',
	'inst430' => 'inst430master',
	'inst431' => 'inst431master',
	'inst432' => 'inst432master',
	'inst434' => 'inst434master',
	'inst437' => 'inst437master',
	'inst438' => 'inst438master',
	'inst444' => 'inst444master',
	'inst445' => 'inst445master',
	'inst448' => 'inst448master',
	'inst460' => 'inst460master',
	'inst461' => 'inst461master',
	'inst464' => 'inst464master',
	'inst466' => 'inst466master',
	'inst467' => 'inst467master',
	'inst468' => 'inst468master',
	'inst501' => 'inst501master',
	'inst503' => 'inst503master',
	'inst514' => 'inst514master',
	'inst526' => 'inst526master',
	'inst622' => 'inst622master',
	'inst623' => 'inst623master',
};


my $config = new OpenBib::Config;
my $user   = new OpenBib::User;

my $cartitems = $user->get_schema->resultset('Cartitem')->search_rs(
    {        
	titlecache   => undef,
    }
    );

while (my $item = $cartitems->next()){
    my $titleid  = $item->get_column('titleid');
    my $database = $item->get_column('dbname');    

    if (defined $db_map_ref->{$database}){
	my $new_record = OpenBib::Record::Title->new({ id => $titleid, database => $db_map_ref->{$database}, config => $config })->load_brief_record->set_database($database);
	
	# Wenn existent, aktualisieren mit neuen Daten
	if ($new_record->record_exists){
	    my $new_titlecache = $new_record->to_json;
	    
	    if ($new_titlecache){
		$item->update({ titlecache => $new_titlecache, comment => 'new from title' });
		print STDERR "Cache aktualisiert fuer DB $database - ID $titleid mit aktuellen Titeldaten\n";	    
	    }
	}
	# Fehler
	else {
	    print STDERR "Fehler DB $database - ID $titleid\n";	    
	}
    }
    else {
	print STDERR "Master DB $database nicht definiert\n";	    
    }
}
