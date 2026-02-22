#!/bin/bash

##### Colors #####
blueHigh="\e[44m"
cyan="\e[96m"
clearColor="\e[0m"
redHigh="\e[41m"
green="\e[32m"
greenHigh="\e[42m"

##### Success/Failure Function #####
function redFlags() {
    if [ $? == 0 ]; then
        echo -e "$clearColor $greenHigh Success: $1. $clearColor"
    else
        echo -e "$clearColor $redHigh Failed: $1. $clearColor"
        exit 1
    fi
}

##### Variables #####
SRC_DIR="$HOME"  # Source directory (home directory)
DEST_DIR="$HOME/mnt/4tb/laptop_backup"  # Backup destination
EXCLUDE_FILE="backup_exclude.txt"  # File containing exclusions
LOG_DIR="logs"  # Directory to store logs
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")  # Current date and time
LOG_FILE="$LOG_DIR/laptop_backup_$TIMESTAMP.log"  # Log file for rsync operations

##### Function for Backup Process #####
function backup_laptop () {
    source=$SRC_DIR
    destination=$DEST_DIR

    echo -e "$clearColor $redHigh Source: $source $clearColor"
    echo -e "$clearColor $redHigh Destination: $destination $clearColor"

    ##### Check if EXCLUDE_FILE exists #####
    if [ ! -f "$EXCLUDE_FILE" ]; then
        echo -e "$clearColor $redHigh Exclusion file $EXCLUDE_FILE not found. Exiting. $clearColor"
        exit 1
    fi

    # Re-mount disks (if needed)
    echo -e "$clearColor $cyan Re-mounting hard drives... $clearColor"
    sudo mount -a

    # Create log directory if it doesn't exist
    mkdir -p $LOG_DIR

    # Prompt for dry run
    echo -e "$clearColor $blueHigh Press Enter to start Dry Run (this will show the top-level directories and files to be changed) $clearColor"
    read
    echo -e "$clearColor $blueHigh Dry run: Below files will be changed. $clearColor"

    # Perform rsync dry-run and log the files that will be changed (level 1 depth only)
    rsync -iaAXvh --delete --no-perms --dry-run --exclude-from="$EXCLUDE_FILE" --no-links \
        "$source/" "$destination/" > "$LOG_FILE"

    redFlags "Rsync Dry Run"

    # Display only level 1 directories and files that would be changed or updated
    echo -e "$clearColor $greenHigh Top-level files and directories that would be updated or changed: $clearColor"
    egrep '^(>|c)' "$LOG_FILE" | awk -F'/' '!seen[$1]++ {print $1}' | sort -u

    # Count number of top-level files and directories
    files_changed=$(egrep '^(>|c)' "$LOG_FILE" | wc -l)
    echo -e "$clearColor $blueHigh Number of top-level files and directories that will be changed: $clearColor $greenHigh $files_changed $clearColor"

    # Extract and display the total size of the data to be synced
    total_size=$(tail -n 5 "$LOG_FILE" | grep 'total size' | awk '{print $4, $5}')
    echo -e "$clearColor $blueHigh Total size of data to be synced: $clearColor $greenHigh $total_size $clearColor"

    # Confirmation prompt before actual sync
    echo -e "$clearColor $blueHigh Press Enter to continue with the actual sync, or Ctrl+C to abort. $clearColor"
    read

    # Perform the actual rsync operation
    rsync -iaAXvh --delete --no-perms --ignore-errors --exclude-from="$EXCLUDE_FILE" --no-links \
          "$source/" "$destination/" >> "$LOG_FILE" 2>&1

    redFlags "Rsync: $source -> $destination"

    # Logging success
    echo "Backup completed on $(date)" >> "$LOG_FILE"
    echo -e "$clearColor $greenHigh Backup completed successfully. $clearColor"
}

backup_laptop
