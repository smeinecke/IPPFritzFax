#!/bin/sh

# Create necessary directories
mkdir -p /var/run/dbus
mkdir -p /var/spool/avahi
mkdir -p /tmp/spool
mkdir -p /tmp/crt

# Set environment variables
export PATH=/app/bin:/app/faxserver/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_LIBRARY_PATH=/app/install/lib

# Change to working directory
cd /app

# Process command line arguments
for i in "$@"; do
  set X $(echo $i | sed 's,=, ,')
  shift
  case $1 in
    -pass*) echo "password=$2" ;;
    -tel*) echo "telFrom=$2" ;;
    -user*) echo "user=$2" ;;
    -url*) echo "url=$2" ;;
    *)
      echo "Unknown argument '$1'" >&2
      exit 99
    ;;
  esac
done > ~/.credentials

# Start D-Bus system daemon
echo "Starting D-Bus system daemon..."
dbus-uuidgen --ensure
dbus-daemon --system --nofork --nopidfile --nosyslog &

# Wait for D-Bus to be ready
sleep 2

# Start Avahi daemon
echo "Starting Avahi daemon..."
avahi-daemon -D --no-drop-root --no-rlimits

# Start Avahi DNS configuration daemon
echo "Starting Avahi DNS configuration daemon..."
avahi-dnsconfd -D

# Start IPP server
echo "Starting IPP server..."
exec ippserver -C faxserver -K crt -d spool -r _universal
