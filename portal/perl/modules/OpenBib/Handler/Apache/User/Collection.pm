#####################################################################
#
#  OpenBib::Handler::Apache::User::Collection
#
#  Dieses File ist (C) 2001-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::User::Collection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common M_GET);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # print, rflush
use Apache2::SubRequest (); # internal_redirect
use Apache2::URI ();
use APR::URI ();

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::ManageCollection::Util;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'       => 'show_collection',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

        
    my $recordlist = $user->get_items_in_collection();

    if ($recordlist->get_size() == 0) {
        # TT-Data erzeugen
        my $ttdata={
            qopts          => $queryoptions->get_options,
        };
        
        $self->print_page($config->{tt_managecollection_empty_tname},$ttdata);
        return Apache2::Const::OK;
    }

    # TT-Data erzeugen
    my $ttdata={
        view              => $view,
        stylesheet        => $stylesheet,
        sessionID         => $session->{ID},
        qopts             => $queryoptions->get_options,
        type              => $type,
        show              => $show,
        recordlist        => $recordlist,
        dbinfo            => $dbinfotable,
        
        user              => $user,
        config            => $config,
        user              => $user,
        msg               => $msg,
    };
    
    $self->print_page($config->{tt_user_collection_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
    # Abspeichern der Merkliste
    elsif ($action eq "save" || $action eq "print" || $action eq "mail") {
        my $loginname=$user->get_username();

        my $recordlist = new OpenBib::RecordList::Title();

        if ($singleidn && $database) {
            $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
        }
        else {
            if ($user->{ID}) {
                $recordlist = $user->get_items_in_collection();
            }
            else {
                $recordlist = $session->get_items_in_collection()
            }
        }

        $recordlist->load_full_records;

        if ($action eq "save"){
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
                qopts       => $queryoptions->get_options,		
                type        => $type,
                show        => $show,
                recordlist  => $recordlist,
                dbinfo      => $dbinfotable,
                
                config     => $config,
                msg        => $msg,
            };

            if ($type eq "HTML") {
                $r->content_type('text/html');
                $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.html\"");
                OpenBib::Common::Util::print_page($config->{tt_managecollection_save_html_tname},$ttdata,$r);
            }
            else {
                $r->content_type('text/plain');
                $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
                OpenBib::Common::Util::print_page($config->{tt_managecollection_save_plain_tname},$ttdata,$r);
            }
            return Apache2::Const::OK;
        }
        elsif ($action eq "print"){
            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,		
                sessionID  => $session->{ID},
                qopts      => $queryoptions->get_options,		
                type       => $type,
                show       => $show,
                loginname  => $loginname,
                singleidn  => $singleidn,
                database   => $database,
                recordlist => $recordlist,
                dbinfo     => $dbinfotable,

                config     => $config,
                msg        => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_managecollection_print_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }
        elsif ($action eq "mail"){
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
                qopts       => $queryoptions->get_options,				
                type        => $type,
                show        => $show,
                loginname   => $loginname,
                singleidn   => $singleidn,
                database    => $database,
                recordlist  => $recordlist,
                dbinfo      => $dbinfotable,
                
                config      => $config,
                msg         => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_managecollection_mail_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
        return Apache2::Const::OK;
    }
    return Apache2::Const::OK;
}

1;
