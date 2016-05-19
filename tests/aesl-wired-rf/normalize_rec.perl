#!/usr/bin/perl -w

(my $doit = shift) ||= 0;
my $seen_reset = 0;
my $start_time = 0.0;

while (<>) {
    my @F = split/ /; push @F,qw(. .);

    $seen_reset |= ($F[2] eq "a002" || /a002 reset from 0/);
    $doit |= (($F[2] eq "a003" || /a003 run from 0/) && $seen_reset);
    next unless $doit;
    next if ($F[1] eq "cfc7" || /from 53191/);
    
    $start_time = $F[0]
	if (/run from 0/ || ($F[2] eq "a003") ||
	    (! $start_time && /^\d/ && $. <= 2));

    $_ =~ s{^(\d+\.\d+)}{ sprintf("%014.3f", $1 - $start_time) }e;

    print $_;
}
