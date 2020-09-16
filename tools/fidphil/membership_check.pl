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
use JSON;
use Text::CSV;
use MIME::Lite;

my $config = OpenBib::Config->new;
#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $systemdbh = DBI->connect(
"DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}",
    $config->{systemdbuser},
    $config->{systemdbpasswd}
) or die "could not connect";

sub collectNumbers {
    my $csv     = Text::CSV->new( { sep_char => ';' } );
    my $file    = shift;
    my %numbers = ();
    open( my $data, '<', $file ) or die "Could not open '$file' $!\n";
    while ( my $line = <$data> ) {
        chomp $line;
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();

            #trim necessary
            $numbers{ $fields[0] } = 'free';
        }
        else {
            warn "Line could not be parsed: $line\n";
        }
    }
    return %numbers;
}

sub is_valid_membership_number {
    $numbers_ref     = shift;
    $mitgliedsnummer = shift;
    if ( $numbers_ref->{$mitgliedsnummer} eq 'free' ) {
         return 1;
    }
    else {
        return 0;
    }
}

sub make_user_society_user {
    $user_id = shift;
    my $request = $systemdbh->prepare(
        "SELECT id from roleinfo WHERE rolename = 'fidphil_society' LIMIT 1");
    $request->execute();
    my $res = $request->fetchrow_array();
    $role_id = $res;
    my $request = $systemdbh->prepare(
        "UPDATE user_role 
         SET roleid = ?
         WHERE userid = ?"
    );
    $request->bind_param( 1, $role_id );
    $request->bind_param( 2, $user_id );
    $request->execute();
}

sub reset_user_status {
    $user_id = shift;
    my $request = $systemdbh->prepare(
        "SELECT mixed_bag from userinfo WHERE id = ? LIMIT 1");
    $request->bind_param( 1, $user_id );
    $request->execute();
    my $res = $request->fetchrow_array();
    $mixed_bag = decode_json($res);
    delete( $mixed_bag->{"bag_society"} );
    delete( $mixed_bag->{"bag_mitgliedsnummer"} );
    $mixed_bag_json = encode_json($mixed_bag);
    my $request = $systemdbh->prepare(
        "UPDATE userinfo 
         SET mixed_bag = ?
         WHERE id = ?"
    );
    $request->bind_param( 1, $mixed_bag_json );
    $request->bind_param( 2, $user_id );
    $request->execute();
}

sub send_membership_confirmation {
    $email           = shift;
    $society         = shift;
    $mitgliedsnummer = shift;

    my $mailmsg = MIME::Lite->new(
        From    => $config->{contact_email},
        To      => $email,
        Subject => 'Sie wurden als Fachgesellschafts-Nutzer bestätigt',
        Type    => 'multipart/mixed'
    );

    $mailmsg->send( 'sendmail',
        "/usr/lib/sendmail -t -oi -f$config->{contact_email}" );
}

#####################################################################
# aktuelle Nummern sammeln

my $dgphil_list = "/opt/openbib/conf/fidphil/membership_dgphil.csv"
  or die "Need to get CSV file on the command line\n";
my %dgphil_numbers = collectNumbers($dgphil_list);
print Dumper @dgphil_numbers;
my $gap_list = "/opt/openbib/conf/fidphil/membership_gap.csv"
  or die "Need to get CSV file on the command line\n";
my %gap_numbers = collectNumbers($gap_list);
print Dumper @gap_numbers;

#####################################################################
# alle User der Rollen fidphil_user, fidphil_society finden
# vielleicht sollte das normale Skript nur die normalen FidPhil User finden

my $request = $systemdbh->prepare(
    "SELECT id from roleinfo WHERE rolename = 'fidphil_user'"

#"SELECT id from roleinfo WHERE rolename = 'fidphil_user' OR  rolename = 'fidphil_society' "
);
$request->execute();
@ids = ();
while ( my $res = $request->fetchrow_hashref ) {
    push( @ids, $res->{id} );
}

#####################################################################
# Nutzerdaten abrufen und Nutzer iterieren

my $request = $systemdbh->prepare(
    "SELECT userinfo.id, email, mixed_bag, vorname
    FROM userinfo
    INNER JOIN user_role
    ON userinfo.id = user_role.userid 
    WHERE roleid = ? "
);

$request->execute(@ids);

while ( my $res = $request->fetchrow_hashref ) {
    my $userid          = $res->{id};
    my $email           = $res->{email};
    my $mixed_bag       = decode_json( $res->{mixed_bag} );
    my $society         = $mixed_bag->{"bag_society"}[0];
    my $mitgliedsnummer = $mixed_bag->{'bag_mitgliedsnummer'}->[0];

    if ( $society eq 'gap' && $mitgliedsnummer ) {
        if ( is_valid_membership_number( \%gap_numbers, $mitgliedsnummer ) ) {
            print "is valid " . $mitgliedsnummer . "\n";
            $gap_numbers{$mitgliedsnummer} = "taken";
            #we have to check here if the operation is succesful
            make_user_society_user($userid);
            send_membership_confirmation( $email, $society, $mitgliedsnummer );
        }
        else {
            print "is invalid " . $mitgliedsnummer . "\n";
            reset_user_status($userid);
        }
    }
    elsif ( $society eq 'dgphil' && $mitgliedsnummer ) {
        if ( is_valid_membership_number( \%dgphil_numbers, $mitgliedsnummer ) )
        {
            print "is valid " . $mitgliedsnummer . "\n";
            #we have to check here if the operation is succesful
            $dgphil_numbers{$mitgliedsnummer} = "taken";
            make_user_society_user($userid);
            send_membership_confirmation( $email, $society, $mitgliedsnummer );
        }
        else {
            print "is invalid " . $mitgliedsnummer . "\n";
            reset_user_status($userid);
        }
    }
}
#we need to serialize the new information back to the csv-file
print Dumper(\%dgphil_numbers);
print Dumper(\%gap_numbers);

