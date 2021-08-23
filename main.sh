#!/bin/bash
: '
Description: Backup and sync hard-disks
Author: github.com/jadia
Date: 2021-08-21
Version: v0.0.1
'

    # Backup flow
    #   ┌─────────────┐        ┌──────────────┐       ┌────────────┐
    #   │             │        │              │       │            │
    #   │     1TB     ├──────► │     2TB      ├──────►│    4TB     │
    #   │             │        │              │       │            │
    #   └─────────────┘        └──────────────┘       └────────────┘

    # Backup structure;
    #  ┌─────────────────────────────────────┐
    #  │                                     │  Most important data will be
    #  │                4TB                  │  saved in 1TB and whole 1TB
    #  │                                     │  will be synced to 2TB and 
    #  │    ┌───────────────────────────┐    │  whole 2TB will be synced to
    #  │    │                           │    │  4TB.
    #  │    │           2TB             │    │  This way most important data
    #  │    │     ┌──────────────┐      │    │  will be replicated across
    #  │    │     │              │      │    │  3 drives for redundancy.
    #  │    │     │     1TB      │      │    │
    #  │    │     │              │      │    │
    #  │    │     └──────────────┘      │    │
    #  │    │                           │    │
    #  │    └───────────────────────────┘    │
    #  │                                     │
    #  └─────────────────────────────────────┘


#### Variables ####
# The trailing slashes are IMPORTANT!
hdd_1tb="$HOME/mnt/1tb/"
hdd_2tb="$HOME/mnt/2tb/"
hdd_4tb="$HOME/mnt/4tb/"

# Path where backup of smaller drives are stored
# No need to have trailing slashes here.
hdd_2tb_1tb="$HOME/mnt/2tb/1tb"
hdd_4tb_2tb="$HOME/mnt/4tb/2tb"

UUID_1TB="EE36E83B36E80685"
UUID_2TB="DC60524D60522F10"
UUID_4TB="FC5826D858269206"


##### Colors #####
blueHigh="\e[44m"
cyan="\e[96m"
clearColor="\e[0m"
redHigh="\e[41m"
green="\e[32m"
greenHigh="\e[42m"


function redFlags() {
    if [ $? == 0 ]; then
        echo -e "$clearColor $greenHigh Success: $1. $clearColor"
    else
        echo -e "$clearColor $redHigh Failed: $1. $clearColor"
        exit 1
    fi
}

#### Functions ####

function rsync_hdd () {
    source=$1
    destination=$2
    echo -e "$clearColor $redHigh Source: $source $clearColor"
    echo -e "$clearColor $redHigh Destination: $destination $clearColor"

    echo "Re-mount harddisks"
    sudo mount -a

    LOG_DIR=$(pwd)/logs
    mkdir -p $LOG_DIR
    echo -e "$clearColor $blueHigh Press Enter to start Dry Run $clearColor"
    read
    echo -e "$clearColor $blueHigh Dry run: Below files will be changed. $clearColor"
    rsync -iaAXvh --delete --dry-run --exclude={"\$RECYCLE.BIN","System\ Volume\ Information",".Trash-1000"} $source $destination > $LOG_DIR/rsync_files.txt
    redFlags "Rsync Dry Run"
    # What files will be updated?
    egrep '^(>|c)' $LOG_DIR/rsync_files.txt
    #Adapted from: https://unix.stackexchange.com/a/293941
    files_changed=$(egrep '^(>|c)' $LOG_DIR/rsync_files.txt | wc -l)
    
    echo -e "$clearColor $blueHigh Number files will be changed: $clearColor $greenHigh $files_changed $clearColor"
    echo -e "$clearColor $blueHigh Press Enter to continue with the sync... $clearColor"
    read
    rsync -iaAXvh --delete --exclude={"\$RECYCLE.BIN","System\ Volume\ Information",".Trash-1000"} $source $destination
    redFlags "Rsync: $source -> $destination"
}


function remove_hdd() {
    # remove hdd safely
    if [[ $1 == '1tb' ]]; then
        hdd_uuid=$UUID_1TB
        mount_path=$hdd_1tb
    elif [[ $1 == '2tb' ]]; then
        hdd_uuid=$UUID_2TB
        mount_path=$hdd_2tb
    elif [[ $1 == '4tb' ]]; then
        hdd_uuid=$UUID_4TB
        mount_path=$hdd_4tb
    fi
    sudo umount $mount_path
    redFlags "Unmount - $mount_path"
    sleep_time=10
    echo "Waiting ${sleep_time}s for partition to unmount properly."
    sleep $sleep_time
    echo "Attempting to Power off the drive with UUID: $hdd_uuid"
    # Adapted from: https://askubuntu.com/questions/671683/how-to-turn-off-hard-drive-in-ubuntu/1184352#1184352
    sudo udisksctl power-off -b /dev/disk/by-uuid/$hdd_uuid
    redFlags "Poweroff - $mount_path"
}


function help_menu() {
    echo """
Usage:   $0 --OPTION <SOURCE> <DESTINATION>
Example: $0 --sync 1tb 2tb
         $0 --remove 1tb

Options:
    --sync : Backup data from smaller driver to bigger
        Only below combinations are allowed:
        1tb -> 2tb
        2tb -> 4tb

    --remove : Remove a drive safely
        Unmount the partition and power off the device
        Only below inputs are allowed:
        1tb, 2tb & 4tb
    """
    exit 1
}


#### MAIN ####

if [[ "$#" -lt 2 && "$#" -gt 3 ]]; then
    help_menu
fi

if [[ $1 == '--sync' ]]; then

    if [[ $2 == '1tb' && $3 == '2tb' ]]; then
        echo -e "$clearColor $blueHigh Do you wish to sync 1TB HDD with 2TB HDD? $clearColor"
        rsync_hdd $hdd_1tb $hdd_2tb_1tb

    elif [[ $2 == '2tb' && $3 == '4tb' ]]; then
        echo -e "$clearColor $blueHigh Do you wish to sync 2TB HDD with 4TB HDD? $clearColor"
        rsync_hdd $hdd_2tb $hdd_4tb_2tb

    else
        echo """
        Wrong HDD combination.
        Usage:   $0 --sync <SOURCE> <DESTINATION>
        Example: $0 --sync 1tb 2tb

        Only below combinations are allowed:
        1tb -> 2tb
        2tb -> 4tb
        """
        exit 1
    fi

elif [[ $1 == '--remove' ]]; then
    
    if [[ $2 == '1tb' || $2 == '2tb' || $2 == '4tb' ]]; then
        remove_hdd $2
    fi
else
    help_menu
fi


