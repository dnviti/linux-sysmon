#!/bin/bash
# Script to monitor disks with uniform output and selectable output format
# All sizes are computed in KiB and then converted to the most viable unit.

##########################
# Option Parsing
##########################
OUTPUT_FORMAT="text"
while getopts ":o:" opt; do
    case ${opt} in
        o)
            if [[ "$OPTARG" == "json" || "$OPTARG" == "yaml" ]]; then
                OUTPUT_FORMAT=$OPTARG
            else
                echo "Invalid output format: $OPTARG. Use 'json' or 'yaml'."
                exit 1
            fi
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

##########################
# Common Functions & Setup
##########################
if [ -t 1 ] && [ "$OUTPUT_FORMAT" = "text" ]; then
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

# Function to determine the color based on a value and thresholds.
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
    local bar_length=10
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

# Function to convert a size in KiB to a value and unit.
# If less than 1024 KiB, returns the value in KiB.
# If less than 1 GiB, returns the value in MiB.
# Otherwise, returns the value in GiB.
convert_hr() {
    local kib=$1
    if [ "$kib" -lt 1024 ]; then
        echo "$kib KiB"
    elif [ "$kib" -lt 1048576 ]; then
        local value
        value=$(awk "BEGIN {printf \"%.2f\", $kib/1024}")
        echo "$value MiB"
    else
        local value
        value=$(awk "BEGIN {printf \"%.2f\", $kib/1048576}")
        echo "$value GiB"
    fi
}

##########################
# Disk Monitoring Branch
##########################
# Exclude tmpfs and devtmpfs to focus on physical filesystems.
disk_info=$(df -P -x tmpfs -x devtmpfs)
disk_found=false

# Variables for structured output.
disk_count=0
json_array=""
yaml_output="disks:"$'\n'

while IFS= read -r line; do
    # Skip header.
    if [[ "$line" == Filesystem* ]]; then
        continue
    fi

    disk_found=true
    # df -P output: Filesystem Total Used Available Capacity Mounted_on
    read -r filesystem total used available capacity mountpoint <<< "$line"
    
    # Calculate usage percentage.
    usage_percent=$(( used * 100 / total ))
    
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        # In text mode, combine the conversion into a single human-readable string.
        used_hr=$(convert_hr "$used")
        total_hr=$(convert_hr "$total")
        
        usage_color=$(get_color "$usage_percent" 50 80)
        usage_bar=$(progress_bar "$usage_percent")
        
        echo "Disk: ${filesystem} (${mountpoint})"
        printf "  %-15s %s %s\n" "Usage:" "${usage_color}${usage_bar}${NC}" "(${usage_percent}%)"
        printf "  %-15s %s\n" "Used/Total:" "(${used_hr} / ${total_hr})"
        echo ""
    elif [ "$OUTPUT_FORMAT" = "json" ]; then
        # For JSON, split the conversion into numeric value and unit.
        read -r used_value used_unit <<< $(convert_hr "$used")
        read -r total_value total_unit <<< $(convert_hr "$total")
        
        disk_count=$((disk_count+1))
        fs_escaped=$(echo "$filesystem" | sed 's/"/\\"/g')
        mp_escaped=$(echo "$mountpoint" | sed 's/"/\\"/g')
        json_disk=$(printf '{"filesystem": "%s", "mountpoint": "%s", "usage_percent": %d, "used": {"value": %s, "unit": "%s"}, "total": {"value": %s, "unit": "%s"}}' \
            "$fs_escaped" "$mp_escaped" "$usage_percent" "$used_value" "$used_unit" "$total_value" "$total_unit")
        if [ $disk_count -gt 1 ]; then
            json_array="${json_array},\n${json_disk}"
        else
            json_array="${json_disk}"
        fi
    elif [ "$OUTPUT_FORMAT" = "yaml" ]; then
        read -r used_value used_unit <<< $(convert_hr "$used")
        read -r total_value total_unit <<< $(convert_hr "$total")
        
        yaml_output+="  - filesystem: \"$filesystem\"\n"
        yaml_output+="    mountpoint: \"$mountpoint\"\n"
        yaml_output+="    usage_percent: $usage_percent\n"
        yaml_output+="    used:\n"
        yaml_output+="      value: $used_value\n"
        yaml_output+="      unit: $used_unit\n"
        yaml_output+="    total:\n"
        yaml_output+="      value: $total_value\n"
        yaml_output+="      unit: $total_unit\n"
    fi
done <<< "$disk_info"

if [ "$disk_found" = false ]; then
    echo "Error: No disks found."
    exit 1
fi

##########################
# Output in Desired Format
##########################
if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo "{"
    echo "  \"disks\": ["
    echo -e "$json_array"
    echo "  ]"
    echo "}"
    exit 0
elif [ "$OUTPUT_FORMAT" = "yaml" ]; then
    echo -e "$yaml_output"
    exit 0
fi
