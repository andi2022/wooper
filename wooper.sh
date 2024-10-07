#!/system/bin/sh
# version 1.7.13

#Version checks
Ver55wooper="1.2"
Ver55cron="1.3"
VerMonitor="1.2.3"

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

android_version=`getprop ro.build.version.release | sed -e 's/\..*//'`
appdir="/data/wooper"
exeggcute="/data/local/tmp/config.json"
wooper_versions="/data/local/wooper_versions"
wooper_adb_keys="/data/local/wooper_adb_keys"
adb_keys="/data/misc/adb/adb_keys"
branchoverwrite="/data/local/tmp/branch"
[[ -f /data/local/wooper_download ]] && wooper_download=$(/system/bin/grep url /data/local/wooper_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/wooper_download ]] && wooper_user=$(/system/bin/grep authUser /data/local/wooper_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/wooper_download ]] && wooper_pass=$(/system/bin/grep authPass /data/local/wooper_download | awk -F "=" '{ print $NF }')
if [[ -f /data/local/tmp/config.json ]] ;then
    origin=$(/system/bin/cat $exeggcute | /system/bin/tr , '\n' | /system/bin/grep -w 'device_name' | awk -F "\"" '{ print $4 }')
else
    origin=$(/system/bin/cat /data/local/initDName)
fi
pogo_package_samsung="com.nianticlabs.pokemongo.ares"
pogo_package_google="com.nianticlabs.pokemongo"

# stderr to logfile
exec 2>> $logfile

# add wooper.sh command to log
echo "" >> $logfile
echo "`date +%Y-%m-%d_%T` ## Executing $(basename $0) $@" >> $logfile


########## Functions

# logger
logger() {
if [[ ! -z $discord_webhook ]] ;then
  echo "`date +%Y-%m-%d_%T` wooper.sh: $1" >> $logfile
  if [[ -z $origin ]] ;then
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper.sh\", \"content\": \" $1 \"}"  $discord_webhook &>/dev/null
  else
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper.sh\", \"content\": \" $origin: $1 \"}"  $discord_webhook &>/dev/null
  fi
else
  echo "`date +%Y-%m-%d_%T` wooper.sh: $1" >> $logfile
fi
}

appdir() {
  if [ ! -d "$appdir" ]; then
    # Create the directory
    mkdir -p "$appdir"
    logger "new app directory $appdir created."
  fi
}

migrate_wooper() {
if [ -f /system/bin/wooper.sh ] && [ ! -f $appdir/wooper.sh ]; then
    cp /system/bin/wooper.sh $appdir/wooper.sh
    chmod +x $appdir/wooper.sh
    logger "wooper.sh copied to new path $appdir"
fi
}

migrate_wooper_monitor() {
  if [ -f /system/bin/wooper_monitor.sh ] && [ ! -f $appdir/wooper_monitor.sh ]; then
    cp /system/bin/wooper_monitor.sh $appdir/wooper_monitor.sh
    chmod +x $appdir/wooper_monitor.sh
    logger "wooper_monitor.sh copied to new path $appdir"
fi
}

cleanup_old_installdir(){
  BASE_PATH=$(dirname "$0")
   if [ -f /system/bin/wooper.sh ]; then
    if [ "$BASE_PATH" = "$appdir" ]; then
      logger "Delete old scripts in /system/bin after migration to $appdir"
      mount_system_rw
      rm -f /system/bin/wooper.sh
      rm -f /system/bin/wooper_new.sh
      rm -f /system/bin/wooper_monitor.sh
      rm -f /system/bin/ping_test.sh
      mount_system_ro
    fi
   fi 
}

delay_after_reboot(){
  uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
  # Check if uptime is less than 120 seconds (2 minutes)
  if [ "$uptime_seconds" -lt 120 ]; then
      echo "$(date +%Y-%m-%d_%T) Wait 30 seconds, safety delay" >> $logfile
      sleep 30
  fi
}

read_versionfile(){
if [[ -f $wooper_versions ]] ;then
discord_webhook=$(grep 'discord_webhook' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
fi
if [[ -z $discord_webhook ]] ;then
  discord_webhook=$(grep discord_webhook /data/local/wooper_download | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
fi

#Scriptbrach
branch=$(grep 'branch' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
if [[ -z $branch ]] ;then
  branch=main
fi

#Overwrite branch with a local config file for testing on a single device
if [ -e "$branchoverwrite" ]; then
    branch=$(grep 'branch' $branchoverwrite | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
fi

  #apk google or samsung
  apk=$(grep '^apk=' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
  if [[ "$apk" == "samsung" ]]; then
      :
  else
      apk="google"
  fi

  if [ "$apk" == "samsung" ]; then
      pogo_package=$pogo_package_samsung
  elif [ "$apk" == "google" ]; then
      pogo_package=$pogo_package_google
  else
      pogo_package=$pogo_package_google
  fi

# apkbundle enabled or disabled
apkm=$(grep '^apkm=' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')

# adbfingerprint anabled or disabled
adbfingerprint=$(grep '^adbfingerprint=' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')

#logger apk=$apk
#logger pogoPackage=$pogo_package
}

read_versionfile


reboot_device(){
    echo "`date +%Y-%m-%d_%T` Reboot device" >> $logfile
    sleep 15
    /system/bin/reboot
}

case "$(uname -m)" in
    aarch64) arch="arm64-v8a";;
    armv8l)  arch="armeabi-v7a";;
esac

mount_system_rw() {
  if [ $android_version -ge 9 ]; then
    # if a magisk module is installed that puts stuff under /system/etc, we're screwed, though.
    # because then /system/etc ends up full of bindmounts.. and you can't place new files under it.
    mount -o remount,rw /
  else
    mount -o remount,rw /system
    mount -o remount,rw /system/etc/init.d
  fi
}

mount_system_ro() {
  if [ $android_version -ge 9 ]; then
    mount -o remount,ro /
  else
    mount -o remount,ro /system
    mount -o remount,ro /system/etc/init.d
  fi
}

download_versionfile() {
# verify download credential file and set download
if [[ ! -f /data/local/wooper_download ]] ;then
    echo "`date +%Y-%m-%d_%T` File /data/local/wooper_download not found, exit script" >> $logfile && exit 1
else
    if [[ $wooper_user == "" ]] ;then
        download="/system/bin/curl -s -k -L --fail --show-error -o"
    else
        download="/system/bin/curl -s -k -L --fail --show-error --user $wooper_user:$wooper_pass -o"
    fi
fi

# download latest version file
until $download $wooper_versions $wooper_download/versions || { echo "`date +%Y-%m-%d_%T` $download $wooper_versions $wooper_download/versions" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download gocheats versions file failed, exit script" >> $logfile ; exit 1; } ;do
    sleep 2
done
dos2unix $wooper_versions
echo "`date +%Y-%m-%d_%T` Downloaded latest versions file"  >> $logfile
read_versionfile
}

download_adb_keys() {
  until $download $wooper_adb_keys $wooper_download/adb_keys || { echo "`date +%Y-%m-%d_%T` $download $wooper_adb_keys $wooper_download/adb_keys" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download adb_keys file failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
  done
  dos2unix $wooper_adb_keys
  echo "`date +%Y-%m-%d_%T` Downloaded latest adb_keys file"  >> $logfile
}

copy_adb_keys_if_newer() {
  # Check if the destination file exists
  if [ ! -f "$adb_keys" ]; then
    logger "Install adb_keys"
    cp -f "$wooper_adb_keys" "$adb_keys"
    chmod 644 $adb_keys
  else
    # Compare file contents
    if ! diff "$wooper_adb_keys" "$adb_keys" >/dev/null; then
      logger "Newer adb_keys found, copy updated version"
      cp -f "$wooper_adb_keys" "$adb_keys"
      chmod 644 "$adb_keys"
    else
      echo "$(date +%Y-%m-%d_%T) latest adb_keys file already installed"  >> "$logfile"
    fi
  fi
}

install_wooper(){
download_versionfile

# search discord webhook url for install log
discord_webhook=$(grep 'discord_webhook' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
if [[ -z $discord_webhook ]] ;then
  discord_webhook=$(grep discord_webhook /data/local/wooper_download | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
fi


    # install 55wooper
	mount_system_rw
	until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55wooper https://raw.githubusercontent.com/andi2022/wooper/$branch/55wooper || { echo "`date +%Y-%m-%d_%T` Download 55wooper failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55wooper
    logger "55wooper installed"

    # install 55cron
    until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/andi2022/wooper/$branch/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55cron
    logger "55cron installed"

    # install cron job
    until /system/bin/curl -s -k -L --fail --show-error -o  $appdir/ping_test.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x $appdir/ping_test.sh
    mkdir /data/crontabs || true
    touch /data/crontabs/root
    echo "15 * * * * /system/bin/ping_test.sh" > /data/crontabs/root
	crond -b -c /data/crontabs
	logger "cron jobs installed"

	# install wooper monitor
	until /system/bin/curl -s -k -L --fail --show-error -o $appdir/wooper_monitor.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper_monitor.sh || { echo "`date +%Y-%m-%d_%T` Download wooper_monitor.sh failed, exit script" >> $logfile ; exit 1; } ;do
		sleep 2
	done
	chmod +x /system/bin/wooper_monitor.sh
	logger "wooper monitor installed"
    mount_system_ro

    # get version
    exeggcuteversions=$(/system/bin/grep 'exeggcute' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    # download exeggcute
    /system/bin/rm -f /sdcard/Download/exeggcute.apk
    until $download /sdcard/Download/exeggcute.apk $wooper_download/com.exeggcute.launcher_v$exeggcuteversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/exeggcute.apk $wooper_download/com.exeggcute.launcher_v$exeggcuteversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download exeggcute failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done

    # let us kill pogo as well and clear data
    /system/bin/am force-stop $pogo_package > /dev/null 2>&1
    /system/bin/pm clear $pogo_package > /dev/null 2>&1

    # Install exeggcute
    /system/bin/pm install -r /sdcard/Download/exeggcute.apk > /dev/null 2>&1
    /system/bin/rm -f /sdcard/Download/exeggcute.apk
    logger "exeggcute installed"

    # Grant su access + settings
	euid="$(dumpsys package com.gocheats.launcher | /system/bin/grep userId | awk -F'=' '{print $2}')"
	magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($euid,2,0,1,1);"
    /system/bin/pm grant com.gocheats.launcher android.permission.READ_EXTERNAL_STORAGE
    /system/bin/pm grant com.gocheats.launcher android.permission.WRITE_EXTERNAL_STORAGE
    logger "exeggcute granted su"

    # download gocheats config file and adjust orgin
    install_config

    # check pogo version else remove+install
    downgrade_pogo

    # start execute
    /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
    sleep 15

    # Set for reboot device
    reboot=1
}

install_config(){
    until $download /data/local/tmp/config.json $wooper_download/config.json || { echo "`date +%Y-%m-%d_%T` $download /data/local/tmp/config.json $wooper_download/config.json" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download exeggcute config file failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done
    /system/bin/sed -i 's,dummy,'$origin',g' $exeggcute
    logger "exeggcute config installed"
}

check_apkinstall_settings(){
  # Desired settings
  desired_package_verifier_enable=0
  desired_verifier_verify_adb_installs=0
  desired_package_verifier_user_consent=-1

  # Get current settings
  current_package_verifier_enable=$(settings get global package_verifier_enable)
  current_verifier_verify_adb_installs=$(settings get global verifier_verify_adb_installs)
  current_package_verifier_user_consent=$(settings get global package_verifier_user_consent)

  # Check and set settings if necessary
  if [ "$current_package_verifier_enable" != "$desired_package_verifier_enable" ]; then
      settings put global package_verifier_enable $desired_package_verifier_enable
      logger "disable package verifier"
  fi

  if [ "$current_verifier_verify_adb_installs" != "$desired_verifier_verify_adb_installs" ]; then
      settings put global verifier_verify_adb_installs $desired_verifier_verify_adb_installs
      logger "disable adb package verifier"
  fi

  if [ "$current_package_verifier_user_consent" != "$desired_package_verifier_user_consent" ]; then
      settings put global package_verifier_user_consent $desired_package_verifier_user_consent
      logger "disable package verifier user consent"
  fi
}

update_all(){
    download_versionfile
    pinstalled=$(dumpsys package $pogo_package | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    pversions=$(/system/bin/grep 'pogo' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    exeggcuteinstalled=$(dumpsys package com.gocheats.launcher | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    exeggcuteversions=$(/system/bin/grep 'exeggcute' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  globalworkers=$(/system/bin/grep 'globalworkers' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  workerscount=$(/system/bin/grep 'workerscount' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  exeggcuteworkerscount=$(grep 'workers_count' $exeggcute | sed -r 's/^ [^:]*: ([0-9]+),?$/\1/')
    playintegrityfixinstalled=$(cat /data/adb/modules/playintegrityfix/module.prop | /system/bin/grep version | head -n1 | /system/bin/sed 's/ *version=v//')    
	  playintegrityfixupdate=$(/system/bin/grep 'playintegrityfixupdate' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')	
	  playintegrityfixversions=$(/system/bin/grep 'playintegrityfixversion' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    if [[ "$apk" = "google" ]] ;then
      if pm list packages | grep -w "^package:$pogo_package_samsung$"; then
        logger "Configured PoGo APK is $apk, a Samsung version is detected and will be uninstalled."
      	am force-stop $pogo_package_samsung
		    sleep 2
		    pm uninstall $pogo_package_samsung
      fi
    fi

    if [[ "$apk" = "samsung" ]] ;then
      if pm list packages | grep -w "^package:$pogo_package_google$"; then
        logger "Configured PoGo APK is $apk, a Google version is detected and will be uninstalled."
      	am force-stop $pogo_package_google
		    sleep 2
		    pm uninstall $pogo_package_google
      fi
    fi

    if [[ "$pinstalled" != "$pversions" ]] ;then
      logger "New pogo version detected, $pinstalled=>$pversions"
        if [[ "$apkm" = "true" ]] ;then
          /system/bin/rm -f /sdcard/Download/pogo.apkm
          /system/bin/rm -f -r /sdcard/Download/pogoapkm
          until $download /sdcard/Download/pogo.apkm $wooper_download/com.nianticlabs.pokemongo_$arch\_$pversions.apkm || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apkm $wooper_download/com.nianticlabs.pokemongo_$arch_$pversions.apkm" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
          done
          mkdir /sdcard/Download/pogoapkm
          logger "Extract pogo.apkm $versions"
          unzip /sdcard/Download/pogo.apkm -d /sdcard/Download/pogoapkm
          /system/bin/rm -f /sdcard/Download/pogo.apkm
        else
          /system/bin/rm -f /sdcard/Download/pogo.apk
          until $download /sdcard/Download/pogo.apk $wooper_download/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $wooper_download/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
          done
        fi
      # set pogo to be installed
      pogo_install="install"
    else
     pogo_install="skip"
     echo "`date +%Y-%m-%d_%T` PoGo already on correct version" >> $logfile
    fi

    if [ "$exeggcuteinstalled" != "$exeggcuteversions" ] ;then
      logger "New exeggcute version detected, $exeggcuteinstalled=>$exeggcuteversions"
      /system/bin/rm -f /sdcard/Download/exeggcute.apk
      until $download /sdcard/Download/exeggcute.apk $wooper_download/com.exeggcute.launcher_v$exeggcuteversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/exeggcute.apk $wooper_download/com.exeggcute.launcher_v$exeggcuteversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download exeggcute failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set exeggcute to be installed
      exeggcute_install="install"
    else
     exeggcute_install="skip"
     echo "`date +%Y-%m-%d_%T` exeggcute already on correct version" >> $logfile
    fi

    if [[ $playintegrityfixupdate == "true" ]] && [ "$playintegrityfixinstalled" != "$playintegrityfixversions" ] ;then
      logger "New PlayIntegrityFix version detected, $playintegrityfixinstalled=>$playintegrityfixversions"
      /system/bin/rm -f /sdcard/Download/playintegrityfix.zip
      until $download /sdcard/Download/playintegrityfix.zip $wooper_download/PlayIntegrityFix_v$playintegrityfixversions.zip || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/playintegrityfix.zip $wooper_download/PlayIntegrityFix_v$playintegrityfixversions.zip" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download PlayIntegrityFix failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
	  # set PlayIntegrityFix to be installed
      playintegrityfix_install="install"
    else
     playintegrityfix_install="skip"
     echo "`date +%Y-%m-%d_%T` PlayIntegrityFix already on correct version or not enabled" >> $logfile
    fi

    if [[ $globalworkers == "true" ]] && [ "$exeggcuteworkerscount" != "$workerscount" ] ;then
      logger "New global workers count detected, $exeggcuteworkerscount=>$workerscount"
	  sed -i "s/\"workers_count\": [0-9]*/\"workers_count\": $workerscount/" $exeggcute
	  logger "New workers count $workerscount is active, restarting exeggcute"
	  am force-stop com.gocheats.launcher
	  sleep 2
	  /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
	else
     echo "`date +%Y-%m-%d_%T` workers count ok or not enabled" >> $logfile
    fi

    if [ ! -z "$exeggcute_install" ] && [ ! -z "$pogo_install" ] && [ ! -z "$playintegrityfix_install" ] ;then
      echo "`date +%Y-%m-%d_%T` All updates checked and downloaded if needed" >> $logfile
      if [ "$exeggcute_install" = "install" ] ;then
        logger "Start updating exeggcute"
        # install gocheats
        am force-stop com.gocheats.launcher
        sleep 2
        pm uninstall com.gocheats.launcher
        sleep 2
        /system/bin/pm install -r /sdcard/Download/exeggcute.apk || { echo "`date +%Y-%m-%d_%T` Install gocheats failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/exeggcute.apk

        # Grant su access + settings after reinstall
        euid="$(dumpsys package com.gocheats.launcher | /system/bin/grep userId | awk -F'=' '{print $2}')"
        magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($euid,2,0,1,1);"
        /system/bin/pm grant com.gocheats.launcher android.permission.READ_EXTERNAL_STORAGE
        /system/bin/pm grant com.gocheats.launcher android.permission.WRITE_EXTERNAL_STORAGE
		    /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
        logger "exeggcute updated, launcher started"
      fi
      if [ "$pogo_install" = "install" ] ;then
        logger "Start updating pogo"
        # install pogo
          am force-stop com.gocheats.launcher
          am force-stop $pogo_package
          sleep 2
          pm uninstall $pogo_package
          sleep 2
          if [ "$apkm" = "true" ] ;then
            /system/bin/pm install -r /sdcard/Download/pogoapkm/base.apk && /system/bin/pm install -p com.nianticlabs.pokemongo -r /sdcard/Download/pogoapkm/split_config.*.apk || { logger "install pogo failed, downgrade perhaps? Exit script" ; exit 1; }
            /system/bin/rm -f -r /sdcard/Download/pogoapkm
          else
            /system/bin/pm install -r /sdcard/Download/pogo.apk || { echo "`date +%Y-%m-%d_%T` Install pogo failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
            /system/bin/rm -f /sdcard/Download/pogo.apk
          fi
        /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
        logger "PoGo $pversions, launcher started"
        # restart wooper monitor
        if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }') == "true" ]] && [ -f /system/bin/wooper_monitor.sh ] ;then
          checkMonitor=$(pgrep -f /system/bin/wooper_monitor.sh)
          if [ ! -z $checkMonitor ] ;then
            kill -9 $checkMonitor
            sleep 2
            /system/bin/wooper_monitor.sh >/dev/null 2>&1 &
            logger "wooper monitor restarted after PoGo update"
          fi
        fi
      fi
	  if [ "$playintegrityfix_install" = "install" ] ;then
        logger "start updating playintegrityfix"
        # install playintegrityfix
        magisk --install-module /sdcard/Download/playintegrityfix.zip
		/system/bin/rm -f /sdcard/Download/playintegrityfix.zip
        reboot=1
      fi
      if [ "$exeggcute_install" != "install" ] && [ "$pogo_install" != "install" ] && [ "$playintegrityfix_install" != "install" ] ; then
        echo "`date +%Y-%m-%d_%T` Updates checked, nothing to install" >> $logfile
      fi
    fi
}

downgrade_pogo(){
    pinstalled=$(dumpsys package $pogo_package | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    pversions=$(/system/bin/grep 'pogo' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    if [[ "$pinstalled" != "$pversions" ]] ;then
      if [[ "$apkm" = "true" ]] ;then
         /system/bin/rm -f /sdcard/Download/pogo.apkm
         /system/bin/rm -f -r /sdcard/Download/pogoapkm
         until $download /sdcard/Download/pogo.apkm $wooper_download/com.nianticlabs.pokemongo_$arch\_$pversions.apkm || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apkm $wooper_download/com.nianticlabs.pokemongo_$arch_$pversions.apkm" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
         sleep 2
        done
        mkdir /sdcard/Download/pogoapkm
        logger "Extract pogo.apkm $versions"
        unzip /sdcard/Download/pogo.apkm -d /sdcard/Download/pogoapkm
        /system/bin/rm -f /sdcard/Download/pogo.apkm
       else
        /system/bin/rm -f /sdcard/Download/pogo.apk
        until $download /sdcard/Download/pogo.apk $wooper_download/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $wooper_download/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
          sleep 2
        done
      fi
      # install pogo
        am force-stop com.gocheats.launcher
        am force-stop $pogo_package
        sleep 2
        pm uninstall $pogo_package
        sleep 2
        if [ "$apkm" = "true" ] ;then
          /system/bin/pm install -r /sdcard/Download/pogoapkm/base.apk && /system/bin/pm install -p com.nianticlabs.pokemongo -r /sdcard/Download/pogoapkm/split_config.*.apk || { logger "install pogo failed, downgrade perhaps? Exit script" ; exit 1; }
          /system/bin/rm -f -r /sdcard/Download/pogoapkm
        else
          /system/bin/pm install -r /sdcard/Download/pogo.apk || { echo "`date +%Y-%m-%d_%T` Install pogo failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
          /system/bin/rm -f /sdcard/Download/pogo.apk
        fi
      logger "PoGo installed, now $pversions"
      /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
    else
      echo "`date +%Y-%m-%d_%T` pogo version correct, proceed" >> $logfile
    fi
}

########## Execution

#wait on internet
until ping -c1 8.8.8.8 >/dev/null 2>/dev/null || ping -c1 1.1.1.1 >/dev/null 2>/dev/null; do
    sleep 10
done
echo "`date +%Y-%m-%d_%T` Internet connection available" >> $logfile
delay_after_reboot

download_versionfile

#Create new appdir if it does not exist.
appdir

migrate_wooper
#download latest wooper.sh
if [[ $(basename $0) != "wooper_new.sh" ]] ;then
    mount_system_rw
    oldsh=$(head -2 $appdir/wooper.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    until /system/bin/curl -s -k -L --fail --show-error -o $appdir/wooper_new.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper.sh || { echo "`date +%Y-%m-%d_%T` Download wooper.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x $appdir/wooper_new.sh
    newsh=$(head -2 $appdir/wooper_new.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    if [[ "$oldsh" != "$newsh" ]] ;then
        logger "wooper.sh updated $oldsh=>$newsh | Github branch $branch, restarting script"
        cp $appdir/wooper_new.sh $appdir/wooper.sh
        mount_system_ro
        $appdir/wooper_new.sh $@
        exit 1
    fi
fi

#update 55wooper if needed
if [[ $(basename $0) = "wooper_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55wooper | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ "$Ver55wooper" != "$old55" ] ;then
        mount_system_rw
        until /system/bin/curl -s -k -L --fail --show-error -o /system/etc/init.d/55wooper https://raw.githubusercontent.com/andi2022/wooper/$branch/55wooper || { echo "`date +%Y-%m-%d_%T` Download 55wooper failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55wooper
        mount_system_ro
        new55=$(head -2 /system/etc/init.d/55wooper | /system/bin/grep '# version' | awk '{ print $NF }')
        logger "55wooper updated $old55=>$new55 | Github branch $branch"
    fi
fi

#update 55cron if needed
if [[ $(basename $0) = "wooper_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55cron | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ "$Ver55cron" != "$old55" ] ;then
        mount_system_rw

        # install 55cron
        until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/andi2022/wooper/$branch/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55cron
        echo "`date +%Y-%m-%d_%T` 55cron installed" >> $logfile

        # install cron job
        until /system/bin/curl -s -k -L --fail --show-error -o  $appdir/ping_test.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x $appdir/ping_test.sh
        mkdir /data/crontabs || true
        touch /data/crontabs/root
        echo "15 * * * * $appdir/ping_test.sh" > /data/crontabs/root
		crond -b -c /data/crontabs		
        mount_system_ro
        new55=$(head -2 /system/etc/init.d/55cron | /system/bin/grep '# version' | awk '{ print $NF }')
        logger "55cron updated $old55=>$new55 | Github branch $branch"
    fi
fi

migrate_wooper_monitor
#update wooper monitor if needed
if [[ $(basename $0) = "wooper_new.sh" ]] ;then
  [ -f $appdir/wooper_monitor.sh ] && oldMonitor=$(head -2 $appdir/wooper_monitor.sh | grep '# version' | awk '{ print $NF }') || oldMonitor="0"
  if [ $VerMonitor != $oldMonitor ] ;then
    until /system/bin/curl -s -k -L --fail --show-error -o $appdir/wooper_monitor.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper_monitor.sh || { echo "`date +%Y-%m-%d_%T` Download wooper_monitor.sh failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done
    chmod +x $appdir/wooper_monitor.sh
    newMonitor=$(head -2 $appdir/wooper_monitor.sh | grep '# version' | awk '{ print $NF }')
	logger "wooper monitor updated $oldMonitor => $newMonitor | Github branch $branch"
	
    # restart wooper monitor
    if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }') == "true" ]] && [ -f $appdir/wooper_monitor.sh ] ;then
      checkMonitor=$(pgrep -f $appdir/wooper_monitor.sh)
      if [ ! -z $checkMonitor ] ;then
        kill -9 $checkMonitor
        sleep 2
        $appdir/wooper_monitor.sh >/dev/null 2>&1 &
		logger "wooper monitor restarted"
      fi
    fi
  fi
fi

# prevent wooper causing reboot loop. Add bypass ??
if [ $(/system/bin/cat $logfile | /system/bin/grep `date +%Y-%m-%d` | /system/bin/grep rebooted | wc -l) -gt 20 ] ;then
    logger "Device rebooted over 20 times today, wooper.sh signing out, see you tomorrow"
	echo "`date +%Y-%m-%d_%T` Device rebooted over 20 times today, wooper.sh signing out, see you tomorrow"  >> $logfile
    exit 1
fi

# set hostname = origin, wait till next reboot for it to take effect
if [[ $origin != "" ]] ;then
    if [ $(/system/bin/cat /system/build.prop | /system/bin/grep net.hostname | wc -l) = 0 ]; then
        mount_system_rw
        echo "`date +%Y-%m-%d_%T` No hostname set, setting it to $origin" >> $logfile
        echo "net.hostname=$origin" >> /system/build.prop
        mount_system_ro
    else
        hostname=$(/system/bin/grep net.hostname /system/build.prop | awk 'BEGIN { FS = "=" } ; { print $2 }')
        if [[ $hostname != $origin ]] ;then
            mount_system_rw
            echo "`date +%Y-%m-%d_%T` Changing hostname, from $hostname to $origin" >> $logfile
            /system/bin/sed -i -e "s/^net.hostname=.*/net.hostname=$origin/g" /system/build.prop
            mount_system_ro
        fi
    fi
fi

# check exeggcute config file exists
if [[ -d /data/data/com.gocheats.launcher ]] && [[ ! -s $exeggcute ]] ;then
    install_config
    am force-stop com.gocheats.launcher
    /system/bin/monkey -p com.gocheats.launcher 1 > /dev/null 2>&1
fi

# enable wooper monitor
if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }' | awk '{ gsub(/ /,""); print }') == "true" ]] && [ -f $appdir/wooper_monitor.sh ] ;then
  checkMonitor=$(pgrep -f $appdir/wooper_monitor.sh)
  if [ -z $checkMonitor ] ;then
    $appdir/wooper_monitor.sh >/dev/null 2>&1 &
    echo "`date +%Y-%m-%d_%T` wooper.sh: wooper monitor enabled" >> $logfile
  fi
fi

# check apk install settings
check_apkinstall_settings

# install or update adb_keys if config is enabled
  if [ "$adbfingerprint" = "true" ] ;then
  download_adb_keys
  copy_adb_keys_if_newer
  fi

for i in "$@" ;do
    case "$i" in
        -iw) install_wooper ;;
        -ic) install_config ;;
        -ua) update_all ;;
        -dp) downgrade_pogo;;
    esac
done

#Remove Scripts in old install dir (/system/bin) after migration to new appdir
cleanup_old_installdir

(( $reboot )) && reboot_device
exit