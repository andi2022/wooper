#!/system/bin/sh
# Version 1.0.0

magiskcmd="/bin/magisk"
pogopkg="com.nianticlabs.pokemongo"
dbupdate="/data/data/com.android.vending/databases/auto_update.db"
dbdata="X'0a19636f6d2e6e69616e7469636c6162732e706f6b656d6f6e676f12001801200228e5a3d8c40738eb87a0c0b4314000480050005a0072007a008201008a010c08f6d1c4a90610c0e9e9eb029001009a0100a20100aa010c08becec2a906108099b6fe02'"
initdir=/data/init
configdir=/data/local/tmp
logdir=/data/local/tmp/init
logfile=$logdir/initrom.log


cd `dirname $0`


makedir(){
	if [ ! -f $initdir/mkdir ]; then
		mkdir -p $initdir
		chmod 755 $initdir
		chown shell $initdir
		chmod 755 $configdir
		chown shell $configdir
		mkdir -p $logdir
		chmod 755 $logdir
		chown shell $logdir
		touch $initdir/mkdir
	fi
}

makedir

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
			
			echo "Logfile was larger than 1 MB and has been replaced."
		else
			echo "Logfile size is within the limit."
		fi
	else
		touch "$logfile"
		chown shell "$logfile"
	fi
}

checklogfile
exec >>"$logfile" 2>&1

log() {
    line="`date +'[%Y-%m-%dT%H:%M:%S %Z]'` $@"
    echo "$line"
}

settimezone(){
	if [ ! -f $initdir/timezone ]; then
			# Fetch the timezone from an online API
			log "Fetch timezone from an online API"
			response=$(curl -s "http://worldtimeapi.org/api/ip")
			
			# Extract the timezone using sed
			timezone=$(echo "$response" | sed -n 's/.*"timezone":"\([^"]*\)".*/\1/p')

			# Check if the timezone was fetched successfully
			if [ -n "$timezone" ]; then
			  log "Detected timezone: $timezone"
			  # Set the timezone on the Android device
			  setprop persist.sys.timezone "$timezone"
			  log "Timezone set to $timezone"
			else
			  log "Failed to detect timezone"
			fi
		touch $initdir/timezone
		sleep 1
	fi
}

delete_tmp_files(){
	log 'Deleting init temp files'
	deleted_files=""
	find $initdir ! -name 'initrom.log' ! -name "timezone" ! -name 'mkdir' ! -name 'bootpatch' ! -name 'set' ! -name 'disableupdpogo' -type f -exec rm -f {} + | tee -a $deleted_files
	log "Deleted files: $deleted_files"
}



do_settings() {
	if [ ! -f $initdir/set ]; then
		log 'Setting Navigation bar for Pogo'
		settings put global policy_control immersive.full=com.nianticlabs.pokemongo
		settings put secure immersive_mode_confirmations confirmed
		settings put global heads_up_enabled 0
		log 'Setting Bluetooth off'
		settings put global bluetooth_disabled_profiles 1
		settings put global bluetooth_on 0
		log 'Setting no play check for apps'
		settings put global package_verifier_user_consent -1
		touch $initdir/set
	fi
}

setup_magisk_settings() {
	if [ ! -f $initdir/magiskset ]; then
		denylist_count=`magisk --sqlite 'select count(*) from denylist' | awk -F= '{ print $2 }'`

		log 'Adding root access for shell'
		shell_uid=`id -u shell`
		$magiskcmd --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($shell_uid,2,0,1,1);"

		if [ `id -u` -ne 0 ]; then
			log 'Root is needed from this point forward. Re-run as root.'
			exit 1
		fi

		log 'Adding packages to denylist'
		$magiskcmd --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.google.android.gms','com.google.android.gms');"
		$magiskcmd --sqlite "REPLACE INTO denylist (package_name, process) VALUES ('com.google.android.gms', 'com.google.android.gms.unstable');"
		$magiskcmd --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.nianticlabs.pokemongo','com.nianticlabs.pokemongo');"

		denylist_count_now=`$magiskcmd --sqlite 'select count(*) from denylist' | awk -F= '{ print $2 }'`
		if [ $denylist_count -ne $denylist_count_now ]; then
			log 'Updated magisk DB for zygisk,su policy,denylist'
		fi
		
		log 'Allowing package install permission for Magisk'
		appops set com.topjohnwu.magisk REQUEST_INSTALL_PACKAGES allow
		
		touch $initdir/magiskset
		sleep 5
	fi
}

pogo_disable_update(){
	if [ ! -f $initdir/disableupdpogo ]; then
		log 'Check if Pogo already in Play Store updates db'
		result=$(sqlite3 $dbupdate "SELECT * FROM auto_update  WHERE pk = $pogopkg;")
		sleep 2
		if [ -n "$result" ]; then
			log 'Pogo found in the db. Updating the entry'
			sqlite3 $dbupdate "UPDATE auto_update SET data = $dbdata WHERE pk = $pogopkg;"
		else
			log 'Pogo not found in the db. Creating table and inserting the entry'
			sqlite3 $dbupdate "CREATE TABLE IF NOT EXISTS android_metadata (locale TEXT);"
			sqlite3 $dbupdate "INSERT INTO android_metadata VALUES('en_US');"
			sqlite3 $dbupdate "CREATE TABLE IF NOT EXISTS auto_update (data BLOB, pk TEXT PRIMARY KEY);"
			sqlite3 $dbupdate "INSERT INTO auto_update (data, pk) VALUES ($dbdata, '$pogopkg');"
			sqlite3 $dbupdate "CREATE TABLE IF NOT EXISTS auto_update_audit(data_table_pk TEXT,data BLOB,timestamp INTEGER,reason TEXT,trace TEXT);"
		fi
		touch $initdir/disableupdpogo
	fi
}

log 'ATV Booted.'
if [ ! -f $initdir/initend ]; then
    settimezone
	do_settings
	configureUnifyKeys
	setup_magisk_settings
	clear_google_data
	delete_tmp_files
	touch $initdir/initend
fi
pogo_disable_update
log 'Done'