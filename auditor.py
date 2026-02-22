#!/usr/bin/env python3
"""
Backup Utility - Intelligent Hashing Auditor
This script scans directories, calculates SHA256 hashes of files, and stores them in an SQLite database.
It is designed to be fast and minimize false positives by distinguishing between:
1. Untouched files (skips hashing if mtime and size are unchanged)
2. Moved files (detects matching hash/size at a new path)
3. Modified files (mtime/size changed, recalculates hash)
4. Bit-rot (mtime/size unchanged, but hash changed)
"""

import os
import sys
import sqlite3
import hashlib
import time
import argparse
import json
from datetime import datetime

# Load configuration safely from JSON
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "auditor_config.json")

def load_config():
    if not os.path.exists(CONFIG_FILE):
        print(f"Error: {CONFIG_FILE} not found. Please ensure it exists.")
        sys.exit(1)
        
    with open(CONFIG_FILE, 'r') as f:
        try:
            config = json.load(f)
            return config
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON configuration in {CONFIG_FILE}: {e}")
            sys.exit(1)

CONFIG = load_config()

# Database setup
DB_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), CONFIG.get('DB_NAME', 'auditor.db'))
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")

# Ensure logs dir exists
os.makedirs(LOG_DIR, exist_ok=True)
TIMESTAMP = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
LOG_FILE = os.path.join(LOG_DIR, f"auditor_log_{TIMESTAMP}.txt")

def log(msg, echo=True):
    if echo:
        print(msg)
    with open(LOG_FILE, 'a') as f:
        f.write(msg + '\n')

def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS file_hashes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT UNIQUE,
            file_name TEXT,
            file_size INTEGER,
            mtime REAL,
            sha256_hash TEXT,
            last_seen REAL,
            status TEXT DEFAULT 'active'
        )
    ''')
    # Indexes for fast querying
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_file_path ON file_hashes(file_path)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_hash_size ON file_hashes(sha256_hash, file_size)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_status ON file_hashes(status)')
    conn.commit()
    return conn

def calculate_sha256(file_path):
    """Calculates SHA256 hash of a file efficiently by reading in chunks."""
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except IOError as e:
        log(f"Error hashing {file_path}: {e}", echo=False)
        return None

def should_exclude(file_path):
    """Check if file should be excluded based on config rules."""
    path_lower = file_path.lower()
    
    # 1. Check directory exclusions
    for exclusion in CONFIG.get('EXCLUSIONS', []):
        if exclusion.lower() in path_lower:
            return True
            
    # 2. Check extension filter (if defined)
    ext_filter = CONFIG.get('EXT_FILTER', [])
    if ext_filter:
        _, ext = os.path.splitext(file_path)
        if ext.lower() not in ext_filter:
            return True
            
    return False

def run_audit(target_dir, force_rehash=False):
    if not os.path.isdir(target_dir):
        log(f"Error: Target directory '{target_dir}' does not exist.")
        return

    log(f"--- Starting Audit of: {target_dir} ---")
    log(f"Database: {DB_FILE}")
    log(f"Start Time: {datetime.now()}")
    
    conn = init_db()
    cursor = conn.cursor()
    
    current_time = time.time()
    
    # Stats
    stats = {
        'scanned': 0,
        'skipped_unchanged': 0,
        'new_files': 0,
        'modified_files': 0,
        'moved_files': 0,
        'bitrot_detected': 0,
        'removed_files': 0,
        'errors': 0
    }
    
    bitrot_list = []
    
    # Reset 'current_run_flag' or similar logic. We will use `last_seen` to track what is currently present.
    # Files not seen in this run will be marked as 'missing'.
    
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            file_path = os.path.join(root, file)
            
            if should_exclude(file_path):
                continue
                
            stats['scanned'] += 1
            if stats['scanned'] % 5000 == 0:
                print(f"Scanned {stats['scanned']} files...")

            try:
                stat_info = os.stat(file_path)
                file_size = stat_info.st_size
                mtime = stat_info.st_mtime
                
                # Check if file exists in DB
                cursor.execute("SELECT id, file_size, mtime, sha256_hash FROM file_hashes WHERE file_path = ?", (file_path,))
                row = cursor.fetchone()
                
                if row:
                    db_id, db_size, db_mtime, db_hash = row
                    
                    if not force_rehash and db_size == file_size and db_mtime == mtime:
                        # 1. Untouched file
                        cursor.execute("UPDATE file_hashes SET last_seen = ?, status = 'active' WHERE id = ?", (current_time, db_id))
                        stats['skipped_unchanged'] += 1
                    else:
                        # File changed (size or mtime changed) OR force rehash
                        new_hash = calculate_sha256(file_path)
                        if not new_hash:
                            stats['errors'] += 1
                            continue
                            
                        # If size/mtime matches but hash changed -> BIT-ROT 🚨
                        if not force_rehash and db_size == file_size and db_mtime == mtime and new_hash != db_hash:
                            log(f"[🚨 BIT-ROT DETECTED] {file_path}")
                            log(f"  Old Hash: {db_hash} -> New Hash: {new_hash}")
                            stats['bitrot_detected'] += 1
                            bitrot_list.append(file_path)
                            # Update DB so we don't keep alerting? Or keep alerting? Let's update it for now but flag it.
                            cursor.execute("UPDATE file_hashes SET sha256_hash = ?, last_seen = ?, status = 'corrupted' WHERE id = ?", (new_hash, current_time, db_id))
                        else:
                            # 3. Intentional modification (mtime/size changed)
                            cursor.execute("UPDATE file_hashes SET file_size = ?, mtime = ?, sha256_hash = ?, last_seen = ?, status = 'active' WHERE id = ?", (file_size, mtime, new_hash, current_time, db_id))
                            stats['modified_files'] += 1
                else:
                    # File not in DB at this path. Calculate hash.
                    new_hash = calculate_sha256(file_path)
                    if not new_hash:
                        stats['errors'] += 1
                        continue
                        
                    # Check if it's a move (hash & size exist elsewhere)
                    cursor.execute("SELECT id, file_path FROM file_hashes WHERE sha256_hash = ? AND file_size = ?", (new_hash, file_size))
                    move_candidates = cursor.fetchall()
                    
                    moved = False
                    for mc_id, mc_path in move_candidates:
                        if not os.path.exists(mc_path):
                            # The old path no longer exists, so this is definitely a move!
                            cursor.execute("UPDATE file_hashes SET file_path = ?, file_name = ?, mtime = ?, last_seen = ?, status = 'active' WHERE id = ?", 
                                         (file_path, file, mtime, current_time, mc_id))
                            stats['moved_files'] += 1
                            moved = True
                            break
                    
                    if not moved:
                        # 2. Truly new file
                        cursor.execute("INSERT INTO file_hashes (file_path, file_name, file_size, mtime, sha256_hash, last_seen) VALUES (?, ?, ?, ?, ?, ?)",
                                     (file_path, file, file_size, mtime, new_hash, current_time))
                        stats['new_files'] += 1
                        
            except Exception as e:
                log(f"Error processing {file_path}: {e}", echo=False)
                stats['errors'] += 1
                
        # Commit periodically
        conn.commit()
    
    # Find active files not seen in this run (if they share the root directory prefix, they are deleted)
    like_query = f"{target_dir}%"
    cursor.execute("SELECT file_path FROM file_hashes WHERE file_path LIKE ? AND last_seen < ? AND status = 'active'", (like_query, current_time - 3600))
    missing_files = cursor.fetchall()
    
    for mf in missing_files:
        if not os.path.exists(mf[0]):
            cursor.execute("UPDATE file_hashes SET status = 'missing' WHERE file_path = ?", (mf[0],))
            stats['removed_files'] += 1
            
    conn.commit()
    conn.close()
    
    log("\n--- Audit Summary ---")
    log(f"Total Files Scanned  : {stats['scanned']}")
    log(f"Skipped (Unchanged)  : {stats['skipped_unchanged']}")
    log(f"New Files Added      : {stats['new_files']}")
    log(f"Files Modified       : {stats['modified_files']}")
    log(f"Files Moved/Renamed  : {stats['moved_files']}")
    log(f"Files Removed        : {stats['removed_files']}")
    log(f"Processing Errors    : {stats['errors']}")
    
    if stats['bitrot_detected'] > 0:
        log("\n=======================================================")
        log(f"🚨 CRITICAL: {stats['bitrot_detected']} FILES FLAGGED FOR BIT-ROT! 🚨")
        log("These files have the exact same size and modification time")
        log("as before, but their SHA-256 hash has changed.")
        for brf in bitrot_list:
            log(f" -> {brf}")
        log("=======================================================")
    else:
        log("\n✅ Health Check Passed: 0 files flagged for bit-rot.")
        
    log(f"\nDetailed log saved to: {LOG_FILE}")

def find_duplicates(target_dir, known_dupes_file=None):
    log(f"--- Finding Duplicates in DB for: {target_dir} ---")
    
    known_dupes_map = {}
    if known_dupes_file and os.path.isfile(known_dupes_file):
        log(f"Loading known duplicates from: {known_dupes_file}")
        try:
            with open(known_dupes_file, 'r') as f:
                known_data = json.load(f)
                if isinstance(known_data, list):
                    for item in known_data:
                        if 'hash' in item and 'files' in item:
                            known_dupes_map[item['hash']] = set(item['files'])
        except Exception as e:
            log(f"Warning: Could not parse known duplicates JSON: {e}")
            
    conn = init_db()
    cursor = conn.cursor()
    
    like_query = f"{target_dir}%"
    cursor.execute('''
        SELECT sha256_hash, COUNT(*) as c
        FROM file_hashes
        WHERE file_path LIKE ? AND status = 'active'
        GROUP BY sha256_hash
        HAVING c > 1
    ''', (like_query,))
    
    duplicate_hashes = cursor.fetchall()
    
    result = []
    total_wasted_space = 0
    duplicate_count = 0
    
    result = []
    total_wasted_space = 0
    duplicate_count = 0
    
    for (d_hash, count) in duplicate_hashes:
        cursor.execute("SELECT file_path, file_size FROM file_hashes WHERE sha256_hash = ? AND status = 'active' AND file_path LIKE ?", (d_hash, like_query))
        files = cursor.fetchall()
        
        # Exclude Archive directory hits
        active_files = [f for f in files if "/Archive/" not in f[0]]
        active_paths_set = set(f[0] for f in active_files)
        
        # If all paths found are already known duplicates to the user for this hash, ignore it output.
        if d_hash in known_dupes_map and active_paths_set.issubset(known_dupes_map[d_hash]):
            continue
            
        if len(active_files) > 1:
            file_size = active_files[0][1]
            total_wasted_space += file_size * (len(active_files) - 1)
            duplicate_count += len(active_files) - 1
            
            result.append({
                "hash": d_hash,
                "size_bytes": file_size,
                "files": list(active_paths_set)
            })
            
    conn.close()
    
    out_file = os.path.join(LOG_DIR, f"duplicates_{TIMESTAMP}.json")
    with open(out_file, 'w') as f:
        json.dump(result, f, indent=4)
        
    log(f"Found {duplicate_count} purely new duplicate files.")
    log(f"Wasted space: {total_wasted_space / (1024*1024):.2f} MB")
    log(f"Duplicate report saved to: {out_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backup utility intelligent hashing auditor.")
    parser.add_argument("target_dir", help="The directory to audit")
    parser.add_argument("--force-rehash", action="store_true", help="Force recalculation of hashes ignoring mtime/size")
    parser.add_argument("--find-duplicates", action="store_true", help="Find duplicate files in the audited directory (based on DB)")
    parser.add_argument("--known-duplicates", default="", help="Path to JSON file with known duplicates to ignore")
    
    args = parser.parse_args()
    
    if args.find_duplicates:
        find_duplicates(args.target_dir, args.known_duplicates)
    else:
        run_audit(args.target_dir, args.force_rehash)
