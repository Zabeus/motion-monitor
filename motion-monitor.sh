#!/bin/bash
# motion-monitor.sh
# Script to respond to events from "motion". (camera motion detector software for linux)
# Run this from motion when an event is recorded:
#	/path/to/motion-monitor.sh alert recorded_file
# Requirements:
#	Cameras are set up in Motion and working
#	SSMTP is configured to send mail correctly
#	Port forwarding on router is set up for each camera.
#	Static hostname or no-ip or other dynamic dns system is set up.
#	CRON is used to schedule alerts. Use /path/to/motion-monitor.sh on/off to enable or disable detection and alerts.

URL_SHORTENER="/opt/goo.gl.sh"
DROPBOX_UPLOAD="/opt/dropbox_uploader.sh -f /opt/dropbox_uploader.conf upload"
DROPBOX_SHARE="/opt/dropbox_uploader.sh -f /opt/dropbox_uploader.conf share %REMOTEFILE%"
CAMERAS=( "" "" "" "http://" "http://" )
# Will only alert for cameras that have an alert message.
ALERTS=( "" "" "MOVEMENT NEAR DOOR." "" "" )
ON_URL="http://:@:8080/%CAM%/detection/start"
OFF_URL="http://:@:8080/%CAM%/detection/pause"
ALERT_TEMPLATE_FILE="/opt/alert-sms.template"
RECIPIENTS=`cat /opt/motion-recipients | sed -e s/" "/,/`
MAIL_CMD=sendmail
ALERT_DELAY=120		# minimum time between alerts (seconds)
WEBUSER=
WEBPASS=

RET=0

case "$1" in
  cleanup)
	echo "remove/move old files from recording directories"
	;;
  off)
        CAMERA="$2"
        if [ ! -z "$CAMERA" ]; then
                echo "stop detection ($CAMERA)"
        else
                echo "stop detection (ALL)"
                CAMERA="0"
        fi
	curl `echo "http://$WEBUSER:$WEBPASS@:8080/%CAM%/detection/pause" | sed -e s/%CAM%/$CAMERA/`
	;;
  on)
	CAMERA="$2"
	if [ ! -z "$CAMERA" ]; then
		echo "start detection ($CAMERA)"
	else
		echo "start detection (ALL)"
		CAMERA="0"
	fi
	curl `echo "http://$WEBUSER:$WEBPASS@:8080/%CAM%/detection/start" | sed -e s/%CAM%/$CAMERA/`
	;;

  alert)
	#send an alert on the most recent event
	#1. uploads video to dropbox
	#2. creates shortened link to recording on dropbox
	VIDFILE="$2"
	CAMERA="$3"
        if [ -z $CAMERA ]; then CAMERA="0"; fi
	BASENAME=CAM$CAMERA-`basename $VIDFILE`
	VIDLINK=""
	ALERT=${ALERTS[$CAMERA]}
	CAMLINK=${CAMERAS[$CAMERA]}
	echo "Video file: $VIDFILE"
	echo "Camera: $CAMERA"
	if [ -n $VIDFILE ]; then
		#echo $DROPBOX_UPLOAD $VIDFILE $BASENAME
		$DROPBOX_UPLOAD $VIDFILE $BASENAME
		#echo "Uploaded"
		DROPBOX_SHARE="`echo $DROPBOX_SHARE | sed -e s/%REMOTEFILE%/$BASENAME/`"
		echo $DROPBOX_SHARE
		VIDLINK=`$DROPBOX_SHARE`
		VIDLINK=`echo $VIDLINK | cut -c 15-`
		echo "Dropbox link: $VIDLINK"
		VIDLINK=`$URL_SHORTENER $VIDLINK`
		echo "Dropbox short link: $VIDLINK"
	fi
	#3. creates shortened link to live camera
	echo "Camera link: $CAMLINK"
	CAMLINK=`$URL_SHORTENER $CAMLINK`
	echo "Camera short link: $CAMLINK"
	#4. builds alert message from template and links
	#5. sends alert to each recipient
	# don't alert until delay has passed
	NOW=`date +"%s"`
	NOW_TIME=`date +"%H:%M"`
	PASSED=$ALERT_DELAY
	if [ -z "$ALERT" ]; then
		echo "No alert defined for camera $CAMERA. Not alerting."
	else
		if [ -f "/tmp/motion-last-alert" ]; then
			LAST=`cat /tmp/motion-last-alert`
			PASSED=`expr $NOW - $LAST`
		fi
		if [ "$PASSED" -ge "$ALERT_DELAY" ]; then
			echo "Sending alert to $RECIPIENTS"
			ALERT_MESSAGE="`cat $ALERT_TEMPLATE_FILE | sed -e s^%camlink%^"$CAMLINK"^ | sed -e s^%vidlink%^"$VIDLINK"^ | sed -e s^%text%^"$ALERT"^ | sed -e s^%time%^$NOW_TIME^`"
			echo -e "\t$ALERT_MESSAGE"
			echo "$ALERT_MESSAGE" | $MAIL_CMD $RECIPIENTS
			echo $NOW > /tmp/motion-last-alert	# update time
		else
			echo "Too many alerts. Not alerting."
		fi
	fi
	;;
  *)
	echo "Usage: motion-monitor.sh {on [camera]|off [camera]|alert [camera [text]]|cleanup}"
	RET=1
    ;;
esac

exit $RET

