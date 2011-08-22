#!/usr/bin/perl

#####################################################################
#
#  joinindex.pl
#
#  Erzeugung kombinierter Indizes fuer alle Profile, deren
#  Organisationseinheiten und Views
#
#  Dieses File ist (C) 2011 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use DBI;
use YAML;

use OpenBib::Config;

my $config = new OpenBib::Config;

my $xapian_path = $config->{xapian_index_base_path};

my $all_profiles_ref = $config->get_profileinfo_overview;

my %is_active = ();

foreach my $item ($config->get_databaseinfo->search({ active => 1 })->all){
    my $dbname=$item->dbname;
    
    $is_active{$dbname} = 1 if (-d "$xapian_path/$dbname");
}

# View
foreach my $item_ref ($config->get_viewinfo->search({ joinindex => 1 })->all){
    my $viewname = $item_ref->viewname;
    
    print "Processing View $viewname\n";
    
    my @databases = $config->get_viewdbs($viewname);
    
    my $destination_index = "$xapian_path/joined/view_$viewname";
    
    if (! -d $destination_index ){
        system("mkdir -p $destination_index");
    }
    
    if (! -d "$destination_index.tmp" ){
        system("mkdir -p $destination_index.tmp");
    }
    
    my @databaseindex = map { $_ = "$xapian_path/$_" } grep {$is_active{$_}} @databases;
    
    if (@databaseindex){
        my $cmd = "/usr/bin/xapian-compact -m ".join(' ',@databaseindex)." $destination_index.tmp";
        
        print "$cmd\n";
        
        system ($cmd);
        
            system("rm $destination_index/* ; rmdir $destination_index ; mv $destination_index.tmp $destination_index");
    }
}

exit;
# Profile
foreach my $profile_ref (@{$all_profiles_ref}){
    my $profilename = $profile_ref->{profilename};

    print "Processing Profile $profilename\n";
    
    my $all_orgunits_ref = $config->get_orgunits($profilename);

    my @orgunitindex = ();
    
    foreach my $orgunit_ref (@{$all_orgunits_ref}){
        my $orgunitname = $orgunit_ref->{orgunitname};

        print "Processing Orgunit $orgunitname\n";
        
        my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);

        my @databases = @{$orgunitinfo_ref->{dbname}};

        my $destination_index = "$xapian_path/joined/$profilename/org_$orgunitname";

        if (! -d $destination_index ){
            system("mkdir -p $destination_index");
        }

        if (! -d "$destination_index.tmp" ){
            system("mkdir -p $destination_index.tmp");
        }

        my @databaseindex = map { $_ = "$xapian_path/$_" } grep {$is_active{$_}} @databases;

        if (@databaseindex){
            my $cmd = "/usr/bin/xapian-compact -m ".join(' ',@databaseindex)." $destination_index.tmp";
            
            print "$cmd\n";
            
            system ($cmd);
        
            system("rm $destination_index/* ; rmdir $destination_index ; mv $destination_index.tmp $destination_index");

            push @orgunitindex, $orgunitname;
        }
    }


    # Alle Kataloge im Profil
    my $destination_index = "$xapian_path/joined/$profilename/alldbs";
    
    if (! -d $destination_index ){
        system("mkdir -p $destination_index");
        }
    
    if (! -d "$destination_index.tmp" ){
        system("mkdir -p $destination_index.tmp");
    }

    if (@orgunitindex){
        my $cmd = "/usr/bin/xapian-compact -m ".join(' ',@orgunitindex)." $destination_index.tmp";
        
        print "$cmd\n";
        
        system ($cmd);
        
        system("rm $destination_index/* ; rmdir $destination_index ; mv $destination_index.tmp $destination_index");
    }
}
