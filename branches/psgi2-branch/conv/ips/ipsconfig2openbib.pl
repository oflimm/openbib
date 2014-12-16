#!/usr/bin/perl

use Encode 'decode';
use File::Find;
use File::Slurp;
use Getopt::Long;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML::Syck;
use DB_File;
use Encode qw /decode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $gatewayconfig_ref = {};

my ($configdir);

&GetOptions(
	    "configdir=s"           => \$configdir,
	    );

if (!$configdir){
    print << "HELP";
ipsconfig2openbib.pl - Aufrufsyntax

    ipsconfig2openbib.pl --configdir=xxx
HELP
exit;
}

our $parser = XML::LibXML->new();
#    $parser->keep_blanks(0);
#    $parser->recover(2);
#    $parser->clean_namespaces( 1 );

sub process_file {
    return unless ($File::Find::name=~/.xml$/);

    print $File::Find::name,"\n";

    my $slurped_file = decode("latin1",read_file($File::Find::name));

    my $tree = $parser->parse_string($slurped_file);
    my $root = $tree->getDocumentElement;

    my $simple_element_ref = {
        "name" => "NAME",
        "description" => "DESCRIPTION",
        "module" => "MODULE",
        "host" => "HOST",
        "port" => "PORT",
        "path"  => "PATH",
        "method" => "METHOD",
        "useurlenc" => "USEURLENC",
        "urldata" => "URLDATA",
        "lurldata" =>"LURLDATA",
        "murldata" => "MURLDATA",
        "prefilter" => "PREFILTER",
        "postfilter" => "POSTFILTER",
        "lprefilter" => "LPREFILTER",
        "lpostfilter" => "LPOSTFILTER",
        "mprefilter" => "MPREFILTER",
        "mpostfilter" => "MPOSTFILTER",
        "charsetfromclient" => "CHARSETFROMCLIENT",
    };

    my $z3950_searchtype_element_ref = {
        "ips_label" => "IPS_LABEL",
        "use" => "USE",
        "description" => "DESCRIPTION",
        "structure" => "STRUCTURE",
        "truncation" => "TRUNCATION",
        "relation" => "RELATION",
        "position" => "POSITION",
        "completeness" => "COMPLETENESS",
        "normalization" => "NORMALIZATION",
    };
    
    # HTTP-Gateways
    foreach my $node ($root->findnodes('/DBGATEWAYS/DBHTTP')) {
        my $id    = $node->getAttribute ('id');

        # Einfach Elemente einlesen
        foreach my $element (keys %{$simple_element_ref}){
            my $ipselement = $simple_element_ref->{$element};
            foreach my $item ($node->findnodes ("$ipselement//text()")) {
                my $content = $item->textContent;
                $gatewayconfig_ref->{$id}{$element} = $content;
            }
        }

    }

    # HTTPXML-Gateways
    foreach my $node ($root->findnodes('/DBGATEWAYS/DBHTTPXML')) {
        my $id    = $node->getAttribute ('id');

        # Einfach Elemente einlesen
        foreach my $element (keys %{$simple_element_ref}){
            my $ipselement = $simple_element_ref->{$element};
            foreach my $item ($node->findnodes ("$ipselement//text()")) {
                my $content = $item->textContent;
                $gatewayconfig_ref->{$id}{$element} = $content;
            }
        }

    }

    # Z3950-Gateways
    foreach my $node ($root->findnodes('/DBGATEWAYS/DBZ3950')) {
        my $id    = $node->getAttribute ('id');

        # Einfach Elemente einlesen
        foreach my $element (keys %{$simple_element_ref}){
            my $ipselement = $simple_element_ref->{$element};
            foreach my $item ($node->findnodes ("$ipselement//text()")) {
                my $content = $item->textContent;
                $gatewayconfig_ref->{$id}{$element} = $content;
            }
        }

        # Spezielle Z3950-Elemente Einlesen
        
        # Z39.50 SERVERCONFIG ATOM
        my $serverconfig_ref = {};
        foreach my $item ($node->findnodes ("Z3950_GATEWAY_SETTINGS/ATOMS/ATOM")) {
            my $element = $item->getAttribute ('id');
            my $content = $item->textContent;
            $serverconfig_ref->{$element} = $content;

        }

        push @{$gatewayconfig_ref->{$id}{serverconfig}}, $serverconfig_ref;

        # SEARCH_TYPES
        foreach my $item ($node->findnodes ("Z3950_GATEWAY_SETTINGS/SEARCH_TYPES/SEARCH_TYPE")) {

            my $searchtype_ref = {};
            # Einfach Elemente einlesen
            foreach my $element (keys %{$z3950_searchtype_element_ref}){
                my $ipselement = $z3950_searchtype_element_ref->{$element};
                foreach my $subitem ($item->findnodes ("$ipselement//text()")) {
                    my $content = $subitem->textContent;
                    $searchtype_ref->{$element} = $content;
                }
            }

            push @{$gatewayconfig_ref->{$id}{search_types}}, $searchtype_ref;
        }


    }
}

find(\&process_file, $configdir);

YAML::DumpFile("gatewayconfig.yml",$gatewayconfig_ref);
