#!/bin/bash
# Script to monitor system, CPU, and GPU fans with uniform output

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

# Function to determine the color based on fan speed percentage.
# Thresholds (arbitrary):
# - Green: less than 30% of MAX_RPM (low speed)
# - Yellow: 30% to 70% of MAX_RPM (moderate speed)
# - Red: above 70% of MAX_RPM (high speed)
get_color() {
    local percent=$1
    if [ "$percent" -ge 70 ]; then
        echo "$RED"
    elif [ "$percent" -ge 30 ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# Function to draw a progress bar based on a percentage.
progress_bar() {
    local percent=$1
    local bar_length=10
    # If the value is not numeric (e.g., "N/A"), return an empty bar.
    if ! [[ "$percent" =~ ^[0-9]+$ ]]; then
        printf "%0.s░" $(seq 1 $bar_length)
        return
    fi
    # Cap percentage at 100.
    if [ "$percent" -gt 100 ]; then
        percent=100
    fi
    local filled_length=$(( percent * bar_length / 100 ))
    local empty_length=$(( bar_length - filled_length ))
    local filled=$(printf "%0.s█" $(seq 1 $filled_length))
    local empty=$(printf "%0.s░" $(seq 1 $empty_length))
    echo "${filled}${empty}"
}

####################
# Fan Monitoring   #
####################

# Set a default maximum RPM for fan normalization (this value is arbitrary and may be adjusted)
MAX_RPM=5000

echo "System Fans:"

# Check if the sensors command is available
if ! command -v sensors &> /dev/null; then
    echo "Error: 'sensors' command not found. Please install lm-sensors."
    exit 1
fi

# Get fan information lines from sensors output (lines that include "fan" followed by a number or text)
fan_lines=$(sensors | grep -Ei "fan[0-9]*:")

if [ -z "$fan_lines" ]; then
    echo "No fan data found."
    exit 1
fi

# Process each fan line
echo "$fan_lines" | while IFS= read -r line; do
    # Extract the fan label and speed.
    # Example line: "fan1:        1200 RPM"
    fan_label=$(echo "$line" | cut -d ':' -f1)
    fan_speed=$(echo "$line" | awk '{print $2}')
    
    # Determine the fan type based on the label.
    lower_label=$(echo "$fan_label" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_label" == *"cpu"* ]]; then
        fan_type="CPU Fan"
    elif [[ "$lower_label" == *"gpu"* ]]; then
        fan_type="GPU Fan"
    else
        fan_type="System Fan"
    fi
    
    # If fan speed is not a number (e.g., "N/A"), display accordingly.
    if ! [[ "$fan_speed" =~ ^[0-9]+$ ]]; then
        echo "$fan_type: $fan_label"
        printf "  %-15s %s\n" "Speed:" "N/A"
        echo ""
        continue
    fi

    # Calculate the percentage of the maximum RPM.
    percent=$(( fan_speed * 100 / MAX_RPM ))
    # Cap the percentage at 100.
    if [ "$percent" -gt 100 ]; then
        percent=100
    fi

    # Get the appropriate color and progress bar.
    color=$(get_color "$percent")
    bar=$(progress_bar "$percent")
    
    # Print the fan report.
    echo "$fan_type: $fan_label"
    printf "  %-15s %s %s\n" "Speed:" "${color}${bar}${NC}" "(${fan_speed} RPM)"
    echo ""
done
