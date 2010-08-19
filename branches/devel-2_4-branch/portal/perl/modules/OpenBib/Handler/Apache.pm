#####################################################################
#
#  OpenBib::Handler::Apache
#
#  Dieses File ist (C) 2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use CGI::Application::Plugin::Apache qw(:all);
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'CGI::Application';

sub cgiapp_init() {       # overrides
   my $self = shift;

   # Log4perl logger erzeugen
   my $logger = get_logger();

   $logger->debug("Entering cgiapp_init");
   
   my $r          = $self->param('r');

   my $config     = OpenBib::Config->instance;
   my $session    = OpenBib::Session->instance({ apreq => $r , view => $self->param('view') });
   my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

   my $useragent  = $r->subprocess_env('HTTP_USER_AGENT');
   my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);

   my $queryoptions = OpenBib::QueryOptions->instance($self->query());

   # Message Katalog laden
   my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
   $msg->fail_with( \&OpenBib::L10N::failure_handler );

   $self->param('config',$config);
   $self->param('session',$session);
   $self->param('user',$user);
   $self->param('useragent',$useragent);
   $self->param('stylesheet',$stylesheet);
   $self->param('msg',$msg);
   $self->param('qopts',$queryoptions);

   $logger->debug("Exit cgiapp_init");
   #   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
}

1;
