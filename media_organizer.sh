#!/bin/bash

# Start timer immediately so we can calculate elapsed correctly
start_time=$(date +%s)

#######################################
# Helper & usage
#######################################
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

help_message() {
  cat <<EOF
Usage: $0 --source-path PATH --output-path PATH [--recursive] [--dry-run] [--include-uncategorized] [--skip-duplicates]

  -s, --source-path:            Path to your source directory
  -o, --output-path:            Path to the target directory
  -r, --recursive:              Recurse into subdirectories
  -d, --dry-run:                Don’t actually copy, just show actions
  -u, --include-uncategorized:  Put files w/o valid EXIF date under "uncategorized/"
  -S, --skip-duplicates:        If target exists, skip it outright (no checksum)
EOF
}

#######################################
# Configuration
#######################################
datetime_format="%Y%m%d_%H%M%S"
extensions=("cr2" "raf" "jpg" "mov" "avi" "png" "wmv" "mp4" "vob")
extensions_raw=("cr2" "raf")

# Flags
recursive=0
dry_run=0
uncategorized=0
skip_duplicates=0

#######################################
# Arg parsing
#######################################
if [ $# -eq 0 ]; then
  help_message
  exit 0
fi

PARSED=$(getopt -n "$0" -o s:o:rhudS --long "source-path:,output-path:,recursive,help,include-uncategorized,dry-run,skip-duplicates" -- "$@")
eval set -- "$PARSED"
while true; do
  case "$1" in
    -s|--source-path)   source_path="$2"; shift 2;;
    -o|--output-path)   output_path="$2"; shift 2;;
    -r|--recursive)     recursive=1; shift;;
    -h|--help)          help_message; exit 0;;
    -u|--include-uncategorized) uncategorized=1; shift;;
    -d|--dry-run)       dry_run=1; shift;;
    -S|--skip-duplicates) skip_duplicates=1; shift;;
    --) shift; break;;
    *) echo "Invalid option: $1" >&2; exit 1;;
  esac
done

# Normalize (strip trailing slash)
source_path="${source_path%/}"
output_path="${output_path%/}"

#######################################
# Sanity checks & setup
#######################################
if [[ ! -d $source_path ]]; then
  log "Error: Source '$source_path' is not a directory."
  exit 1
fi

if [[ ! -d $output_path ]]; then
  msg="Creating output directory: $output_path"
  if (( dry_run )); then
    log "$msg (dry-run)"
  else
    mkdir -p "$output_path" && log "$msg"
  fi
fi

# Load ignore list if present
ignore_file="$source_path/ignore.txt"
ignore_list=()
if [[ -f $ignore_file ]]; then
  while IFS= read -r line; do
    ignore_list+=("$line")
  done < "$ignore_file"
fi

#######################################
# Gather files
#######################################
file_list=()
if (( recursive )); then
  for ext in "${extensions[@]}"; do
    while IFS= read -r -d '' f; do
      file_list+=("$f")
    done < <(find "$source_path" -type f -iname "*.$ext" -print0)
  done
else
  for ext in "${extensions[@]}"; do
    for f in "$source_path"/*.[${ext,,}]; do
      [[ -f $f ]] && file_list+=("$f")
    done
  done
fi

total=${#file_list[@]}
count=0
renamed=0
skipped_exists=0
skipped_nodate=0
skipped_ignored=0

echo "Source: $source_path"
echo "Output: $output_path"
echo "Files found: $total"
log "Starting..."

#######################################
# Main loop
#######################################
for file in "${file_list[@]}"; do
  ((count++))

  # Extract EXIF DateTimeOriginal in our format (or blank)
  datetime=$(exiftool -s3 -d "$datetime_format" -DateTimeOriginal "$file" 2>/dev/null)
  datetime="${datetime//[[:space:]]/}"   # strip whitespace

  # If it doesn’t strictly match 8digits_6digits, treat as “no date”
  if ! [[ $datetime =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
    if (( uncategorized )); then
      rel="${file#$source_path/}"
      target_dir="$output_path/uncategorized/$(dirname "$rel")"
      msg="UNCAT: $file → $target_dir/"
      if (( dry_run )); then
        log "$msg (dry-run)"
      else
        mkdir -p "$target_dir"
        cp -n "$file" "$target_dir"
        log "$msg"
      fi
    else
      log "Skipped (no valid date): $file ($count/$total)"
      ((skipped_nodate++))
    fi
    continue
  fi

  # Skip if in ignore.txt
  if printf '%s\n' "${ignore_list[@]}" | grep -qx "$datetime"; then
    log "Ignored via ignore.txt: $file ($count/$total)"
    ((skipped_ignored++))
    continue
  fi

  # Derive YYYY-MM
  year="${datetime:0:4}"
  month="${datetime:4:2}"
  subdir="$year-$month"

  # Extension subfolder
  ext="${file##*.}"
  ext="${ext,,}"
  target_dir="$output_path/$subdir/$ext"

  if [[ ! -d $target_dir ]]; then
    if (( dry_run )); then
      log "Would mkdir -p $target_dir"
    else
      mkdir -p "$target_dir" && log "Created directory $target_dir"
    fi
  fi

  # Build target filename & path
  new_name="$datetime.$ext"
  target_path="$target_dir/$new_name"

  # Handle duplicates
  if [[ -e $target_path ]]; then
    if (( skip_duplicates )); then
      log "Skipped (exists): $file ($count/$total)"
      ((skipped_exists++))
      continue
    fi
    orig_ck=$(md5sum "$file" | cut -d' ' -f1)
    tgt_ck=$(md5sum "$target_path" | cut -d' ' -f1)
    if [[ $orig_ck == $tgt_ck ]]; then
      log "Skipped (identical): $file ($count/$total)"
      ((skipped_exists++))
      continue
    fi
    suffix="${orig_ck: -8}"
    new_name="${datetime}_${suffix}.${ext}"
    target_path="$target_dir/$new_name"
  fi

  # Copy the file
  msg="$file → $target_path ($count/$total)"
  if (( dry_run )); then
    log "$msg (dry-run)"
  else
    cp -n "$file" "$target_path" && log "$msg" && ((renamed++))
  fi

  # Copy .xmp sidecar if it exists
  if printf '%s\n' "${extensions_raw[@]}" | grep -qx "$ext"; then
    xmp_src="${file%.*}.xmp"
    if [[ -f $xmp_src ]]; then
      xmp_dst="${target_path%.*}.xmp"
      msg="Sidecar: $xmp_src → $xmp_dst"
      if (( dry_run )); then
        log "$msg (dry-run)"
      else
        cp -n "$xmp_src" "$xmp_dst" && log "$msg"
      fi
    fi
  fi

done

#######################################
# Summary & elapsed time
#######################################
end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
h=$(( elapsed / 3600 ))
m=$(( (elapsed % 3600) / 60 ))
s=$(( elapsed % 60 ))

echo "------------------------"
echo "Done."
echo "Renamed:           $renamed"
echo "Skipped (exists):  $skipped_exists"
echo "Skipped (no date): $skipped_nodate"
echo "Skipped (ignored): $skipped_ignored"
echo "Time elapsed:      ${h}h ${m}m ${s}s"
