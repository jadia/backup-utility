# Architecture & Philosophy

This document outlines *why* this utility is structured the way it is and *how* the different components collaborate to provide a failsafe environment.

## The Sync Problem: Cascading and Redundancy
In a standard daisy-chain cascading backup (`1TB -> 2TB -> 4TB`), using `rsync --delete` creates an identical mirror. This introduces two severe flaws:
1. **Silent Overwrites**: If a file becomes silently corrupted on the source drive (e.g., bit-rot), `rsync` detects a difference and faithfully overwrites the healthy backup downstream. This destroys the only good copy of the data. 
2. **Nested Redundancy**: If you cascade A into B, and then sync B into C, you end up with C holding copies of both B and awkwardly nested copies of A (`/mnt/4tb/2tb_backup/1tb_backup`).

## The Solutions

### 1. The Hub & Spoke Topology
To prevent redundant nesting, we utilize a Hub & Spoke mapping model configured in `config.env`. The 1TB backups reside independently on both the 2TB and the 4TB. To enforce this, the `auditor_config.json` natively excludes the `1tb_backup/` directory when syncing data from the 2TB to the 4TB, ensuring flat, independent archives.

### 2. The "Archive" Failsafe
Instead of directly overwriting or deleting files on the destination drive, `core_sync.sh` utilizes `rsync`'s built-in `--backup` and `--backup-dir` flags.

**How it works:**
1. Let's say `/mnt/1tb/photo.jpg` is corrupted.
2. `core_sync` detects a difference between `/mnt/1tb/photo.jpg` and `/mnt/2tb/1tb_backup/photo.jpg`.
3. Before overwriting the 2TB version, `rsync` **moves** the healthy 2TB version into a timestamped directory: `/mnt/2tb/1tb_backup/Archive/2026-02-.../photo.jpg`.
4. It then copies the corrupted 1TB version to the main pool on the 2TB drive.

This means you *always* retain the historical state of files prior to modification or deletion, safely tucked away in the Archive folder.

## The Integrity Auditor (`auditor.py`)
To solve the silent corruption issue *before* it gets synced downstream, we've implemented an intelligent SQLite hashing auditor.

### Why not just re-hash everything?
Hashing 4TB of data takes hours. We need it to be fast.
### The Auditor Logic
1. **Unchanged Files:** The auditor checks the file's Size and Modified Time (`mtime`) against the SQLite DB. If they remain the same, it assumes the file hasn't changed and skips the expensive hashing process.
2. **True Corruption (Bit-Rot):** If the Size and `mtime` are identical to the Database, BUT a random or forced re-hash reveals the `SHA-256` signature changed, the auditor flags this as **CRITICALLY CORRUPTED**.
3. **Intentional Edits:** If the Size or `mtime` changed, the auditor recalculates the hash and updates the DB, assuming you intentionally edited the file.
4. **Renames/Moves:** If a "new" file appears, the auditor hashes it and checks the DB. If it finds the exact same hash and size under an older, missing filename, it intelligently updates the path without creating duplicate noise.

## Database Structure & Schema (`auditor.db`)
The Python auditor utilizes a lightweight SQLite3 database to map the state of your drive efficiently. 

### Table: `file_hashes`
| Column Name   | Type    | Description |
| ------------- | ------- | ----------- |
| `id`          | INTEGER | Primary Auto-Increment Key. |
| `file_path`   | TEXT    | Absolute path to the file on the drive (UNIQUE). |
| `file_name`   | TEXT    | The basename of the file. |
| `file_size`   | INTEGER | Size of the file in bytes. |
| `mtime`       | REAL    | Modification timestamp of the file. |
| `sha256_hash` | TEXT    | The calculated SHA-256 integrity hash of the file. |
| `last_seen`   | REAL    | Timestamp of the last time the auditor verified this file existed. |
| `status`      | TEXT    | Tracks file state. Values: `active`, `missing`, `corrupted`. |

### Database Limitations & Constraints
1. **Single-Threaded Writing:** SQLite locks the database file during writes. While read queries are fast, the current python script executes single-threaded directory walks.
2. **Absolute vs Relative Paths:** The database tracks absolute paths (`/mnt/1TB/images/...`). If you mount a drive to a different mount point (e.g., `/media/user/1TB`), the database will treat all files as missing and new. **Always use the `main.sh` wrapper** to ensure drives are mounted to consistent paths as defined in your `config.env`.
3. **Mass Deletions via `last_seen`:** The auditor doesn't actively track folder deletions in real-time. Instead, it sweeps the database at the end of every run. Any active file that belongs to the current target directory but has a `last_seen` time predating the start of the audit is marked as `missing`.
