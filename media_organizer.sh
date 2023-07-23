#!/bin/bash

# This script organizes image files based on their DateTimeOriginal metadata.
#
# Configuration:
# datetime_format: Format for new filenames (strftime format). Example: "%Y%m%d_%H%M%S" for "20230723_174530"
# extensions: Array of file extensions to process. Example: ("RAF" "JPG" "xmp")
# subdir_format: Format for subdirectories in output path (strftime format). Example: "%Y-%m" for "2023-07"

datetime_format="%Y%m%d_%H%M%S"
extensions=("cr2" "raf" "jpg" "xmp" "mov" "avi" "png" "wmv" "mp4" "vob")
subdir_format="%Y-%m"

#
# Usage:
# ./script.sh --source-path SRC --output-path OUT
#
# Options:
# --recursive (-r): Process directories recursively.
# --keep-originals (-k): Keep original files (copies instead of moving).
# --dry-run (-d): Do not perform any changes, only print what would be done.
#
# Short forms: -s for --source-path, -o for --output-path
#
# Example:
# ./script.sh -s SRC -o OUT -r -k -d
#
# The script logs operations, totals, and reasons for skipping files.
#
# ignore.txt: A file in the same directory as the script, listing dates to be ignored (one per line).

# Variables for command-line options
recursive=0
keep_originals=0
dry_run=0
help_message="Usage: $0 --source-path source_path --output-path output_path [--recursive] [--keep-originals] [--dry-run]"

start_time=$(date +%s)

# Check if any arguments were passed to the script
if [ $# -eq 0 ]; then
  echo $help_message
  exit 0
fi

# Parse command-line options
PARSED_ARGUMENTS=$(getopt -n "$0" -o s:o:rhkd --long "source-path:,output-path:,recursive,help,keep-originals,dry-run" -- "$@")

eval set -- "$PARSED_ARGUMENTS"

while true; do
  case "$1" in
    -s|--source-path) source_path="$2"; shift 2;;
    -o|--output-path) output_path="$2"; shift 2;;
    -r|--recursive) recursive=1; shift;;
    -h|--help) echo $help_message; exit 0;;
    -k|--keep-originals) keep_originals=1; shift;;
    -d|--dry-run) dry_run=1; shift;;
    --) shift; break;;
    *) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

# Check if source path is a directory
if [[ ! -d $source_path ]]; then
  echo "Error: Source path does not exist or is not a directory"
  exit 1
fi

# Check if output path is a directory
if [[ ! -d $output_path ]]; then
  if [[ $dry_run -eq 0 ]]; then
    mkdir -p "$output_path"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to create output directory"
      exit 1
    fi
  else
    echo "Would create directory: $output_path"
  fi
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

# Output start message
echo "Starting operation..."
echo "Source directory: $source_path"
echo "Output directory: $output_path"
echo "Total number of files to process: $total_files"
echo "------------------------"

# Iterate over each file in the list
for file in "${file_list[@]}"; do
  datetime=$(exiftool -s3 -d "$datetime_format" -DateTimeOriginal "$file")
  if [[ "$datetime" == "" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $file due to lack of DateTimeOriginal ($(($count+1))/$total_files)" 
    echo "$file" >> skipped_no_datetime.log
    ((skipped_no_datetime++))
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

  # Use cp instead of mv when keep_originals option is used
  if [[ $keep_originals -eq 1 ]]; then
    if [[ $dry_run -eq 0 ]]; then
      cp_output=$(cp -vn "$file" "$output_path/$output_subdir/$new_name")
      # Check if cp actually copied the file
      if [[ -z $cp_output ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $file due to existing target ($(($count+1))/$total_files)"
        ((skipped_target_exists++))
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S'): $cp_output ($(($count+1))/$total_files)"
        ((renamed++))
      fi
    else
      echo "Would copy $file to $output_path/$output_subdir/$new_name"
    fi
  else
    if [[ $dry_run -eq 0 ]]; then
      mv_output=$(mv -vn "$file" "$output_path/$output_subdir/$new_name")
      # Check if mv actually renamed the file
      if [[ -z $mv_output ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $file due to existing target ($(($count+1))/$total_files)"
        ((skipped_target_exists++))
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S'): $mv_output ($(($count+1))/$total_files)"
        ((renamed++))
      fi
    else
      echo "Would move $file to $output_path/$output_subdir/$new_name"
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

# Output end message
echo "------------------------"
echo "Finished processing."
echo "Total files renamed: $renamed"
echo "Total files skipped due to existing target: $skipped_target_exists"
echo "Total files skipped due to lack of DateTimeOriginal: $skipped_no_datetime"
echo "Time elapsed: $hours hour(s) $minutes minute(s) $seconds second(s)"
