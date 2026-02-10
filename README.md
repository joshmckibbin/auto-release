# GitHub Release Monitor

A robust shell script system for monitoring multiple GitHub private repositories for new releases and automatically downloading them to specified locations on your server. Designed with **Multiple Configuration Files** support for enterprise-scale deployment management.

## Features

- ✅ **Multiple Repository Support** - Monitor unlimited GitHub repositories simultaneously
- ✅ **Template-Based Configuration** - Easy setup with systemd service templates
- ✅ **Automated Management** - Script-based setup, status monitoring, and maintenance
- ✅ **Private Repository Support** - Works with GitHub personal access tokens
- ✅ **Minor Version Filtering** - Monitor specific minor release branches (e.g., v1.2.x)
- ✅ **Individual Scheduling** - Different schedules and configurations per repository
- ✅ **Asset Filtering** - Download only specific file types or patterns per repository
- ✅ **Version Management** - Keeps track of downloaded versions and cleans up old releases
- ✅ **Comprehensive Logging** - Separate logs for each repository with configurable verbosity
- ✅ **Systemd Integration** - Modern service management with templates and timers
- ✅ **Security Focused** - Dedicated user, file permissions, and systemd security features

## Project Structure

```
github-release-monitor/
├── github-release-monitor.sh        # Main monitoring script
├── github-release-monitor.conf      # Base configuration template
├── configs/                         # Repository configurations
│   ├── template.conf               # Configuration template
│   └── *.conf                      # Per-repository configs (created by user)
├── systemd/                         # Systemd service files
│   ├── github-release-monitor@.service  # Template service
│   ├── github-release-monitor@.timer    # Template timer
│   ├── github-release-monitor.service   # Legacy single service
│   └── github-release-monitor.timer     # Legacy single timer
├── scripts/                         # Management scripts
│   ├── setup-multi-repo.sh         # Multi-repo setup and management
│   └── check-status.sh             # Status monitoring script
├── examples/                        # Example configurations
│   ├── frontend-app.conf           # Frontend application example
│   ├── backend-api.conf            # Backend API example
│   └── microservice.conf           # Microservice example
├── README.md                        # This file
└── SETUP.md                        # Detailed setup guide
```

## Quick Start

1. **Copy files to your server**:
   ```bash
   sudo mkdir -p /opt/github-monitor
   sudo cp github-release-monitor.sh /opt/github-monitor/
   sudo cp github-release-monitor.conf /opt/github-monitor/
   sudo chmod +x /opt/github-monitor/github-release-monitor.sh
   ```

2. **Configure the script** by editing [github-release-monitor.conf](github-release-monitor.conf):
   ```bash
   sudo nano /opt/github-monitor/github-release-monitor.conf
   ```

3. **Test the configuration**:
   ```bash
   /opt/github-monitor/github-release-monitor.sh --config /opt/github-monitor/github-release-monitor.conf --verbose
   ```

4. **Set up automated execution** (choose one):

   **Option A: Cron (Traditional)**
   ```bash
   crontab -e
   # Add: */30 * * * * /opt/github-monitor/github-release-monitor.sh --config /opt/github-monitor/github-release-monitor.conf
   ```

   **Option B: Systemd (Modern)**
   ```bash
   sudo cp github-release-monitor.service /etc/systemd/system/
   sudo cp github-release-monitor.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable github-release-monitor.timer
   sudo systemctl start github-release-monitor.timer
   ```

## Files Included

- **[github-release-monitor.sh](github-release-monitor.sh)** - Main script
- **[github-release-monitor.conf](github-release-monitor.conf)** - Configuration template
- **[SETUP.md](SETUP.md)** - Detailed setup and configuration guide
- **[github-release-monitor.service](github-release-monitor.service)** - Systemd service file
- **[github-release-monitor.timer](github-release-monitor.timer)** - Systemd timer file

## Configuration Example

```bash
# Repository details
GITHUB_OWNER="mycompany"
GITHUB_REPO="my-private-app"
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# Monitor v2.1.x releases
MINOR_VERSION_PREFIX="v2.1"

# Download to /opt/releases/my-app
DOWNLOAD_DIR="/opt/releases/my-app"
STATE_FILE="/opt/releases/my-app/.last-version"

# Only download .tar.gz files
ASSET_PATTERN=".*\.tar\.gz$"

# Enable logging
LOG_FILE="/var/log/github-release-monitor.log"
VERBOSE=false
```

## How It Works

1. **Checks GitHub API** for releases matching your version prefix
2. **Compares versions** using semantic versioning to find the latest
3. **Downloads new releases** if a newer version is found
4. **Stores files** in organized directories by version
5. **Updates state** to track the last downloaded version
6. **Cleans up** old releases to save disk space
7. **Logs everything** for monitoring and troubleshooting

## Directory Structure After Use

```
/opt/releases/my-app/
├── v2.1.0/
│   ├── my-app-linux.tar.gz
│   └── my-app-windows.zip
├── v2.1.1/
│   ├── my-app-linux.tar.gz
│   └── my-app-windows.zip
├── v2.1.2/
│   ├── my-app-linux.tar.gz
│   └── my-app-windows.zip
└── .last-version  # Contains: v2.1.2
```

## Requirements

- Linux server with bash shell
- `curl` and `jq` installed
- GitHub personal access token with repo access
- Write permissions to download directory
- Network access to api.github.com

## Security Features

- Token-based authentication
- Configurable file permissions
- Systemd security hardening options
- No sensitive data in logs
- Secure directory structure

For detailed setup instructions, see [SETUP.md](SETUP.md).

## License

MIT License - Feel free to modify and use in your projects.