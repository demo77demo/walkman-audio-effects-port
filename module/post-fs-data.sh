#!/system/bin/sh
# post-fs-data.sh for ICX1295 Audio HAL Magisk Module
# Runs after /data is mounted but before /system is mounted

mount -o rw,remount /data
MODDIR=${0%/*}
MODPATH=$MODDIR

LOG="$MODDIR/debug-pfsd.log"
exec 2>$LOG

# function
set_perm() {
  chown $2:$3 $1 || return 1
  chmod $4 $1 || return 1
  local CON=$5
  [ -z $CON ] && CON=u:object_r:system_file:s0
  chcon $CON $1 || return 1
}
set_perm_recursive() {
  find $1 -type d 2>/dev/null | while read dir; do
    set_perm $dir $2 $3 $4 $6
  done
  find $1 -type f -o -type l 2>/dev/null | while read file; do
    set_perm $file $2 $3 $5 $6
  done
}

# permission
set_perm_recursive $MODPATH 0 0 0755 0644

# var
ABI=`getprop ro.product.cpu.abi`
if [ ! -d $MODPATH/vendor ]\
|| [ -L $MODPATH/vendor ]; then
  MODSYSTEM=/system
fi
MOD=/data/adb/modules/nomount
NM=$MOD/bin/nm
NOMOUNT=false
[ ! -f $MOD/disable ] && [ -x $NM ] && $NM v >/dev/null 2>&1 && NOMOUNT=true

# function
permissive() {
if [ "`toybox cat $FILE`" = 1 ]; then
  chmod 640 $FILE
  chmod 440 $FILE2
  echo 0 > $FILE
fi
}
magisk_permissive() {
if [ "`toybox cat $FILE`" = 1 ]; then
  if [ -x "`command -v magiskpolicy`" ]; then
    magiskpolicy --live "permissive *"
  else
    $MODPATH/$ABI/libmagiskpolicy.so --live "permissive *"
  fi
fi
}
sepolicy_sh() {
if [ -f $FILE ]; then
  if [ -x "`command -v magiskpolicy`" ]; then
    magiskpolicy --live --apply $FILE 2>/dev/null
  else
    $MODPATH/$ABI/libmagiskpolicy.so --live --apply $FILE 2>/dev/null
  fi
fi
}

# selinux
FILE=/sys/fs/selinux/enforce
FILE2=/sys/fs/selinux/policy
#1permissive
chmod 0755 $MODPATH/*/libmagiskpolicy.so
#2magisk_permissive
# sepolicy.rule / sepolicy.pfsd are OPTIONAL — only load if shipped.
# Missing files fall back to permissive() global toggle above.
FILE=$MODPATH/sepolicy.rule
[ -f "$FILE" ] && sepolicy_sh || echo "[pfsd] no sepolicy.rule — skipping (permissive fallback)" >> "$LOG"
FILE=$MODPATH/sepolicy.pfsd
[ -f "$FILE" ] && sepolicy_sh || echo "[pfsd] no sepolicy.pfsd — skipping (permissive fallback)" >> "$LOG"

# Device detection
MANUFACTURER=$(getprop ro.product.manufacturer | tr -d '[:space:]')
#IS_SONY=$( [ "$MANUFACTURER" = "OnePlus" ] && echo "true" || echo "false" )

# Create IZM data directory
mkdir -p /data/vendor/izm

# permission
chmod 0751 $MODPATH/system/bin
FILES=`find $MODPATH/system/bin -type f`
for FILE in $FILES; do
  chmod 0755 $FILE
done
chown -R 0.2000 $MODPATH/system/bin
DIRS=`find $MODPATH/vendor\
           $MODPATH/system/vendor -type d`
for DIR in $DIRS; do
  chown 0.2000 $DIR
done
chcon -R u:object_r:system_lib_file:s0 $MODPATH/system/lib*
chcon -R u:object_r:vendor_configs_file:s0 $MODPATH/system/odm/etc
chmod 0751 $MODPATH$MODSYSTEM/vendor/bin
chmod 0751 $MODPATH$MODSYSTEM/vendor/bin/hw
chmod 0755 $MODPATH$MODSYSTEM/vendor/odm/bin
chmod 0755 $MODPATH$MODSYSTEM/vendor/odm/bin/hw
FILES=`find $MODPATH$MODSYSTEM/vendor/bin\
            $MODPATH$MODSYSTEM/vendor/odm/bin -type f`
for FILE in $FILES; do
  chmod 0755 $FILE
  chown 0.2000 $FILE
done
chcon -R u:object_r:vendor_file:s0 $MODPATH$MODSYSTEM/vendor
chcon -R u:object_r:vendor_configs_file:s0 $MODPATH$MODSYSTEM/vendor/etc
chcon -R u:object_r:vendor_configs_file:s0 $MODPATH$MODSYSTEM/vendor/odm/etc
chcon u:object_r:vendor_hal_file:s0 $MODPATH$MODSYSTEM/vendor/lib*/hw
#chcon u:object_r:hal_dms_default_exec:s0 $MODPATH$MODSYSTEM/vendor/bin/hw/vendor.dolby*.hardware.dms*@*-service
#chcon u:object_r:hal_dms_default_exec:s0 $MODPATH$MODSYSTEM/vendor/odm/bin/hw/vendor.dolby*.hardware.dms*@*-service
#NAMES="libhwbinder libhidl*.so libut*.so"
#for NAME in $NAMES; do
#  chcon u:object_r:same_process_hal_file:s0 $MODPATH$MODSYSTEM/vendor/lib*/$NAME
#done

# Recreate symlinks lost during zipping
[ -f "$MODDIR/recreate_symlinks.sh" ] && sh "$MODDIR/recreate_symlinks.sh" >> "$LOG" 2>&1

# Set NVP driver init flag
resetprop -n vendor.load_nvp_driver.init 1

# mount
if [ -d /odm ] && [ "`realpath /odm/etc`" == /odm/etc ]\
&& ! grep /odm /data/adb/magisk/magisk\
&& ! grep /odm /data/adb/magisk/magisk64\
&& ! grep /odm /data/adb/magisk/magisk32; then
  mount_odm
fi
if [ -d /my_product ]\
&& ! grep /my_product /data/adb/magisk/magisk\
&& ! grep /my_product /data/adb/magisk/magisk64\
&& ! grep /my_product /data/adb/magisk/magisk32; then
  mount_my_product
fi

# function
mount_bind_file() {
for FILE in $FILES; do
  if $NOMOUNT; then
    $NM del $FILE 2>/dev/null || true
    $NM add $FILE $MODFILE
  else
    umount $FILE
    mount -o bind $MODFILE $FILE
  fi
done
}
mount_bind_to_apex() {
for NAME in $NAMES; do
  MODFILE=$MODPATH/system/lib64/$NAME
  if [ -f $MODFILE ]; then
    FILES=`find /apex /system/apex -path *lib64/* -type f -name $NAME`
    mount_bind_file
  fi
  MODFILE=$MODPATH/system/lib/$NAME
  if [ -f $MODFILE ]; then
    FILES=`find /apex /system/apex -path *lib/* -type f -name $NAME`
    mount_bind_file
  fi
done
}

# mount
#NAMES="libhidlbase.so libutils.so"
#mount_bind_to_apex

# cleaning













