#####################################################################
#
#  OpenBib::Handler::PSGI::Extensions::FidPhil::Login
#
#  Dieses File ist (C) 2004-2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Extensions::FidPhil::Fulltexts;

use strict;
use warnings;
no warnings 'redefine';
use utf8;
use OpenBib::Record::Title;
use base 'OpenBib::Handler::PSGI';
use Data::Dumper;


# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_record'                  => 'show_record',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    #my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');
    my $userid         = $self->param('userid');
    my $tagname        = $self->strip_suffix($self->param('tagname'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $path_prefix    = $self->param('path_prefix');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args
    my $method         = $query->param('_method');
    
    $titleid           = $self->param('edsid');
    $titleid   =~ s/.html//;
    my $record = OpenBib::Record::Title->new({database => "eds", id => $titleid, config => $config})->load_full_record({id => $titleid});

    my $url = $record->{_fields}->{eds_source}->[0]->{content}->{Record}->{FullText}->{Links}->[0]->{Url};
    return $self->redirect($url);

}

1;