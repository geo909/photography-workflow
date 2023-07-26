#!/bin/bash

# This Bash script is designed to either move or copy media files (photo or video, anything with exif data)
# from a source directory to a target directory, whilst renaming the files based on their "DateTimeOriginal" 
# metadata.
#
# Renamed files are organized in subdirectories, sorted by their creation year and month. 
# If a media file lacks the "DateTimeOriginal" metadata, the script provides options to either skip this file or to 
# place it into a separate "uncategorized" directory. Additional features include recursive operation on the 
# source directory, dry-run mode for previewing changes without making any modifications.

# Configuration:
datetime_format="%Y%m%d_%H%M%S"
extensions=("cr2" "raf" "jpg" "mov" "avi" "png" "wmv" "mp4" "vob")
extensions_raw=("cr2" "raf")
subdir_format="%Y-%m"

# Create arrays with files
file_list=()

recursive=0
dry_run=0
uncategorized=0
skip_duplicates=0

help_message() {
  echo -e "Usage: $0 --source-path source_path --output-path output_path [--recursive] [--dry-run] [--verbose] [--include-uncategorized] [--skip-duplicates]"
  echo -e ""
  echo -e "  -s, --source-path: Sets the path to the source directory."
  echo -e "  -o, --output-path: Sets the path to the target directory."
  echo -e "  -r, --recursive: Enables the script to operate recursively on the source directory."
  echo -e "  -d, --dry-run: Executes a dry-run where the script shows changes that would be made without actually performing them."
  echo -e "  -u, --include-uncategorized: Places any files lacking 'DateTimeOriginal' metadata in an 'uncategorized' directory instead of skipping them."
  echo -e "  -S, --skip-duplicates: If a file of the same name exists in the target, this option will skip the move operation. By default, files are compared by their hashes and if different, a hash is appended to the new file's basename."
}

start_time=$(date +%s)

# Helper function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

# Check if any arguments were passed to the script
if [ $# -eq 0 ]; then
  help_message
  exit 0
fi

# Parse command-line options
PARSED_ARGUMENTS=$(getopt -n "$0" -o s:o:rhRduO --long "source-path:,output-path:,recursive,help,include-uncategorized,dry-run,skip-duplicates" -- "$@")

eval set -- "$PARSED_ARGUMENTS"

while true; do
  case "$1" in
    -s|--source-path) source_path="$2"; shift 2;;
    -o|--output-path) output_path="$2"; shift 2;;
    -r|--recursive) recursive=1; shift;;
    -h|--help) help_message; exit 0;;
    -u|--include-uncategorized) uncategorized=1; shift;;
    -d|--dry-run) dry_run=1; shift;;
    -S|--skip-duplicates) skip_duplicates=1; shift;;
    --) shift; break;;
    *) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

# Check if source path is a directory
if [[ ! -d $source_path ]]; then
  log "Error: Source path does not exist or is not a directory"
  exit 1
fi

# Check if output path is a directory, and if not, try to create it
if [[ ! -d $output_path ]]; then
  message="Created directory $output_path"
  if [[ $dry_run -eq 0 ]]; then
    mkdir -p "$output_path"
    log $message
    if [[ $? -ne 0 ]]; then
      log "Error: Failed to create output directory"
      exit 1
    fi
  else
    log "$message (dryrun)"
  fi
fi

# Create array with ignored prefixes
ignore_file="$source_path/ignore.txt"
ignore_list=()
if [[ -f $ignore_file ]]; then
  while IFS= read -r line; do
    ignore_list+=("$line")
  done < "$ignore_file"
fi

# Create arrays with files
file_list=()

# Populate file_list with files
if [[ $recursive -eq 1 ]]; then
  for ext in "${extensions[@]}"; do
    while IFS=  read -r -d $'\0'; do
      file_list+=("$REPLY")
    done < <(find "$source_path" -iname "*.$ext" -print0)
  done
else
  for ext in "${extensions[@]}"; do
    while IFS= read -r; do
      file_list+=("$source_path/$REPLY")
    done < <(ls "$source_path" | grep -i "\.$ext$")
  done
fi

total_files=${#file_list[@]}
count=0
renamed=0
skipped_target_exists=0
skipped_no_datetime=0
skipped_ignore_txt=0

# Output start message
echo "Source directory: $source_path"
echo "Output directory: $output_path"
echo "Total number of files to process: $total_files"
echo "------------------------"
log "Starting operation..."


# Iterate over each file in the list
for file in "${file_list[@]}"; do
  ((count++))

  # Parse its original Datetime
  datetime=$(exiftool -s3 -d "$datetime_format" -DateTimeOriginal "$file")

  # Skip if file is in ignore list and datetime is not empty
  if [[ -n "$datetime" ]] && [[ " ${ignore_list[@]} " =~ " ${datetime} " ]]; then
    log "Ignored $file due to entry in ignore.txt ($count/$total_files)"
    ((skipped_ignore_txt++))
    continue
  fi

  # Handle files with empty datetimes: if -u is used, it will move them 
  # in an "uncategorized" folder in the output, using the same relative
  # path as in the source
  if [[ "$datetime" == "" ]]; then
    if [[ $uncategorized -eq 1 ]]; then
      relative_dir="${file%/*}"
      relative_path="${relative_dir#$source_path/}"
      output_dir="$output_path/uncategorized/$relative_path"

      if [[ ! -d "$output_dir" && $dry_run -eq 0 ]]; then
        mkdir -p "$output_dir"
      fi
  
      message="$file ---> $output_dir ($count/$total_files)"
      if [[ $dry_run -eq 0 ]]; then
        cp -n "$file" "$output_dir"
        log "$message"
      else
        log "$message (dryrun)"
      fi
    else
      # No -u flag is used; skip
      log "Skipped $file due to lack of DateTimeOriginal ($count/$total_files)" 
      ((skipped_no_datetime++))
    fi
    continue
  fi

  # Now datetime is not empty; we format it according to $subdir_format
  # and use this as our output subdirectory name
  output_subdir=$(exiftool -s3 -d "$subdir_format" -DateTimeOriginal "$file")

  # Check if output subdirectory exists, create it if not
  if [[ ! -d "$output_path/$output_subdir" && $dry_run -eq 0 ]]; then
    mkdir -p "$output_path/$output_subdir"
  fi

  ext=${file##*.}
  new_name="${datetime,,}.$(echo $ext | awk '{print tolower($0)}')"

  # Check if target file already exists
  target_path="$output_path/$output_subdir/$new_name"

  if [[ -e "$target_path" ]]; then
    if [[ $skip_duplicates -eq 0 ]]; then 
      # if skip_duplicates is set to 0 (the default behaviour), use a checksum suffix to differentiate if the file is different
      original_checksum=$(md5sum "$file" | cut -d " " -f 1)
      target_checksum=$(md5sum "$target_path" | cut -d " " -f 1)
  
      # Check if checksums match
      if [[ "$original_checksum" == "$target_checksum" ]]; then
        log "Skipped $file due to identical file already exists ($count/$total_files)"
        ((skipped_target_exists++))
        continue
      else
        # Use the last 8 characters of the md5 checksum as a suffix for the new filename
        suffix="${original_checksum: -8}"
        new_name="${datetime,,}_$suffix.$(echo $ext | awk '{print tolower($0)}')"
        target_path="$output_path/$output_subdir/$new_name"
      fi
    else # skip_duplicates is set to 1
      log "Skipped $file due to existing target file ($count/$total_files)"
      ((skipped_target_exists++))
      continue
    fi
  fi

  # Now let's do the copying
  message="$file ---> $target_path ($count/$total_files)"
  if [[ $dry_run -eq 0 ]]; then
    cp -n "$file" "$target_path"
    log "$message"
    ((renamed++))
  else
    log "$message (dryrun)"
  fi

  # Check if there exists a .xmp file with the same base name for files with extensions in extensions_raw
  if [[ " ${extensions_raw[@]} " =~ "${ext,,}" ]]; then
    base_name=${file%.*}
    xmp_file="${base_name}.xmp"
    if [[ -f $xmp_file ]]; then
      xmp_target_path="${target_path%.*}.xmp"
      message="$xmp_file ---> $xmp_target_path"
      # Copy the .xmp file to the same target location
      if [[ $dry_run -eq 0 ]]; then
        cp -n "$xmp_file" "$xmp_target_path"
        log "$message"
      else
        log "$message (dryrun)"
      fi
    fi
  fi

done

# Calculate time elapsed
end_time=$(date +%s)
elapsed_seconds=$(( end_time - start_time ))
hours=$(( elapsed_seconds / 3600 ))
minutes=$(( (elapsed_seconds % 3600) / 60 ))
seconds=$(( elapsed_seconds % 60 ))

echo "------------------------"
echo "Finished processing."
echo "Total files renamed: $renamed"
echo "Total files skipped due to existing target: $skipped_target_exists"
echo "Total files skipped due to lack of DateTimeOriginal: $skipped_no_datetime"
echo "Total files skipped due to their datetime being in ignore.txt: $skipped_ignore_txt"
echo "Time elapsed: $hours hour(s) $minutes minute(s) $seconds second(s)"
