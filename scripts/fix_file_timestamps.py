#!/usr/bin/env python3

"""
Fix file timestamps using EXIF data when available, otherwise use OS creation time.

For files with EXIF metadata (images, videos), extracts the timestamp from EXIF.
For files without EXIF, uses the operating system's creation/birth time.
"""

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("Warning: PIL/Pillow not installed. Install with: pip install Pillow", file=sys.stderr)

try:
    import exifread
    HAS_EXIFREAD = True
except ImportError:
    HAS_EXIFREAD = False


def get_exif_datetime_pil(image_path: Path) -> datetime | None:
    """Extract datetime from EXIF using PIL/Pillow."""
    if not HAS_PIL:
        return None
    
    try:
        with Image.open(image_path) as img:
            exif = img.getexif()
            if not exif:
                return None
            
            # Try different EXIF datetime tags
            datetime_tags = [306, 36867, 36868]  # DateTime, DateTimeOriginal, DateTimeDigitized
            for tag_id in datetime_tags:
                if tag_id in exif:
                    dt_str = exif[tag_id]
                    if isinstance(dt_str, str):
                        # Parse EXIF datetime format: "YYYY:MM:DD HH:MM:SS"
                        try:
                            return datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
                        except ValueError:
                            continue
    except Exception:
        pass
    
    return None


def get_exif_datetime_exifread(image_path: Path) -> datetime | None:
    """Extract datetime from EXIF using exifread library."""
    if not HAS_EXIFREAD:
        return None
    
    try:
        with open(image_path, 'rb') as f:
            tags = exifread.process_file(f, details=False)
            
            # Try different EXIF datetime tags
            datetime_tags = ['EXIF DateTimeOriginal', 'EXIF DateTimeDigitized', 'Image DateTime']
            for tag_name in datetime_tags:
                if tag_name in tags:
                    dt_str = str(tags[tag_name])
                    # Parse EXIF datetime format: "YYYY:MM:DD HH:MM:SS"
                    try:
                        return datetime.strptime(dt_str, "%Y:%m:%d %H:%M:%S")
                    except ValueError:
                        continue
    except Exception:
        pass
    
    return None


def get_exif_datetime(image_path: Path) -> datetime | None:
    """Extract datetime from EXIF metadata, trying multiple methods."""
    # Try PIL first (more common)
    dt = get_exif_datetime_pil(image_path)
    if dt:
        return dt
    
    # Fall back to exifread
    dt = get_exif_datetime_exifread(image_path)
    if dt:
        return dt
    
    return None


def get_creation_time(file_path: Path) -> datetime:
    """Get file creation/birth time from OS."""
    stat_info = os.stat(file_path)
    
    # Try st_birthtime (macOS, BSD)
    if hasattr(stat_info, 'st_birthtime'):
        return datetime.fromtimestamp(stat_info.st_birthtime)
    
    # Fall back to st_ctime (Linux - metadata change time, but often creation time)
    # On Linux, st_ctime is actually the metadata change time, not creation time
    # but it's the best we can do without filesystem-specific tools
    return datetime.fromtimestamp(stat_info.st_ctime)


def get_file_timestamp(file_path: Path) -> tuple[datetime, str]:
    """
    Get timestamp for a file, preferring EXIF over OS creation time.
    
    Returns:
        (datetime, source) where source is 'exif' or 'creation'
    """
    # Check if file might have EXIF (common image/video extensions)
    exif_extensions = {'.jpg', '.jpeg', '.tiff', '.tif', '.png', '.heic', '.heif', '.cr2', '.nef', '.arw'}
    
    if file_path.suffix.lower() in exif_extensions:
        exif_dt = get_exif_datetime(file_path)
        if exif_dt:
            return (exif_dt, 'exif')
    
    # Fall back to OS creation time
    creation_dt = get_creation_time(file_path)
    return (creation_dt, 'creation')


def set_file_timestamp(file_path: Path, dt: datetime) -> bool:
    """Set file modification and access time to the given datetime."""
    try:
        timestamp = dt.timestamp()
        os.utime(file_path, (timestamp, timestamp))
        return True
    except Exception as e:
        print(f"Error setting timestamp for {file_path}: {e}", file=sys.stderr)
        return False


def process_file(file_path: Path, dry_run: bool = False, set_timestamp: bool = False) -> None:
    """Process a single file and display or update its timestamp."""
    if not file_path.exists():
        print(f"File not found: {file_path}", file=sys.stderr)
        return
    
    dt, source = get_file_timestamp(file_path)
    
    print(f"{file_path.name}")
    print(f"  Timestamp: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Source: {source}")
    
    if set_timestamp:
        if dry_run:
            print(f"  [DRY RUN] Would set file timestamp to {dt.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            if set_file_timestamp(file_path, dt):
                print(f"  [OK] Set file timestamp to {dt.strftime('%Y-%m-%d %H:%M:%S')}")
            else:
                print(f"  [ERROR] Failed to set file timestamp")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fix file timestamps using EXIF data or OS creation time"
    )
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="File or directory paths to process"
    )
    parser.add_argument(
        "--set-timestamp",
        action="store_true",
        help="Set file modification time to the extracted timestamp"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes"
    )
    parser.add_argument(
        "--recursive",
        "-r",
        action="store_true",
        help="Recursively process directories"
    )
    parser.add_argument(
        "--extensions",
        nargs="+",
        default=None,
        help="Only process files with these extensions (e.g., .jpg .png). Default: all files"
    )
    
    args = parser.parse_args()
    
    if not HAS_PIL and not HAS_EXIFREAD:
        print("Error: No EXIF library available. Install one of:", file=sys.stderr)
        print("  pip install Pillow", file=sys.stderr)
        print("  pip install exifread", file=sys.stderr)
        sys.exit(1)
    
    files_to_process = []
    
    for path in args.paths:
        if not path.exists():
            print(f"Warning: Path does not exist: {path}", file=sys.stderr)
            continue
        
        if path.is_file():
            if args.extensions:
                if path.suffix.lower() not in [ext.lower() for ext in args.extensions]:
                    continue
            files_to_process.append(path)
        elif path.is_dir():
            if args.recursive:
                for file_path in path.rglob("*"):
                    if file_path.is_file():
                        if args.extensions:
                            if file_path.suffix.lower() not in [ext.lower() for ext in args.extensions]:
                                continue
                        files_to_process.append(file_path)
            else:
                print(f"Warning: {path} is a directory. Use --recursive to process directories.", file=sys.stderr)
        else:
            print(f"Warning: {path} is not a file or directory", file=sys.stderr)
    
    if not files_to_process:
        print("No files to process.", file=sys.stderr)
        sys.exit(1)
    
    print(f"Processing {len(files_to_process)} file(s)...\n")
    
    for file_path in sorted(files_to_process):
        process_file(file_path, dry_run=args.dry_run, set_timestamp=args.set_timestamp)


if __name__ == "__main__":
    main()
