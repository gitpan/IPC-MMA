#!/usr/local/bin/perl

# test lock features of IPC::MMA

use strict;
use warnings;
use Test::More tests => 11;
use Time::HiRes qw(usleep);

# test 1 is use_ok
BEGIN {use_ok ('IPC::MMA', qw(:basic :scalar))}

# test 2: create acts OK
my $mm = mm_create (1, '/tmp/test_lockfile');
if (!defined $mm || !$mm) {BAIL_OUT "can't create shared memory"}
ok (1, "create shared mem");

# test 3: create a scalar to talk to each other with
my $scalar = mm_make_scalar($mm);
if (!defined $scalar || !$scalar) {BAIL_OUT "can't create shared scalar"}
ok (1, "make scalar");

# test 4, tie it and initialize it
my $var;
if (!tie ($var, 'IPC::MMA::Scalar', $scalar)) {BAIL_OUT "Can't tie scalar"}
ok (1, "tie scalar");
$var = '00';

my ($id, $timer);
my @pid = ($$, $$, $$, $$);

# test 5: fork into 4 processes and make a process number $id 0 to 3
if (!defined ($pid[1] = fork)) {BAIL_OUT("can't fork into 2 processes")}
if ($pid[1]) {
    ok (1, "fork into 2 processes");
    if (!defined ($pid[2] = fork)) {BAIL_OUT("can't fork into 3 processes")}
    if ($pid[2]) {
        # test 6
        ok (1, "fork into 3 processes");
        if (!defined ($pid[3] = fork)) {BAIL_OUT("can't fork into 4 processes")}
        if ($pid[3]) {
            # test 7
            ok (1, "fork into 4 processes");
            $id = 0;
        } else {$id = 3}
    } else {$id = 2}
} else {$id = 1}

# test 8: process 0 sets a RD lock, sets var 1 or 2, others acknowledge 2 by setting 3, 4, 5
if (!$id) {
    $var = mm_lock($mm, MM_LOCK_RD) ? '02' : '01';
    $timer = 0;
    while ($var < 5 && $timer < 20000) {
        $timer += 10;
        usleep 10;    
    }
    cmp_ok ($var, '==', 5, "id 0 read lock");
    $var = '05';
} else {
    while ($var < $id + 1) {usleep 10}
    $var = sprintf ("%02d", $id + 2);
    while ($var < 5) {usleep 10}
}

# test 9: process 1 sets a RD lock, sets var 6 or 7, others acknowledge 7 by setting 8, 9, 10
if ($id==1) {
    while ($var < 6) {usleep 10}
    $var = mm_lock($mm, MM_LOCK_RD) ? '08' : '07';
    while ($var < 11) {usleep 10}
} elsif (!$id) {
    $var = '06';
    $timer = 0;
    while ($var < 11 && $timer < 20000) {
        if ($var == 8) {$var = '09'}
        $timer += 10;
        usleep 10;
    }    
    is ($var, 11, "id 1 read lock");
    $var = 11;
} else {
    while ($var < ($id+7)) {usleep 10}
    $var = $id + 8;
    while ($var < 11) {usleep 10}
}

# test 10: process 2 sets a RD lock, sets var 11-12, others ack 12 by setting 13, 14, 15
if ($id == 2) {
    while ($var < 12) {usleep 10}
    $var = mm_lock($mm, MM_LOCK_RD) ? 14 : 13;
    while ($var < 17) {usleep 10}
} elsif (!$id) {
    $var = 12;
    $timer = 0;
    while ($var < 17 && $timer < 20000) {
        if ($var == 14) {$var = 15}
        $timer += 10;
        usleep 10;
    }    
    is ($var, 17, "id 2 read lock");
    $var = 17;
} else {
    while ($var < ($id==1 ? 15 : 16)) {usleep 10}
    $var = $id == 1 ? 16 : 17;
    while ($var < 17) {usleep 10}
}
            
# test 11: upgrading a RD lock to RW
            
if ($id==1) {
    # at time 0 of test 11, id 1 sets var to 19 and requests 
    # an upgrade of its RD lock to RW
    while ($var < 18) {usleep 10}
    $var = 19;
    if (!mm_lock ($mm, MM_LOCK_RW)) {
        $var = 97;
        die "1 can't get RW lock";
    }
    usleep 200;  # let id 3 finish storing its value
    if ($var == 24) {
        $var = mm_unlock($mm) ? 26 : 25;
    } elsif ($var == 26) {
        $var = mm_unlock($mm) ? 30 : 29;
    }

} elsif ($id==3) {
    # when process 3 (which has no lock at all) sees 19, 
    # it requests a read lock.  
    while ($var < 19) {usleep 10}
    usleep 200; 

    if (!mm_lock($mm, MM_LOCK_RD)) {
        $var = 98;
        die "3 can't get RD lock";
    }
    # when id gets its read lock, it sets var to 20
    # and then waits up to 2000 for id 1 to get its WR lock and 
    # advance $var from 23 to 25.
    $var = 20;
    $timer = 0;
    while ($var < 26 && $timer < 2000) {
        $timer += 10;
        usleep 10;
    }
    if ($var == 24) {
        $var = mm_unlock($mm) ? 26 : 25;
    } elsif ($var == 26) {
        $var = mm_unlock($mm) ? 28 : 27;
    }
    
} elsif (!$id) {

    # when process 0 sees 20, it releases its read lock and 
    #  advances to 21 or 22 depending on the success of its unlock
    # then it continues to wait until a timeout, or it sees one of 
    #  the terminating values
    $var = 18;
    $timer = 0;
    while ($var < 27 && $timer < 8000) {
        if ($var == 20) {$var = mm_unlock($mm) ? 22 : 21}
        $timer += 10;
        usleep 10;
    }
    ok ($var == 28 || $var == 30, "id 1 write lock "
        . ($var == 28 ? "was granted before a later id 3 RD request" 
                      : $var == 30 ? "had to wait for a later id 3 RD request"
                                   : "test failed: got $var"));
} else {

    # when process 2 sees 22, it releases its read lock and 
    # advances to 23 or 24 depending on the success of its unlock
    while ($var < 22) {usleep 10}
    $var = mm_unlock($mm) ? 24 : 23;
}
# success on test 11 means that a process can upgrade a read lock 
#   to a write lock without first releasing the read lock
#   but online words says theis upgrade is subject to an interloper

# not a test: knock off the other processes and destroy the shared memory
if (!$id) {
    kill 9, $pid[1], $pid[2], $pid[3];
    mm_destroy ($mm);
}
