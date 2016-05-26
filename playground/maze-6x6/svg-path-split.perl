#!/usr/bin/perl -w

use Math::Round qw(round);
use Math::Trig qw(acos rad2deg deg2rad);
use GD;

use XML::XPath;
use XML::XPath::XMLParser;

(my $base = shift) ||= "maze-6x6";
open(LOG,'>',"$base.log") or die($!);
open(PNG,'>',"$base.check.png") or die($!);
open(PLAYGROUND,'>',"$base.playground") or die($!);

my $door = "";
open(DOOR,'<',"$base.door.xml") and $door=join('',<DOOR>);

$im = new GD::Image(241,241);
$white = $im->colorAllocate(255,255,255);
$black = $im->colorAllocate(0,0,0);
$im->transparent($white);

prolog();

my $xp = XML::XPath->new(filename => "$base.svg");

my $nodeset = $xp->find('//g[@inkscape:label="Walls"]//path/@d'); # find all paragraphs

foreach my $node ($nodeset->get_nodelist) {
    my $d = XML::XPath::XMLParser::as_string($node);
    $d =~ s{.*?d=\"(.*)\".*?}{$1};

    my @F = map { ($_=~/-?\d+/) ? round($_/2.0) : $_ } split(/[,\s]/,$d);
    chomp @F;

    next unless ($d =~ /^m/);
    print LOG "# ---------- ",join(" ",@F)," ----------\n";

    my $cmd = shift @F;
    my $x = (shift @F) - 30;
    my $y = 486 - (shift @F);
    print LOG "\t\t\t\t# m start at $x $y\n";

    while (@F) {
	if ($F[0] eq 'L') {
	    $cmd = shift @F;
	    my $x2 = (shift @F) - 30;
	    my $y2 = 486 - (shift @F);
	    #print "# L line to $x2 $y2\n";
	    print LOG join("\t",$x,$y,$x2,$y2,
			   "# L line from $x $y to absolute $x2 $y2"),"\n";
	    $im->line($x,$y,$x2,$y2,$black);
	    wall($x,$y,$x2,$y2);
	    ($x,$y) = ($x2,$y2);
	}
	elsif ($F[0] eq 'l') {
	    print LOG "\t\t\t\t# l restart relative\n";
	    $cmd = shift @F;
	}
	else {
	    # print "# relative line $F[0] $F[1] to $x $y\n";
	    my $x2 = $x + $F[0];
	    my $y2 = $y - $F[1];
	    print LOG join("\t",$x,$y,$x2,$y2,
			   "# relative line $F[0] $F[1] from $x $y to $x2 $y2"),"\n";
	    $im->line($x,$y,$x2,$y2,$black);
	    wall($x,$y,$x2,$y2);
	    ($x,$y) = ($x2,$y2);
	    shift @F; shift @F;
	}
    }
}
binmode PNG;
print PNG $im->png;

epilog();

sub wall {
    my ($x1,$y1,$x2,$y2) = @_;
    my $mid_x = ($x1+$x2)/2;
    my $mid_y = ($y1+$y2)/2;
    my $length = sqrt(($x1-$x2)*($x1-$x2) + ($y1-$y2)*($y1-$y2));
    my ($l1,$l2,$angle);
    if ($x1 == $x2) {
	# vertical
	($l1,$l2) = (2, $length + 2);
    }
    elsif ($y1 == $y2) {
	# horizontal
	($l1,$l2) = ($length + 2, 2);
    }
    else {
	# angle
	($l1,$l2) = ($length + 2, 2);
	my $x = ($x2-$x1) * ($y2>$y1 ? 1.0 : -1.0);
	$angle = acos($x/$length);
    }
    printf PLAYGROUND
	sprintf("\t<wall x=\"%.2f\" y=\"%.2f\" l1=\"%.2f\" l2=\"%.2f\" h=\"%.2f\" color=\"%s\" %s/>\n",
		$mid_x,$mid_y, $l1,$l2, 10, "wall",
		(defined $angle ? sprintf("angle=\"%.3f\" ",$angle) : ""));
}

sub prolog {
    print PLAYGROUND << "END";
<!DOCTYPE aseba-playground>
<aseba-playground>
	<color name="white" r="1.0" g="1.0" b="1.0" />
	<color name="wall" r="0.9" g="0.9" b="0.9" />
	<color name="red" r="0.77" g="0.2" b="0.15" />
	<color name="green" r="0" g="0.5" b="0.17" />
	<color name="blue" r="0" g="0.38" b="0.61" />

	<world w="240" h="240" color="white" groundTexture="$base.png" />
	<thymio2 x="145" y="20" port="33333" angle="0.00" />
	<thymio2 x="220" y="180" port="33334" angle="1.57" />
END
}

sub epilog {
    print PLAYGROUND "$door" if $door;
    print PLAYGROUND << "END";
</aseba-playground>
END
}

# m 300,732.3622 0,60 20,20 60,0
# m 219.86665,712.15122 -19.98029,20.21098 -59.88636,0 0,0 0,0 0,0
# m 140,652.3622 -60,0 -20,-20 0,-120 20,-20 440,0 20,20 0.30491,120.36134 L 520,652.3622 l -60,0 -20,-20 0,-40 20,-20 -140,0 -20,20 0,140 -80,0 0,-70 0,-70 -20,-20 -60,0 0,0
# m 80,652.3622 -20,20 0,120 20,20 120,0 20,20 0.57595,40.15987
# m 540,672.3622 0,280 -20,20 -200,0 -20,-20
# m 80,812.3622 -20,20 0,120 20,20 80,0 20,-20 0,-40 -20,-20 0,0 0,0
# m 220,872.3622 20,20
# m 180,952.3622 20,20 80,0 20,-20 0,-40 20,-20 120,0 20,-20 0,-120 -20,-20 -40,0 -20,-20 0,-40
# m 520,652.3622 20,20
