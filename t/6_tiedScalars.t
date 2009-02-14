#!/usr/local/bin/perl

# program to test tied scalars under IPC::MMA

use strict;
use warnings;
use Test::More tests => 19;
use Test::Warn;
use IPC::MMA qw(:basic :scalar);

# all sizes round to mult of 8
use constant SCALAR_SIZE => 8;
use constant ALLOC_OVERHEAD => 8;

my $alloc_size;

# determine the expected effect on available memory of the argument value
sub mmLen {
  return ((length(shift) - 1) | ($alloc_size - 1)) + 1;
}

# test 1: create acts OK
my $mm = mm_create (1, '/tmp/test_lockfile');
ok (defined $mm && $mm, "created shared mem");

# test 2: see if available answers civilly
my $memsize = mm_available ($mm);
ok (defined $memsize && $memsize, "read available mem");

$alloc_size = mm_alloc_size ($mm);

# test 3: make a scalar
my $scalar = mm_make_scalar ($mm);
ok (defined $scalar && $scalar, "make scalar");

# test 4: available should be less by the right amount
my $avail2 = mm_available ($mm);
cmp_ok ($avail2 - $memsize, '==', -(SCALAR_SIZE + ALLOC_OVERHEAD), 
    "effect on available mem is " . ($avail2 - $memsize));

# test 5: tie the scalar
ok (tie(my $tiedScalar, 'IPC::MM::Scalar', $scalar), "tie scalar");

# test 6: set the scalar value, see how much memory it took
my $val = "0123456789ABCD";
$tiedScalar = $val;

my $avail3 = mm_available ($mm);
my $expect = -(ALLOC_OVERHEAD + mmLen($val));
cmp_ok ($avail3 - $avail2, '==', $expect,  
    "effect on available mem is " . ($avail3 - $avail2) . " (expected $expect)");

# test 7: read it back and compare
my $val1 = $tiedScalar;
is ($val1, $val, "check scalar (1)");

# test 8: set it to a longer string 
#  avail should have gone down by difference in length
my $val2 = "FEDCBA9876543210123";
$tiedScalar = $val2;
my $avail4 = mm_available ($mm);
$expect = mmLen ($val) - mmLen ($val2);
is ($avail4 - $avail3, $expect, "effect of (increasing size) on available mem");

# test 9: read it back
my $val3 = $tiedScalar;
is ($val3, $val2, "check scalar (2)");

# test 10: set it to a shorter string 
#  read back and compare the shorter scalar
my $val4 = "Z12345";
$tiedScalar = $val4;
my $val5 = mm_scalar_fetch ($scalar);
is ($val5, $val4, "check scalar (3)");

# test 11: effect on available memory
# malloc drops a total-16 block into a total-24 hole and can't give back the 8
$expect = mmLen($val2) - mmLen($val4) - $alloc_size;
my $avail5 = mm_available($mm);
is ($avail5 - $avail4, $expect, 
    "effect of store shorter string on avail mem");

# test 12: make another scalar
my $scalar2 = mm_make_scalar ($mm);
ok (defined $scalar2 && $scalar2, "make scalar (2)");

# test 13: tie it
ok (tie(my $tiedScalar2, 'IPC::MMA::Scalar', $scalar2), "tie scalar2");

# test 14: check effect on available memoery
my $avail6 = mm_available($mm);
$expect = -(SCALAR_SIZE + ALLOC_OVERHEAD);
my $create2nd = $avail6 - $avail5;
ok ($create2nd <= $expect && $create2nd >= $expect-8, 
   "effect of (creating 2nd scalar) on avail mem was $create2nd");

# test 15: set the first scalar to a long value
#  read it back and compare
my $val6 = 'x' x (($avail6 >> 1) + 70);
$tiedScalar = $val6;
my $val7 = $tiedScalar;
is ($val7, $val6, "check long scalar");

# test 16: test effect on available memory
# we get back the 8 that were lost for test 11
my $avail7 = mm_available ($mm);
$expect = mmLen ($val4) - mmLen ($val6) + $alloc_size;
is ($avail7 - $avail6, $expect, "effect of (setting scalar long) on available mem");

# test 17: should not be able to set the second scalar to the long value
warning_like {$tiedScalar2 = $val6} qr/out of memory/, 
    "should give warning";

# test 18: returned false
#  free the second scalar, check the effect
mm_free_scalar ($scalar2);
my $avail8 = mm_available ($mm);
$expect = -$create2nd;
is ($avail8 - $avail7, $expect, "effect of (freeing 2nd scalar) on avail mem");

# test 19: free the scalar
mm_free_scalar ($scalar);
my $avail9 = mm_available ($mm);
$expect = $avail8 - $memsize;
is ($avail8 - $avail9, $expect, "effect of (freeing scalar) on avail mem");

# not a test: destroy the shared memory
mm_destroy ($mm);
