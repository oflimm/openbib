#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use OpenBib::Catalog::Factory;
use OpenBib::Config;

use LWP::UserAgent;
use XML::LibXML;
use Encode qw(decode decode_utf8);

my $config = OpenBib::Config->new;

my $dbis        = OpenBib::Catalog::Factory->create_catalog({database => 'dbis' });

my $dbistopics = $config->get_schema->resultset('Dbistopic');

# Zuerst loeschen
$config->get_schema->resultset('DbistopicDbisdb')->delete;
$config->get_schema->resultset('Dbisdb')->delete;

foreach my $thisdbistopic ($dbistopics->all){
    my $dbistopicid = $thisdbistopic->id;
    my $dbistopic   = $thisdbistopic->topic;

    print "$dbistopicid - $dbistopic\n";

    my $url="http://dbis.uni-regensburg.de/dbinfo/dbliste.php?bib_id=usb_k&colors=63&ocolors=40&lett=f&gebiete=$dbistopic&xmloutput=1";
    
    my $response =  LWP::UserAgent->new->get($url)->decoded_content(charset => 'utf8');

    print $url,$response,"\n";
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;
    
    my $db_group_ref             = {};
    my $dbs_ref                  = [];
    my $have_group_ref           = {};
    $db_group_ref->{group_order} = [];
    
    my $search_count = 0;
    foreach my $db_node ($root->findnodes('/dbis_page/list_dbs/dbs[@top_db=1]/db')) {
	my $single_db_ref = {};
	
	$single_db_ref->{id}       = $db_node->findvalue('@title_id');
	$single_db_ref->{access}   = $db_node->findvalue('@access_ref');
	my @types = split(" ",$db_node->findvalue('@db_type_refs'));
	
	$single_db_ref->{db_types} = \@types;
	$single_db_ref->{title}     = $db_node->textContent;
	
	push @{$dbs_ref}, $single_db_ref;
    }
    

    foreach my $dbinfo (@$dbs_ref){
        my $dbisdb   = $config->get_schema->resultset('Dbisdb')->single({ id => $dbinfo->{id} });
        
        if (!$dbisdb){
            $dbisdb   = $config->get_schema->resultset('Dbisdb')->create({id => $dbinfo->{id}, description => $dbinfo->{title}, url => '1' });
        }
        
        my $dbisdbid = $dbisdb->id;

        $config->get_schema->resultset('DbistopicDbisdb')->create({dbisdbid => $dbisdbid, dbistopicid => $dbistopicid, rank => 1 });
        
    }
}
