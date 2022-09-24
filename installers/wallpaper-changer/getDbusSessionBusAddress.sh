#! /bin/bash
# Returns $DBUS_SESSION_BUS_ADDRESS of logged user (in $LOGNAME), using systemctl process.
# If env variable $DBUS_SESSION_BUS_ADDRESS is not empty, just return.
if [ ! -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
	echo ${DBUS_SESSION_BUS_ADDRESS}
	exit 0
fi

# Get the pid of systemctl
systemctl_pid=$(pgrep -u $LOGNAME -n dbus-daemon)

# If systemctl isn't running, just exit silently.
if [ -z "$systemctl_pid" ]; then
  1>&2 echo "No systemctl pid found"
  exit 1
fi

# Grab the DBUS_SESSION_BUS_ADDRESS variable from systemctl's environment.
DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$systemctl_pid/environ | grep '^DBUS_SESSION_BUS_ADDRESS='| cut -d '=' -f 2-)

# Check that we actually found it.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  1>&2 echo "Failed to find bus address"
  exit 1
fi

echo "$DBUS_SESSION_BUS_ADDRESS"
