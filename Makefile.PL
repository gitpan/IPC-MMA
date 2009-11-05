use lib inc; 
use Devel::AssertOS qw(Unix OS390 BeOS Cygwin);
use ExtUtils::MakeMaker;

my $binpath = 'mm-config';
if (system "which -s $binpath") {

    # mm-config is not in PATH, but maybe it's installed outside PATH
    print "$binpath not in PATH: trying to find it...\n";
    my $found;
    DIR: for ('/usr', glob("~")) {
        my $result = `find $_ -maxdepth 6 -name "$binpath" 2>/dev/null`;
        while ($result =~ m"^(\S*?/$binpath)$"mg) {
            if ($found = -X $1) {$binpath = $1; last DIR}
    }   }
    if (!$found) {
        print "IPC::MMA requires the mm library, including its $binpath utility\n";
        $binpath = prompt("Please enter path to $binpath (or just return to quit):");
        chomp $binpath;
        $binpath =~ s"(.)(/(mm-config)?)?$"$1/mm-config";

        if (!$binpath || !-e $binpath || !-X $binpath) {
            if ($binpath) {warn "'$binpath' not found or not executable\n"}
            warn "The mm library is available at http://www.ossp.org/pkg/lib/mm/\n";
            exit 0;
}   }   }
# mm-config provides parameters to link with the mm library
my $cflags = `$binpath --cflags`;
my $libs   = `$binpath --ldflags --libs`;
chomp $cflags, $libs;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'         => 'IPC::MMA',
    'INC'          => $cflags,            # e.g., '-I/usr/include/other'
    'LIBS'         => [$libs],            # e.g., '-lm' 
    'LICENSE'      => 'perl',
    'OBJECT'       => 'mma_alloc.o MMA.o',
    'OPTIMIZE'     => '-Os',              # '-Os' for release, '-g' for debug
    'PREREQ_PM'    => {'Test::Warn'=>'0.11', 'ExtUtils::ParseXS'=>'2.200401'},
    'VERSION_FROM' => 'MMA.pm'            # finds $VERSION
);
