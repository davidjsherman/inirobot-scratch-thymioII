#!/usr/bin/perl -w

use Math::Round qw(round nearest);
use Math::Trig qw(acos rad2deg deg2rad);
use GD;
use Data::Dumper;

use XML::XPath;
use XML::XPath::XMLParser;
use Image::SVG::Path qw(extract_path_info);

(my $base = shift) ||= "maze-6x6";
open(LOG,'>',"$base.log") or die($!);
open(PNG,'>',"$base.check.png") or die($!);
open(PLAYGROUND,'>',"$base.playground") or die($!);

my $door = "";
open(DOOR,'<',"$base.door.xml") and $door=join('',<DOOR>);

my $xp = XML::XPath->new(filename => "$base.svg");

my $width = get_attribute($xp, 'width', 240);
my $height = get_attribute($xp, 'height', 240);
my @viewBox = get_attribute($xp, 'viewBox', '0 0 240 240');
my @scale = ( $width/($viewBox[2]-$viewBox[0]), $height/($viewBox[3]-$viewBox[1]));
print STDERR "w $width h $height v ",join(' ',@viewBox),"; scale = $scale[0] $scale[1]\n";

$im = new GD::Image($width,$height);
$white = $im->colorAllocate(255,255,255);
$black = $im->colorAllocate(0,0,0);
$im->transparent($white);

prolog();

my @origin = (0,0);
@origin = find_origin('//g[@inkscape:label="Walls"]/@transform');
print STDERR "wall transform $origin[0] $origin[1]\n";

my $pathset = $xp->find('//g[@inkscape:label="Walls"]//path'); # find all paths

foreach my $path ($pathset->get_nodelist) {
    my $d = $xp->findvalue('@d',$path);
    print STDERR "d=$d\n";
    my @d = extract_path_info ($d);

    print LOG "# ---------- ",join(" ",map { $_->{point}->[0], $_->{point}->[1] } @d)," ----------\n";

    my ($x0,$y0, $x1,$y1, $x2,$y2);
    foreach my $cmd (@d) {
	if ($cmd->{type} eq 'moveto') {
	    ($x1,$y1) = ($x0,$y0) = get_point($cmd,'absolute');
	    print LOG "\t\t\t\t# m start at $x1 $y1\n";
	}
	elsif ($cmd->{type} eq 'line-to') {
	    ($x2,$y2) = get_point($cmd,$cmd->{position});
	    ($x2,$y2) = ($x1+$x2, $y1+$y2) if ($cmd->{position} eq 'relative');
	    $im->line($x1,$y1,$x2,$y2,$black);
	    wall($x1,$y1,$x2,$y2);
	    print LOG join("\t",$x1,$y1,$x2,$y2,
			   join(" ", "# Line from $x1 $y1 to $x2 $y2",
				"(",$cmd->{position},$cmd->{point}->[0], $cmd->{point}->[1],")")),"\n";
	    ($x1,$y1) = ($x2,$y2);
	}
	elsif ($cmd->{type} eq 'closepath') {
	    ($x1,$y1, $x2,$y2) = ($x2,$y2, $x0,$y0);
	    $im->line($x1,$y1,$x2,$y2,$black);
	    wall($x1,$y1,$x2,$y2);
	    print LOG join("\t",$x1,$y1,$x2,$y2, "# Close path from $x1 $y1 back to $x2 $y2"),"\n";
	}
    }
}

find_origin('//g[@inkscape:label="Robots"]/@transform');
print STDERR "robots transform $origin[0] $origin[1]\n";

my $robotset = $xp->find('//g[@inkscape:label="Robots"]//rect'); # find all paths
my @robots = map { [ map_point($_->getAttribute('x'),$_->getAttribute('y'),'absolute') ] } $robotset->get_nodelist;
my $port = 33333;
@robots = ( [145,20], [220,180] ) unless (@robots);
print PLAYGROUND
    sprintf("\t<thymio2 x=\"%.2f\" y=\"%.2f\" port=\"%d\" angle=\"%.2f\" />\n",
	    $_->[0]+5, $_->[1]-5, $port++, 0.0)
    foreach (@robots);
	

epilog();

binmode PNG;
print PNG $im->png;

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
    print PLAYGROUND
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

	<world w="$width" h="$height" color="white" groundTexture="$base.png" />
END
}

sub epilog {
    print PLAYGROUND "$door" if $door;
    print PLAYGROUND << "END";
</aseba-playground>
END
}

sub get_attribute {
    ($xp, $attribute, $default) = @_;
    my $result = $xp->findvalue('/svg/@'.$attribute)
	or warn('can\'t find /svg/@width');
    $result =~ s{([\.\d]+)mm}{$1};
    $result ||= $default;
    return wantarray ? split /\s+/,$result : $result;
}

sub get_point {
    my ($c,$type) = @_;
    my ($x,$y) = ($c->{point}->[0], $c->{point}->[1]);
    print LOG "\t\t\t\t# get point $x $y\n";
    return map_point($x,$y,$type);
}

sub map_point {
    my ($x,$y,$type) = @_;
    $x += $origin[0] if ($type ne 'relative');
    $y += $origin[1] if ($type ne 'relative');
    my @res = nearest(.5, ($x * $scale[0], $y * $scale[1]));
    $res[1] = ($type ne 'relative' ? $height : 0) - $res[1];
    print LOG "\t\t\t\t# map point $res[0]=$x*scale $res[1]=$height-$y*scale\n";
    return @res;
}

sub find_origin {
    my ($path) = @_;
    my $transform = $xp->findvalue($path) or return;
    my @o = ($transform =~ m{translate\((.+),(.+)\)}) or return;
    return (@origin = @o);
}	
