#####################################################################
#
#  OpenBib::Search::Local::Xapian
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Local::Xapian;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Apache::Request ();
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config = \%OpenBib::Config::config;

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

sub get_relevant_terms {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $category_ref       = exists $arg_ref->{categories}
        ? $arg_ref->{categories}        : undef;
    my $type               = exists $arg_ref->{type}
        ? $arg_ref->{type}              : undef;
    my $resultbuffer_ref   = exists $arg_ref->{resultbuffer}
        ? $arg_ref->{resultbuffer}      : undef;
    my $relevanttokens_ref = exists $arg_ref->{relevanttokens}
        ? $arg_ref->{relevanttokens}    : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fulltermsem_ref={};
    my $fullterm_ref=[];

    $logger->debug(YAML::Dump($relevanttokens_ref->{$type}));

    my $atime=new Benchmark;
    
    for (my $i=1; exists $relevanttokens_ref->{$type}[$i-1]{name} ; $i++){
        my $term=$relevanttokens_ref->{$type}[$i-1]{name};

        # Problematische Zeichen fuer Regexp herausfiltern
        $term=~s/\+//g;
        
        $logger->debug("Token: $term");
        foreach my $titlistitem_ref (@{$resultbuffer_ref}){
            foreach my $category (@{$category_ref}){
#                $logger->debug("Testing category $category");
                foreach my $thisterm_ref (@{$titlistitem_ref->{$category}}){
                    my $thisterm = $thisterm_ref->{content};
                    my $cmpterm;
                    if (exists $thisterm_ref->{contentnorm}){
                        $cmpterm  = $thisterm_ref->{contentnorm};
                    }
                    else {
                        $cmpterm  = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $thisterm,
                        });
                    }
                    if ($cmpterm=~m/$term/i){
                        next if (exists $fulltermsem_ref->{$thisterm});
                        $fulltermsem_ref->{$thisterm}=1;
                        $logger->debug("Found $thisterm");

                        push @{$fullterm_ref}, $thisterm;
                    }
                }
            }
        }
    }

    my $btime       = new Benchmark;
    my $timeall     = timediff($btime,$atime);
    $logger->debug("Time: ".timestr($timeall,"nop"));

    $logger->debug(YAML::Dump($fullterm_ref));
    return $fullterm_ref;
}


1;

