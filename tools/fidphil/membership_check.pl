#!/usr/bin/perl

#####################################################################
#
#  activate_rss_all.pl
#
#  Aktivierung aller Standard-RSS-Feeds in der Session-DB
#
#  Dieses File ist (C) 2006-2008 Oliver Flimm <flimm@openbib.org>
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

use DBI;

use OpenBib::Config;
use Data::Dumper;


my $config = OpenBib::Config->new;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $systemdbh = DBI->connect(
"DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}",
    $config->{systemdbuser},
    $config->{systemdbpasswd}
) or die "could not connect";

#####################################################################
# alle User der Rollen fidphil_user, fidphil_society finden
# vielleicht sollte das normale Skript nur die normalen FidPhil User finden

my $request = $systemdbh->prepare(
"SELECT id from roleinfo WHERE rolename = 'fidphil_user' OR  rolename = 'fidphil_society' "
);
$request->execute();
@ids = ();
while ( my $res = $request->fetchrow_hashref ) {
    push( @ids, $res->{id} );
}

my $request = $systemdbh->prepare(
    "SELECT userinfo.id, email, mixed_bag, vorname
    FROM userinfo
    INNER JOIN user_role
    ON userinfo.id = user_role.userid 
    WHERE roleid = ? OR roleid = ? "
);

$request->execute(@ids);
while ( my $res = $request->fetchrow_hashref ) {
    my $id    = $res->{id};
    my $email = $res->{email};
    my $vorname = $res->{vorname};
    my $mixed_bag = 0;
    print STDERR "$vorname\n";
}

print "done\n";
