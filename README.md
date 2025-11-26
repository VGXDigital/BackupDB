# BackupDB - MySQL Database Backup Script

**Simple, automated MySQL backups to Git, S3, or OneDrive**

[![Version](https://img.shields.io/badge/version-6.9-blue.svg)](RELEASE_NOTES.md)
[![Storage](https://img.shields.io/badge/storage-Git%20%7C%20S3%20%7C%20OneDrive-green.svg)](#storage-backends)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#supported-platforms)



## 🆕 What's New

For complete version history and migration guides, see **[RELEASE_NOTES.md](RELEASE_NOTES.md)**

## 📦 Installation

### Download Script and Sample Configuration
```bash
# Download the script
curl -O https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sh
chmod +x BackupDB.sh

# Download sample configuration
curl -O https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sample.env
cp BackupDB.sample.env BackupDB.env
```

### Test Your Setup
```bash
./BackupDB.sh --test    # Validate configuration
./BackupDB.sh --debug   # Run with detailed logging
./BackupDB.sh           # Run backup
```

## 🔧 Configuration

Edit `BackupDB.env` with your settings. The script automatically loads this file.

### Essential Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `VGX_DB_STORAGE_TYPE` | Yes | Where to store backups | `"git"`, `"s3"`, `"onedrive"` |
| `VGX_DB_HOSTS` | Yes | Database servers | `"localhost"` or `"db1.com,db2.com"` |
| `VGX_DB_USERS` | Yes | Database usernames | `"backup_user"` or `"user1,user2"` |
| `VGX_DB_PASSWORDS` | Yes | Database passwords | `"password"` or `"pass1,pass2"` |

### Git Storage Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `VGX_DB_GIT_REPO` | Git repository URL | `"git@github.com:user/backups.git"` |

### S3 Storage Variables  
| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | S3 access key | `"AKIA..."` |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | `"secret..."` |
| `VGX_DB_S3_BUCKET` | S3 bucket name | `"my-backups"` |
| `VGX_DB_S3_ENDPOINT_URL` | S3 endpoint (non-AWS only) | `"https://s3.backblaze.com"` |

### OneDrive Storage Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `ONEDRIVE_REMOTE` | rclone remote name | `"onedrive"` |
| `ONEDRIVE_PATH` | OneDrive folder path | `"/DatabaseBackups"` |

### Optional Settings
| Variable | Default | Description |
|----------|---------|-------------|
| `VGX_DB_INCREMENTAL_BACKUPS` | `"true"` | Skip unchanged databases |
| `VGX_DB_DELETE_LOCAL_BACKUPS` | `"true"` | Delete local files after upload |
| `VGX_DB_GIT_RETENTION_DAYS` | `"-1"` | Git backup retention (-1=keep all) |
| `VGX_DB_MAX_PARALLEL_JOBS` | CPU cores | Number of parallel DB backups |

## ⏰ Automation (Cron)

### Method 1: Local Installation
```bash
# Download and install
curl -O https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sh
curl -O https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sample.env

# Install script
sudo cp BackupDB.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/BackupDB.sh

# Setup config directory
sudo mkdir -p /etc/backupdb
cp BackupDB.sample.env /etc/backupdb/BackupDB.env
sudo chown root:root /etc/backupdb/BackupDB.env
sudo chmod 600 /etc/backupdb/BackupDB.env

# Edit configuration
sudo nano /etc/backupdb/BackupDB.env

# Add to cron (daily at 2 AM)
echo "0 2 * * * cd /etc/backupdb && /usr/local/bin/BackupDB.sh" | sudo crontab -
```

### Method 2: Direct from GitHub (No Installation)
```bash
# Download config to home directory
curl -o $HOME/BackupDB.env https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sample.env

# Edit configuration
nano $HOME/BackupDB.env

# Add to cron
crontab -e

# Add this line:
0 2 * * * curl -s https://raw.githubusercontent.com/VGXConsulting/BackupDB/main/BackupDB.sh | /bin/bash
```

## 🗂️ Backup File Structure

Backups are organized by date:
```
Storage Location/
├── DatabaseBackups/
│   ├── 2025-01-15/
│   │   ├── 20250115_database1.sql.gz
│   │   └── 20250115_database2.sql.gz
│   └── 2025-01-16/
│       ├── 20250116_database1.sql.gz
│       └── 20250116_database2.sql.gz
```

## 🔍 Troubleshooting

### Test Configuration
```bash
./BackupDB.sh --test
```

### Debug Mode
```bash
./BackupDB.sh --debug
```

### Common Issues

**Git Authentication Failed**
- Ensure SSH key is set up for the Git repository
- Test: `git clone your-repo-url`

**S3 Upload Failed**  
- Verify access keys and bucket permissions
- Check endpoint URL for non-AWS services

**Database Connection Failed**
- Verify database credentials and network access
- Test: `mysql -h host -u user -p`

## 📖 Settings Documentation

- **[Sample Configuration](BackupDB.sample.env)** - Complete configuration template

---

**[Repository Link](https://github.com/VGXConsulting/BackupDB)**
