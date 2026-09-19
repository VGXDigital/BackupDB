#!/bin/bash
###############################################################################
# Database Backup Script - Simplified & Optimized
# Copyright (c) 2025-2026 VGX Consulting by Vijendra Malhotra. All rights reserved.
# https://vgx.digital
#
# Version: 7.2
# Modified: September 19, 2026
#
# DESCRIPTION:
# Automated MySQL/MariaDB and PostgreSQL database backups with multi-storage backend support.
# Supports Git repositories, AWS S3, S3-compatible storage, and OneDrive.
#
# QUICK START:
# 1. Set storage type: export VGX_DB_STORAGE_TYPE="git|s3|onedrive"
# 2. Configure credentials (see --help for details)
# 3. Set database connection: export VGX_DB_HOSTS="host1,host2"
# 4. Run: ./BackupDB.sh
#
# HELP: ./BackupDB.sh --help
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Mode defaults — set before arg parsing so they exist
TEST_MODE=false
DEBUG_MODE=false
DRY_RUN=false

# Script identity
VERSION="7.2"
SCRIPT_NAME="BackupDB"
GITHUB_REPO="https://raw.githubusercontent.com/VGXDigital/BackupDB/refs/heads/main/BackupDB.sh"

# Lock file path
LOCK_FILE="/tmp/backupdb.lock"

# Temp files to clean up on exit
CRED_FILE=""

###############################################################################
# MINIMAL FUNCTIONS — available before anything else
###############################################################################

# Fatal error — visible on stderr
die() {
    echo -e "${RED}[$(date '+%H:%M:%S') FATAL] $*${NC}" >&2
    exit 1
}

# Unified logging function with timestamps
log() {
    local level=$1; shift
    local ts
    ts=$(date '+%H:%M:%S')

    case $level in
        DEBUG)   [[ "$DEBUG_MODE" == "true" ]] && echo -e "${BLUE}[$ts DEBUG] $*${NC}" ;;
        ERROR)   echo -e "${RED}[$ts ERROR] $*${NC}" >&2 ;;
        WARN)    echo -e "${YELLOW}[$ts WARN] $*${NC}" >&2 ;;
        SUCCESS) echo -e "${GREEN}[$ts SUCCESS] $*${NC}" ;;
        INFO)    [[ "$TEST_MODE" == "true" || "$DEBUG_MODE" == "true" ]] && echo "[$ts INFO] $*" ;;
        *)       echo "[$ts $level] $*" ;;
    esac
    return 0
}

###############################################################################
# HELP & VERSION — available before config loading
###############################################################################

show_help() {
    cat << 'EOF'
DATABASE BACKUP SCRIPT v7.2 - SIMPLIFIED & OPTIMIZED

USAGE:
  ./BackupDB.sh [OPTIONS]

OPTIONS:
  -h, --help         Show this help
  -v, --version      Show version
  -t, --test         Test configuration only
  -d, --debug        Debug mode (verbose logging)
  --dry-run          Show what would be done

STORAGE TYPES:
  git       Git repository (default)
  s3        AWS S3 or S3-compatible (Backblaze B2, Wasabi, etc.)
  onedrive  Microsoft OneDrive

CONFIGURATION METHODS:

  1. Environment Variables (export commands)
  2. BackupDB.env file in script directory
  3. BackupDB.env file in current directory
  4. BackupDB.env file in home directory ($HOME/BackupDB.env)

QUICK SETUP:

  Option 1: Environment Variables
  Git Storage:
    export VGX_DB_GIT_REPO="git@github.com:user/repo.git"

  S3/S3-Compatible:
    export VGX_DB_STORAGE_TYPE="s3"
    export AWS_ACCESS_KEY_ID="your-key"
    export AWS_SECRET_ACCESS_KEY="your-secret"
    export VGX_DB_S3_BUCKET="your-bucket"
    export VGX_DB_S3_PREFIX="backups/"  # Optional folder prefix
    # For non-AWS (Backblaze B2, Wasabi, etc.):
    export VGX_DB_S3_ENDPOINT_URL="https://s3.region.service.com"

  OneDrive:
    # 1. Install rclone: brew install rclone
    # 2. Configure: rclone config → New remote → Microsoft OneDrive
    # 3. Test: rclone ls onedrive:
    export VGX_DB_STORAGE_TYPE="onedrive"
    export ONEDRIVE_REMOTE="onedrive"  # Name from rclone config
    export ONEDRIVE_PATH="/DatabaseBackups"  # Optional folder path

  Database:
    export VGX_DB_HOSTS="db1.com,db2.com"
    export VGX_DB_TYPES="mysql,postgres"        # Optional: mysql (default), mariadb, postgres
    export VGX_DB_PORTS="3306,3307"             # Optional: defaults to 3306 (mysql) / 5432 (postgres)
    export VGX_DB_USERS="user1,user2"
    export VGX_DB_PASSWORDS="pass1,pass2"
    # A single VGX_DB_TYPES value applies to every host.
    # Postgres needs psql + pg_dump; databases are listed via the "postgres" db.

  Performance:
    export VGX_DB_MAX_PARALLEL_JOBS=4             # Number of parallel DB backups (default: number of CPU cores)

  Cleanup Settings:
    export VGX_DB_DELETE_LOCAL_BACKUPS="false"      # Delete local backups after upload (default: true)
    export VGX_DB_GIT_RETENTION_DAYS="7"            # Git backup retention in days (default: -1 = never delete)

EXAMPLES:
  ./BackupDB.sh --test                    # Test configuration
  ./BackupDB.sh --debug                   # Run backup with debug logging
  ./BackupDB.sh                           # Run backup (quiet mode)
  VGX_DB_STORAGE_TYPE=s3 ./BackupDB.sh    # Use S3 storage

BACKBLAZE B2 EXAMPLE:
  export VGX_DB_STORAGE_TYPE="s3"
  export VGX_DB_S3_BUCKET="your-bucket"
  export AWS_ACCESS_KEY_ID="your-keyID"
  export AWS_SECRET_ACCESS_KEY="your-applicationKey"
  export VGX_DB_S3_ENDPOINT_URL="https://s3.us-west-004.backblazeb2.com"
  ./BackupDB.sh

  Option 2: .env File Method
  Create BackupDB.env in script directory, current directory, or $HOME:

    # BackupDB Configuration
    VGX_DB_STORAGE_TYPE=s3
    VGX_DB_S3_BUCKET=my-backup-bucket
    AWS_ACCESS_KEY_ID=your-access-key
    AWS_SECRET_ACCESS_KEY=your-secret-key
    VGX_DB_S3_ENDPOINT_URL=https://s3.amazonaws.com
    VGX_DB_HOSTS=db1.example.com,db2.example.com
    VGX_DB_PORTS=3306,3307
    VGX_DB_USERS=backup_user1,backup_user2
    VGX_DB_PASSWORDS=secret1,secret2
    VGX_DB_DELETE_LOCAL_BACKUPS=false
    VGX_DB_GIT_RETENTION_DAYS=30
    VGX_DB_MAX_PARALLEL_JOBS=4

  Then simply run: ./BackupDB.sh
EOF
}

show_version() {
    echo "$SCRIPT_NAME v$VERSION"
    echo "Multi-storage database backup tool"
}

###############################################################################
# PARSE ARGUMENTS FIRST — so --debug works from line 1
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_help; exit 0 ;;
        -v|--version) show_version; exit 0 ;;
        -t|--test)    TEST_MODE=true; shift ;;
        -d|--debug)   DEBUG_MODE=true; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        *)            echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2; show_help; exit 1 ;;
    esac
done

log DEBUG "Arguments parsed: TEST_MODE=$TEST_MODE DEBUG_MODE=$DEBUG_MODE DRY_RUN=$DRY_RUN"

###############################################################################
# ENVIRONMENT LOADING — after arg parsing so debug output works
###############################################################################

# Resolve the directory where this script lives (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log DEBUG "Script directory resolved: $SCRIPT_DIR"

# Load environment variables from .env file
load_env_file() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        log DEBUG "Loading environment from: $env_file"
        set -a
        # shellcheck source=/dev/null
        source "$env_file"
        set +a
        return 0
    fi
    return 1
}

# Try script dir first, then CWD, then $HOME
if load_env_file "$SCRIPT_DIR/BackupDB.env"; then
    log DEBUG "Loaded env from script directory"
elif load_env_file "./BackupDB.env"; then
    log DEBUG "Loaded env from current directory"
elif load_env_file "$HOME/BackupDB.env"; then
    log DEBUG "Loaded env from home directory"
else
    log DEBUG "No BackupDB.env file found (using environment variables or defaults)"
fi

###############################################################################
# CONFIGURATION — all variables use ${VAR:-default} to avoid unset errors
###############################################################################

# Storage backend (git is default for backward compatibility)
STORAGE_TYPE="${VGX_DB_STORAGE_TYPE:-git}"

# Local backup directory
BACKUP_DIR="${VGX_DB_OPATH:-$HOME/DBBackup/}"

# Cleanup settings
DELETE_LOCAL_BACKUPS="${VGX_DB_DELETE_LOCAL_BACKUPS:-true}"

# Git backup retention period in days (-1 = never delete, 0 = delete all, >0 = days to keep)
GIT_RETENTION_DAYS="${VGX_DB_GIT_RETENTION_DAYS:--1}"

# Incremental backups (skip if no changes detected)
INCREMENTAL_BACKUPS="${VGX_DB_INCREMENTAL_BACKUPS:-true}"

# Number of parallel backup jobs
MAX_PARALLEL_JOBS="${VGX_DB_MAX_PARALLEL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

# Git configuration
GIT_REPO="${VGX_DB_GIT_REPO:-git@github.com:YourUsername/DBBackups.git}"

# S3 configuration (works for AWS S3 and all S3-compatible services)
S3_BUCKET="${VGX_DB_S3_BUCKET:-}"
S3_PREFIX="${VGX_DB_S3_PREFIX:-DatabaseBackups/}"
S3_ENDPOINT="${VGX_DB_S3_ENDPOINT_URL:-}"
S3_REGION="${VGX_DB_S3_REGION:-}"

# OneDrive configuration
ONEDRIVE_REMOTE="${ONEDRIVE_REMOTE:-}"
ONEDRIVE_PATH="${ONEDRIVE_PATH:-/DatabaseBackups}"

# Parse comma-separated env var into array, with a default value
# Usage: parse_csv_var ARRAY_NAME "env_value" "default"
parse_csv_var() {
    local -n arr=$1
    local value="$2"
    local default="$3"
    if [[ -n "$value" ]]; then
        IFS=',' read -ra arr <<< "$value"
    else
        arr=("$default")
    fi
}

# Database configuration
parse_csv_var DB_HOSTS     "${VGX_DB_HOSTS:-}"     "localhost"
parse_csv_var DB_USERS     "${VGX_DB_USERS:-}"     "root"
parse_csv_var DB_PASSWORDS "${VGX_DB_PASSWORDS:-}" "password"
parse_csv_var DB_PORTS     "${VGX_DB_PORTS:-}"     ""   # empty = engine default (3306/5432)
parse_csv_var DB_TYPES     "${VGX_DB_TYPES:-}"     "mysql"

###############################################################################
# DATE & CROSS-PLATFORM CHECKSUM
###############################################################################

TODAY=$(date +%Y%m%d)

# Detect checksum command: sha256sum (Linux) vs shasum -a 256 (macOS)
CHECKSUM_CMD=""
if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_CMD="shasum -a 256"
else
    log WARN "No SHA-256 checksum tool found — incremental backups will be disabled"
    INCREMENTAL_BACKUPS="false"
fi
log DEBUG "Checksum command: ${CHECKSUM_CMD:-none}"

###############################################################################
# LOCK FILE + TRAP CLEANUP
###############################################################################

# Cleanup function — runs on EXIT, INT, TERM
cleanup() {
    local exit_code=$?
    log DEBUG "Cleanup running (exit code: $exit_code)"

    # Remove credentials temp file (contains password)
    if [[ -n "$CRED_FILE" && -f "$CRED_FILE" ]]; then
        rm -f "$CRED_FILE"
        log DEBUG "Removed credentials file"
    fi

    # Release lock file
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$LOCK_FILE"
            log DEBUG "Released lock file"
        fi
    fi

    exit "$exit_code"
}

trap cleanup EXIT INT TERM

# Acquire lock file — prevent concurrent runs
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local existing_pid
        existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
        # Check if the process is still running
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            die "Another instance is already running (PID: $existing_pid). Remove $LOCK_FILE if this is incorrect."
        else
            log WARN "Stale lock file found (PID: $existing_pid no longer running). Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log DEBUG "Lock file acquired (PID: $$)"
}

###############################################################################
# CREDENTIALS FILE — keeps passwords out of the process list
###############################################################################

# Create a temporary credentials file: mysql defaults file or postgres .pgpass
# Usage: create_cred_file <type> <password>
# Sets CRED_FILE to the path
create_cred_file() {
    local type="$1"
    local password="$2"
    # Remove old file if any
    if [[ -n "$CRED_FILE" && -f "$CRED_FILE" ]]; then
        rm -f "$CRED_FILE"
    fi
    CRED_FILE=$(mktemp /tmp/backupdb_cred.XXXXXX)
    chmod 600 "$CRED_FILE"
    if [[ "$type" == "postgres" ]]; then
        # .pgpass format: host:port:db:user:password — escape \ and : in the password
        password="${password//\\/\\\\}"
        printf '*:*:*:*:%s\n' "${password//:/\\:}" > "$CRED_FILE"
    else
        printf '[client]\npassword=%s\n' "$password" > "$CRED_FILE"
    fi
    log DEBUG "Created $type credentials file: $CRED_FILE"
}

###############################################################################
# DATABASE ENGINE HELPERS — mysql/mariadb and postgres
###############################################################################

# Normalise a VGX_DB_TYPES entry to "mysql" or "postgres"
# Usage: type=$(db_type <index>) — missing entries fall back to the first type
db_type() {
    local type="${DB_TYPES[$1]:-${DB_TYPES[0]}}"
    case "$(echo "$type" | tr '[:upper:]' '[:lower:]')" in
        mysql|mariadb)          echo "mysql" ;;
        postgres|postgresql|pg) echo "postgres" ;;
        *) log ERROR "Unsupported database type: '$type' (expected: mysql, mariadb, postgres)"; return 1 ;;
    esac
}

# Default port for a database type
default_port() {
    [[ "$1" == "postgres" ]] && echo 5432 || echo 3306
}

# Run a query and print rows without headers
# Usage: db_query <type> <host> <port> <user> <sql>  (uses $CRED_FILE)
db_query() {
    local type="$1" host="$2" port="$3" user="$4" sql="$5"
    if [[ "$type" == "postgres" ]]; then
        PGPASSFILE="$CRED_FILE" psql -w -X -A -t -h "$host" -p "$port" -U "$user" -d postgres -c "$sql"
    else
        mysql --defaults-extra-file="$CRED_FILE" -N -B -h "$host" -P "$port" -u "$user" -e "$sql"
    fi
}

# List user databases on a server (system databases excluded)
# The grep may return 1 if all databases are system databases — that's OK
db_list() {
    if [[ "$1" == "postgres" ]]; then
        db_query "$@" "SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn AND datname <> 'postgres' ORDER BY 1;"
    else
        db_query "$@" "SHOW DATABASES;" | grep -Ev "mysql|information_schema|performance_schema|sys" || true
    fi
}

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

# Check for script updates (non-blocking, never crashes)
check_for_updates() {
    if ! command -v curl >/dev/null 2>&1; then
        log DEBUG "curl not found, skipping update check"
        return 0
    fi

    local remote_version
    remote_version=$(curl -s --max-time 5 "$GITHUB_REPO" 2>/dev/null | grep "^VERSION=" | head -1 | cut -d'"' -f2 || true)

    if [[ -n "$remote_version" && "$remote_version" != "$VERSION" ]]; then
        echo
        log WARN "New version available: $remote_version (current: $VERSION)"
        log INFO "Update available at: https://github.com/VGXDigital/BackupDB"
        echo
    fi
}

# Check if a required command exists
check_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log ERROR "Required command '$cmd' not found. Please install it."
        return 1
    fi
    return 0
}

# Show current configuration
show_config() {
    log INFO "Configuration Summary:"
    echo "  Storage Type: $STORAGE_TYPE"
    echo "  Backup Directory: $BACKUP_DIR"
    echo "  Parallel Jobs: $MAX_PARALLEL_JOBS"
    echo "  Incremental Backups: $INCREMENTAL_BACKUPS"
    echo "  Delete Local Backups: $DELETE_LOCAL_BACKUPS"

    case $STORAGE_TYPE in
        "git")
            echo "  Git Repository: $GIT_REPO"
            echo "  Git Retention Days: $GIT_RETENTION_DAYS"
            ;;
        "s3")
            echo "  S3 Bucket: $S3_BUCKET"
            echo "  S3 Prefix: $S3_PREFIX"
            echo "  S3 Endpoint: ${S3_ENDPOINT:-AWS Default}"
            [[ -n "$S3_REGION" ]] && echo "  S3 Region: $S3_REGION"
            ;;
        "onedrive")
            echo "  OneDrive Remote: $ONEDRIVE_REMOTE"
            echo "  OneDrive Path: $ONEDRIVE_PATH"
            ;;
    esac

    echo "  Database Types: ${DB_TYPES[*]}"
    echo "  Database Hosts: ${DB_HOSTS[*]}"
    echo "  Database Users: ${DB_USERS[*]}"
    echo "  Checksum Tool: ${CHECKSUM_CMD:-none (incremental disabled)}"
}

# Cleanup local backups after successful upload — only deletes .sql.gz files
cleanup_local_backups() {
    if [[ "$DELETE_LOCAL_BACKUPS" != "true" || ! -d "$BACKUP_DIR" ]]; then
        log DEBUG "Local backup cleanup skipped"
        return 0
    fi
    find "$BACKUP_DIR" -name "*.sql.gz" -type f -delete 2>/dev/null || true
    log WARN "Deleted local backup files from: $BACKUP_DIR"
}

###############################################################################
# AWS / S3 HELPER
###############################################################################

# Execute AWS CLI command with optional endpoint and region
aws_cmd() {
    local aws_args=("$@")

    if [[ -n "$S3_ENDPOINT" ]]; then
        aws_args+=(--endpoint-url "$S3_ENDPOINT")
    fi
    if [[ -n "$S3_REGION" ]]; then
        aws_args+=(--region "$S3_REGION")
    fi

    log DEBUG "AWS command: aws ${aws_args[*]}"
    aws "${aws_args[@]}"
}

###############################################################################
# VALIDATION FUNCTIONS
###############################################################################

# Validate storage configuration
validate_storage() {
    local test_connection=${1:-false}

    case $STORAGE_TYPE in
        "git")
            if ! check_command git; then return 1; fi
            if [[ -z "$GIT_REPO" || "$GIT_REPO" == *"YourUsername"* ]]; then
                log ERROR "Git repository not configured. Set VGX_DB_GIT_REPO environment variable."
                return 1
            fi
            if [[ "$test_connection" == "true" ]]; then
                log INFO "Testing Git connection..."
                if ! git ls-remote "$GIT_REPO" >/dev/null 2>&1; then
                    log ERROR "Git connection failed. Check repository URL and SSH keys."
                    return 1
                fi
                log SUCCESS "Git connection successful"
            fi
            ;;
        "s3")
            if ! check_command aws; then return 1; fi
            if [[ -z "$S3_BUCKET" ]]; then
                log ERROR "S3 bucket not configured. Set VGX_DB_S3_BUCKET environment variable."
                return 1
            fi
            if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
                log ERROR "S3 credentials not configured. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
                return 1
            fi
            if [[ "$test_connection" == "true" ]]; then
                log INFO "Testing S3 connection..."
                local s3_output
                if ! s3_output=$(aws_cmd s3 ls "s3://$S3_BUCKET/" 2>&1); then
                    log ERROR "S3 connection failed: $s3_output"
                    return 1
                fi
                log SUCCESS "S3 connection successful"
            fi
            ;;
        "onedrive")
            if ! check_command rclone; then return 1; fi
            if [[ -z "$ONEDRIVE_REMOTE" ]]; then
                log ERROR "OneDrive remote not configured. Set ONEDRIVE_REMOTE environment variable."
                return 1
            fi
            if [[ "$test_connection" == "true" ]]; then
                log INFO "Testing OneDrive connection..."
                local remotes
                remotes=$(rclone listremotes 2>/dev/null || true)
                if ! echo "$remotes" | grep -q "^${ONEDRIVE_REMOTE}:$"; then
                    log ERROR "OneDrive remote '$ONEDRIVE_REMOTE' not found. Run: rclone config"
                    return 1
                fi
                log SUCCESS "OneDrive connection successful"
            fi
            ;;
        *)
            log ERROR "Unsupported storage type: $STORAGE_TYPE (expected: git, s3, onedrive)"
            return 1
            ;;
    esac
    return 0
}

# Validate database configuration
validate_database() {
    local test_connection=${1:-false}

    # Check client tools for each engine in use
    local i type
    for i in "${!DB_HOSTS[@]}"; do
        type=$(db_type "$i") || return 1
        if [[ "$type" == "postgres" ]]; then
            check_command psql && check_command pg_dump || return 1
        else
            check_command mysql && check_command mysqldump || return 1
        fi
    done

    # Checksum tool is optional — already handled at startup
    if [[ "$INCREMENTAL_BACKUPS" == "true" && -z "$CHECKSUM_CMD" ]]; then
        log WARN "Incremental backups requested but no checksum tool available — disabling"
        INCREMENTAL_BACKUPS="false"
    fi

    if [[ ${#DB_HOSTS[@]} -ne ${#DB_USERS[@]} || ${#DB_HOSTS[@]} -ne ${#DB_PASSWORDS[@]} ]]; then
        log ERROR "Database configuration mismatch. Hosts, users, and passwords arrays must have same length."
        log ERROR "  Hosts: ${#DB_HOSTS[@]}, Users: ${#DB_USERS[@]}, Passwords: ${#DB_PASSWORDS[@]}"
        return 1
    fi

    if [[ "$test_connection" == "true" ]]; then
        log INFO "Testing database connections..."
        for i in "${!DB_HOSTS[@]}"; do
            local host="${DB_HOSTS[$i]}"
            local user="${DB_USERS[$i]}"
            local password="${DB_PASSWORDS[$i]}"
            local type; type=$(db_type "$i")
            local port="${DB_PORTS[$i]:-$(default_port "$type")}"

            log INFO "Testing $type connection to database: $host:$port (user: $user)"
            create_cred_file "$type" "$password"

            local test_output
            if ! test_output=$(db_query "$type" "$host" "$port" "$user" "SELECT 1;" 2>&1); then
                log ERROR "Connection failed to $host:$port with user '$user': $test_output"
                return 1
            fi
        done
        log SUCCESS "All database connections successful!"
    fi
    return 0
}

# Run all validations
validate_config() {
    local test_connection=${1:-false}
    log INFO "Validating configuration..."
    validate_storage "$test_connection" && validate_database "$test_connection" || return 1
    log SUCCESS "Configuration validation passed!"
}

###############################################################################
# STORAGE / UPLOAD FUNCTIONS
###############################################################################

# Upload to Git repository — runs in a subshell to protect CWD
upload_git() {
    local backup_path="$1"

    log INFO "Uploading to Git repository..."

    (
        cd "$backup_path" || { log ERROR "Cannot cd to backup path: $backup_path"; return 1; }

        # Check for changes — capture to variable instead of piping to grep
        local status_output
        status_output=$(git status --porcelain 2>/dev/null || true)

        if [[ -n "$status_output" ]]; then
            log INFO "Changes detected. Committing..."
            git add .
            if ! git commit -m "Database backup: $TODAY"; then
                log ERROR "Git commit failed"
                return 1
            fi
            if ! git push origin "$(git rev-parse --abbrev-ref HEAD)"; then
                log ERROR "Git push failed"
                return 1
            fi
            log SUCCESS "Git upload completed."
        else
            log INFO "No changes to commit."
        fi
    )
    local git_result=$?

    cleanup_local_backups
    return $git_result
}

# Upload to S3 (works with all S3-compatible services) — runs in a subshell
upload_s3() {
    local backup_path="$1"

    log INFO "Uploading to S3 storage..."

    local s3_target="s3://$S3_BUCKET/${S3_PREFIX}${TODAY}/"
    log DEBUG "S3 target: $s3_target"

    local s3_output
    if ! s3_output=$(aws_cmd s3 cp "$backup_path" "$s3_target" --recursive --exclude "*" --include "*.gz" 2>&1); then
        log ERROR "S3 upload failed: $s3_output"
        return 1
    fi
    log DEBUG "S3 output: $s3_output"
    log SUCCESS "S3 upload completed."

    cleanup_local_backups
    return 0
}

# Upload to OneDrive
upload_onedrive() {
    local backup_path="$1"

    log INFO "Uploading to OneDrive..."

    local target_path="${ONEDRIVE_REMOTE}:${ONEDRIVE_PATH}/${TODAY}"

    if ! rclone copy "$backup_path" "$target_path" --include "*.gz" 2>/dev/null; then
        log ERROR "OneDrive upload failed"
        return 1
    fi

    log SUCCESS "OneDrive upload completed."
    cleanup_local_backups
    return 0
}

# Main upload function
upload_backups() {
    local backup_path="$1"

    case $STORAGE_TYPE in
        "git")      upload_git "$backup_path" ;;
        "s3")       upload_s3 "$backup_path" ;;
        "onedrive") upload_onedrive "$backup_path" ;;
        *)          log ERROR "Unknown storage type: $STORAGE_TYPE"; return 1 ;;
    esac
}

###############################################################################
# BACKUP FUNCTIONS
###############################################################################

# Create database backup for a single database
backup_database() {
    local type="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local cred_file="$5"
    local db="$6"
    local backup_path="$7"

    local backup_file="${backup_path}/${TODAY}_${db}.sql"

    log INFO "Backing up $type database: $db from $host:$port"

    # Create backup using credentials file (password not in process list)
    local dump_ok=true
    if [[ "$type" == "postgres" ]]; then
        PGPASSFILE="$cred_file" pg_dump -w --clean --if-exists \
            -h "$host" -p "$port" -U "$user" -d "$db" > "$backup_file" 2>/dev/null || dump_ok=false
    else
        mysqldump --defaults-extra-file="$cred_file" --add-drop-table --allow-keywords --skip-dump-date -c \
            -h "$host" -P "$port" -u "$user" "$db" > "$backup_file" 2>/dev/null || dump_ok=false
    fi
    if [[ "$dump_ok" != "true" ]]; then
        log ERROR "$type dump failed for database: $db"
        rm -f "$backup_file"
        return 1
    fi

    if [[ ! -s "$backup_file" ]]; then
        log WARN "Backup file is empty, skipping: $db"
        rm -f "$backup_file"
        return 1
    fi

    # Compare with yesterday's backup if incremental backups are enabled
    if [[ "$INCREMENTAL_BACKUPS" == "true" && -n "$CHECKSUM_CMD" ]]; then
        local yesterday
        if [[ "$OSTYPE" == "darwin"* ]]; then
            yesterday=$(date -v -1d +%Y%m%d)
        else
            yesterday=$(date --date="yesterday" +%Y%m%d)
        fi
        local yesterday_file="${backup_path}/${yesterday}_${db}.sql.gz"
        if [[ -f "$yesterday_file" ]]; then
            log DEBUG "Comparing with yesterday's backup for $db..."
            local current_hash yesterday_hash
            # pg_dump >= 17.6/16.10 wraps output in \restrict <random key> lines — ignore them
            current_hash=$(grep -Ev '^\\(un)?restrict ' "$backup_file" | $CHECKSUM_CMD | awk '{print $1}')
            yesterday_hash=$(gunzip -c "$yesterday_file" | grep -Ev '^\\(un)?restrict ' | $CHECKSUM_CMD | awk '{print $1}')

            if [[ "$current_hash" == "$yesterday_hash" ]]; then
                log INFO "No changes detected in $db, skipping."
                rm -f "$backup_file"
                return 2  # Special code for "no changes"
            fi
        fi
    fi

    # Compress backup
    if ! gzip -f -9 "$backup_file"; then
        log ERROR "Failed to compress backup for: $db"
        return 1
    fi
    log SUCCESS "Database backup created: $db"
    return 0
}

# Run backups for all configured databases
run_backups() {
    local backup_path="$1"
    mkdir -p "$backup_path"

    # Clean up old Git backups based on retention policy
    if [[ "$STORAGE_TYPE" == "git" && "$GIT_RETENTION_DAYS" -ge 0 ]]; then
        find "$backup_path" -name "*.sql.gz" -mtime "+$GIT_RETENTION_DAYS" -type f -delete 2>/dev/null || true
        log INFO "Cleaned up old Git backups (older than $GIT_RETENTION_DAYS days)"
    fi

    local overall_failed=false

    # Process each database host
    for (( i = 0; i < ${#DB_HOSTS[@]}; i++ )); do
        local host="${DB_HOSTS[$i]}"
        local user="${DB_USERS[$i]}"
        local password="${DB_PASSWORDS[$i]}"
        local type; type=$(db_type "$i")
        local port="${DB_PORTS[$i]:-$(default_port "$type")}"

        log INFO "Processing $type database host: $host:$port (user: $user)"

        # Create credentials file for this host (keeps password out of process list)
        create_cred_file "$type" "$password"

        # Test connection using credentials file
        if ! db_query "$type" "$host" "$port" "$user" "SELECT 1;" >/dev/null 2>&1; then
            log ERROR "Cannot connect to $type database: $host:$port with user '$user'"
            overall_failed=true
            continue
        fi

        # Get database list (exclude system databases)
        local databases
        databases=$(db_list "$type" "$host" "$port" "$user" 2>/dev/null)

        if [[ -z "$databases" ]]; then
            log WARN "No user databases found on $host:$port"
            continue
        fi

        log DEBUG "Databases to backup: $(echo "$databases" | tr '\n' ' ')"

        # Backup each database using background jobs (replaces xargs -P + export -f)
        local job_count=0
        local pids=()
        local db_names=()

        while IFS= read -r db; do
            [[ -z "$db" ]] && continue

            # Launch backup in background
            backup_database "$type" "$host" "$port" "$user" "$CRED_FILE" "$db" "$backup_path" &
            pids+=($!)
            db_names+=("$db")
            job_count=$((job_count + 1))

            # Throttle: wait for some jobs to finish if we hit the max
            if [[ $job_count -ge $MAX_PARALLEL_JOBS ]]; then
                # Wait for the oldest job
                wait "${pids[0]}" 2>/dev/null
                local result=$?
                if [[ $result -ne 0 && $result -ne 2 ]]; then
                    log ERROR "Failed to backup database: ${db_names[0]} (exit code: $result)"
                    overall_failed=true
                fi
                pids=("${pids[@]:1}")
                db_names=("${db_names[@]:1}")
                job_count=$((job_count - 1))
            fi
        done <<< "$databases"

        # Wait for remaining background jobs
        for idx in "${!pids[@]}"; do
            wait "${pids[$idx]}" 2>/dev/null
            local result=$?
            if [[ $result -ne 0 && $result -ne 2 ]]; then
                log ERROR "Failed to backup database: ${db_names[$idx]} (exit code: $result)"
                overall_failed=true
            fi
        done
    done

    if [[ "$overall_failed" == "true" ]]; then
        log ERROR "One or more database backups failed"
        return 1
    fi

    return 0
}

###############################################################################
# MAIN EXECUTION
###############################################################################

# Acquire lock file to prevent concurrent runs
acquire_lock

# Capture start time for timing
START_TIME=$(date +%s)

# Script header
echo "======================================================================"
echo "DATABASE BACKUP SCRIPT v$VERSION"
echo "Copyright (c) 2025-2026 VGX Consulting"
echo "https://vgx.digital"
echo
echo "Starting at $(date)"
echo "======================================================================"

# Check for updates (non-blocking)
check_for_updates

# Show configuration
show_config
echo

# Validate configuration (without connection test)
if ! validate_config; then
    die "Configuration validation failed. Fix the errors above and retry."
fi

# Test mode — validate with connection tests and exit
if [[ "$TEST_MODE" == "true" ]]; then
    log INFO "Running connection tests..."
    if ! validate_config true; then
        die "Connection tests failed. Fix the errors above and retry."
    fi
    log SUCCESS "Configuration test passed! Ready for backups."
    exit 0
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "DRY RUN MODE - No actual backups will be performed"
    echo "  Would backup databases from: ${DB_HOSTS[*]}"
    echo "  Would upload to: $STORAGE_TYPE"
    echo "  Backup directory: $BACKUP_DIR"
    echo "  Parallel jobs: $MAX_PARALLEL_JOBS"
    echo "  Incremental: $INCREMENTAL_BACKUPS"
    echo "  Delete local after upload: $DELETE_LOCAL_BACKUPS"
    exit 0
fi

# Run the backup process
log INFO "Starting backup process..."

# Setup Git repository if needed
if [[ "$STORAGE_TYPE" == "git" ]]; then
    if [[ -d "$BACKUP_DIR" && ! -d "$BACKUP_DIR/.git" ]]; then
        log INFO "Removing existing backup directory for Git setup..."
        rm -rf "$BACKUP_DIR"
    fi

    if [[ ! -d "$BACKUP_DIR/.git" ]]; then
        log INFO "Cloning Git repository..."
        if ! git clone "$GIT_REPO" "$BACKUP_DIR"; then
            die "Failed to clone Git repository: $GIT_REPO"
        fi
    else
        log INFO "Pulling latest from Git repository..."
        if ! git -C "$BACKUP_DIR" pull; then
            die "Failed to pull from Git repository: $GIT_REPO"
        fi
    fi
fi

# Create backups
if ! run_backups "$BACKUP_DIR"; then
    die "Backup process failed. Check errors above."
fi

# Upload backups
if ! upload_backups "$BACKUP_DIR"; then
    die "Upload process failed. Check errors above."
fi

# Final success message
echo "======================================================================"
echo "SUCCESS: Backup process completed successfully at $(date)"
echo "Total execution time: $(( $(date +%s) - START_TIME )) seconds"
echo "======================================================================"
