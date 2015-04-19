# Scratch and Thymio-II

These files define a software link between Scratch 2 and the Thymio-II robot, with which one can drive (teleoperate) the Thymio-II using programs written in Scratch 2.

Scratch 2 is a visual programming system designed for children. A Scratch 2 program is comprised of _sprites_ and a _stage_, each of which has a behavior, a set of appearances, a set of sounds, and state variables. Sprites communicate using messages and shared variables. The behavior of a sprite is defined by an independent program decomposed into event handlers for global events, such as key presses, mouse movements, and messages.

Thymio-II is an autonomous two-wheeled robot, also designed for children. It has proximity sensors, lights, sound, a 3-axis accelerometer, and independent motors for the wheels. The onboard microcontroller runs a user-defined event-based program, written in the _Aseba_ language. Thymio-II can communicate with external programs using a USB link.

## Requirements

1. [Offline Scratch 2](https://scratch.mit.edu/scratch2download/)
2. This software (current release [0.6.2-alpha](https://github.com/davidjsherman/inirobot-scratch-thymioII/releases/tag/v0.6.2-alpha))
3. A Thymio-II *tethered to the machine* running Scratch 2
4. On Windows, the [Aseba software](https://aseba.wikidot.com/en:start) that came with the robot

## Quick start

1. Download and open the bundle for your operating system.
2. Double-click “Scratch2-ThymioII” to run the helper
3. Open one of the Scratch 2 examples

## Rationale

In order for the connection between Scratch 2 and Thymio-II to be useful in a teaching setting, we need to find the best match between their respective programming concepts. Note that many do not match: for example, Scratch 2 sprites have an absolute X-Y position and can move instantaneously, whereas the Thymio-II can only move by running its motors; Scratch 2 sprites can have many costumes whereas the Thymio-II can only changes its lights; Thymio-II can continue to move even when the controlling program is busy, and so on. Furthermore, the operations available on the Thymio-II are at a lower level of abstraction than what might be expected by a traditional Scratch 2 programmer.

This software defines a “Scratch 2 personality” for the Thymio-II that can be modified fairly easily to test different language elements.

## Implementation

Extensions are added to offline Scratch 2 by a helper application, running on the same machine, that communicates with Scratch 2 using HTTP. An extension description file written in JSON declares the new blocks and reporters made available to Scratch 2 by the extension, and maps them to the REST interface provided by the helper.

The helper application *asebascratch* implements a micro web server that translates Scratch 2 requests to Aseba messages. It is an extension of my *asebahttp* switch, which provides a generic HTTP interface to the Thymio-II.

The interface to the Thymio-II is defined by a bytecode program *thymio_motion.aesl* that provides
- basic events for motors, lights, and sound;
- variables that report on the robot’s environment;
- a queue for blocking operations such as motion;
- simple odometry for reporting the robot’s approximate position.

This program is loaded automatically by a helper script.

## Interfaces

### REST interfaces provided by asebascratch

The asebascratch helper responds to five kinds of request:

1. **/scratch_…**
A high-level Scratch 2 interface for turtle motion, simplified environment sensing, Scratch 2 color effects 
2. **/Q_…**, **/V_…**, **/A_…**, **/M_…**
A mid-level interface to events defined in thymio_motion.aesl
3. **/_variable_name_**
Get/set interface to robot variables
4. **/poll, /reset_all**
Standard requests required by Scratch 2
5. **/nodes/thymio-II**
JSON description of the events defined in thymio_motion.aesl and available through the REST interface

### Scratch 2 high-level blocks and reporters

Importing ext-scratch-thymioII.json into Scratch 2 provides the following blocks:
- move N mm
- turn N degrees
- curve radius N mm N degrees
- start motors N x N mm/sec
- change motors N x N mm/sec
- stop motors
- switch dial to N
- next dial
- next dial up to N
- leds clear
- leds set color N flags N
- leds change color N flags N
- play note N for N 60ths
- play system sound N
- set odometer direction:N x:N y:N

and provides the following reporter variables:
- touching SENSORS (boolean)
- button BUTTON (boolean)
- clap (boolean)
- distance SENSORS (0..190 mm)
- angle ANGLE (-90..90 degrees)
- motor LEFTRIGHT speed (-200..200 mm/sec)
- motor LEFTRIGHT target (-200..200 mm/sec)
- tilt on TILT axis
- leds color LIGHT
- sensing front
- temperature (-40..40)
- loundness (-100..100)
- odometer ODO

where
- N is a floating-point number
- SENSORS :=   front | back | ground
- BUTTON :=    center | forward | backward | left | right
- ANGLE := front | back
- LEFTRIGHT := left | right
- TILT := right_left | front_back | top_bottom
- LIGHT := top | bottom/left | bottom/right
- ODO := direction | x | y

### Low-level events

Loading thymio_motion.aesl into the Thymio-II defined the following events, with the indicated number of arguments:
- Q_add_motion : 4
- Q_cancel_motion : 1
- Q_motion_added : 5
- Q_motion_cancelled : 5
- Q_motion_started : 5
- Q_motion_ended : 5
- Q_motion_noneleft : 1
- Q_set_odometer : 3
- V_leds_prox_h : 8
- V_leds_circle : 8
- V_leds_top : 3
- V_leds_bottom : 4
- V_leds_prox_v : 2
- V_leds_buttons : 4
- V_leds_rc : 1
- V_leds_temperature : 2
- V_leds_sound : 1
- A_sound_freq : 2
- A_sound_play : 1
- A_sound_system : 1
- A_sound_replay : 1
- A_sound_record : 1
- M_motor_left : 1
- M_motor_right : 1
