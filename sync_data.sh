#!/bin/bash
set -euo pipefail  # Enable strict mode for safety

: '
Description: Backup and sync hard-disks
Author: jadia.dev
Date: 2021-08-21
Version: v0.0.2
'

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

LOG_DIR="$(pwd)/logs"
LOG_FILE="rsync_files_$(date +"%Y-%m-%d_%H-%M-%S").txt"

EXCLUDES=(
    "\$RECYCLE.BIN"
    "System Volume Information"
    ".Trash-1000"
)
EXCLUDE_ARGS=()
for exclude in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=("--exclude=$exclude")
done

##### Colors #####
blueHigh="\e[44m"
cyan="\e[96m"
clearColor="\e[0m"
redHigh="\e[41m"
green="\e[32m"
greenHigh="\e[42m"

function redFlags() {
    if [ $? -eq 0 ]; then
        echo -e "$clearColor $greenHigh Success: $1. $clearColor"
    else
        echo -e "$clearColor $redHigh Failed: $1. $clearColor"
        exit 1
    fi
}

#### Functions ####
function rsync_hdd () {
    local source="$1"
    local destination="$2"

    echo -e "$clearColor $redHigh Source: $source $clearColor"
    echo -e "$clearColor $redHigh Destination: $destination $clearColor"

    echo "Re-mounting hard disks..."
    sudo mount -a

    mkdir -p "$LOG_DIR"

    echo -e "$clearColor $blueHigh Press Enter to start Dry Run $clearColor"
    read
    echo -e "$clearColor $blueHigh Dry run: Below files will be changed. $clearColor"
    rsync -iaAXvh --delete --dry-run "${EXCLUDE_ARGS[@]}" "$source" "$destination" > "$LOG_DIR/$LOG_FILE"
    redFlags "Rsync Dry Run"
    # What files will be updated?
    #Adapted from: https://unix.stackexchange.com/a/293941
    files_changed=$(grep -E '^(>|c)' "$LOG_DIR/$LOG_FILE" | wc -l)
    echo -e "$clearColor $blueHigh Number of files to be changed: $clearColor $greenHigh $files_changed $clearColor"

    echo -e "$clearColor $blueHigh Press Enter to continue with the sync... $clearColor"
    read
    rsync -iaAXvh --delete "${EXCLUDE_ARGS[@]}" "$source" "$destination"
    redFlags "Rsync: $source -> $destination"
}

function remove_hdd() {
    local hdd_uuid=""
    local mount_path=""

    case "$1" in
        1tb) hdd_uuid="$UUID_1TB"; mount_path="$hdd_1tb";;
        2tb) hdd_uuid="$UUID_2TB"; mount_path="$hdd_2tb";;
        4tb) hdd_uuid="$UUID_4TB"; mount_path="$hdd_4tb";;
        *) echo "Invalid HDD selection"; exit 1;;
    esac

    sudo umount "$mount_path"
    redFlags "Unmount - $mount_path"

    sleep_time=10
    echo "Waiting ${sleep_time}s for partition to unmount properly."
    sleep "$sleep_time"

    echo "Attempting to power off the drive with UUID: $hdd_uuid"
    # Adapted from: https://askubuntu.com/questions/671683/how-to-turn-off-hard-drive-in-ubuntu/1184352#1184352
    sudo udisksctl power-off -b "/dev/disk/by-uuid/$hdd_uuid"
    redFlags "Poweroff - $mount_path"
}

function help_menu() {
    echo """
Usage:   $0 --OPTION <SOURCE> <DESTINATION>
Example: $0 --sync 1tb 2tb
         $0 --remove 1tb

Options:
    --sync : Backup data from smaller drive to bigger
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
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    help_menu
fi

case "$1" in
    --sync)
        case "$2" in
            1tb) [[ "$3" == "2tb" ]] && rsync_hdd "$hdd_1tb" "$hdd_2tb_1tb" || help_menu;;
            2tb) [[ "$3" == "4tb" ]] && rsync_hdd "$hdd_2tb" "$hdd_4tb_2tb" || help_menu;;
            *) help_menu;;
        esac
        ;;

    --remove)
        case "$2" in
            1tb|2tb|4tb) remove_hdd "$2";;
            *) help_menu;;
        esac
        ;;

    *)
        help_menu
        ;;
esac
