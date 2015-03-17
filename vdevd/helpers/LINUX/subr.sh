#!/bin/sh

# common subroutines for adding and removing devices 
VDEV_PROGNAME=$0


# add a device symlink, but remember which device node it was for,
# so we can remove it later even when the device node no longer exists.
# Make all directories leading up to the link as well.
# arguments:
#  $1  link source 
#  $2  link target
#  $3  vdev device metadata directory
add_link() {

   _LINK_SOURCE="$1"
   _LINK_TARGET="$2"
   _METADATA="$3"

   _DIRNAME=$(echo $_LINK_TARGET | /bin/sed -r "s/[^/]+$//g")

   test -d $_DIRNAME || /bin/mkdir -p $_DIRNAME

   /bin/ln -s $_LINK_SOURCE $_LINK_TARGET
   _RC=$?

   if [ 0 -eq $_RC ]; then

      # save this
      echo $_LINK_TARGET >> $_METADATA/links
   fi

   return 0
}

# remove all of a device's symlinks, stored by add_link.
# arguments: 
#  $1  vdev device metadata directory
remove_links() {

   _METADATA="$1"

   while read _LINKNAME; do

      _DIRNAME=$(echo $_LINKNAME | /bin/sed -r "s/[^/]+$//g")
      
      /bin/rm -f $_LINKNAME
      /bin/rmdir $_DIRNAME 2>/dev/null

   done < $_METADATA/links

   /bin/rm -f $_METADATA/links
   
   return 0
}


# log a message to the logfile, or stdout 
# arguments:
#   $1  message to log 
vdev_log() {
   
   if [ -z "$VDEV_LOGFILE" ]; then
      # stdout 
      echo "[helpers/subr.sh] INFO: $1"
   else

      # logfile 
      echo "[helpers/subr.sh] INFO: $1" >> $VDEV_LOGFILE
   fi 
}



# log a warning to the logfile, or stdout 
# arguments:
#   $1  message to log 
vdev_warn() {
   
   if [ -z "$VDEV_LOGFILE" ]; then
      # stdout 
      echo "[helpers/subr.sh] WARN: $1"
   else

      # logfile 
      echo "[helpers/subr.sh] WARN: $1" >> $VDEV_LOGFILE
   fi 
}


# log an error to the logfile, or stdout 
# arguments:
#   $1  message to log 
vdev_error() {
   
   if [ -z "$VDEV_LOGFILE" ]; then
      # stdout 
      echo "[helpers/subr.sh] ERROR: $1"
   else

      # logfile 
      echo "[helpers/subr.sh] ERROR: $1" >> $VDEV_LOGFILE
   fi 
}


# log a message to vdev's log and exit 
#   $1 is the exit code 
#   $2 is the (optional) message
fail() {

   _CODE="$1"
   _MSG="$2"

   if [ -n "$_MSG" ]; then
      vdev_log "$VDEV_PROGNAME '$VDEV_PATH': $_MSG"
   fi

   exit $_CODE
}


# print the list of device drivers in a sysfs device path 
#   $1  sysfs device path
drivers() {
   
   _SYSFS_PATH="$1"

   # strip trailing '/'
   _SYSFS_PATH=$(echo $_SYSFS_PATH | /bin/sed -r "s/[/]+$//g")
   
   while [ -n "$_SYSFS_PATH" ]; do
      
      # driver name is the base path name of the link target of $_SYSFS_PATH/driver
      test -L $_SYSFS_PATH/driver && /bin/readlink $_SYSFS_PATH/driver | /bin/sed -r "s/[^/]*\///g"

      # search parent 
      _SYSFS_PATH=$(echo $_SYSFS_PATH | /bin/sed -r "s/[^/]+$//g" | /bin/sed -r "s/[/]+$//g")
      
   done
}


# print the list of subsystems in a sysfs device path 
#  $1   sysfs device path 
# NOTE: uniqueness is not guaranteed!
subsystems() {

   _SYSFS_PATH="$1"

   # strip trailing '/'
   _SYSFS_PATH=$(echo $_SYSFS_PATH | /bin/sed -r "s/[/]+$//g")
   
   while [ -n "$_SYSFS_PATH" ]; do
      
      # subsystem name is the base path name of the link target of $_SYSFS_PATH/subsystem
      test -L $_SYSFS_PATH/subsystem && /bin/readlink $_SYSFS_PATH/subsystem | /bin/sed -r "s/[^/]*\///g"

      # search parent 
      _SYSFS_PATH=$(echo $_SYSFS_PATH | /bin/sed -r "s/[^/]+$//g" | /bin/sed -r "s/[/]+$//g")
      
   done
}


# load firmware for a device 
# $1   the sysfs device path 
# $2   the path to the firmware 
# return 0 on success
# return 1 on error
load_firmware() {
   
   _SYSFS_PATH="$1"
   _FIRMWARE_PATH="$2"
   _SYSFS_FIRMWARE_PATH=$VDEV_OS_SYSFS_MOUNTPOINT/$_SYSFS_PATH

   test -e $_SYSFS_FIRMWARE_PATH/loading || return 1
   test -e $_SYSFS_FIRMWARE_PATH/data || return 1
   
   echo 1 > $_SYSFS_FIRMWARE_PATH/loading
   /bin/cat $_FIRMWARE_PATH > $_SYSFS_FIRMWARE_PATH/data
   
   _RC=$?
   if [ $_RC -ne 0 ]; then 
      # abort 
      echo -1 > $_SYSFS_FIRMWARE_PATH/loading
   else 
      # succes
      echo 0 > $_SYSFS_FIRMWARE_PATH/loading
   fi

   return $_RC
}
