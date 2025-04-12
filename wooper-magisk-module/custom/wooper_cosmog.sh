#!/system/bin/sh
# version 2.1.2

#Version checks
VerService="1.0.3"
VerInit="1.0.1"
VerMonitor="1.3.2"

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
MODDIR="/data/adb/modules/wooper"
mitm=cosmog
mitm_config="/data/local/tmp/cosmog.json"
mitm_package="com.nianticlabs.pokemongo.ares"
mitm_startcmd="am start -n $mitm_package/$mitm_package.MainActivity"
pogo_package="com.nianticlabs.pokemongo"
wooper_versions="/data/local/wooper_versions"
service_config="/data/local/tmp/service.config"
wooper_adb_keys="/data/local/wooper_adb_keys"
adb_keys="/data/misc/adb/adb_keys"
branchoverwrite="/data/local/tmp/branch"
reboot="0"

if [ -f "$service_config" ]; then
  source $service_config
  export device_name
  export wooper_url
  export wooper_user
  export wooper_pass
  export workerscount_override
fi

# stderr to logfile
exec 2>> $logfile

# add wooper_cosmog.sh command to log
echo "" >> $logfile
echo "`date +%Y-%m-%d_%T` ## Executing $(basename $0) $@" >> $logfile


########## Functions

# logger
logger() {
if [[ ! -z $discord_webhook ]] ;then
  echo "`date +%Y-%m-%d_%T` wooper_cosmog.sh: $1" >> $logfile
  if [[ -z $device_name ]] ;then
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_cosmog.sh\", \"content\": \" $1 \"}"  $discord_webhook &>/dev/null
  else
    curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"wooper_cosmog.sh\", \"content\": \" $device_name: $1 \"}"  $discord_webhook &>/dev/null
  fi
else
  echo "`date +%Y-%m-%d_%T` wooper_cosmog.sh: $1" >> $logfile
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
    branch=magisk
  fi

  #Overwrite branch with a local config file for testing on a single device
  if [ -e "$branchoverwrite" ]; then
      branch=$(grep 'branch' $branchoverwrite | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
  fi

  # apkbundle enabled or disabled
  apkm=$(grep '^apkm=' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')

  # adbfingerprint anabled or disabled
  adbfingerprint=$(grep '^adbfingerprint=' $wooper_versions | awk -F "=" '{ print $NF }' | sed -e 's/^"//' -e 's/"$//')
}

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
if [[ ! -f $service_config ]] ;then
    echo "`date +%Y-%m-%d_%T` File $service_config not found, exit script" >> $logfile && exit 1
else
    if [[ $wooper_user == "" ]] ;then
        download="/system/bin/curl -s -k -L --fail --show-error -o"
    else
        download="/system/bin/curl -s -k -L --fail --show-error --user $wooper_user:$wooper_pass -o"
    fi
fi

# download latest version file
until $download $wooper_versions $wooper_url/versions || { echo "`date +%Y-%m-%d_%T` $download $wooper_versions $wooper_url/versions" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download wooper versions file failed, exit script" >> $logfile ; exit 1; } ;do
    sleep 2
done
dos2unix $wooper_versions
echo "`date +%Y-%m-%d_%T` Downloaded latest wooper versions file"  >> $logfile
read_versionfile
}

download_adb_keys() {
  until $download $wooper_adb_keys $wooper_url/adb_keys || { echo "`date +%Y-%m-%d_%T` $download $wooper_adb_keys $wooper_url/adb_keys" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download adb_keys file failed, exit script" >> $logfile ; exit 1; } ;do
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

install_config(){
    until $download $mitm_config $wooper_url/cosmog_config.json || { echo "`date +%Y-%m-%d_%T` $download $mitm_config $wooper_url/cosmog_config.json" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download mitm config file failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done
    /system/bin/sed -i 's,dummy,'$device_id',g' $mitm_config
    logger "mitm config installed"
}

cosmog_lib(){
  vLibVer=$(grep 'cosmog_libVerion' $mitmversions | awk -F "=" '{ print $NF }' | sed 's/\"//g')
  if [[ ! -d /data/data/$mitm_package/files ]] ;then
    mkdir -p /data/data/$mitm_package/files/
  fi
  if [[ ! -f /data/data/$mitm_package/files/libNianticLabsPlugin.so ]] ;then
    logger "Cosmog Lib not found, downloading it"
    rm -f /data/local/tmp/libNianticLabsPlugin.so_*
    until $download /data/local/tmp/libNianticLabsPlugin.so_$vLibVer $wooper_url/libNianticLabsPlugin.so_$vLibVer || { echo "`date +%Y-%m-%d_%T` $download /data/local/tmp/libNianticLabsPlugin.so_$vLibVer $wooper_url/libNianticLabsPlugin.so_$vLibVer" >> $logfile ; logger "download $mitm lib file failed, exit script" ; exit 1; } ;do
      sleep 2
    done
  else
    iLibVer=$(find /data/local/tmp/ -type f -name "libNianticLabsPlugin.so_*" | cut -d '_' -f 2)
    if [[ $vLibVer != $iLibVer ]] ;then
      logger "Cosmog Lib too old, downloading new version"
      rm -f /data/local/tmp/libNianticLabsPlugin.so_*
      until $download /data/local/tmp/libNianticLabsPlugin.so_$vLibVer $wooper_url/libNianticLabsPlugin.so_$vLibVer || { echo "`date +%Y-%m-%d_%T` $download /data/local/tmp/libNianticLabsPlugin.so_$vLibVer $wooper_url/modules/libNianticLabsPlugin.so_$vLibVer" >> $logfile ; logger "download $mitm lib file failed, exit script" ; exit 1; } ;do
        sleep 2
      done
    else
      echo "`date +%Y-%m-%d_%T` wooper_cosmog.sh: cosmog lib already on correct version" >> $logfile
    fi
  fi

  #Move lib and set perms
  cp /data/local/tmp/libNianticLabsPlugin.so_$vLibVer /data/data/$mitm_package/files/libNianticLabsPlugin.so
  chown root:root /data/data/$mitm_package/files/libNianticLabsPlugin.so
  chmod 444 /data/data/$mitm_package/files/libNianticLabsPlugin.so
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
    mitminstalled=$(dumpsys package $mitm_package | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    mitmversions=$(/system/bin/grep 'cosmog' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  globalworkers=$(/system/bin/grep 'globalworkers' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  workerscount=$(/system/bin/grep 'workerscount' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
	  mitmworkerscount=$(grep 'workers' $mitm_config | sed -r 's/^ [^:]*: ([0-9]+),?$/\1/')
    playintegrityfixinstalled=$(cat /data/adb/modules/playintegrityfix/module.prop | /system/bin/grep version | head -n1 | /system/bin/sed 's/ *version=v//')    
	  playintegrityfixupdate=$(/system/bin/grep 'playintegrityfixupdate' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')	
	  playintegrityfixversions=$(/system/bin/grep 'playintegrityfixversion' $wooper_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    if [ -n "$workerscount_override" ]; then
    workerscount=$workerscount_override
    fi

    if [[ "$pinstalled" != "$pversions" ]] ;then
      logger "New pogo version detected, $pinstalled=>$pversions"
        if [[ "$apkm" = "true" ]] ;then
          /system/bin/rm -f /sdcard/Download/pogo.apkm
          /system/bin/rm -f -r /sdcard/Download/pogoapkm
          until $download /sdcard/Download/pogo.apkm $wooper_url/com.nianticlabs.pokemongo_$arch\_$pversions.apkm || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apkm $wooper_url/com.nianticlabs.pokemongo_$arch_$pversions.apkm" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
          done
          mkdir /sdcard/Download/pogoapkm
          logger "Extract pogo.apkm $versions"
          unzip /sdcard/Download/pogo.apkm -d /sdcard/Download/pogoapkm
          /system/bin/rm -f /sdcard/Download/pogo.apkm
        else
          /system/bin/rm -f /sdcard/Download/pogo.apk
          until $download /sdcard/Download/pogo.apk $wooper_url/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $wooper_url/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
          done
        fi
      # set pogo to be installed
      pogo_install="install"
    else
     pogo_install="skip"
     echo "`date +%Y-%m-%d_%T` PoGo already on correct version" >> $logfile
    fi

    if [ "$mitminstalled" != "$mitmversions" ] ;then
      logger "New $mitm version detected, $mitminstalled=>$mitmversions"
      /system/bin/rm -f /sdcard/Download/mitm.apk
      until $download /sdcard/Download/mitm.apk $wooper_url/cosmog-$mitmversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/mitm.apk $wooper_url/cosmog-$mitmversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download $mitm failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set mitm to be installed
      mitm_install="install"
    else
     mitm_install="skip"
     echo "`date +%Y-%m-%d_%T` $mitm already on correct version" >> $logfile
    fi

    if [[ $playintegrityfixupdate == "true" ]] && [ "$playintegrityfixinstalled" != "$playintegrityfixversions" ] ;then
      logger "New PlayIntegrityFix version detected, $playintegrityfixinstalled=>$playintegrityfixversions"
      /system/bin/rm -f /sdcard/Download/playintegrityfix.zip
      until $download /sdcard/Download/playintegrityfix.zip $wooper_url/PlayIntegrityFix_v$playintegrityfixversions.zip || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/playintegrityfix.zip $wooper_url/PlayIntegrityFix_v$playintegrityfixversions.zip" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download PlayIntegrityFix failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
	  # set PlayIntegrityFix to be installed
      playintegrityfix_install="install"
    else
     playintegrityfix_install="skip"
     echo "`date +%Y-%m-%d_%T` PlayIntegrityFix already on correct version or not enabled" >> $logfile
    fi

    if [[ $globalworkers == "true" ]] && [ "$mitmworkerscount" != "$workerscount" ] ;then
    logger "New global workers count detected, $mitmworkerscount=>$workerscount"
	  sed -i "s/\"workers_count\": [0-9]*/\"workers\": $workerscount/" $mitm_config
	  logger "New workers count $workerscount is active, restarting $mitm"
	  am force-stop $mitm_package
	  sleep 2
	  $mitm_startcmd
	else
     echo "`date +%Y-%m-%d_%T` workers count ok or not enabled" >> $logfile
    fi

    if [ ! -f "$mitm_config" ]; then
    install_config
    fi

    if [ ! -z "$mitm_install" ] && [ ! -z "$pogo_install" ] && [ ! -z "$playintegrityfix_install" ] ;then
      echo "`date +%Y-%m-%d_%T` All updates checked and downloaded if needed" >> $logfile
      if [ "$mitm_install" = "install" ] ;then
        logger "Start updating $mitm"
        # install mitm
          am force-stop $mitm_package
          am force-stop $pogo_package
        sleep 2
        /system/bin/pm install -r /sdcard/Download/mitm.apk || { echo "`date +%Y-%m-%d_%T` Install $mitm failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/mitm.apk
        
        # Grant su access + settings
        mitmuid="$(dumpsys package $mitm_package | grep userId | awk -F'=' '{print $2}')"
        magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($mitmuid,2,0,1,0)"
        
        # add cosmog workers to denylist
        i=1
        while [ $i -le 100 ]; do
          magisk --sqlite "REPLACE INTO denylist (package_name,process) VALUES('com.nianticlabs.pokemongo.ares','com.nianticlabs.pokemongo.ares:worker$i');"
          i=$((i + 1))
        done

		    $mitm_startcmd
        sleep 15
        am force-stop $mitm_package

        cosmog_lib

        logger "$mitm updated, launcher started"
      fi
      if [ "$pogo_install" = "install" ] ;then
        logger "Start updating pogo"
        # install pogo
          am force-stop $mitm_package
          am force-stop $pogo_package
          sleep 2
          pm uninstall $pogo_package
          sleep 2
          if [ "$apkm" = "true" ]; then
              # Base APK file
              BASE_APK="/sdcard/Download/pogoapkm/base.apk"
              
              # Calculate total size of all APKs
              TOTAL_SIZE=$(stat -c%s "$BASE_APK")
              for APK in /sdcard/Download/pogoapkm/split_config*.apk; do
                  TOTAL_SIZE=$((TOTAL_SIZE + $(stat -c%s "$APK")))
              done
              
              # Create an installation session
              SESSION_ID=$(pm install-create -S $TOTAL_SIZE | awk -F'[][]' '{print $2}')
              
              # Check if session ID was created successfully
              if [ -z "$SESSION_ID" ]; then
                  echo "Failed to create installation session."
                  exit 1
              fi
              
              # Stage the base APK
              pm install-write -S $(stat -c%s "$BASE_APK") $SESSION_ID 0 "$BASE_APK" || { logger "install pogo failed, downgrade perhaps? Exit script"; exit 1; }
              
              # Stage the split APKs
              INDEX=1
              for APK in /sdcard/Download/pogoapkm/split_config*.apk; do
                  pm install-write -S $(stat -c%s "$APK") $SESSION_ID $INDEX "$APK" || { logger "install pogo failed, downgrade perhaps? Exit script"; exit 1; }
                  INDEX=$((INDEX + 1))
              done
              
              # Commit the installation
              pm install-commit $SESSION_ID || { logger "install pogo failed, downgrade perhaps? Exit script"; exit 1; }
              
              # Clean up
              /system/bin/rm -f -r /sdcard/Download/pogoapkm
          else
              /system/bin/pm install -r /sdcard/Download/pogo.apk || { echo "$(date +%Y-%m-%d_%T) Install pogo failed, downgrade perhaps? Exit script" >> $logfile; exit 1; }
              /system/bin/rm -f /sdcard/Download/pogo.apk
          fi
        $mitm_startcmd
        logger "PoGo $pversions, launcher started"
        # restart wooper monitor
        if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }') == "true" ]] && [ -f $MODDIR/wooper_cosmog_monitor.sh ] ;then
          checkMonitor=$(pgrep -f $MODDIR/wooper_cosmog_monitor.sh)
          if [ ! -z $checkMonitor ] ;then
            kill -9 $checkMonitor
            sleep 2
            $MODDIR/wooper_cosmog_monitor.sh >/dev/null 2>&1 &
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
      if [ "$mitm_install" != "install" ] && [ "$pogo_install" != "install" ] && [ "$playintegrityfix_install" != "install" ] ; then
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
         until $download /sdcard/Download/pogo.apkm $wooper_url/com.nianticlabs.pokemongo_$arch\_$pversions.apkm || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apkm $wooper_url/com.nianticlabs.pokemongo_$arch_$pversions.apkm" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
         sleep 2
        done
        mkdir /sdcard/Download/pogoapkm
        logger "Extract pogo.apkm $versions"
        unzip /sdcard/Download/pogo.apkm -d /sdcard/Download/pogoapkm
        /system/bin/rm -f /sdcard/Download/pogo.apkm
       else
        /system/bin/rm -f /sdcard/Download/pogo.apk
        until $download /sdcard/Download/pogo.apk $wooper_url/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $wooper_url/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
          sleep 2
        done
      fi
      # install pogo
        am force-stop $mitm_package
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
      $mitm_startcmd
    else
      echo "`date +%Y-%m-%d_%T` pogo version correct, proceed" >> $logfile
    fi
}

########## Execution
download_versionfile

#update wooper service script
if [[ $(basename $0) = "wooper_cosmog_new.sh" ]]; then
  [ -f $MODDIR/service.sh ] && oldService=$(head -3 $MODDIR/service.sh | grep -i '# version' | awk '{ print $NF }') || oldService="0"
  if [ $VerService != $oldService ]; then
    until /system/bin/curl -s -k -L --fail --show-error -o $MODDIR/service.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper-magisk-module/common/service.sh || { echo "`date +%Y-%m-%d_%T` Download service.sh failed, exit script" >> $logfile ; exit 1; }; do
      sleep 2
    done
    chmod +x $MODDIR/service.sh
    dos2unix $MODDIR/service.sh
    newService=$(head -2 $MODDIR/service.sh | grep '# version' | awk '{ print $NF }')
    logger "wooper service script updated $oldService => $newService | Github branch $branch"
  fi
fi

#update wooper init
if [[ $(basename $0) = "wooper_cosmog_new.sh" ]]; then
  [ -f $MODDIR/init.sh ] && oldInit=$(head -3 $MODDIR/init.sh | grep -i '# version' | awk '{ print $NF }') || oldInit="0"
  if [ $VerInit != $oldInit ]; then
    until /system/bin/curl -s -k -L --fail --show-error -o $MODDIR/init.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper-magisk-module/custom/init.sh || { echo "`date +%Y-%m-%d_%T` Download init.sh failed, exit script" >> $logfile ; exit 1; }; do
      sleep 2
    done
    chmod +x $MODDIR/init.sh
    dos2unix $MODDIR/init.sh
    newInit=$(head -2 $MODDIR/init.sh | grep '# version' | awk '{ print $NF }')
    logger "wooper init updated $oldInit => $newInit | Github branch $branch"
  fi
fi

#download latest wooper_cosmog.sh
if [[ $(basename $0) != "wooper_cosmog_new.sh" ]] ;then
    oldsh=$(head -2 $MODDIR/wooper_cosmog.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    until /system/bin/curl -s -k -L --fail --show-error -o $MODDIR/wooper_cosmog_new.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper-magisk-module/custom/wooper_cosmog.sh || { echo "`date +%Y-%m-%d_%T` Download wooper_cosmog.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x $MODDIR/wooper_cosmog_new.sh
    dos2unix $MODDIR/wooper_cosmog_new.sh
    newsh=$(head -2 $MODDIR/wooper_cosmog_new.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    if [[ "$oldsh" != "$newsh" ]] ;then
        logger "wooper_cosmog.sh updated $oldsh=>$newsh | Github branch $branch, restarting script"
        cp $MODDIR/wooper_cosmog_new.sh $MODDIR/wooper_cosmog.sh
        "$MODDIR/wooper_cosmog_new.sh" $@
        exit 1
    fi
fi


#update wooper monitor if needed
if [[ $(basename $0) = "wooper_cosmog_new.sh" ]]; then
  [ -f $MODDIR/wooper_cosmog_monitor.sh ] && oldMonitor=$(head -2 $MODDIR/wooper_cosmog_monitor.sh | grep '# version' | awk '{ print $NF }') || oldMonitor="0"
  if [ $VerMonitor != $oldMonitor ]; then
    until /system/bin/curl -s -k -L --fail --show-error -o $MODDIR/wooper_cosmog_monitor.sh https://raw.githubusercontent.com/andi2022/wooper/$branch/wooper-magisk-module/custom/wooper_cosmog_monitor.sh || { echo "`date +%Y-%m-%d_%T` Download wooper_cosmog_monitor.sh failed, exit script" >> $logfile ; exit 1; }; do
      sleep 2
    done
    chmod +x $MODDIR/wooper_cosmog_monitor.sh
    dos2unix $MODDIR/wooper_cosmog_monitor.sh
    newMonitor=$(head -2 $MODDIR/wooper_cosmog_monitor.sh | grep '# version' | awk '{ print $NF }')
    logger "wooper monitor updated $oldMonitor => $newMonitor | Github branch $branch"
    
    # restart wooper monitor
    if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }') == "true" ]] && [ -f $MODDIR/wooper_cosmog_monitor.sh ]; then
      checkMonitor=$(pgrep -f $MODDIR/wooper_cosmog_monitor.sh)
      if [ ! -z $checkMonitor ]; then
        kill -9 $checkMonitor
        sleep 2
        "$MODDIR/wooper_cosmog_monitor.sh" >/dev/null 2>&1 &
        logger "wooper monitor restarted"
      fi
    fi
  fi
fi

# prevent wooper causing reboot loop. Add bypass ??
if [ $(/system/bin/cat $logfile | /system/bin/grep `date +%Y-%m-%d` | /system/bin/grep rebooted | wc -l) -gt 50 ] ;then
    logger "Device rebooted over 50 times today, wooper_cosmog.sh signing out, see you tomorrow"
	echo "`date +%Y-%m-%d_%T` Device rebooted over 50 times today, wooper_cosmog.sh signing out, see you tomorrow"  >> $logfile
    exit 1
fi

# set hostname = origin, wait till next reboot for it to take effect
if [[ $device_name != "" ]] ;then
    if [ $(/system/bin/cat /system/build.prop | /system/bin/grep net.hostname | wc -l) = 0 ]; then
        mount_system_rw
        echo "`date +%Y-%m-%d_%T` No hostname set, setting it to $device_name" >> $logfile
        echo "net.hostname=$device_name" >> /system/build.prop
        mount_system_ro
    else
        hostname=$(/system/bin/grep net.hostname /system/build.prop | awk 'BEGIN { FS = "=" } ; { print $2 }')
        if [[ $hostname != $device_name ]] ;then
            mount_system_rw
            echo "`date +%Y-%m-%d_%T` Changing hostname, from $hostname to $device_name" >> $logfile
            /system/bin/sed -i -e "s/^net.hostname=.*/net.hostname=$device_name/g" /system/build.prop
            mount_system_ro
        fi
    fi
fi

# check mitm config file exists
if [[ ! -s $mitm_config ]] ;then
    download_versionfile
    install_config
    am force-stop $mitm_package
    $mitm_startcmd
fi

# check cosmog lib ver
vLibVer=$(grep 'cosmog_libVerion' $wooper_versions | awk -F "=" '{ print $NF }' | sed 's/\"//g')
iLibVer=$(find /data/local/tmp/ -type f -name "libNianticLabsPlugin.so_*" | cut -d '_' -f 2)
if [[ -d /data/data/$mitm_package ]] ;then
  if [[ $vLibVer != $iLibVer ]] || [[ ! -f /data/data/$mitm_package/files/libNianticLabsPlugin.so ]] ;then
    logger "Cosmog Lib not matched, downloading new version"
    cosmog_lib
  else
    echo "`date +%Y-%m-%d_%T` wooper_cosmog.sh: cosmog lib already on correct version" >> $logfile
  fi
fi

# enable wooper monitor
if [[ $(grep useMonitor $wooper_versions | awk -F "=" '{ print $NF }' | awk '{ gsub(/ /,""); print }') == "true" ]] && [ -f $MODDIR/wooper_cosmog_monitor.sh ] ;then
  checkMonitor=$(pgrep -f $MODDIR/wooper_cosmog_monitor.sh)
  if [ -z $checkMonitor ] ;then
    "$MODDIR/wooper_cosmog_monitor.sh" >/dev/null 2>&1 &
    echo "`date +%Y-%m-%d_%T` wooper_cosmog.sh: wooper monitor enabled" >> $logfile
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
        -ic) install_config ;;
        -ua) update_all ;;
        -dp) downgrade_pogo;;
    esac
done

# Check if reboot is equal to 1
if [ "$reboot" -eq 1 ]; then
    reboot_device
fi

exit