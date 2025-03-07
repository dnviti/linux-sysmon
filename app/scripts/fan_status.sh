#!/bin/bash
# Script to monitor system, CPU, and GPU fans with uniform output

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

# Enable colors only for text output.
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

# Get color based on fan speed percentage.
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

# Draw a progress bar of fixed length based on a percentage.
progress_bar() {
    local percent=$1
    local bar_length=10
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

# Default maximum RPM used for normalization.
MAX_RPM=5000

# Check for the 'sensors' command.
if ! command -v sensors &> /dev/null; then
    echo "Error: 'sensors' command not found. Please install lm-sensors." >&2
    exit 1
fi

# Get fan information from sensors.
fan_lines=$(sensors | grep -Ei "fan[0-9]*:")

if [ -z "$fan_lines" ]; then
    echo "No fan data found." >&2
    exit 1
fi

# For JSON or YAML output, collect fan data into an array.
if [ "$OUTPUT_FORMAT" = "json" ] || [ "$OUTPUT_FORMAT" = "yaml" ]; then
    fan_data=()
    while IFS= read -r line; do
        # Extract the fan label and speed.
        fan_label=$(echo "$line" | cut -d ':' -f1)
        fan_speed=$(echo "$line" | awk '{print $2}')
        
        # Determine fan type based on the label.
        lower_label=$(echo "$fan_label" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_label" == *"cpu"* ]]; then
            fan_type="CPU Fan"
        elif [[ "$lower_label" == *"gpu"* ]]; then
            fan_type="GPU Fan"
        else
            fan_type="System Fan"
        fi
        
        # If the fan speed is not a number, mark values as null.
        if ! [[ "$fan_speed" =~ ^[0-9]+$ ]]; then
            speed_rpm="null"
            percentage="null"
        else
            speed_rpm=$fan_speed
            percentage=$(( fan_speed * 100 / MAX_RPM ))
            if [ "$percentage" -gt 100 ]; then
                percentage=100
            fi
        fi
        
        # Store the data as a string with a separator.
        fan_data+=("$fan_type|$fan_label|$speed_rpm|$percentage")
    done <<< "$fan_lines"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "{"
        echo '  "fans": ['
        first=1
        for entry in "${fan_data[@]}"; do
            IFS='|' read -r ft fl sr per <<< "$entry"
            if [ $first -eq 1 ]; then
                first=0
            else
                echo "    ,"
            fi
            echo -n "    { \"fan_type\": \"${ft}\", \"fan_label\": \"${fl}\", \"speed_rpm\": "
            if [ "$sr" = "null" ]; then
                echo -n "null"
            else
                echo -n "$sr"
            fi
            echo -n ", \"percentage\": "
            if [ "$per" = "null" ]; then
                echo "null }"
            else
                echo "$per }"
            fi
        done
        echo "  ]"
        echo "}"
        exit 0
    elif [ "$OUTPUT_FORMAT" = "yaml" ]; then
        echo "fans:"
        for entry in "${fan_data[@]}"; do
            IFS='|' read -r ft fl sr per <<< "$entry"
            echo "  - fan_type: \"$ft\""
            echo "    fan_label: \"$fl\""
            if [ "$sr" = "null" ]; then
                echo "    speed_rpm: null"
            else
                echo "    speed_rpm: $sr"
            fi
            if [ "$per" = "null" ]; then
                echo "    percentage: null"
            else
                echo "    percentage: $per"
            fi
        done
        exit 0
    fi
fi

####################
# Human-readable   #
# Textual Output   #
####################

echo "System Fans:"
while IFS= read -r line; do
    fan_label=$(echo "$line" | cut -d ':' -f1)
    fan_speed=$(echo "$line" | awk '{print $2}')
    
    lower_label=$(echo "$fan_label" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_label" == *"cpu"* ]]; then
        fan_type="CPU Fan"
    elif [[ "$lower_label" == *"gpu"* ]]; then
        fan_type="GPU Fan"
    else
        fan_type="System Fan"
    fi
    
    if ! [[ "$fan_speed" =~ ^[0-9]+$ ]]; then
        echo "$fan_type: $fan_label"
        printf "  %-15s %s\n" "Speed:" "N/A"
        echo ""
        continue
    fi
    
    percent=$(( fan_speed * 100 / MAX_RPM ))
    if [ "$percent" -gt 100 ]; then
        percent=100
    fi
    
    color=$(get_color "$percent")
    bar=$(progress_bar "$percent")
    
    echo "$fan_type: $fan_label"
    printf "  %-15s %s %s\n" "Speed:" "${color}${bar}${NC}" "(${fan_speed} RPM)"
    echo ""
done <<< "$fan_lines"
