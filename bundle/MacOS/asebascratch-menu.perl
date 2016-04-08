#!/usr/bin/perl

use Cwd;

my $port = 3000;
my $aesl = cwd().'/thymio_motion.aesl';
my $asebascratch = cwd().'/../MacOS/asebascratch';
my @portlist = map { 'ser:device='.(split/ /)[1] } grep { /thymio.ii/i } `../MacOS/portlist`;

if (scalar(@ARGV)) {
    system("killall asebascratch asebascratch 2>/dev/null");
    system("\"$asebascratch\" -p $port -a \"$aesl\" $ARGV[0] &");
}
else {
    print join("\n", @portlist),"\n";
    if (system("killall -s asebascratch asebascratch >/dev/null 2>&1") && (@portlist>0)) {
	system("\"$asebascratch\" -p $port -a \"$aesl\" ".join(" ",@portlist)." >/dev/null 2>&1 &");
    }
}


