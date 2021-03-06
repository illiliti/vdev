#!/bin/dash

# Helper to maintain udev compatibility.
# This should be run last, once the device has been initialized

. "$VDEV_HELPERS/subr.sh"
. "$VDEV_HELPERS/subr-event.sh"

# Enumerate udev properties.  This writes the "E" records in the device's equivalent of /run/udev/data/$DEVICE_ID to stdout.
# $1    Device metadata directory; defaults to $VDEV_METADATA if not given 
# Return 0 on success
udev_enumerate_properties() {
   
   local _METADATA _LINE
   
   _METADATA="$1"
   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -f "$_METADATA/properties" ]; then 
      
      /bin/sed \
         -e 's/^VDEV_OS_/E:/g' \
         -e 's/^VDEV_PERSISTENT_/E:ID_/g' \
         -e 's/^VDEV_/E:ID_/g' \
      "$_METADATA/properties"
   fi
      
   return 0
}


# Enumerate udev symlinks.  This writes the "S" records in the device's equivalent of /run/udev/data/$DEVICE_ID to stdout.
# $1    Device metadata directory: defaults to $VDEV_METADATA if not given 
# $2    Global metadata directory: defaults to $VDEV_GLOBAL_METADATA if not given
# $3    /dev mountpoint; defaults to $VDEV_MOUNTPOINT
# Returns 0 on success
udev_enumerate_symlinks() {
   
   local _METADATA _GLOBAL_METADATA _MOUNTPOINT _LINE _STRIPPED_LINE _STRIPPED_LINE2 _OLDIFS

   _METADATA="$1"
   _GLOBAL_METADATA="$2"
   _MOUNTPOINT="$3"
   _OLDIFS="$IFS"
   
   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi

   if [ -z "$_MOUNTPOINT" ]; then 
      _MOUNTPOINT="$VDEV_MOUNTPOINT"
   fi

   if ! [ -f "$_METADATA/links" ]; then 
      return 0
   fi

   while IFS= read -r _LINE; do
   
      _STRIPPED_LINE="${_LINE##$_MOUNTPOINT/}"
      _STRIPPED_LINE="${_STRIPPED_LINE##/}"
      
      # skip metadata directory
      _STRIPPED_LINE2="${_LINE##$_GLOBAL_METADATA/}"
      if [ "$_STRIPPED_LINE" != "$_STRIPPED_LINE2" ]; then 
         continue 
      fi

      echo "S:${_STRIPPED_LINE}"
      
   done < "$_METADATA/links"

   IFS="$_OLDIFS"

   return 0
}


# Enumerate udev tags.  This writes the "G" records in the device's equivalent of /run/udev/data/$DEVICE_ID to stdout.
# $1    Device metadata directory; defaults to $VDEV_METADATA if not given 
# Returns 0 on success 
udev_enumerate_tags() {

   local _METADATA _LINE _OLDIFS
   
   _METADATA="$1"
   
   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   _OLDIFS="$IFS"
   
   if [ -d "$_METADATA/tags" ]; then 

      while IFS= read -r _TAG; do 
         
         echo "G:$_TAG"
      done <<EOF
$(/bin/ls "$_METADATA/tags")
EOF
   fi
   
   IFS="$_OLDIFS"
   
   return 0
}


# Get the current monotonic uptime in microseconds, i.e. for the udev database
# Print it to stdout--it's too big to return.
udev_monotonic_usec() {
   
   /bin/sed 's/\([0-9]\+\)\.\([0-9]\+\)[ ]\+.*/I:\1\20000/g' "/proc/uptime"
   return 0
}



# Generate a udev-compatible device database record, i.e. the file under /run/udev/data/$DEVICE_ID.
# It will be stored under /dev/metadata/udev/data/$DEVICE_ID, which in turn can be symlinked to /run/udev
# $1    Device ID (defaults to the result of vdev_device_id)
# $2    Device metadata directory (defaults to $VDEV_METADATA)
# $3    Global metadata directory (defaults to $VDEV_GLOBAL_METADATA)
# $4    device hierarchy mountpoint (defaults to $VDEV_MOUNTPOINT)
# NOTE: the /dev/metadata/udev directory hierarchy must have been set up (e.g. by dev-setup.sh)
# return 0 on success, and generate /dev/metadata/udev/data/$DEVICE_ID to contain the same information that /run/udev/data/$DEVICE_ID would contain
# return non-zero on error
udev_generate_data() {

   local _DEVICE_ID _METADATA _GLOBAL_METADATA _MOUNTPOINT _UDEV_DATA_PATH _UDEV_DATA_PATH_TMP _RC _INIT_TIME_USEC
   
   _DEVICE_ID="$1"
   _METADATA="$2"
   _GLOBAL_METADATA="$3"
   _MOUNTPOINT="$4"

   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi
   
   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi

   if [ -z "$_MOUNTPOINT" ]; then
      _MOUNTPOINT="$VDEV_MOUNTPOINT"
   fi
   
   _UDEV_DATA_PATH="$_GLOBAL_METADATA/udev/data/$_DEVICE_ID"
   _UDEV_DATA_PATH_TMP="$_GLOBAL_METADATA/udev/data/.$_DEVICE_ID.tmp"
   
   udev_enumerate_symlinks "$_METADATA" "$_GLOBAL_METADATA" "$_MOUNTPOINT" >> "$_UDEV_DATA_PATH_TMP"
   _RC=$?

   if [ $_RC -ne 0 ]; then 

      /bin/rm -f "$_UDEV_DATA_PATH_TMP"
      vdev_error "udev_enumerate_symlinks rc = $_RC"
      return $_RC
   fi 
   udev_monotonic_usec >> "$_UDEV_DATA_PATH_TMP"

   udev_enumerate_properties "$_METADATA" >> "$_UDEV_DATA_PATH_TMP"
   _RC=$?

   if [ $_RC -ne 0 ]; then 

      /bin/rm -f "$_UDEV_DATA_PATH_TMP"
      vdev_error "udev_enumerate_properties rc = $_RC"
      return $_RC
   fi 

   udev_enumerate_tags "$_METADATA" >> "$_UDEV_DATA_PATH_TMP"
   _RC=$?

   if [ $_RC -ne 0 ]; then 
      
      /bin/rm -f "$_UDEV_DATA_PATH_TMP"
      vdev_error "udev_enumerate_tags rc = $_RC"
      return $_RC
   fi 

   /bin/mv "$_UDEV_DATA_PATH_TMP" "$_UDEV_DATA_PATH"
   return $?
}


# remove udev data, from /dev/metadata/udev/data/$DEVICE_ID 
# $1    The device ID (defaults to the string generated by vdev_device_id)
# $2    The global metadata directory (defaults to $VDEV_GLOBAL_METADATA)
# return 0 on success
# return nonzero on error
udev_remove_data() {
   
   local _DEVICE_ID _GLOBAL_METADATA
   
   _DEVICE_ID="$1"
   _GLOBAL_METADATA="$2"

   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi
   
   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi

   _UDEV_DATA_PATH="$_GLOBAL_METADATA/udev/data/$_DEVICE_ID"

   /bin/rm -f "$_UDEV_DATA_PATH"
   return $?
}


# Generate a udev-compatible symlinks index, i.e. the device-specific directories under /run/udev/links/ that contain this given device.
# For each symlink, create a directory in /dev/metadata/udev/links that contains the serialized links path relative to the mountpoint, and put 
# the udev device ID within that directory.  For example, /dev/disk/by-id/ata-MATSHITADVD-RAM_UJ890_UG99_083452 gets a directory 
# called /dev/metadata/udev/links/\x2fdisk\x2fby-id\x2fata-MATSHITADVD-RAM_UJ890_UG99_083452, and a file named after the device ID (e.g. b8:0) 
# gets created within it.
# $1    The device ID (defaults to the string generated by vdev_device_id)
# $2    The device metadata hierarchy (defaults to $VDEV_METADATA)
# $3    The global metadata hierarchy (defaults to $VDEV_GLOBAL_METADATA)
# $4    The device hierarchy mountpoint (defaults to $VDEV_MOUNTPOINT)
# NOTE: the /dev/metadata/udev directory hierarchy must have been set up (e.g. by dev-setup.sh)
# return 0 on success 
# return nonzero on error 
udev_generate_links() {

   local _RC _DEVICE_ID _METADATA _GLOBAL_METADATA _MOUNTPOINT _LINE _STRIPPED_LINE _STRIPPED_LINE2 _LINK_DIR _OLDIFS

   _DEVICE_ID="$1"
   _METADATA="$2"
   _GLOBAL_METADATA="$3"
   _MOUNTPOINT="$4"
   _OLDIFS="$IFS" 

   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi

   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi
   
   if [ -z "$_MOUNTPOINT" ]; then 
      _MOUNTPOINT="$VDEV_MOUNTPOINT"
   fi

   if ! [ -f "$_METADATA/links" ]; then 
      return 0
   fi
      
   while IFS= read -r _LINE; do
   
      _STRIPPED_LINE="${_LINE##$_MOUNTPOINT}"
      
      _LINK_DIR="$(vdev_serialize_path "$_STRIPPED_LINE")"

      if [ -z "$_LINK_DIR" ]; then 
         vdev_warn "Empty link: $_LINE"
         continue 
      fi

      # expand
      _LINK_DIR="$_GLOBAL_METADATA/udev/links/$_LINK_DIR"

      if ! [ -d "$_LINK_DIR" ]; then 

         /bin/mkdir -p "$_LINK_DIR"
         _RC=$?

         if [ $_RC -ne 0 ]; then 
            
            vdev_error "mkdir $_LINK_DIR failed"
            break
         fi
      
      else

         # TODO: is it possible for there to be duplicate symlinks anymore?  Old udev bug reports suggest as much.
         vdev_warn "Duplicate symlink for $_DEVICE_ID"
      fi

      echo "" > "$_LINK_DIR/$_DEVICE_ID"
      RC=$?

      if [ $_RC -ne 0 ]; then 

         vdev_error "Indexing link at $_LINK_DIR/$_DEVICE_ID failed"
         break
      fi 
 
   done < "$_METADATA/links"

   IFS="$_OLDIFS"

   return $_RC
}


# remove the udev symlink reverse index
# $1    The device ID (defaults to the string generated by vdev_device_id)
# $2    The device metadata directory (defaults to $VDEV_GLOBAL_METADATA)
# $3    The global metadata directory (defaults to $VDEV_GLOBAL_METADATA)
# $4    The device hierarchy mountpoint (defaults to $VDEV_MOUNTPOINT)
# return 0 on success 
# return nonzero on error
udev_remove_links() {
   
   local _RC _DEVICE_ID _MOUNTPOINT _LINE _STRIPPED_LINE _LINK_DIR _OLDIFS _METADATA _GLOBAL_METADATA

   _DEVICE_ID="$1"
   _METADATA="$2"
   _GLOBAL_METADATA="$3"
   _MOUNTPOINT="$4"
   _OLDIFS="$IFS"

   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi

   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi
   
   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi

   if [ -z "$_MOUNTPOINT" ]; then 
      _MOUNTPOINT="$VDEV_MOUNTPOINT"
   fi
    
   # find each link
   if ! [ -f "$_METADATA/links" ]; then 
      return 0
   fi

   while IFS= read -r _LINE; do
      
      _STRIPPED_LINE="${_LINE##$_MOUNTPOINT}"
      
      _LINK_DIR="$(vdev_serialize_path "$_STRIPPED_LINE")"

      if [ -z "$_LINK_DIR" ]; then 
         vdev_warn "Empty link: $_LINK_DIR"
         continue 
      fi

      # expand
      _LINK_DIR="$_GLOBAL_METADATA/udev/links/$_LINK_DIR"

      if ! [ -d "$_LINK_DIR" ]; then 
         continue
      else

         /bin/rm -rf $_LINK_DIR
         
         # TODO: is it possible for there to be duplicate symlinks anymore?  Old udev bug reports suggest as much.
         if [ $? -ne 0 ]; then 
            vdev_warn "Link index directory not empty: $_LINK_DIR"
         fi
      fi

   done < "$_METADATA/links"

   IFS="$_OLDIFS"

   return 0
}


# Generate a udev-compatible tags index, i.e. the tag-to-device index under /run/udev/tags that contain this given device.
# For each tag, touch an empty file in /dev/metadata/udev/tags/$TAG/$DEVICE_ID.
# NOTE: the /dev/metadata/udev directory hierarchy must have been set up (e.g. by dev-setup.sh)
# $1    Device ID (defaults to the result of vdev_device_id)
# $2    device metadata directory (defaults to $VDEV_METADATA)
# $2    global metadata directory (defaults to $VDEV_GLOBAL_METADATA)
# return 0 on success 
# return nonzero on error 
udev_generate_tags() {
   
   local _RC _DEVICE_ID _METADATA _GLOBAL_METADATA _LINE _TAGDIR _OLDIFS

   _DEVICE_ID="$1"
   _METADATA="$2"
   _GLOBAL_METADATA="$3"
   _OLDIFS="$IFS"
   _RC=0
   
   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi

   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -z "$_GLOBAL_METADATA" ]; then 
      _GLOBAL_METADATA="$VDEV_GLOBAL_METADATA"
   fi
   
   if [ -d "$_METADATA/tags" ]; then 
      while IFS= read -r _LINE; do 
         
         _TAGDIR="$_GLOBAL_METADATA/udev/tags/$_LINE"
         
         if ! [ -d "$_TAGDIR" ]; then 

            /bin/mkdir -p "$_TAGDIR"
            _RC=$?

            if [ $_RC -ne 0 ]; then 

               vdev_warn "mkdir $_TAGDIR failed"
               break
            fi
         fi

         echo "" > "$_TAGDIR/$_DEVICE_ID"
         RC=$?

         if [ $_RC -ne 0 ]; then 

            vdev_warn "create $_TAGDIR/$_DEVICE_ID failed"
            break
         fi
      done <<EOF
$(/bin/ls "$_METADATA/tags")
EOF
   fi
   
   IFS="$_OLDIFS"
   
   return $_RC
}


# Remove udev tags for this device 
# $1    Device ID (defaults to the result of vdev_device_id)
# $2    Device metadata directory (defaults to $VDEV_METADATA)
# return 0 on success
udev_remove_tags() {
   
   local _RC _DEVICE_ID _METADATA _LINE _TAGDIR _OLDIFS

   _DEVICE_ID="$1"
   _METADATA="$2"
   _OLDIFS="$IFS"
   
   if [ -z "$_DEVICE_ID" ]; then 
      _DEVICE_ID="$(vdev_device_id)"
   fi

   if [ -z "$_METADATA" ]; then 
      _METADATA="$VDEV_METADATA"
   fi

   if [ -d "$_METADATA/tags" ]; then 
      while IFS= read -r _LINE; do 
         
         _TAGDIR="$_METADATA/udev/tags"
         
         if ! [ -d "$_TAGDIR" ]; then 
            continue 
         else

            /bin/rm -f "$_TAGDIR/$_DEVICE_ID"
            /bin/rmdir "$_TAGDIR" || true
         fi
      done <<EOF
$(/bin/ls "$_METADATA/tags")
EOF
   fi
   
   IFS="$_OLDIFS"
   
   return 0
}


# convert an event's text into a udev-compatible event text 
# $1    the action (defaults to $VDEV_ACTION)
# $2    the sysfs device path (defaults to $VDEV_OS_DEVPATH)
# $3    the subsystem name (defaults to $VDEV_OS_SUBSYSTEM)
# $4    the sequence number from the kernel (defaults to $VDEV_OS_SEQNUM)
# $5    the metadata directory for this device (defaults to $VDEV_METADATA)
# Also pulls in VDEV_PATH, VDEV_MAJOR, VDEV_MINOR, VDEV_OS_IFINDEX, VDEV_OS_DRIVER from the caller environment, if they are non-empty
# (VDEV_PATH will be treated as empty if it is "UNKNOWN").
# returns 0 on success
udev_event_generate_text() {

   event_generate_text "$1" "$2" "$3" "$4" "$5" | \
   /bin/sed \
      -e 's/^VDEV_OS_//g' \
      -e 's/^VDEV_PERSISTENT_/ID_/g' \
      -e 's/^VDEV_/ID_/g'
   
   return 0
}


# entry point
# return 0 on success
main() {

   local _DEVICE_ID _RC

   # if our path is still "UNKNOWN", then generate a device ID and go with that for metadata
   if [ "$VDEV_PATH" = "UNKNOWN" ]; then 
      
      VDEV_METADATA="$VDEV_GLOBAL_METADATA/dev"/"$(vdev_device_id)"
      /bin/mkdir -p "$VDEV_METADATA"
   fi

   _DEVICE_ID="$(vdev_device_id)"

   if [ "$VDEV_ACTION" = "add" ]; then 
      
      # add udev data
      # echo "udev_generate_data $_DEVICE_ID" >> /tmp/udev-compat.log
      udev_generate_data "$_DEVICE_ID" "$VDEV_METADATA" "$VDEV_GLOBAL_METADATA" "$VDEV_MOUNTPOINT" || vdev_error "Failed to generate udev data for $VDEV_PATH"
      
      # echo "udev_generate_links $_DEVICE_ID" >> /tmp/udev-compat.log
      udev_generate_links "$_DEVICE_ID" "$VDEV_METADATA" "$VDEV_GLOBAL_METADATA" "$VDEV_MOUNTPOINT" || vdev_error "Failed to generate udev links for $VDEV_PATH"

      # echo "udev_generate_tags $_DEVICE_ID" >> /tmp/udev-compat.log 
      udev_generate_tags "$_DEVICE_ID" "$VDEV_METADATA" "$VDEV_GLOBAL_METADATA" || vdev_error "Failed to generate udev tags for $VDEV_PATH"

   elif [ "$VDEV_ACTION" = "remove" ]; then 

      # remove udev data
      # echo "udev_remove_data $_DEVICE_ID" >> /tmp/udev-compat.log 
      udev_remove_data "$_DEVICE_ID" "$VDEV_GLOBAL_METADATA" || vdev_error "Failed to remove udev data for $VDEV_PATH"

      # echo "udev_remove_links $_DEVICE_ID" >> /tmp/udev-compat.log
      udev_remove_links "$_DEVICE_ID" "$VDEV_METADATA" "$VDEV_GLOBAL_METADATA" "$VDEV_MOUNTPOINT" || vdev_error "Failed to remove udev links for $VDEV_PATH"

      # echo "udev_remove_tags $_DEVICE_ID" >> /tmp/udev-compat.log
      udev_remove_tags "$_DEVICE_ID" "$VDEV_METADATA" || vdev_error "Failed to remove udev tags for $VDEV_PATH"
   fi
   
   # require sequence number and devpath, at least, for event propagation
   if [ -z "$VDEV_OS_SEQNUM" ] || [ -z "$VDEV_OS_DEVPATH" ] || [ -z "$VDEV_OS_SUBSYSTEM" ]; then 
      echo "" >> /tmp/udev-compat.log
      return 0
   fi

   # clear path if UNKNOWN
   if [ "$VDEV_PATH" = "UNKNOWN" ]; then 
      VDEV_PATH=""
   fi

   # propagate to each libudev-compat event queue
   "$VDEV_HELPERS/event-put" -s "$VDEV_GLOBAL_METADATA/udev/events/global" <<EOF
$(udev_event_generate_text "$VDEV_ACTION" "$VDEV_OS_DEVPATH" "$VDEV_OS_SUBSYSTEM" "$VDEV_OS_SEQNUM" "$VDEV_METADATA")
EOF

   echo "event-put $_DEVICE_ID" >> /tmp/udev-compat.log 
   echo "" >> /tmp/udev-compat.log 

   _RC=$?
   return $_RC
}


if [ $VDEV_DAEMONLET -eq 0 ]; then 
   main 
   exit $?
fi
