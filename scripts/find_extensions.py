#!/usr/bin/env python3
import os
import sys
from collections import Counter

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 find_extensions.py <target_directory> [output_file]")
        sys.exit(1)
        
    target_dir = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "extension_report.log"
    
    if not os.path.isdir(target_dir):
        print(f"Error: {target_dir} is not a valid directory.")
        sys.exit(1)
        
    print(f"Scanning {target_dir} for file extensions...")
    ext_counts = Counter()
    
    scanned = 0
    # Walk the directory tree
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            scanned += 1
            if scanned % 10000 == 0:
                print(f"Scanned {scanned} files...")
            
            # Extract extension and convert to lowercase
            _, ext = os.path.splitext(file)
            if ext:
                ext_counts[ext.lower()] += 1
            else:
                ext_counts["<no_extension>"] += 1
                
    print(f"\nScan complete. Total files processed: {scanned}")
    
    # Save formatted report
    with open(output_file, 'w') as f:
        f.write(f"Extension Report for: {target_dir}\n")
        f.write(f"Total Files: {scanned}\n")
        f.write("-" * 40 + "\n")
        f.write(f"{'Extension':<20} | {'Count':<10}\n")
        f.write("-" * 40 + "\n")
        
        for ext, count in ext_counts.most_common():
            f.write(f"{ext:<20} | {count:<10}\n")
            
    print(f"Report saved to: {output_file}")
    print("\nTop 15 most common extensions:")
    for ext, count in ext_counts.most_common(15):
        print(f"  {ext:<15} : {count}")

if __name__ == "__main__":
    main()
