#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Backup Utility - Main Interactive Wrapper
# Provides user interface, pre-flight checks, and drive mounting capabilities
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
AUDITOR_SCRIPT="$SCRIPT_DIR/auditor.py"
CORE_SYNC_SCRIPT="$SCRIPT_DIR/core_sync.sh"

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

# Load Configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Configuration file config.env not found!${NC}"
    exit 1
fi
source "$CONFIG_FILE"

# --- Functions ---

check_dependencies() {
    local missing=0
    for cmd in rsync python3 sqlite3; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Dependency missing: $cmd${NC}"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Please install missing dependencies and try again.${NC}"
        exit 1
    fi
}

mount_drive() {
    local uuid="$1"
    local mount_point="$2"
    
    if ! mountpoint -q "$mount_point"; then
        echo -e "${YELLOW}Mounting HDD with UUID $uuid to $mount_point...${NC}"
        sudo mount "UUID=$uuid" "$mount_point" || {
            echo -e "${RED}Failed to mount drive. Ensure it is connected.${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}Drive already mounted at $mount_point${NC}"
    fi
}

umount_drive() {
    local mount_point="$1"
    local uuid="$2"
    
    if mountpoint -q "$mount_point"; then
        echo -e "${YELLOW}Unmounting $mount_point...${NC}"
        sudo umount "$mount_point"
        sleep 2
        
        echo -e "${CYAN}Powering off drive (UUID: $uuid)...${NC}"
        sudo udisksctl power-off -b "/dev/disk/by-uuid/$uuid" || true
        echo -e "${GREEN}Drive powered off safely.${NC}"
    else
        echo -e "${YELLOW}Drive not mounted at $mount_point${NC}"
    fi
}

sync_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}          Select Sync Direction           ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo "1. 1TB -> 2TB HDD"
    echo "2. 1TB -> 4TB HDD"
    echo "3. 2TB -> 4TB HDD"
    echo "4. Laptop -> 4TB HDD"
    echo "5. Back to Main Menu"
    echo ""
    read -rp "Option [1-5]: " sync_opt

    local src=""
    local dest=""
    local dest_uuid=""
    
    case $sync_opt in
        1)
            mount_drive "$UUID_1TB" "$MOUNT_1TB"
            mount_drive "$UUID_2TB" "$MOUNT_2TB"
            src="$MOUNT_1TB"
            dest="$DEST_2TB_FROM_1TB"
            dest_uuid="$UUID_2TB"
            ;;
        2)
            mount_drive "$UUID_1TB" "$MOUNT_1TB"
            mount_drive "$UUID_4TB" "$MOUNT_4TB"
            src="$MOUNT_1TB"
            dest="$DEST_4TB_FROM_1TB"
            dest_uuid="$UUID_4TB"
            ;;
        3)
            mount_drive "$UUID_2TB" "$MOUNT_2TB"
            mount_drive "$UUID_4TB" "$MOUNT_4TB"
            src="$MOUNT_2TB"
            dest="$DEST_4TB_FROM_2TB"
            dest_uuid="$UUID_4TB"
            ;;
        4)
            mount_drive "$UUID_4TB" "$MOUNT_4TB"
            src="$HOME"
            dest="$DEST_4TB_LAPTOP"
            dest_uuid="$UUID_4TB"
            ;;
        5) return ;;
        *) echo "Invalid option"; sleep 1; sync_menu; return ;;
    esac

    echo -e "\n${CYAN}Select Sync Mode:${NC}"
    echo "1. Safe Sync (Dry-run -> Review -> Actual Sync + Archiving)"
    echo "2. Fast Sync (Direct Sync + Archiving - NO DRY RUN)"
    read -rp "Option [1-2]: " mode_opt
    
    local mode="safe"
    if [ "$mode_opt" == "2" ]; then
        mode="fast"
    fi
    
    # Run Core Sync
    bash "$CORE_SYNC_SCRIPT" "$src" "$dest" "$mode"
    
    echo -ne "\n${CYAN}Would you like to run the Hashing Auditor on the Destination now? [y/N]: ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        python3 "$AUDITOR_SCRIPT" "$dest" --db-name "${dest_uuid}.db"
    fi
    
    echo -e "\nPress Enter to return to main menu..."
    read -r
}

umount_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}          Safe Remove Drives              ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo "1. Remove 1TB HDD"
    echo "2. Remove 2TB HDD"
    echo "3. Remove 4TB HDD"
    echo "4. Back to Main Menu"
    echo ""
    read -rp "Option [1-4]: " u_opt
    
    case $u_opt in
        1) umount_drive "$MOUNT_1TB" "$UUID_1TB" ;;
        2) umount_drive "$MOUNT_2TB" "$UUID_2TB" ;;
        3) umount_drive "$MOUNT_4TB" "$UUID_4TB" ;;
        4) return ;;
        *) echo "Invalid option." ;;
    esac
    sleep 2
}

audit_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}          Integrity Auditor               ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo "1. Audit 1TB HDD"
    echo "2. Audit 2TB HDD"
    echo "3. Audit 4TB HDD"
    echo "4. Custom Audit (Enter path manually)"
    echo "5. Back to Main Menu"
    echo ""
    read -rp "Option [1-5]: " au_opt
    
    local target=""
    local db_name=""
    case $au_opt in
        1) target="$MOUNT_1TB"; db_name="${UUID_1TB}.db" ;;
        2) target="$MOUNT_2TB"; db_name="${UUID_2TB}.db" ;;
        3) target="$MOUNT_4TB"; db_name="${UUID_4TB}.db" ;;
        4) 
            read -rp "Enter absolute path to audit: " target
            db_name="custom_audit.db"
            ;;
        5) return ;;
        *) echo "Invalid option." ; sleep 1; audit_menu; return ;;
    esac
    
    if [[ -d "$target" ]]; then
        python3 "$AUDITOR_SCRIPT" "$target" --db-name "$db_name"
    else
        echo -e "${RED}Path $target does not exist! Did you mount the drive?${NC}"
    fi
    echo -e "\nPress Enter to return to main menu..."
    read -r
}

duplicate_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}          Find Duplicate Files            ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo "1. Search 1TB HDD"
    echo "2. Search 2TB HDD"
    echo "3. Search 4TB HDD"
    echo "4. Custom Search (Enter path manually)"
    echo "5. Back to Main Menu"
    echo ""
    read -rp "Option [1-5]: " dup_opt
    
    local target=""
    local db_name=""
    case $dup_opt in
        1) target="$MOUNT_1TB"; db_name="${UUID_1TB}.db" ;;
        2) target="$MOUNT_2TB"; db_name="${UUID_2TB}.db" ;;
        3) target="$MOUNT_4TB"; db_name="${UUID_4TB}.db" ;;
        4) 
            read -rp "Enter absolute path to search: " target
            db_name="custom_audit.db"
            ;;
        5) return ;;
        *) echo "Invalid option." ; sleep 1; duplicate_menu; return ;;
    esac
    
    if [[ -d "$target" ]]; then
        if [[ -n "${KNOWN_DUPLICATES_JSON:-}" ]] && [[ -f "$KNOWN_DUPLICATES_JSON" ]]; then
            python3 "$AUDITOR_SCRIPT" "$target" --find-duplicates --known-duplicates "$KNOWN_DUPLICATES_JSON" --db-name "$db_name"
        else
            python3 "$AUDITOR_SCRIPT" "$target" --find-duplicates --db-name "$db_name"
        fi
    else
        echo -e "${RED}Path $target does not exist! Did you mount the drive?${NC}"
    fi
    echo -e "\nPress Enter to return to main menu..."
    read -r
}

# --- Main Initialization ---
check_dependencies

while true; do
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}     Cascading Backup & Audit Utility     ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo "1. Run Backup / Sync"
    echo "2. Run Integrity Auditor"
    echo "3. Find Duplicate Files"
    echo "4. Safely Remove Drive"
    echo "5. Exit"
    echo ""
    read -rp "Select an option [1-5]: " option
    
    case $option in
        1) sync_menu ;;
        2) audit_menu ;;
        3) duplicate_menu ;;
        4) umount_menu ;;
        5) clear; exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
    esac
done
