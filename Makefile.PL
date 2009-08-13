use lib inc; 
use Devel::AssertOS qw(Unix OS390 BeOS Cygwin);
use ExtUtils::MakeMaker;

my $libpath = '/usr/local/lib';

if (!-e "$libpath/libmm.so") {
    use Devel::CheckLib;

    print "\nIPC::MMA requires the mm library, which is available at http://www.ossp.org/pkg/lib/mm/\n";
    $libpath = prompt(" Please enter path to libmm.so:", $libpath);

    check_lib_or_exit(lib => 'mm', libpath => $libpath);
}
my $binpath = `which mm-config`;
chomp $binpath;
if ($binpath !~ m'^/') {
    print "installation requires mm-config, which should have been installed with the mm library\n";
    $binpath = prompt(" Please enter path to mm-config:");
    
    $binpath =~ s'(/(mm-config)?)?$'/mm-config';
    if (!-e $binpath || !-X $binpath) {
        warn "'$binpath' not found or not executable\n";
        exit;
}   }
my $cflags  = `$binpath --cflags`;
chomp $cflags;
my $ldflags = `$binpath --ldflags`;
chomp $ldflags;
my $libs    = `$binpath --libs`;
chomp $libs;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'         => 'IPC::MMA',
    'VERSION_FROM' => 'MMA.pm',           # finds $VERSION
    'LIBS'         => ["$ldflags $libs"], # e.g., '-lm' 
    'INC'          => $cflags,            # e.g., '-I/usr/include/other'
    'OBJECT'       => 'mma_alloc.o MMA.o',
    'OPTIMIZE'     => '-O2',              # '-Os' for release, '-g' for debug
    'PREREQ_PM'    => {'Test::Warn'=>'0.11', 'ExtUtils::ParseXS'=>'2.20_04'}
);
