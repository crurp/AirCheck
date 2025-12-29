#!/bin/bash

# Resend test emails for LAX and BWI deals
# This script sends emails once for testing purposes, bypassing duplicate detection

set -euo pipefail

# Email configuration
: "${AIRCHECK_EMAIL:=ethancchow@gmail.com}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Test deals with URLs (LAX and BWI only)
TEST_DEALS=(
    "https://www.secretflying.com/test/lax-deal|LOS ANGELES TO TOKYO FOR ONLY \$450 ROUNDTRIP"
    "https://www.secretflying.com/test/bwi-deal|BALTIMORE TO LONDON FOR ONLY \$380 ROUNDTRIP"
    "https://www.secretflying.com/test/lax-deal2|LAX TO SINGAPORE FOR ONLY \$520 ROUNDTRIP"
)

# Function to check if title contains airport
contains_airport() {
    local title="$1"
    local airport="$2"
    
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

# Enhanced email sending function
send_notification() {
    local airport="$1"
    local title="$2"
    local link="$3"
    local subject="AirCheck: New Flight Deal - ${airport}"
    local body="New flight deal found for ${airport}!

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
        echo "Warning: No mail command found. Email not sent."
        return 1
    fi
}

# Main execution
echo "=== Resending Test Emails ==="
echo "Email: $AIRCHECK_EMAIL"
echo ""

AIRPORTS=("LAX" "BWI")
sent_count=0
failed_count=0

for deal in "${TEST_DEALS[@]}"; do
    title=$(echo "$deal" | cut -d '|' -f2)
    htmllink=$(echo "$deal" | cut -d '|' -f1)
    
    for airport in "${AIRPORTS[@]}"; do
        if contains_airport "$title" "$airport"; then
            echo "Sending email for $airport: $title"
            echo "  URL: $htmllink"
            
            if send_notification "$airport" "$title" "$htmllink"; then
                echo "  ✓ Email sent successfully!"
                sent_count=$((sent_count + 1))
            else
                echo "  ✗ Failed to send email"
                failed_count=$((failed_count + 1))
            fi
            echo ""
            break
        fi
    done
done

echo "=== Results ==="
echo "Emails sent: $sent_count"
echo "Failed: $failed_count"
echo ""
echo "Check your inbox at: $AIRCHECK_EMAIL"

