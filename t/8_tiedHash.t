#!/usr/local/bin/perl

# test tied-hash features of IPC::MMA

use strict;
use warnings;
use Test::More tests => 142;

use constant ALLOC_OVERHEAD => 8;
my $alloc_size;

# determine the expected effect on available memory of the argument value
sub mmLen {
  return ((length(shift) - 1) | ($alloc_size - 1)) + 1;
}

# round a length up per the allocation size
sub round_up {
    return ((shift() - 1) | ($alloc_size - 1)) + 1;
}

our ($hash, $entries);
our %checkHash;

sub randStr {
    my $len = int(rand shift())+1; 
    my $ret = '';
    if ($len) {sysread (RAND, $ret, $len)}
    return $ret;
}

sub shoHex {
    my ($s) = @_;
    my $ret = '';
    while (my $c = substr ($s, 0, 1, '')) {
        $ret .= sprintf ("%02X", ord($c));
    }
    return $ret;
}

open (RAND, "</dev/random") or die "Can't open /dev/random for read: $!\n";

# test 1 is use_ok
BEGIN {use_ok ('IPC::MMA', qw(:basic :hash))}

# test 2: create acts OK
my $mm = mm_create ((1<<20) - 200, '/tmp/test_lockfile');
ok (defined $mm && $mm, "create shared mem");

# test 3: see if available answers civilly
my $memsize = mm_available ($mm);
ok (defined $memsize && $memsize, "read available mem = $memsize");

# test 4: get the allocation size
$alloc_size = mm_alloc_size ($mm);
ok (defined $alloc_size && $alloc_size, "read allocation size");

use constant MM_HASH_ROOT_USES => 12;
my $MM_HASH_ROOT_SIZE = round_up (MM_HASH_ROOT_USES);

# test 5: make a hash
use constant DELTA_ENTRIES => 64;
$hash = mm_make_hash ($mm, DELTA_ENTRIES);
ok (defined $hash && $hash, "make hash");

# the check hash
%checkHash = ();        

# test 6: memory reqd
my $avail2 = mm_available ($mm);
my $ptr_size_bytes=($memsize-$avail2-2*ALLOC_OVERHEAD-$MM_HASH_ROOT_SIZE)/DELTA_ENTRIES;

is ($ptr_size_bytes, int ($ptr_size_bytes), 
    "the computed pointer size ($ptr_size_bytes) should be an integer");

# test 7: tie the hash
my %tiedHash;
ok (tie (%tiedHash, 'IPC::MMA::Hash', $hash), "tie hash");

# tests 8-71: populate the tied and check hashes
my ($i, $key, $value, $exists, $dups);
my ($keyBlockSize, $oldValBlockSize, $newValBlockSize, $decreased);
my $incFrom = my $incTo = '';
my $expect = $entries = $dups = $decreased = 0;
 
do {
    $key = randStr(16);
    $value = randStr(256);
    
    is ($exists = exists $tiedHash{$key}, exists $checkHash{$key},
        "key ". shoHex($key) . " (" . ($entries + $dups)
        . ") existance in tied hash vs. existance in check hash");
    
    $oldValBlockSize = $exists ? round_up (length $tiedHash{$key}) : 0;
    $keyBlockSize = round_up ($ptr_size_bytes + length($key));    
    $newValBlockSize = round_up (length($value));
    
    $tiedHash{$key} = $value;
    $checkHash{$key} = $value;
    
    if ($_ = mm_error()) {
        diag "$_ at mm_hash_store (".($entries + $dups)."), key=".shoHex($key).")";
    }
    # add in the memory contribution of this entry
    if ($exists) {
        $expect += $newValBlockSize - $oldValBlockSize;
        # keep track of how much we have decreased value-block sizes
        if ($newValBlockSize < $oldValBlockSize) {
            $decreased += $oldValBlockSize - $newValBlockSize;
        } else {
            $incTo   = $newValBlockSize;
            $incFrom = $oldValBlockSize;
        }
        $dups++;
        # quietly sneak another entry in to keep the number of tests constant
        do {$key = randStr(16)} until (!exists $tiedHash{$key});
        $keyBlockSize = round_up ($ptr_size_bytes + length($key));
        $tiedHash {$key} = $value; 
        $checkHash{$key} = $value;
    }
    $expect += $keyBlockSize + $newValBlockSize + 2*ALLOC_OVERHEAD;
    $entries++;
} until ($entries == DELTA_ENTRIES);

#if ($dups) {diag "$dups duplicate keys ($lt <) occurred in "
#                    . DELTA_ENTRIES ." random 1-16 byte keys"}

# test 72
my $avail3 = mm_available ($mm);
my $got = $avail3 - $avail2;
ok ($got <= -$expect
 && $got >= -$expect - 128,  # subject to random shortages (replaced $decreased) 
    "effect of stores on avail mem: got $got, expected -$expect, "
  . "decreased $decreased, incFrom $incFrom, incTo $incTo");
    
# test 73
my $mmEntries = scalar (%tiedHash);
is ($mmEntries, $entries, 
    "entries reported by scalar(tied hash) vs. count in this test");

# test 74
is ($mmEntries, scalar(keys(%checkHash)), 
    "same number of entries in tied hash and check hash");

# test 75: compare the two hashes against each other, 
is_deeply (\%tiedHash, \%checkHash, "compare hashes after populating");

my @keys = keys (%tiedHash);

# second-last thing to check is delete
# test 76
my $delKey = $keys[$#keys - 1];
my $delVal;
ok (($delVal = delete ($tiedHash{$delKey})) eq delete($checkHash{$delKey}),
    "delete 2nd-last returns same value as delete same key from check Hash");

# test 77
is ($mmEntries = scalar(%tiedHash), --$entries,
    "hash should contain 1 less entry");

# test 78
my $avail4 = mm_available ($mm);
my $delta4 = ALLOC_OVERHEAD + round_up ($ptr_size_bytes + length($delKey))
           + (length($delVal) ? ALLOC_OVERHEAD + mmLen($delVal) : 0);
           
is ($avail4 - $avail3, $delta4,
    "effect of delete 2nd-last on available memory");
$expect -= $delta4;

# test 79-140: check that keys(%tiedHash) returns sorted array
my $prevKey = $keys[0];
for ($i = 1; $i < $mmEntries; $i++) {
    $key = $keys[$i];
    ok ($prevKey lt $key, "keys[" . ($i-1) . "]=" . shoHex($prevKey)
           . " < keys[$i]=" . shoHex($key));
    $prevKey = $key;
}

# test 141: clear the hash and test effect on mem avail
%tiedHash = ();
my $avail9 = mm_available ($mm);

is ($avail9, $avail2,  
    "after mm_hash_clear, avail mem should be what it was after mm_make_hash");
        
# test 142: free the MM_ARRAY and see that all is back to where we started
mm_free_hash ($hash);
my $avail99 = mm_available ($mm);
is ($avail99, $memsize,
    "after mm_free_hash, avail mem should be what it was before mm_make_hash");

# not a test: destroy the shared memory
mm_destroy ($mm);
