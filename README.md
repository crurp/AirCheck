# AirCheck

Flight deal monitoring script that watches SecretFlying.com for deals to specific airports and sends email notifications.

## Features

- Monitors flight deals for **LAX** (Los Angeles) and **BWI** (Baltimore) airports
- Secure email configuration via environment variable
- Duplicate detection to avoid spam
- Error handling and logging
- Automatic cleanup of temporary files

## Security

The script uses an environment variable for the email address to avoid hardcoding sensitive information. The email address is stored as a global environment variable on the system.

## Setup

1. Make the script executable:
   ```bash
   chmod +x aircheck.sh
   ```

2. Email address is configured globally:
   - The email address must be stored in `~/.bashrc` and `~/.profile`
   - To set it, edit the `AIRCHECK_EMAIL` variable in `~/.bashrc`:
     ```bash
     export AIRCHECK_EMAIL="your-email@example.com"
     ```
   - Then reload your shell configuration:
     ```bash
     source ~/.bashrc
     ```
   
   The script will automatically use this global variable. No need to export it each time you run the script.
   **Note:** The email address is not stored in any script files for security.

3. Ensure you have a mail client configured on your system:
   - `mail` command (usually via `mailutils` or `mailx`)
   - Or `sendmail` command

## Usage

Run the script:
```bash
./aircheck.sh
```

For automated monitoring, add to crontab:
```bash
# Run every 6 hours
0 */6 * * * cd /path/to/AirCheck && ./aircheck.sh >> aircheck.log 2>&1
```

## Files

- `aircheck.sh` - Main monitoring script
- `exclude.txt` - Tracks already-notified deals (auto-created)
- `Final.txt` - Latest parsed flight deal data

## Airport Codes Monitored

- **LAX** - Los Angeles International Airport
- **BWI** - Baltimore/Washington International Airport

The script searches for these airport codes and common city name variations in deal titles.
