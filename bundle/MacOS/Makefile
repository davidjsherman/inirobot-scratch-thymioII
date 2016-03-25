BUNDLE = Scratch2-ThymioII.app
SCRIPT = asebascratch-none.perl
PROFILE = Scratch2-ThymioII.platypus

DASHEL = ~/src/build-dashel
ASEBA = ~/work/xcode-aseba
PROGRAMS =  $(DASHEL)/portlist $(ASEBA)/switches/http/Debug/asebahttp $(ASEBA)/examples/clients/scratch/Debug/asebascratch
LIBS = /usr/lib/libxml2.2.dylib /usr/lib/liblzma.5.dylib /usr/lib/libiconv.2.dylib
change = /usr/lib/libxml2.2.dylib @executable_path/../Frameworks/libxml2.2.dylib

all:	bundle

bundle:	app libs pgms

app:	$(SCRIPT)
	rm -rf "$(BUNDLE)"
	platypus -P "$(PROFILE)" "$(BUNDLE)"

libs:	$(LIBS)
	mkdir -p "$(BUNDLE)"/Contents/Frameworks
	install $^ "$(BUNDLE)"/Contents/Frameworks

pgms:	$(PROGRAMS)
	install $^ "$(BUNDLE)"/Contents/MacOS/
	install_name_tool -change $(change) "$(BUNDLE)"/Contents/MacOS/asebahttp
	install_name_tool -change $(change) "$(BUNDLE)"/Contents/MacOS/asebascratch
