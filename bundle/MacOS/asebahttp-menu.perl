#!/usr/bin/perl

use Cwd;

my $port = 3000;
my $aesl = cwd().'/thymio_motion.aesl';
my $asebahttp = cwd().'/../MacOS/asebahttp';
my @portlist = map { 'ser:device='.(split/ /)[1] } grep { /thymio.ii/i } `../MacOS/portlist`;

if (scalar(@ARGV)) {
    system("killall asebascratch asebahttp 2>/dev/null");
    system("\"$asebahttp\" -p $port -a \"$aesl\" $ARGV[0] &");
}
else {
    print join("\n",(@portlist<=1) ? @portlist : (@portlist, join(' ',@portlist))),"\n";
    if (system("killall -s asebascratch asebahttp >/dev/null 2>&1") && (@portlist>0)) {
	system("\"$asebahttp\" -p $port -a \"$aesl\" ".join(" ",@portlist)." >/dev/null 2>&1 &");
    }
}


