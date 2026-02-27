#!/usr/bin/env python3
import json
import os
import csv
from datetime import datetime
from collections import defaultdict

def parse_rmlint_report(json_path: str):
    """
    Parses the rmlint JSON output and groups all identical files by their hash.
    Returns a dictionary mapping the hash to a list of file dictionaries.
    """
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    # Group all identical files into a single list under their hash.
    # No distinction between "original" and "duplicate" is made here.
    duplicate_groups = defaultdict(list)
    
    for item in data:
        # Filter out the summary block by ensuring 'checksum' exists
        if "checksum" in item and "path" in item:
            file_hash = item["checksum"]
            duplicate_groups[file_hash].append(item)
            
    # Filter out any unique files (just in case rmlint included them)
    # We only care about groups that have more than 1 file.
    return {k: v for k, v in duplicate_groups.items() if len(v) > 1}

def format_size(bytes_size: int) -> str:
    """Converts bytes into human-readable sizes."""
    if bytes_size < 1024 * 1024:
        return f"{bytes_size / 1024:.2f} KB"
    elif bytes_size < 1024 * 1024 * 1024:
        return f"{bytes_size / (1024 * 1024):.2f} MB"
    else:
        return f"{bytes_size / (1024 * 1024 * 1024):.2f} GB"

def format_date(timestamp: float) -> str:
    """Converts a UNIX timestamp into a readable date string."""
    return datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')

def generate_pretty_report(grouped_data: dict, output_file: str):
    """
    Generates a highly readable text report for manual review.
    """
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("=" * 70 + "\n")
        f.write(" IDENTICAL FILES REPORT\n")
        f.write("=" * 70 + "\n\n")
        
        group_counter = 1
        for file_hash, files in grouped_data.items():
            file_size_str = format_size(files[0]["size"])
            total_copies = len(files)
            
            f.write(f"--- Group {group_counter} ---\n")
            f.write(f"Hash:  {file_hash}\n")
            f.write(f"Size:  {file_size_str} per file\n")
            f.write(f"Count: {total_copies} identical copies\n\n")
            
            for index, file_data in enumerate(files, 1):
                f.write(f"  {index}. Path: {file_data['path']}\n")
                f.write(f"     Date: {format_date(file_data['mtime'])}\n")
            
            f.write("\n" + "-" * 70 + "\n\n")
            group_counter += 1

def generate_csv_export(grouped_data: dict, output_file: str):
    """
    Generates a CSV file where each row is a file. It includes columns for 
    path, date, size, hash, and importantly, the paths to the other identical copies.
    """
    headers = [
        "Group ID", "File Path", "Modified Date", "Size", 
        "Hash", "Total Copies", "Paths of Other Copies"
    ]
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        
        group_counter = 1
        for file_hash, files in grouped_data.items():
            file_size_str = format_size(files[0]["size"])
            total_copies = len(files)
            
            # Create a row for every individual file in the group
            for current_file in files:
                # Get the paths of all *other* files in this group
                other_paths = [f["path"] for f in files if f["path"] != current_file["path"]]
                other_paths_str = " | ".join(other_paths)
                
                writer.writerow([
                    group_counter,
                    current_file["path"],
                    format_date(current_file["mtime"]),
                    file_size_str,
                    file_hash,
                    total_copies,
                    other_paths_str
                ])
                
            group_counter += 1

if __name__ == "__main__":
    input_json = "rmlint_report.json"
    txt_output = "duplicates_report.txt"
    csv_output = "duplicates_export.csv"
    
    if os.path.exists(input_json):
        print(f"Parsing {input_json}...")
        grouped_files = parse_rmlint_report(input_json)
        
        print("Generating text report...")
        generate_pretty_report(grouped_files, txt_output)
        
        print("Generating CSV export...")
        generate_csv_export(grouped_files, csv_output)
        
        print(f"\nDone! Please review '{txt_output}' and '{csv_output}'.")
    else:
        print(f"Error: Could not find '{input_json}'. Please run rmlint first.")

