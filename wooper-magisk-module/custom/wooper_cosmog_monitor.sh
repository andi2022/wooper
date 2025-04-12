#!/system/bin/sh
# version 1.3.2

logfile="/data/local/tmp/wooper_monitor.log"
MODDIR="/data/adb/modules/wooper"
tmp="/data/local/tmp"
mitm_config="$tmp/cosmog.json"
mitm_package="com.nianticlabs.pokemongo.ares"
mitm_startcmd="am start -n $mitm_package/$mitm_package.MainActivity"
pogo_package="com.nianticlabs.pokemongo"
wooper_versions="/data/local/wooper_versions"
origin=$(cat $mitm_config | tr , '\n' | grep -w 'device_name' | awk -F "\"" '{ print $4 }')
rotom="$(grep rotom_url $mitm_config | cut -d \" -f 4)"
rotom_host="$(echo $rotom | cut -d / -f 3 | cut -d : -f 1)"
rotom_port="$(echo $rotom | cut -d / -f 3 | cut -sd : -f 2)"  # if there is a manual port
rotom_proto="$(echo $rotom | cut -d : -f 1)"
if [ -z "$rotom_port" ]; then  # no manual port defined
	rotom_port=80
elif [[ "$rotom_proto" == "wss" ]]; then
	rotom_port=443
fi
connection_min=1 # Number of upsteam ws connections to require. 
android_version=`getprop ro.build.version.release | sed -e 's/\..*//'`
updatecheck=0

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

# stderr to logfile
exec 2>> $logfile

# logger
logger() {
if [[ ! -z $discord_webhook ]] ;then
  echo "`date +%Y-%m-%d_%T` wooper_cosmog_monitor.sh: $1" >> $logfile
  if [[ -z $origin ]] ;then
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_monitor.sh\", \"content\": \" $1 \"}"  $discord_webhook &>/dev/null
  else
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_monitor.sh\", \"content\": \" $origin: $1 \"}"  $discord_webhook &>/dev/null
  fi
else
  echo "`date +%Y-%m-%d_%T` wooper_gc.sh: $1" >> $logfile
fi
}

source /data/local/wooper_versions
export discord_webhook
export useMonitor
export monitor_interval
export update_check_interval
export debug
export recreate_mitm_config
export mitm_died
export mitm_disconnected
export pogo_died
export pogo_not_focused


update_check=$((update_check_interval/monitor_interval))

check_for_updates() {
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Checking for updates" >> $logfile
	"$MODDIR/wooper_gc.sh" -ua
	sleep 20
}

stop_start_mitm () {
	am force-stop $pogo_package &  rm -rf /data/data/$pogo_package/cache/* & am force-stop $mitm_package
	sleep 5
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Start $mitm launcher" >> $logfile
	$mitm_startcmd
	sleep 1
}

stop_pogo () {
	am force-stop $pogo_package & rm -rf /data/data/$pogo_package/cache/*
	sleep 5
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Killing pogo and clearing junk" >> $logfile
}

reboot_device(){
    logger "Reboot device"
    sleep 10
    /system/bin/reboot
}

stop_start_mitm
echo "`date +%Y-%m-%d_%T` [MONITORBOT] Starting $mitm data monitor in 5 mins, loop is $monitor_interval seconds" >> $logfile
[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] DEBUG sleep command is now starting" >> $logfile
sleep 300
[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] DEBUG Starting data monitor" >> $logfile
while :
do
	[[ $useMonitor == "false" ]] && echo "`date +%Y-%m-%d_%T` wooper_monitor stopped" >> $logfile && exit 1

	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] DEBUG Internet check" >> $logfile
	until ping -c1 8.8.8.8 >/dev/null 2>/dev/null
	do
		[[ $( awk '/./{line=$0} END{print line}' $logfile | grep 'No internet' | wc -l) != 1 ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] No internet, pay the bill?" >> $logfile
		sleep 60
	done

	[[ -z $origin ]] && origin=$(cat $mitm_config | tr , '\n' | grep -w 'device_name' | awk -F "\"" '{ print $4 }')

        updatecheck=$(($updatecheck+1))
        if [[ $updatecheck -gt $update_check ]] ;then
		echo  "`date +%Y-%m-%d_%T` [MONITORBOT] Checking $mitm and Pogo for update" >> $logfile
		updatecheck=0
		check_for_updates
	fi

	if [ -d /data/data/$mitm_package ] && [ -s $mitm_config ]
		then
			[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] $mitm config looks good" >> $logfile
	else
			echo "`date +%Y-%m-%d_%T` [MONITORBOT] $mitm config does not exist or is empty! Let's fix that!" >> $logfile
			[[ $recreate_mitm_config == "true" ]] && logger "$mitm config does not exist or is empty! Let's fix that!"
			. "$MODDIR/wooper_cosmog.sh" -ic
			[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Fixed config" >> $logfile
			stop_start_mitm
			sleep $monitor_interval
			continue
	fi

	# Capture the logcat output
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Logcat analysis" >> $logfile
	log_output=$(logcat -d -s "cosmog")

	# Check if the logcat contains a mismatch game version.
	if echo "$log_output" | grep -q "Mismatching game version!"; then
		logger "Mismatching game version detected"
		logcat -c
	fi

	# Check if the logcat contains a License validation error
	if echo "$log_output" | grep -q "License validation failed!"; then
		logger "License Validation error found"
		logcat -c
	fi

    # Check if mitm is not running
    if ! pgrep -f $mitm_package
    then
        echo "`date +%Y-%m-%d_%T` [MONITORBOT] $mitm is not running. Let's fix that!" >> $logfile
		[[ $mitm_died == "true" ]] && logger "$mitm is not running. Let's fix that!"
		stop_start_mitm
        sleep 60
    fi

	focusedapp=$(dumpsys activity activities | grep -E 'ResumedActivity' | sed -n '1p' | awk -F '[ =/]+' '{print $5}')
    if [ "$focusedapp" != "$pogo_package" ]
    then
        echo "`date +%Y-%m-%d_%T` [MONITORBOT] Something is not right! PoGo is not in focus. Killing PoGo and clearing junk" >> $logfile
		[[ $pogo_not_focused == "true" ]] && logger "Something is not right! PoGo is not in focus. Killing PoGo and clearing junk."
		stop_pogo
        sleep 20
    fi

	# code for check disconnected state is from jinnatar and his mitm_nanny script (https://github.com/jinnatar/mitm_nanny/tree/main)
	# Dirty hack to resolve a host where no dns tools are available.
	rotom_ip="$(ping -c 1 "$rotom_host" | grep PING | cut -d \( -f 2 | cut -d \) -f 1)"
	if [[ $(ss -pnt | grep pokemongo | grep "${rotom_ip}:${rotom_port}" | wc -l) -lt "$connection_min" ]]; then
		[[ $mitm_disconnected == "true" ]] && logger "mitm is disconnected. Let's fix that!"
		stop_start_mitm
		sleep 20
	fi

	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] wait $monitor_interval seconds before recheck" >> $logfile
	sleep $monitor_interval
done