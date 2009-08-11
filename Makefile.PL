use ExtUtils::MakeMaker;
my $libpath = '/usr/local/lib';

if (!-e "$libpath/libmm.so") {
    use lib qw(inc);
    use Devel::CheckLib;

    print "\nIPC::MMA requires the mm library, which is available at http://www.ossp.org/pkg/lib/mm/\n";
    $libpath = prompt(" Please enter path to libmm.so:", $libpath);

    check_lib_or_exit(lib => 'mm', libpath => $libpath);
}
my $binpath = `which mm-config`;
chomp $binpath;
if (!$binpath) {
    print "installation requires mm-config, which should have been installed with the mm library\n";
    $binpath = prompt(" Please enter path to mm-config:");
    $binpath =~ s'(/(mm-config)?)?$'/';
}
my $cflags  = `${binpath}mm-config --cflags`;
my $ldflags = `${binpath}mm-config --ldflags`;
my $libs    = `${binpath}mm-config --libs`;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'         => 'IPC::MMA',
    'VERSION_FROM' => 'MMA.pm',           # finds $VERSION
    'LIBS'         => ["$ldflags $libs"], # e.g., '-lm' 
    'INC'          => $cflags,            # e.g., '-I/usr/include/other'
    'OBJECT'       => 'mma_alloc.o MMA.o',
    'OPTIMIZE'     => '-O2',              # '-Os' for release, '-g' for debug
    'PREREQ_PM'    => {'Test::Warn'=>'0.11'}
);
