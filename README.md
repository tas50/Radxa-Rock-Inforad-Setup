# Radxa-Rock-Inforad-Setup
A simple script for configuring a Radxa Rock as an Inforad


Flashing SD cards
-----------------
* Download the latest Ubuntu (actually Linaro) release at http://dl.radxa.com/rock_pro/images/ubuntu/sd/
* Follow the flashing instructions at http://radxa.com/Rock/SD_images (we've edited these to be correct)
* Boot the Rock using the SD card (make sure to push it in far enough that it clicks in)
* Resize the partition
* Run 'fdisk /dev/mmcblk0' and then use 'p' to see the current partition layout.  Note the start block of the first partition
* Delete the partition with 'd'
* Create a new partition with 'n' and use the same start block (probably 65536)
* Set the partition to be bootable with 'a'
* Write the partition with 'w'
* Reboot the host.
* When you run the inforad setup script it will automatically run resize2fs /dev/mmcblk0p1 to perform the resize
