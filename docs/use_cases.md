# General Use Cases & Recovery

This guide walks through the primary use cases and how to manually recover data.

## Use Case 1: Routine Backup

**Scenario:** You have shot some new photos on your 1TB drive and want to safely back them up to your 2TB drive.
1. Run `./main.sh`
2. Select "Run Backup / Sync"
3. Choose `1TB -> 2TB HDD`
4. Select `Safe Sync`
5. The utility will parse the dry-run, tell you it found 45 new files, 0 deleted, and 0 modified.
6. It prompts for approval. You hit `Y`.
7. Once finished, it asks if you'd like to Audit the destination. This is optional but good practice to run periodically.

## Use Case 2: Accidental Deletion Recovery

**Scenario:** You accidentally deleted the "Family Vacation 2025" folder off the 1TB drive three months ago. You only just realized this today after running `main.sh` numerous times.

**Recovery Steps:**
Because you used `Safe Sync`, `rsync` did not permanently delete the folder from the 2TB drive. Instead, it moved the folder to the `Archive/` directory during the sync cycle when it originally noticed the folder was missing.
1. Navigate to `/mnt/2tb/1tb_backup/Archive/`
2. Look through the timestamped folders for the date you likely ran the sync after deleting it.
3. You will find `Family Vacation 2025` completely intact.
4. Copy it back to the active `1tb_backup` repository or the original 1TB drive.

## Use Case 3: The Integrity Audit (Bit-Rot Detection)

**Scenario:** You want peace of mind that your thousands of photos haven't succumbed to silent data corruption on the 4TB long-term storage drive.
1. Run `./main.sh` -> "Run Integrity Auditor" -> `4TB HDD`.
2. The auditor will scan the drive. Since it's the first time, it hashes everything, building a baseline in `auditor.db` and outputting a log.
3. Six months later, you run it again. The auditor skips everything that hasn't changed its size or `mtime`.
4. If a file's hash mysteriously un-aligns with the database while its size and `mtime` stayed the same...
   **[🚨 CRITICAL: 1 FILES FLAGGED FOR BIT-ROT!]** 
5. Open the log file mentioned in the terminal output to find the exact corrupted file. 
6. You can then restore a healthy version of that file from the `Archive/` directories or a secondary backup.

## Use Case 4: Freeing up Drive Space

**Scenario:** Over time, the `Archive/` directories on your 2TB and 4TB drives will grow large as they capture every modified and deleted file. 
* **Protocol:** Once you are completely satisfied that the main `1tb_backup` repository is healthy and you have no accidental deletions you wish to restore, you can safely `rm -rf` the older timestamped folders inside `Archive/` to reclaim space.

## Use Case 5: Dealing with Duplicates

**Scenario:** Over the years, you have accumulated duplicate files across different folders, and you want to detect them without being overwhelmed by duplicates you have intentionally kept.
1. Run `./main.sh` -> "Find Duplicate Files" -> `Select a Drive`.
2. The auditor will use its existing database (no hashing required) to find all active files that share a hash and output an organized `duplicates_YYYY-MM-DD.json` in the `logs/` directory.
3. If you review this file and decide you want to intentionally keep these duplicates (and don't want the script to keep bugging you about them), simply copy or rename this `.json` file to the path specified in your `config.env` under `KNOWN_DUPLICATES_JSON`.
4. Next time you run "Find Duplicate Files", the auditor will load your known duplicates file. Any file sets that perfectly match the known files you already acknowledged will be intelligently hidden, only showing you *new* duplicates!

## Use Case 6: Direct SQLite Database Querying for Insights

**Scenario:** You want precisely detailed metrics about your drive's state without writing complex bash `find` scripts. Since `auditor.py` builds a full SQLite database mapping your drives, you can query it directly!

**How to Query:**
Enter the SQLite prompt by running:
```bash
sqlite3 auditor.db
```

**Creative Query Examples:**

* **Find the Top 10 Largest Forgotten Files (Not Modified in over 5 Years)**
  ```sql
  SELECT file_path, (file_size / 1024 / 1024) || ' MB' as SizeMB 
  FROM file_hashes 
  WHERE status = 'active'
    -- Find files older than 5 years (approx 157784630 seconds)
    AND mtime < strftime('%s', 'now') - 157784630 
  ORDER BY file_size DESC 
  LIMIT 10;
  ```

* **Generate a "Corrupted Files" Report**
  ```sql
  -- Instantly list every file ever flagged by the auditor for Bit-rot.
  SELECT file_path, datetime(last_seen, 'unixepoch') as Discovered
  FROM file_hashes
  WHERE status = 'corrupted';
  ```

* **Find Files that Only Exist as "Archive" Backups (Missing from the main drive)**
  ```sql
  -- Assuming your sync script moves things to /Archive/ folders when modified/deleted:
  SELECT file_name, file_path 
  FROM file_hashes 
  WHERE file_path LIKE '%/Archive/%' 
    AND status = 'active'
    AND sha256_hash NOT IN (
        SELECT sha256_hash 
        FROM file_hashes 
        WHERE file_path NOT LIKE '%/Archive/%' AND status = 'active'
    );
  ```

* **Storage Consumption by File Extension**
  ```sql
  SELECT 
      substr(file_name, instr(file_name, '.') + 1) as extension,
      count(*) as total_files,
      SUM(file_size) / 1024 / 1024 || ' MB' as TotalSize
  FROM file_hashes
  WHERE status = 'active' AND file_name LIKE '%.%'
  GROUP BY extension
  ORDER BY SUM(file_size) DESC
  LIMIT 5;
  ```
