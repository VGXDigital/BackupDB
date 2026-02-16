# BackupDB Script - Release Notes

A comprehensive database backup script with multi-storage backend support, automatic dependency management, and enhanced security features.

---

## Version 7.0 (February 16, 2026) - Robust Error Handling & Security Hardening

### Major Rewrite: Error Handling Framework
The script's core error handling has been completely rewritten. The previous approach (`set -euo pipefail`) caused silent crashes when commands like `grep` returned non-zero in normal operation. v7.0 uses explicit error handling throughout with no silent failures.

### Breaking Changes
- **Removed `set -euo pipefail`** — all error handling is now explicit with `if ! cmd; then`
- **Lock file** prevents concurrent runs — second instance exits with clear message

### New Features
- **`die()` function** — fatal errors always visible on both stdout and stderr
- **Timestamped logging** — all output uses `[HH:MM:SS LEVEL]` format
- **`DEBUG` log level** — separate from `INFO`, only shown with `--debug`
- **Lock file** (`/tmp/backupdb.lock`) — prevents overlapping cron runs with stale PID detection
- **Signal handling** — `trap cleanup EXIT INT TERM` for clean shutdown
- **Script directory resolution** — `.env` lookup uses `$SCRIPT_DIR/BackupDB.env` (works from any CWD)

### Security Improvements
- **Secure MySQL credentials** — uses `--defaults-extra-file` temp file instead of `-p"password"` in process list
- **S3 upload filtering** — `--exclude "*" --include "*.gz"` prevents uploading non-backup files

### Bug Fixes
| Bug | Fix |
|-----|-----|
| `set -u` + unset `$VGX_DB_HOSTS` crashes | All env vars use `${VAR:-default}` |
| `sha256sum` missing on macOS | Auto-detects `sha256sum` vs `shasum -a 256` |
| `check_for_updates` pipeline crash | Added `\|\| true` to grep pipeline |
| `git status --porcelain \| grep -q '.'` | Captures to variable, tests with `[[ -n ]]` |
| `grep -Ev` returns 1 if all system DBs | Added `\|\| true` |
| `validate_config` kills script via `set -e` | Explicit `if ! validate_config; then die` |
| Passwords visible in `ps` via `xargs bash -c` | Uses `--defaults-extra-file` temp file |
| `export -f` for parallel backups | Replaced with background `&` jobs + `wait` |
| `cd` in upload functions mutates global CWD | Wrapped in subshells `(cd ... && cmd)` |
| `cleanup_local_backups` does `rm -rf $BACKUP_DIR` | Only deletes `.sql.gz` files |
| `--debug` flag parsed too late | Arguments parsed before env loading or config |

### Backblaze B2 / S3-Compatible Fixes
| Issue | Fix |
|-------|-----|
| `aws s3 ls` validation unreliable on B2 | Uses `aws s3 ls "s3://$BUCKET/"` (list specific bucket) |
| `--endpoint-url=` format causes errors | Uses space-separated `--endpoint-url "$S3_ENDPOINT"` |
| `--region` not passed to AWS CLI | Included in `aws_cmd` when `S3_REGION` is set |
| Upload failure crashes script | Captures output, shows error, returns 1 |
| Upload of non-backup files to S3 | Added `--exclude "*" --include "*.gz"` filter |

### Script Structure (New Order)
```
1. Shell header + copyright (NO set -euo pipefail)
2. Colors, mode defaults, VERSION="7.0"
3. die() + log() — minimal functions for arg parsing
4. show_help() + show_version()
5. Parse arguments (--debug, --test, --dry-run, --help, --version)
6. load_env_file() + load env (script dir → CWD → $HOME)
7. Configuration variables (all with :- defaults)
8. Date + cross-platform checksum detection
9. Lock file + trap cleanup + create_mysql_defaults()
10. Utility functions (check_for_updates, check_command, show_config, etc.)
11. Validation functions
12. Storage/upload functions (git, s3, onedrive)
13. Backup functions (backup_database, run_backups)
14. Main execution
```

---

## Version 6.9 (September 17, 2025) - Parallel Backups & Performance Optimizations

### 🚀 Major Features
- **Parallel Database Backups**: Back up multiple databases on the same host concurrently, significantly speeding up the process.
- **Configurable Parallelism**: New `VGX_DB_MAX_PARALLEL_JOBS` environment variable to control the number of parallel jobs (defaults to the number of CPU cores).
- **Efficient Incremental Backups**: Uses SHA256 checksums instead of `diff` to detect database changes, resulting in faster and more memory-efficient incremental backups.

### ⚙️ New Environment Variables
```bash
VGX_DB_MAX_PARALLEL_JOBS=4  # Set the number of parallel backup jobs
```

### 🔧 Technical Improvements
- **Robust Error Handling**: Implemented stricter error handling with `set -e` and `set -o pipefail`.
- **Parallel Job Error Reporting**: Ensures that failures in any parallel backup job are correctly reported, and the script exits with a non-zero status code.
- **Simplified `.env` Loading**: The function for loading `.env` files has been simplified and made more efficient.

### 💡 Benefits
- **Faster Backups**: Parallel execution dramatically reduces the time it takes to back up multiple databases.
- **Improved Performance**: Checksum-based incremental backups are faster and use less memory, especially for large databases.
- **Greater Reliability**: Stricter error handling makes the script more robust and reliable.

---

## Version 6.7 (August 6, 2025) - Enhanced Cleanup Features

### 🚀 New Features
- **Default Cleanup Enabled**: Local backup cleanup now defaults to enabled for better space management
- **Git Retention Control**: New `VGX_DB_GIT_RETENTION_DAYS` variable for configurable Git backup retention
- **Smart Git Cleanup**: Replaces hardcoded 5-day cleanup with flexible retention policy
- **Never Delete Option**: Set retention to `-1` to disable Git backup deletion entirely

### ⚙️ New Environment Variables
```bash
VGX_DB_DELETE_LOCAL_BACKUPS="true"     # Local cleanup (now defaults to true)
VGX_DB_GIT_RETENTION_DAYS="30"         # Keep 30 days of backups
VGX_DB_GIT_RETENTION_DAYS="0"          # Delete all old backups
VGX_DB_GIT_RETENTION_DAYS="-1"         # Never delete (default)
```

### 🔧 Technical Improvements
- **Detailed Logging**: Shows count of files cleaned up and retention policy status
- **Safe Defaults**: Git retention disabled by default (`-1`) to prevent accidental data loss
- **Flexible Control**: Users can set any retention period from 0 days to unlimited
- **Error Resilient**: Cleanup operations continue even if individual deletions fail

### ⚠️ Breaking Changes
- **Local backup cleanup now enabled by default** - set to `"false"` to disable
- Git backup retention is now user-configurable instead of hardcoded 5 days

---

## Version 6.6 (August 6, 2025) - Configurable Local Backup Cleanup

### 🚀 Major Feature: Local Backup Cleanup
- **Space-Saving Option**: New `VGX_DB_DELETE_LOCAL_BACKUPS` environment variable
- **Smart Cleanup**: Automatically deletes local backup files after successful upload
- **Default Behavior**: Disabled by default to maintain backward compatibility
- **All Storage Types**: Works with Git, S3, and OneDrive storage backends

### 🔧 Technical Implementation
- **Cleanup Function**: New `cleanup_local_backups()` function with detailed logging
- **Upload Integration**: Cleanup runs after each successful upload operation
- **File Detection**: Uses `find` command to locate and count `.gz` backup files
- **Safe Operation**: Only runs when explicitly enabled

### 💡 Benefits
- **Disk Space Management**: Prevents local storage from filling up with backup files
- **Flexible Control**: Users choose when to enable cleanup based on their needs
- **Detailed Logging**: Shows exactly how many files were cleaned up
- **Multi-Storage Support**: Works consistently across all storage backends

---

## Version 6.5 (August 6, 2025) - Automatic Environment File Loading

### 🚀 Major Feature: Auto .env Detection
- **Auto .env Loading**: Script automatically loads environment variables from `BackupDB.env` files
- **Priority Order**: Current directory first, then user home directory
- **GitHub-Ready**: Clients can run script directly from GitHub with local configuration
- **Secure Distribution**: Environment variables stay local while script remains shareable

### 🔧 Technical Improvements
- **Smart File Parsing**: Handles both `export VAR=value` and `VAR=value` formats
- **Comment Support**: Ignores comment lines and empty lines in .env files
- **Quote Handling**: Automatically strips surrounding quotes from values
- **Logging Integration**: Shows which .env file was loaded and variables set
- **Error Resilient**: Gracefully handles missing .env files

### 💡 Benefits for Distribution
- **Client-Friendly**: Download from GitHub and add local .env file
- **No Script Modification**: No need to hardcode sensitive data
- **Version Control Safe**: .env files can be gitignored
- **Multiple Environments**: Different .env files for dev, staging, production

---

## Version 6.4 (July 24, 2025) - Major Fixes & Optimizations

### 🐛 Major Fixes
- **Fixed AWS CLI Quoting**: Resolved argument parsing errors in S3 upload commands
- **Optimized S3 Upload**: Single recursive upload command instead of file-by-file transfers
- **Consistent Environment Variables**: All script variables use `VGX_DB_` prefix (except AWS credentials)
- **Improved Error Handling**: Better debugging with visible AWS commands in logs
- **Conditional Connection Testing**: S3/OneDrive tests only run with `--test` flag

### ⚙️ Environment Variable Changes
- **AWS Credentials**: Keep standard `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- **S3 Variables**: Use `VGX_DB_S3_*` prefix for consistency:
  - `VGX_DB_S3_BUCKET` - S3 bucket name
  - `VGX_DB_S3_PREFIX` - Optional folder prefix
  - `VGX_DB_S3_ENDPOINT_URL` - Required for non-AWS S3 services
  - `VGX_DB_S3_REGION` - S3 region

### 🔧 Technical Improvements
- **S3 Upload Method**: Uses `aws s3 cp . target --recursive` for optimal performance
- **Directory Structure**: Preserves `<dbname>/<backup>` structure in S3
- **Command Visibility**: Debug output shows exact AWS commands being executed

---

## Version 5.0.1 (July 22, 2025) - Multi-Storage Backend Support

### 🚀 Major Feature: Multi-Storage Backend Support
- **Storage Options**: Added support for Git, AWS S3, S3-compatible storage, and Microsoft OneDrive
- **Universal S3 Protocol**: Works with AWS S3, Backblaze B2, Wasabi, DigitalOcean Spaces, MinIO
- **Storage Configuration**: New `VGX_DB_STORAGE_TYPE` environment variable (git, s3, onedrive)

### 🏗️ Key Architecture Changes
- **Storage Abstraction**: Refactored upload logic into storage-agnostic functions:
  - `upload_to_git()` - Git repository with LFS support
  - `upload_to_s3()` - AWS S3 with automatic retention management  
  - `upload_to_onedrive()` - OneDrive via rclone with organized folder structure
- **Smart Dependencies**: Only installs dependencies based on selected storage type
- **Cleanup Strategy**: Git keeps local files, object storage removes local files after upload
- **Backward Compatibility**: Git remains the default storage type

### ✨ Enhanced Features
- **Universal S3 Compatibility**: Single codebase works with any S3-compatible service
- **No aws configure Required**: Uses environment variables for all S3-compatible services
- **Smart Validation**: Uses `aws s3 ls` for testing instead of AWS-specific STS calls
- **Dynamic Dependency Management**: Installs aws-cli for S3, rclone for OneDrive
- **Storage Validation**: Pre-flight checks for storage credentials and connectivity
- **Built-in Help System**: Interactive help with `--help`, `--version`, `--test-config`
- **Organized Storage**: S3 and OneDrive use date-based folder structure
- **Automatic Retention**: Object storage backends implement 30-day retention policies

### ✅ Completed Status
- **Backblaze B2 Integration**: Successfully configured and tested
- **User Environment**: vijendra (Fish shell, macOS)
- **Production Ready**: Fully working with optimized recursive uploads

---

## Version 4.2 (July 22, 2025) - Environment Variable Support

### 🚀 Major Feature: Secure Configuration
- **Environment Variable Priority**: Script prioritizes environment variables over hardcoded values
- **New Environment Variables**:
  - `VGX_DB_OPATH` - Backup directory path
  - `VGX_DB_GIT_REPO` - Git repository URL
  - `VGX_DB_HOSTS` - Database hosts (comma-separated)
  - `VGX_DB_PORTS` - Database ports (comma-separated)
  - `VGX_DB_USERS` - Database usernames (comma-separated)
  - `VGX_DB_PASSWORDS` - Database passwords (comma-separated)

### 💡 Benefits
- **Easy Testing**: No need to modify script for different environments
- **Enhanced Security**: Passwords stored in environment variables instead of script
- **Configuration Display**: Shows source of each configuration value at startup
- **Fallback Support**: Uses script defaults if environment variables not set

---

## Version 4.1 (July 22, 2025) - Centralized Logging

### 🚀 New Features
- **Centralized Logging**: Added `logme()` function with color-coded output
  - **ERROR** messages in red
  - **WARNING** messages in yellow
  - **SUCCESS** messages in green
  - **INFO** messages normal
- **Cleaner Code**: Replaced scattered color echo statements with single function calls

### 🔧 Code Quality Improvements
- More maintainable logging system
- Consistent message formatting throughout script
- Easier to modify colors/formatting in future

---

## Version 4.0 (July 22, 2025) - Major Enhancements

### 🚀 Major Enhancements
- **Comprehensive Dependency Management**: Auto-detection and installation of missing dependencies
- **Smart Git LFS Integration**: Pattern-based tracking for large database backups (>100MB)
- **Enhanced OS Support**: macOS (brew), Ubuntu/Debian (apt), RHEL/CentOS (yum/dnf), openSUSE (zypper)
- **Color-coded Logging**: `logme()` function with RED (errors), YELLOW (warnings), GREEN (success)
- **Improved Error Handling**: Better git operation handling and dynamic branch detection

### 🔧 Technical Improvements
- Fixed duplicate Step 5 numbering (renamed to Step 4.5 for LFS)
- Simplified LFS file detection using `find` with size filtering
- Added dynamic git branch detection instead of hardcoded 'main'
- Replaced unsafe `eval` with `bash -c` for command execution
- Fixed syntax errors and documentation inconsistencies

### ✨ New Features
- **Step 0**: System dependency verification with auto-installation
- **Smart LFS Patterns**: Database-specific patterns like `customer_db/*.gz`
- **Permission Detection**: Automatic detection of elevated privileges
- **Cross-platform Compatibility**: Enhanced OS and package manager detection

### 🐛 Bug Fixes
- Fixed missing quote in final echo statement
- Corrected script name references in documentation
- Added proper error handling for git pull operations
- Moved functions to appropriate locations

---

## Version 3.5 (April 20, 2025) - Foundation Release

### 🚀 Core Features
- **Basic MySQL Backup**: Fundamental database backup functionality
- **Git Integration**: Basic backup versioning with Git repositories
- **File Compression**: Simple compression and cleanup operations
- **Manual Dependencies**: Manual dependency management required

---

## About This Script

BackupDB is a comprehensive database backup solution that has evolved from a simple MySQL backup script to a sophisticated multi-storage backend system with automatic dependency management, configurable cleanup options, and support for multiple cloud storage providers.

### Key Features
- **Multi-Storage Support**: Git, S3-compatible storage (AWS, Backblaze B2, etc.), OneDrive
- **Automatic Dependency Management**: Cross-platform package installation
- **Environment Variable Support**: Secure configuration management
- **Smart Cleanup Options**: Configurable local and remote backup retention
- **Universal S3 Compatibility**: Works with any S3-compatible storage service
- **Enhanced Security**: No hardcoded credentials required

### Supported Platforms
- macOS (Homebrew)
- Ubuntu/Debian (APT)
- RHEL/CentOS/Fedora (YUM/DNF)
- openSUSE (Zypper)

### Storage Backends
- **Git**: Version-controlled backups with LFS support for large files
- **S3-Compatible**: AWS S3, Backblaze B2, Wasabi, DigitalOcean Spaces, MinIO
- **OneDrive**: Microsoft OneDrive integration via rclone

---

*For detailed usage instructions and configuration examples, see the main script documentation.*