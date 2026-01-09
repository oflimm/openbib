#####################################################################
#
#  OpenBib::MQ
#
#  Message Queue fuer asynchrone Bearbeitung langlaufender Aufgaben
#
#  Dieses File ist (C) 2026 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::MQ;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Cache::Memcached::Fast;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use Net::AMQP::RabbitMQ;
use POSIX;
use UUID::Tiny;
use YAML::Syck;

use OpenBib::Config;

$SIG{'PIPE'} = 'IGNORE'; # Prevent SSL problem, see: https://metacpan.org/pod/Net::AMQP::RabbitMQ#connect(-%24hostname%2C-%24options-)

sub new {
    my $class   = shift;
    my $arg_ref = shift;
    
    my $config     = exists $arg_ref->{config}
        ? $arg_ref->{config}                : OpenBib::Config->new;
    
    my $logger = get_logger();

    my $self = {};

    bless ($self, $class);

    my $mqconfig = $config->get('rabbitmq');
    
    my $mq = Net::AMQP::RabbitMQ->new();

    $mq->connect($mqconfig->{server}, { user => $mqconfig->{user}, password => $mqconfig->{password} });

    $mq->channel_open(1);
    
    $self->{_config} = $config;
    $self->{_mqconfig} = $mqconfig;
    $self->{_mq} = $mq;
    
    return $self;
}

sub submit_job {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queue      = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $payload_ref = exists $arg_ref->{payload}
        ? $arg_ref->{payload}             : {};

    my $job_id          = exists $arg_ref->{job_id}
        ? $arg_ref->{job_id}              : undef;

    my $logger = get_logger();

    # Job cached? No Message
    if ($self->job_processed({ queue => $queue, job_id => $job_id})){
	my $response_ref = {
	    submitted => 1,
	    queue     => $queue,
	    job_id    => $job_id,
	};
        
	return $response_ref;
    }
    
    my $mq = $self->get_mq;

    $mq->queue_declare(1, $queue);

    # Add job_id
    $payload_ref->{meta} = {
	job_id => $job_id,
    };
    
    my $encoded_payload_ref = {};

    eval {
	$encoded_payload_ref = encode_json($payload_ref);
    };

    if ($@){
	$logger->error($@);
	return {
	    submitted => 0,
	};
    }

    eval {
	$mq->publish(1, $queue, encode_json($payload_ref));
    };

    unless ($@){
	my $response_ref = {
	    submitted => 1,
	    queue     => $queue,
	    job_id    => $job_id,
	};
        
	return $response_ref;
    }    
}

sub consume_job {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $session     = exists $arg_ref->{session}
        ? $arg_ref->{session}             : undef;

    my $queue      = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $logger = get_logger();
    
    my $mq = $self->get_mq;

    $mq->queue_declare(1, $queue);
    
    $mq->basic_qos(1, {prefetch_count => 1});

    $mq->consume(1, $queue, {no_ack => 0});

    my $response_ref = { consumed => 0 };
    
    while (1) {
	my $received = $mq->recv(0);

	if ($received){
	    my $received_json_ref;
	    
	    eval {
		$received_json_ref = decode_json($received->{body});
	    };
	    
	    if ($@){
		$logger->error($@);
		last;
	    }
	
	    $logger->debug("Received payload ".YAML::Dump($received_json_ref));

	    if ($received_json_ref->{meta}{job_id}){
		$response_ref = {
		    consumed       => 1,
		    job_id         => $received_json_ref->{meta}{job_id},
		    payload        => $received_json_ref,
		};
		
		$mq->ack(1, $received->{delivery_tag});

		last;
	    }
	}
    }

    return $response_ref;
}

sub job_processed {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $session         = exists $arg_ref->{session}
        ? $arg_ref->{session}             : undef;

    my $queue           = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $job_id          = exists $arg_ref->{job_id}
        ? $arg_ref->{job_id}              : undef;
    
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my $memc_key = "mq:$queue:$job_id";

    if ($config->{memc} && $config->{memc}->get($memc_key)){
	return 1;
    }

    return 0;
}

sub get_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queue           = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $job_id          = exists $arg_ref->{job_id}
        ? $arg_ref->{job_id}              : undef;

    my $logger = get_logger();

    my $config = $self->get_config;

    my $memc_key = "mq:$queue:$job_id";

    $$logger->debug("Hole Ergebnis fuer $memc_key");
    
    if ($config->{memc}){
	return $config->{memc}->get($memc_key) if ($config->{memc}->get($memc_key));
    }
    else {
	$logger->fatal("Keine Verbindung zu Memecached");
    }

    return;
}

sub set_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queue       = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $job_id      = exists $arg_ref->{job_id}
        ? $arg_ref->{job_id}              : undef;

    my $payload_ref = exists $arg_ref->{payload}
        ? $arg_ref->{payload}             : {};
    
    my $logger = get_logger();

    my $config = $self->get_config;

    my $memc_key = "mq:$queue:$job_id";

    if ($config->{memc}){
	$$logger->debug("Setting result for $memc_key: ".YAML::Dump($payload_ref));
	
	$config->{memc}->set($memc_key,$payload_ref,$self->{memcached_expiration}{$memc_key});
    }
    else {
	$logger->fatal("Keine Verbindung zu Memecached");
    }

    return;
}

sub get_config {
    my $self = shift;

    return $self->{_config};
}

sub get_mqconfig {
    my $self = shift;

    return $self->{_mqconfig};
}

sub get_mq {
    my $self = shift;

    return $self->{_mq};
}

sub DESTROY {
    my $self = shift;

    $self->get_mq->disconnect();
}

1;
