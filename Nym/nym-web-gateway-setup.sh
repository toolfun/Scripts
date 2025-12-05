#!/bin/bash

#
# mkdir -p $HOME/scripts/nym-scripts
# URLGIST="https://gist.githubusercontent.com/toolfun/0b7ae31463245380bb83f12360aac81e/raw/nym-web-gateway-setup.sh"	
# URLGH="https://raw.githubusercontent.com/toolfun/Scripts/refs/heads/main/Nym/nym-web-gateway-setup.sh"
# curl --fail -L --progress-bar $URLGH -o ~/scripts/nym-scripts/nym-web-gateway-setup.sh	
# chmod +x ~/scripts/nym-scripts/nym-web-gateway-setup.sh
#

################################################################################
# Nym Node - Reverse Proxy & WSS Configuration Script
# For Ubuntu 22.04/24.04
# Author: toolfun
# Version: 2.0.1
# Date: 2025-11-30
################################################################################

set +e  # Don't exit on errors - we handle them manually

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log file setup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$HOME/.nym-installer"
LOG_FILE="$LOG_DIR/nym-reverse-proxy-setup_${TIMESTAMP}.log"
mkdir -p "$LOG_DIR"

# Global variables
HOSTNAME=""
nym_node_id=""
CERTBOT_EMAIL=""
BACKUP_DIR="$HOME/.nym-installer/backups_${TIMESTAMP}"
REQUIRED_PORTS_TCP=(8080 1789 1790 9000 9001)
REQUIRED_PORTS_UDP=(51822 4443)
CONFIG_MODIFIED=false

# Check if variables are imported from parent script
if [[ -n "$nym_node_id" ]]; then
    print_info "Node ID imported from parent script: $nym_node_id"
fi

if [[ -n "$HOSTNAME" ]]; then
    print_info "Hostname imported from parent script: $HOSTNAME"
fi

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${BLUE}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
    log "BLOCK: $1"
}

print_info() {
    echo -e "${CYAN}ℹ ${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

print_question() {
    echo -e "${BOLD}❯${NC} $1"
}

show_progress() {
    local message="$1"
    echo -ne "${CYAN}${message}${NC}"
    for i in {1..5}; do
        echo -n "."
        sleep 0.3
    done
    echo ""
}

ask_continue() {
    local block_name="$1"
    local description="$2"
    
    echo -e "\n${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Block:${NC} $block_name"
    echo -e "${BOLD}Description:${NC} $description"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}Press [ENTER] to execute | Press [S] to skip${NC}"
    read -r choice
    
    if [[ "$choice" =~ ^[Ss]$ ]]; then
        print_warning "Block skipped by user"
        log "SKIPPED: $block_name"
        return 1
    fi
    return 0
}

handle_error() {
    local error_msg="$1"
    print_error "$error_msg"
    echo -e "\n${YELLOW}Options:${NC}"
    echo -e "  [ENTER] Continue to next block"
    echo -e "  [Q] Quit script"
    read -r choice
    
    if [[ "$choice" =~ ^[Qq]$ ]]; then
        print_warning "Script terminated by user"
        exit 1
    fi
    print_info "Continuing to next block..."
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

check_port_usage() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if command -v ss &> /dev/null; then
        if [[ "$protocol" == "tcp" ]]; then
            ss -tuln | grep -q ":${port} " && return 0
        else
            ss -uln | grep -q ":${port} " && return 0
        fi
    elif command -v netstat &> /dev/null; then
        if [[ "$protocol" == "tcp" ]]; then
            netstat -tuln | grep -q ":${port} " && return 0
        else
            netstat -uln | grep -q ":${port} " && return 0
        fi
    fi
    return 1
}

create_backup() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_file="$BACKUP_DIR/$(basename "$file").backup"
        cp "$file" "$backup_file"
        print_success "Backup created: $backup_file"
        log "BACKUP: $file -> $backup_file"
    fi
}

check_disk_space() {
    local min_space_gb=1
    local available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_space -lt $min_space_gb ]]; then
        print_warning "Low disk space: ${available_space}GB available in $HOME"
        return 1
    else
        print_success "Disk space check passed: ${available_space}GB available"
        return 0
    fi
}

check_dns_records() {
    local domain="$1"
    local server_ipv4=$(curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
    local server_ipv6=$(curl -s -6 --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
    local dns_ipv4=""
    local dns_ipv6=""
    local a_record_ok=false
    local aaaa_record_ok=false
    
    print_info "Server IPv4: ${server_ipv4:-Unable to detect}"
    print_info "Server IPv6: ${server_ipv6:-Unable to detect}"
    
    # Check A record
    if command -v dig &> /dev/null; then
        print_info "Checking A record..."
        dns_ipv4=$(dig +short A "$domain" @8.8.8.8 | head -1)
        if [[ -n "$dns_ipv4" ]]; then
            print_success "A record found: $dns_ipv4"
            if [[ "$dns_ipv4" == "$server_ipv4" ]]; then
                print_success "A record matches server IPv4"
                a_record_ok=true
            else
                print_warning "A record ($dns_ipv4) does NOT match server IPv4 ($server_ipv4)"
            fi
        else
            print_warning "No A record found for $domain"
        fi
        
        # Check AAAA record
        print_info "Checking AAAA record..."
        dns_ipv6=$(dig +short AAAA "$domain" @8.8.8.8 | head -1)
        if [[ -n "$dns_ipv6" ]]; then
            print_success "AAAA record found: $dns_ipv6"
            if [[ "$dns_ipv6" == "$server_ipv6" ]]; then
                print_success "AAAA record matches server IPv6"
                aaaa_record_ok=true
            else
                print_warning "AAAA record ($dns_ipv6) does NOT match server IPv6 ($server_ipv6)"
            fi
        else
            print_warning "No AAAA record found for $domain"
        fi
    else
        print_warning "dig command not found"
        return 2
    fi
    
    # Return status
    if [[ "$a_record_ok" == true ]] && [[ "$aaaa_record_ok" == true ]]; then
        return 0  # Both OK
    elif [[ "$a_record_ok" == true ]] || [[ "$aaaa_record_ok" == true ]]; then
        return 1  # Partial OK
    else
        return 3  # Both missing/wrong
    fi
}

################################################################################
# BLOCK 0: PRE-FLIGHT CHECKS
################################################################################

block_preflight_checks() {
    if ! ask_continue "Pre-Flight Checks" \
        "Check if Nym node is already configured and warn about existing setup"; then
        return 0
    fi
    
    # Check if nym_node_id is set from environment
    if [[ -f "$HOME/.bash_profile" ]]; then
        source "$HOME/.bash_profile" 2>/dev/null
    fi
    
    if [[ -n "$nym_node_id" ]]; then
        local config_file="$HOME/.nym/nym-nodes/$nym_node_id/config/config.toml"
        
        if [[ -f "$config_file" ]]; then
            print_warning "Nym node configuration already exists for node: $nym_node_id"
            print_info "Config file: $config_file"
            
            # Check existing values
            local existing_hostname=$(grep "^hostname = " "$config_file" 2>/dev/null | cut -d"'" -f2)
            local existing_landing=$(grep "^landing_page_assets_path = " "$config_file" 2>/dev/null | cut -d"'" -f2)
            local existing_wss=$(grep "^announce_wss_port = " "$config_file" 2>/dev/null | awk '{print $3}')
            
            if [[ -n "$existing_hostname" ]]; then
                print_info "Existing hostname: $existing_hostname"
            fi
            if [[ -n "$existing_landing" ]]; then
                print_info "Existing landing page path: $existing_landing"
            fi
            if [[ -n "$existing_wss" ]]; then
                print_info "Existing WSS port: $existing_wss"
            fi
            
            echo -e "\n${YELLOW}This script will modify the existing configuration.${NC}"
            echo -e "${YELLOW}Backups will be created automatically.${NC}\n"
            read -r -p "Continue with existing node configuration? [Y/n]: " continue_existing
            
            if [[ "$continue_existing" =~ ^[Nn]$ ]]; then
                print_warning "User chose not to continue with existing configuration"
                exit 0
            fi
        fi
    fi
    
    print_success "Pre-flight checks completed"
}

################################################################################
# BLOCK 1: PRELIMINARY CHECKS & SERVER PREPARATION
################################################################################

block_preliminary_checks() {
    if ! ask_continue "Preliminary Checks & Server Preparation" \
        "Check system requirements, install dependencies, verify environment"; then
        return 0
    fi
    
    # Check sudo/root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        handle_error "Insufficient permissions"
        return 1
    fi
    print_success "Running with appropriate privileges"
    
    # Check disk space
    check_disk_space
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        print_info "Detected OS: $PRETTY_NAME"
        if [[ "$ID" == "ubuntu" ]]; then
            if [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]]; then
                print_success "Ubuntu version supported"
            else
                print_warning "Ubuntu version $VERSION_ID is not 22.04 or 24.04. Continuing anyway..."
            fi
        else
            print_warning "Not running Ubuntu. Continuing anyway..."
        fi
    fi
    
    # Update package lists
    print_info "Updating package lists"
    show_progress "Updating"
    if apt update -y >> "$LOG_FILE" 2>&1; then
        print_success "Package lists updated"
    else
        print_warning "Failed to update package lists"
    fi
    
    # Install dependencies
    print_info "Installing required packages: nginx, certbot, python3-certbot-nginx, ufw, curl, wget, dnsutils"
    local packages=(nginx certbot python3-certbot-nginx ufw curl wget dnsutils)
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            print_success "$pkg already installed"
        else
            print_info "Installing $pkg"
            show_progress "Installing $pkg"
            if apt install -y "$pkg" >> "$LOG_FILE" 2>&1; then
                print_success "$pkg installed successfully"
            else
                print_error "Failed to install $pkg"
                handle_error "Package installation failed for $pkg"
            fi
        fi
    done
    
    # Check nym-node service
    if systemctl list-unit-files | grep -q "nym-node.service"; then
        print_info "Checking nym-node service status..."
        systemctl status nym-node --no-pager -l >> "$LOG_FILE" 2>&1
        if systemctl is-active --quiet nym-node; then
            print_success "nym-node service is active"
        else
            print_warning "nym-node service exists but is not active"
        fi
    else
        print_warning "nym-node service not found"
    fi
    
    print_success "Preliminary checks completed"
}

################################################################################
# BLOCK 2: USER INPUT COLLECTION
################################################################################

block_user_input() {
    if ! ask_continue "User Input Collection" \
        "Collect node ID, domain name, and email addresses"; then
        return 0
    fi

    # DNS reminder
    echo -e "
${YELLOW}${BOLD}⚠ IMPORTANT DNS REMINDER${NC}"
    echo -e "${YELLOW}Before proceeding, ensure you have created:${NC}"
    echo -e "${YELLOW}  • A Record pointing to your server's IPv4 address${NC}"
    echo -e "${YELLOW}  • AAAA Record pointing to your server's IPv6 address${NC}"
    echo -e "${YELLOW}at your domain hosting provider.${NC}
"
    read -r -p "Press [ENTER] to continue..."

    # Get nym_node_id (check if imported first)
    if [[ -z "$nym_node_id" ]]; then
        # Try to load from bash_profile
        if [[ -f "$HOME/.bash_profile" ]]; then
            source "$HOME/.bash_profile"
        fi
    fi

    if [[ -z "$nym_node_id" ]]; then
        while true; do
            read -r -p "$(echo -e ${BOLD})Enter your Nym node ID: $(echo -e ${NC})" nym_node_id
            if [[ -n "$nym_node_id" ]]; then
                print_success "Node ID set: $nym_node_id"
                break
            else
                print_error "Node ID cannot be empty"
            fi
        done
    else
        print_success "Node ID loaded from environment: $nym_node_id"
    fi

    # Get hostname (domain) - check if imported first
    if [[ -z "$HOSTNAME" ]]; then
        while true; do
            read -r -p "$(echo -e ${BOLD})Enter your domain name (e.g., nym.example.com): $(echo -e ${NC})" HOSTNAME
            if validate_domain "$HOSTNAME"; then
                print_success "Domain name set: $HOSTNAME"
                break
            else
                print_error "Invalid domain format. Please enter a valid domain name."
            fi
        done
    else
        print_success "Domain name imported from parent script: $HOSTNAME"
        # Validate imported hostname
        if ! validate_domain "$HOSTNAME"; then
            print_warning "Imported hostname is invalid, please enter a new one"
            while true; do
                read -r -p "$(echo -e ${BOLD})Enter your domain name (e.g., nym.example.com): $(echo -e ${NC})" HOSTNAME
                if validate_domain "$HOSTNAME"; then
                    print_success "Domain name set: $HOSTNAME"
                    break
                else
                    print_error "Invalid domain format. Please enter a valid domain name."
                fi
            done
        fi
    fi

    # Get email for certbot
    print_info "Email for Certbot SSL certificate (optional - press ENTER to skip)"
    read -r -p "$(echo -e ${BOLD})Email: $(echo -e ${NC})" CERTBOT_EMAIL
    if [[ -n "$CERTBOT_EMAIL" ]]; then
        if validate_email "$CERTBOT_EMAIL"; then
            print_success "Email set: $CERTBOT_EMAIL"
        else
            print_warning "Invalid email format. Will use --register-unsafely-without-email flag"
            CERTBOT_EMAIL=""
        fi
    else
        print_info "No email provided. Will use --register-unsafely-without-email flag"
    fi

    print_success "User input collection completed"
}

################################################################################
# BLOCK 3: DNS VERIFICATION (OPTIONAL)
################################################################################

block_dns_verification() {
    if ! ask_continue "DNS Verification" \
        "Verify DNS A and AAAA records for your domain"; then
        return 0
    fi
    
    while true; do
        print_info "Checking DNS records for $HOSTNAME..."
        check_dns_records "$HOSTNAME"
        local dns_status=$?
        
        if [[ $dns_status -eq 0 ]]; then
            print_success "Both A and AAAA records are correctly configured"
            break
        elif [[ $dns_status -eq 1 ]]; then
            print_warning "Only one DNS record (A or AAAA) is correctly configured"
            echo -e "\n${YELLOW}Options:${NC}"
            echo -e "  [ENTER] Re-check DNS records"
            echo -e "  [S] Skip and continue anyway"
            read -r dns_choice
            
            if [[ "$dns_choice" =~ ^[Ss]$ ]]; then
                print_warning "DNS verification skipped by user"
                break
            fi
        elif [[ $dns_status -eq 2 ]]; then
            print_error "DNS tools not available"
            break
        else
            print_error "A and/or AAAA records not found or incorrect"
            echo -e "\n${YELLOW}${BOLD}Please create DNS records at your domain provider:${NC}"
            echo -e "${YELLOW}  • A Record: $HOSTNAME → $(curl -s -4 ifconfig.me 2>/dev/null)${NC}"
            echo -e "${YELLOW}  • AAAA Record: $HOSTNAME → $(curl -s -6 ifconfig.me 2>/dev/null)${NC}"
            echo -e "\n${YELLOW}DNS propagation can take 5-30 minutes.${NC}\n"
            
            echo -e "${YELLOW}Options:${NC}"
            echo -e "  [ENTER] Re-check DNS records after adding them"
            echo -e "  [S] Skip DNS verification"
            read -r dns_choice
            
            if [[ "$dns_choice" =~ ^[Ss]$ ]]; then
                print_warning "DNS verification skipped by user"
                break
            fi
        fi
        
        echo ""
    done
    
    print_success "DNS verification completed"
}

################################################################################
# BLOCK 4: PORT USAGE CHECK
################################################################################

block_port_check() {
    if ! ask_continue "Port Usage Check" \
        "Verify required ports are not in use by other services"; then
        return 0
    fi
    
    print_info "Checking TCP ports: ${REQUIRED_PORTS_TCP[*]}"
    local nginx_port_in_use=false
    
    for port in "${REQUIRED_PORTS_TCP[@]}"; do
        if check_port_usage "$port" "tcp"; then
            local process=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $6}' | head -1)
            
            # Special handling for port 8080 (common nginx port)
            if [[ "$port" == "8080" ]] && echo "$process" | grep -q "nginx"; then
                print_info "Port $port/tcp is in use by nginx (this is expected)"
                nginx_port_in_use=true
            else
                print_warning "Port $port/tcp is already in use by: $process"
            fi
        else
            print_success "Port $port/tcp is available"
        fi
    done
    
    print_info "Checking UDP ports: ${REQUIRED_PORTS_UDP[*]}"
    for port in "${REQUIRED_PORTS_UDP[@]}"; do
        if check_port_usage "$port" "udp"; then
            local process=$(ss -ulnp 2>/dev/null | grep ":${port} " | awk '{print $5}' | head -1)
            print_warning "Port $port/udp is already in use by: $process"
        else
            print_success "Port $port/udp is available"
        fi
    done
    
    # Check additional ports (80, 443, 9000)
    print_info "Checking web service ports: 80, 443, 9000"
    for port in 80 443 9000; do
        if check_port_usage "$port" "tcp"; then
            local process=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $6}' | head -1)
            
            # Port 80 often used by nginx - this is OK
            if [[ "$port" == "80" ]] && echo "$process" | grep -q "nginx"; then
                print_info "Port $port/tcp is in use by nginx (this is expected and OK)"
            else
                print_warning "Port $port/tcp is already in use by: $process"
            fi
        else
            print_success "Port $port/tcp is available"
        fi
    done
    
    if [[ "$nginx_port_in_use" == true ]]; then
        print_info "Nginx is already using expected ports - this is normal for running nodes"
    fi
    
    print_success "Port check completed"
}

################################################################################
# BLOCK 5: UFW FIREWALL CONFIGURATION
################################################################################

block_ufw_configuration() {
    if ! ask_continue "UFW Firewall Configuration" \
        "Configure firewall rules for Nym node and web services"; then
        return 0
    fi
    
    # Check SSH port
    local ssh_port=22
    if [[ -f /etc/ssh/sshd_config ]]; then
        local custom_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [[ -n "$custom_port" ]]; then
            ssh_port="$custom_port"
            print_info "Detected custom SSH port: $ssh_port"
        else
            print_info "Using default SSH port: 22"
        fi
    fi
    
    # Check if SSH port is allowed in UFW
    if ! ufw status | grep -q "${ssh_port}/tcp"; then
        print_warning "SSH port $ssh_port is not allowed in UFW"
        echo -e "${YELLOW}${BOLD}⚠ WARNING: Enabling UFW without allowing SSH may lock you out!${NC}"
        read -r -p "Allow SSH port $ssh_port in UFW? [Y/n]: " allow_ssh
        if [[ ! "$allow_ssh" =~ ^[Nn]$ ]]; then
            if ufw allow "${ssh_port}/tcp" comment "SSH" >> "$LOG_FILE" 2>&1; then
                print_success "SSH port $ssh_port allowed in UFW"
            else
                print_error "Failed to allow SSH port"
                handle_error "UFW SSH rule creation failed"
            fi
        fi
    else
        print_success "SSH port $ssh_port is already allowed in UFW"
    fi
    
    # Add Nginx Full profile
    print_info "Adding Nginx Full profile (ports 80, 443)..."
    if ufw allow 'Nginx Full' comment "Nginx app" >> "$LOG_FILE" 2>&1; then
        print_success "Nginx Full profile added"
    else
        print_info "Nginx Full profile may already exist"
    fi
    
    # Add TCP ports with comments
    print_info "Adding Nym-specific TCP port rules..."
    
    ufw allow 1789/tcp comment "Nym specific (Mix port)" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 1789/tcp (Mix port) allowed" || \
        print_info "Port 1789/tcp rule may already exist"
    
    ufw allow 1790/tcp comment "Nym specific (Verloc port)" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 1790/tcp (Verloc port) allowed" || \
        print_info "Port 1790/tcp rule may already exist"
    
    ufw allow 8080/tcp comment "Nym specific - Nym node API" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 8080/tcp (Nym node API) allowed" || \
        print_info "Port 8080/tcp rule may already exist"
    
    ufw allow 9000/tcp comment "Nym Specific - Client WS API port" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 9000/tcp (Client WS API) allowed" || \
        print_info "Port 9000/tcp rule may already exist"
    
    ufw allow 9001/tcp comment "Nym specific - WSS port" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 9001/tcp (WSS port) allowed" || \
        print_info "Port 9001/tcp rule may already exist"
    
    # Add UDP ports with comments
    print_info "Adding UDP port rules..."
    
    ufw allow 51822/udp comment "WireGuard" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 51822/udp (WireGuard) allowed" || \
        print_info "Port 51822/udp rule may already exist"
    
    ufw allow 4443/udp comment "nym-bridge QUIC transport" >> "$LOG_FILE" 2>&1 && \
        print_success "Port 4443/udp (nym-bridge QUIC) allowed" || \
        print_info "Port 4443/udp rule may already exist"
    
    # Add WireGuard interface rule (will succeed even if interface doesn't exist yet)
    print_info "Adding WireGuard interface bandwidth rule..."
    if ufw allow in on nymwg to any port 51830 proto tcp comment "Bandwidth queries/topup" >> "$LOG_FILE" 2>&1; then
        print_success "WireGuard bandwidth rule added (will be active when nymwg interface exists)"
    else
        print_info "WireGuard bandwidth rule may already exist"
    fi
    
    # Check UFW status
    print_info "Current UFW status:"
    ufw status | tee -a "$LOG_FILE"
    
    if ! ufw status | grep -q "Status: active"; then
        echo -e "\n${YELLOW}UFW is currently inactive${NC}"
        print_info "Added rules (not yet active):"
        ufw show added | tee -a "$LOG_FILE"
        
        read -r -p "Enable UFW now? [y/N]: " enable_ufw
        if [[ "$enable_ufw" =~ ^[Yy]$ ]]; then
            if echo "y" | ufw enable >> "$LOG_FILE" 2>&1; then
                print_success "UFW enabled"
            else
                print_error "Failed to enable UFW"
                handle_error "UFW enable failed"
            fi
        else
            print_info "UFW remains disabled. Enable it later with: sudo ufw enable"
        fi
    else
        print_success "UFW is active"
    fi
    
    print_success "UFW configuration completed"
}

################################################################################
# BLOCK 6: NGINX SETUP
################################################################################

block_nginx_setup() {
    if ! ask_continue "Nginx Initial Setup" \
        "Prepare Nginx web server and remove default configuration"; then
        return 0
    fi
    
    # Unlink default site
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        print_info "Removing default Nginx site..."
        if unlink /etc/nginx/sites-enabled/default 2>> "$LOG_FILE"; then
            print_success "Default site removed"
        else
            print_error "Failed to remove default site"
        fi
    else
        print_info "Default Nginx site already removed"
    fi
    
    # Restart nginx
    print_info "Restarting Nginx"
    show_progress "Restarting Nginx"
    if systemctl restart nginx >> "$LOG_FILE" 2>&1; then
        print_success "Nginx restarted successfully"
    else
        print_error "Failed to restart Nginx"
        handle_error "Nginx restart failed"
    fi
    
    print_success "Nginx setup completed"
}

################################################################################
# BLOCK 7: LANDING PAGE CREATION
################################################################################

block_landing_page() {
    if ! ask_continue "Landing Page Creation" \
        "Create HTML landing page for your Nym node"; then
        return 0
    fi
    
    # Create directory
    local web_dir="/var/www/$HOSTNAME"
    print_info "Creating web directory: $web_dir"
    if mkdir -p "$web_dir" 2>> "$LOG_FILE"; then
        print_success "Directory created"
    else
        print_error "Failed to create directory"
        handle_error "Directory creation failed"
        return 1
    fi
    
    # Download landing page template
    local template_url="https://raw.githubusercontent.com/nymtech/nym/refs/heads/develop/scripts/nym-node-setup/landing-page.html"
    local landing_page="$web_dir/index.html"
    
    print_info "Downloading landing page template"
    show_progress "Downloading template"
    if curl -sL "$template_url" -o "$landing_page" >> "$LOG_FILE" 2>&1; then
        print_success "Template downloaded"
    else
        print_error "Failed to download template"
        handle_error "Template download failed"
        return 1
    fi
    
    # Ask for email with validation loop
    local contact_email=""
    while true; do
        read -r -p "$(echo -e ${BOLD})Enter your contact email for landing page: $(echo -e ${NC})" contact_email
        
        if validate_email "$contact_email"; then
            # Add email to landing page
            if sed -i "s/<YOUR_EMAIL_ADDRESS>/$contact_email/" "$landing_page" 2>> "$LOG_FILE"; then
                print_success "Email added to landing page: $contact_email"
                break
            else
                print_error "Failed to add email to landing page"
                handle_error "Email insertion failed"
                break
            fi
        else
            print_error "Invalid email format. Please enter a valid email address."
        fi
    done
    
    # Add comment with node info
    local comment="<!-- Nym Node: $nym_node_id | Domain: $HOSTNAME | Setup: $(date) -->"
    if sed -i "1i $comment" "$landing_page" 2>> "$LOG_FILE"; then
        print_success "Node info added to landing page"
    else
        print_warning "Failed to add comment"
    fi
    
    # Show first line of index.html for verification
    print_info "First line of index.html:"
    echo -e "${CYAN}$(head -1 "$landing_page")${NC}"
    
    print_success "Landing page created at $landing_page"
}

################################################################################
# BLOCK 8: NYM NODE CONFIG MODIFICATION
################################################################################

block_nym_config() {
    if ! ask_continue "Nym Node Configuration" \
        "Update config.toml with landing page path, hostname, and WSS port"; then
        return 0
    fi
    
    local config_file="$HOME/.nym/nym-nodes/$nym_node_id/config/config.toml"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Config file not found: $config_file"
        handle_error "Config file missing"
        return 1
    fi
    
    print_success "Config file found: $config_file"
    
    # Backup config
    create_backup "$config_file"
    
    local changes_made=false
    
    # Check and update landing_page_assets_path
    print_info "Checking landing_page_assets_path..."
    local current_landing_path=$(grep "^landing_page_assets_path = " "$config_file" | cut -d"'" -f2)
    local expected_landing_path="/var/www/$HOSTNAME/index.html"
    
    if [[ "$current_landing_path" == "$expected_landing_path" ]]; then
        print_info "landing_page_assets_path already configured: $current_landing_path"
    else
        print_info "Updating landing_page_assets_path..."
        if sed -i "s|^landing_page_assets_path = .*|landing_page_assets_path = '$expected_landing_path'|" "$config_file" 2>> "$LOG_FILE"; then
            print_success "landing_page_assets_path updated to: $expected_landing_path"
            changes_made=true
        else
            print_error "Failed to update landing_page_assets_path"
            handle_error "Config update failed"
        fi
    fi
    
    # Check and update announce_wss_port
    print_info "Checking announce_wss_port..."
    local current_wss_port=$(grep "^announce_wss_port = " "$config_file" | awk '{print $3}')
    
    if [[ "$current_wss_port" == "9001" ]]; then
        print_info "announce_wss_port already configured: 9001"
    else
        print_info "Updating announce_wss_port..."
        if sed -i "s|^announce_wss_port = .*|announce_wss_port = 9001|" "$config_file" 2>> "$LOG_FILE"; then
            print_success "announce_wss_port updated to: 9001"
            changes_made=true
        else
            print_error "Failed to update announce_wss_port"
            handle_error "Config update failed"
        fi
    fi
    
    # Check and update hostname
    print_info "Checking hostname..."
    local current_hostname=$(grep "^hostname = " "$config_file" | cut -d"'" -f2)
    
    if [[ "$current_hostname" == "$HOSTNAME" ]]; then
        print_info "hostname already configured: $HOSTNAME"
    else
        if [[ -n "$current_hostname" ]]; then
            print_warning "Config has existing hostname: $current_hostname"
            print_info "New hostname will be: $HOSTNAME"
        fi
        
        print_info "Updating hostname..."
        if sed -i "s|^hostname = .*|hostname = '$HOSTNAME'|" "$config_file" 2>> "$LOG_FILE"; then
            print_success "hostname updated to: $HOSTNAME"
            changes_made=true
        else
            print_error "Failed to update hostname"
            handle_error "Config update failed"
        fi
    fi
    
    # Set global flag if changes were made
    if [[ "$changes_made" == true ]]; then
        CONFIG_MODIFIED=true
    fi
    
    print_success "Nym node configuration completed"
}

################################################################################
# BLOCK 9: NGINX SITE CONFIGURATION
################################################################################

block_nginx_site_config() {
    if ! ask_continue "Nginx Site Configuration" \
        "Create Nginx configuration for your domain"; then
        return 0
    fi
    
    local nginx_config="/etc/nginx/sites-available/$HOSTNAME"
    
    # Check if config exists
    if [[ -f "$nginx_config" ]]; then
        print_warning "Nginx config already exists: $nginx_config"
        create_backup "$nginx_config"
        print_info "Overwriting existing configuration..."
    fi
    
    # Create nginx config
    print_info "Creating Nginx site configuration..."
    cat > "$nginx_config" << EOF
server {
    listen 80;
    listen [::]:80;

    server_name $HOSTNAME;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "Nginx config created: $nginx_config"
    else
        print_error "Failed to create Nginx config"
        handle_error "Nginx config creation failed"
        return 1
    fi
    
    # Create symlink
    print_info "Enabling site configuration..."
    if [[ -L "/etc/nginx/sites-enabled/$HOSTNAME" ]]; then
        print_info "Symlink already exists"
    else
        if ln -s "$nginx_config" /etc/nginx/sites-enabled/ 2>> "$LOG_FILE"; then
            print_success "Site enabled"
        else
            print_error "Failed to create symlink"
            handle_error "Symlink creation failed"
        fi
    fi
    
    # Test nginx config
    print_info "Testing Nginx configuration..."
    if nginx -t >> "$LOG_FILE" 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        handle_error "Nginx config test failed"
        return 1
    fi
    
    print_success "Nginx site configuration completed"
}

################################################################################
# BLOCK 10: SSL CERTIFICATE SETUP
################################################################################

block_ssl_certificate() {
    if ! ask_continue "SSL Certificate Setup" \
        "Request/recreate Let's Encrypt SSL certificate with Certbot"; then
        return 0
    fi
    
    # Certbot rate limit warning
    echo -e "\n${YELLOW}${BOLD}⚠ CERTBOT RATE LIMITS${NC}"
    echo -e "${YELLOW}Let's Encrypt allows 5 certificate requests per domain per week.${NC}"
    echo -e "${YELLOW}If you've requested certificates recently, this may fail.${NC}"
    echo -e "${YELLOW}Failed requests also count towards the limit.${NC}\n"
    read -r -p "Continue with certificate request? [Y/n]: " continue_cert
    
    if [[ "$continue_cert" =~ ^[Nn]$ ]]; then
        print_warning "SSL certificate setup skipped by user"
        return 0
    fi
    
    # Check if certificate exists
    if certbot certificates -d "$HOSTNAME" 2>/dev/null | grep -q "Certificate Name: $HOSTNAME"; then
        print_warning "Certificate already exists for $HOSTNAME"
        print_info "Revoking and recreating certificate..."
        
        if certbot revoke --cert-name "$HOSTNAME" --non-interactive >> "$LOG_FILE" 2>&1; then
            print_success "Old certificate revoked"
        else
            print_warning "Failed to revoke old certificate (may not exist)"
        fi
        
        if certbot delete --cert-name "$HOSTNAME" --non-interactive >> "$LOG_FILE" 2>&1; then
            print_success "Old certificate deleted"
        else
            print_warning "Failed to delete old certificate"
        fi
    fi
    
    # Build certbot command
    local certbot_cmd="certbot --nginx --non-interactive --agree-tos --redirect"
    
    if [[ -n "$CERTBOT_EMAIL" ]]; then
        certbot_cmd="$certbot_cmd -m $CERTBOT_EMAIL"
    else
        certbot_cmd="$certbot_cmd --register-unsafely-without-email"
    fi
    
    certbot_cmd="$certbot_cmd -d $HOSTNAME"
    
    # Request certificate
    print_info "Requesting SSL certificate"
    show_progress "Requesting certificate"
    print_info "Command: $certbot_cmd"
    
    if eval "$certbot_cmd" >> "$LOG_FILE" 2>&1; then
        print_success "SSL certificate obtained successfully"
    else
        print_error "Failed to obtain SSL certificate"
        echo -e "\n${YELLOW}Last 20 lines from log:${NC}"
        tail -20 "$LOG_FILE"
        handle_error "Certbot certificate request failed"
        return 1
    fi
    
    print_success "SSL certificate setup completed"
}

################################################################################
# BLOCK 11: WSS CONFIGURATION
################################################################################

block_wss_config() {
    if ! ask_continue "WebSocket Secure (WSS) Configuration" \
        "Configure Nginx for secure WebSocket connections on port 9001"; then
        return 0
    fi
    
    local wss_config="/etc/nginx/sites-available/wss-config-nym"
    
    # Check if config exists
    if [[ -f "$wss_config" ]]; then
        print_warning "WSS config already exists: $wss_config"
        create_backup "$wss_config"
        print_info "Overwriting existing configuration..."
    fi
    
    # Create WSS config
    print_info "Creating WSS configuration..."
    cat > "$wss_config" << EOF
#############################################################
# Nym Node WSS Configuration
# Domain: $HOSTNAME
# WSS Port: 9001
#############################################################

server {
    listen 9001 ssl http2;
    listen [::]:9001 ssl http2;

    server_name $HOSTNAME;

    ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Ignore favicon requests
    location /favicon.ico {
        return 204;
        access_log     off;
        log_not_found  off;
    }

    location / {

        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, HEAD';
        add_header 'Access-Control-Allow-Headers' '*';

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header X-Forwarded-For \$remote_addr;

        proxy_pass http://localhost:9000;
        proxy_intercept_errors on;
    }
}
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "WSS config created: $wss_config"
    else
        print_error "Failed to create WSS config"
        handle_error "WSS config creation failed"
        return 1
    fi
    
    # Create symlink
    print_info "Enabling WSS configuration..."
    if [[ -L "/etc/nginx/sites-enabled/wss-config-nym" ]]; then
        print_info "Symlink already exists"
    else
        if ln -s "$wss_config" /etc/nginx/sites-enabled/ 2>> "$LOG_FILE"; then
            print_success "WSS config enabled"
        else
            print_error "Failed to create symlink"
            handle_error "Symlink creation failed"
        fi
    fi
    
    print_success "WSS configuration completed"
}

################################################################################
# BLOCK 12: FINAL NGINX VERIFICATION & RESTART
################################################################################

block_nginx_final_verification() {
    if ! ask_continue "Nginx Verification & Restart" \
        "Test Nginx configuration and reload Nginx service"; then
        return 0
    fi
    
    # Final nginx test
    print_info "Running final Nginx configuration test..."
    if nginx -t >> "$LOG_FILE" 2>&1; then
        print_success "Nginx configuration is valid"
        
        # Reload nginx
        print_info "Reloading Nginx"
        show_progress "Reloading Nginx"
        if systemctl reload nginx >> "$LOG_FILE" 2>&1; then
            print_success "Nginx reloaded successfully"
        else
            print_error "Failed to reload Nginx"
            handle_error "Nginx reload failed"
        fi
    else
        print_error "Nginx configuration test failed"
        nginx -t
        handle_error "Nginx config test failed"
    fi
    
    # Check nginx status
    print_info "Checking Nginx service status..."
    if systemctl is-active --quiet nginx; then
        print_success "Nginx service is active and running"
    else
        print_error "Nginx service is not active"
        systemctl status nginx --no-pager -l
        handle_error "Nginx service issue"
    fi
    
    print_success "Final verification completed"
}

################################################################################
# BLOCK 13: POST-SETUP TESTING
################################################################################

block_post_testing() {
    if ! ask_continue "Post-Setup Testing" \
        "Test HTTP redirect, HTTPS access, and landing page"; then
        return 0
    fi
    
    # Test HTTP to HTTPS redirect
    print_info "Testing HTTP to HTTPS redirect"
    show_progress "Testing redirect"
    local redirect_test=$(curl -Is "http://$HOSTNAME" 2>/dev/null | head -1)
    if echo "$redirect_test" | grep -q "301\|302"; then
        print_success "HTTP redirect is working"
        local redirect_location=$(curl -Is "http://$HOSTNAME" 2>/dev/null | grep -i "^location:" | awk '{print $2}' | tr -d '\r')
        print_info "Redirects to: $redirect_location"
    else
        print_warning "HTTP redirect test inconclusive: $redirect_test"
    fi
    
    # Test HTTPS access
    print_info "Testing HTTPS access"
    show_progress "Testing HTTPS"
    local https_test=$(curl -Is "https://$HOSTNAME" 2>/dev/null | head -1)
    if echo "$https_test" | grep -q "200 OK"; then
        print_success "HTTPS access is working"
    else
        print_warning "HTTPS test result: $https_test"
    fi
    
    # Test landing page
    print_info "Testing landing page content"
    show_progress "Testing landing page"
    if curl -s "https://$HOSTNAME" 2>/dev/null | grep -q "Nym"; then
        print_success "Landing page is accessible and contains expected content"
    else
        print_warning "Landing page test inconclusive"
    fi
    
    print_success "Post-setup testing completed"
}

################################################################################
# FINAL SUMMARY
################################################################################

show_summary() {
    print_header "SETUP SUMMARY"
    
    echo -e "${BOLD}Configuration Details:${NC}"
    echo -e "  ${CYAN}Node ID:${NC} $nym_node_id"
    echo -e "  ${CYAN}Domain:${NC} $HOSTNAME"
    echo -e "  ${CYAN}Landing Page:${NC} https://$HOSTNAME"
    echo -e "  ${CYAN}Log File:${NC} $LOG_FILE"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo -e "  ${CYAN}Backups:${NC} $BACKUP_DIR"
    fi
    
    # DNS recheck
    echo -e "\n${BOLD}DNS Records Status (Final Check):${NC}"
    check_dns_records "$HOSTNAME" > /dev/null 2>&1
    local final_dns_status=$?
    
    if [[ $final_dns_status -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Both A and AAAA records are correctly configured"
    elif [[ $final_dns_status -eq 1 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Only partial DNS configuration detected"
    else
        echo -e "  ${RED}✗${NC} DNS records not properly configured or not propagated yet"
    fi
    
    echo -e "\n${BOLD}SSL Certificate Status:${NC}"
    if certbot certificates -d "$HOSTNAME" 2>/dev/null | grep -q "Certificate Name: $HOSTNAME"; then
        echo -e "  ${GREEN}✓${NC} Certificate obtained for $HOSTNAME"
        certbot certificates -d "$HOSTNAME" 2>/dev/null | grep -E "Expiry Date|Domains" | sed 's/^/  /'
    else
        echo -e "  ${RED}✗${NC} No certificate found"
    fi
    
    echo -e "\n${BOLD}Nginx Service Status:${NC}"
    if systemctl is-active --quiet nginx; then
        echo -e "  ${GREEN}✓${NC} Nginx is active and running"
        
        # Check for recent errors in nginx logs
        if [[ -f /var/log/nginx/error.log ]]; then
            local error_count=$(grep -c "error" /var/log/nginx/error.log 2>/dev/null | tail -20 || echo "0")
            if [[ $error_count -gt 0 ]]; then
                echo -e "  ${YELLOW}⚠${NC} Recent errors detected in nginx logs (last 20 lines):"
                tail -20 /var/log/nginx/error.log | grep "error" | sed 's/^/    /'
            fi
        fi
    else
        echo -e "  ${RED}✗${NC} Nginx is not active"
    fi
    
    echo -e "\n${BOLD}UFW Firewall Status:${NC}"
    if ufw status | grep -q "Status: active"; then
        echo -e "  ${GREEN}✓${NC} UFW is active"
        echo -e "  ${CYAN}Open ports:${NC}"
        ufw status | grep "ALLOW" | sed 's/^/    /'
    else
        echo -e "  ${YELLOW}⚠${NC} UFW is inactive"
        echo -e "  ${CYAN}Added rules (not active):${NC}"
        ufw show added 2>/dev/null | sed 's/^/    /'
    fi
    
    echo -e "\n${BOLD}${YELLOW}Next Steps:${NC}"
    
    if [[ "$CONFIG_MODIFIED" == true ]]; then
        echo -e "  ${YELLOW}1. Your node's config.toml was modified. Restart your nym-node service:${NC}"
        echo -e "     ${CYAN}sudo systemctl restart nym-node${NC}"
        echo -e ""
        echo -e "  ${YELLOW}2. Test WSS connection from an external device:${NC}"
    else
        echo -e "  ${YELLOW}1. Test WSS connection from an external device:${NC}"
    fi
    echo -e "     ${CYAN}wscat -c wss://$HOSTNAME:9001${NC}"
    echo -e "     ${YELLOW}Note: This must be run from a different server/machine${NC}"
    
    echo -e "\n${GREEN}${BOLD}Setup completed successfully!${NC}"
    echo -e "${CYAN}Thank you for running a Nym node!${NC}\n"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    clear
    echo -e "${BLUE}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     Nym Node - Reverse Proxy & WSS Configuration Script      ║
║                                                               ║
║                    Ubuntu 22.04 / 24.04                       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    log "=== Script started ==="
    log "User: $(whoami)"
    log "Date: $(date)"
    log "Hostname: $(hostname)"
    
    # Execute blocks
    block_preflight_checks
    block_preliminary_checks
    block_user_input
    block_dns_verification
    block_port_check
    block_ufw_configuration
    block_nginx_setup
    block_landing_page
    block_nym_config
    block_nginx_site_config
    block_ssl_certificate
    block_wss_config
    block_final_verification
    block_post_testing
    
    # Show summary
    show_summary
    
    log "=== Script completed ==="
}

# Run main function
main
