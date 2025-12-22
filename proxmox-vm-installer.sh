#!/usr/bin/env bash

# AkashOS VM Creation Script for Proxmox VE
# Creates a VM ready for AkashOS installation
# Compatible with Proxmox VE 8.x and 9.x

set -euo pipefail

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly AKASHOS_ISO_NAME="akashos-v0.11-alpha-ubuntu-server-24.04.3.iso"
readonly AKASHOS_ISO_URL="https://github.com/88plug/akashos/releases/latest/download/${AKASHOS_ISO_NAME}"
readonly ISO_STORAGE_PATH="/var/lib/vz/template/iso"

# Default VM Settings
readonly DEFAULT_BRIDGE="vmbr0"

# System Resource Detection
get_host_cpus() {
    nproc
}

get_available_ram_mb() {
    free -m | awk '/^Mem:/ {print $7}'
}

get_total_ram_mb() {
    free -m | awk '/^Mem:/ {print $2}'
}

get_storage_available_gb() {
    local storage="$1"
    pvesm status -storage "$storage" | awk 'NR>1 {printf "%.0f", $5/1024/1024}'
}

get_storage_total_gb() {
    local storage="$1"
    pvesm status -storage "$storage" | awk 'NR>1 {printf "%.0f", $3/1024/1024}'
}

# Format size with TB for values >= 1000GB
format_size_gb() {
    local size_gb="$1"
    if [[ $size_gb -ge 1000 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size_gb/1024}")TB"
    else
        echo "${size_gb}GB"
    fi
}

# Format memory with TB for values >= 1000GB (input in MB)
format_size_mb() {
    local size_mb="$1"
    local size_gb=$((size_mb / 1024))
    if [[ $size_gb -ge 1000 ]]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $size_gb/1024}")TB"
    else
        echo "${size_gb}GB"
    fi
}

# Generate CPU options based on host
generate_cpu_options() {
    local host_cpus=$(get_host_cpus)
    local options=()
    local values=(4 8 16 32 64 128 256)

    for val in "${values[@]}"; do
        if [[ $val -le $((host_cpus - 2)) ]]; then
            options+=("$val")
        fi
    done

    # Always include at least one option
    if [[ ${#options[@]} -eq 0 ]]; then
        options=("$((host_cpus / 2))")
    fi

    echo "${options[@]}"
}

# Generate RAM options based on available memory (returns MB values)
generate_ram_options() {
    local available_mb=$(get_available_ram_mb)
    local options=()
    local values=(4096 8192 16384 32768 65536 131072 262144 524288)  # 4GB to 512GB in MB

    for val in "${values[@]}"; do
        # Leave at least 8GB for the host
        if [[ $val -le $((available_mb - 8192)) ]]; then
            options+=("$val")
        fi
    done

    # Always include at least one option
    if [[ ${#options[@]} -eq 0 ]]; then
        options=("$((available_mb / 2))")
    fi

    echo "${options[@]}"
}

# Generate disk size options based on storage pool (returns GB values)
generate_disk_options() {
    local storage="$1"
    local available_gb=$(get_storage_available_gb "$storage")
    local options=()
    local values=(64 128 256 512 1024 2048 4096)  # GB values

    for val in "${values[@]}"; do
        # Leave at least 50GB free on storage
        if [[ $val -le $((available_gb - 50)) ]]; then
            options+=("$val")
        fi
    done

    # Always include at least one option
    if [[ ${#options[@]} -eq 0 ]] && [[ $available_gb -gt 50 ]]; then
        options+=("$((available_gb - 50))")
    fi

    echo "${options[@]}"
}

# Get smart defaults based on system resources
get_smart_cpu_default() {
    local host_cpus=$(get_host_cpus)
    local default=8

    if [[ $host_cpus -ge 64 ]]; then
        default=16
    elif [[ $host_cpus -ge 32 ]]; then
        default=8
    elif [[ $host_cpus -ge 16 ]]; then
        default=4
    else
        default=$((host_cpus / 2))
    fi

    echo "$default"
}

get_smart_ram_default() {
    local available_mb=$(get_available_ram_mb)
    local default=16384  # 16GB

    if [[ $available_mb -ge 262144 ]]; then  # 256GB+ available
        default=32768  # 32GB
    elif [[ $available_mb -ge 65536 ]]; then  # 64GB+ available
        default=16384  # 16GB
    elif [[ $available_mb -ge 32768 ]]; then  # 32GB+ available
        default=8192   # 8GB
    else
        default=$((available_mb / 4))
    fi

    echo "$default"
}

get_smart_disk_default() {
    local storage="$1"
    local available_gb=$(get_storage_available_gb "$storage")
    local default=128

    if [[ $available_gb -ge 2048 ]]; then  # 2TB+ available
        default=256
    elif [[ $available_gb -ge 512 ]]; then  # 512GB+ available
        default=128
    elif [[ $available_gb -ge 256 ]]; then  # 256GB+ available
        default=64
    else
        default=$((available_gb / 4))
    fi

    echo "$default"
}

# Parse arguments
HEADLESS_MODE=false
DEBUG_MODE=false
AUTO_START=""
QUANTITY=1

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--headless)
            HEADLESS_MODE=true
            shift
            ;;
        -d|--debug)
            DEBUG_MODE=true
            shift
            ;;
        --start-vm)
            AUTO_START="yes"
            shift
            ;;
        --no-start-vm)
            AUTO_START="no"
            shift
            ;;
        -q|--quantity)
            if [[ -z "${2:-}" ]] || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                error "Quantity must be a positive integer"
                exit 1
            fi
            QUANTITY="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create an AkashOS VM on Proxmox VE

OPTIONS:
    -h, --headless    Run without interactive prompts
    -d, --debug       Enable debug output
    -q, --quantity N  Number of VMs to create (default: 1)
    --start-vm        Start VM(s) after creation
    --no-start-vm     Do not start VM(s) after creation
    --help            Show this help message

EXAMPLES:
    $(basename "$0")                          # Interactive mode
    $(basename "$0") --headless               # Automatic with defaults
    $(basename "$0") --headless --quantity 3  # Create 3 VMs automatically
    $(basename "$0") --headless --debug       # Automatic with debug output
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging
debug() { 
    if [[ "$DEBUG_MODE" == true ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $*" >&2
    fi
}
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }

# Check requirements
[[ $EUID -ne 0 ]] && { error "Must run as root"; exit 1; }
command -v pveversion &>/dev/null || { error "Must run on Proxmox VE"; exit 1; }

# Install Gum if needed (only for interactive mode)
install_gum() {
    if [[ "$HEADLESS_MODE" == false ]] && ! command -v gum &>/dev/null; then
        info "Installing Gum for enhanced UI..."
        
        # For Debian/Ubuntu/Proxmox
        if [[ -f /etc/debian_version ]]; then
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            
            # Download latest Gum release
            curl -fsSL https://github.com/charmbracelet/gum/releases/latest/download/gum_0.14.5_linux_amd64.tar.gz -o gum.tar.gz 2>/dev/null
            tar xzf gum.tar.gz
            mv gum /usr/local/bin/
            chmod +x /usr/local/bin/gum
            
            # Cleanup
            cd - >/dev/null
            rm -rf "$temp_dir"
            
            success "Gum installed successfully"
        else
            error "Unable to auto-install Gum on this system"
            info "Falling back to standard prompts"
            return 1
        fi
    fi
    return 0
}

# Get next available VM ID
get_vmid() {
    local vmid=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")
    while qm status "$vmid" &>/dev/null || pct status "$vmid" &>/dev/null; do
        ((vmid++))
    done
    echo "$vmid"
}

# Get storage
get_storage() {
    local storages=($(pvesm status -content images | awk 'NR>1 {print $1}'))
    [[ ${#storages[@]} -eq 0 ]] && { error "No storage available"; exit 1; }
    echo "${storages[0]}"
}

# Download ISO if needed
ensure_iso() {
    local iso_path="${ISO_STORAGE_PATH}/${AKASHOS_ISO_NAME}"
    
    if [[ -f "$iso_path" ]]; then
        info "ISO found: $AKASHOS_ISO_NAME"
        return 0
    fi
    
    info "Downloading AkashOS ISO..."
    mkdir -p "$ISO_STORAGE_PATH"
    
    if curl -fL --progress-bar -o "$iso_path" "$AKASHOS_ISO_URL"; then
        success "Downloaded ISO successfully"
    else
        error "Failed to download ISO"
        exit 1
    fi
}

# Interactive mode with Gum
interactive_mode() {
    # Install gum if needed
    install_gum
    local USE_GUM=$?
    
    if [[ $USE_GUM -eq 0 ]] && command -v gum &>/dev/null; then
        # Welcome screen
        gum style \
            --border double \
            --border-foreground 212 \
            --padding "1 2" \
            --margin "1 2" \
            --align center \
            --width 50 \
            "🚀 AkashOS VM Creator" \
            "" \
            "Create a Provider VM for Akash Network" \
            "Ubuntu 24.04 + Kubernetes"
        
        if ! gum confirm "Create a new AkashOS VM?"; then
            info "Cancelled."
            exit 0
        fi

        # Get quantity
        QUANTITY=$(gum input \
            --prompt "Quantity: " \
            --value "1" \
            --placeholder "Number of VMs to create" \
            --prompt.foreground 212)
        if [[ ! "$QUANTITY" =~ ^[1-9][0-9]*$ ]]; then
            error "Quantity must be a positive integer"
            exit 1
        fi

        # Get base VM ID
        BASE_VMID=$(gum input \
            --prompt "Base VM ID: " \
            --value "$(get_vmid)" \
            --placeholder "Enter starting VM ID" \
            --prompt.foreground 212)
        
        # Storage selection (first, so we can show disk options based on it)
        local storage_list=($(pvesm status -content images | awk 'NR>1 {print $1}'))
        [[ ${#storage_list[@]} -eq 0 ]] && { error "No storage available"; exit 1; }
        if [[ ${#storage_list[@]} -gt 1 ]]; then
            # Build storage options with available space
            local storage_opts=()
            for s in "${storage_list[@]}"; do
                local avail=$(get_storage_available_gb "$s")
                storage_opts+=("$s ($(format_size_gb "$avail") free)")
            done
            local selected=$(printf '%s\n' "${storage_opts[@]}" | gum choose \
                --header "Select Storage Pool:" \
                --cursor.foreground 212 \
                --selected.foreground 212)
            STORAGE=$(echo "$selected" | awk '{print $1}')
        else
            STORAGE="${storage_list[0]}"
        fi

        # Get system info for display
        local host_cpus=$(get_host_cpus)
        local avail_ram=$(get_available_ram_mb)
        local avail_disk=$(get_storage_available_gb "$STORAGE")

        # Select configuration mode
        local mode=$(gum choose \
            --header "Select Configuration:" \
            --cursor.foreground 212 \
            --selected.foreground 212 \
            "Quick Setup (Recommended)" \
            "Advanced Configuration")

        if [[ "$mode" == "Advanced Configuration" ]]; then
            # CPU Cores - dynamic options
            local cpu_opts=($(generate_cpu_options))
            local cpu_default=$(get_smart_cpu_default)
            CPU_CORES=$(printf '%s\n' "${cpu_opts[@]}" | gum choose \
                --header "Select CPU Cores (${host_cpus} available):" \
                --cursor.foreground 212 \
                --selected.foreground 212)

            # RAM Size - dynamic options with formatted display
            local ram_opts=($(generate_ram_options))
            local ram_display=()
            for r in "${ram_opts[@]}"; do
                ram_display+=("$r:$(format_size_mb "$r")")
            done
            local ram_selected=$(printf '%s\n' "${ram_display[@]}" | awk -F: '{print $2}' | gum choose \
                --header "Select RAM ($(format_size_mb "$avail_ram") available):" \
                --cursor.foreground 212 \
                --selected.foreground 212)
            # Convert display back to MB value
            for i in "${!ram_display[@]}"; do
                if [[ "${ram_display[$i]}" == *":$ram_selected" ]]; then
                    RAM_SIZE="${ram_opts[$i]}"
                    break
                fi
            done

            # Disk Size - dynamic options based on storage
            local disk_opts=($(generate_disk_options "$STORAGE"))
            local disk_display=()
            for d in "${disk_opts[@]}"; do
                disk_display+=("$d:$(format_size_gb "$d")")
            done
            local disk_selected=$(printf '%s\n' "${disk_display[@]}" | awk -F: '{print $2}' | gum choose \
                --header "Select Disk Size ($(format_size_gb "$avail_disk") available):" \
                --cursor.foreground 212 \
                --selected.foreground 212)
            # Convert display back to GB value
            for i in "${!disk_display[@]}"; do
                if [[ "${disk_display[$i]}" == *":$disk_selected" ]]; then
                    DISK_SIZE="${disk_opts[$i]}"
                    break
                fi
            done

            # Network Bridge
            BRIDGE=$(gum input \
                --prompt "Network Bridge: " \
                --value "$DEFAULT_BRIDGE" \
                --placeholder "Enter bridge name" \
                --prompt.foreground 212)
        else
            # Use smart defaults
            CPU_CORES=$(get_smart_cpu_default)
            RAM_SIZE=$(get_smart_ram_default)
            DISK_SIZE=$(get_smart_disk_default "$STORAGE")
            BRIDGE=$DEFAULT_BRIDGE
        fi

        # Calculate VM IDs
        VMIDS=()
        current=$BASE_VMID
        for ((i=0; i<QUANTITY; i++)); do
            while qm status "$current" &>/dev/null || pct status "$current" &>/dev/null; do
                ((current++))
            done
            VMIDS+=("$current")
            ((current++))
        done

        # Show summary - build display strings with proper formatting
        if [[ $QUANTITY -eq 1 ]]; then
            VMID_LINE="VM ID:        ${VMIDS[0]}"
        else
            VMID_LINE="VM IDs:       $(IFS=', '; echo "${VMIDS[*]}")"
        fi
        local QUANTITY_LINE="Quantity:     $QUANTITY"
        local CPU_LINE="CPU Cores:    $CPU_CORES"
        local RAM_LINE="RAM:          $(format_size_mb "$RAM_SIZE")"
        local DISK_LINE="Disk:         $(format_size_gb "$DISK_SIZE")"
        local STORAGE_LINE="Storage:      $STORAGE"
        local BRIDGE_LINE="Bridge:       $BRIDGE"

        gum style \
            --border normal \
            --border-foreground 212 \
            --padding "1 2" \
            --margin "1" \
            --width 50 \
            "📋 Configuration Summary" \
            "" \
            "$VMID_LINE" \
            "$QUANTITY_LINE" \
            "$CPU_LINE" \
            "$RAM_LINE" \
            "$DISK_LINE" \
            "$STORAGE_LINE" \
            "$BRIDGE_LINE"
        
        if ! gum confirm "Proceed with VM creation?"; then
            info "Cancelled."
            exit 0
        fi
        
        # Ask about starting VM
        if gum confirm "Start VM after creation?"; then
            AUTO_START="yes"
        else
            AUTO_START="no"
        fi
    else
        # Fallback to standard prompts
        info "Creating AkashOS VM..."

        # Show system info
        local host_cpus=$(get_host_cpus)
        local avail_ram=$(get_available_ram_mb)
        echo "System: ${host_cpus} CPUs, $(format_size_mb "$avail_ram") RAM available"

        echo -n "Quantity [1]: "
        read -r QUANTITY
        QUANTITY=${QUANTITY:-1}
        if [[ ! "$QUANTITY" =~ ^[1-9][0-9]*$ ]]; then
            error "Quantity must be a positive integer"
            exit 1
        fi

        STORAGE=$(get_storage)
        local avail_disk=$(get_storage_available_gb "$STORAGE")
        echo "Storage: $STORAGE ($(format_size_gb "$avail_disk") available)"

        # Get smart defaults
        local cpu_default=$(get_smart_cpu_default)
        local ram_default=$(get_smart_ram_default)
        local disk_default=$(get_smart_disk_default "$STORAGE")

        echo -n "Use default settings? (y/n): "
        read -r -n 1 REPLY
        echo

        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -n "CPU Cores [$cpu_default]: "
            read -r CPU_CORES
            CPU_CORES=${CPU_CORES:-$cpu_default}

            echo -n "RAM Size in MB [$ram_default = $(format_size_mb "$ram_default")]: "
            read -r RAM_SIZE
            RAM_SIZE=${RAM_SIZE:-$ram_default}

            echo -n "Disk Size in GB [$disk_default = $(format_size_gb "$disk_default")]: "
            read -r DISK_SIZE
            DISK_SIZE=${DISK_SIZE:-$disk_default}

            echo -n "Network Bridge [$DEFAULT_BRIDGE]: "
            read -r BRIDGE
            BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}
        else
            CPU_CORES=$cpu_default
            RAM_SIZE=$ram_default
            DISK_SIZE=$disk_default
            BRIDGE=$DEFAULT_BRIDGE
        fi

        # Get base VM ID
        echo -n "Base VM ID [$(get_vmid)]: "
        read -r BASE_VMID
        BASE_VMID=${BASE_VMID:-$(get_vmid)}

        # Calculate VM IDs
        VMIDS=()
        current=$BASE_VMID
        for ((i=0; i<QUANTITY; i++)); do
            while qm status "$current" &>/dev/null || pct status "$current" &>/dev/null; do
                ((current++))
            done
            VMIDS+=("$current")
            ((current++))
        done

        if [[ $QUANTITY -eq 1 ]]; then
            VMID_DISPLAY="VM ID: ${VMIDS[0]}"
        else
            VMID_DISPLAY="VM IDs: ${VMIDS[*]}"
        fi

        echo "Configuration:"
        echo "  $VMID_DISPLAY"
        echo "  Quantity: $QUANTITY"
        echo "  CPU Cores: $CPU_CORES"
        echo "  RAM: $(format_size_mb "$RAM_SIZE")"
        echo "  Disk: $(format_size_gb "$DISK_SIZE")"
        echo "  Storage: $STORAGE"
        echo "  Bridge: $BRIDGE"
        
        echo -n "Continue? (y/n): "
        read -r -n 1 REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cancelled."
            exit 0
        fi
        
        if [[ -z "$AUTO_START" ]]; then
            echo -n "Start VM after creation? (y/n): "
            read -r -n 1 REPLY
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                AUTO_START="yes"
            else
                AUTO_START="no"
            fi
        fi
    fi
}

# Main
if [[ "$HEADLESS_MODE" == true ]]; then
    info "Creating AkashOS VM in headless mode..."
    STORAGE=$(get_storage)
    CPU_CORES=$(get_smart_cpu_default)
    RAM_SIZE=$(get_smart_ram_default)
    DISK_SIZE=$(get_smart_disk_default "$STORAGE")
    BRIDGE=$DEFAULT_BRIDGE

    debug "Auto-detected: CPU=$CPU_CORES, RAM=$(format_size_mb "$RAM_SIZE"), Disk=$(format_size_gb "$DISK_SIZE")"

    # Calculate VM IDs
    BASE_VMID=$(get_vmid)
    VMIDS=()
    current=$BASE_VMID
    for ((i=0; i<QUANTITY; i++)); do
        while qm status "$current" &>/dev/null || pct status "$current" &>/dev/null; do
            ((current++))
        done
        VMIDS+=("$current")
        ((current++))
    done
else
    interactive_mode
fi

# Ensure ISO is available
ensure_iso

# Get storage type once (doesn't change per VM)
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')

for VMID in "${VMIDS[@]}"; do
    MAC=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

    debug "VM ID: $VMID"
    debug "Storage: $STORAGE (type: $STORAGE_TYPE)"
    debug "MAC: $MAC"

    # Create VM
    info "Creating VM $VMID..."
    qm create "$VMID" \
        -agent 1 \
        -machine q35 \
        -tablet 0 \
        -localtime 1 \
        -bios ovmf \
        -cpu host \
        -cores "$CPU_CORES" \
        -memory "$RAM_SIZE" \
        -balloon 0 \
        -name "akashos-${VMID}" \
        -tags "akashos" \
        -net0 "virtio,bridge=${BRIDGE},macaddr=${MAC}" \
        -onboot 1 \
        -ostype l26 \
        -scsihw virtio-scsi-pci

    # Create EFI disk
    info "Creating EFI disk for VM $VMID..."
    qm set "$VMID" -efidisk0 "${STORAGE}:1,efitype=4m" 2>/dev/null

    # Create main disk
    info "Creating main disk (${DISK_SIZE}GB) for VM $VMID..."
    case "$STORAGE_TYPE" in
        dir|nfs|cifs)
            qm set "$VMID" -scsi0 "${STORAGE}:${DISK_SIZE},format=qcow2" 2>/dev/null
            ;;
        *)
            qm set "$VMID" -scsi0 "${STORAGE}:${DISK_SIZE}" 2>/dev/null
            ;;
    esac

    # Attach ISO
    info "Attaching installation ISO to VM $VMID..."
    qm set "$VMID" -ide2 "local:iso/${AKASHOS_ISO_NAME},media=cdrom" 2>/dev/null
    qm set "$VMID" -boot "order=ide2;scsi0" 2>/dev/null
    #Disable serial
    #qm set "$VMID" -serial0 socket &>/dev/null

    # Set VM description
    DESCRIPTION=$(cat <<'EOF'
<div align="center">

<img src="https://raw.githubusercontent.com/cryptoandcoffee/akashos/main/logo.png" width="120">

<h1>🚀 AkashOS Provider VM</h1>
<p><b>Ubuntu 24.04 + Kubernetes for Akash Network</b></p>

<hr width="50%">

<p><b>⚡ REQUIREMENTS</b><br>
Internet connection to install • 5 AKT minimum to start the provider</p>

<hr width="80%">

<h2>⚙️ Configuration</h2>

<table border="1" cellpadding="8" width="80%">
<tr>
<td><b>🔐 Credentials</b></td>
<td>akash / akash</td>
</tr>
<tr>
<td><b>🎯 Dashboard</b></td>
<td>http://IP_OF_VM:8888</td>
</tr>
<tr>
<td><b>🛑 Disable</b></td>
<td>systemctl disable --now dash</td>
</tr>
<tr>
<td><b>🔒 Security</b></td>
<td>No telemetry • No remote pinging</td>
</tr>
<tr>
<td><b>💰 Min AKT</b></td>
<td>5 AKT required</td>
</tr>
</table>

<h2>📋 Installation Steps</h2>

<table cellpadding="8" width="80%">
<tr>
<td align="center" width="50">1️</td>
<td align="left"><b>Start VM</b> → View the Console</td>
</tr>
<tr>
<td align="center">2️</td>
<td align="left"><b>Setup</b> → Answer 3 questions (5-15 min)</td>
</tr>
<tr>
<td align="center">3️</td>
<td align="left"><b>Wait</b> → "AkashOS is ready. Remove CD and reboot."</td>
</tr>
<tr>
<td align="center">4️</td>
<td align="left"><b>Stop VM</b> → Hardware → Remove CD-ROM</td>
</tr>
<tr>
<td align="center">5️</td>
<td align="left"><b>Snapshot</b> → Create safe restore point 💾</td>
</tr>
<tr>
<td align="center">6️</td>
<td align="left"><b>Login</b> → SSH/Console: akash / akash</td>
</tr>
<tr>
<td align="center">7️</td>
<td align="left"><b>Setup Wizard</b> → Complete (auto-restart once)</td>
</tr>
<tr>
<td align="center">8️</td>
<td align="left"><b>Dashboard</b> → Access when "Installation Complete"</td>
</tr>
</table>

<hr width="80%">

<p><b>📎 QUICK LINKS</b></p>
<p>
<a href="https://akashos.com">🌐 Website</a> •
<a href="https://github.com/cryptoandcoffee/akashos">💻 GitHub</a> •
<a href="https://akash.network">🚀 Akash Network</a>
</p>

<hr width="80%">

<h3>💡 Help Make AkashOS Better</h3>
<p><a href="https://github.com/cryptoandcoffee/akashos">→ Contribute on GitHub</a></p>

<p><i>Secure by Design • Open Source • No Telemetry</i></p>

</div>
EOF
)
    qm set "$VMID" -description "$DESCRIPTION" >/dev/null
done

# Start VMs
if [[ "$AUTO_START" == "yes" ]] || [[ "$HEADLESS_MODE" == true && "$AUTO_START" != "no" ]]; then
    for VMID in "${VMIDS[@]}"; do
        info "Starting VM $VMID..."
        qm start "$VMID" && success "VM $VMID started"
    done
fi

# Done
if command -v gum &>/dev/null && [[ "$HEADLESS_MODE" == false ]]; then
    # Success message with gum
    gum style \
        --border double \
        --border-foreground 76 \
        --padding "1 2" \
        --margin "1" \
        --align center \
        --width 50 \
        "✅ VMs Created Successfully!" \
        "" \
        "VM IDs: ${VMIDS[*]}" \
        "Consoles: Proxmox VE > [VMID] > Console" \
        "" \
        "Next Steps:" \
        "1. Access VM console" \
        "2. Login: akash / akash" \
        "3. Follow setup wizard" \
        "4. Access dashboard at http://VM_IP:8888" \
        "5. Fund wallet with 5+ AKT"
else
    # Standard success message
    success "AkashOS VMs created successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VM IDs: ${VMIDS[*]}"
    echo "Consoles: Proxmox VE > [VMID] > Console"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next steps:"
    echo "1. Access the VM console to complete installation"
    echo "2. Login with: akash / akash"
    echo "3. Follow on-screen setup instructions"
    echo "4. Access dashboard after reboot"
    echo "5. Fund wallet with 5+ AKT to start provider"
fi
