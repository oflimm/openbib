####################################################################
#
#  OpenBib::Handler::PSGI::Connector::SpellCheck.pm
#
#  Dieses File ist (C) 2008-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Connector::SpellCheck;

use strict;
use warnings;
no warnings 'redefine';

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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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

    # CGI Args
    my $word = $query->param('q') || '';

    return if (!$word || $word=~/\d/);
    
    # Blacklist von unterdrueckten Worten, die leider in den entsprechenden Aspell-Dictionaries vorhanden sind
    # ToDo: Entfernung auf dem Dictionary-Level. Hier kann es aber zu Lizenzproblemen kommen, wenn diese geaendert werden.
    my $profanities_ref = {
        'Fotzen' => 1,
        'Fotze'  => 1,
        'fick'   => 1,
        'ficken' => 1,
        'fickte' => 1,
    };

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

    $self->header_add('Content-Type','text/plain');
    
    if (@aspell_suggestions){
        return join("\n",map {decode_utf8($_)} @aspell_suggestions);
    }
    else {
        $logger->debug("Found $word in dictionary or no suggestions");
    }

    return;
}

1;
