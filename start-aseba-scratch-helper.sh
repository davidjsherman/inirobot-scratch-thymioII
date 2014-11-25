#! /bin/bash

#
DIR=$HOME
DBUSFILE=$DIR/.dbus.sh

function can_connect_to_dbus () { 
    dbus-send --print-reply --dest=org.freedesktop.DBus \
	--type=method_call / org.freedesktop.DBus.GetId > /dev/null 2>&1
}

#
DBUS_SESSION_BUS_ADDRESS=unix:path=$(launchctl getenv DBUS_FINK_SESSION_BUS_SOCKET)
echo DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:=invalid:/}
export DBUS_SESSION_BUS_ADDRESS

[ -f $DBUSFILE ] && . $DBUSFILE

# If we can't connect to DBus, try to launch a session
if ! can_connect_to_dbus; then
  echo "Launching D-Bus session"
  dbus-launch --sh-syntax | tee $DBUSFILE
  . $DBUSFILE
fi

# If we can connect to the session, launch an asebamedulla process
if can_connect_to_dbus; then
    killall asebamedulla > /dev/null 2>&1 # avoid conflicts
    # asebamedulla ser:device=/dev/cu.usbmodem411
    asebamedulla ser:name=Thymio-II &
    ./aseba-scratch-dbus.perl daemon > aseba-scratch.log 2>&1 &
    disown -a
else 
    echo "Failed to launch session DBUS, bailing out."
fi

# Show processes
sleep 1
ps -cA | egrep -w 'dbus-daemon|asebamedulla|aseba-scratch'
