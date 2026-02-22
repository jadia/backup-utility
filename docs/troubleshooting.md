# Troubleshooting & Scenario Guides

## Issue: Permission Denied during `./main.sh`
* **Cause**: The scripts were not granted execution permissions.
* **Fix**: Run `chmod +x main.sh core_sync.sh auditor.py`

## Issue: UUID Not Found / Drive Fails to Mount
* **Cause**: You may have replaced a hard drive, leaving the old UUID in `config.env`.
* **Fix**: 
  1. Plug in the new drive.
  2. Run `lsblk -f` or `sudo blkid` in the terminal to find the new UUID.
  3. Open `config.env` and update the respective `UUID_1TB` / `UUID_2TB` / `UUID_4TB`.

## Issue: Auditor.py is returning heavily inflated "New Files"
* **Cause**: You recently ran a massive folder restructuring. While `auditor.py` attempts to intelligently resolve moves, if you also touched the `mtime` or simultaneously modified the files during the move, it handles them as brand new files.
* **Fix**: This is normal expected behavior during massive restructures. Allow the auditor to rebuild baseline hashes. To reduce noise in the future, try to move directories without modifying their contents before the next audit.

## Issue: Windows reports invalid characters in filenames
* **Cause**: Ext4 (Linux) allows characters strictly prohibited by NTFS (Windows), such as `:`, `?`, `<`, `>`, and `*`.
* **Fix/Workaround**: Before syncing laptop data to the external drives, use a utility like `detox` to sanitize filenames, or pipe a `find` command to strip invalid characters. Currently, `rsync` warns but may stall on these files. We advise reviewing `rsync` logs for any skipped files due to invalid NTFS naming conventions.

## Issue: The Auditor is taking longer than expected
* **Cause**: By default, the Python hashing auditor reads files in 4096-byte chunks.
* **Fix**: 
  * Ensure the drive is plugged into a USB 3.0+ port.
  * Adjust `AUDITOR_EXT_FILTER` in `config.env` to only target high-value binary files like `.jpg`, `.mp4`, or `.pdf` to vastly reduce the scope of the hash calculations.

## Use Case: Migrating the Auditor Database
* **Scenario**: You are moving to a new laptop and want to take the backup utility along.
* **Action**: Ensure you copy `auditor.db` (usually sitting in the `backup-utility/` root) along with `config.env`. The SQLite database is fully portable. If you lose `auditor.db`, the auditor will simply rebuild the baseline hashes from scratch on its next run.

## Advanced Use Case: Changing Mount Points (Database Migration)
* **Scenario**: You decided to change your system's drive mount points. For example, you were mounting the 1TB drive at `/mnt/1tb` but now you want to mount it at `/mounts/1tb_hdd`. 
* **The Problem**: Because the SQLite database (`auditor.db`) stores **absolute file paths**, simply changing `config.env` and running the script will cause the auditor to think every single file was deleted from `/mnt/1tb` and millions of brand new files were just added to `/mounts/1tb_hdd`. It will forcefully rehash everything.
* **The Solution (SQLite Query)**: You can manually modify the file paths in the database instantly using a single SQL `REPLACE` string function!

**Step-by-Step Guide**:
1. First, update `config.env` to your new mount path (`MOUNT_1TB="/mounts/1tb_hdd"`).
2. Do **not** run the backup script or auditor yet!
3. Open the database in your terminal:
   ```bash
   sqlite3 auditor.db
   ```
4. Run the following `UPDATE` query to instantly rewrite the `/mnt/1tb/` prefix to `/mounts/1tb_hdd/` for all rows:
   ```sql
   UPDATE file_hashes 
   SET file_path = REPLACE(file_path, '/mnt/1tb/', '/mounts/1tb_hdd/') 
   WHERE file_path LIKE '/mnt/1tb/%';
   ```
5. Verify it worked:
   ```sql
   SELECT file_path FROM file_hashes WHERE file_path LIKE '/mounts/1tb_hdd/%' LIMIT 3;
   ```
6. Type `.exit` to close SQLite. 
7. You can now safely run the auditor, and it will flawlessly map to the new mount path without rehashing a single byte!
