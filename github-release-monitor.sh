#!/bin/bash

# GitHub Release Monitor Script
# Monitors a private GitHub repository for new minor releases and downloads them
# Designed to run via cron

set -euo pipefail

# =============================================================================
# CONFIGURATION - Modify these variables as needed
# =============================================================================

# GitHub repository details
GITHUB_OWNER=""           # Repository owner (user or organization)
GITHUB_REPO=""            # Repository name
GITHUB_TOKEN=""           # GitHub personal access token for private repo access

# Release monitoring configuration
MINOR_VERSION_PREFIX=""   # e.g., "v1.2" to monitor 1.2.x releases
DOWNLOAD_DIR=""           # Directory to store downloaded releases
STATE_FILE=""             # File to store the last downloaded version

# Asset filtering (optional)
ASSET_PATTERN=".*"        # Regex pattern to match specific assets, default matches all

# Logging configuration
LOG_FILE=""               # Log file path, leave empty to disable file logging
VERBOSE=false             # Set to true for verbose output

# =============================================================================
# FUNCTIONS
# =============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]]; then
        echo "$log_entry" >&2
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# Validate configuration
validate_config() {
    local errors=()
    
    [[ -z "$GITHUB_OWNER" ]] && errors+=("GITHUB_OWNER is required")
    [[ -z "$GITHUB_REPO" ]] && errors+=("GITHUB_REPO is required")
    [[ -z "$GITHUB_TOKEN" ]] && errors+=("GITHUB_TOKEN is required")
    [[ -z "$MINOR_VERSION_PREFIX" ]] && errors+=("MINOR_VERSION_PREFIX is required")
    [[ -z "$DOWNLOAD_DIR" ]] && errors+=("DOWNLOAD_DIR is required")
    [[ -z "$STATE_FILE" ]] && errors+=("STATE_FILE is required")
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log "ERROR" "Configuration errors:"
        for error in "${errors[@]}"; do
            log "ERROR" "  - $error"
        done
        exit 1
    fi
}

# Create directories if they don't exist
setup_directories() {
    mkdir -p "$DOWNLOAD_DIR"
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -n "$LOG_FILE" ]] && mkdir -p "$(dirname "$LOG_FILE")"
}

# Get the latest release matching the minor version prefix
get_latest_release() {
    local api_url="https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases"
    local releases
    
    log "INFO" "Fetching releases from GitHub API..."
    
    releases=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$releases" ]]; then
        log "ERROR" "Failed to fetch releases from GitHub API"
        exit 1
    fi
    
    # Filter releases by minor version prefix and get the latest
    echo "$releases" | jq -r --arg prefix "$MINOR_VERSION_PREFIX" \
        '.[] | select(.tag_name | startswith($prefix)) | .tag_name' | \
        sort -V | tail -n 1
}

# Get currently stored version
get_current_version() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo ""
    fi
}

# Compare two version strings
version_greater_than() {
    local new_version="$1"
    local current_version="$2"
    
    if [[ -z "$current_version" ]]; then
        return 0  # No current version, so new version is greater
    fi
    
    # Use sort -V for version comparison
    local highest=$(printf '%s\n%s\n' "$current_version" "$new_version" | sort -V | tail -n 1)
    [[ "$highest" == "$new_version" && "$new_version" != "$current_version" ]]
}

# Download release assets
download_release() {
    local version="$1"
    local api_url="https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/tags/$version"
    local release_info
    local download_url
    local asset_name
    local download_path
    
    log "INFO" "Downloading release $version..."
    
    # Get release information
    release_info=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url")
    
    if [[ $? -ne 0 ]] || [[ -z "$release_info" ]]; then
        log "ERROR" "Failed to get release information for version $version"
        exit 1
    fi
    
    # Create version-specific directory
    local version_dir="$DOWNLOAD_DIR/$version"
    mkdir -p "$version_dir"
    
    # Process each asset
    local asset_count=0
    while IFS= read -r asset_info; do
        asset_name=$(echo "$asset_info" | jq -r '.name')
        download_url=$(echo "$asset_info" | jq -r '.url')
        
        # Skip if asset doesn't match pattern
        if [[ ! "$asset_name" =~ $ASSET_PATTERN ]]; then
            log "INFO" "Skipping asset $asset_name (doesn't match pattern)"
            continue
        fi
        
        download_path="$version_dir/$asset_name"
        
        log "INFO" "Downloading asset: $asset_name"
        
        # Download the asset
        if curl -L -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/octet-stream" \
            -o "$download_path" \
            "$download_url"; then
            log "INFO" "Successfully downloaded: $asset_name"
            ((asset_count++))
        else
            log "ERROR" "Failed to download: $asset_name"
            exit 1
        fi
    done < <(echo "$release_info" | jq -c '.assets[]')
    
    if [[ $asset_count -eq 0 ]]; then
        log "WARN" "No assets matching pattern '$ASSET_PATTERN' found for release $version"
    fi
    
    # Update state file
    echo "$version" > "$STATE_FILE"
    log "INFO" "Updated state file with version: $version"
}

# Cleanup old releases (keep only the latest N versions)
cleanup_old_releases() {
    local keep_count=${1:-3}  # Keep 3 versions by default
    
    if [[ ! -d "$DOWNLOAD_DIR" ]]; then
        return
    fi
    
    log "INFO" "Cleaning up old releases (keeping $keep_count most recent)..."
    
    # Get all version directories, sort by version, and remove old ones
    local version_dirs=()
    while IFS= read -r -d '' dir; do
        version_dirs+=("$dir")
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -type d -name "$MINOR_VERSION_PREFIX*" -print0 2>/dev/null)
    
    if [[ ${#version_dirs[@]} -le $keep_count ]]; then
        log "INFO" "No cleanup needed (${#version_dirs[@]} versions <= $keep_count)"
        return
    fi
    
    # Sort and remove excess versions
    local sorted_dirs=($(printf '%s\n' "${version_dirs[@]}" | sort -V))
    local remove_count=$((${#sorted_dirs[@]} - keep_count))
    
    for ((i=0; i<remove_count; i++)); do
        local dir_to_remove="${sorted_dirs[$i]}"
        log "INFO" "Removing old release directory: $(basename "$dir_to_remove")"
        rm -rf "$dir_to_remove"
    done
}

# Main execution function
main() {
    log "INFO" "Starting GitHub release monitor..."
    
    validate_config
    setup_directories
    
    local latest_version
    local current_version
    
    latest_version=$(get_latest_release)
    current_version=$(get_current_version)
    
    if [[ -z "$latest_version" ]]; then
        log "WARN" "No releases found matching prefix '$MINOR_VERSION_PREFIX'"
        exit 0
    fi
    
    log "INFO" "Latest release: $latest_version"
    log "INFO" "Current version: ${current_version:-"none"}"
    
    if version_greater_than "$latest_version" "$current_version"; then
        log "INFO" "New release available: $latest_version"
        download_release "$latest_version"
        cleanup_old_releases 3
        log "INFO" "Release update completed successfully"
    else
        log "INFO" "No new releases available"
    fi
    
    log "INFO" "GitHub release monitor finished"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --config|-c)
            CONFIG_FILE="$2"
            if [[ -f "$CONFIG_FILE" ]]; then
                # Source configuration file
                source "$CONFIG_FILE"
                log "INFO" "Loaded configuration from $CONFIG_FILE"
            else
                log "ERROR" "Configuration file not found: $CONFIG_FILE"
                exit 1
            fi
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -c, --config FILE    Load configuration from file"
            echo "  -v, --verbose        Enable verbose output"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "This script monitors a GitHub repository for new releases and downloads them."
            echo "Configure the script by editing the variables at the top of the file or"
            echo "by using a configuration file."
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Trap to handle interruption
trap 'log "ERROR" "Script interrupted"; exit 130' INT TERM

# Run main function
main

exit 0