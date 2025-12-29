#!/bin/bash

# Send a test email with the new format

set -euo pipefail

# Email address from global environment variable
if [[ -z "${AIRCHECK_EMAIL:-}" ]]; then
    echo "Error: AIRCHECK_EMAIL environment variable is not set" >&2
    echo "Please set it in ~/.bashrc: export AIRCHECK_EMAIL=\"your-email@example.com\"" >&2
    exit 1
fi

# Test data - LAX deal
AIRPORT="LAX"
TITLE="Vancouver BC Canada (YVR) – Los Angeles CA USA (LAX) from \$216 CAD Round Trip"
LINK="https://www.secretflyer.com/vancouver-bc-canada-yvr-los-angeles-ca-usa-lax-from-216-cad-round-trip/"

SUBJECT="Aircheck Bot"
BODY="New deal found for ${AIRPORT}!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DEAL DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Title: ${TITLE}

Direct Link: ${LINK}

Click here to view deal: ${LINK}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This is an automated notification from AirCheck."

echo "Sending test email to: $AIRCHECK_EMAIL"
echo "Subject: $SUBJECT"
echo ""

if command -v mail >/dev/null 2>&1; then
    echo -e "$BODY" | mail -s "$SUBJECT" "$AIRCHECK_EMAIL" && echo "✓ Email sent successfully!"
elif command -v sendmail >/dev/null 2>&1; then
    {
        echo "To: $AIRCHECK_EMAIL"
        echo "Subject: $SUBJECT"
        echo ""
        echo "$BODY"
    } | sendmail "$AIRCHECK_EMAIL" && echo "✓ Email sent successfully!"
else
    echo "✗ No mail command found"
    exit 1
fi

