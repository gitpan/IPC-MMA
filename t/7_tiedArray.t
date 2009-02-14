#!/usr/local/bin/perl

# test tied array features of IPC::MMA

use strict;
use warnings;
use Test::More tests => 130;
use IPC::MMA qw(:basic :array);

use constant ALLOC_OVERHEAD => 8;
my $alloc_size;

# determine the expected effect on available memory of the argument value
sub mmLen {
  my $len = length(shift);
  if (!$len) {return 0} 
  return (($len - 1) | ($alloc_size - 1)) + 1;
}
# round a length up per the allocation size
sub round_up {
    return ((shift() - 1) | ($alloc_size - 1)) + 1;
}

our ($array, $var_size_bytes);
our (@mmArray, @checkArray);

sub randVar {
    my $ret = '';
    if ($_ = int(rand 256)) {sysread (RAND, $ret, $_)}
    return $ret;
}

# check the whole array
sub checkArray {
    my $testName = shift;
    my ($size, $size2);
    is ($size = scalar @mmArray, $size2 = scalar @checkArray,
        "$testName: size of test array and check array should match");
    if ($size2 < $size) {$size = $size2}
    for (my $i=0; $i < $size; $i++) {
        is ($mmArray[$i], $checkArray[$i],
            "$testName: element $i");
}   }

# compare 2 arrays
sub compArray {
    my ($array1ref, $array2ref, $testName) = @_;
    my ($size1, $size2);
    is ($size1 = scalar @$array1ref, $size2 = scalar @$array2ref, 
        "$testName: arrays should be same size");
    if ($size2 < $size1) {$size1 = $size2}
    for (my $i=0; $i <$size1; $i++) {
        is ($$array1ref[$i], $$array2ref[$i],
            "$testName: element $i")
}   }

open (RAND, "</dev/random") or die "Can't open /dev/random for read: $!\n";

# test 1: create acts OK
my $mm = mm_create ((1<<20) - 200, '/tmp/test_lockfile');
ok (defined $mm && $mm, 
    "create shared mem");

# test 2: see if available answers civilly
my $memsize = mm_available ($mm);
ok (defined $memsize && $memsize, 
    "read available mem");

# test 3: get the allocation size
$alloc_size = mm_alloc_size ($mm);
ok (defined $alloc_size && $alloc_size, 
    "read allocation size");

# the next may increase to 24 if we split out an options word
use constant MM_ARRAY_ROOT_USES => 20;
my $MM_ARRAY_ROOT_SIZE = round_up (MM_ARRAY_ROOT_USES);

# test 4: make a GP array
use constant ARRAY_SIZE => 64;
$array = mm_make_array ($mm, MM_ARRAY, ARRAY_SIZE);
ok (defined $array && $array, "make array");

@checkArray = ();

# test 5: tie it to a perl array
ok (tie (@mmArray, 'IPC::MM::Array', $array),
    "tie array");

# test 6: memory reqd
my $avail2 = mm_available ($mm);
$var_size_bytes = ($memsize - $avail2 - ALLOC_OVERHEAD*2 - $MM_ARRAY_ROOT_SIZE) / ARRAY_SIZE;

is ($var_size_bytes, int ($var_size_bytes), 
    "the computed variable size ($var_size_bytes) should be an integer");
my $expect = 0;

# tests 7-70: populate the array
my ($i, $rc, $bool, $bool2);
my $rand=0;
for ($i=0; $i < ARRAY_SIZE; $i++) {
    $rand = randVar;
    $checkArray[$i] = $rand;
    $mmArray[$i] = $rand;
    if (length($rand)) {$expect += ALLOC_OVERHEAD + mmLen ($rand)}
    ok (!($_ = mm_error() || ''),
        "'$_' in assigning to tied array at index $i");
}

# test 71
my $avail3 = mm_available ($mm);
is ($avail3 - $avail2, -$expect, 
    "effect of storing ".ARRAY_SIZE." array elements on available memory");
        
# tests 72: read back and check the array elements
is_deeply (\@mmArray, \@checkArray, "compare arrays after populating");

# test 73
ok ($mmArray[-1] eq $checkArray[-1],
    "element -1 should return last element");

# test 74: fetch returns undef outside the array
ok (!defined $mmArray[-(ARRAY_SIZE+1)], 
    "element ".(-(ARRAY_SIZE+1))." should be undef");

# test 75
ok (!defined $mmArray[ARRAY_SIZE], 
    "element ".ARRAY_SIZE." should be undef");

# test 76: test array status: entries
my ($entries, $shiftCount, $typeRet, $options) = mm_array_status ($array);
is ($entries, ARRAY_SIZE, 
    "array size returned by mm_array_status");

# test 77
is ($shiftCount, 0, 
    "shift count returned by mm_array_status");

# test 78
is ($typeRet, MM_ARRAY, 
    "array type returned by mm_array_status");

# test 79: array_status: options
is ($options, 0, 
    "options returned by mm_array_status");

# test 80
is (scalar @mmArray, ARRAY_SIZE, 
    "array size returned by scalar");

# test 81
ok (exists $mmArray[ARRAY_SIZE - 1], 
    "exists: should");

# test 82
ok (exists $mmArray[0], 
    "exists: should");

# test 83
ok (exists $mmArray[-1], 
    "exists: should");

# test 84
ok (!exists $mmArray[-(ARRAY_SIZE+1)], 
    "exists: shouldn't");

# test 85
ok (!exists $mmArray[ARRAY_SIZE], 
    "exists: shouldn't");

# test 86: delete the end element, see that it returns the right value
my $val;
is ($val = delete $mmArray[ARRAY_SIZE - 1], delete $checkArray[ARRAY_SIZE - 1], 
    "delete should return deleted value");
    
# test 87: delete at end reduces array size
is (scalar @mmArray, ARRAY_SIZE - 1, 
    "array size down by 1 after delete at end");
        
# test 88
$expect = length($val) ? ALLOC_OVERHEAD + mmLen($val) : 0;
my $avail4 = mm_available ($mm);
is ($avail4 - $avail3, $expect, 
    "effect of delete at end on avail mem");

# test 89: can't delete the same one twice
ok (!defined delete $mmArray[ARRAY_SIZE - 1], 
    "can't delete ".($entries - 1)." twice");

# test 90: array size again
is (scalar @mmArray, ARRAY_SIZE - 1, 
    "array size not changed by failing delete");

# test 91: middle delete 
my $delix = (ARRAY_SIZE >> 1) - 3;
is ($val = delete $mmArray[$delix], $checkArray[$delix],
    "delete element $delix should have returned element value");
    
# test 92: reading it should return undef
ok (!defined $mmArray[$delix],
    "deleted element should fetch undef");

# test 93
$expect = length($val) ? ALLOC_OVERHEAD + mmLen($val) : 0;
my $avail5 = mm_available ($mm);
is ($avail5 - $avail4, $expect, 
    "effect of deleting element $delix on avail mem");

# test 94
is (scalar @mmArray, ARRAY_SIZE - 1, 
    "array size not changed by delete in middle");

# make checkArray match
$checkArray[$delix] = undef;

# test 95
is_deeply (\@mmArray, \@checkArray, "compare arrays after middle delete");

# test 96: try pop
is ($val = pop @mmArray, pop @checkArray, 
    "pop both arrays");
$expect = length($val) ? ALLOC_OVERHEAD + mmLen($val) : 0;
# diag "expect = $expect";

# test 97
my $size;
($size, $shiftCount) = mm_array_status ($array);
is ($size, ARRAY_SIZE - 2, 
    "pop decreases array size by 1");

# test 98
is ($shiftCount, 0, 
    "pop should not affect shift count");

# test 99
is ($mmArray[ARRAY_SIZE-2], undef, 
    "get popped index should return undef");

# test 100
is_deeply (\@mmArray, \@checkArray, "compare arrays after pop");

# test 101
my $avail6 = mm_available ($mm);
is ($avail6 - $avail5, $expect, 
    "effect of pop on avail mem");

# test 102: push it back
is (push (@mmArray, $val), ARRAY_SIZE - 1, 
    "push array should return new array size");

push @checkArray, $val;

# test ???
################## come back to this someday ###############
# once in a while the push takes as many as 88 bytes more than it should

my $avail7 = mm_available ($mm);
#is ($avail7 - $avail6, -$expect,
#    "effect of push on avail mem (length is ".length($val)
#   .", alloc len ".mmLen($val).")");
    
# test 103
($size, $shiftCount) = mm_array_status ($array);
is ($size, ARRAY_SIZE - 1, 
    "push should increase array size by 1");

# test 104
is ($shiftCount, 0, 
    "push should not affect shift count");

# test 105
is_deeply (\@mmArray, \@checkArray, "compare arrays after push");

# test 106: try shift
is ($val = shift @mmArray, shift @checkArray,
    "value returned by shift");
    
# test 107
($size, $shiftCount) = mm_array_status ($array);
is ($size, ARRAY_SIZE - 2, 
    "shift should decrease array size by 1");
    
# test 108
is ($shiftCount, 1,
    "shift should increase shift count by 1");
    
# test 109
$expect = length($val) ? ALLOC_OVERHEAD + mmLen($val) : 0;
my $avail8 = mm_available ($mm);
is ($avail8 - $avail7, $expect,  
    "effect of shift on avail mem");

# test 110
is_deeply (\@mmArray, \@checkArray, "compare arrays after shift");

# test 111: unshift 7 elements into array
my @ioArray = ();
my $ioN = 7;
$i=0;
while (++$i <= $ioN) {push @ioArray, randVar}
is (unshift (@mmArray, @ioArray), $size + $ioN,
    "unshift $ioN should return new array size");

# test 112:
my ($newsize, $newshiftCount) = mm_array_status ($array);
is ($newsize, $size + $ioN,
    "unshift $ioN should increase array size by $ioN");

# test 113
is ($newshiftCount, $shiftCount - $ioN,
    "unshift $ioN should subtract $ioN from shift count");

# test 114: compare the resulting arrays
unshift (@checkArray, @ioArray);
is_deeply (\@mmArray, \@checkArray, "compare arrays after unshift $ioN");

# tests 115: splice out 9 
$ioN = 9;
@ioArray = splice (@mmArray, 38, $ioN);
is (scalar @ioArray, $ioN,
    "splice out $ioN should return correct number of elements");

# tests 116
my @ioArray2 = splice (@checkArray, 38, $ioN);
is_deeply (\@ioArray, \@ioArray2, "compare returned arrays from splice out ${ioN}s");

# test 117
$size = $newsize;
$shiftCount = $newshiftCount;
($newsize, $newshiftCount) = mm_array_status ($array);
is ($newsize, $size - $ioN, 
    "splice out $ioN should decrease array size by $ioN");
    
# test 118
is ($newshiftCount, $shiftCount,
    "splice out $ioN in middle should not affect shift count");

# tests 119
is_deeply (\@mmArray, \@checkArray, "compare arrays after splice out $ioN");

# test 120: splice the same data back in
ok (!defined(splice (@mmArray, 38, 0, @ioArray)), 
    "splice in $ioN without deletion should return undef");

# test 121
$size = $newsize;
$shiftCount = $newshiftCount;
($newsize, $newshiftCount) = mm_array_status ($array);
is ($newsize, $size + $ioN, 
    "splice in $ioN should increase array size by $ioN");

# test 122
is ($newshiftCount, $shiftCount,
    "splice in $ioN in middle should not affect shift count");

# tests 123
splice (@checkArray, 38, 0, @ioArray);
is_deeply (\@mmArray, \@checkArray, "compare arrays after splice in ${ioN}s");

# tests 124: splice out 21, add 2
$ioN = 21;
my @two = (randVar, randVar);
(@ioArray)  = splice (@mmArray, 3, $ioN, @two);
(@ioArray2) = splice (@checkArray, 3, $ioN, @two);
is (scalar @ioArray, $ioN,
    "splice out $ioN, add 2 should return $ioN elements");

# test 125
is_deeply (\@ioArray, \@ioArray2, "compare returned arrays from splice out");

# test 126
is_deeply (\@mmArray, \@checkArray, "after splice out $ioN");

# tests 127: splice in
ok (!defined(splice (@mmArray, 5, 0, @ioArray)),
    "splice in $ioN (no delete) should return undef");
    
# tests 128
splice (@checkArray, 5, 0, @ioArray);
is_deeply (\@mmArray, \@checkArray, "compare arrays after splice in ${ioN}s");

# test 129: clear the array and test effect on mem avail
my $avail9 = mm_available ($mm);
@mmArray = ();
my $avail10 = mm_available ($mm);
######## put back in
is ($avail10 - $avail9, $avail2 - $avail9,
    "effect of '= ()' on avail mem");
        
# test 130: free the MM_ARRAY and see that all is back to where we started
mm_free_array ($array);
my $avail99 = mm_available ($mm);
is ($avail99 - $avail10, $memsize - $avail10,
    "effect of mm_free_array on avail mem");

# not a test: destroy the shared memory
mm_destroy ($mm);
