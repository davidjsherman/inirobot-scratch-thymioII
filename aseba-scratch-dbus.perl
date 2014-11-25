#!/usr/bin/perl

### Tiny web server for Aseba network connected through dbus, on the helper machine.
### In time this should wither away, and be replaced by a thin, low power (e.g. Arduino),
### onboard HTTP server.

### Assumes that asebamedulla is running, on the session bus, on the helper machine.
### Assumes that port 3000 is tunneled to the laptop running Scratch 2.

### Important! especially assumes that the vmcode.aesl program is running on the ThymioII:
### as not all Aseba functions are exposed through dbus we need an onboard program that
### offers an event API for them. Since we need this program anyway, we will use it to
### define a "Scratch 2 personality" for the ThymioII.

### Four kinds of routes make up the REST API that is proposed by this server:
### 1. /poll, /reset_all required by Scratch 2 extension protocol
### 2. High-level routes specific to Scratch 2: this logic is defined here to make it easy
###    to explore, but gradually we want to move as much of this as possible to the ThymioII.
### 3. Mid-level routes specific to Thymio-II events defined in vmcode.aesl
### 4. Low-level debugging routes for Aseba on DBus
### Lots of painful black magic is needed to define child-friendly reporters for Scratch.

use Mojolicious::Lite;
use Mojo::IOLoop;
use Net::DBus;
use Time::HiRes qw(usleep sleep);
use List::Util qw(sum);
use XML::Twig;

use Carp qw(cluck carp confess);
#$SIG{__WARN__} = sub { cluck $_[0] };
#$SIG{__DIE__} = sub { confess "[". $_[0] ."]"};
use Getopt::Long;
use Data::Dumper;

my @palette = build_palette(33);

my $app;

## Handle options
my $verbose = 0;
my $help = 0;
my $use_system_bus = 0;
my $dry_run = 0;
my $Aseba_service = 'ch.epfl.mobots.Aseba';
my $Aseba_object  = '/';
my $script_filename = 'vmcode.aesl';
my $freq_report = 30; # Scratch polling frequency
GetOptions( 'verbose!'  => \$verbose,
	    'help!'     => \$help,
	    'system!'   => \$use_system_bus,
	    'dry-run!'  => \$dry_run,
	    'script-file=s' => \$script_filename,  # default /home/david/vmcode.aesl
	    'service=s' => \$Aseba_service,  # default ch.epfl.mobots.Aseba
	    'object=s'  => \$Aseba_object,   # default /
	    'freq-report=n'  => \$freq_report,   # default 30
    );
$freq_report ||= 1; # at least once every second

## Global reporter variables (listed here for documentation, actually defined in sub update_reporters.

my %reporters = map { $_ => 0 } qw(motorSpeed/left motorSpeed/right
				   tilt/right-left tilt/front-back tilt/top-bottom
				   button/center button/forward button/backward button/left button/right
				   touching/front touching/back touching/ground
				   temperature tap clap neighbor sensing loudness
				   current_dial current_color_top current_color_bottomLeft
				   current_color_bottomRight);

## ThymioII events (hard-wired, although in fact we should get this from script file)

my %thymioII_events = ('thymioII_motor.left.target' => 1, 'thymioII_motor.right.target' =>
                       1, 'thymioII_mic.threshold' => 1, 'thymioII_leds_prox_h' => 8,
                       'thymioII_leds_circle' => 8, 'thymioII_leds_top' => 3,
                       'thymioII_leds_bottom' => 4, 'thymioII_leds_prox_v' => 2,
                       'thymioII_leds_buttons' => 4, 'thymioII_leds_rc' => 1,
                       'thymioII_leds_temperature' => 2, 'thymioII_leds_sound' => 1,
                       'thymioII_sound_freq' => 2, 'thymioII_sound_play' => 1,
                       'thymioII_sound_system' => 1, 'thymioII_sound_replay' => 1,
                       'thymioII_sound_wave' => 32, 'thymioII_sound_record' => 1,
		       );

## Set up DBus session

my $bus =
    (( !$use_system_bus ? Net::DBus->session() : Net::DBus->system() )
     or confess("no dbus connection: $!"))
    unless $dry_run;
my $service =
    ($bus->get_service($Aseba_service)
     or confess("no dbus service: $!"))
    unless $dry_run;
my $aseba =
    ($service->get_object($Aseba_object)
     or confess("no dbus object: $!"))
    unless $dry_run;

# Load event descriptions
$aseba->LoadScripts($script_filename)
    unless $dry_run;


## ------------------------------------------------------------
## Define Mojolicious routes

# poll, reset_all are part of the Scratch 2 protocol
get '/poll' => sub {
    my $c = shift;
    # $c->update_reporters(); # no, use recurring timer in case we need to throttle polling
    my @report = map { "$_ $reporters{$_}" } grep { $_ ne '_busy' } sort keys %reporters;

    if ($reporters{'_busy'}) {
	my @busy = keys %{$reporters{'_busy'}};
	push @report, join(' ', '_busy', @busy) if (@busy);
    }
    $c->render( text => join("\n", @report) );
} => 'poll';
get '/reset_all' => sub {
    my $c = shift;
    $aseba->SetVariable('thymio-II','motor.left.target', [0]);
    $aseba->SetVariable('thymio-II','motor.right.target', [0]);
    $aseba->SetVariable('thymio-II','mic.threshold', [10]);
    $aseba->SendEventName($thymioII_events{$_}, [-1]) foreach (grep { /thymioII_sound/ } keys %thymioII_events);
    $aseba->SendEventName($thymioII_events{$_}, [(0) x 8]) foreach (grep { /thymioII_leds/ } keys %thymioII_events);
    $c->render( text => 'reset_all' );
} => 'reset_all';

## ------------------------------------------------------------
## high-level routes specific to Scratch 2

# move
get '/scratch/move/:busyid/:steps' => sub {
    my $c = shift;
    my $busyid = $c->param('busyid');
    my $steps = $c->param('steps'); # steps are mm
    $reporters{_busy}->{$busyid} = 1;

    my $mm = abs($steps);

    my ($speedLeft,$speedRight) = (150,150); # maximum motor speed 500 is 150 mm/sec
    if ($mm < 150) {
	$speedLeft = $speedRight = $mm; # try to do it in 1 sec
	if ($speedLeft < 20) { # minimum 20 mm/sec = motor speed 100
	    $speedLeft = $speedRight = 20;
	}
    }
    my $delay = ($mm / $speedRight);

    $speedLeft = $speedRight = 500 * $speedRight / 150; # convert to motor speed
    $speedLeft = $speedRight *= ($steps > 0 ? 1 : -1);

    $c->timed_turn_motors('scratch_move',$busyid, $speedLeft,$speedRight, $delay);

    $c->render( text => join(' ','scratch_move',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'move';

# arc
get '/scratch/arc/:busyid/:radius/:degrees' => sub {
    my $c = shift;
    my $busyid = $c->param('busyid');
    my $radius = $c->param('radius');
    my $degrees = $c->param('degrees');
    $reporters{_busy}->{$busyid} = 1;

    $radius = 50 if ($radius < 50);

    my $speedLeft = 500; # 150 mm/sec
    my $speedRight = $speedLeft * ($radius - 50) / ($radius + 50);
    my $delay = (abs($degrees) / 180) * 3.1416 * ($radius + 50) / 150;
    ($speedLeft,$speedRight) = ($speedRight,$speedLeft) if ($degrees < 0);

    $c->timed_turn_motors('scratch_arc',$busyid, $speedLeft,$speedRight, $delay);

    $c->render( text => join(' ','scratch_arc',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'arc';

# swerve
get '/scratch/swerve/:busyid/:speedleft/:speedright/:sec' => sub {
    my $c = shift;
    my $busyid = $c->param('busyid');
    my $speedLeft = $c->param('speedleft');
    my $speedRight = $c->param('speedright');
    my $sec = $c->param('sec');
    $reporters{_busy}->{$busyid} = 1;

    $speedLeft  = 500 * $speedLeft  / 150; # convert to motor speed
    $speedRight = 500 * $speedRight / 150; # convert to motor speed

    $c->timed_turn_motors('scratch_swerve',$busyid, $speedLeft,$speedRight, $sec);

    $c->render( text => join(' ','scratch_swerve',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'swerve';

# turn
get '/scratch/turn/:busyid/:degrees' => sub {
    my $c = shift;
    my $degrees = $c->param('degrees');
    my $busyid = $c->param('busyid');
    $reporters{_busy}->{$busyid} = 1;

    my ($speedLeft,$speedRight) = (200,-200);
    ($speedLeft,$speedRight) = ($speedRight,$speedLeft) if ($degrees < 0);
    my $delay = 2.350/2.0 * (abs($degrees) / 90.0);

    $c->timed_turn_motors('scratch_swerve',$busyid, $speedLeft,$speedRight, $delay);

    $c->render( text => join(' ','scratch_turn',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'turn';

# reverse
get '/scratch/reverse/:dirleft/:dirright' => [dirleft=>[qw(forward backward opposite)]]
                                          => [dirright=>[qw(forward backward opposite)]] => sub {
    my $c = shift;
    my $change_left  = changeSpeedClosure($c->param('dirleft'));
    my $change_right = changeSpeedClosure($c->param('dirright'));

    my $currentLeft = $aseba->GetVariable('thymio-II','motor.left.target')->[0];
    my $speedLeft = &$change_left($currentLeft);
    my $currentRight = $aseba->GetVariable('thymio-II','motor.right.target')->[0];
    my $speedRight = &$change_right($currentRight);

    $aseba->SetVariable('thymio-II','motor.left.target',  [$speedLeft]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$speedRight]);
    $c->render( text => join(' ','reverse', &$change_left($currentLeft), &$change_right($currentRight) ));
} => 'reverse';

# avoid
get '/scratch/avoid' => sub {
    my $c = shift;
    my @prox = map { $_ / 2000.0 } @{ $aseba->GetVariable('thymio-II','prox.horizontal') };

    my $left = $aseba->GetVariable('thymio-II','motor.left.target')->[0];
    my $right = $aseba->GetVariable('thymio-II','motor.right.target')->[0];
    my ($new_left,$new_right) = (0,0);
    my $speed = ($left + $right)/2;
    if ($speed > 0) {
        # going forward
	my ($urgency,$direction) = $c->braitenberg(@prox);

        $new_left  = $speed * (1 - $urgency - $direction);
        $new_right = $speed * (1 - $urgency + $direction);
    }
    else {
        # going backward
        $new_left  = $speed * (1 + $prox[6] * 7);
        $new_right = $speed * (1 + $prox[5] * 7);
    }

    $aseba->SetVariable('thymio-II','motor.left.target',  [$new_left]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$new_right]);
    sleep(0.10);
    $aseba->SetVariable('thymio-II','motor.left.target',  [$left]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$right]);

    $c->render( text => join(' ', 'avoid', '('.join(' ',@prox).'): ',$left,$right));
} => 'avoid';

# start
get '/scratch/start/#speedleft/#speedright' => sub {
    my $c = shift;
    my $speedLeft = $c->param('speedleft');
    my $speedRight = $c->param('speedright');

    $speedLeft  = 500 * $speedLeft  / 150; # convert to motor speed
    $speedRight = 500 * $speedRight / 150; # convert to motor speed

    $aseba->SetVariable('thymio-II','motor.left.target',  [$speedLeft]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$speedRight]);

    $c->render( text => join(' ','scratch_start',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'start';

# changeSpeed
get '/scratch/changeSpeed/#deltaleft/#deltaright' => sub {
    my $c = shift;
    my $deltaLeft = $c->param('deltaleft');
    my $deltaRight = $c->param('deltaright');

    my $speedLeft  = (500 * $deltaLeft  / 150)  # convert to motor speed
      + $aseba->GetVariable('thymio-II','motor.left.target')->[0];
    my $speedRight = (500 * $deltaRight / 150)  # convert to motor speed
      + $aseba->GetVariable('thymio-II','motor.right.target')->[0];

    $aseba->SetVariable('thymio-II','motor.left.target',  [$speedLeft]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$speedRight]);

    $c->render( text => join(' ','scratch_changeSpeed',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'changeSpeed';

# stop
get '/scratch/stop' => sub {
    my $c = shift;

    my ($speedLeft,$speedRight) = (0,0);

    $aseba->SetVariable('thymio-II','motor.left.target',  [$speedLeft]);
    $aseba->SetVariable('thymio-II','motor.right.target', [$speedRight]);

    $c->render( text => join(' ','scratch_stop',
			     $aseba->GetVariable('thymio-II','motor.left.target')->[0],
			     $aseba->GetVariable('thymio-II','motor.right.target')->[0]) );
} => 'stop';

# setLeds color from palette
get '/scratch/setLeds/:leds/*value' => [leds=>[qw(all bottomLeft bottomRight prox_h circle top
						  prox_v buttons rc temperature sound)]] => sub {
    my $c = shift;
    my $leds = $c->param('leds');
    my $value = $c->param('value');
    my @rgb = (0,0,0);
    if ($leds =~ /bottom(Left|Right)/){
	@rgb = @{$palette[$value % (1+$#palette)]};
	$aseba->SendEventName('thymioII_leds_bottom', [
				   ($leds eq 'bottomRight'), @rgb
			       ]);
	$reporters{'current_color_'.$leds} = $value % (1+$#palette);
    }
    elsif ($leds eq 'top'){
	@rgb = @{$palette[$value % (1+$#palette)]};
	$aseba->SendEventName('thymioII_leds_top', [ @rgb ]);
	$reporters{'current_color_'.$leds} = $value % (1+$#palette);
    }
    elsif ($leds eq 'all'){
	@rgb = @{$palette[$value % (1+$#palette)]};
	map { $aseba->SendEventName('thymioII_leds_bottom',[$_,@rgb]) } 0..1;
	$aseba->SendEventName('thymioII_leds_top',[@rgb]);
	$reporters{'current_color_'.$_} = $value % (1+$#palette)
	    foreach (qw(top bottomLeft bottomRight));;
    }
    else { # $leds =~ /^(buttons|circle|prox_h|prox_v|rc|sound|temperature)$/
	@rgb = map { $_ =~ /^\d+$/ ? $_ : 32 } split(/[,\+\&\/ ]/, $value);
	$aseba->SendEventName('thymioII_leds_'.$leds, [ @rgb ]);
    }
    $c->render( text => join(' ','setLeds', $leds, $value,'=',@rgb));
} => 'setLeds';

# changeLeds color from palette
get '/scratch/changeLeds/:leds/*value' => [leds=>[qw(all bottomLeft bottomRight top)]] => sub {
    my $c = shift;
    my $leds = $c->param('leds');
    my $value = $c->param('value');
    my @leds = ($leds eq 'all') ? qw(bottomLeft bottomRight top) : ($leds);
    my @render_text = ();

    foreach my $this_led (@leds) {
      my $new_value = ($value + $reporters{'current_color_'.$this_led}) % (1+$#palette);
      my @rgb = @{$palette[$new_value % (1+$#palette)]};
      unshift @rgb, 0 if ($this_led eq 'bottomLeft');
      unshift @rgb, 1 if ($this_led eq 'bottomRight');
      $aseba->SendEventName('thymioII_leds_'.substr($this_led,0,6), [ @rgb ]);
      $reporters{'current_color_'.$this_led} = $new_value;
      push @render_text, join(' ','changeLeds', $leds, $value,'=',@rgb);
    }
    $c->render( text => join("\n",@render_text) );
} => 'changeLeds';

# clearLeds color
get '/scratch/clearLeds/:leds' => [leds=>[qw(all bottomLeft bottomRight prox_h circle top
					     prox_v buttons rc temperature sound)]] => sub {
    my $c = shift;
    my $leds = $c->param('leds');
    my @all = qw(prox_h circle top bottom prox_v buttons rc
                 temperature sound);

    if ($leds =~ /bottom(Left|Right)/){
	$aseba->SendEventName('thymioII_leds_bottom', [ ($leds eq 'bottomRight'), (0) x 3 ]);
    }
    elsif ($leds eq 'all'){
	$aseba->SendEventName('thymioII_leds_'.$_, [ (0) x 8 ])
	    foreach qw(prox_h circle top prox_v buttons rc temperature sound);
	$aseba->SendEventName('thymioII_leds_bottom', [ 1, (0) x 3 ]);
    }
    else {
	$aseba->SendEventName('thymioII_leds_'.$leds, [ (0) x 8 ]);
    }
    $c->render( text => join(' ','clearLeds', $leds));
} => 'clearLeds';

# setLeds RGB
get '/scratch/setLedsRGB/:leds/:red/:green/:blue' => [leds => [qw(bottomLeft bottomRight top all)]] => sub {
    my $c = shift;
    my $leds = $c->param('leds');
    my $red = $c->param('red');
    my $green = $c->param('green');
    my $blue = $c->param('blue');
    if ($leds =~ /bottom(Left|Right)/) {
	$aseba->SendEventName('thymioII_leds_bottom', [
				   ($leds eq 'bottomRight'), $red, $green, $blue
			       ]);
    }
    elsif ($leds eq 'top'){
	$aseba->SendEventName('thymioII_leds_top', [
				   $red, $green, $blue
			       ]);
    }
    elsif ($leds eq 'all'){
	map { $aseba->SendEventName('thymioII_leds_bottom',[$_,$red,$green,$blue]) } 0..1;
	$aseba->SendEventName('thymioII_leds_top',[$red,$green,$blue]);
    }
    $c->render( text => join(' ','setLedsRGB', $leds, $red,$green,$blue));
} => 'setLedsRGB';

# switchDial
get '/scratch/switchDial/:dial' => sub {
    my $c = shift;
    my $dial = $c->param('dial');
    $aseba->SendEventName('scratch_set_dial', [ $dial ]);
    $reporters{'current_dial'} = $dial;
    $c->render( text => join(' ', 'switchDial', ));
} => 'switchDial';

# nextDial
get '/scratch/nextDial/:level' => sub {
    my $c = shift;
    my $level = $c->param('level');
    my $limit = ($level eq 'simple') ? 8 : (($level eq 'double') ? 72 : 684);
    $aseba->SendEventName('scratch_next_dial_limit', [ $limit ]);
    $reporters{'current_dial'} = $reporters{'current_dial'} % $limit;
    $c->render( text => join(' ', 'nextDial', ));
} => 'nextDial';

# playNote
get '/scratch/playNote/:freq/#secs' => sub {
    my $c = shift;
    my $freq = $c->param('freq');
    my $secs = $c->param('secs');
    $aseba->SendEventName('thymioII_sound_freq', [ $freq, $secs * 60.0 ]);
    $c->render( text => join(' ','playNote', $freq, $secs));
} => 'playNote';

# playSound
get '/scratch/playSound/:kind/:number' => [kind => [qw(sound system replay)]] => sub {
    my $c = shift;
    my $kind = $c->param('kind');
    my $number = $c->param('number');
    $aseba->SendEventName("thymioII_sound_$kind", [ $number ]);
    $c->render( text => join(' ','playSound', $kind, $number));
} => 'playSound';

# recordSound
get '/scratch/recordSound/:number/:secs' => sub {
    my $c = shift;
    my $number = $c->param('number');
    my $secs = $c->param('secs');
    $aseba->SendEventName('thymioII_sound_record', [ $number ]);
    sleep($secs);
    $aseba->SendEventName('thymioII_sound_record', [ -1 ]);
    $c->render( text => join(' ','recordSound', ));
} => 'recordSound';

# setSoundWave
get '/scratch/setSoundWave/*samplevector' => sub {
    my $c = shift;
    my $samplevector = $c->param('samplevector');
    my @vector = split /[,\+\&\/ ]/, $samplevector;
    $c->render( text => join(' ','setSoundWave', [ @vector ]));
} => 'setSoundWave';


## ------------------------------------------------------------
## mid-level routes specific to Thymio-II 

# load aesl file to learn event handlers, and define a route for each one
my $aesl = XML::Twig->new()->parsefile($script_filename);

foreach my $thymioII_event ($aesl->first_elt('network')->children('event')) {
  (my $route = $thymioII_event->att('name')) =~ s{_}{/};
  get "/$route/*args" => sub {
    my $c = shift;
    my @args = split/\//,$c->param('args');
    $aseba->SendEventName($thymioII_event->att('name'), [@args[0..($thymioII_event->att('size')-1)]]);
    $c->render( text => join(' ',$thymioII_event->att('name'),@args) );
  } => $thymioII_event->att('name');
}

# define routes for hard-coded variables
foreach my $thymioII_variable (qw(motor.left.target motor.right.target mic.threshold)) {
  get '/thymioII/'.$thymioII_variable.'/*args' => sub {
    my $c = shift;
    my @args = split/\//,$c->param('args');
    $aseba->SetVariable('thymio-II',$thymioII_variable, [@args[0..0]]);
    $c->render( text => join(' ','thymioII_'.$thymioII_variable, @args) );
  } => 'thymioII_'.$thymioII_variable;
}


## ------------------------------------------------------------
## Generic routes for Aseba on DBus
## Hard-coded, don't use introspection
# method GetNodesList
#    arg type="as" direction="out"
get '/GetNodesList' => sub {
    my $c = shift;
    my $out = $aseba->GetNodesList # array of strings
	unless $dry_run;
    $c->render(text => "GetNodesList = ".join(' ',@{$out}).".");
} => 'GetNodesList';

# method GetNodeId
#    arg type="n" direction="out"
#    arg name="node" type="s" direction="in"
get '/GetNodeId/#node' => sub {
    my $c = shift;
    my $node = $c->param('node');
    my $out = $aseba->GetNodeId($node) # number
	unless $dry_run;
    $c->render(text => "GetNodeId: $node = ".$out.".");
} => 'GetNodeId';

# method GetVariablesList
#    arg type="as" direction="out"
#    arg name="node" type="s" direction="in"
get '/GetVariablesList/#node' => sub {
    my $c = shift;
    my $node = $c->param('node');
    my $out = $aseba->GetVariablesList($node) # array of strings
	unless $dry_run;
    $c->render(text => "GetVariablesList: $node = ".join(' ',@{$out}).".");
} => 'GetVariablesList';

# method SetVariable
#    arg name="node" type="s" direction="in"
#    arg name="variable" type="s" direction="in"
#    arg name="values" type="an" direction="in"
get '/SetVariable/#node/#variable/#value' => sub {
    my $c = shift;
    my $node = $c->param('node');
    my $variable = $c->param('variable');
    my @values = split/[,\+\& ]/, $c->param('value');
    $aseba->SetVariable($node,$variable,[@values])
	unless $dry_run;
    $c->render(text => "SetVariable $node $variable (".join(' ',@values).").");
} => 'SetVariable';

# method GetVariable
#    arg type="an" direction="out"
#    arg name="node" type="s" direction="in"
#    arg name="variable" type="s" direction="in"
get '/GetVariable/:node/#variable' => sub {
    my $c = shift;
    my $node = $c->param('node');
    my $variable = $c->param('variable');
    my $out = $aseba->GetVariable($node,$variable) # array of numbers
	unless $dry_run;
    $c->render(text => "GetVariable: $node $variable = ".join(' ',@{$out}).".");
} => 'GetVariable';

# method SendEvent
#    arg name="event" type="q" direction="in"
#    arg name="values" type="an" direction="in"
get '/SendEvent/#event/#values' => sub {
    my $c = shift;
    my $event = $c->param('event');
    my @values = split/[,\+\& ]/, $c->param('values');
    $aseba->SendEvent($event,[@values])
	unless $dry_run;
    $c->render(text => "SendEvent: $event (".join(' ',@values).").");
} => 'SendEvent';

# method SendEventName
#    arg name="name" type="s" direction="in"
#    arg name="values" type="an" direction="in"
get '/SendEventName/#name/#values' => sub {
    my $c = shift;
    my $name = $c->param('name');
    my @values = split/[,\+\& ]/, $c->param('values');
    $aseba->SendEventName($name,[@values])
	unless $dry_run;
    $c->render(text => "SendEventName $name (".join(' ',@values).").");
} => 'SendEventName';


sub changeSpeedClosure {
    my $change = shift;

    return (sub { return  abs($_[0]) }) if ($change eq 'forward');
    return (sub { return -abs($_[0]) }) if ($change eq 'backward');
    return (sub { return     -$_[0]  }) if ($change eq 'opposite');
    return (sub { return      $_[0]  });
}

sub build_palette {
    (my $step = shift) ||= 33;
    my @colors;

    for my $i (0..33) {
	$colors[$i + (0 * $step)] = [        33,        $i,         0 ];
	$colors[$i + (1 * $step)] = [ (33 - $i),        33,         0 ];
	$colors[$i + (2 * $step)] = [         0,        33,        $i ];
	$colors[$i + (3 * $step)] = [         0, (33 - $i),        33 ];
	$colors[$i + (4 * $step)] = [        $i,         0,        33 ];
	$colors[$i + (5 * $step)] = [        33,         0, (33 - $i) ];
    }

    push @colors, $colors[0];
    return @colors;
}

## ------------------------------------------------------------
## Define Mojolicious helpers

helper timed_turn_motors => sub {
  my $c = shift;
  (my $route_name = shift) ||= 'scratch (undef)';
  (my $busyid     = shift) ||= 0xdeadbeef;
  (my $speedLeft  = shift) ||= 0;
  (my $speedRight = shift) ||= 0;
  (my $delay      = shift) ||= 0.0;

  $aseba->SetVariable('thymio-II','motor.left.target',  [$speedLeft]);
  $aseba->SetVariable('thymio-II','motor.right.target', [$speedRight]);
  $c->app->log->debug("$route_name started motors $speedLeft $speedRight.");

  $c->app->log->debug("$route_name started timer for $delay seconds.");
  my $timer = Mojo::IOLoop->timer($delay => sub {
      $aseba->SetVariable('thymio-II','motor.left.target',  [0]);
      $aseba->SetVariable('thymio-II','motor.right.target', [0]);
      delete $reporters{_busy}->{$busyid};
      $c->app->log->debug("$route_name completed after $delay seconds.");
    });
  $c->on(finish => sub { }); # dummy finish handler
};

helper braitenberg => sub {
  my $c = shift;
  my @prox = @_;
  my @wt_urgency = (1,2,3,2,1);
  my @wt_direction = (-4,-3,0,3,4);
    
  my $urgency   = sum map { $prox[$_] * ($wt_urgency[$_]) } 0..4;
  my $direction = sum map { $prox[$_] * ($wt_direction[$_]) } 0..4;
  return ($urgency,$direction);
};

helper update_reporters => sub {
    my $c = shift;
    return if $dry_run;
    # Thymio-II mid-level reporters
    $reporters{'motorSpeed/left'}  = 150/500 * $aseba->GetVariable('thymio-II','motor.left.target')->[0];
    $reporters{'motorSpeed/right'} = 150/500 * $aseba->GetVariable('thymio-II','motor.right.target')->[0];

    my $acc = $aseba->GetVariable('thymio-II','acc');
    ($reporters{'tilt/right-left'}, $reporters{'tilt/front-back'}, $reporters{'tilt/top-bottom'}) = @$acc;

    $reporters{'loudness'} =
        $aseba->GetVariable('thymio-II','mic.intensity')->[0];
    $reporters{'temperature'} = $aseba->GetVariable('thymio-II','temperature')->[0];

    # Scratch consolidated reporters
    my $prox = $aseba->GetVariable('thymio-II','prox.horizontal');
    # ($reporters{'proximityLeftFront'}, $reporters{'proximityMiddleLeftFront'},
    #  $reporters{'proximityMiddleFront'}, $reporters{'proximityMiddleRightFront'},
    #  $reporters{'proximityRightFront'}, $reporters{'proximityLeftBack'},
    #  $reporters{'proximityRightBack'}) = @$prox;

    my $prox_gd = $aseba->GetVariable('thymio-II','prox.ground.delta');
    # ($reporters{'proximityLeftGround'},$reporters{'proximityRightGround'}) = @$prox_gd;

    $reporters{'proximity'} =
      ':' . join('', map { int($_ / 460) } @$prox) . ':';

    $reporters{'proximity'} .=
            join('', map { int($_/100) } @$prox_gd) . ':';

    # $reporters{'buttons'} =
    #   'B' . join('', map { $_ ? $_ : '-' } 
    # 		 map { $reporters{"button/$_"} eq 'true' ? "1" : "0" }
    # 		 qw(center forward backward left right));

    # Scratch measurement and obstacle avoidance
    ($reporters{'distance/front'},$reporters{'nearSide'}) = $c->braitenberg(@$prox);
    $reporters{'nearSide'} = -2 * int($reporters{'nearSide'} / 1000);
    $reporters{'distance/front'} = ($reporters{'distance/front'} > 30400)
      ? 0 : 190 - int($reporters{'distance/front'} / 160);
    $reporters{'distance/back'} = [sort {$b<=>$a} ($prox->[5], $prox->[6])]->[0];
    $reporters{'distance/back'} = ($reporters{'distance/back'} > 4680)
      ? 0 : 125 - int($reporters{'distance/back'} / 37.44);
    
    # Scratch boolean reporters
    $reporters{ "button/$_" } =
      ($aseba->GetVariable('thymio-II',"button.$_")->[0] ? 'true' : 'false')
      foreach (qw(center forward backward left right));        

    $reporters{'touching/front'}  = ($reporters{'proximity'} !~ /:00000..:..:/) ? 'true' : 'false';
    $reporters{'touching/back'}   = ($reporters{'proximity'} !~ /:.....00:..:/) ? 'true' : 'false';
    $reporters{'touching/ground'} = ($reporters{'proximity'} !~ /:.......:00:/) ? 'true' : 'false';
    $reporters{'tap'} =
        $aseba->GetVariable('thymio-II','acc._tap')->[0]
        ? 'true' : 'false';
    $reporters{'clap'} = 
        ( $aseba->GetVariable('thymio-II','mic.intensity')->[0] >
	  $aseba->GetVariable('thymio-II','mic.threshold')->[0] )
        ? 'true' : 'false';
    $reporters{'neighbor'} =
        $aseba->GetVariable('thymio-II','prox.comm.rx')->[0]
        ? 'true' : 'false';

    # low-level raw variables from ThymioII spec
    $reporters{$_} = $aseba->GetVariable('thymio-II',$_)->[0]
      foreach (qw(event.source event.args buttons._raw button.backward button.left
                  button.center button.forward button.right buttons._mean buttons._noise
                  prox.comm.rx._payloads prox.comm.rx._intensities prox.comm.rx
                  prox.comm.tx motor.left.target motor.right.target motor.left.speed
                  motor.right.speed motor.left.pwm motor.right.pwm temperature rc5.address
                  rc5.command mic.intensity mic.threshold mic._mean timer.period
                  acc._tap));
    $reporters{$_} = join(' ',@{$aseba->GetVariable('thymio-II',$_)})
      foreach (qw(prox.horizontal prox.ground.ambiant prox.ground.reflected
                  prox.ground.delta acc));
};

## Start the Mojolicious micro server
$app = app;
$app->secrets(['Ann had come to the realization that it was a typical case of 36%8==4']);

# recurring timer triggered $freq_report times per sec
Mojo::IOLoop->recurring( (1.0 / $freq_report) => sub {
  my $loop = shift;
  $app->update_reporters();
});

$app->start;
