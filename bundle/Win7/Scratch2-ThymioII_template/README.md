# Connecting Scratch 2 to the Thymio-II robot

Scratch2-ThymioII is a helper program that connects the Scratch 2 offline editor to a Thymio-II robot.

- connect the Thymio-II by a USB cable
- run the Scratch2-ThymioII helper
- open the Thymio-II.sb2 example in Scratch 2

The new Thymio-II blocks will be in “More Blocks”. Clicking on the backdrop in Thymio-II.sb2 will run a simple program to show how the Thymio-II senses its environment. The example “Spirograph arcs.sb2” shows how basic odometry is provided by the helper.

On Windows you will need to have installed the Aseba software that came with the robot, since it provides a necessary USB driver.

Instead of running an example, you can load the “ext-scratch-thymioII” extension definition into Scratch 2 using the shift-File menu. The “ext-basic-thymioII” extension can be loaded instead to provide a the low-level interface to the robot. Thymio-II.sprite2 is a simple sprite definition that can be added to any scene.

The helper program is a micro HTTP server that loads a special AESL file “thymio_motion.aesl” that gives the Thymio-II a ‘Scratch personality’, then listens to port 3000 and responds to a simple REST API. See github.com / davidjsherman / inirobot-scratch-thymioII for details.

*Le fichier fr-thymioII.po, qui traduit en français les noms des blocs, peut être chargé dans Scratch 2 à partir du menu shift-Monde à gauche*.

— [David James Sherman](mailto:david.sherman@inria.fr), Inria Bordeaux Sud-Ouest, 2014-12-13