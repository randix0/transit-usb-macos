#! /bin/bash -p

# ================================================================================
# firmware loader
# ================================================================================

/bin/echo  "Removing Firmware Loader /Library/StartupItems/M-Audio Firmware Loader."
/bin/rm -rf /Library/StartupItems/M-Audio\ Firmware\ Loader

# ================================================================================
# kill kernel extensions
# ================================================================================
/bin/echo  "Removing boot driver /System/Library/Extensions/MAudioTransitUSBBoot.kext."
if [ -e "/System/Library/Extensions/MAudioTransitUSBBoot.kext" ]; then
   if ! /bin/rm -rf /System/Library/Extensions/MAudioTransitUSBBoot.kext; then
      /bin/echo  "** FAILED ** Unable to remove /System/Library/Extensions/MAudioTransitUSBBoot.kext."
      MM_FAILED="y"
   fi
fi

/bin/echo  "Removing audio driver /System/Library/Extensions/MAudioTransitUSBJag.kext."
if [ -e "/System/Library/Extensions/MAudioTransitUSBJag.kext" ]; then
   if ! /bin/rm -rf /System/Library/Extensions/MAudioTransitUSBJag.kext; then
      /bin/echo  "** FAILED ** Unable to remove /System/Library/Extensions/MAudioTransitUSBJag.kext."
      MM_FAILED="y"
   fi
fi

# ================================================================================
# kill startup item
# ================================================================================

/bin/echo  "Removing helper application /Library/StartupItems/MAudioTransitUSB."
if [ -e "/Library/StartupItems/MAudioTransitUSB" ]; then
   if ! /bin/rm -rf /Library/StartupItems/MAudioTransitUSB; then
      /bin/echo  "** FAILED ** Unable to remove /Library/StartupItems/MAudioTransitUSB."
      MM_FAILED="y"
   fi
fi

# ================================================================================
# remove preference panel
# ================================================================================

/bin/echo  "Removing preference panel /Library/PreferencePanes/MAudioTransitUSB.prefPane."
if [ -e "/Library/PreferencePanes/MAudioTransitUSB.prefPane" ]; then
   if ! /bin/rm -rf /Library/PreferencePanes/MAudioTransitUSB.prefPane; then
      /bin/echo  "** FAILED ** Unable to remove /Library/PreferencePanes/MAudioTransitUSB.prefPane."
      MM_FAILED="y"
   fi
fi

# ================================================================================
# Remove installer receipts
# ================================================================================

/bin/echo  "Removing installer receipts."
/bin/rm -rf "/Library/Receipts/M-Audio Transit USB.pkg"
/bin/rm -rf /Library/Receipts/FirmwareLoader.pkg

# ================================================================================
# wipe away preference files
# ================================================================================

/bin/echo  "Removing preference files."

# Driver preferences
rm -f	/Library/Preferences/com.maudio.usb.transit.driver.plist

# ================================================================================
# Make sure that Extensions cache gets updated.
# ================================================================================
 
/bin/echo "Updating the extensions cache."
/usr/bin/touch "/System/Library/Extensions"
 
# ================================================================================
# Make sure that PreferencePanes cache gets updated.
# ================================================================================
 
/bin/echo "Updating the preference panes cache."
/usr/bin/touch "/Library/PreferencePanes/MAudioCacheUpdateTrigger"
/bin/rm -r "/Library/PreferencePanes/MAudioCacheUpdateTrigger"

# exit with an error if failure occurred
if [ "y" = "$MM_FAILED" ]; then
   exit 1
fi


