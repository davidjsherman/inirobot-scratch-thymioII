#!/usr/bin/perl

use Cwd;

my $port = 3000;
my $aesl = cwd().'/thymio_motion.aesl';
my $asebascratch = cwd().'/../MacOS/asebascratch';
my @portlist = map { 'ser:device='.(split/ /)[1] } grep { /thymio.ii/i } `../MacOS/portlist`;

if (scalar(@ARGV)) {
    system("killall asebascratch asebahttp 2>/dev/null");
    exec ("\"$asebascratch\" -p $port -a \"$aesl\" $ARGV[0]")
      or die("couldn't exec $asebascratch: $!");
}
else {
    if (@portlist>0) {
        system("killall asebascratch asebahttp 2>/dev/null");
	exec("\"$asebascratch\" -p $port -a \"$aesl\" ".join(" ",@portlist)." >/dev/null 2>&1")
	  or die("couldn't exec $asebascratch: $!");
    }
}


