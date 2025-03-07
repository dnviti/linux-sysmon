# System Monitoring Scripts

This repository contains a collection of Bash scripts designed to monitor various hardware components on your system with uniform, color-coded output and progress bars. The scripts are lightweight and work on most Linux distributions, making it easy to quickly check the status of your CPU, RAM, disks, and GPUs.

## Repository Contents

- **cpu_status.sh**  
  Monitors the CPU and RAM usage. It shows the CPU model (if available), calculates the CPU usage percentage, optionally retrieves the CPU temperature using the `sensors` command, and displays RAM usage with progress bars.

- **disk_status.sh**  
  Monitors disk usage for physical filesystems. It excludes temporary file systems (like `tmpfs` and `devtmpfs`), calculates disk usage percentages, and converts the used and total disk space from KiB to GiB for readability.

- **gpu_status.sh**  
  Monitors GPU usage for NVIDIA, AMD, and Intel GPUs.  
  - **NVIDIA:** Uses `nvidia-smi` to retrieve GPU utilization, temperature, and memory usage.  
  - **AMD:** Uses `rocm-smi` to retrieve similar information for AMD GPUs.  
  - **Intel:** Detects Intel integrated GPUs via `lspci` and attempts to read the temperature from sysfs. (Note: Dedicated usage and memory monitoring for Intel GPUs may not be available.)

## Features

- **Color-Coded Output:**  
  Uses terminal colors (green, yellow, red) based on usage thresholds to easily visualize performance:
  - **Green:** Normal usage.
  - **Yellow:** Moderate usage (above 50%).
  - **Red:** High usage (above 80%).

- **Progress Bars:**  
  Displays a graphical progress bar for each metric to provide a quick visual indicator of resource usage.

- **Compatibility:**  
  Designed to work in environments where the required utilities (e.g., `lscpu`, `free`, `df`, `nvidia-smi`, `rocm-smi`, `sensors`, and `lspci`) are available.

## Prerequisites

- **General:**  
  A Linux distribution with a POSIX-compliant shell (e.g., Bash).

- **For CPU Monitoring (`cpu_status.sh`):**
  - `lscpu` (optional, for CPU model information)
  - `sensors` (optional, for CPU temperature)
  - `free` (for memory usage)

- **For Disk Monitoring (`disk_status.sh`):**
  - `df` (to obtain disk information)

- **For GPU Monitoring (`gpu_status.sh`):**
  - **NVIDIA:** [`nvidia-smi`](https://developer.nvidia.com/nvidia-system-management-interface)
  - **AMD:** [`rocm-smi`](https://github.com/RadeonOpenCompute/rocm_smi_lib)
  - **Intel:** `lspci` (for detecting the GPU) and access to sysfs for temperature data

## Installation

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/yourusername/system-monitoring-scripts.git
   cd system-monitoring-scripts
   ```

2. **Make the Scripts Executable:**

   ```bash
   chmod +x cpu_status.sh disk_status.sh gpu_status.sh
   ```

## Usage

Run the scripts directly from the terminal:

- **CPU and RAM Status:**

  ```bash
  ./cpu_status.sh
  ```

- **Disk Usage Status:**

  ```bash
  ./disk_status.sh
  ```

- **GPU Status:**

  ```bash
  ./gpu_status.sh
  ```

> **Note:** Some scripts may require root privileges or proper configuration of hardware monitoring tools to retrieve all data correctly.

## Customization

- **Thresholds:**  
  You can adjust the thresholds for the color coding (default values: 50% for yellow, 80% for red) by modifying the respective function calls in the scripts.

- **Progress Bar Length:**  
  The progress bar length is set to 10 by default. To modify it, change the `bar_length` variable in the `progress_bar` functions.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request for any improvements or bug fixes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.