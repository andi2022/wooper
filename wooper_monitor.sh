#!/system/bin/sh
# version 1.1.1

logfile="/data/local/tmp/wooper_monitor.log"
exeggcute="/data/local/tmp/config.json"
origin=$(cat $exeggcute | tr , '\n' | grep -w 'device_name' | awk -F "\"" '{ print $4 }')
android_version=`getprop ro.build.version.release | sed -e 's/\..*//'`
updatecheck=0

source /data/local/wooper_versions
export discord_webhook
export useMonitor
export monitor_interval
export update_check_interval
export debug
export recreate_exeggcute_config
export exeggcute_died
export pogo_died
export pogo_not_focused


update_check=$((update_check_interval/monitor_interval))

#Create logfile
if [ ! -e /data/local/tmp/wooper_monitor.log ] ;then
	touch /data/local/tmp/wooper_monitor.log
fi

# stderr to logfile
exec 2>> $logfile

# logger
logger() {
if [[ ! -z $discord_webhook ]] ;then
  echo "`date +%Y-%m-%d_%T` wooper_monitor.sh: $1" >> $logfile
  if [[ -z $origin ]] ;then
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_monitor.sh\", \"content\": \" $1 \"}"  $discord_webhook &>/dev/null
  else
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_monitor.sh\", \"content\": \" $origin: $1 \"}"  $discord_webhook &>/dev/null
  fi
else
  echo "`date +%Y-%m-%d_%T` wooper.sh: $1" >> $logfile
fi
}

check_for_updates() {
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Checking for updates" >> $logfile
	/system/bin/wooper.sh -ua
}

stop_start_exeggcute () {
	am force-stop com.nianticlabs.pokemongo &  rm -rf /data/data/com.nianticlabs.pokemongo/cache/* & am force-stop com.gocheats.launcher
	sleep 5
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Start exeggcute launcher" >> $logfile
	/system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
	sleep 1
}

stop_pogo () {
	am force-stop com.nianticlabs.pokemongo & rm -rf /data/data/com.nianticlabs.pokemongo/cache/*
	sleep 5
	[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Killing pogo and clearing junk" >> $logfile
}

echo "`date +%Y-%m-%d_%T` [MONITORBOT] Starting exeggcute data monitor in 5 mins, loop is $monitor_interval seconds" >> $logfile
sleep 300
while :
do
	[[ $useMonitor == "false" ]] && echo "`date +%Y-%m-%d_%T` wooper_monitor stopped" >> $logfile && exit 1

	until ping -c1 8.8.8.8 >/dev/null 2>/dev/null
	do
		[[ $( awk '/./{line=$0} END{print line}' $logfile | grep 'No internet' | wc -l) != 1 ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] No internet, pay the bill?" >> $logfile
		sleep 60
	done

	[[ -z $origin ]] && origin=$(cat $aconf | tr , '\n' | grep -w 'deviceName' | awk -F "\"" '{ print $4 }')

        updatecheck=$(($updatecheck+1))
        if [[ $updatecheck -gt $update_check ]] ;then
		echo  "`date +%Y-%m-%d_%T` [MONITORBOT] Checking Exeggcute and Pogo for update" >> $logfile
		updatecheck=0
		check_for_updates
	fi

	if [ -d /data/data/com.gocheats.launcher ] && [ -s /data/local/tmp/config.json ]
		then
			[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Exeggcute config.json looks good" >> $logfile
	else
			echo "`date +%Y-%m-%d_%T` [MONITORBOT] Exeggcute config.json does not exist or is empty! Let's fix that!" >> $logfile
			[[ $recreate_exeggcute_config == "true" ]] && logger "exeggcute config.json does not exist or is empty! Let's fix that!"
			/system/bin/wooper.sh -ic
			[[ $debug == "true" ]] && echo "`date +%Y-%m-%d_%T` [MONITORBOT] Fixed config" >> $logfile
			stop_start_exeggcute
			sleep $monitor_interval
			continue
	fi

	# Capture the logcat output
	log_output=$(logcat -d -s "Exeggcute")

	# Check if the logcat contains a mismatch game version.
	if echo "$log_output" | grep -q "Mismatching game version!"; then
		logger "Mismatching game version detected"
	fi

	# Check if the logcat contains a License validation error
	if echo "$log_output" | grep -q "License validation failed!"; then
		logger "License Validation error found"
	fi

    # Check if exeggcute is not running
    if ! pgrep -f "com.gocheats.launcher"
    then
        echo "`date +%Y-%m-%d_%T` [MONITORBOT] exeggcute is not running. Let's fix that!" >> $logfile
		[[ $exeggcute_died == "true" ]] && logger "exeggcute is not running. Let's fix that!"
		stop_start_exeggcute
        sleep 5
    fi

	focusedapp=$(dumpsys window windows | grep -E 'mFocusedApp'| cut -d / -f 1 | cut -d " " -f 7)
    if [ "$focusedapp" != "com.nianticlabs.pokemongo" ]
    then
        echo "`date +%Y-%m-%d_%T` [MONITORBOT] Something is not right! PoGo is not in focus. Killing PoGo and clearing junk" >> $logfile
		[[ $pogo_not_focused == "true" ]] && logger "Something is not right! PoGo is not in focus. Killing PoGo and clearing junk."
		stop_pogo
        sleep 5
    fi

	sleep $monitor_interval
done