# Duplicate File Finder & Reporter

This repository contains the workflow for safely finding and reporting duplicate files across large datasets (like backups and phone syncs) without risking accidental data loss. It uses the highly optimized `rmlint` utility to generate a secure JSON scan, and a custom Python script (`process_dupe_report.py`) to parse that data into human-readable text and Excel-ready CSV formats.

## ⚠️ Important Safety Note
This entire workflow is completely **non-destructive**. 
- `rmlint` is strictly configured to only output a JSON log. No shell deletion scripts are generated.
- `process_dupe_report.py` only reads the JSON and writes text/CSV reports. It contains no `os.remove()` or deletion logic.

---

## Step 1: Scanning with `rmlint`

To find duplicates quickly and safely, we use `rmlint`. This specific command is highly optimized for dealing with massive files (like large video files on external hard drives).

### The Command
```bash
rmlint -T df -g -t 1 --partial-hidden -o json:rmlint_report.json /path/to/scan
```
*(Replace `/path/to/scan` with your actual directory, e.g., `/mnt/external_drive`)*

### Understanding the Flags
*   **`-T df`**: Tells `rmlint` to only look for **D**uplicate **F**iles. It ignores empty directories, empty files, or broken symlinks to keep the JSON output clean.
*   **`-g`**: Displays a progress bar in the terminal so you know the scan isn't frozen.
*   **`-t 1`**: Limits processing to **1 thread**. This prevents violently thrashing the read/write heads of mechanical hard drives when attempting to read multiple 30GB+ video files simultaneously.
*   **`--partial-hidden`**: **(Speed Optimization)** Instead of reading every single byte of a massive file, this tells `rmlint` to only check the exact file size and the first/last few megabytes. This drops scan times for massive video files from hours down to seconds.
*   **`-o json:rmlint_report.json`**: Forces the output strictly into a JSON file format and implicitly stops `rmlint` from generating its default interactive shell deletion script.

> **Note on Filenames:** `rmlint` determines duplicates strictly by content hash and file size, completely ignoring the filenames. A file named `video1.mp4` and an exact copy named `backup.mp4` will correctly be flagged as identical.

---

## Step 2: Generating Reports

Once `rmlint_report.json` is generated, run the custom Python script to parse the data into readable reports.

### The Command
```bash
python3 process_dupe_report.py
```

### What It Does
The script strips away the complex JSON metadata and groups identical files together strictly by their cryptographic hash. It then automatically generates two files in your current directory:

1. **`duplicates_report.txt`** 
   A visually structured text file designed for terminal reading or quick scrolling. It shows the file size, hash, and a cleanly indented list of all identical file paths alongside their modified dates.
   
2. **`duplicates_export.csv`** 
   A structured spreadsheet ready to be opened in Excel, LibreOffice Calc, or Google Sheets. 
   - Every individual file gets its own row.
   - You can easily sort by size or date.
   - The final column (`Paths of Other Copies`) displays exactly where the other identical versions of that specific file are located, keeping all context in a single view.

## Requirements
*   **Ubuntu/Linux**: `sudo apt install rmlint`
*   **Python 3.x**: No external pip packages required (only uses standard libraries: `json`, `csv`, `os`, `collections`, `datetime`).
