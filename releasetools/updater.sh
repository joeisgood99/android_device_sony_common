#!/sbin/sh
#
# Copyright (C) 2012 The Android Open Source Project
# Copyright (C) 2016 The OmniROM Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

# write logs to /tmp
set_log() {
    mkdir -p /tmp/omni;
    rm -rf /tmp/omni/"${1}";
    exec >> /tmp/omni/"${1}" 2>&1;
}

# ui_print
OUTFD=$(\
    ps | \
    grep -v "grep" | \
    grep -o -E "/tmp/updater .*" | \
    cut -d " " -f 3\
);

if test -e /tmp/update_binary ; then
    OUTFD=$(\
        ps | \
        grep -v "grep" | \
        grep -o -E "update_binary(.*)" | \
        cut -d " " -f 3\
    );
fi

ui_print() {
    if [ "${OUTFD}" != "" ]; then
        echo "ui_print ${1} " 1>&"${OUTFD}";
        echo "ui_print " 1>&"${OUTFD}";
    else
        echo "${1}";
    fi
}

# set log
set_log variant_detect.log

# check mounts
check_mount() {
    local MOUNT_POINT=$(readlink "${1}");
    if ! test -n "${MOUNT_POINT}" ; then
        # readlink does not work on older recoveries for some reason
        # doesn't matter since the path is already correct in that case
        echo "Using non-readlink mount point ${1}";
        MOUNT_POINT="${1}";
    fi
    if ! grep -q "${MOUNT_POINT}" /proc/mounts ; then
        mkdir -p "${MOUNT_POINT}";
        if test "${MOUNT_POINT}" = /lta-label ; then
            if ! mount -r -t "${3}" "${2}" "${MOUNT_POINT}" ; then
                echo "Cannot mount ${1} (${MOUNT_POINT}).";
                exit 1;
            fi
        else
            umount -l "${2}";
            if ! mount -t "${3}" "${2}" "${MOUNT_POINT}" ; then
                echo "Cannot mount ${1} (${MOUNT_POINT}).";
                exit 1;
            fi
        fi
    fi
}

# check partitions
check_mount /system /dev/block/bootdevice/by-name/system ext4;
check_mount /lta-label /dev/block/bootdevice/by-name/LTALabel ext4;

# Detect the exact model from the LTALabel partition
# This looks something like:
# 1284-8432_5-elabel-D5303-row.html
variant=$(\
    ls /lta-label/*.html | \
    sed s/.*-elabel-// | \
    sed s/-row.html// | \
    tr -d '\n\r' | \
    tr '[a-z]' '[A-Z]' \
);

ui_print "Device Variant: ${variant}";

# Set product model property
touch /system/vendor/build.prop;
$(echo "ro.product.model=${variant}" > /system/vendor/build.prop);

dsds=$(\
    cat /tmp/variants |\
    grep ${variant} |\
    grep DSDS |\
    tr -d '\n\r' \
);

if [ "${dsds}" != "" ]; then
    $(echo "ro.telephony.default_network=9,1" >> /system/vendor/build.prop);
    $(echo "persist.multisim.config=dsds" >> /system/vendor/build.prop);
    $(echo "persist.radio.multisim.config=dsds" >> /system/vendor/build.prop);
else
    $(echo "ro.telephony.default_network=9" >> /system/vendor/build.prop);
fi

# Set permissions
chmod 0644 /system/vendor/build.prop;

if [ ! -e /dev/block/bootdevice/by-name/modem ] && [ -d /system/blobs/${variant}/ ]; then
    # Remove default modem symlinks
    rm -rf /system/etc/firmware/mba*
    rm -rf /system/etc/firmware/modem*

    # Symlink the correct modem blobs
    basedir="/system/blobs/${variant}/"
    cd ${basedir}
    find . -type f | while read file; do ln -s ${basedir}${file} /system/etc/firmware/${file} ; done
fi;

exit 0
