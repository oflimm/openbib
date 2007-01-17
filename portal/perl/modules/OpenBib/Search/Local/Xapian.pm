#####################################################################
#
#  OpenBib::Search::Local::Xapian
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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
use Search::Xapian;
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

sub new {
    my $class = shift;

    my $self = { };

    bless ($self, $class);

    return $self;
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

sub initial_search {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $searchquery_ref   = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref} : undef;
    my $serien            = exists $arg_ref->{serien}
        ? $arg_ref->{serien}        : undef;
    my $enrich            = exists $arg_ref->{enrich}
        ? $arg_ref->{enrich}        : undef;
    my $enrichkeys_ref    = exists $arg_ref->{enrichkeys_ref}
        ? $arg_ref->{enrichkeys_ref}: undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my $qp = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");
    
    my $querystring = lc($searchquery_ref->{fs}{norm});
    
    $querystring    = OpenBib::Common::Util::grundform({
        content  => $querystring,
    });
        
    $qp->set_default_op(Search::Xapian::OP_AND);
    $qp->add_prefix('inauth'   ,'X1');
    $qp->add_prefix('intitle'  ,'X2');
    $qp->add_prefix('incorp'   ,'X3');
    $qp->add_prefix('insubj'   ,'X4');
    $qp->add_prefix('insys'    ,'X5');
    $qp->add_prefix('inyear'   ,'X7');
    $qp->add_prefix('inisbn'   ,'X8');
    $qp->add_prefix('inissn'   ,'X9');
    
    my $enq       = $dbh->enquire($qp->parse_query($querystring));
    my $thisquery = $enq->get_query()->get_description();
    my @matches   = $enq->matches(0,99999);

    $logger->debug("DB: $database");
    
    $logger->debug("Matches: ".YAML::Dump(\@matches));
    
    $self->{_querystring} = $querystring;
    $self->{_enq}         = $enq;
    $self->{_matches}     = \@matches;

    $logger->info("Running query ".$self->{_querystring});

    $logger->info("Found ".scalar(@matches)." matches");
    return;
}

sub matches {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($self->{_matches}));
    return @{$self->{_matches}};
}

sub querystring {
    my $self=shift;
    return $self->{_querystring};
}

sub enq {
    my $self=shift;
    return $self->{_enq};
}

sub DESTROY {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $logger->debug("dying");
}

1;

