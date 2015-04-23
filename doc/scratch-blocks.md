## Scratch 2 blocks for piloting a Thymio-II using *asebascratch*

Scratch 2 block           | Description
------------------------- | -------------
![move (50) mm](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/move.png) | move forward the given distance (backwards if the distance is negative), then stop
![turn (45) degrees](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/turn.png) | turn in place clockwise number of degrees (counter-clockwise if negative), then stop
![curve radius (150) mm (45) degrees](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/curve-radius.png) | follow arc of a circle of given radius, then stop: forward if radius > 0, backwards if radius < 0; right if degrees > 0, left if degrees < 0
![start motors (20) x (20) mm/sec](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/start-motors.png) | move forward (or backward) continuously at the given rate for right wheel x left wheel
![change motors (10) x (10) mm/sec](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/change-motors.png) | change the motor speed by the given rate for right wheel x left wheel
![stop motors](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/stop-motors.png) | stop the motors
![switch dial to (0)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/switch-dial.png) | set the circle LEDs to the 12 o'clock position
![next dial](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/next-dial.png) | advance the (up to three) hands of the clock by 1/8th of a turn
![next dial up to (71)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/next-dial-modulo.png) | ditto, but limit by the given number
![leds clear](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/leds-clear.png) | clear all color LEDs
![leds set color (0) flags (7)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/leds-set.png) | set the LED color using the Scratch 2 rainbow (0..200); bit mask for top, bottom-left, bottom-right
![leds change color (33) flags (7)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/leds-change.png) | change the LED color by the given amount; bit mask as above
![play note (440) for (60) 60ths](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/play-note.png) | play a tone of given Hertz for the given number of 1/60th seconds
![play system sound (0)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/play-system.png) | play prerecorded system sound of given number
![set odometer direction:(90) x:(0) y:(0)](https://github.com/davidjsherman/inirobot-scratch-thymioII/blob/master/doc/set-odometer.png) | set the robot's idea of its orientation (in degrees) and position (x,y)
