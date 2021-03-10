#!/usr/bin/perl
#####################################################################
#
#  create_user.pl
#
#  Anlegen eines Nutzers in der Infrastruktur
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Email::Valid;
use Getopt::Long;
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::System;
use OpenBib::Statistics;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($view,$username,$authenticator,$password,$email,$help,$loglevel,$logfile);

&GetOptions(
    "username=s"      => \$username,
    "view=s"          => \$view,
    "authenticator=s" => \$authenticator,
    "password=s"      => \$password,
    "email=s"         => \$email,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "help"            => \$help
    );

if ($help){
    print_help();
}

$loglevel = ($loglevel)?$loglevel:"INFO";
$logfile  = ($logfile)?$logfile:'/var/log/openbib/create_user.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config     = OpenBib::Config->new;
my $user       = OpenBib::User->new;


$authenticator=($authenticator)?$authenticator:'selfreg';


if (!$authenticator || !$view || !$username){
    print STDERR "Fehler: Fehlende Parameter view oder username\n\n";
    print_help();
}

if ($authenticator eq "selfreg" && !Email::Valid->address($username)){
    print STDERR "Fehler: Nutzername ist keine gültige Mailadresse\n\n";
    print_help();    
}


my $authenticator_ref = $config->get_authenticator_by_dbname($authenticator);

if (!$authenticator_ref){
    print STDERR "Fehler: Authenticator existiert nicht\n\n";
    print_help();    
}

my $viewid;

eval {
    $viewid = $config->get_viewinfo->single({ viewname => $view })->id;
};

if (!$viewid){
    print STDERR "Fehler: View existiert nicht\n\n";
    print_help();    
}


if ($user->user_exists_in_view({ username => $username, viewid => $viewid})){
    print STDERR "Fehler: User $username existiert bereits in View $view\n\n";
    print_help();    
}

my $new_userid = $user->add({
    username => $username,
    password => $password,
    viewid   => $viewid,
    email    => $email,
    authenticatorid => $authenticator_ref->{id}
			  });


print << "SUCCESS";
Ein neuer Nutzer '$username' wurde angelegt:

Id           : $new_userid
View         : $view (Id: $viewid)
Authenticator: $authenticator (Id: $authenticator_ref->{id})
Passwort     : $password
Email        : $email
SUCCESS


sub print_help {
    print << "ENDHELP";
create_user.pl - Anlegen eines Nutzers

   Optionen:
   -help                 : Diese Informationsseite
   --username=...        : Nutzerkennung
   --view=...            : View
   --authenticator=...   : Authenticator (default: selfreg)
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Loglevel
ENDHELP
    exit;
}

