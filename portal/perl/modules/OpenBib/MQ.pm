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
    my $session     = exists $arg_ref->{session}
        ? $arg_ref->{session}             : undef;

    my $queue      = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $payload_ref = exists $arg_ref->{payload}
        ? $arg_ref->{payload}             : {};

    my $logger = get_logger();
    
    my $mq = $self->get_mq;

    $mq->queue_declare(1, $queue);
    
    $mq->basic_qos(1, {prefetch_count => 1});
    
    my $callback_queue = $mq->queue_declare(1, '', {exclusive => 1});

    my $correlation_id = UUID::Tiny::create_uuid_as_string(UUID::Tiny::UUID_V4);

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
    
    $mq->publish(1, $queue, encode_json($payload_ref), undef, {
	reply_to       => $callback_queue,
	correlation_id => $correlation_id,
	delivery_mode  => 2,
		 });

#    $mq->disconnect();
    
    my $response_ref = {
	submitted      => 1,
	queue          => $queue,
	callback_queue => $callback_queue,
	correlation_id => $correlation_id,
    };
    
    if ($session){	
	$session->set_datacache_by_key("mq_$queue",$response_ref);
    }
    
    return $response_ref;
}

sub wait_for_job {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $session         = exists $arg_ref->{session}
        ? $arg_ref->{session}             : undef;

    my $queue           = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $logger = get_logger();
    
    my $mq = $self->get_mq;

    $mq->queue_declare(1, $queue);
    
    $mq->basic_qos(1, {prefetch_count => 1});
    
    $mq->consume(1, $queue, {no_ack => 0});

    $logger->info("Waiting for payloads");

    my $received_json_ref = { consumed => 0 };
    my $correlation_id;
    my $callback_queue;
    
    while (1) {
	my $received = $mq->recv(0);

	if ($received){	
	    eval {
		$received_json_ref = decode_json($received->{body});
	    };
	    
	    if ($@){
		$logger->error($@);
		last;
	    }
	    
	    $received_json_ref->{consumed} = 1;

	    $correlation_id = $received->{props}{correlation_id};
	    $callback_queue = $received->{props}{reply_to};

	    $mq->ack(1, $received->{delivery_tag});
		
	    $logger->info("Received payload ".YAML::Dump($received_json_ref));
	    last;
	}
    }

#    $mq->disconnect();

    return {
	correlation_id => $correlation_id,
	callback_queue => $callback_queue,
	payload        => $received_json_ref,
    };
}

sub check_for_job {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $session         = exists $arg_ref->{session}
        ? $arg_ref->{session}             : undef;

    my $queue           = exists $arg_ref->{queue}
        ? $arg_ref->{queue}               : undef;

    my $correlation_id  = exists $arg_ref->{correlation_id}
        ? $arg_ref->{correlation_id}      : undef;
    
    my $logger = get_logger();
    
    my $mq = $self->get_mq;
    
    $mq->basic_qos(1, {prefetch_count => 1});

    my $response_ref = { consumed => 0 };

    unless ($mq->get(1, $queue, { no_ack => 1})){   
	return $response_ref;
    }

    $logger->info("");
    $mq->consume(1, $queue);
    
    $logger->info("Queue $queue can be consumed");
    
    my $received_json_ref = { };
    
    my $callback_queue;
    
    my $received = $mq->recv(0);

    $logger->info("Received ".YAML::Dump($received));
    
    if ($received){	
	eval {
	    $received_json_ref = decode_json($received->{body});
	};
	
	if ($@){
	    $logger->error($@);
	    last;
	}
	
	$callback_queue = $received->{props}{reply_to};
	
	$logger->info("Received payload ".YAML::Dump($received_json_ref));

	if ($correlation_id eq $received->{props}{correlation_id}) {
	    $response_ref = {
		consumed       => 1,
		correlation_id => $correlation_id,
		callback_queue => $callback_queue,
		payload        => $received_json_ref,
	    };

	    #$mq->ack(1, $received->{delivery_tag});
	    	    
	    return $response_ref;
	}	
    }
    
    return $response_ref;
}

sub return_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $callback_queue = exists $arg_ref->{callback_queue}
        ? $arg_ref->{callback_queue}      : undef;

    my $payload_ref    = exists $arg_ref->{payload}
        ? $arg_ref->{payload}             : {};

    my $correlation_id = exists $arg_ref->{correlation_id}
        ? $arg_ref->{correlation_id}      : undef;

    my $logger = get_logger();
    
    my $mq = $self->get_mq;

    $mq->publish(
	1,
	$callback_queue,
	encode_utf8(encode_json($payload_ref)),
	undef,
	{
	    correlation_id => $correlation_id,
	    delivery_mode => 2,
	},
	);
    
#    $mq->disconnect();

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
