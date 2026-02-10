#!/bin/bash

# GitHub Release Monitor Status Checker
# Displays the status of all configured repositories

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GitHub Release Monitor Status Check ===${NC}"
echo "Date: $(date)"
echo

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}systemctl not found. This script requires systemd.${NC}"
    exit 1
fi

# Check for configurations
config_count=$(find /opt/github-monitor/configs -name "*.conf" 2>/dev/null | wc -l)
if [[ $config_count -eq 0 ]]; then
    echo -e "${YELLOW}No repository configurations found in /opt/github-monitor/configs/${NC}"
    echo "Use './scripts/setup-multi-repo.sh add <repo-name>' to add repositories"
    exit 0
fi

echo -e "${BLUE}Configuration Summary:${NC}"
echo "======================"
echo "Configured repositories: $config_count"
echo

# Check systemd timers
echo -e "${BLUE}Active Timers:${NC}"
echo "=============="
active_timers=$(sudo systemctl list-timers github-release-monitor@* --no-legend 2>/dev/null | wc -l)
if [[ $active_timers -gt 0 ]]; then
    sudo systemctl list-timers github-release-monitor@* --no-legend 2>/dev/null
else
    echo -e "${YELLOW}No active timers found${NC}"
fi
echo

# Repository-specific status
echo -e "${BLUE}Repository Details:${NC}" 
echo "==================="

for config in /opt/github-monitor/configs/*.conf; do
    if [[ -f "$config" ]]; then
        repo_name=$(basename "$config" .conf)
        echo -e "${BLUE}Repository: $repo_name${NC}"
        
        # Check if timer is active
        if sudo systemctl is-active --quiet "github-release-monitor@${repo_name}.timer" 2>/dev/null; then
            echo -e "  Timer: ${GREEN}✓ Active${NC}"
        else
            echo -e "  Timer: ${RED}✗ Inactive${NC}"
        fi
        
        # Get last run time
        if sudo systemctl show "github-release-monitor@${repo_name}.service" --property=ExecMainStartTimestamp --value 2>/dev/null | grep -q "Thu 1970"; then
            echo -e "  Last run: ${YELLOW}Never${NC}"
        else
            last_run=$(sudo systemctl show "github-release-monitor@${repo_name}.service" --property=ExecMainStartTimestamp --value 2>/dev/null)
            echo "  Last run: $last_run"
        fi
        
        # Get exit status
        exit_status=$(sudo systemctl show "github-release-monitor@${repo_name}.service" --property=ExecMainStatus --value 2>/dev/null)
        if [[ "$exit_status" == "0" ]]; then
            echo -e "  Exit status: ${GREEN}$exit_status (Success)${NC}"
        elif [[ "$exit_status" == "" ]]; then
            echo -e "  Exit status: ${YELLOW}Never run${NC}"
        else
            echo -e "  Exit status: ${RED}$exit_status (Failed)${NC}"
        fi
        
        # Get configuration details if readable
        if [[ -r "$config" ]]; then
            owner=$(grep "^GITHUB_OWNER=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
            repo=$(grep "^GITHUB_REPO=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
            prefix=$(grep "^MINOR_VERSION_PREFIX=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
            download_dir=$(grep "^DOWNLOAD_DIR=" "$config" | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Not configured")
            
            echo "  Repository: $owner/$repo"
            echo "  Monitoring: $prefix.*"
            echo "  Download to: $download_dir"
            
            # Check if download directory exists and has content
            if [[ -d "$download_dir" ]]; then
                version_count=$(find "$download_dir" -maxdepth 1 -type d | wc -l)
                if [[ $version_count -gt 1 ]]; then
                    echo -e "  Downloaded versions: ${GREEN}$((version_count - 1))${NC}"
                    last_version=$(find "$download_dir" -maxdepth 1 -type d -name "v*" | sort -V | tail -n 1 | xargs basename 2>/dev/null || echo "None")
                    if [[ "$last_version" != "None" ]]; then
                        echo "  Latest version: $last_version"
                    fi
                else
                    echo -e "  Downloaded versions: ${YELLOW}0${NC}"
                fi
            else
                echo -e "  Download directory: ${RED}Does not exist${NC}"
            fi
        fi
        
        echo
    fi
done

# Overall health summary
echo -e "${BLUE}Health Summary:${NC}"
echo "==============="

failed_services=0
inactive_timers=0

for config in /opt/github-monitor/configs/*.conf; do
    if [[ -f "$config" ]]; then
        repo_name=$(basename "$config" .conf)
        
        # Check timer status
        if ! sudo systemctl is-active --quiet "github-release-monitor@${repo_name}.timer" 2>/dev/null; then
            ((inactive_timers++))
        fi
        
        # Check service exit status
        exit_status=$(sudo systemctl show "github-release-monitor@${repo_name}.service" --property=ExecMainStatus --value 2>/dev/null)
        if [[ "$exit_status" != "0" && "$exit_status" != "" ]]; then
            ((failed_services++))
        fi
    fi
done

if [[ $inactive_timers -eq 0 && $failed_services -eq 0 ]]; then
    echo -e "${GREEN}✓ All systems operational${NC}"
elif [[ $inactive_timers -gt 0 ]]; then
    echo -e "${YELLOW}⚠ $inactive_timers timer(s) inactive${NC}"
    echo "  Use: sudo systemctl start github-release-monitor@<repo-name>.timer"
elif [[ $failed_services -gt 0 ]]; then
    echo -e "${RED}✗ $failed_services service(s) failed last run${NC}"
    echo "  Check logs: sudo journalctl -u github-release-monitor@<repo-name>.service"
fi

echo
echo -e "${BLUE}Useful Commands:${NC}"
echo "================"
echo "View logs:        sudo journalctl -u 'github-release-monitor@*' -f"
echo "Start all timers: sudo systemctl start github-release-monitor@*.timer"
echo "Stop all timers:  sudo systemctl stop github-release-monitor@*.timer"
echo "Reload systemd:   sudo systemctl daemon-reload"