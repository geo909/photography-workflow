#!/bin/bash

# This Bash script is designed to either move or copy media files (photo or video, anything with exif data)
# from a source directory to a target directory, whilst renaming the files based on their "DateTimeOriginal" 
# metadata.
#
# Renamed files are organized in subdirectories, sorted by their creation year and month. 
# If a media file lacks the "DateTimeOriginal" metadata, the script provides options to either skip this file or to 
# place it into a separate "uncategorized" directory. Additional features include recursive operation on the 
# source directory, dry-run mode for previewing changes without making any modifications, and an option 
# to delete original files after copying.

# Options:
#   -s, --source-path:      Sets the path to the source directory.
#   -o, --output-path:      Sets the path to the target directory.
#   -r, --recursive:        Enables the script to operate recursively on the source directory.
#   -R, --remove-originals: Instructs the script to move files instead of copying them, effectively deleting the original files.
#   -d, --dry-run:          Executes a dry-run where the script shows changes that would be made without actually performing them.
#   -u, --uncategorized:    Instructs the script to place any files lacking 'DateTimeOriginal' metadata in an 'uncategorized' directory instead of skipping them.

# Configuration:
datetime_format="%Y%m%d_%H%M%S"
extensions=("cr2" "raf" "jpg" "xmp" "mov" "avi" "png" "wmv" "mp4" "vob")
subdir_format="%Y-%m"

recursive=0
remove_originals=0
dry_run=0
uncategorized=0

help_message="Usage: $0 --source-path source_path --output-path output_path [--recursive] [--remove-originals] [--dry-run] [--verbose] [--uncategorized]"

start_time=$(date +%s)

# Helper function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

# Check if any arguments were passed to the script
if [ $# -eq 0 ]; then
  echo $help_message
  exit 0
fi

# Parse command-line options
PARSED_ARGUMENTS=$(getopt -n "$0" -o s:o:rhRdu --long "source-path:,output-path:,recursive,help,remove-originals,dry-run" -- "$@")

eval set -- "$PARSED_ARGUMENTS"

while true; do
  case "$1" in
    -s|--source-path) source_path="$2"; shift 2;;
    -o|--output-path) output_path="$2"; shift 2;;
    -r|--recursive) recursive=1; shift;;
    -h|--help) echo $help_message; exit 0;;
    -u|--uncategorized) uncategorized=1; shift;;
    -R|--remove-originals)
        echo "You have opted to remove original files. Are you sure? (y/n)"
        read confirmation
        if [[ $confirmation == "y" || $confirmation == "Y" ]]; then
            remove_originals=1 
        else
            echo "Cancelling operation.."
            exit
        fi
        shift;;
    -d|--dry-run) dry_run=1; shift;;
    --) shift; break;;
    *) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

# Check if source path is a directory
if [[ ! -d $source_path ]]; then
  log "Error: Source path does not exist or is not a directory"
  exit 1
fi

# Check if output path is a directory
if [[ ! -d $output_path ]]; then
  if [[ $dry_run -eq 0 ]]; then
    mkdir -p "$output_path"
    if [[ $? -ne 0 ]]; then
      log "Error: Failed to create output directory"
      exit 1
    fi
  else
    echo "Would create directory: $output_path"
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
echo "Starting operation..."
echo "Source directory: $source_path"
echo "Output directory: $output_path"
echo "Total number of files to process: $total_files"
echo "------------------------"

# Iterate over each file in the list
for file in "${file_list[@]}"; do
  datetime=$(exiftool -s3 -d "$datetime_format" -DateTimeOriginal "$file")

  # Skip if file is in ignore list
  if [[ " ${ignore_list[@]} " =~ " ${datetime} " ]]; then
    log "Ignored $file due to entry in ignore.txt"
    ((skipped_ignore_txt++))
    continue
  fi


  if [[ "$datetime" == "" ]]; then
    if [[ $uncategorized -eq 1 ]]; then
      relative_path="${file#$source_path/}"
      output_dir="$output_path/uncategorized/${relative_path%/*}"
      
      if [[ ! -d "$output_dir" && $dry_run -eq 0 ]]; then
        mkdir -p "$output_dir"
      fi

      if [[ $dry_run -eq 0 ]]; then
        cp -n "$file" "$output_dir"

      else
        echo "Would copy $file to $output_dir"
      fi
    else
      log "Skipped $file due to lack of DateTimeOriginal" 
      ((skipped_no_datetime++))
    fi
    ((count++))
    continue
  fi

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
    log "Skipped $file due to existing target file"
    ((skipped_target_exists++))
    continue
  fi

  # Use mv instead of cp when remove_originals option is used
  if [[ $remove_originals -eq 0 ]]; then
    if [[ $dry_run -eq 0 ]]; then
      cp "$file" "$target_path"
      log "Copied $file to $target_path"
      ((renamed++))
    else
      echo "Would copy $file to $target_path"
    fi
  else
    if [[ $dry_run -eq 0 ]]; then
      mv "$file" "$target_path"
      log "Moved $file to $target_path"
      ((renamed++))
    else
      echo "Would move $file to $target_path"
    fi
  fi
  ((count++))
done

# Calculate time elapsed
end_time=$(date +%s)
elapsed_seconds=$(( end_time - start_time ))
hours=$(( elapsed_seconds / 3600 ))
minutes=$(( (elapsed_seconds % 3600) / 60 ))
seconds=$(( elapsed_seconds % 60 ))

log "------------------------"
log "Finished processing."
log "Total files renamed: $renamed"
log "Total files skipped due to existing target: $skipped_target_exists"
log "Total files skipped due to lack of DateTimeOriginal: $skipped_no_datetime"
log "Total files skipped due to their datetime being in ignore.txt: $skipped_ignore_txt"
log "Time elapsed: $hours hour(s) $minutes minute(s) $seconds second(s)"
