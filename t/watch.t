#!/usr/bin/env perl

use strict;
use warnings;

use Mango;
use MangoX::Queue;

use Test::More;

my $mango = Mango->new('mongodb://localhost:27017');
my $collection = $mango->db('test')->collection('mangox_queue_test');
$collection->remove;

my $queue = MangoX::Queue->new(collection => $collection);

# Note - no easy/sensible way to test blocking watch
# But we'll check it at least returns
my $id = enqueue $queue status => 'Complete', 'test';
watch $queue $id, 'Complete';
ok(1, 'Blocking watch returned');

# Single watch watching a single status

$id = enqueue $queue 'test';

watch $queue $id, 'Complete' => sub {
	ok(1, 'Job status is complete');
	Mojo::IOLoop->stop;
};

Mojo::IOLoop->timer(1 => sub {
	$collection->update({'_id' => $id}, { '$set' => {'status' => 'Complete'}});
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

# Single watch watching multiple statuses

$id = enqueue $queue 'test';
watch $queue $id, ['Complete','Failed'] => sub {
	ok(1, 'Job status is complete or failed');
	$collection->update({'_id' => $id}, { '$set' => {'status' => 'Pending'}});
	watch $queue $id, ['Complete','Failed'] => sub {
		ok(1, 'Job status is complete or failed');
		Mojo::IOLoop->stop;
	};
	Mojo::IOLoop->timer(1 => sub {
		$collection->update({'_id' => $id}, { '$set' => {'status' => 'Failed'}});
	});
};

Mojo::IOLoop->timer(1 => sub {
	$collection->update({'_id' => $id}, { '$set' => {'status' => 'Complete'}});
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

# Separate complete/failed watchs

$id = enqueue $queue 'test';

watch $queue $id, 'Complete' => sub {
	ok(1, 'Job status is complete');
	Mojo::IOLoop->timer(1 => sub {
		$collection->update({'_id' => $id}, { '$set' => {'status' => 'Failed'}});
	});
};
watch $queue $id, 'Failed' => sub {
	ok(1, 'Job status is failed');
	Mojo::IOLoop->stop;
};

Mojo::IOLoop->timer(1 => sub {
	$collection->update({'_id' => $id}, { '$set' => {'status' => 'Complete'}});
});

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;


done_testing;