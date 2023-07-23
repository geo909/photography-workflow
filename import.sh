#!/bin/bash

# This script organizes image files based on their DateTimeOriginal metadata.
# It was created with the help of chatgpt
# https://chat.openai.com/share/fd1bfc92-608b-4ae5-9c25-5398b2088b05
#
# Configuration:
# datetime_format: Format for new filenames (strftime format). Example: "%Y%m%d_%H%M%S" for "20230723_174530"
# extensions: Array of file extensions to process. Example: ("RAF" "JPG" "xmp")
# subdir_format: Format for subdirectories in output path (strftime format). Example: "%Y-%m" for "2023-07"

datetime_format="%Y%m%d_%H%M%S"
extensions=("CR2" "RAF" "JPG" "xmp")
subdir_format="%Y-%m"

#
# Usage:
# ./this_script.sh --source-path SRC --output-path OUT
#
# Options:
# --recursive (-r): Process directories recursively.
# --keep-originals (-k): Keep original files (copies instead of moving).
#
# Short forms: -s for --source-path, -o for --output-path
#
# Example:
# ./this_script.sh -s SRC -o OUT -r -k
#
# The script logs operations, totals, and reasons for skipping files.
#
# ignore.txt: A file in the same directory as the script, listing dates to be ignored (one per line).

# Variables for command-line options
recursive=0
keep_originals=0

# Parse command-line options
PARSED_ARGUMENTS=$(getopt -n "$0" -o s:o:rhk --long "source-path:,output-path:,recursive,help,keep-originals" -- "$@")

eval set -- "$PARSED_ARGUMENTS"

while true; do
  case "$1" in
    -s|--source-path) source_path="$2"; shift 2;;
    -o|--output-path) output_path="$2"; shift 2;;
    -r|--recursive) recursive=1; shift;;
    -h|--help) echo "Usage: $0 --source-path source_path --output-path output_path [--recursive] [--keep-originals]"; exit 0;;
    -k|--keep-originals) keep_originals=1; shift;;
    --) shift; break;;
    *) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

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
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $(basename $file) due to lack of DateTimeOriginal ($(($count+1))/$total_files)"
    ((skipped_no_datetime++))
    ((count++))
    continue
  fi
  output_subdir=$(exiftool -s3 -d "$subdir_format" -DateTimeOriginal "$file")
  ext=${file##*.}
  new_name="${datetime,,}.$(echo $ext | awk '{print tolower($0)}')"

  mkdir -p "$output_path/$output_subdir"

  # Use cp instead of mv when keep_originals option is used
  if [[ $keep_originals -eq 1 ]]; then
    cp_output=$(cp -vn "$file" "$output_path/$output_subdir/$new_name")
    # Check if cp actually copied the file
    if [[ -z $cp_output ]]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $(basename $file) due to existing target ($(($count+1))/$total_files)"
      ((skipped_target_exists++))
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S'): $cp_output ($(($count+1))/$total_files)"
      ((renamed++))
    fi
  else
    mv_output=$(mv -vn "$file" "$output_path/$output_subdir/$new_name")
    # Check if mv actually renamed the file
    if [[ -z $mv_output ]]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S'): Skipped $(basename $file) due to existing target ($(($count+1))/$total_files)"
      ((skipped_target_exists++))
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S'): $mv_output ($(($count+1))/$total_files)"
      ((renamed++))
    fi
  fi
  ((count++))
done

# Output end message
echo "------------------------"
echo "Finished processing."
echo "Total files renamed: $renamed"
echo "Total files skipped due to existing target: $skipped_target_exists"
echo "Total files skipped due to lack of DateTimeOriginal: $skipped_no_datetime"
