#!/bin/bash

# 
# mkdir -p $HOME/scripts/nym-scripts
# URLGIST="https://gist.githubusercontent.com/toolfun/fe137d3d983ebf26b4d603ab71553d6e/raw/nym-node-installer.sh"
# URLGH="https://raw.githubusercontent.com/toolfun/Scripts/refs/heads/main/Nym/nym-node-installer.sh"
# curl --fail -L --progress-bar $URLGH -o ~/scripts/nym-scripts/nym-node-installer.sh
# chmod +x $HOME/scripts/nym-scripts/nym-node-installer.sh 
#

#=============================================================================
# Nym Node Installation Script for Ubuntu 22/24 LTS
# Author: toolfun
# Description: Automated installation and configuration of Nym node
#=============================================================================

set -o pipefail  # Catch errors in pipes
# Note: set -e is disabled to allow manual error handling

#=============================================================================
# COLOR DEFINITIONS
#=============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;94m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#=============================================================================
# ERROR HANDLING
#=============================================================================
handle_command_error() {
    local command="$1"
    local error_msg="$2"
    
    print_error "Command failed: $command"
    if [ -n "$error_msg" ]; then
        print_error "$error_msg"
    fi
    
    echo ""
    print_info "Options:"
    echo -e "  ${GREEN}[C]${NC} - Continue anyway (not recommended)"
    echo -e "  ${GREEN}[R]${NC} - Retry the command"
    echo -e "  ${GREEN}[Q]${NC} - Quit installation"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [C/R/Q]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        case "$choice" in
            c)
                print_warning "Continuing with warning..."
                return 0
                ;;
            r)
                return 1  # Signal retry
                ;;
            q)
                print_info "Exiting installation..."
                exit 1
                ;;
            *)
                print_warning "Invalid choice. Please enter C, R, or Q."
                ;;
        esac
    done
}

# Wrapper for commands that might fail
safe_execute() {
    local description="$1"
    shift
    local command="$@"
    
    while true; do
        if eval "$command"; then
            return 0
        else
            if handle_command_error "$command" "$description"; then
                return 0  # Continue anyway
            else
                continue  # Retry
            fi
        fi
    done
}

#=============================================================================
# LOGGING AND PROGRESS STATE
#=============================================================================
SCRIPT_DIR="$HOME/.nym-installer"
LOG_FILE="$SCRIPT_DIR/install.log"
STATE_FILE="$SCRIPT_DIR/state.conf"

# Create script directory if it doesn't exist
mkdir -p "$SCRIPT_DIR"

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
}

#=============================================================================
# DISPLAY FUNCTIONS
#=============================================================================
print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "SECTION: $1"
}

print_success() {
    echo -e "  ${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
    sleep 2
}

print_error() {
    echo -e "  ${RED}❌ $1${NC}"
    log_error "$1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

print_step() {
    echo -e "${MAGENTA}${BOLD}▶ $1${NC}"
    log "STEP: $1"
}

print_summary() {
    echo ""
    echo -e "${CYAN}${NC} ${BOLD}Summary:${NC} $1"
    echo -e "${CYAN}═════════╝${NC}"
    echo ""
    sleep 2
}

#=============================================================================
# USER INPUT FUNCTIONS
#=============================================================================
prompt_user() {
    local prompt="$1"
    local var_name="$2"
    local required="${3:-required}"
    local validation="${4:-}"
    local input=""
    
    while true; do
        echo -ne "${YELLOW}${prompt}${NC}"
        read -r input
        
        input=$(echo "$input" | xargs)
        
        if [ -z "$input" ] && [ "$required" = "optional" ]; then
            eval "$var_name=''"
            log "User input for $var_name: (empty - optional)"
            return 0
        fi
        
        if [ -z "$input" ] && [ "$required" = "required" ]; then
            print_warning "This field is required. Please enter a value."
            continue
        fi
        
        if [ -n "$validation" ] && [ -n "$input" ]; then
            if ! $validation "$input"; then
                continue
            fi
        fi
        
        eval "$var_name='$input'"
        log "User input for $var_name: $input"
        return 0
    done
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local response=""
    
    if [ "$default" = "yes" ]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi
    
    while true; do
        echo -ne "${YELLOW}${prompt}${NC}"
        read -r response
        
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        case "$response" in
            yes|y)
                log "User response: YES"
                return 0
                ;;
            no|n)
                log "User response: NO"
                return 1
                ;;
            *)
                print_warning "Please answer 'yes' or 'no' (or 'y'/'n')"
                continue
                ;;
        esac
    done
}

prompt_choice() {
    local prompt="$1"
    local options="$2"
    local var_name="$3"
    local response=""
    
    echo -e "${YELLOW}${prompt}${NC}"
    echo -e "${CYAN}Options: ${options}${NC}"
    
    while true; do
        echo -ne "${YELLOW}Enter your choice: ${NC}"
        read -r response
        
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if echo "$options" | tr '|' '\n' | grep -qx "$response"; then
            eval "$var_name='$response'"
            log "User choice for $var_name: $response"
            return 0
        else
            print_warning "Invalid option. Please choose from: $options"
        fi
    done
}

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================
validate_ssh_key() {
    local key="$1"
    
    if [ ${#key} -lt 10 ]; then
        print_warning "SSH key too short. Please enter a valid SSH public key (or press Enter to skip)."
        return 1
    fi
    
    if [[ ! "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ssh-dss) ]]; then
        print_warning "Invalid SSH key format. Key should start with ssh-rsa, ssh-ed25519, or similar."
        return 1
    fi
    
    return 0
}

validate_country_code() {
    local code="$1"
    
    if [[ ! "$code" =~ ^[A-Za-z]{2,3}$ ]]; then
        print_warning "Location should be a 2-3 letter country code (e.g., US, UK, DEU)"
        return 1
    fi
    
    return 0
}

validate_hostname() {
    local hostname="$1"
    
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_warning "Invalid hostname format"
        return 1
    fi
    
    return 0
}

validate_nym_version() {
    local version="$1"
    
    # Updated to accept various version formats:
    # nym-binaries-v1.1.0
    # nym-binaries-v2025.19-kase
    # nym-binaries-v2024.12-eclipse
    if [[ ! "$version" =~ ^nym-binaries-v[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?$ ]]; then
        print_warning "Version should start with 'nym-binaries-v' followed by version number"
        print_warning "Examples: nym-binaries-v1.1.0, nym-binaries-v2025.19-kase"
        return 1
    fi
    
    return 0
}

#=============================================================================
# STATE MANAGEMENT FUNCTIONS
#=============================================================================
save_state() {
    local key="$1"
    local value="$2"
    
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${key}=/d" "$STATE_FILE"
    fi
    
    echo "${key}=${value}" >> "$STATE_FILE"
    log "State saved: ${key}=${value}"
}

load_state() {
    local key="$1"
    
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2-
    fi
}

is_step_completed() {
    local step="$1"
    local completed=$(load_state "completed_${step}")
    
    [ "$completed" = "true" ]
}

mark_step_completed() {
    local step="$1"
    save_state "completed_${step}" "true"
    print_success "Step completed: $step"
}

#=============================================================================
# ERROR HANDLING
#=============================================================================
cleanup_on_error() {
    local exit_code=$?
    print_error "Script encountered an error (exit code: $exit_code)"
    print_info "Check log file for details: $LOG_FILE"
    print_info "You can resume the script by running it again."
    exit $exit_code
}

trap cleanup_on_error ERR

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================
check_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. Script will use sudo where necessary."
        return 0
    fi
    
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges for some operations."
        sudo -v || {
            print_error "Failed to obtain sudo privileges"
            exit 1
        }
    fi
}

check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        print_warning "This script is designed for Ubuntu. Your OS: $ID"
        if ! prompt_yes_no "Continue anyway?" "no"; then
            exit 1
        fi
    fi
    
    local version="${VERSION_ID%%.*}"
    if [ "$version" != "22" ] && [ "$version" != "24" ]; then
        print_warning "This script is tested on Ubuntu 22 and 24 LTS. Your version: $VERSION_ID"
        if ! prompt_yes_no "Continue anyway?" "no"; then
            exit 1
        fi
    fi
    
    print_success "Ubuntu version check passed: $VERSION_ID"
}

#=============================================================================
# INSTALLATION BLOCKS
#=============================================================================

#-----------------------------------------------------------------------------
# BLOCK: SSH Key Setup (Optional)
#-----------------------------------------------------------------------------
setup_ssh_key() {
    if is_step_completed "ssh_key"; then
        print_info "SSH key setup already completed. Skipping..."
        return 0
    fi
    
    print_header "SSH Key Setup (Optional)"
    
    print_info "You can add an SSH public key for secure access to this server."
    print_info "This is optional and can be skipped by pressing Enter."
    echo ""
    
    local ssh_key=""
    prompt_user "Enter the public SSH key to add (or press Enter to skip): " ssh_key "optional" "validate_ssh_key"
    
    if [ -n "$ssh_key" ]; then
        print_step "Adding SSH key to authorized_keys..."
        
        mkdir -p "$HOME/.ssh"
        
        if [ -f "$HOME/.ssh/authorized_keys" ] && grep -qF "$ssh_key" "$HOME/.ssh/authorized_keys"; then
            print_warning "This SSH key is already in authorized_keys. Skipping..."
        else
            echo "$ssh_key" >> "$HOME/.ssh/authorized_keys"
            chmod 600 "$HOME/.ssh/authorized_keys"
            chmod 700 "$HOME/.ssh"
            print_success "SSH key added successfully"
        fi
        
        save_state "ssh_key_added" "yes"
    else
        print_info "No SSH key provided. Skipping SSH key setup."
        save_state "ssh_key_added" "no"
    fi
    
    mark_step_completed "ssh_key"
    print_summary "SSH key setup completed"
}

#-----------------------------------------------------------------------------
# BLOCK: System Preparation
#-----------------------------------------------------------------------------
prepare_system() {
    if is_step_completed "system_prep"; then
        print_info "System preparation already completed. Skipping..."
        return 0
    fi
    
    print_header "System Preparation"
    
    print_info "Next: Fix packages, update system, install essential tools"
    print_info "Installs: git, jq, nginx, fail2ban, snapd, speedtest, etc."
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping system preparation"
            save_state "skipped_system_prep" "yes"
            mark_step_completed "system_prep"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    print_step "Configuring dpkg and fixing broken packages..."
    sudo dpkg --configure -a
    sudo apt update -y && sudo apt upgrade -y && sudo apt --fix-broken install -y
    print_success "Package system configured"
    
    print_step "Installing essential tools and dependencies..."
    sudo apt install -y ufw git jq pkg-config libssl-dev build-essential \
                        nginx ca-certificates vnstat ncdu fail2ban
    print_success "Essential tools installed"
    
    print_step "Installing snapd and speedtest..."
    sudo apt install -y snapd
    sudo snap install speedtest
    print_success "Snapd and speedtest installed"
    
    mark_step_completed "system_prep"
    print_summary "System preparation completed: packages updated, tools installed"
}

#-----------------------------------------------------------------------------
# BLOCK: Rust Installation
#-----------------------------------------------------------------------------
install_rust() {
    if is_step_completed "rust_install"; then
        print_info "Rust installation already completed. Skipping..."
        return 0
    fi
    
    print_header "Rust Installation"
    
    print_info "Next: Install or update Rust programming language"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_rust_install" "yes"
            mark_step_completed "rust_install"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    if command -v rustc &> /dev/null; then
        print_info "Rust is already installed. Version:"
        rustc --version
        
        if prompt_yes_no "Do you want to update Rust?" "yes"; then
            print_step "Updating Rust..."
            rustup update
            print_success "Rust updated successfully"
        fi
    else
        print_step "Installing Rust..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        else
            print_error "Rust installation failed - cargo env not found"
            return 1
        fi
        
        print_step "Updating Rust..."
        rustup update
        print_success "Rust installed successfully"
    fi
    
    print_info "Rust version:"
    echo -e "${GREEN}$(rustc --version)${NC}"
    
    mark_step_completed "rust_install"
    print_summary "Rust installation completed and verified"
}

#-----------------------------------------------------------------------------
# BLOCK: File Limits Configuration
#-----------------------------------------------------------------------------
configure_file_limits() {
    if is_step_completed "file_limits"; then
        print_info "File limits already configured. Skipping..."
        return 0
    fi
    
    print_header "File Limits Configuration"
    
    print_info "Next: Configure system file descriptor limits (>= 65535)"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_file_limits" "yes"
            mark_step_completed "file_limits"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    local system_conf="/etc/systemd/system.conf"
    local needs_config=true
    
    if [ -f "$system_conf" ]; then
        print_step "Checking current configuration..."
        
        local current_limit=$(grep "^DefaultLimitNOFILE=" "$system_conf" | cut -d'=' -f2 | xargs)
        
        if [ -n "$current_limit" ]; then
            print_info "Current DefaultLimitNOFILE: $current_limit"
            
            if [ "$current_limit" -ge 65535 ]; then
                print_success "File limit already configured correctly (>= 65535)"
                needs_config=false
            else
                print_warning "Current limit ($current_limit) is below recommended (65535)"
            fi
        else
            if grep -q "^#DefaultLimitNOFILE=" "$system_conf"; then
                print_info "Found commented DefaultLimitNOFILE setting"
            fi
        fi
    fi
    
    if [ "$needs_config" = true ]; then
        print_step "Setting DefaultLimitNOFILE=65535..."
        
        sudo sed -i '/^#*DefaultLimitNOFILE=/d' "$system_conf"
        
        echo "DefaultLimitNOFILE=65535" | sudo tee -a "$system_conf" > /dev/null
        
        print_step "Reloading systemd daemon..."
        sudo systemctl daemon-reload
        
        print_success "File limits configured: DefaultLimitNOFILE=65535"
    fi
    
    mark_step_completed "file_limits"
    print_summary "File limits configuration completed"
}

#-----------------------------------------------------------------------------
# BLOCK: Environment Variables Setup
#-----------------------------------------------------------------------------
setup_environment_variables() {
    if is_step_completed "env_vars"; then
        print_info "Environment variables already configured. Skipping..."
        return 0
    fi
    
    print_header "Environment Variables Setup"
    
    print_info "Next: Configure Nym node ID and Rust environment"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_env_vars" "yes"
            mark_step_completed "env_vars"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    local bash_profile="$HOME/.bash_profile"
    local needs_nym_var=true
    local needs_cargo_env=true
    
    if [ -f "$bash_profile" ]; then
        print_info "Found existing .bash_profile"
        echo ""
        
        if grep -q "^export nym_node_id=" "$bash_profile"; then
            local existing_id=$(grep "^export nym_node_id=" "$bash_profile" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
            
            echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC} ${BOLD}Current NYM configuration:${NC}"
            echo -e "${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}   nym_node_id: ${GREEN}$existing_id${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            
            if prompt_yes_no "Keep this configuration?" "yes"; then
                export nym_node_id="$existing_id"
                save_state "nym_node_id" "$existing_id"
                needs_nym_var=false
                print_success "Using existing nym_node_id: $existing_id"
            else
                print_info "Will request new nym_node_id..."
            fi
        fi
        
        if grep -q "source \$HOME/.cargo/env" "$bash_profile" || grep -q 'source $HOME/.cargo/env' "$bash_profile"; then
            needs_cargo_env=false
            print_info "Cargo environment already configured in .bash_profile"
        fi
    else
        print_info "Creating new .bash_profile"
        touch "$bash_profile"
    fi
    
    if [ "$needs_cargo_env" = true ]; then
        print_step "Adding Rust cargo environment to .bash_profile..."
        echo "source \$HOME/.cargo/env" >> "$bash_profile"
        print_success "Cargo environment added"
    fi
    
    if [ "$needs_nym_var" = true ]; then
        echo ""
        print_info "Setting up NYM node configuration..."
        
        local nym_node_id=""
        prompt_user "Enter your Nym node ID: " nym_node_id "required"
        
        sed -i '/^# NYM$/,/^export nym_node_id=/d' "$bash_profile"
        
        {
            echo ""
            echo "# NYM"
            echo "export nym_node_id=$nym_node_id"
        } >> "$bash_profile"
        
        export nym_node_id
        save_state "nym_node_id" "$nym_node_id"
        
        print_success "NYM node ID configured: $nym_node_id"
    fi
    
    source "$bash_profile"
    
    mark_step_completed "env_vars"
    print_summary "Environment variables configured in .bash_profile"
}

#-----------------------------------------------------------------------------
# BLOCK: Build/Download Nym-Node Binary
#-----------------------------------------------------------------------------
handle_nym_binary() {
    if is_step_completed "nym_binary"; then
        print_info "Nym-node binary already installed. Skipping..."
        
        if command -v nym-node &> /dev/null; then
            print_info "Current nym-node version:"
            nym-node build-info | grep -E "Build Version|Commit SHA"
            return 0
        else
            print_warning "Binary was marked as installed but not found. Re-running installation..."
            save_state "completed_nym_binary" "false"
        fi
    fi
    
    print_header "Nym-Node Binary Installation"
    
    # Check if binary already exists
    if [ -f "/usr/local/bin/nym-node" ]; then
        print_info "Existing nym-node binary found"
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Current Binary Information:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        /usr/local/bin/nym-node build-info | grep -E "Build Version|Commit SHA"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if prompt_yes_no "Use this existing binary?" "yes"; then
            save_state "NYM_VERSION" "existing"
            mark_step_completed "nym_binary"
            print_summary "Using existing nym-node binary from /usr/local/bin"
            return 0
        fi
    fi
    
    echo ""
    print_info "You can either:"
    print_info "  [B] Build from source (takes longer, always up-to-date)"
    print_info "  [D] Download pre-built binary (faster)"
    print_info "  [Enter] Skip (if already installed)"
    echo ""
    
    local choice=""
    local NYM_VERSION=""
    
    while true; do
        echo -ne "${YELLOW}Choose installation method [B/D/Enter to skip]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            print_step "Checking for existing nym-node binary..."
            
            if [ -f "/usr/local/bin/nym-node" ]; then
                print_success "Found nym-node in /usr/local/bin"
                /usr/local/bin/nym-node build-info | grep -E "Build Version|Commit SHA"
                
                if prompt_yes_no "Is this the correct version?" "yes"; then
                    save_state "NYM_VERSION" "existing"
                    mark_step_completed "nym_binary"
                    print_summary "Using existing nym-node binary from /usr/local/bin"
                    return 0
                else
                    print_info "Let's install the correct version..."
                    continue
                fi
            fi
            
            if [ -f "$HOME/nym-node" ]; then
                print_success "Found nym-node in $HOME"
                "$HOME/nym-node" build-info | grep -E "Build Version|Commit SHA"
                
                if prompt_yes_no "Is this the correct version?" "yes"; then
                    print_step "Moving to /usr/local/bin..."
                    sudo mv "$HOME/nym-node" /usr/local/bin/nym-node
                    print_success "Moved to /usr/local/bin/nym-node"
                    
                    save_state "NYM_VERSION" "existing"
                    mark_step_completed "nym_binary"
                    print_summary "Using existing nym-node binary, moved to /usr/local/bin"
                    return 0
                else
                    print_info "Let's install the correct version..."
                    continue
                fi
            fi
            
            print_error "nym-node binary not found in /usr/local/bin/ or \$HOME"
            print_warning "Cannot continue without nym-node binary."
            echo ""
            print_info "Please choose Build or Download option."
            continue
        fi
        
        if [ "$choice" = "d" ]; then
            download_nym_binary
            if [ $? -eq 0 ]; then
                return 0
            else
                print_warning "Download failed or version incorrect. Try again."
                continue
            fi
        fi
        
        if [ "$choice" = "b" ]; then
            build_nym_binary
            if [ $? -eq 0 ]; then
                return 0
            else
                print_warning "Build failed or version incorrect. Try again."
                continue
            fi
        fi
        
        print_warning "Invalid choice. Please enter 'B' for build, 'D' for download, or press Enter to skip."
    done
}

#-----------------------------------------------------------------------------
# Helper: Detect Latest Release from GitHub
#-----------------------------------------------------------------------------
detect_latest_release() {
    local latest_release=""
    
    # Fetch latest release using GitHub API (silently)
    if command -v curl &> /dev/null; then
        latest_release=$(curl -s https://api.github.com/repos/nymtech/nym/releases/latest 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    
    # Validate the release format
    if [ -n "$latest_release" ] && [[ "$latest_release" =~ ^nym-binaries-v[0-9]+\.[0-9]+ ]]; then
        # Return ONLY the version, no output to screen
        echo "$latest_release"
        return 0
    else
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Helper: Download Nym Binary
#-----------------------------------------------------------------------------
download_nym_binary() {
    print_step "Download mode selected"
    echo ""
    
    local NYM_VERSION=""
    local use_latest=false
    local max_retries=3
    local retry_count=0
    
    # Try to detect latest release
    print_step "Detecting latest Nym release from GitHub..."
    local latest_release=$(detect_latest_release)
    
    if [ -n "$latest_release" ]; then
        print_success "Latest release detected: ${GREEN}$latest_release${NC}"
        echo ""
        if prompt_yes_no "Use latest release: ${GREEN}$latest_release${NC}?" "yes"; then
            NYM_VERSION="$latest_release"
            use_latest=true
        fi
    else
        print_warning "Could not auto-detect latest release"
    fi
    
    while true; do
        # If not using auto-detected latest, ask for version
        if [ "$use_latest" = false ] || [ -z "$NYM_VERSION" ]; then
            print_info "Enter the Nym version you want to download"
            print_info "Examples: nym-binaries-v1.1.0, nym-binaries-v2025.19-kase"
            echo ""
            
            prompt_user "Enter Nym version: " NYM_VERSION "required" "validate_nym_version"
        fi
        
        retry_count=0
        while [ $retry_count -lt $max_retries ]; do
            print_step "Downloading nym-node version: $NYM_VERSION (Attempt $((retry_count + 1))/$max_retries)"
            
            cd "$HOME" || {
                print_error "Failed to change to home directory"
                return 1
            }
            
            [ -f "$HOME/nym-node" ] && rm -f "$HOME/nym-node"
            
            local download_url="https://github.com/nymtech/nym/releases/download/$NYM_VERSION/nym-node"
            
            if curl -L -o "$HOME/nym-node" "$download_url"; then
                print_success "Download completed"
                break
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    print_warning "Download failed. Retrying in 3 seconds..."
                    sleep 3
                else
                    print_error "Failed to download after $max_retries attempts"
                    echo ""
                    print_info "Options:"
                    echo -e "  ${YELLOW}[D]${NC} - Try downloading again"
                    echo -e "  ${YELLOW}[B]${NC} - Build from source instead"
                    echo -e "  ${YELLOW}[V]${NC} - Try different version"
                    echo -e "  ${YELLOW}[Q]${NC} - Quit"
                    echo ""
                    
                    local choice=""
                    echo -ne "${YELLOW}Your choice [D/B/V/Q]: ${NC}"
                    read -r choice
                    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
                    
                    case "$choice" in
                        d)
                            retry_count=0
                            continue
                            ;;
                        b)
                            return 2  # Signal to try build
                            ;;
                        v)
                            use_latest=false
                            NYM_VERSION=""
                            continue 2
                            ;;
                        q)
                            return 1
                            ;;
                        *)
                            print_warning "Invalid choice"
                            return 1
                            ;;
                    esac
                fi
            fi
        done
        
        if [ -f "$HOME/nym-node" ]; then
            chmod u+x "$HOME/nym-node"
            
            print_step "Verifying downloaded binary..."
            echo ""
            echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC} ${BOLD}Build Information:${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
            
            "$HOME/nym-node" build-info
            
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            if prompt_yes_no "Is this build information correct?" "yes"; then
                print_step "Moving binary to /usr/local/bin/..."
                
                sudo mv "$HOME/nym-node" /usr/local/bin/nym-node || {
                    print_error "Failed to move binary to /usr/local/bin/"
                    return 1
                }
                
                print_success "Binary moved to /usr/local/bin/nym-node"
                
                if command -v nym-node &> /dev/null; then
                    print_success "nym-node is now available in PATH"
                else
                    print_warning "nym-node might not be in PATH, but is installed at /usr/local/bin/nym-node"
                fi
                
                save_state "NYM_VERSION" "$NYM_VERSION"
                mark_step_completed "nym_binary"
                print_summary "Nym-node binary downloaded and installed: $NYM_VERSION"
                return 0
            else
                print_info "Let's try a different version..."
                rm -f "$HOME/nym-node"
                use_latest=false
                NYM_VERSION=""
                continue
            fi
        fi
    done
}

#-----------------------------------------------------------------------------
# Helper: Build Nym Binary from Source
#-----------------------------------------------------------------------------
build_nym_binary() {
    print_step "Build mode selected"
    echo ""
    
    print_warning "Building from source may take 2-30 minutes depending on your server."
    if ! prompt_yes_no "Continue with build from source?" "yes"; then
        return 1
    fi
    
    local NYM_VERSION=""
    local use_latest=false
    
    # Ensure Rust is available
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    else
        print_error "Rust cargo environment not found at $HOME/.cargo/env"
        print_info "Please ensure Rust is properly installed"
        return 1
    fi
    
    print_step "Updating Rust toolchain..."
    rustup update
    print_success "Rust toolchain updated"
    
    # Try to detect latest release
    print_step "Detecting latest Nym release from GitHub..."
    local latest_release=$(detect_latest_release)
    
    if [ -n "$latest_release" ]; then
        print_success "Latest release detected: ${GREEN}$latest_release${NC}"
        echo ""
        if prompt_yes_no "Use latest release: ${GREEN}$latest_release${NC}?" "yes"; then
            NYM_VERSION="$latest_release"
            use_latest=true
        fi
    else
        print_warning "Could not auto-detect latest release"
    fi
    
    while true; do
        # If not using auto-detected latest, ask for version
        if [ "$use_latest" = false ] || [ -z "$NYM_VERSION" ]; then
            print_info "Enter the Nym version you want to build"
            print_info "Examples: nym-binaries-v1.1.0, nym-binaries-v2025.19-kase"
            echo ""
            
            prompt_user "Enter Nym version: " NYM_VERSION "required" "validate_nym_version"
        fi
        
        cd "$HOME" || {
            print_error "Failed to change to home directory"
            return 1
        }
        
        if [ -d "$HOME/nym" ]; then
            print_step "Removing old nym source directory..."
            rm -rf "$HOME/nym"
        fi
        
        print_step "Cloning Nym repository (this may take a few minutes)..."
        if ! git clone https://github.com/nymtech/nym.git; then
            print_error "Failed to clone Nym repository"
            
            echo ""
            print_info "Options:"
            echo -e "  ${YELLOW}[R]${NC} - Retry cloning"
            echo -e "  ${YELLOW}[D]${NC} - Download binary instead"
            echo -e "  ${YELLOW}[Q]${NC} - Quit"
            echo ""
            
            local choice=""
            echo -ne "${YELLOW}Your choice [R/D/Q]: ${NC}"
            read -r choice
            choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
            
            case "$choice" in
                r) continue ;;
                d) return 2 ;;
                *) return 1 ;;
            esac
        fi
        print_success "Repository cloned"
        
        cd "$HOME/nym" || {
            print_error "Failed to enter nym directory"
            return 1
        }
        
        print_step "Checking out version: $NYM_VERSION"
        if ! git checkout "$NYM_VERSION" 2>&1; then
            print_error "Failed to checkout version: $NYM_VERSION"
            print_warning "This version tag might not exist in the repository."
            
            echo ""
            print_info "Options:"
            echo -e "  ${YELLOW}[V]${NC} - Try different version"
            echo -e "  ${YELLOW}[D]${NC} - Download binary instead"
            echo -e "  ${YELLOW}[Q]${NC} - Quit"
            echo ""
            
            local choice=""
            echo -ne "${YELLOW}Your choice [V/D/Q]: ${NC}"
            read -r choice
            choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
            
            case "$choice" in
                v)
                    cd "$HOME" || return 1
                    rm -rf "$HOME/nym"
                    use_latest=false
                    NYM_VERSION=""
                    continue
                    ;;
                d)
                    cd "$HOME" || return 1
                    rm -rf "$HOME/nym"
                    return 2
                    ;;
                *)
                    return 1
                    ;;
            esac
        fi
        print_success "Version checked out: $NYM_VERSION"
        
        print_step "Building nym-node (this will take 15-30 minutes)..."
        print_info "You can monitor the progress below..."
        echo ""
        
        if ! cargo build --release --bin nym-node; then
            print_error "Build failed!"
            print_info "Check the error messages above."
            
            echo ""
            print_info "Options:"
            echo -e "  ${YELLOW}[R]${NC} - Retry build"
            echo -e "  ${YELLOW}[V]${NC} - Try different version"
            echo -e "  ${YELLOW}[D]${NC} - Download binary instead"
            echo -e "  ${YELLOW}[Q]${NC} - Quit"
            echo ""
            
            local choice=""
            echo -ne "${YELLOW}Your choice [R/V/D/Q]: ${NC}"
            read -r choice
            choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
            
            case "$choice" in
                r) continue ;;
                v)
                    cd "$HOME" || return 1
                    rm -rf "$HOME/nym"
                    use_latest=false
                    NYM_VERSION=""
                    continue
                    ;;
                d)
                    cd "$HOME" || return 1
                    rm -rf "$HOME/nym"
                    return 2
                    ;;
                *)
                    return 1
                    ;;
            esac
        fi
        
        print_success "Build completed successfully!"
        
        print_step "Verifying built binary..."
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Build Information:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        
        "$HOME/nym/target/release/nym-node" build-info
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if prompt_yes_no "Is this build information correct?" "yes"; then
            print_step "Moving binary to /usr/local/bin/..."
            
            sudo mv "$HOME/nym/target/release/nym-node" /usr/local/bin/nym-node || {
                print_error "Failed to move binary to /usr/local/bin/"
                return 1
            }
            
            print_success "Binary moved to /usr/local/bin/nym-node"
            
            if command -v nym-node &> /dev/null; then
                print_success "nym-node is now available in PATH"
            else
                print_warning "nym-node might not be in PATH, but is installed at /usr/local/bin/nym-node"
            fi
            
            print_step "Cleaning up build directory..."
            cd "$HOME" || return 1
            rm -rf "$HOME/nym"
            print_success "Build directory cleaned up"
            
            save_state "NYM_VERSION" "$NYM_VERSION"
            mark_step_completed "nym_binary"
            print_summary "Nym-node binary built from source and installed: $NYM_VERSION"
            return 0
        else
            print_info "Let's try building a different version..."
            cd "$HOME" || return 1
            rm -rf "$HOME/nym"
            use_latest=false
            NYM_VERSION=""
            continue
        fi
    done
}

#-----------------------------------------------------------------------------
# BLOCK: Initialize Nym Node
#-----------------------------------------------------------------------------
initialize_nym_node() {
    if is_step_completed "nym_init"; then
        print_info "Nym node already initialized. Skipping..."
        return 0
    fi
    
    print_header "Nym Node Initialization"
    
    print_info "Next: Initialize Nym node with mode, location, and network settings"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_nym_init" "yes"
            mark_step_completed "nym_init"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    local nym_node_id=$(load_state "nym_node_id")
    
    if [ -z "$nym_node_id" ]; then
        print_error "nym_node_id not found in state. This should not happen."
        print_info "Please run the script again from the beginning."
        exit 1
    fi
    
    print_info "Node ID: ${GREEN}$nym_node_id${NC}"
    echo ""
    
    local LOCATION=""
    print_info "Enter your server location (2-3 letter country code)"
    print_info "Examples: US, UK, DE, DEU, FR, JP"
    prompt_user "Enter location: " LOCATION "required" "validate_country_code"
    save_state "LOCATION" "$LOCATION"
    
    local NYMMODE=""
    echo ""
    print_info "Select Nym node mode:"
    print_info "  • exit-gateway  - Exit gateway with WireGuard"
    print_info "  • entry-gateway - Entry gateway with WireGuard"
    print_info "  • mixnode       - Mix node (no WireGuard)"
    echo ""
    
    prompt_choice "Select mode:" "exit-gateway|entry-gateway|mixnode" NYMMODE
    save_state "NYMMODE" "$NYMMODE"
    
    local HOSTNAME=""
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        echo ""
        print_info "Enter the hostname for your gateway"
        print_info "This should be a domain name pointing to this server"
        print_info "Example: gateway.example.com"
        prompt_user "Enter hostname: " HOSTNAME "required" "validate_hostname"
        save_state "HOSTNAME" "$HOSTNAME"
    fi
    
    print_step "Detecting public IP address..."
    local PUBLIC_IP=$(curl -4 -s https://ifconfig.me)
    
    if [ -z "$PUBLIC_IP" ]; then
        print_error "Failed to detect public IP address"
        prompt_user "Please enter your public IPv4 address manually: " PUBLIC_IP "required"
    else
        print_success "Detected public IP: $PUBLIC_IP"
    fi
    
    save_state "PUBLIC_IP" "$PUBLIC_IP"
    
    echo ""
    print_step "Initializing Nym node..."
    print_info "Mode: ${GREEN}$NYMMODE${NC}"
    print_info "Location: ${GREEN}$LOCATION${NC}"
    print_info "Public IP: ${GREEN}$PUBLIC_IP${NC}"
    if [ -n "$HOSTNAME" ]; then
        print_info "Hostname: ${GREEN}$HOSTNAME${NC}"
    fi
    echo ""
    
    local init_cmd=""
    
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        init_cmd="nym-node run --id $nym_node_id --init-only --mode $NYMMODE \
                  --public-ips \"$PUBLIC_IP\" --hostname $HOSTNAME \
                  --location $LOCATION --accept-operator-terms-and-conditions \
                  --wireguard-enabled true"
    elif [ "$NYMMODE" = "mixnode" ]; then
        init_cmd="nym-node run --mode $NYMMODE --id $nym_node_id --init-only \
                  --public-ips \"$PUBLIC_IP\" --location $LOCATION \
                  --accept-operator-terms-and-conditions"
    else
        print_error "Invalid mode: $NYMMODE"
        return 1
    fi
    
    if eval "$init_cmd"; then
        print_success "Nym node initialized successfully!"
    else
        print_error "Failed to initialize Nym node"
        print_info "Check the error messages above"
        
        if prompt_yes_no "Try again with different parameters?" "yes"; then
            save_state "completed_nym_init" "false"
            initialize_nym_node
            return $?
        else
            return 1
        fi
    fi
    
    mark_step_completed "nym_init"
    print_summary "Nym node initialized: Mode=$NYMMODE, Location=$LOCATION"
}

#-----------------------------------------------------------------------------
# BLOCK: Setup Description.toml
#-----------------------------------------------------------------------------
setup_description() {
    if is_step_completed "description"; then
        print_info "Description already configured. Skipping..."
        return 0
    fi
    
    print_header "Node Description Configuration"
    
    print_info "Next: Configure your node's public description (visible in explorer)"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_description" "yes"
            mark_step_completed "description"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    local nym_node_id=$(load_state "nym_node_id")
    local description_file="$HOME/.nym/nym-nodes/$nym_node_id/data/description.toml"
    
    if [ -f "$description_file" ]; then
        print_info "Found existing description.toml file"
        echo ""
        
        local has_content=false
        if grep -q '=' "$description_file" && grep -q '= *"[^"]' "$description_file"; then
            has_content=true
        fi
        
        if [ "$has_content" = true ]; then
            echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC} ${BOLD}Current description.toml:${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"
                    echo -e "  ${YELLOW}${key}${NC}=${GREEN}${value}${NC}"
                else
                    echo "  $line"
                fi
            done < "$description_file"
            
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            if ! prompt_yes_no "Do you want to overwrite this description?" "no"; then
                print_info "Keeping existing description"
                mark_step_completed "description"
                print_summary "Using existing node description"
                return 0
            fi
            
            print_info "Will create new description..."
        fi
    fi
    
    local moniker=""
    local website=""
    local security_contact=""
    local details=""
    
    while true; do
        echo ""
        print_step "Enter node description details:"
        echo ""
        
        prompt_user "  Moniker (node name): " moniker "required"
        prompt_user "  Website (e.g., https://example.com): " website "optional"
        prompt_user "  Security contact (email): " security_contact "optional"
        prompt_user "  Details (description of your node): " details "optional"
        
        print_step "Creating description.toml..."
        
        mkdir -p "$(dirname "$description_file")"
        
        cat > "$description_file" << EOF
moniker = "$moniker"
website = "$website"
security_contact = "$security_contact"
details = "$details"
EOF
        
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Generated description.toml:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                echo -e "  ${YELLOW}${key}${NC}=${GREEN}${value}${NC}"
            else
                echo "  $line"
            fi
        done < "$description_file"
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if prompt_yes_no "Is this correct?" "yes"; then
            print_success "Description saved to: $description_file"
            break
        else
            print_info "Let's try again..."
        fi
    done
    
    mark_step_completed "description"
    print_summary "Node description configured"
}

#-----------------------------------------------------------------------------
# BLOCK: Configure config.toml
#-----------------------------------------------------------------------------
configure_config_toml() {
    if is_step_completed "config_toml"; then
        print_info "config.toml already configured. Skipping..."
        return 0
    fi
    
    print_header "Configuration File Setup"
    
    print_info "Next: Configure landing page and WebSocket settings"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_config_toml" "yes"
            mark_step_completed "config_toml"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    local nym_node_id=$(load_state "nym_node_id")
    local HOSTNAME=$(load_state "HOSTNAME")
    local config_file="$HOME/.nym/nym-nodes/$nym_node_id/config/config.toml"
    
    if [ ! -f "$config_file" ]; then
        print_error "config.toml not found at: $config_file"
        print_error "Node initialization might have failed"
        return 1
    fi
    
    print_step "Creating backup of config.toml..."
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    print_success "Backup created"
    
    local NYMMODE=$(load_state "NYMMODE")
    
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        print_step "Setting landing page assets path..."
        
        if grep -q "^landing_page_assets_path = " "$config_file"; then
            sed -i "s|^landing_page_assets_path = .*|landing_page_assets_path = '/var/www/$HOSTNAME/index.html'|" "$config_file"
            print_success "Updated existing landing_page_assets_path"
        elif grep -q "^#landing_page_assets_path = " "$config_file"; then
            sed -i "s|^#landing_page_assets_path = .*|landing_page_assets_path = '/var/www/$HOSTNAME/index.html'|" "$config_file"
            print_success "Uncommented and set landing_page_assets_path"
        else
            print_warning "landing_page_assets_path not found, might need manual configuration"
        fi
        
        print_info "Landing page: ${GREEN}/var/www/$HOSTNAME/index.html${NC}"
    fi
    
    print_step "Setting WebSocket announcement port..."
    
    if grep -q "^announce_wss_port = " "$config_file"; then
        sed -i "s|^announce_wss_port = .*|announce_wss_port = 9001|" "$config_file"
        print_success "Updated existing announce_wss_port"
    elif grep -q "^#announce_wss_port = " "$config_file"; then
        sed -i "s|^#announce_wss_port = .*|announce_wss_port = 9001|" "$config_file"
        print_success "Uncommented and set announce_wss_port"
    else
        print_warning "announce_wss_port not found, might need manual configuration"
    fi
    
    print_info "WebSocket port: ${GREEN}9001${NC}"
    
    echo ""
    print_step "Verifying configuration changes..."
    
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        if grep -q "landing_page_assets_path = '/var/www/$HOSTNAME/index.html'" "$config_file"; then
            print_success "✓ landing_page_assets_path configured correctly"
        else
            print_warning "⚠ landing_page_assets_path might need manual check"
        fi
    fi
    
    if grep -q "announce_wss_port = 9001" "$config_file"; then
        print_success "✓ announce_wss_port configured correctly"
    else
        print_warning "⚠ announce_wss_port might need manual check"
    fi
    
    mark_step_completed "config_toml"
    print_summary "Configuration file updated: landing page path and WSS port"
}

#-----------------------------------------------------------------------------
# BLOCK: Network Tunnel Manager
#-----------------------------------------------------------------------------
setup_network_tunnel_manager() {
    if is_step_completed "network_tunnel"; then
        print_info "Network tunnel manager already configured. Skipping..."
        return 0
    fi
    
    print_header "Network Tunnel Manager Setup"

    local NYMMODE=$(load_state "NYMMODE")
    
    if [ "$NYMMODE" = "mixnode" ]; then
        print_info "Network tunnel manager is only needed for gateway modes"
        print_info "Current mode: ${YELLOW}$NYMMODE${NC} - Skipping..."
        mark_step_completed "network_tunnel"
        print_summary "Network tunnel manager skipped (not needed for mixnode)"
        return 0
    fi

    print_info "Next: Configure network tunneling and WireGuard exit policy"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_network_tunnel" "yes"
            mark_step_completed "network_tunnel"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    cd "$HOME" || {
        print_error "Failed to change to home directory"
        return 1
    }
    
    print_step "Downloading network tunnel manager script..."
    
    # Force overwrite using curl -o
    if ! curl -L -o network-tunnel-manager.sh https://raw.githubusercontent.com/nymtech/nym/refs/heads/develop/scripts/nym-node-setup/network-tunnel-manager.sh; then
        print_error "Failed to download network tunnel manager script"
        return 1
    fi
    
    chmod +x network-tunnel-manager.sh
    print_success "Network tunnel manager script downloaded"
    
    echo ""
    print_step "Running network tunnel configuration commands..."
    print_warning "This will modify system network settings"
    echo ""
    
    local commands=(
        "complete_networking_configuration:Full tunneling and exit policy setup"
    )
    
    for cmd_info in "${commands[@]}"; do
        IFS=':' read -r cmd desc <<< "$cmd_info"
        
        echo -e "${MAGENTA}▶ $desc...${NC}"
        
        if ./network-tunnel-manager.sh $cmd; then
            echo -e "  ${GREEN}✅ Success${NC}"
        else
            print_warning "Command might have failed: $cmd"
            print_info "Continuing anyway..."
        fi
    done
    
    print_success "Network tunnel manager configuration completed"
    
    mark_step_completed "network_tunnel"
    print_summary "Network tunneling and WireGuard exit policy configured"
}

#-----------------------------------------------------------------------------
# BLOCK: QUIC Transport Bridge Deployment
#-----------------------------------------------------------------------------
setup_quic_bridge() {
    if is_step_completed "quic_bridge"; then
        print_info "QUIC transport bridge already configured. Skipping..."
        return 0
    fi
    
    print_header "QUIC Transport Bridge Deployment"
    
    print_info "Next: Brief description of what this block does"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_quic_bridge" "yes"
            mark_step_completed "quic_bridge"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    local NYMMODE=$(load_state "NYMMODE")
    
    if [ "$NYMMODE" = "mixnode" ]; then
        print_info "QUIC bridge is only needed for gateway modes"
        print_info "Current mode: ${YELLOW}$NYMMODE${NC} - Skipping..."
        mark_step_completed "quic_bridge"
        print_summary "QUIC bridge skipped (not needed for mixnode)"
        return 0
    fi
    
    print_info "Next: Deploy QUIC transport bridge (interactive setup)"
    print_warning "This script will ask you to confirm each step"
    echo ""
    print_info "Press ${GREEN}Enter${NC} to continue..."
    read -r
    
    cd "$HOME" || {
        print_error "Failed to change to home directory"
        return 1
    }
    
    print_step "Downloading QUIC bridge deployment script..."
    
    # Force overwrite using curl -o
    if ! curl -L -o quic_bridge_deployment.sh https://raw.githubusercontent.com/nymtech/nym/refs/heads/develop/scripts/nym-node-setup/quic_bridge_deployment.sh; then
        print_error "Failed to download QUIC bridge deployment script"
        return 1
    fi
    
    chmod +x quic_bridge_deployment.sh
    print_success "QUIC bridge deployment script downloaded"
    
    echo ""
    print_step "Starting QUIC bridge setup (interactive)..."
    print_info "The script will ask you to confirm each step"
    echo ""
    
    # Pass control to the QUIC bridge script
    if ./quic_bridge_deployment.sh full_bridge_setup; then
        print_success "QUIC bridge deployment completed successfully"
    else
        print_warning "QUIC bridge deployment encountered issues"
        print_info "Check the output above for details"
        
        if ! prompt_yes_no "Continue with installation despite QUIC bridge issues?" "yes"; then
            return 1
        fi
    fi
    
    mark_step_completed "quic_bridge"
    print_summary "QUIC transport bridge configured"
}

#-----------------------------------------------------------------------------
# BLOCK: UFW Status Check
#-----------------------------------------------------------------------------
check_ufw_status() {
    if is_step_completed "ufw_check"; then
        print_info "UFW check already completed. Skipping..."
        return 0
    fi
    
    print_header "Firewall (UFW) Status Check"
    
    print_info "Next: Check firewall status and display required ports"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_ufw_check" "yes"
            mark_step_completed "ufw_check"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    if ! command -v ufw &> /dev/null; then
        print_warning "UFW is not installed"
        
        if prompt_yes_no "Do you want to install UFW?" "yes"; then
            print_step "Installing UFW..."
            safe_execute "Installing UFW firewall" "sudo apt install -y ufw"
            print_success "UFW installed"
        else
            print_info "Skipping UFW installation"
            mark_step_completed "ufw_check"
            return 0
        fi
    else
        print_success "UFW is installed"
    fi
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}UFW Status:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    sudo ufw status numbered
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if sudo ufw status | grep -q "Status: active"; then
        print_info "UFW is ${GREEN}ENABLED${NC}"
    else
        print_info "UFW is ${YELLOW}DISABLED${NC}"
        print_warning "Note: UFW is not currently protecting your server"
    fi
    
    echo ""
    print_info "Important ports for Nym node:"
    echo -e "  ${YELLOW}•${NC} 1789  - Mix node traffic"
    echo -e "  ${YELLOW}•${NC} 1790  - Mix node verloc"
    echo -e "  ${YELLOW}•${NC} 8080  - HTTP API"
    echo -e "  ${YELLOW}•${NC} 9000  - WebSocket (mixnet)"
    echo -e "  ${YELLOW}•${NC} 9001  - WebSocket (announced)"
    
    local NYMMODE=$(load_state "NYMMODE")
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        echo -e "  ${YELLOW}•${NC} 51822 - WireGuard"
        echo -e "  ${YELLOW}•${NC} 4443  - QUIC transport (UDP)"
    fi
    
    echo ""
    print_warning "Make sure these ports are allowed in your firewall!"
    print_info "You can configure UFW rules later based on your needs"
    
    echo ""
    if prompt_yes_no "Do you want to see UFW rule suggestions?" "no"; then
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Suggested UFW Commands:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${YELLOW}# Allow SSH \e[31m(change 22 to your SSH port)\e[0m ${NC}"
        echo -e "  sudo ufw allow 22/tcp"
        echo ""
        echo -e "  ${YELLOW}# Allow Nym ports${NC}"
        echo -e "  sudo ufw allow 1789/tcp"
        echo -e "  sudo ufw allow 1790/tcp"
        echo -e "  sudo ufw allow 8080/tcp"
        echo -e "  sudo ufw allow 9000/tcp"
        echo -e "  sudo ufw allow 9001/tcp"
        
        if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
            echo ""
            echo -e "  ${YELLOW}# Allow WireGuard (for gateways)${NC}"
            echo -e "  sudo ufw allow 51822/udp"
            echo -e "  ${YELLOW}# Allow QUIC transport (for gateways)${NC}"
            echo -e "  sudo ufw allow 4443/udp"
        fi
        
        echo ""
        echo -e "  ${YELLOW}# Enable UFW${NC}"
        echo -e "  sudo ufw enable"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
    
    mark_step_completed "ufw_check"
    print_summary "UFW status checked - configure firewall rules as needed"
}

################################################################################
# BLOCK: Reverse Proxy & WSS Configuration (Optional)
################################################################################

block_web_gateway_setup() {
    # Check if this block is needed for current mode
    local NYMMODE=$(load_state "NYMMODE")
    
    if [[ "$NYMMODE" == "mixnode" ]]; then
        print_header "Reverse Proxy & WSS Configuration"
        print_info "Reverse Proxy & WSS Configuration is only needed for gateway modes (exit-gateway, entry-gateway)"
        print_info "Current mode: ${YELLOW}$NYMMODE${NC} - Skipping..."
        print_summary "Reverse Proxy & WSS Configuration skipped (not needed for mixnode)"
        return 0
    fi
    
    if !  ask_continue "Reverse Proxy & WSS Configuration (Nginx + SSL + WSS)" \
        "Launch nym-web-gateway-setup.sh for reverse proxy and WebSocket Secure setup"; then
        return 0
    fi
    
    local web_script="nym-web-gateway-setup.sh"
    local scripts_dir="$HOME/scripts/nym-scripts"
    local web_script_path="$scripts_dir/$web_script"
    local download_url="https://raw.githubusercontent.com/toolfun/Scripts/main/Nym/nym-web-gateway-setup.sh"
    
    # Create scripts directory if it doesn't exist
    if [[ ! -d "$scripts_dir" ]]; then
        print_info "Creating scripts directory: $scripts_dir"
        mkdir -p "$scripts_dir"
    fi
    
    # Main logic: try to download first, then fallback to existing
    local script_ready=false
    
    while [[ "$script_ready" == false ]]; do
        
        # Step 1: Try to download the latest version
        print_step "Downloading latest version of $web_script..."
        print_info "URL: $download_url"
        
        if curl --fail -L --progress-bar "$download_url" -o "$web_script_path"; then
            chmod +x "$web_script_path"
            print_success "Script downloaded successfully: $web_script_path"
            script_ready=true
        else
            print_error "Failed to download $web_script"
            echo ""
            
            # Step 2: Check if local copy exists
            if [[ -f "$web_script_path" ]]; then
                print_warning "Found existing local copy: $web_script_path"
                echo ""
                
                if prompt_yes_no "Use existing local copy instead?" "yes"; then
                    print_info "Using existing local copy"
                    script_ready=true
                else
                    print_info "Will not use existing copy"
                fi
            fi
            
            # Step 3: If still not ready, ask user what to do
            if [[ "$script_ready" == false ]]; then
                echo ""
                print_warning "Cannot proceed without $web_script"
                echo ""
                echo -e "${YELLOW}Options:${NC}"
                echo -e "  ${GREEN}[R]${NC} - Retry download"
                echo -e "  ${GREEN}[S]${NC} - Skip Reverse Proxy & WSS Configuration (not recommended)"
                echo -e "  ${GREEN}[Q]${NC} - Quit installation"
                echo ""
                
                local choice=""
                while true; do
                    echo -ne "${YELLOW}Your choice [R/S/Q]: ${NC}"
                    read -r choice
                    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
                    
                    case "$choice" in
                        r)
                            print_info "Retrying download..."
                            echo ""
                            break  # Break inner loop, continue outer while loop
                            ;;
                        s)
                            print_warning "Skipping Reverse Proxy & WSS Configuration"
                            print_warning "Your node will work, but WSS and reverse proxy will NOT be configured!"
                            print_warning "You can run $web_script manually later from: $scripts_dir"
                            echo ""
                            return 0
                            ;;
                        q)
                            print_error "Installation aborted by user"
                            exit 1
                            ;;
                        *)
                            print_warning "Invalid choice.  Please enter R, S, or Q."
                            ;;
                    esac
                done
            fi
        fi
    done
    
    # At this point, script is ready to execute
    
    # Load and export variables for the child script
    export nym_node_id=$(load_state "nym_node_id")
    export HOSTNAME=$(load_state "HOSTNAME")
    
    # Verify nym_node_id is not empty
    if [[ -z "$nym_node_id" ]]; then
        print_error "nym_node_id is empty!  Cannot proceed with Reverse Proxy & WSS Configuration."
        print_info "This variable should have been set in 'Environment Variables Setup' step."
        print_info "Please restart the installation or set nym_node_id manually."
        return 1
    fi
    
    # Verify HOSTNAME is not empty (required for gateway modes)
    if [[ -z "$HOSTNAME" ]]; then
        print_error "HOSTNAME is empty! Cannot proceed with Reverse Proxy & WSS Configuration."
        print_info "This variable should have been set in 'Nym Node Initialization' step."
        print_info "Please restart the installation or set HOSTNAME manually."
        return 1
    fi
    
    print_info "Using nym_node_id: $nym_node_id"
    print_info "Using HOSTNAME: $HOSTNAME"
    
    echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  Launching Reverse Proxy & WSS Configuration Script${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}\n"
    
    print_info "Executing: sudo bash $web_script_path"
    echo -e "${YELLOW}Note: You will be returned here after completion${NC}\n"
    
    sleep 2
    
    # Execute the web gateway script
    if sudo bash "$web_script_path"; then
        echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}  Returned from Reverse Proxy & WSS Configuration${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}\n"
        print_success "Reverse Proxy & WSS Configuration completed successfully"
    else
        echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}  Returned from Reverse Proxy & WSS Configuration${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${NC}\n"
        print_warning "Reverse Proxy & WSS Configuration exited with errors or was skipped"
        
        if !  prompt_yes_no "Continue with node installation?" "yes"; then
            print_warning "Installation paused by user"
            exit 0
        fi
    fi
    
    print_info "Continuing with node installation..."
    sleep 1
}

#-----------------------------------------------------------------------------
# BLOCK: Systemd Service Setup
#-----------------------------------------------------------------------------
setup_systemd_service() {
    if is_step_completed "systemd_service"; then
        print_info "Systemd service already configured. Skipping..."
        return 0
    fi
    
    print_header "Systemd Service Setup"
    
    print_info "Next: Set up nym-node as a system service"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_systemd_service" "yes"
            mark_step_completed "systemd_service"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    local nym_node_id=$(load_state "nym_node_id")
    local NYMMODE=$(load_state "NYMMODE")
    local service_file="/etc/systemd/system/nym-node.service"
    
    local service_description="Nym Node"
    print_info "Choose a description/name for your systemd service"
    echo ""
    
    if prompt_yes_no "Use default name 'Nym Node'?" "yes"; then
        service_description="Nym Node"
        print_info "Using service description: ${GREEN}$service_description${NC}"
    else
        prompt_user "Enter your preferred service description: " service_description "required"
    fi
    
    save_state "service_description" "$service_description"
    echo ""
    
    if [ -f "$service_file" ]; then
        print_warning "Service file already exists: $service_file"
        
        if ! prompt_yes_no "Do you want to overwrite it?" "yes"; then
            print_info "Keeping existing service file"
            
            print_step "Ensuring service is enabled and running..."
            sudo systemctl daemon-reload
            sudo systemctl enable nym-node
            
            if systemctl is-active --quiet nym-node; then
                print_info "Service is already running"
                
                if prompt_yes_no "Do you want to restart it?" "yes"; then
                    print_step "Restarting nym-node service..."
                    sudo systemctl restart nym-node
                    sleep 3
                fi
            else
                print_step "Starting nym-node service..."
                sudo systemctl start nym-node
                sleep 3
            fi
            
            check_service_status
            mark_step_completed "systemd_service"
            return 0
        fi
    fi
    
    print_step "Creating systemd service file..."
    
    local wireguard_flag=""
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        wireguard_flag="--wireguard-enabled true"
    fi
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=$service_description
StartLimitInterval=200
StartLimitBurst=10

[Service]
User=root
ExecStart=/usr/local/bin/nym-node run --id $nym_node_id --mode $NYMMODE --accept-operator-terms-and-conditions $wireguard_flag
KillSignal=SIGINT
Restart=on-failure
RestartSec=7
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service file created: $service_file"
    print_info "Service description: ${GREEN}$service_description${NC}"
    
    print_step "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    print_success "Daemon reloaded"
    
    print_step "Enabling nym-node service (auto-start on boot)..."
    sudo systemctl enable nym-node
    print_success "Service enabled"
    
    if systemctl is-active --quiet nym-node; then
        print_warning "Service is already running, will restart..."
        print_step "Restarting nym-node service..."
        sudo systemctl restart nym-node
    else
        print_step "Starting nym-node service..."
        sudo systemctl start nym-node
    fi
    
    sleep 3
    
    check_service_status
    
    mark_step_completed "systemd_service"
    print_summary "Systemd service configured and started"
}

#-----------------------------------------------------------------------------
# Helper: Check Service Status
#-----------------------------------------------------------------------------
check_service_status() {
    print_step "Checking service status..."
    echo ""
    
    if systemctl is-active --quiet nym-node; then
        print_success "✓ Service is RUNNING"
        
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Service Status:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        sudo systemctl status nym-node --no-pager -n 10
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        return 0
    else
        print_error "✗ Service is NOT running or FAILED"
        
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC} ${BOLD}Service Status (FAILED):${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        sudo systemctl status nym-node --no-pager -n 20
        
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        print_error "Service failed to start!"
        print_info "Check the logs above for error messages"
        print_info "You can view full logs with: sudo journalctl -u nym-node -n 100"
        
        if prompt_yes_no "Do you want to retry starting the service?" "yes"; then
            print_step "Attempting to restart service..."
            sudo systemctl restart nym-node
            sleep 3
            
            if systemctl is-active --quiet nym-node; then
                print_success "Service started successfully on retry!"
                return 0
            else
                print_error "Service still failed to start"
                
                if ! prompt_yes_no "Continue with installation anyway?" "no"; then
                    print_error "Installation cannot continue without running service"
                    exit 1
                fi
            fi
        return 1
    fi
fi
}

#-----------------------------------------------------------------------------
# BLOCK: Network Tunnel Manager - Wireguard Exit Policy
#-----------------------------------------------------------------------------
setup_network_tunnel_manager_exit_policy() {
    print_header "Network Tunnel Manager Setup"

    local NYMMODE=$(load_state "NYMMODE")
    
    if [ "$NYMMODE" = "mixnode" ]; then
        print_info "Network tunnel manager is only needed for gateway modes"
        print_info "Current mode: ${YELLOW}$NYMMODE${NC} - Skipping..."
        mark_step_completed "network_tunnel"
        print_summary "Network tunnel manager skipped (not needed for mixnode)"
        return 0
    fi

    print_info "Next: Configure network tunneling and WireGuard exit policy"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_network_tunnel" "yes"
            mark_step_completed "network_tunnel"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    cd "$HOME" || {
        print_error "Failed to change to home directory"
        return 1
    }
    
    print_step "Downloading network tunnel manager script..."
    
    # Force overwrite using curl -o
    if ! curl -L -o network-tunnel-manager.sh https://raw.githubusercontent.com/nymtech/nym/refs/heads/develop/scripts/nym-node-setup/network-tunnel-manager.sh; then
        print_error "Failed to download network tunnel manager script"
        return 1
    fi
    
    chmod +x network-tunnel-manager.sh
    print_success "Network tunnel manager script downloaded"
    
    echo ""
    print_step "Running network tunnel configuration commands..."
    print_warning "This will modify system network settings"
    echo ""
    
    local commands=(
        "complete_networking_configuration:Full tunneling and exit policy setup"
    )
    
    for cmd_info in "${commands[@]}"; do
        IFS=':' read -r cmd desc <<< "$cmd_info"
        
        echo -e "${MAGENTA}▶ $desc...${NC}"
        
        if ./network-tunnel-manager.sh $cmd; then
            echo -e "  ${GREEN}✅ Success${NC}"
        else
            print_warning "Command might have failed: $cmd"
            print_info "Continuing anyway..."
        fi
    done
    
    print_success "Network tunnel manager configuration completed"
    
    mark_step_completed "network_tunnel"
    print_summary "Network tunneling and WireGuard exit policy configured"
}

#-----------------------------------------------------------------------------
# BLOCK: Node Bonding (Optional)
#-----------------------------------------------------------------------------
handle_node_bonding() {
    if is_step_completed "bonding"; then
        print_info "Bonding step already completed. Skipping..."
        return 0
    fi
    
    print_header "Node Bonding (Optional)"
    
    print_info "Next: Bond your node to the Nym network"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_bonding" "yes"
            mark_step_completed "bonding"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done

    local nym_node_id=$(load_state "nym_node_id")
    
    print_info "Bonding your node to the Nym network allows you to:"
    print_info "  • Participate in the mixnet and earn rewards"
    print_info "  • Be listed in the Nym network explorer"
    print_info "  • Contribute to network privacy and security"
    echo ""
    print_warning "You need:"
    print_warning "  • A Nym wallet with tokens"
    print_warning "  • Your node's Identity Key"
    print_warning "  • Your node's public IPv4 address"
    echo ""
    
    if ! prompt_yes_no "Do you want to bond the node now?" "no"; then
        print_info "Skipping bonding - you can bond later through the Nym wallet"
        save_state "bonding_done" "skipped"
        mark_step_completed "bonding"
        return 0
    fi
    
    echo ""
    print_step "Gathering bonding information..."
    echo ""
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}Bonding Information:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    nym-node bonding-information --id "$nym_node_id"
    
    echo ""
    
    local ipv4=$(curl -4 -s https://ifconfig.me)
    echo -e "${YELLOW}IPv4 Address:${NC} ${GREEN}$ipv4${NC}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    print_info "Steps to bond your node:"
    echo ""
    echo -e "  ${YELLOW}1.${NC} Open your Nym wallet"
    echo -e "  ${YELLOW}2.${NC} Go to the ${BOLD}Bonding${NC} page"
    echo -e "  ${YELLOW}3.${NC} Enter your node's ${BOLD}Identity Key${NC} (shown above)"
    echo -e "  ${YELLOW}4.${NC} Enter your ${BOLD}IP address${NC}: ${GREEN}$ipv4${NC}"
    echo -e "  ${YELLOW}5.${NC} Enter port: ${GREEN}8080${NC} (default)"
    echo -e "  ${YELLOW}6.${NC} Click ${BOLD}Bond${NC} and generate the payload"
    echo -e "  ${YELLOW}7.${NC} Copy the ${BOLD}payload${NC} from the wallet"
    echo ""
    
    local payload=""
    print_step "Waiting for payload from Nym wallet..."
    echo ""
    
    prompt_user "Paste the payload from your Nym wallet: " payload "required"
    
    echo ""
    print_step "Signing the payload with your node..."
    echo ""
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}Signature:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    nym-node sign --id "$nym_node_id" --contract-msg "$payload"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    print_success "Signature generated!"
    echo ""
    print_info "Final steps:"
    echo -e "  ${YELLOW}1.${NC} Copy the ${BOLD}signature${NC} from above"
    echo -e "  ${YELLOW}2.${NC} Paste it into your Nym wallet"
    echo -e "  ${YELLOW}3.${NC} Complete the bonding transaction"
    echo ""
    print_info "Your node will be ${GREEN}active${NC} at the beginning of the next epoch"
    print_info "Epoch changes occur approximately every ${YELLOW}1 hour${NC}"
    
    echo ""
    if prompt_yes_no "Press Enter when bonding is complete..." "yes"; then
        save_state "bonding_done" "yes"
        print_success "Bonding completed!"
    fi
    
    mark_step_completed "bonding"
    print_summary "Node bonding process completed"
}

#-----------------------------------------------------------------------------
# BLOCK: Run Network Tests
#-----------------------------------------------------------------------------
run_network_tests() {
    if is_step_completed "network_tests"; then
        print_info "Network tests already completed. Skipping..."
        return 0
    fi
    
    print_header "Final Network Connectivity Tests"
    
    print_info "Next: Run some tests to verify node and system configuration"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}[Enter]${NC} - Execute block"
    echo -e "  ${GREEN}[S]${NC}     - Skip"
    echo ""
    
    local choice=""
    while true; do
        echo -ne "${YELLOW}Your choice [Enter/S]: ${NC}"
        read -r choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ -z "$choice" ]; then
            break  # Execute the block
        elif [ "$choice" = "s" ]; then
            print_warning "Skipping this block"
            save_state "skipped_network_tests" "yes"
            mark_step_completed "network_tests"
            return 0
        else
            print_warning "Invalid choice. Press 'S' to skip or Enter to execute."
        fi
    done
    
    # Block logic continues here...

    local NYMMODE=$(load_state "NYMMODE")
    
    # Track test results
    local test_mixnet_passed="n/a"
    local test_wg_passed="n/a"
    local test_iptables_passed="n/a"
    local test_ipv6_passed=false
    local test_exit_policy_conn="n/a"
    local test_exit_policy_general="n/a"

    # For mixnode mode, skip gateway-specific tests
    if [ "$NYMMODE" = "mixnode" ]; then
        print_info "Running tests for ${YELLOW}mixnode${NC} mode..."
        print_info "Gateway-specific tests will be skipped"
        echo ""
        
        test_mixnet_passed="skipped"
        test_wg_passed="skipped"
        test_iptables_passed="skipped"
        test_exit_policy_conn="skipped"
        test_exit_policy_general="skipped"
    else
        print_info "Running tests for ${YELLOW}gateway${NC} mode..."
        echo ""
        
        cd "$HOME" || return 1
        
        # Test 1: Mixnet connectivity (only for gateways)
        print_step "Test 1: Mixnet connectivity (joke through the mixnet)..."
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Mixnet Test:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        local mixnet_output=$(./network-tunnel-manager.sh joke_through_the_mixnet 2>&1)
        echo "$mixnet_output"
        
        echo ""
        if echo "$mixnet_output" | grep -q "joke fetching processes completed for nymtun0"; then
            print_success "✓ Mixnet connectivity test PASSED"
            test_mixnet_passed=true
        else
            print_error "✗ Mixnet connectivity test FAILED"
            print_warning "Check the output above for details"
            test_mixnet_passed=false
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Test 2: WireGuard tunnel (only for gateways)
        print_step "Test 2: WireGuard tunnel connectivity..."
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}WireGuard Tunnel Test:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        local wg_output=$(./network-tunnel-manager.sh joke_through_wg_tunnel 2>&1)
        echo "$wg_output"
        
        echo ""
        if echo "$wg_output" | grep -q "joke fetching processes completed for nymwg"; then
            print_success "✓ WireGuard tunnel test PASSED"
            test_wg_passed=true
        else
            print_error "✗ WireGuard tunnel test FAILED"
            print_warning "Check the output above for details"
            test_wg_passed=false
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Test 3: iptables rules for WireGuard port (only for gateways)
        print_step "Test 3: Checking iptables rules for WireGuard port 51830..."
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}IPtables Rules (port 51830):${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        local iptables_output=$(iptables -S | grep 51830)
        if [ -n "$iptables_output" ]; then
            echo "$iptables_output"
            test_iptables_passed=true
        else
            echo "No specific rules found for port 51830"
            print_warning "⚠ No iptables rules found for port 51830"
            test_iptables_passed=false
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        # Test 4: "exit_policy_test_connectivity"
        if [ "$NYMMODE" = "exit-gateway" ]; then
            echo ""
            if prompt_yes_no "Run Exit Policy Connectivity test? (exit_policy_test_connectivity)" "no"; then
                print_step "Test 4: exit_policy_test_connectivity ..."
                echo ""
                echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${NC} ${BOLD} Exit Policy Connectivity:${NC}"
                echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                
                if ./network-tunnel-manager.sh exit_policy_test_connectivity; then
                    echo ""
                    print_success "✓ Exit Policy Connectivity test PASSED"
                    test_exit_policy_conn=true
                else
                    echo ""
                    print_warning "⚠ Exit Policy Connectivity test had issues"
                    test_exit_policy_conn=false
                fi
                
                echo ""
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
            else
                print_info "Skipping Exit Policy Connectivity test"
                test_exit_policy_conn="skipped"
            fi
        else
            test_exit_policy_conn="n/a"
        fi
    fi

        # Test 5: "exit_policy_tests"
        if [ "$NYMMODE" = "exit-gateway" ]; then
            echo ""
            if prompt_yes_no "Run Exit Policy test? (exit_policy_tests)" "no"; then
                print_step "Test 5: exit_policy_tests ..."
                echo ""
                echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${NC} ${BOLD}Exit Policy tests:${NC}"
                echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                
                if ./network-tunnel-manager.sh exit_policy_tests; then
                        echo ""
                        print_success "✓ Exit Policy tests PASSED"
                        test_exit_policy_general=true
                    else
                        echo ""
                        print_warning "⚠ Exit Policy tests had issues"
                        test_exit_policy_general=false
                fi
                
                echo ""
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
            else
                print_info "Skipping Exit Policy test"
                test_exit_policy_general="skipped"
            fi
        else
            test_exit_policy_general="n/a"
        fi
    
    # Test 6: IPv6 connectivity (run for all modes)
    print_step "Test 6: IPv6 connectivity test (ping google.com)..."
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}IPv6 Connectivity Test:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if ping6 -c 4 google.com 2>&1; then
        echo ""
        print_success "✓ IPv6 connectivity test PASSED"
        test_ipv6_passed=true
    else
        echo ""
        print_warning "⚠ IPv6 connectivity not available (this may be normal)"
        test_ipv6_passed=false
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Test 7: UFW status (run for all modes)
    print_step "Test 7: Firewall status..."
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}UFW Firewall Rules:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    sudo ufw status numbered
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Save test results to state
    save_state "test_mixnet_passed" "$test_mixnet_passed"
    save_state "test_wg_passed" "$test_wg_passed"
    save_state "test_iptables_passed" "$test_iptables_passed"
    save_state "test_ipv6_passed" "$test_ipv6_passed"
    save_state "test_exit_policy_conn" "$test_exit_policy_conn"
    save_state "test_exit_policy_general" "$test_exit_policy_general"
    
    mark_step_completed "network_tests"
    print_summary "Network tests completed - check results above"
}

#-----------------------------------------------------------------------------
# BLOCK: Verify Bash Profile
#-----------------------------------------------------------------------------
verify_bash_profile() {
    print_step "Verifying ~/.bash_profile activation..."
    
    if [ -f "$HOME/.bash_profile" ]; then
        source "$HOME/.bash_profile"
        
        local nym_node_id=$(load_state "nym_node_id")
        
        if [ -n "$nym_node_id" ] && [ "$nym_node_id" = "${nym_node_id:-unset}" ]; then
            print_success "✓ bash_profile variables are active"
        else
            print_warning "bash_profile might not be fully activated"
            print_info "You may need to run: source ~/.bash_profile"
        fi
        
        # Check Rust environment
        if command -v rustc &> /dev/null; then
            print_success "✓ Rust environment is active"
        else
            print_warning "Rust environment not in PATH"
            print_info "Run: source ~/.bash_profile"
        fi
    else
        print_warning "~/.bash_profile not found"
    fi
}

#-----------------------------------------------------------------------------
# BLOCK: Final Information and Summary
#-----------------------------------------------------------------------------
show_final_summary() {
    print_header "Installation Complete! 🎉"
    
    local nym_node_id=$(load_state "nym_node_id")
    local NYMMODE=$(load_state "NYMMODE")
    local LOCATION=$(load_state "LOCATION")
    local PUBLIC_IP=$(load_state "PUBLIC_IP")
    local HOSTNAME=$(load_state "HOSTNAME")
    local NYM_VERSION=$(load_state "NYM_VERSION")
    local bonding_done=$(load_state "bonding_done")
    local service_description=$(load_state "service_description")
    
    # Load test results
    local test_mixnet_passed=$(load_state "test_mixnet_passed")
    local test_wg_passed=$(load_state "test_wg_passed")
    local test_iptables_passed=$(load_state "test_iptables_passed")
    local test_ipv6_passed=$(load_state "test_ipv6_passed")
    
    echo ""
    echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                                       ║${NC}"
    echo -e "${GREEN}${BOLD}║              NYM NODE SUCCESSFULLY INSTALLED!                         ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                                       ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Node Configuration
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}Node Configuration:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}Node ID:${NC}              ${GREEN}$nym_node_id${NC}"
    echo -e "  ${YELLOW}Service Name:${NC}         ${GREEN}${service_description:-Nym Node}${NC}"
    echo -e "  ${YELLOW}Mode:${NC}                 ${GREEN}$NYMMODE${NC}"
    echo -e "  ${YELLOW}Location:${NC}             ${GREEN}$LOCATION${NC}"
    echo -e "  ${YELLOW}Public IP:${NC}            ${GREEN}$PUBLIC_IP${NC}"
    
    if [ -n "$HOSTNAME" ]; then
        echo -e "  ${YELLOW}Hostname:${NC}             ${GREEN}$HOSTNAME${NC}"
    fi
    
    if [ -n "$NYM_VERSION" ] && [ "$NYM_VERSION" != "existing" ]; then
        echo -e "  ${YELLOW}Version:${NC}              ${GREEN}$NYM_VERSION${NC}"
    fi
    
    if [ "$bonding_done" = "yes" ]; then
        echo -e "  ${YELLOW}Bonding Status:${NC}       ${GREEN}✓ Completed${NC}"
    elif [ "$bonding_done" = "skipped" ]; then
        echo -e "  ${YELLOW}Bonding Status:${NC}       ${YELLOW}⊘ Skipped${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Test Results Summary
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}Test Results Summary:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Skipped Blocks Warning
    local skipped_blocks=""
    
    if [ "$(load_state "skipped_system_prep")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}System Preparation, "
    fi
    if [ "$(load_state "skipped_rust_install")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Rust Installation, "
    fi
    if [ "$(load_state "skipped_file_limits")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}File Limits, "
    fi
    if [ "$(load_state "skipped_env_vars")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Environment Variables, "
    fi
    if [ "$(load_state "skipped_nym_binary")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Nym Binary, "
    fi
    if [ "$(load_state "skipped_nym_init")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Node Initialization, "
    fi
    if [ "$(load_state "skipped_description")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Description, "
    fi
    if [ "$(load_state "skipped_config_toml")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Config.toml, "
    fi
    if [ "$(load_state "skipped_network_tunnel")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Network Tunnel, "
    fi
    if [ "$(load_state "skipped_quic_bridge")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}QUIC Bridge, "
    fi
    if [ "$(load_state "skipped_ufw_check")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}UFW Check, "
    fi
    if [ "$(load_state "skipped_systemd_service")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Systemd Service, "
    fi
    if [ "$(load_state "skipped_wg_exit_policy")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}WireGuard Exit Policy, "
    fi
    if [ "$(load_state "skipped_bonding")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Node Bonding, "
    fi
    if [ "$(load_state "skipped_network_tests")" = "yes" ]; then
        skipped_blocks="${skipped_blocks}Network Tests, "
    fi
    
    # Remove trailing comma and space
    skipped_blocks=$(echo "$skipped_blocks" | sed 's/, $//')
    
    if [ -n "$skipped_blocks" ]; then
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC} ${BOLD}Skipped Blocks:${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠${NC}  The following blocks were skipped:"
        echo -e "     ${YELLOW}$skipped_blocks${NC}"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    # Load WireGuard policy test results
    local test_exit_policy_conn=$(load_state "test_exit_policy_conn")
    local test_exit_policy_general=$(load_state "test_exit_policy_general")
    
    # Only show gateway tests if not mixnode
    if [ "$NYMMODE" != "mixnode" ]; then
        # Mixnet Test
        if [ "$test_mixnet_passed" = "true" ]; then
            echo -e "  ${YELLOW}Mixnet Test:${NC}                       ${GREEN}✓ PASSED${NC}"
        elif [ "$test_mixnet_passed" = "false" ]; then
            echo -e "  ${YELLOW}Mixnet Test:${NC}                       ${RED}✗ FAILED${NC}"
        fi
        
        # WireGuard Test
        if [ "$test_wg_passed" = "true" ]; then
            echo -e "  ${YELLOW}WireGuard Tunnel Test:${NC}             ${GREEN}✓ PASSED${NC}"
        elif [ "$test_wg_passed" = "false" ]; then
            echo -e "  ${YELLOW}WireGuard Tunnel Test:${NC}             ${RED}✗ FAILED${NC}"
        fi
        
        # IPtables Test
        if [ "$test_iptables_passed" = "true" ]; then
            echo -e "  ${YELLOW}IPtables Rules (port 51830):${NC}       ${GREEN}✓ CONFIGURED${NC}"
        elif [ "$test_iptables_passed" = "false" ]; then
            echo -e "  ${YELLOW}IPtables Rules (port 51830):${NC}       ${YELLOW}⚠ NOT FOUND${NC}"
        fi
        
        # Exit policy tests (exit-gateway only)
        if [ "$NYMMODE" = "exit-gateway" ]; then
            if [ "$test_exit_policy_conn" = "true" ]; then
                echo -e "  ${YELLOW}Exit Policy Connectivity:${NC}          ${GREEN}✓ PASSED${NC}"
            elif [ "$test_exit_policy_conn" = "false" ]; then
                echo -e "  ${YELLOW}Exit Policy Connectivity:${NC}          ${RED}✗ FAILED${NC}"
            elif [ "$test_exit_policy_conn" = "skipped" ]; then
                echo -e "  ${YELLOW}Exit Policy Connectivity:${NC}          ${BLUE}⊘ SKIPPED${NC}"
            fi
            
            if [ "$test_exit_policy_general" = "true" ]; then
                echo -e "  ${YELLOW}General Exit Policy Test:${NC}          ${GREEN}✓ PASSED${NC}"
            elif [ "$test_exit_policy_general" = "false" ]; then
                echo -e "  ${YELLOW}General Exit Policy Test:${NC}          ${YELLOW}⚠ HAD ISSUES${NC}"
            elif [ "$test_exit_policy_general" = "skipped" ]; then
                echo -e "  ${YELLOW}General Exit Policy Test:${NC}          ${BLUE}⊘ SKIPPED${NC}"
            fi
        fi
    else
        # For mixnode, show that gateway tests were skipped
        echo -e "  ${BLUE}ℹ${NC}  Gateway-specific tests skipped for ${YELLOW}mixnode${NC} mode"
    fi
    
    # IPv6 Test (always shown)
    echo ""
    if [ "$test_ipv6_passed" = "true" ]; then
        echo -e "  ${YELLOW}IPv6 Connectivity Test:${NC}            ${GREEN}✓ AVAILABLE${NC}"
    else
        echo -e "  ${YELLOW}IPv6 Connectivity Test:${NC}            ${YELLOW}⊘ NOT AVAILABLE${NC}"
    fi
    
    # UFW Firewall Status
    echo ""
    if command -v ufw &> /dev/null; then
        if sudo ufw status | grep -q "Status: active"; then
            echo -e "  ${YELLOW}UFW Firewall:${NC}                      ${GREEN}✓ ACTIVE${NC}"
            echo ""
            echo -e "  ${BOLD}Active Firewall Rules:${NC}"
            sudo ufw status numbered | tail -n +4 | while IFS= read -r line; do
                if [ -n "$line" ]; then
                    echo -e "    ${CYAN}$line${NC}"
                fi
            done

            # Check for port 4443 if gateway mode
            if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
                echo ""
                if sudo ufw status | grep -q "4443.*ALLOW"; then
                    echo -e "  ${GREEN}✓${NC} Port 4443/UDP (QUIC): ${GREEN}ALLOWED${NC}"
                else
                    echo -e "  ${YELLOW}⚠${NC} Port 4443/UDP (QUIC): ${YELLOW}NOT FOUND${NC}"
                fi
            fi
        else
            echo -e "  ${YELLOW}UFW Firewall:${NC}                      ${YELLOW}⊘ INACTIVE${NC}"
            echo ""
            echo -e "  ${BOLD}Added Rules (not active):${NC}"
            local added_rules=$(sudo ufw show added 2>/dev/null | grep "^ufw")
            if [ -n "$added_rules" ]; then
                echo "$added_rules" | while IFS= read -r line; do
                    echo -e "    ${CYAN}$line${NC}"
                done
            else
                echo -e "    ${YELLOW}No rules added yet${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}UFW Firewall:${NC}                      ${YELLOW}⊘ NOT INSTALLED${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Build information (filtered)
    print_step "Current build information:"
    echo ""
    nym-node build-info | grep -E "Build Version|Commit SHA"
    echo ""
    
    # Bonding information (filtered)
    print_step "Bonding information:"
    echo ""
    nym-node bonding-information --id "$nym_node_id" | grep -E "Identity Key|Host|Custom HTTP Port"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Important Notes (dynamic based on status)
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}Important Notes:${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local has_critical_issues=false
    local has_warnings=false
    
    # Check for critical issues (only for gateway modes)
    if [ "$NYMMODE" != "mixnode" ]; then
        if [ "$test_mixnet_passed" = "false" ]; then
            echo -e "  ${RED}${BOLD}⚠ CRITICAL:${NC} ${RED}Mixnet test failed!${NC}"
            echo -e "     Check node logs: ${CYAN}sudo journalctl -u nym-node -n 100${NC}"
            echo -e "     Verify firewall allows ports: 1789, 1790, 8080, 9000, 9001"
            echo ""
            has_critical_issues=true
        fi
        
        if [ "$test_wg_passed" = "false" ]; then
            echo -e "  ${RED}${BOLD}⚠ CRITICAL:${NC} ${RED}WireGuard tunnel test failed!${NC}"
            echo -e "     Check WireGuard configuration and network settings"
            echo -e "     Verify UDP ports and 51830 are open"
            echo ""
            has_critical_issues=true
        fi
        
        if [ "$test_iptables_passed" = "false" ]; then
            echo -e "  ${YELLOW}${BOLD}⚠ WARNING:${NC} ${YELLOW}No iptables rules found for port 51830${NC}"
            echo -e "     WireGuard traffic filtering may not be configured properly"
            echo ""
            has_warnings=true
        fi
    fi
    
    # Firewall warnings
    if command -v ufw &> /dev/null; then
        if ! sudo ufw status | grep -q "Status: active"; then
            echo -e "  ${YELLOW}${BOLD}⚠ WARNING:${NC} ${YELLOW}UFW firewall is INACTIVE${NC}"
            echo -e "     Check Nym docs on how to configure:"
            echo -e "  ${CYAN}     https://nym.com/docs/operators/nodes/preliminary-steps/vps-setup#4-open-all-needed-ports-to-have-your-firewall-for-nym-node-working-correctly${NC}"
            echo ""
            has_warnings=true
        fi
    fi
    
    # IPv6 note (informational only)
    if [ "$test_ipv6_passed" != "true" ]; then
        echo -e "  ${BLUE}ℹ${NC}  IPv6 not available (this is normal for most servers)"
        echo ""
    fi
    
    # Bonding reminder
    if [ "$bonding_done" != "yes" ]; then
        echo -e "  ${YELLOW}${BOLD}⚠ REMINDER:${NC} ${YELLOW}Bond your node to earn rewards${NC}"
        echo -e "     Visit Nym wallet → Bonding page"
        echo -e "     Use Identity Key and IP shown above"
        echo ""
        has_warnings=true
    fi
    
    # Files location
    echo -e "  ${BLUE}ℹ${NC}  Log file: ${CYAN}$LOG_FILE${NC}"
    echo -e "  ${BLUE}ℹ${NC}  State file: ${CYAN}$STATE_FILE${NC}"
    echo ""
    echo -e "  ${BLUE}ℹ${NC}  Node config: ${CYAN}$HOME/.nym/nym-nodes/$nym_node_id/${NC}"
    
    # Required ports reminder
    if [ "$NYMMODE" = "exit-gateway" ] || [ "$NYMMODE" = "entry-gateway" ]; then
        echo -e "  ${BLUE}ℹ${NC}  Required ports: ${CYAN}80, 443, 1789, 1790, 8080, 9000, 9001, 51830, 51822/udp, 4443/udp${NC}"
    else
        echo -e "  ${BLUE}ℹ${NC}  Required ports: ${CYAN}80, 443, 1789, 1790, 8080, 9000, 9001${NC}"
    fi
    
    # Network explorer
    echo -e "  ${BLUE}ℹ${NC}  Monitor your node: ${CYAN}https://explorer.nymtech.net/${NC}"
    echo -e "  ${BLUE}ℹ${NC}  ${CYAN}https://nymesis.vercel.app/${NC}"
    echo -e "  ${BLUE}ℹ${NC}  ${CYAN}https://node-status.nym.com/${NC}"
    echo -e "  ${BLUE}ℹ${NC}  ${CYAN}https://nym.com/explorer{NC}"
    echo -e "  ${BLUE}ℹ${NC}  ${CYAN}https://harbourmaster.nymtech.net/{NC}"
    echo ""
    
    # Status summary banner
    if [ "$has_critical_issues" = true ]; then
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${RED}${BOLD}  ⚠ ACTION REQUIRED: Critical issues detected - see above  ⚠${NC}"
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    elif [ "$has_warnings" = true ]; then
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}${BOLD}  ⚠ Installation completed with warnings - review above  ⚠${NC}"
        echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${GREEN}${BOLD}  ✓ All systems operational - node is ready!  ✓${NC}"
        echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Final ASCII art
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
    _____ _                 _      __   __          _ 
   |_   _| |__   __ _ _ __ | | __  \ \ / /__  _   _| |
     | | | '_ \ / _` | '_ \| |/ /   \ V / _ \| | | | |
     | | | | | | (_| | | | |   <     | | (_) | |_| |_|
     |_| |_| |_|\__,_|_| |_|_|\_\    |_|\___/ \__,_(_)
                                                       
EOF
    echo -e "${NC}"
    
    # Final status message
    if [ "$has_critical_issues" = true ]; then
        echo -e "${YELLOW}${BOLD}Installation completed with critical issues. Please resolve them before bonding.${NC}"
    elif [ "$has_warnings" = true ]; then
        echo -e "${YELLOW}${BOLD}Installation completed with warnings. Your node is running but review the notes above.${NC}"
    else
        echo -e "${GREEN}${BOLD}Your Nym node is fully operational and ready to contribute to the privacy network!${NC}"
    fi
    echo ""
    
    log "=== Installation completed ==="
}

#=============================================================================
# MAIN SCRIPT EXECUTION
#=============================================================================
main() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║              NYM NODE INSTALLATION SCRIPT                             ║
║              Ubuntu 22/24 LTS                                         ║
║                                                                       ║
║              Version: 2.0.1                                           ║
║              Date: 2025-11-30                                         ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    log "=== Script started by user: $(whoami) ==="
    
    print_info "Installation log: $LOG_FILE"
    print_info "State file: $STATE_FILE"
    echo ""
    
    if [ -f "$STATE_FILE" ]; then
        print_warning "Found previous installation state."
        if prompt_yes_no "Do you want to resume from where you left off?" "yes"; then
            print_info "Resuming installation..."
        else
            if prompt_yes_no "Start fresh installation (this will remove previous state)?" "no"; then
                rm -f "$STATE_FILE"
                print_info "Starting fresh installation..."
            else
                print_info "Exiting..."
                exit 0
            fi
        fi
    fi
    
    sleep 2
    
    # Pre-checks
    check_root_or_sudo
    check_ubuntu_version
    
    # Installation blocks - Part 2 (SSH removed)
    prepare_system
    install_rust
    configure_file_limits
    setup_environment_variables
    
    # Installation blocks - Part 3
    handle_nym_binary
    initialize_nym_node
    
    # Installation blocks - Part 4
    setup_description
    configure_config_toml
    setup_network_tunnel_manager
    setup_quic_bridge    # -------------------- # NEW: Added QUIC bridge here
    check_ufw_status
    block_web_gateway_setup    # -------------- # Adding script - Reverse Proxy, WSS, certificate
    setup_systemd_service
    setup_network_tunnel_manager_exit_policy    # Same but no skipping rule
    
    # Installation blocks - Part 5
    handle_node_bonding
    run_network_tests
    verify_bash_profile
    show_final_summary
}

# Start the script
main "$@"
