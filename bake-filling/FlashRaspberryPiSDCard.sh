#!/bin/sh
# Creates a Raspberry Pi SD card from the software built by the Buildroot tool
#
# Ensure that this script is in the Buildroot home directory prior to running
#
PI_SDCARD="${1}"
BOOT_SIZE="+60M"
#
# A function that prints out the status of what this script is doing
# in a nice format
#
printMessage() {
	echo "-"
	echo "-----"
	echo "- ${*}"
	echo "-----"
	echo "-"
}
# 
# Ensure that the path is set up correctly
#
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
OUTPUT_PREFIX=""
#
# check that we have a parameter passed in, if not then don't bother going any further
#
if [ -z "${PI_SDCARD}" ]; then
	printMessage "Enter the SD Card Device"
	exit 0
fi
#
# as this involves mounting and un-mounting we need to be 'root'
# using sudo will do the trick but we check now to make sure that this is the case
#
if [ $(id -u) -ne 0 ] 
then
	echo "${0} requires root privileges in order to work."
	exit 0
fi
#
# check if parameter passed is a block device, i.e. a disk in our case
#
if [ ! -b "${PI_SDCARD}" ]; then
	echo "${PI_SDCARD} is not a block device!"
	exit 1
fi
#
# dd binary check
# this binary is used to destroy the first part of the SD Card ready for the new file table
# to be created by fdisk.
#
DD="which dd"
if [ -z "${DD}" ]; then
	echo "Missing dd\n"
	echo "FlashRaspberryPiSdCard.sh FAILED."
	exit 3
fi
#
# fdisk binary check
# fdisk is used to create the new partitions on the SD Card in preparation
# for formatting them and copying the relevant files for the Raspberry Pi.
#
FDISK=`which fdisk`
if [ -z "${FDISK}" ]; then
	echo "Missing fdisk\n"
	echo "FlashRaspberryPiSdCard.sh FAILED."
	exit 3
fi
#
# mkfs.vfat binary check
# This binary is used to format the fist partition as a FAT partition. The Raspberry Pi 
# expects the first partition to be a FAT partition and not a typical Linux formatted partition 
#
MKFS_VFAT=`which mkfs.vfat`
if [ -z "${MKFS_VFAT}" ]; then
	echo "Missing mkfs.vfat\n"
	echo "FlashRaspberryPiSdCard.sh FAILED."
	exit 3
fi
#
# mkfs.ext4 binary check
# This binary is used to format the main partition on the SD Card.
#
MKFS_EXT4=`which mkfs.ext4`
if [ -z "${MKFS_EXT4}" ]; then
	echo "Missing mkfs.ext4\n"
	echo "FlashRaspberryPiSdCard.sh FAILED."
	exit 3
fi
#
# tar binary check
# tar is used to unpack the root file system created by the Buildroot tool
# onto the SD card
#
TAR=`which tar`
if [ -z "${TAR}" ]; then
	echo "Missing tar\n"
	echo "FlashRaspberryPiSdCard.sh FAILED."
	exit 3
fi
#
# check that the image and root tar ball have been created and locate them.
# These files will only be there upon the BuildRoot tool successfully creating
# the complete image for the Raspberry Pi
#
if [ ! -f "images/zImage" ] || [ ! -f "images/rootfs.tar" ]; then
	if [ -f "output/images/zImage" ] && [ -f "output/images/rootfs.tar" ]; then
		OUTPUT_PREFIX="output/"
	else
		echo "Didn't find boot and/or rootfs.tar! ABORT."
		exit 1
	fi
fi
#
# Print out a conformation prior to running anything that will make changes
# to the SD card.
#
echo "You are about to delete all contents of the SD Card"
echo "for the following device node: ${PI_SDCARD}"
echo
echo "If you are sure you want to continue [y/N]?"
read CONTINUE
if [ "$CONTINUE" != "Y" ] && [ "$CONTINUE" != 'y' ] 
then
	echo "Aborted, no damage done!"
	exit 1
fi
#
# check the drive is mounted, sometimes ubuntu will auto-mount the SD
# card if it has been used before. If we find that the card is mounted then we need
# to unmount it otherwise we will not be able to access it.
#
MOUNTS=`grep ${PI_SDCARD} /proc/mounts | cut -d' ' -f 1`
for d in $MOUNTS
do
	printMessage "Unmounting ${d}"
	umount -f ${d}
done
#
# clear the first 10Meg of the SD card. We do not need to clear the entire card since
# we will br creating new partitions.
#
printMessage "Clearing first part of SD card..."
dd if=/dev/zero of=${PI_SDCARD} bs=1M count=10 || exit 1
sync
#
# Create the necessary partitions.
#
# we are creating two partitions, the first is a FAT format partition that the Raspberry Pi
# looks for when it first powers up. 
#
# The second partition is for the operating system
# that is loaded once the Raspberry pi has performed it's initial startup.
#
printMessage "Partitioning SD card..."
${FDISK} ${PI_SDCARD} <<END
o
n
p
1

${BOOT_SIZE}
t
c
n
p
2


a
1
w
END
sync
sleep 1
#
# format the two newly created partitions. We first format the 'boot' partition
# as FAT32 as this is what the raspberry Pi looks for when it first powers on
#
printMessage "Formatting partitions..."
# The boot partition
${MKFS_VFAT} -F 32 -n boot -I "${PI_SDCARD}1" || exit 1
#
# format the root file system. This is a native linux file system. We can use 
# a native file system here since the Raspberry Pi has already booted and can understand
# this partition layout.
#
${MKFS_EXT4} -L rootfs "${PI_SDCARD}2" || exit 1
sync
#
# Create a temporary mount point so we have somewhere to mount the two partitions we 
# have created.
#
mkdir .mnt
#
# mount the partitions and copy the new software across
#
printMessage "Populating boot partition..."
# The boot partition
mount "${PI_SDCARD}1" .mnt || exit 2
cp ${OUTPUT_PREFIX}images/rpi-firmware/* .mnt
cp ${OUTPUT_PREFIX}images/zImage .mnt
sync
umount .mnt
sync
# The root file system
printMessage "Populating rootfs partition..."
mount "${PI_SDCARD}2" .mnt || exit 2
${TAR} -xpsf ${OUTPUT_PREFIX}images/rootfs.tar -C .mnt
sync
umount .mnt
sync
#
# Remove the directory we used for the mount point
#
printMessage "Cleaning up"
rmdir .mnt
#
# If we have gotten this far then we have created the card successfully
#
printMessage "You have Baked your own Raspberry Pi Filling!"
exit 0
