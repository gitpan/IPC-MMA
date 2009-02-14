#!/usr/local/bin/perl

# program to test basics of IPC::MM::Array

use strict;
use warnings;
use Test::More tests => 9;

# test 1 is use_ok
BEGIN {use_ok ('IPC::MMA', qw(:basic))}

# test 2, print out the maxsize
my $maxsize = mm_maxsize();
ok (defined $maxsize && $maxsize, "get max shared mem size") and 

# test 3, try a create
my $mm = mm_create (1, '/tmp/test_lockfile');
ok (defined $mm && $mm, "created shared mem");

# test 4: see if available answers civilly
my $memsize = mm_available ($mm);
ok (defined $memsize && $memsize, "read available mem");

# test 5: get the allocation size
my $alloc_size = mm_alloc_size ($mm);
ok (defined $alloc_size && $alloc_size, "read allocation size");

# show the max and min shared memory size and allocation size
diag sprintf ("max shared mem size on this platform is %d (0x%X),\n"
. "                       min shared mem size is %d (0x%X), allocation unit is %d bytes\n",
                $maxsize, $maxsize, $memsize, $memsize, $alloc_size);

# test 4: see if available answers civilly
my $avail = mm_available ($mm);
ok (defined $avail && $avail, "read available mem");

# test 5: avail is reasonable
ok ($avail <= $memsize && $avail > $memsize * 0.95, "avail mem reasonable");

# test 6: lock returns 1
my $locked = mm_lock($mm, MM_LOCK_RW);
ok ($locked == 1, "lock(RW) returned 1");

# test 7: unlock returns 1
my $unlocked = mm_unlock($mm);
ok ($unlocked == 1, "unlock returned 1");

# not a test: destroy
mm_destroy $mm;
