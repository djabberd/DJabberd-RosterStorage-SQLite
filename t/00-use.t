#!/usr/bin/perl
use strict;
use Test::More tests => 23;
use_ok("DJabberd::RosterStorage::SQLite");

use DJabberd::Log;
use DJabberd::JID;
use DJabberd::Callback;
use Data::Dumper;

my $rosterdb = "roster.sqlite";
my $my_roster;
my $my_item;
my @ops = ('');

my $r=DJabberd::RosterStorage::SQLite->new;
unlink($rosterdb) if(-f $rosterdb);
$r->set_config_database($rosterdb);
$r->finalize;
my $cb = DJabberd::Callback->new({
	set_roster => sub {
		my $cb = shift;
		$my_roster = shift;
	},
	done => sub {
		my $cb = shift;
		$my_item = shift;
	},
	error => sub {
		print STDERR Dumper([@_]);
	}
});
my $user = DJabberd::JID->new("user\@example.com");
$r->get_roster($cb,$user); # ver n/a
ok(ref($my_roster) && !$my_roster->items,"Check roster retrieval: is ".ref($my_roster));

my $ri = DJabberd::RosterItem->new(DJabberd::JID->new('user1@example.com'));
$cb->{_has_been_called} = 0;
$r->set_roster_item($cb,$user,$ri); # ver 1

push(@ops, 'INSERT');

ok(ref($my_item), "Submitted roster change, ".ref($my_item));
$cb->{_has_been_called} = 0;
$r->get_roster($cb,$user); # ver 1
ok(ref($my_roster) && scalar($my_roster->items) == 1 && ($my_roster->items)[-1]->ver == 1, "Roster contains new element, version increased to 1");

$ri->add_group('Allgemeine');
$cb->{_has_been_called} = 0;

push(@ops, 'UPDATE');
push(@ops, 'GRPADD');

$r->set_roster_item($cb,$user,$ri); # ver 2 (set) and 3 (group_add)
ok(ref($my_item), "Submitted roster change, ".ref($my_item));

$cb->{_has_been_called} = 0;
$r->get_roster($cb,$user); # ver 2
ok(ref($my_roster) && scalar($my_roster->items) == 1 && ($my_roster->items)[-1]->ver == 3, "Roster contains new element and group, version increased to 3");

$ri->{groups} = [];
$cb->{_has_been_called} = 0;

push(@ops, 'GRPDEL');
push(@ops, 'UPDATE');

$r->set_roster_item($cb,$user,$ri); # ver 4 (set) and 5 (group_del)
ok(ref($my_item), "Submitted roster change, ".ref($my_item));

$cb->{_has_been_called} = 0;
$r->get_roster($cb,$user); # ver 5
ok(ref($my_roster) && scalar($my_roster->items) == 1 && ($my_roster->items)[-1]->ver == 5, "Roster contains new element and no group, version increased to 5");

$ri->add_group('Privat');
$ri->add_group('Buddy');
$cb->{_has_been_called} = 0;

push(@ops, 'UPDATE');
push(@ops, 'GRPADD');
push(@ops, 'GRPADD');

$r->set_roster_item($cb,$user,$ri); # ver 6 (set) and 7,8 (group_add)
ok(ref($my_item), "Submitted roster change, ".ref($my_item));

$cb->{_has_been_called} = 0;
$r->get_roster($cb,$user); # ver 8
ok(ref($my_roster) && scalar($my_roster->items) == 1 && ($my_roster->items)[-1]->ver == 8, "Roster contains new element and groups, version increased to 8");

$cb->{_has_been_called} = 0;

push(@ops, 'GRPDEL');
push(@ops, 'GRPDEL');
push(@ops, 'DELETE');

$r->delete_roster_item($cb,$user,$ri); # ver 9 (del) and 10,11 (group_del)
ok(!ref($my_item), "Removed roster entry, ".ref($my_item));

$cb->{_has_been_called} = 0;
$r->get_roster($cb,$user); # ver 11
ok(ref($my_roster) && scalar($my_roster->items) == 1 && ($my_roster->items)[-1]->ver == 11 && ($my_roster->items)[-1]->remove, "Roster contains removed element, version increased to 11");

# Validate journal entries
my $sth = $r->{dbh}->prepare('SELECT * FROM journal');
$sth->execute;

while(my ($ver,$uid,$cid,$ts,$log) = $sth->fetchrow_array) {
	diag("$ver\t$uid\t$cid\t$ts\t$ops[$ver]\t[$log]\n");
	ok($log =~ /^$ops[$ver]/, "Validate journal operation ".$ver);
}
unlink($rosterdb);
