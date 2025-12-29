#!/bin/bash

# Test script for AirCheck - Tests email sending and duplicate detection

set -euo pipefail

# Email configuration
: "${AIRCHECK_EMAIL:=ethancchow@gmail.com}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

EXCLUDE_FILE="exclude.txt"
TEST_FILE="test_deals.txt"

# Source functions from main script (simplified versions)
normalize_title() {
    local title="$1"
    echo "$title" | tr '[:lower:]' '[:upper:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

is_duplicate() {
    local title="$1"
    local normalized_title
    
    normalized_title=$(normalize_title "$title")
    
    if [[ ! -f "$EXCLUDE_FILE" ]]; then
        return 1
    fi
    
    while IFS= read -r excluded_title || [[ -n "$excluded_title" ]]; do
        local normalized_excluded=$(normalize_title "$excluded_title")
        if [[ "$normalized_title" == "$normalized_excluded" ]]; then
            return 0
        fi
    done < "$EXCLUDE_FILE"
    
    return 1
}

record_deal() {
    local title="$1"
    local normalized_title
    
    normalized_title=$(normalize_title "$title")
    
    if ! grep -qFx "$normalized_title" "$EXCLUDE_FILE" 2>/dev/null; then
        echo "$normalized_title" >> "$EXCLUDE_FILE"
        echo "✓ Added to exceptions list: $normalized_title"
    fi
}

send_notification() {
    local airport="$1"
    local title="$2"
    local link="$3"
    local subject="AirCheck TEST: New Flight Deal - ${airport}"
    local body="TEST: New flight deal found for ${airport}!

Title: ${title}

Link: ${link}

---
This is a TEST notification from AirCheck."

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

# Main test
echo "=== AirCheck Test Mode ==="
echo "Email: $AIRCHECK_EMAIL"
echo ""

AIRPORTS=("LAX" "BWI")
touch "$EXCLUDE_FILE"

deal_count=0
notification_count=0

while IFS= read -r input || [[ -n "$input" ]]; do
    [[ -z "$input" ]] && continue
    
    title=$(echo "$input" | cut -d '|' -f2)
    htmllink=$(echo "$input" | cut -d '|' -f1)
    
    [[ -z "$title" ]] || [[ -z "$htmllink" ]] && continue
    
    for airport in "${AIRPORTS[@]}"; do
        if contains_airport "$title" "$airport"; then
            deal_count=$((deal_count + 1))
            echo "Found deal for $airport: $title"
            
            if ! is_duplicate "$title"; then
                echo "  → New deal (not in exceptions list)"
                
                if send_notification "$airport" "$title" "$htmllink"; then
                    record_deal "$title"
                    notification_count=$((notification_count + 1))
                    echo "  ✓ Email sent successfully!"
                else
                    echo "  ✗ Failed to send email"
                fi
            else
                echo "  → Duplicate (already in exceptions list - skipping)"
            fi
            break
        fi
    done
done < "$TEST_FILE"

echo ""
echo "=== Test Results ==="
echo "Total deals found: $deal_count"
echo "New notifications sent: $notification_count"
echo ""
echo "Exceptions list contents:"
cat "$EXCLUDE_FILE" | sed 's/^/  - /' || echo "  (empty)"

