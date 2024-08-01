# Wooper

This tool is meant to let you easily maintain new ATVs (both 32bits and 64bits) to Unown stack and Exeggcute.

It will automatically take care of keeping your devices up to date when a new version of Exeggcute and/or PoGo is required in the future.
The script will automatically check those versions on every reboot of an ATV.  If the versions have changed, it will download the corresponding APKs from your above specified folder and will install them automatically.

Codebase
Wooper's codebase is [aconf](https://github.com/TechG3n/aconf) which is initialy developed by [dkmur](https://github.com/dkmur) and now maintained through [TechG3n](https://github.com/TechG3n).
Some inspiration through [Kneckter](https://github.com/Kneckter) and his [version](https://github.com/Kneckter/aconf-rdm).
The disconnected check function in the wooper_monitor script is from [jinntar](https://github.com/jinnatar) and his [mitm_nanny](https://github.com/jinnatar/mitm_nanny) script.

# Features
- Updating Exeggcute and PoGo
- Monitoring script
- Status messages as Discord Webhook
- Change worker count global for all devices
# Changelog
**wooper script**
```
1.3.12
added branch logging when some component is updated
1.3.11
added basic support to change github branch for develpment and testing
1.3.10
added the key events for handling pink screen also in pogo downgrade logic
1.3.9
fix 1 keyevent
1.3.8
dirty fix for pink screen
1.3.6
new wooper_monitor.sh version 1.1.5
1.3.5
new wooper_monitor.sh version 1.1.4
1.3.4
forgot increase wooper_monitor.sh version number
1.3.3
new wooper_monitor.sh version 1.1.3
1.3.2
Fix wrong variable in logger output for worker count update
1.3.1
No reboot when pogo and exeggcute updates installing, cleanup orphaned logger message, bump version for wooper_monitor.sh update
1.3.0
Add PlayIntegrityFix update logic (See version.example)
1.2.2
fix exeggcute update, remove orphaned stuff
1.2.1
minor fixes
1.2.0
wooper public release
1.1.0 - 1.1.9
Internal release, implementation wooper_monitor.sh
1.0.1 - 1.0.11
Internal release, testing and minor fixes
1.0.0
Internal release, reworking gcconf to wooper with support for Exeggcute
```

**wooper monitor script**
```
1.1.5
clear logcat after issue found to prevent false positive after script rerun
1.1.4
increase wait time after fix for death exeggcute
1.1.3
increase wait time after fix command 
1.1.2
Add check if exeggcute is disconnected
code is from jinntar and his mitm_nanny script
1.1.1
No longer restart exeggcute when pogo client is the problem.
1.1.0
public release
1.0.1 - 1.0.9
Internal release, testing and minor fixes
1.0.0
Internal release
```
# NGINX Setup

Setup a internal server block with autoindex to be able to download the files for update. By using the internal IP address of the server, it will only be accessible to devices on the same network.
```
server {
    listen 8099;
    server_name 192.168.1.2;

    location / {
        root /var/www/html/gcconf;
        autoindex on;
    }
}
```
***OPTIONAL BUT HIGHLY RECOMMANDED :***
The script allows you to add an `authUser` and `authPass`. Those user and passwords will be used if basic auth has been enabled on your directory. 
Please remember this directory contains important information such as your Exeggcute API key or Unown stack auth.
Refer to this documentation on how to enable basic auth for nginx : https://ubiq.co/tech-blog/how-to-password-protect-directory-in-nginx/


The directory should contain the following files :

- The APK of the latest version of Exeggcute
- The APK of the 32bits version of PoGo matching your version of Exeggcute
- The APK of the 64bits version of PoGo matching your version of Exeggcute
- The Exeggcute config file (to be described hereunder)
- A version file (to be described hereunder)


Hers is a typical example of directory content :

```
com.exeggcute.launcher_v3.0.111.apk
pokemongo_arm64-v8a_0.291.2.apk
pokemongo_armeabi-v7a_0.291.2.apk
PlayIntegrityFix_v14.5.zip
config.json
versions
```
Please note the naming convention for the different files, this is important and shouldn't be changed.

Here is the content of the `config.json` file :

```
{
    "api_key": "<your_exeggcute_api_key>",
    "device_name": "dummy",
    "rotom_url": "ws://<rotom_url>",
    "rotom_secret": "<rotom_secret>",
    "workers_count": 6
}
```
Please note that `"device_name":"dummy"` should not be changed. The script will automatically replace this dummy value with the one defined below.

Here is the content of the `versions` file:
```
pogo=0.291.2
exeggcute=3.0.111
playintegrityfixupdate=true
playintegrityfixversion=14.5
discord_webhook="Your_webhock_url"

# Settings for worker count
globalworkers=true
workerscount=6

# Settings for Wooper monitor script
useMonitor=true
monitor_interval=300
update_check_interval=3600
debug=false

# Settings for Monitor Webhooks
recreate_exeggcute_config=true
exeggcute_died=true
exeggcute_disconnected=true
pogo_died=true
pogo_not_focused=true

```
The script will automatically check those versions. If the versions have changed, it will download the corresponding APKs from your above specified folder and will install them automatically.
# Tested ATV Devices/ROM's
- X96 Mini (S905w) / a95xf1 (S905w) PoGoRom 1.5
- TX9S (S912) PoGoRom 1.5.1

That Wooper will do the job you need a working init.d implementation on the used Android ROM.
I don't recommend to use the cs5 image for the TX9S ATV Devices.
The cs5 image don't is reliable with the most init.d enabler. In my other repository i have a dirty working sollution for this.
https://github.com/andi2022/magisk_initd_service
# Installation
 - This setup assumes the device has been imaged and rooted already.
 - Connecting to the device using ADB `adb connect xxx.xxx.xxx.xxx` where the X's are replaced with the device's IP address.
 - Using the following commands to create the wooper_download and wooper.sh files
   - Change the `url`, `authUser`, and `authPass` to the values used for NGINX
   - Change `DeviceName` to the name you want on this device
```
su -c 'file='/data/local/wooper_download' && \
mount -o remount,rw / && \
touch $file && \
echo url=https://mydownloadfolder.com > $file && \
echo authUser='username' >> $file && \
echo authPass='password' >> $file && \
echo device123 > /data/local/initDName && \
/system/bin/curl -L -o /system/bin/wooper.sh -k -s https://raw.githubusercontent.com/andi2022/wooper/main/wooper.sh && \
chmod +x /system/bin/wooper.sh && \
/system/bin/wooper.sh -iw'
```
 - If the script finishes successfuly and the device reboots, you can `adb disconnect` from it.

Logs are created in the folder: /data/local/tmp/
wooper.log
wooper_monitor.log
# Remove Wooper
If you will remove Wooper you need to delete the following files. For some files you need to mount the volume with read / write.
```
/data/crontabs/root
/data/local/wooper_download
/data/local/wooper_versions
/data/local/tmp/config.json
/data/local/tmp/wooper.log
/data/local/tmp/wooper_monitor.log
/sdcard/Download/exeggcute.apk
/sdcard/Download/pogo.apk
/system/bin/wooper.sh
/system/bin/wooper_new.sh
/system/bin/wooper_monitor.sh
/system/bin/ping_test.sh
/system/etc/init.d/55cron
/system/etc/init.d/55wooper
```
# Funfact
I have called the script Wooper because the Pokémon have an inverted WiFi symbol on his belly. :-)