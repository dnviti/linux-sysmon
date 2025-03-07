#!/bin/bash
# Script to monitor CPU and RAM with uniform output

# Parse command line options for output format.
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

############################
# Common Functions & Setup #
############################

# If stdout is a terminal and we're in text mode, use tput for colors; otherwise, disable colors.
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
    else
        local value_int=${value%%.*}
        if [ "$value_int" -ge "$threshold_red" ]; then
            echo "$RED"
        elif [ "$value_int" -ge "$threshold_yellow" ]; then
            echo "$YELLOW"
        else
            echo "$GREEN"
        fi
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

####################
# CPU Monitoring   #
####################

# Capture CPU model if available.
if command -v lscpu &> /dev/null; then
    cpu_model=$(lscpu | grep "Model name:" | cut -d ':' -f2 | xargs)
else
    cpu_model=""
fi

# Function to calculate overall CPU usage percentage using /proc/stat.
calculate_cpu_usage() {
    read -r cpu user nice system idle iowait irq softirq steal extra < /proc/stat
    total1=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle1=$idle
    sleep 0.2
    read -r cpu user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 extra < /proc/stat
    total2=$(( user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2 ))
    idle2=$idle2
    total_diff=$(( total2 - total1 ))
    idle_diff=$(( idle2 - idle1 ))
    usage=$(( 100 * (total_diff - idle_diff) / total_diff ))
    echo "$usage"
}

cpu_usage=$(calculate_cpu_usage)

# Obtain CPU temperature via 'sensors' if available.
if command -v sensors &> /dev/null; then
    cpu_temp=$(sensors | awk '/Package id 0:/ {print $4; exit}' | tr -d '+°C')
    if [ -z "$cpu_temp" ]; then
        cpu_temp="N/A"
    fi
else
    cpu_temp="N/A"
fi

# For text output, get colors and progress bar.
if [ "$OUTPUT_FORMAT" = "text" ]; then
    cpu_usage_color=$(get_color "$cpu_usage" 50 80)
    cpu_usage_bar=$(progress_bar "$cpu_usage")
    if [ "$cpu_temp" != "N/A" ]; then
        cpu_temp_color=$(get_color "$cpu_temp" 60 80)
    fi
fi

####################
# RAM Monitoring   #
####################

# Obtain memory info (in MiB) using 'free'.
read total used free shared buff available < <(free -m | awk '/^Mem:/{print $2, $3, $4, $5, $6, $7}')

# Calculate effective used memory as (total - available).
effective_used=$(( total - available ))
if [ "$total" -gt 0 ]; then
    ram_usage_percent=$(( effective_used * 100 / total ))
else
    ram_usage_percent=0
fi

if [ "$OUTPUT_FORMAT" = "text" ]; then
    ram_usage_color=$(get_color "$ram_usage_percent" 50 80)
    ram_usage_bar=$(progress_bar "$ram_usage_percent")
fi

# Convert MiB to GiB (approximate conversion).
used_gib=$(( effective_used / 1024 ))
total_gib=$(( total / 1024 ))

############################
# Output in Desired Format #
############################

if [ "$OUTPUT_FORMAT" = "json" ]; then
    # Escape quotes in cpu_model, if any.
    if [ -n "$cpu_model" ]; then
        safe_cpu_model=$(echo "$cpu_model" | sed 's/"/\\"/g')
    else
        safe_cpu_model=""
    fi
    # For CPU temperature: output null if not available.
    if [ "$cpu_temp" = "N/A" ]; then
        json_cpu_temp=null
    else
        json_cpu_temp=$cpu_temp
    fi

    cat <<EOF
{
  "cpu": {
    "model": "$( [ -n "$safe_cpu_model" ] && echo "$safe_cpu_model" || echo null )",
    "utilization": $cpu_usage,
    "temperature": $json_cpu_temp
  },
  "ram": {
    "utilization": $ram_usage_percent,
    "used_gib": $used_gib,
    "total_gib": $total_gib
  }
}
EOF
    exit 0
elif [ "$OUTPUT_FORMAT" = "yaml" ]; then
    echo "cpu:"
    if [ -n "$cpu_model" ]; then
        echo "  model: \"$cpu_model\""
    else
        echo "  model: null"
    fi
    echo "  utilization: $cpu_usage"
    echo "  temperature: $( [ "$cpu_temp" = "N/A" ] && echo "null" || echo "$cpu_temp" )"
    echo "ram:"
    echo "  utilization: $ram_usage_percent"
    echo "  used_gib: $used_gib"
    echo "  total_gib: $total_gib"
    exit 0
fi

####################
# Human-readable   #
# Textual Output   #
####################

echo "CPU:"
if [ -n "$cpu_model" ]; then
    printf "  %-15s %s\n" "Model:" "$cpu_model"
fi
printf "  %-15s %s %s\n" "Utilization:" "${cpu_usage_color}${cpu_usage_bar}${NC}" "(${cpu_usage}%)"
if [ "$cpu_temp" = "N/A" ]; then
    printf "  %-15s %s\n" "Temperature:" "N/A"
else
    printf "  %-15s %s\n" "Temperature:" "${cpu_temp_color}${cpu_temp}°C${NC}"
fi
echo ""

echo "RAM:"
printf "  %-15s %s %s\n" "Utilization:" "${ram_usage_color}${ram_usage_bar}${NC}" "(${ram_usage_percent}%)"
printf "  %-15s %s\n" "Used Memory:" "${ram_usage_color}${used_gib}/${total_gib} GiB${NC}"
echo ""
