# Scratch and Thymio-II

These files define a software link between Scratch 2 and the Thymio-II robot, with which
one can drive (teleoperate) the Thymio-II using programs written in Scratch 2.

Scratch 2 is a visual programming system designed for children. A Scratch 2 program is
comprised of _sprites_ and a _stage_, each of which has a behavior, a set of
appearances, a set of sounds, and state variables. Sprites communicate using messages and
shared variables. The behavior of a sprite is defined by an independent program decomposed
into event handlers for global events, such as key presses, mouse movements, and messages.

Thymio-II is an autonomous two-wheeled robot, also designed for children. It has proximity
sensors, lights, sound, a 3-axis accelerometer, and independent motors for the wheels. The
onboard microcontroller runs a user-defined event-based program, written in the _Aseba_
language. Thymio-II can communicate with external programs using a USB link.

## Requirements

1. Offline Scratch 2
2. Perl libraries Mojolicious, Net::DBus, Time::HiRes, List::Util, XML::Twig
3. The asebamedulla switch from the Aseba tools
4. A Thymio-II *tethered to the machine* running Scratch 2

## Quick start on MacOSX

- Copy "thymio_native_events.abo" to an SD card as "vmcode.abo".
- In shell, run "start-aseba-scratch-helper.sh"
- In Scratch 2, shift-File to import extension "ext-scratch-thymioII.json"

## Rationale

In order for the connection between Scratch 2 and Thymio-II to be useful in a teaching
setting, we need to find the best match between their respective programming
concepts. Note that many do not match: for example, Scratch 2 sprites have an absolute X-Y
position and can move instantaneously, whereas the Thymio-II can only move by running its
motors; Scratch 2 sprites can have many costumes whereas the Thymio-II can only changes
its lights; Thymio-II can continue to move even when the controlling program is busy, and
so on. Furthermore, the operations available on the Thymio-II are at a lower level of
abstraction than what might be expected by a traditional Scratch 2 programmer.

These files define a kind of software "breadboard" for easily testing different ideas for
which Scratch 2 language elements might be appropriate for the Thymio-II. The priority for
this breadboard was to make it easy to modify the language elements, and consequently it
is fairly high in the software food chain. The plan is that as the "Scratch 2 personality"
for the Thymio-II becomes better defined, it will be moved as much as possible to the
Thymio-II. The Thymio-II is currently driven by the Scratch 2 program. When this set of
language elements converges, we can consider compiling (certain kinds of) Scratch 2
programs to Aseba and permit autonomous activity.

## Implementation

Extensions are added to offline Scratch 2 by a helper application, running on the same
machine, that communicates with Scratch 2 using HTTP. An extension description file
written in JSON declares the new blocks and reporters made available to Scratch 2 by the
extension, and maps them to the REST interface provided by the helper.

The helper application aseba-scratch-dbus.perl implements a micro web server that
translates Scratch 2 requests to Aseba messages. It uses DBus to communicate with the
asebamedulla switch, provided by the Aseba tools, which communicates with the Thymio-II.

Some operations on the Thymio-II, such as lights and sound management, are not available
through the DBus interface proposed by asebamedulla. It is thus necessary to define Aseba
events to implement these operations and pre-program event handlers in the firmware of the
Thymio-II. The program thymio_native_events.aesl must be loaded onto the Thymio-II before
operation. The easiest way to do this is to write the compiled bytecode
thymio_native_events.abo to an SD card under the (N)ame vmcode.abo. The Thymio-II will load
this bytecode when it starts up.

## Interfaces

### REST interfaces provided by aseba-scratch-dbus.perl

The aseba-scratch helper responds to three APIs:
1. /scratch/*
A high-level Scratch 2 interface for turtle motion, simplified environment sensing, Scratch 2 color effects (0..200) 
2. /thymioII/*
A mid-level interface to variables and events defined in thymio_native_events.aesl
3. /SetVariable, /GetVariable, /SendEventName
A low-level DBus interface to Aseba

### Scratch 2 high-level blocks and reporters

Importing ext-scratch-thymioII.json into Scratch 2 provides the following blocks:
- move (N) mm
- turn (N) degrees
- curve radius (N) mm (N) degrees
- run motors (N) x (N) mm/sec for (N) sec
- start motors (N) x (N) mm/sec
- change speed (N) x (N) mm/sec
- stop motors
- reverse left (DIRECTION), right (DIRECTION)
- avoid

- switch dial to (N)
- next (DIALLEVEL) dial
- set (LIGHT) color effect (N)
- change (LIGHT) color effect (N)
- clear (LIGHT) color effect
- play note (N) for (N) sec
- play (SOUND) sound (N)
- stop (SOUND) sound
- record sound number (N) for (N) sec

where
- DIRECTION := forward | backward | opposite
- DIALLEVEL := simple | double | triple
- LIGHT := top | bottom | sensor | button | microphone | temperature
- SOUND := system | special | recorded
- N is a floating-point number

Importing ext-scratch-thymioII.json into Scratch 2 provides the following reporters:
- touching front : (true/false)
- touching back : (true/false)
- touching ground : (true/false)
- distance back : (0..150 mm)
- distance front : (0..190 mm)
- near side : (-90..90 degrees)
- motor left speed : (-200..200 mm/sec)
- motor right speed : (-200..200 mm/sec)

- touching front|back|ground : (true/false)
- button center|forward|backward|left|right : (true/false)
- clap : (true/false)
- distance front|back|ground : (0..190 mm)
- near side : (-90..90 degrees)
- motor left|right speed : (-200..200 mm/sec)
- tilt right-left|front-back|top-bottom : (-50..50)
- sensing : (:0000000:00:..:9999999:99:)
- temperature : (-40..40)
- loundness : (-100..100)


### Scratch 2 Thymio-II and Dbus blocks and reporters

Importing ext-aseba-thymioII.json into Scratch 2 provides the following blocks:
- set motor_left_target (N)
- set motor_right_target (N)
- set leds_prox_h (N) (N) (N) (N) (N) (N) (N) (N)
- set leds_circle (N) (N) (N) (N) (N) (N) (N) (N)
- set leds_top (N) (N) (N)
- set leds_bottom (N) (N) (N) (N)
- set leds_prox_v (N) (N)
- set leds_buttons (N) (N) (N) (N)
- set leds_rc (N)
- set leds_temperature red (N) blue (N)
- set leds_sound (N)
- set sound_freq (N) Hz (N) msec
- set sound_play (N)
- set sound_system (N)
- set sound_replay (N)
- set sound_wave (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N) (N)
- set sound_record (N)
- set mic_threshold (N)
- reset all colors and sound

Importing ext-aseba-thymioII.json into Scratch 2 provides a reporter for every standard variable of the Thymio-II.

## Testing
No standard tests are defined yet.

# Examples
- Thymio-II.sb2: Schematic view of the Thymio-II showing some sensor values
- Sierpinski ThymioII colors.sb2: Thymio-II and the Scratch cat iteratively trace the Sierpinski fractal
- Friendly Thymio-II.sb2: an approximation of the built-in green bahavior (cablibrated for low light conditions!)
- Friendly Thymio-II watchers.sb2: a variant with separate event handlers
