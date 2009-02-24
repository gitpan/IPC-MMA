use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $cflags  = `mm-config --cflags`;
my $ldflags = `mm-config --ldflags`;
my $libs    = `mm-config --libs`;
WriteMakefile(
    'NAME'	       => 'IPC::MMA',
    'VERSION_FROM' => 'MMA.pm',           # finds $VERSION
    'LIBS'	       => ["$ldflags $libs"], # e.g., '-lm' 
    'INC'	       => $cflags,            # e.g., '-I/usr/include/other'
    'OBJECT'       => 'mma_alloc.o MMA.o',
    'OPTIMIZE'     => '-O2',              # '-Os' for release, '-g' for debug
    'PREREQ_PM'    => {'Test::Warn'=>'0.11'}
);
