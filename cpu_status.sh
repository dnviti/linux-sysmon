#!/bin/bash
# Script to monitor CPU and RAM with uniform output

############################
# Common Functions & Setup #
############################

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
    else
        # Remove decimal portion if exists (e.g. "33.0" becomes "33")
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

####################
# CPU Monitoring   #
####################

echo "CPU:"

# Optionally, show the CPU model if lscpu is available.
if command -v lscpu &> /dev/null; then
    cpu_model=$(lscpu | grep "Model name:" | cut -d ':' -f2 | xargs)
    echo "  Model: ${cpu_model}"
fi

# Function to calculate the overall CPU usage percentage by sampling /proc/stat.
calculate_cpu_usage() {
    # First sample (read extra token(s) to avoid issues with additional fields)
    read -r cpu user nice system idle iowait irq softirq steal extra < /proc/stat
    total1=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle1=$idle
    sleep 0.2
    # Second sample
    read -r cpu user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 extra < /proc/stat
    total2=$(( user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2 ))
    idle2=$idle2
    total_diff=$(( total2 - total1 ))
    idle_diff=$(( idle2 - idle1 ))
    usage=$(( 100 * (total_diff - idle_diff) / total_diff ))
    echo "$usage"
}

cpu_usage=$(calculate_cpu_usage)

# Attempt to obtain CPU temperature via the 'sensors' command if available.
if command -v sensors &> /dev/null; then
    # Look for a reading such as "Package id 0:"; adjust the grep pattern if needed.
    cpu_temp=$(sensors | awk '/Package id 0:/ {print $4; exit}' | tr -d '+°C')
    if [ -z "$cpu_temp" ]; then
        cpu_temp="N/A"
    fi
else
    cpu_temp="N/A"
fi

# Determine colors and build progress bars.
cpu_usage_color=$(get_color "$cpu_usage" 50 80)
cpu_usage_bar=$(progress_bar "$cpu_usage")
if [ "$cpu_temp" != "N/A" ]; then
    cpu_temp_color=$(get_color "$cpu_temp" 60 80)
fi

# Print the CPU report.
printf "  %-15s %s %s\n" "Utilization:" "${cpu_usage_color}${cpu_usage_bar}${NC}" "(${cpu_usage}%)"
if [ "$cpu_temp" = "N/A" ]; then
    printf "  %-15s %s\n" "Temperature:" "N/A"
else
    printf "  %-15s %s\n" "Temperature:" "${cpu_temp_color}${cpu_temp}°C${NC}"
fi
echo ""

####################
# RAM Monitoring   #
####################

echo "RAM:"
# Use 'free' to obtain memory info (in MiB).
# The 'free' output line typically looks like:
# Mem: total used free shared buff/cache available
read total used free shared buff available < <(free -m | awk '/^Mem:/{print $2, $3, $4, $5, $6, $7}')

# Calculate effective used memory as (total - available).
effective_used=$(( total - available ))
if [ "$total" -gt 0 ]; then
    ram_usage_percent=$(( effective_used * 100 / total ))
else
    ram_usage_percent=0
fi

# Determine color and progress bar for RAM utilization.
ram_usage_color=$(get_color "$ram_usage_percent" 50 80)
ram_usage_bar=$(progress_bar "$ram_usage_percent")

# Convert MiB to GiB (approximate conversion).
used_gib=$(( effective_used / 1024 ))
total_gib=$(( total / 1024 ))

# Print the RAM report.
printf "  %-15s %s %s\n" "Utilization:" "${ram_usage_color}${ram_usage_bar}${NC}" "(${ram_usage_percent}%)"
printf "  %-15s %s\n" "Used Memory:" "${ram_usage_color}${used_gib}/${total_gib} GiB${NC}"
echo ""
