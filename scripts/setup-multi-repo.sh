#!/bin/bash

# Multi-Repository GitHub Release Monitor Setup Script
# This script helps set up monitoring for multiple repositories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create system directories and users
setup_system() {
    log_info "Creating system directories and users..."
    
    # Create github-monitor user if it doesn't exist
    if ! id github-monitor &>/dev/null; then
        sudo useradd -r -s /bin/false github-monitor
        log_success "Created github-monitor user"
    else
        log_info "github-monitor user already exists"
    fi
    
    # Create directories
    sudo mkdir -p /opt/github-monitor/{configs,scripts}
    sudo mkdir -p /opt/releases
    sudo mkdir -p /var/log
    
    # Copy script files
    sudo cp "$PROJECT_ROOT/github-release-monitor.sh" /opt/github-monitor/
    sudo chmod +x /opt/github-monitor/github-release-monitor.sh
    
    # Set ownership
    sudo chown -R github-monitor:github-monitor /opt/github-monitor
    sudo chown github-monitor:github-monitor /opt/releases
    
    log_success "System setup completed"
}

# Function to install systemd services
install_systemd() {
    log_info "Installing systemd service templates..."
    
    sudo cp "$PROJECT_ROOT/systemd/github-release-monitor@.service" /etc/systemd/system/
    sudo cp "$PROJECT_ROOT/systemd/github-release-monitor@.timer" /etc/systemd/system/
    
    sudo systemctl daemon-reload
    
    log_success "Systemd templates installed"
}

# Function to create a new repository configuration
add_repository() {
    local repo_name="$1"
    local config_file="/opt/github-monitor/configs/${repo_name}.conf"
    
    if [[ -f "$config_file" ]]; then
        log_warning "Configuration for $repo_name already exists at $config_file"
        return 1
    fi
    
    # Use the base configuration as template
    sudo cp "$PROJECT_ROOT/github-release-monitor.conf" "$config_file"
    sudo chown github-monitor:github-monitor "$config_file"
    sudo chmod 600 "$config_file"
    
    log_success "Created configuration template for $repo_name at $config_file"
    log_info "Please edit $config_file to configure the repository settings"
    
    # Enable and start the timer
    sudo systemctl enable "github-release-monitor@${repo_name}.timer"
    sudo systemctl start "github-release-monitor@${repo_name}.timer"
    
    log_success "Enabled and started timer for $repo_name"
}

# Function to remove a repository configuration
remove_repository() {
    local repo_name="$1"
    local config_file="/opt/github-monitor/configs/${repo_name}.conf"
    
    # Stop and disable the timer
    sudo systemctl stop "github-release-monitor@${repo_name}.timer" 2>/dev/null || true
    sudo systemctl disable "github-release-monitor@${repo_name}.timer" 2>/dev/null || true
    
    # Remove configuration file
    if [[ -f "$config_file" ]]; then
        sudo rm "$config_file"
        log_success "Removed configuration for $repo_name"
    else
        log_warning "Configuration file for $repo_name not found"
    fi
}

# Function to list all configured repositories
list_repositories() {
    log_info "Configured repositories:"
    echo "========================="
    
    for config in /opt/github-monitor/configs/*.conf 2>/dev/null; do
        if [[ -f "$config" ]]; then
            repo_name=$(basename "$config" .conf)
            echo "Repository: $repo_name"
            
            # Check timer status
            if systemctl is-active --quiet "github-release-monitor@${repo_name}.timer" 2>/dev/null; then
                echo "  Timer: ✓ Active"
            else
                echo "  Timer: ✗ Inactive"
            fi
            
            # Get last run time
            last_run=$(systemctl show "github-release-monitor@${repo_name}.service" --property=ExecMainStartTimestamp --value 2>/dev/null || echo "Never")
            echo "  Last run: $last_run"
            
            # Get configuration details
            if [[ -r "$config" ]]; then
                owner=$(grep "^GITHUB_OWNER=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
                repo=$(grep "^GITHUB_REPO=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
                echo "  Repository: $owner/$repo"
            fi
            echo
        fi
    done
    
    if ! ls /opt/github-monitor/configs/*.conf &>/dev/null; then
        echo "No repositories configured"
    fi
}

# Function to show status of all repositories
show_status() {
    log_info "Repository Monitor Status:"
    echo "=========================="
    
    # Show systemd timers
    sudo systemctl list-timers github-release-monitor@* --no-legend 2>/dev/null || echo "No active timers found"
    
    echo
    list_repositories
}

# Main function
main() {
    case "${1:-}" in
        "setup")
            setup_system
            install_systemd
            ;;
        "add")
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 add <repository-name>"
                exit 1
            fi
            add_repository "$2"
            ;;
        "remove")
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 remove <repository-name>"
                exit 1
            fi
            remove_repository "$2"
            ;;
        "list")
            list_repositories
            ;;
        "status")
            show_status
            ;;
        "help"|"--help"|"-h")
            echo "Multi-Repository GitHub Release Monitor Setup"
            echo "Usage: $0 <command> [arguments]"
            echo
            echo "Commands:"
            echo "  setup                   - Initial system setup (run once)"
            echo "  add <repo-name>         - Add a new repository to monitor"
            echo "  remove <repo-name>      - Remove repository monitoring"
            echo "  list                    - List all configured repositories"
            echo "  status                  - Show status of all monitors"
            echo "  help                    - Show this help"
            echo
            echo "Examples:"
            echo "  $0 setup                # Initial setup"
            echo "  $0 add frontend-app     # Add frontend-app repository"
            echo "  $0 add backend-api      # Add backend-api repository"
            echo "  $0 list                 # List all repositories"
            echo "  $0 remove frontend-app  # Remove frontend-app"
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check if running as root for setup operations
if [[ "${1:-}" == "setup" ]] || [[ "${1:-}" == "add" ]] || [[ "${1:-}" == "remove" ]]; then
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This operation requires sudo privileges"
        exit 1
    fi
fi

main "$@"