#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Backup Utility - Core Sync Logic
# Handles dry-runs, threshold verification, and the final rsync execution.
# Protects against cascading corruption via --backup and --backup-dir
# -----------------------------------------------------------------------------

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config.env not found in $SCRIPT_DIR!"
    exit 1
fi
source "$CONFIG_FILE"

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m" # No Color

# Arguments
SOURCE_DIR="$1"
DEST_DIR="$2"
MODE="${3:-safe}"  # 'safe' or 'fast'

# Setup Logging & Archiving Paths
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/rsync_core_${TIMESTAMP}.log"

# The killer feature: Archive directory for overwritten/deleted files
ARCHIVE_DIR="$DEST_DIR/Archive/$TIMESTAMP"

# Build Exclusions Array for Rsync
RSYNC_EXCLUDES=()
for excl in "${EXCLUSIONS[@]}"; do
    RSYNC_EXCLUDES+=("--exclude=$excl")
done

echo -e "${CYAN}--- Initializing Sync ---${NC}"
echo "Source      : $SOURCE_DIR"
echo "Destination : $DEST_DIR"
echo "Mode        : $MODE"
echo "Archive Dir : $ARCHIVE_DIR"
echo "Log File    : $LOG_FILE"
echo ""

verify_thresholds() {
    local logfile="$1"
    
    # Extract file creation, deletion, and modification counts from rsync itemize-changes output
    # >f+++++++++ means created file
    # *deleting   means deleted
    # >f... means modified
    
    local created=$(grep -E '^>f\+' "$logfile" | wc -l || true)
    local deleted=$(grep -E '^\*deleting' "$logfile" | wc -l || true)
    local modified=$(grep -E '^>f[^\+]' "$logfile" | wc -l || true)
    
    echo -e "${YELLOW}>> Dry-Run Summary <<${NC}"
    echo -e "Files to Add     : ${GREEN}$created${NC}"
    echo -e "Files to Modify  : ${YELLOW}$modified${NC}"
    echo -e "Files to Delete  : ${RED}$deleted${NC}"
    
    # Calculate stats
    # To calculate total files, we could count the find command output, but it's slow.
    # We will rely entirely on the absolute deletion count for safety.
    
    local WARN=0
    
    if [ "$deleted" -gt "${WARN_THRESHOLD_DELETES:-50}" ]; then
        echo -e "\n${RED}[CRITICAL WARNING] DELETIONS EXCEED THRESHOLD!${NC}"
        echo "Threshold: ${WARN_THRESHOLD_DELETES} | Found: $deleted"
        WARN=1
    fi
    # Add more threshold checks here if we want (like modify percent)

    echo ""
    if [ "$WARN" -eq 1 ]; then
        echo -e "${RED}Large number of changes detected! Please review the log manually.${NC}"
        echo "Log snippet (top deleted files):"
        grep -E '^\*deleting' "$logfile" | head -n 10 || true
        echo ""
    fi
}

# 1. safe Mode (Dry Run first)
if [[ "$MODE" == "safe" ]]; then
    echo "Running dry-run analysis... (this may take a moment for large drives)"
    # Perform dry run using itemize-changes to be parseable
    rsync -iaAXvh --delete --dry-run "${RSYNC_EXCLUDES[@]}" "$SOURCE_DIR/" "$DEST_DIR/" > "$LOG_FILE" 2>&1
    
    verify_thresholds "$LOG_FILE"
    
    echo -ne "\n${CYAN}Do you want to proceed with the actual sync? [y/N]: ${NC}"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Sync aborted by user."
        exit 0
    fi
    echo "Proceeding with sync..."
fi

# 2. Actual Sync Execution
# --backup ensures that any file about to be overwritten or deleted is moved to --backup-dir instead
mkdir -p "$ARCHIVE_DIR"

echo "Executing rsync..."
if rsync -iaAXvh --delete --backup --backup-dir="$ARCHIVE_DIR" "${RSYNC_EXCLUDES[@]}" "$SOURCE_DIR/" "$DEST_DIR/" >> "$LOG_FILE" 2>&1; then
    echo -e "${GREEN}Sync completed successfully!${NC}"
    echo "Files that were overwritten or deleted have been safely moved to:"
    echo "$ARCHIVE_DIR"
else
    echo -e "${RED}Sync encountered errors. Check the log for details:${NC}"
    echo "$LOG_FILE"
    exit 1
fi
