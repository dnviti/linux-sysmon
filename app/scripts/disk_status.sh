#!/bin/bash
# Script to monitor disks with uniform output

##########################
# Common Functions
##########################
# If stdout is a terminal, use tput for colors; otherwise, disable colors.
if [ -t 1 ]; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    NC=$(tput sgr0)
else
    GREEN=""
    YELLOW=""
    RED=""
    NC=""
fi

# Function to determine the color based on a value and specific thresholds.
get_color() {
    local value=$1
    local threshold_yellow=$2
    local threshold_red=$3

    if [ "$value" = "N/A" ]; then
        echo ""
    elif [ "$value" -ge "$threshold_red" ]; then
        echo "$RED"
    elif [ "$value" -ge "$threshold_yellow" ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# Function to draw a progress bar based on a percentage.
progress_bar() {
    local percent=$1
    local bar_length=10   # length of the bar
    # If the value is not numeric (e.g. "N/A"), return an empty bar.
    if ! [[ "$percent" =~ ^[0-9]+$ ]]; then
        printf "%0.s░" $(seq 1 $bar_length)
        return
    fi
    local filled_length=$(( percent * bar_length / 100 ))
    local empty_length=$(( bar_length - filled_length ))
    local filled=$(printf "%0.s█" $(seq 1 $filled_length))
    local empty=$(printf "%0.s░" $(seq 1 $empty_length))
    echo "${filled}${empty}"
}

##########################
# Disk Monitoring Branch
##########################
# Exclude tmpfs and devtmpfs to focus on physical filesystems.
disk_info=$(df -P -x tmpfs -x devtmpfs)
disk_found=false

# Process each line from df output.
while IFS= read -r line; do
    # Skip the header line.
    if [[ "$line" == Filesystem* ]]; then
        continue
    fi

    disk_found=true
    # df -P output format: Filesystem Total Used Available Capacity Mounted_on
    # Example: /dev/sda1 20511388 15328172 3679676 81% /
    read -r filesystem total used available capacity mountpoint <<< "$line"
    
    # Calculate usage percentage based on used and total (both in 1K blocks).
    usage_percent=$(( used * 100 / total ))
    
    # Convert used and total from KiB to GiB (approximate conversion).
    used_gib=$(( used / 1048576 ))
    total_gib=$(( total / 1048576 ))
    
    # Determine color based on usage thresholds (50 and 80%).
    usage_color=$(get_color "$usage_percent" 50 80)
    
    # Build a progress bar for usage.
    usage_bar=$(progress_bar "$usage_percent")
    
    # Print the report for the disk.
    echo "Disk: ${filesystem} (${mountpoint})"
    printf "  %-15s %s %s\n" "Usage:" "${usage_color}${usage_bar}${NC}" "(${usage_percent}%)"
    printf "  %-15s %s\n" "Used/Total:" "(${used_gib}/${total_gib} GiB)"
    echo ""
done <<< "$disk_info"

if [ "$disk_found" = false ]; then
    echo "Error: No disks found."
    exit 1
fi
