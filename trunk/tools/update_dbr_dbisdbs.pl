#!/usr/bin/perl

use OpenBib::Catalog::Factory;
use OpenBib::Config;

use LWP::UserAgent;
use XML::LibXML;
use Encode qw(decode decode_utf8);

my $config = OpenBib::Config->instance;

my $dbis        = OpenBib::Catalog::Factory->create_catalog({database => 'dbis' });

my $dbistopics = $config->{schema}->resultset('Dbistopic');

# Zuerst loeschen
$config->{schema}->resultset('Dbisdb')->delete;

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
    foreach my $dbs_node ($root->findnodes('/dbis_page/list_dbs/dbs')) {
        $search_count = $dbs_node->findvalue('@db_count');

        foreach my $db_node ($dbs_node->findnodes('db')) {
            next unless $db_node->findvalue('@top_db');
            
            my $single_db_ref = {};
            
            $single_db_ref->{id}       = $db_node->findvalue('@title_id');
            $single_db_ref->{access}   = $db_node->findvalue('@access_ref');
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));
            
            $single_db_ref->{db_types} = \@types;
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);
            
            push @{$dbs_ref}, $single_db_ref;
        }
    }
    

    foreach my $dbinfo (@$dbs_ref){
        my $dbisdb   = $config->{schema}->resultset('Dbisdb')->single({ id => $dbinfo->{id} });
        
        if (!$dbisdb){
            $dbisdb   = $config->{schema}->resultset('Dbisdb')->create({id => $dbinfo->{id}, description => $dbinfo->{title}, url => '1' });
        }
        
        my $dbisdbid = $dbisdb->id;

        $config->{schema}->resultset('DbistopicDbisdb')->create({dbisdbid => $dbisdbid, dbistopicid => $dbistopicid, rank => 1 });
        
    }
}
