#!/system/bin/sh
# version 1.0.0

# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

logfile="/data/local/tmp/wooper.log"

#Create/Check logfile (Cleanup if bigger than 1MB)
checklogfile() {
	# Check if the logfile exists
	if [ -f "$logfile" ]; then
		# Get the size of the logfile in bytes
		filesize=$(stat -c%s "$logfile")
		
		# Check if the filesize is greater than 1 MB (1048576 bytes)
		if [ $filesize -gt 1048576 ]; then
			# Delete the logfile
			rm "$logfile"
			
			# Create a new logfile
			touch "$logfile"
			
			# Change the ownership to 'shell'
			chown shell "$logfile"

      echo "`date +%Y-%m-%d_%T` $logfile was larger than 1 MB and has been replaced." >> $logfile 
		fi
	else
		touch "$logfile"
		chown shell "$logfile"
    echo "`date +%Y-%m-%d_%T` $logfile created" >> $logfile 
	fi
}
checklogfile

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") eMagisk | ${*}" >>$logfile
    /system/bin/log -t wooper.sh -p i "${@}"
}

echo "`date +%Y-%m-%d_%T` ##################### Boot #####################" >> $logfile
echo "`date +%Y-%m-%d_%T` Waiting for boot to complete..." >> $logfile

# credit for the shit below:
#   Advanced Charging Controller (teh good stuff)
# wait until data is decrypted
until [ -d /sdcard/Download ]; do
    sleep 10
done

# wait until zygote exists, and
pgrep zygote >/dev/null && {
    # wait until sys.boot_comlpeted returns 1
    until [ .$(getprop sys.boot_completed) = .1 ]; do
        sleep 10
    done
}

#wait on internet
until ping -c1 8.8.8.8 >/dev/null 2>/dev/null || ping -c1 1.1.1.1 >/dev/null 2>/dev/null; do
    sleep 10
done
echo "`date +%Y-%m-%d_%T` Internet connection available" >> $logfile

delay_after_reboot(){
  uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
  # Check if uptime is less than 120 seconds (2 minutes)
  if [ "$uptime_seconds" -lt 120 ]; then
      echo "$(date +%Y-%m-%d_%T) Wait 30 seconds, safety delay" >> $logfile
      sleep 30
  fi
}
delay_after_reboot

if [ -f "$MODDIR/init.sh" ]; then
    echo "`date +%Y-%m-%d_%T` Starting init.sh" >> $logfile
    "$MODDIR/init.sh"
fi

echo "`date +%Y-%m-%d_%T` ################ Boot completed ################" >> $logfile

if [ -f "$MODDIR/wooper.sh" ]; then
    sleep 20
    echo "`date +%Y-%m-%d_%T` Starting wooper.sh" >> $logfile
    "$MODDIR/wooper.sh" -ua
fi