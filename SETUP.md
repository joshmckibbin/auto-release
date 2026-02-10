# GitHub Release Monitor Setup Guide

This guide explains how to set up and configure the GitHub release monitoring system for multiple repositories on your server using the **Multiple Configuration Files** approach.

## Features

- ✅ **Multiple Repository Support** - Monitor multiple GitHub repositories simultaneously
- ✅ **Template-based Configuration** - Easy setup with systemd service templates
- ✅ **Automated Management** - Script-based setup and management
- ✅ **Private Repository Support** - Works with GitHub personal access tokens
- ✅ **Individual Scheduling** - Different schedules per repository
- ✅ **Centralized Logging** - Separate logs for each repository

## Project Structure

After setup, your project will have this structure:
```
/opt/github-monitor/
├── github-release-monitor.sh       # Main monitoring script
├── configs/                        # Repository-specific configurations
│   ├── frontend-app.conf           # Example: Frontend application
│   ├── backend-api.conf            # Example: Backend API
│   └── payment-service.conf        # Example: Microservice
└── scripts/                        # Management scripts
    └── setup-multi-repo.sh         # Setup and management utility

/etc/systemd/system/
├── github-release-monitor@.service # Systemd service template
└── github-release-monitor@.timer   # Systemd timer template

/opt/releases/                      # Download directories
├── frontend/                       # Frontend releases
├── backend/                        # Backend releases
└── payment-service/                # Service releases
```

## Prerequisites

- Linux server with bash, curl, and jq installed
- Access to GitHub private repositories
- GitHub personal access token with repository access
- sudo/root access for system setup

## Quick Setup

### 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install curl jq git

# CentOS/RHEL/Rocky
sudo yum install curl jq git
# or for newer versions:
sudo dnf install curl jq git
```

### 2. Download and Initial Setup

```bash
# Clone or download the project
git clone <repository-url> /opt/github-monitor-source
cd /opt/github-monitor-source

# Run the automated setup
./scripts/setup-multi-repo.sh setup
```

### 3. Create GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name (e.g., "Release Monitor - MyServer")
4. Select expiration period (recommend 1 year or no expiration for automation)
5. Select scopes:
   - `repo` (Full control of private repositories)
   - Or just `repo:read` if you only need read access
6. Generate and copy the token (starts with `ghp_`)

## Repository Management

### Add a New Repository

```bash
# Add a new repository to monitor
./scripts/setup-multi-repo.sh add frontend-app

# This creates: /opt/github-monitor/configs/frontend-app.conf
# Edit the configuration file
sudo nano /opt/github-monitor/configs/frontend-app.conf
```

Update the configuration with your repository details:
```bash
GITHUB_OWNER="mycompany"
GITHUB_REPO="frontend-app"
GITHUB_TOKEN="ghp_your_token_here"
MINOR_VERSION_PREFIX="v2.1"  # Monitor v2.1.x releases
DOWNLOAD_DIR="/opt/releases/frontend"
STATE_FILE="/opt/releases/frontend/.last-version"
ASSET_PATTERN=".*build.*\.zip$"  # Only download build ZIP files
LOG_FILE="/var/log/github-monitor-frontend.log"
```

### List All Repositories

```bash
./scripts/setup-multi-repo.sh list
```

### Check Status

```bash
./scripts/setup-multi-repo.sh status
```

### Remove a Repository

```bash
./scripts/setup-multi-repo.sh remove frontend-app
```

### Test a Repository Configuration

```bash
# Test with verbose output
sudo -u github-monitor /opt/github-monitor/github-release-monitor.sh \
  --config /opt/github-monitor/configs/frontend-app.conf --verbose
```

## Systemd Management (Recommended)

The system uses systemd service templates for easy management of multiple repositories.

### Service Management

```bash
# Enable and start a repository timer
sudo systemctl enable github-release-monitor@frontend-app.timer
sudo systemctl start github-release-monitor@frontend-app.timer

# Check timer status
sudo systemctl status github-release-monitor@frontend-app.timer

# View logs for a specific repository
sudo journalctl -u github-release-monitor@frontend-app.service -f

# Stop monitoring a repository
sudo systemctl stop github-release-monitor@frontend-app.timer

# List all active timers
sudo systemctl list-timers github-release-monitor@*
```

### All Repository Operations

```bash
# Start all repository monitors
sudo systemctl start github-release-monitor@*.timer

# Stop all repository monitors
sudo systemctl stop github-release-monitor@*.timer

# Check status of all monitors
./scripts/setup-multi-repo.sh status
```

## Alternative: Cron Setup

If you prefer cron over systemd, you can set up individual cron jobs:

```bash
# Edit user crontab
crontab -e

# Add entries for each repository (staggered timing to avoid conflicts)
*/30 * * * * /opt/github-monitor/github-release-monitor.sh --config /opt/github-monitor/configs/frontend-app.conf
*/35 * * * * /opt/github-monitor/github-release-monitor.sh --config /opt/github-monitor/configs/backend-api.conf
*/40 * * * * /opt/github-monitor/github-release-monitor.sh --config /opt/github-monitor/configs/payment-service.conf
```

## Configuration Examples

The `examples/` directory contains sample configuration files for different types of applications:

### Frontend Application
See [examples/frontend-app.conf](examples/frontend-app.conf) for a React/Vue/Angular app configuration:
- Monitors build artifacts (ZIP files)
- Version prefix: `v2.1`
- Downloads to `/opt/releases/frontend`

### Backend API
See [examples/backend-api.conf](examples/backend-api.conf) for a REST API configuration:
- Monitors Linux binaries (tar.gz files)
- Version prefix: `v1.5`
- Downloads to `/opt/releases/backend`

### Microservice
See [examples/microservice.conf](examples/microservice.conf) for a Java microservice:
- Monitors JAR files
- Version prefix: `v3.0`
- Downloads to `/opt/releases/payment-service`

### Custom Configuration

Create a new repository configuration:

```bash
# Create and edit new configuration
./scripts/setup-multi-repo.sh add my-new-app
sudo nano /opt/github-monitor/configs/my-new-app.conf

# Test the configuration
sudo -u github-monitor /opt/github-monitor/github-release-monitor.sh \
  --config /opt/github-monitor/configs/my-new-app.conf --verbose
```

## Configuration Details

## Security Considerations

### File Permissions
```bash
# Protect GitHub tokens in config files
sudo chmod 600 /opt/github-monitor/configs/*.conf
sudo chown github-monitor:github-monitor /opt/github-monitor/configs/*.conf

# Ensure proper ownership
sudo chown -R github-monitor:github-monitor /opt/github-monitor
sudo chown github-monitor:github-monitor /opt/releases
```

### User Isolation
The system runs as a dedicated `github-monitor` user with restricted permissions:
- No shell access (`/bin/false`)
- Limited file system access via systemd security features
- Read-only access to most system directories

### Token Management
- Use tokens with minimal required permissions (`repo:read` if possible)
- Set reasonable expiration dates
- Store tokens only in protected configuration files
- Never log or expose tokens in scripts

### Log Rotation
Create logrotate configuration:

```bash
sudo nano /etc/logrotate.d/github-release-monitor
```

Content:
```
/var/log/github-monitor-*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 github-monitor github-monitor
}
```

## Quick Reference

### Management Commands
```bash
# Setup (run once)
./scripts/setup-multi-repo.sh setup

# Add repository
./scripts/setup-multi-repo.sh add <repo-name>

# Remove repository  
./scripts/setup-multi-repo.sh remove <repo-name>

# List all repositories
./scripts/setup-multi-repo.sh list

# Check status
./scripts/setup-multi-repo.sh status

# Test configuration
sudo -u github-monitor /opt/github-monitor/github-release-monitor.sh \
  --config /opt/github-monitor/configs/<repo-name>.conf --verbose
```

### Systemd Commands
```bash
# Start/stop specific repository
sudo systemctl start github-release-monitor@<repo-name>.timer
sudo systemctl stop github-release-monitor@<repo-name>.timer

# View logs
sudo journalctl -u github-release-monitor@<repo-name>.service -f

# List all timers
sudo systemctl list-timers github-release-monitor@*
```

### File Locations
- **Script**: `/opt/github-monitor/github-release-monitor.sh`
- **Configs**: `/opt/github-monitor/configs/*.conf`
- **Downloads**: `/opt/releases/*/`
- **Logs**: `/var/log/github-monitor-*.log`
- **Systemd**: `/etc/systemd/system/github-release-monitor@.*`

For additional help and examples, see the `examples/` directory in this repository.