#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

use OpenBib::Config;
use JSON::XS;
use XML::Twig;
use XML::Simple;
use YAML;
    
my $pool = "digisoz";

my $config = new OpenBib::Config;

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";

my $url           = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

my $httpauthstring="";
if ($dbinfo->protocol eq "http" && $dbinfo->remoteuser ne "" && $dbinfo->remotepassword ne ""){
    $httpauthstring=" --http-user=".$dbinfo->remoteuser." --http-password=".$dbinfo->remotepassword;
}


# Download CDM Export

system("cd $pooldir/$pool ; rm *.xml");
system("$wgetexe $httpauthstring -P $pooldir/$pool/ $url > /dev/null 2>&1 ");

unlink "./enrich_cdm.db";

our %enrich_cdm = ();
tie %enrich_cdm,                'MLDBM', "./enrich_cdm.db"
    or die "Could not tie enrich_cdm.\n";


my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
   }
 );

my $xmlfile = "$pooldir/$pool/".$dbinfo->titlefile;

print STDERR "Parsing $xmlfile\n";

$twig->parsefile($xmlfile);

print STDERR "Parsing done\n";

print STDERR "Processing titles\n";


while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $enrich_fields;
    
    if (defined $enrich_cdm{$titleid} && keys %{$enrich_cdm{$titleid}}){
	$enrich_fields = $enrich_cdm{$titleid};
    }

    if (defined $enrich_fields->{'0662'}){
	my $max_mult = 0;

	# Maxmult bestimmen
	foreach my $field_ref (@{$title_ref->{fields}{'0662'}}){
	    if ($field_ref->{mult} > $max_mult){
		$max_mult = $field_ref->{mult};
	    }
	}

	foreach my $enrich_field_ref (@{$enrich_fields->{'0662'}}){
	    push @{$title_ref->{fields}{'0662'}}, {
		content  => $enrich_field_ref->{content},
		mult     => sprintf('%03d',$max_mult+1),
		subfield => '',
	    };
	    push @{$title_ref->{fields}{'0663'}}, {
		content  => "Volltext SSOAR",
		mult     => sprintf('%03d',$max_mult+1),
		subfield => '',
	    };

	    $max_mult++;
	}
	
    }

    foreach my $structure_field ('6050','6051','6052','6053','6054'){
	$title_ref->{fields}{$structure_field} = $enrich_fields->{$structure_field} if (defined $enrich_fields->{$structure_field});
    }


    print encode_json $title_ref, "\n";
}

unlink "./enrich_cdm.db";

sub parse_titset {
    my($t, $titset)= @_;
    
    my $fields_ref = {};
    
    my $katkey;

    # Katkey
    if (defined $titset->first_child('katkey') && $titset->first_child('katkey')->text()){
	my $content = konv($titset->first_child('katkey')->text());
	
	$katkey=$content;
    }

    # SSOAR_Url
    if (defined $titset->first_child('ssoar_url') && $titset->first_child('ssoar_url')->text()){
	my $content = $titset->first_child('ssoar_url')->text();


	push @{$fields_ref->{'0662'}}, {
	    content  => $content,
	    subfield => '',
	};
	
    }

    # Strukturdaten    
    # if (defined $titset->first_child('structure')){
    #     my $structure = $titset->first_child('structure')->sprint();
        
    #     my $xs = new XML::Simple(ForceArray => ['node','page','pagefile']);
        
    #     my $structure_ref = $xs->XMLin($structure);
        
    #     # print YAML::Syck::Dump($structure_ref);
        
        
    #     if (@{$structure_ref->{page}} > 0){
    #         my $mult = 1;
            
    #         foreach my $page_ref (@{$structure_ref->{page}}){
    #             push @{$fields_ref->{'6050'}}, {
    #                 mult       => $mult,
    #                 subfield   => '',
    #                 content    => $page_ref->{pagetitle},
    #             } if (defined $page_ref->{pagetitle});

    #             foreach my $pagefile_ref (@{$page_ref->{pagefile}}){
    #                 if ($pagefile_ref->{pagefiletype} eq "access"){
    #                     push @{$fields_ref->{'6051'}}, {
    #                         mult       => $mult,
    #                         subfield   => '',
    #                         content    => $pagefile_ref->{pagefilelocation},
    #                     } if (defined $pagefile_ref->{pagefilelocation});
    #                 }
                    
                    
    #                 if ($pagefile_ref->{pagefiletype} eq "thumbnail"){
    #                     push @{$fields_ref->{'6052'}}, {
    #                         mult       => $mult,
    #                         subfield   => '',
    #                         content    => $pagefile_ref->{pagefilelocation},
    #                     } if (defined $pagefile_ref->{pagefilelocation});
    #                 }
    #             }
    #             push @{$fields_ref->{'6053'}}, {
    #                 mult       => $mult,
    #                 subfield   => '',
    #                 content    => $page_ref->{pagetext},
    #             } if (defined $page_ref->{pagetext});

    #             push @{$fields_ref->{'6054'}}, {
    #                 mult       => $mult,
    #                 subfield   => '',
    #                 content    => $page_ref->{pageptr},
    #             } if (defined $page_ref->{pageptr});
    #             $mult++;
    #         }   
    #     }

    #     elsif (@{$structure_ref->{node}} > 0){

    #         foreach my $node_ref (@{$structure_ref->{node}}){
    #             my $mult = 1;
            
    #             foreach my $page_ref (@{$node_ref->{page}}){
    #                 push @{$fields_ref->{'6050'}}, {
    #                     mult       => $mult,
    #                     subfield   => '',
    #                     content    => $page_ref->{pagetitle},
    #                 } if (defined $page_ref->{pagetitle});
                    
    #                 foreach my $pagefile_ref (@{$page_ref->{pagefile}}){
    #                     if ($pagefile_ref->{pagefiletype} eq "access"){
    #                         push @{$fields_ref->{'6051'}}, {
    #                             mult       => $mult,
    #                             subfield   => '',
    #                             content    => $pagefile_ref->{pagefilelocation},
    #                         } if (defined $pagefile_ref->{pagefilelocation});
    #                     }
                        
    #                     if ($pagefile_ref->{pagefiletype} eq "thumbnail"){
    #                         push @{$fields_ref->{'6052'}}, {
    #                             mult       => $mult,
    #                             subfield   => '',
    #                             content    => $pagefile_ref->{pagefilelocation},
    #                         } if (defined $pagefile_ref->{pagefilelocation});
    #                     }
    #                 }
                    
    #                 push @{$fields_ref->{'6053'}}, {
    #                     mult       => $mult,
    #                     subfield   => '',
    #                     content    => $page_ref->{pagetext},
    #                 } if (defined $page_ref->{pagetext});
                    
    #                 push @{$fields_ref->{'6054'}}, {
    #                     mult       => $mult,
    #                     subfield   => '',
    #                     content    => $page_ref->{pageptr},
    #                 } if (defined $page_ref->{pageptr});
    #                 $mult++;
    #             }
    #         }
    #     }
    # }
    
    $enrich_cdm{$katkey} = $fields_ref if ($katkey);
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
