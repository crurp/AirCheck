#!/bin/bash

# AirCheck - Flight Deal Monitor
# Monitors SecretFlyer.com for deals to specific airports (LAX, BWI)
# Sends email notifications when new deals are found

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Email address - Set via environment variable for security
# The email address should be configured globally in ~/.bashrc
# Usage: export AIRCHECK_EMAIL="your-email@example.com" in ~/.bashrc

# Validate email is set
if [[ -z "${AIRCHECK_EMAIL:-}" ]]; then
    echo "Error: AIRCHECK_EMAIL environment variable is not set" >&2
    echo "Please set it in ~/.bashrc: export AIRCHECK_EMAIL=\"your-email@example.com\"" >&2
    exit 1
fi

# Airports to monitor (IATA codes)
AIRPORTS=("LAX" "BWI")

# Base URL for flight deals
DEALS_URL="https://www.secretflyer.com/flight-deals/"

# Working directory (use script's directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Temporary files directory
TMP_DIR=$(mktemp -d)
trap "rm -rf '$TMP_DIR'" EXIT INT TERM

# Output files
EXCLUDE_FILE="exclude.txt"
FINAL_FILE="Final.txt"

# ============================================================================
# Functions
# ============================================================================

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Normalize title for duplicate checking (remove extra spaces, convert to uppercase)
normalize_title() {
    local title="$1"
    # Convert to uppercase, collapse multiple spaces, trim
    echo "$title" | tr '[:lower:]' '[:upper:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Check if deal was already notified (robust duplicate detection)
is_duplicate() {
    local title="$1"
    local normalized_title
    
    # Normalize the title for comparison
    normalized_title=$(normalize_title "$title")
    
    if [[ ! -f "$EXCLUDE_FILE" ]]; then
        return 1  # File doesn't exist, not a duplicate
    fi
    
    # Check for exact match (case-insensitive, normalized)
    while IFS= read -r excluded_title || [[ -n "$excluded_title" ]]; do
        local normalized_excluded=$(normalize_title "$excluded_title")
        if [[ "$normalized_title" == "$normalized_excluded" ]]; then
            return 0  # Is duplicate
        fi
    done < "$EXCLUDE_FILE"
    
    return 1  # Not duplicate
}

# Record deal as notified (adds to exceptions list)
record_deal() {
    local title="$1"
    local normalized_title
    
    # Normalize before storing
    normalized_title=$(normalize_title "$title")
    
    # Only add if not already in file (extra safety check)
    if ! grep -qFx "$normalized_title" "$EXCLUDE_FILE" 2>/dev/null; then
        echo "$normalized_title" >> "$EXCLUDE_FILE"
        log "Added to exceptions list: $normalized_title"
    fi
}

# Send email notification
send_notification() {
    local airport="$1"
    local title="$2"
    local link="$3"
    local subject="Aircheck Bot"
    local body="New deal found for ${airport}!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DEAL DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Title: ${title}

Direct Link: ${link}

Click here to view deal: ${link}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This is an automated notification from AirCheck."

    if command -v mail >/dev/null 2>&1; then
        echo -e "$body" | mail -s "$subject" "$AIRCHECK_EMAIL" && return 0
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $AIRCHECK_EMAIL"
            echo "Subject: $subject"
            echo ""
            echo "$body"
        } | sendmail "$AIRCHECK_EMAIL" && return 0
    else
        log "Warning: No mail command found. Email not sent."
        log "Deal: $title - $link"
        return 1
    fi
}

# Check if title contains airport code
contains_airport() {
    local title="$1"
    local airport="$2"
    
    # Case-insensitive search for airport code
    # Also check common variations (e.g., "LAX", "Los Angeles", "LA")
    case "$airport" in
        "LAX")
            if [[ "${title^^}" =~ (LAX|LOS\ ANGELES|LA\ ) ]]; then
                return 0
            fi
            ;;
        "BWI")
            if [[ "${title^^}" =~ (BWI|BALTIMORE) ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# ============================================================================
# Main Script
# ============================================================================

log "Starting AirCheck monitor..."

# Download flight deals page
log "Downloading deals from SecretFlyer..."
# Try wget first, fallback to curl if wget fails
if command -v wget >/dev/null 2>&1; then
    if ! wget -q --timeout=30 --tries=3 --max-redirect=5 --user-agent="Mozilla/5.0" -O "$TMP_DIR/usa-deals" "$DEALS_URL" 2>/dev/null; then
        log "Wget failed, trying curl..."
        if ! curl -s -L --max-time 30 --user-agent "Mozilla/5.0" -o "$TMP_DIR/usa-deals" "$DEALS_URL" 2>/dev/null; then
            log "Error: Failed to download deals page with both wget and curl"
            exit 1
        fi
    fi
elif command -v curl >/dev/null 2>&1; then
    if ! curl -s -L --max-time 30 --user-agent "Mozilla/5.0" -o "$TMP_DIR/usa-deals" "$DEALS_URL" 2>/dev/null; then
        log "Error: Failed to download deals page"
        exit 1
    fi
else
    log "Error: Neither wget nor curl is available"
    exit 1
fi

# Verify we got content
if [[ ! -s "$TMP_DIR/usa-deals" ]]; then
    log "Error: Downloaded file is empty"
    exit 1
fi

# Parse HTML to extract deal information
# Extract links from h2.post-title > a elements (format: <a href="URL">Title</a>)
log "Parsing deals data..."

# Method 1: Extract URL and title pairs directly using sed (works with multiline)
# Look for h2 with post-title class containing an <a> tag
sed -n 's/.*<h2[^>]*class="[^"]*post-title[^"]*"[^>]*>.*<a[^>]*href="\([^"]*\)"[^>]*>\([^<]*\)<\/a>.*/\1|\2/p' "$TMP_DIR/usa-deals" > "$TMP_DIR/Final.txt" || true

# Method 2: If Method 1 fails, try extracting from article context
if [[ ! -s "$TMP_DIR/Final.txt" ]]; then
    log "Trying alternative parsing method..."
    # Extract lines with post-title, then get the following link
    grep -A 3 'post-title' "$TMP_DIR/usa-deals" | \
        grep -oP '<a\s+href="\K[^"]+(?=")' > "$TMP_DIR/urls.txt" || true
    grep -A 3 'post-title' "$TMP_DIR/usa-deals" | \
        grep -oP '<a[^>]*href="[^"]*"[^>]*>\K[^<]+(?=</a>)' > "$TMP_DIR/titles.txt" || true
    
    if [[ -s "$TMP_DIR/urls.txt" ]] && [[ -s "$TMP_DIR/titles.txt" ]]; then
        paste -d '|' "$TMP_DIR/urls.txt" "$TMP_DIR/titles.txt" > "$TMP_DIR/Final.txt" || true
    fi
fi

# Method 3: Fallback - extract all links and filter by context
if [[ ! -s "$TMP_DIR/Final.txt" ]]; then
    log "Using fallback parsing method..."
    # Get all article sections, then extract links from post-title areas
    awk '/post-title/,/<\/h2>/' "$TMP_DIR/usa-deals" | \
        grep -oP '<a\s+href="\K[^"]+(?=")' > "$TMP_DIR/urls.txt" || true
    awk '/post-title/,/<\/h2>/' "$TMP_DIR/usa-deals" | \
        grep -oP '<a[^>]*href="[^"]*"[^>]*>\K[^<]+(?=</a>)' > "$TMP_DIR/titles.txt" || true
    
    if [[ -s "$TMP_DIR/urls.txt" ]] && [[ -s "$TMP_DIR/titles.txt" ]]; then
        paste -d '|' "$TMP_DIR/urls.txt" "$TMP_DIR/titles.txt" > "$TMP_DIR/Final.txt" || true
    fi
fi

# Clean up HTML entities
if [[ -s "$TMP_DIR/Final.txt" ]]; then
    sed -i \
        -e 's/&amp;/\&/g' \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&quot;/"/g' \
        -e "s/&#39;/'/g" \
        -e 's/&#8211;/-/g' \
        -e 's/&#8212;/--/g' \
        -e "s/&#8217;/'/g" \
        -e 's/&#8220;/"/g' \
        -e 's/&#8221;/"/g' \
        "$TMP_DIR/Final.txt"
fi

# Copy final file to working directory for reference
cp "$TMP_DIR/Final.txt" "$FINAL_FILE"

# Initialize exclude file if it doesn't exist
touch "$EXCLUDE_FILE"

# Process each deal
log "Checking for deals to ${AIRPORTS[*]}..."
deal_count=0
notification_count=0

while IFS= read -r input || [[ -n "$input" ]]; do
    # Skip empty lines
    [[ -z "$input" ]] && continue
    
    # Extract title and link
    title=$(echo "$input" | cut -d '|' -f2)
    htmllink=$(echo "$input" | cut -d '|' -f1)
    
    # Validate extracted data
    if [[ -z "$title" ]] || [[ -z "$htmllink" ]]; then
        continue
    fi
    
    # Check each monitored airport
    for airport in "${AIRPORTS[@]}"; do
        if contains_airport "$title" "$airport"; then
            deal_count=$((deal_count + 1))
            
            # Check for duplicates
            if ! is_duplicate "$title"; then
                log "New deal found for $airport: $title"
                
                if send_notification "$airport" "$title" "$htmllink"; then
                    record_deal "$title"
                    notification_count=$((notification_count + 1))
                    log "Notification sent for $airport deal"
                else
                    log "Failed to send notification for $airport deal"
                fi
            else
                log "Duplicate deal skipped: $title"
            fi
            break  # Found match, no need to check other airports
        fi
    done
done < "$TMP_DIR/Final.txt"

log "Processing complete. Found $deal_count deals, sent $notification_count new notifications."

# Cleanup is handled by trap
log "AirCheck finished successfully."