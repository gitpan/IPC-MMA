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

# test 9: process 1 sets a RD lock, sets var 7 or 8, others acknowledge 8 by setting 9, 10, 11
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
    $var = $id == 2 ? 10 : 11;
    while ($var < 11) {usleep 10}
}

# test 10: process 2 sets a RD lock, sets var 13-14, others ack 14 by setting 15, 16, 17
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
# at the start, processes 0, 1, 2 have read locks
$timer = 0;
            
if ($id==1) {
    # when process 1 sees process 0 set var to 18,
    #  it sets var to 19 then requests 
    #  an upgrade of its RD lock to RW
    while ($var < 18) {usleep 10}
    $var = 19;
    # this should lock up until 0 and 2 have released their locks, 
    #  and 3 has read-locked and then released 
    if (!mm_lock ($mm, MM_LOCK_RW)) {
        $var = 97;
        exit;
    }
    while ($var < 23 && $timer < 500) {
      $timer += 10;
      usleep 10; # let 3 store its 23
    }
    if ($var == 22) {
        $var = mm_unlock($mm) ? 24 : 91;
    } elsif ($var == 23) {
        $var = mm_unlock($mm) ? 26 : 91;
    }
    
} elsif ($id==3) {
    # a short while after process 3 (which has no lock at all) sees 20, 
    # it requests a read lock (1 will have gotten its write lock by then)  
    while ($var < 20) {usleep 10}
    usleep 100;
    if (!mm_lock($mm, MM_LOCK_RD)) {
        $var = 98;
        exit;
    }
    # when process 3 gets its read lock, it sets var to 21
    # and then waits a while to see if process 1 gets its WR lock and 
    # sets $var to 24
    $var = 21;
    while ($var < 24 && $timer < 1000) {
        $timer += 10;
        usleep 10;
    }
    if ($var == 22) {
        $var = mm_unlock($mm) ? 23 : 93;
    } elsif ($var == 24) {
        $var = mm_unlock($mm) ? 25 : 93;
    }
    
} elsif (!$id) {
    # when process 0 sees 19, it releases its read lock and 
    #  advances to 20
    # then it continues to wait until a timeout, or it sees one of 
    #  the terminating values
    $var = 18;
    while ($var < 25 && $timer < 4000) {
        if ($var == 19) {$var = mm_unlock($mm) ? 20 : 90}
        $timer += 10;
        usleep 10;
    }
    my $mes = $var==97 ? "id 1 couldn't upgrade read to write lock"
            : $var==98 ? "id 3 couldn't get read lock"
            : $var>=90 ? "id ".($var-90)." couldn't unlock"
            : $var< 25 ? "state got stuck at $var"
            : "id 1 write lock " 
            . ($var == 25 ? "was granted before a later id 3 read lock" 
                          : "had to wait for a later id 3 read lock");
    # report the test result (2 results are OK)
    ok ($var == 25 || $var == 26, $mes);

} else {
    # process 2: when it sees 21 it releases its read lock and 
    # advances to 22
    while ($var < 21) {usleep 10}
    $var = mm_unlock($mm) ? 22 : 92;
}
# success on test 11 means that a process can upgrade a read lock 
#   to a write lock without first releasing the read lock
#   but online words say this upgrade is subject to an interloper

# not a test: knock off the other processes and destroy the shared memory
if (!$id) {
    kill 9, $pid[1], $pid[2], $pid[3];
    mm_destroy ($mm);
}
