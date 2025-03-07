#!/bin/bash
# Script to monitor NVIDIA, AMD, and Intel GPUs with uniform output

# Common Functions

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

# Flag to check if at least one supported GPU is found.
gpu_found=false

##########################
# NVIDIA Branch
##########################
if command -v nvidia-smi &> /dev/null; then
    # Retrieve information for all NVIDIA GPUs in a single CSV call:
    # name, utilization, temperature, used memory, and total memory.
    mapfile -t gpu_info < <(nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits)
    
    if [ ${#gpu_info[@]} -gt 0 ]; then
        gpu_found=true
        for info in "${gpu_info[@]}"; do
            # Extract values (trimming extra spaces)
            IFS=',' read -r name usage temp memory_used memory_total <<< "$info"
            name=$(echo "$name" | xargs)
            usage=$(echo "$usage" | xargs)
            temp=$(echo "$temp" | xargs)
            memory_used=$(echo "$memory_used" | xargs)
            memory_total=$(echo "$memory_total" | xargs)
            
            # Calculate the percentage of used memory.
            if [ "$memory_total" -gt 0 ]; then
                memory_percent=$(( memory_used * 100 / memory_total ))
            else
                memory_percent=0
            fi
            
            # Convert memory from MiB to GiB (approximate conversion).
            memory_used_gib=$(( memory_used / 1024 ))
            memory_total_gib=$(( memory_total / 1024 ))
            
            # Determine colors based on thresholds (utilization: 50 and 80, temperature: 60 and 80, memory: 50 and 80).
            utilization_color=$(get_color "$usage" 50 80)
            temp_color=$(get_color "$temp" 60 80)
            memory_color=$(get_color "$memory_percent" 50 80)
            
            # Build progress bars for utilization and memory.
            usage_bar=$(progress_bar "$usage")
            memory_bar=$(progress_bar "$memory_percent")
            
            # Print the report for the GPU.
            echo "GPU: ${name}"
            printf "  %-15s %s %s\n" "Utilization:" "${utilization_color}${usage_bar}${NC}" "(${usage}%)"
            printf "  %-15s %s\n" "Temperature:" "${temp_color}${temp}°C${NC}"
            printf "  %-15s %s %s\n" "Used Memory:" "${memory_color}${memory_bar}${NC}" "(${memory_used_gib}/${memory_total_gib} GiB - ${memory_percent}%)"
            echo ""
        done
    fi
fi

##########################
# AMD Branch (rocm-smi)
##########################
if command -v rocm-smi &> /dev/null; then
    # Use rocm-smi with options to show:
    # product name, GPU usage, temperature, and VRAM information (total and used).
    amd_info=$(rocm-smi --showproductname --showuse --showtemp --showmeminfo vram 2>/dev/null)
    
    # Check if at least one AMD GPU is found by looking for lines containing "GPU[".
    gpu_count=$(echo "$amd_info" | grep -c "GPU\[")
    if [ "$gpu_count" -gt 0 ]; then
        gpu_found=true
        for (( i=0; i<gpu_count; i++ )); do
            # Extract information for GPU[i].
            name=$(echo "$amd_info" | grep "GPU\[$i\]" | grep -i "product name" | awk -F':' '{print $2}' | xargs)
            usage=$(echo "$amd_info" | grep "GPU\[$i\]" | grep -i "GPU use" | awk -F':' '{print $2}' | tr -d '% ' | xargs)
            temp=$(echo "$amd_info" | grep "GPU\[$i\]" | grep -i "Temperature" | head -n1 | awk -F':' '{print $2}' | tr -d 'c°C ' | xargs)
            mem_total=$(echo "$amd_info" | grep "GPU\[$i\]" | grep -i "VRAM Total" | awk -F':' '{print $2}' | tr -d 'MiB ' | xargs)
            mem_used=$(echo "$amd_info" | grep "GPU\[$i\]" | grep -i "VRAM Used" | awk -F':' '{print $2}' | tr -d 'MiB ' | xargs)
            
            # Set default values if any value is missing.
            usage=${usage:-0}
            temp=${temp:-0}
            mem_total=${mem_total:-0}
            mem_used=${mem_used:-0}
            
            if [ "$mem_total" -gt 0 ]; then
                memory_percent=$(( mem_used * 100 / mem_total ))
            else
                memory_percent=0
            fi
            
            memory_used_gib=$(( mem_used / 1024 ))
            memory_total_gib=$(( mem_total / 1024 ))
            
            utilization_color=$(get_color "$usage" 50 80)
            temp_color=$(get_color "$temp" 60 80)
            memory_color=$(get_color "$memory_percent" 50 80)
            
            usage_bar=$(progress_bar "$usage")
            memory_bar=$(progress_bar "$memory_percent")
            
            echo "GPU: ${name}"
            printf "  %-15s %s %s\n" "Utilization:" "${utilization_color}${usage_bar}${NC}" "(${usage}%)"
            printf "  %-15s %s\n" "Temperature:" "${temp_color}${temp}°C${NC}"
            printf "  %-15s %s %s\n" "Used Memory:" "${memory_color}${memory_bar}${NC}" "(${memory_used_gib}/${memory_total_gib} GiB - ${memory_percent}%)"
            echo ""
        done
    fi
fi

##########################
# Intel Branch
##########################
# Detect Intel GPU presence via lspci (typically integrated).
intel_line=$(lspci | grep -i 'vga.*intel')
if [ -n "$intel_line" ]; then
    gpu_found=true
    # Extract the GPU name (the part after the second ':').
    intel_name=$(echo "$intel_line" | cut -d ':' -f3 | xargs)
    
    # Attempt to read the temperature from sysfs (if available).
    intel_temp_file=$(find /sys/class/drm/card0/device/hwmon/ -type f -name "temp1_input" 2>/dev/null | head -n1)
    if [ -n "$intel_temp_file" ]; then
        raw_temp=$(cat "$intel_temp_file")
        # Convert from millidegree to Celsius.
        intel_temp=$(( raw_temp / 1000 ))
    else
        intel_temp="N/A"
    fi
    
    # For Intel GPUs (integrated) a dedicated monitoring tool for usage and dedicated memory is often not available.
    # Set these values to "N/A" and show an empty bar.
    intel_usage="N/A"
    intel_memory_percent="N/A"
    
    # Empty bars for usage and memory.
    usage_bar_intel=$(progress_bar 0)
    memory_bar_intel=$(progress_bar 0)
    
    echo "GPU: ${intel_name}"
    printf "  %-15s %s %s\n" "Utilization:" "${usage_bar_intel}" "(N/A)"
    if [ "$intel_temp" = "N/A" ]; then
        printf "  %-15s %s\n" "Temperature:" "N/A"
    else
        printf "  %-15s %s\n" "Temperature:" "${intel_temp}°C"
    fi
    printf "  %-15s %s %s\n" "Used Memory:" "${memory_bar_intel}" "(N/A)"
    echo ""
fi

if [ "$gpu_found" = false ]; then
    echo "Error: No supported GPU monitoring tool found."
    exit 1
fi

