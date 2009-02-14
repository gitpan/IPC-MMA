#!/usr/local/bin/perl

# program to test scalars under IPC::MMA

use strict;
use warnings;
use Test::More tests => 23;
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

# test 3 alloc size answers civilly 
$alloc_size = mm_alloc_size ($mm);
ok (defined $alloc_size && $alloc_size, "alloc size is $alloc_size");

# test 4: make a scalar
my $scalar = mm_make_scalar ($mm);
ok (defined $scalar && $scalar, "make scalar");

# test 5: available should be less by the right amount
my $avail2 = mm_available ($mm);
cmp_ok ($avail2 - $memsize, '==', -(SCALAR_SIZE + ALLOC_OVERHEAD), 
    "effect on available mem is " . ($avail2 - $memsize));

# test 6: set the scalar value
my $val = "0123456789ABCD";
my $rc = mm_scalar_store ($scalar, $val);
ok (defined $rc && $rc, 
    sprintf ("set scalar to %d-byte string", length $val));

# test 7: see how much the set scalar took
my $avail3 = mm_available ($mm);
my $expect = -(ALLOC_OVERHEAD + mmLen($val));
cmp_ok ($avail3 - $avail2, '==', $expect,  
    "effect on available mem is " . ($avail3 - $avail2) . " (expected $expect)");

# test 9: read it back and compare
my $val1 = mm_scalar_fetch ($scalar);
is ($val1, $val, "check scalar (1)");

# test 9: set it to a longer string 
my $val2 = "FEDCBA9876543210123";
# diag mm_var_show ($val2);
$rc = mm_scalar_store ($scalar, $val2);
ok (defined $rc && $rc, 
    sprintf ("set scalar to longer (%d-byte) string", length $val2));

# test 10: avail should have gone down by difference in length
my $avail4 = mm_available ($mm);
$expect = mmLen ($val) - mmLen ($val2);
is ($avail4 - $avail3, $expect, "effect of (increasing size) on available mem");

# test 11: read it back
my $val3 = mm_scalar_fetch ($scalar);
is ($val3, $val2, "check scalar (2)");

# test 12: set it to a shorter string 
my $val4 = "Z12345";
$rc = mm_scalar_store ($scalar, $val4);
ok (defined $rc && $rc, 
    "set scalar to shorter (".(length $val4)."-byte) string");
    
# test 13: read back and compare the shorter scalar
my $val5 = mm_scalar_fetch ($scalar);
is ($val5, $val4, "check scalar (3)");

# test 14: effect on available memory
# malloc drops a total-16 block into a total-24 hole and can't give back the 8
$expect = mmLen($val2) - mmLen($val4) - $alloc_size;
my $avail5 = mm_available($mm);
is ($avail5 - $avail4, $expect, 
    "effect of store shorter string on avail mem");

# test 15: make another scalar
my $scalar2 = mm_make_scalar ($mm);
ok (defined $scalar2 && $scalar2, "make scalar (2)");

# test 16: check effect on available memory
my $avail6 = mm_available($mm);
$expect = -(SCALAR_SIZE + ALLOC_OVERHEAD);
my $create2nd = $avail6 - $avail5;
ok ($create2nd <= $expect && $create2nd >= $expect-8, 
   "effect of (creating 2nd scalar) on avail mem was $create2nd");

# test 17: set the first scalar to a long value
my $val6 = 'x' x (($avail6 >> 1) + 70);
$rc = mm_scalar_store ($scalar, $val6);
ok (defined $rc && $rc, 
    sprintf ("set scalar to very long (%d-byte) string", length $val6));
    
# test 18: read it back and compare
my $val7 = mm_scalar_fetch ($scalar);
is ($val7, $val6, "check long scalar");

# test 19: test effect on available memory
# we get back the 8 that were lost for test 14
my $avail7 = mm_available ($mm);
$expect = mmLen ($val4) - mmLen ($val6) + $alloc_size;
is ($avail7 - $avail6, $expect, "effect of (setting scalar long) on available mem");

# test 20: should not be able to set the second scalar to the long value
warning_like {$rc = mm_scalar_store ($scalar2, $val6)} qr/out of memory/, 
    "should give warning";

# test 21: returned false
ok (defined $rc && !$rc, 
    "should not have been able to set another scalar to long value");

# test 22: free the second scalar, check the effect
mm_free_scalar ($scalar2);
my $avail8 = mm_available ($mm);
$expect = -$create2nd;
is ($avail8 - $avail7, $expect, "effect of (freeing 2nd scalar) on avail mem");

# test 23: free the scalar
mm_free_scalar ($scalar);
my $avail9 = mm_available ($mm);
$expect = $avail8 - $memsize;
is ($avail8 - $avail9, $expect, "effect of (freeing scalar) on avail mem");

# not a test: destroy the shared memory
mm_destroy ($mm);
