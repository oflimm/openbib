####################################################################
#
#  OpenBib::Handler::Apache::Connector::SpellCheck.pm
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::SpellCheck;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # print, rflush
use Apache2::RequestRec ();
use Benchmark;
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;
use Text::Aspell;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);
    
#     my $status=$query->parse;
    
#     if ($status){
#         $logger->error("Cannot parse Arguments");
#     }

    # Blacklist von unterdrueckten Worten, die leider in den entsprechenden Aspell-Dictionaries vorhanden sind
    # ToDo: Entfernung auf dem Dictionary-Level. Hier kann es aber zu Lizenzproblemen kommen, wenn diese geaendert werden.
    my $profanities_ref = {
        'Fotzen' => 1,
        'Fotze'  => 1,
        'fick'   => 1,
        'ficken' => 1,
        'fickte' => 1,
    };
    
    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $word = $query->param('q') || '';
    
    return Apache2::Const::OK if (!$word || $word=~/\d/);

    my @aspell_languages = ('de','en');
    
    # Nur Vorschlaege sammeln, wenn der Begriff nicht im Woerterbuch vorkommt
    my @aspell_suggestions = ();
    my %have_suggestion    = ();

    foreach my $aspell_language (@aspell_languages){
        my $speller = Text::Aspell->new;
        
        $speller->set_option('sug-mode','normal');
        $speller->set_option('ignore-case','true');
        $speller->set_option('encoding','utf-8');
        $speller->set_option('lang',$aspell_language);

        my @this_aspell_suggestions=($speller->check($word))?():$speller->suggest( $word );

        # Filtern
        @this_aspell_suggestions =
                            grep {! $have_suggestion{lc($_)} ++}                              # Doppelte Vorschlaege herausfiltern
                                grep {! /[ -']/ }                                             # Vorschlaege mit speziellen Zeichen herausfiltern
                                    grep {! $profanities_ref->{$_}} @this_aspell_suggestions; # Unerwuenschte Vorschlaege herausfiltern

        # Maximal 7 Vorschlaege pro Sprache
        if ($#this_aspell_suggestions > 6){
            push @aspell_suggestions, @this_aspell_suggestions[0..6];
        }
        else {
            push @aspell_suggestions, @this_aspell_suggestions;
        }

        $logger->debug("Found corrections for $word in language $aspell_language: ".join(',',@aspell_suggestions));
    }

    $r->content_type("text/plain");
    
    if (@aspell_suggestions){
        $r->print(join("\n",map {decode_utf8($_)} @aspell_suggestions));
    }
    else {
        $logger->debug("Found $word in dictionary or no suggestions");
    }


    return Apache2::Const::OK;
}

1;
