#!/bin/bash
# feed2ini.sh - Convert feed.txt to MutTechDirector.ini [MutTechDirector.DirectorFeed] section
# UNVERIFIED: The .ini array format is assumed based on typical UT2004 config format.
# Run the game once with the default messages first to generate the actual format,
# then update this script if needed.

set -euo pipefail

PROJECT_ROOT="/home/jdmr/Proyectos/ut2k4mutators/TeamDirector"
FEED_TXT="$PROJECT_ROOT/feed.txt"
INI_FILE="/home/jdmr/Juegos/UT2004/System/MutTechDirector.ini"

if [[ ! -f "$FEED_TXT" ]]; then
    echo "Error: $FEED_TXT not found"
    exit 1
fi

# Read non-empty, non-comment lines from feed.txt
messages=()
while IFS= read -r line; do
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue
    messages+=("$line")
done < "$FEED_TXT"

if [[ ${#messages[@]} -eq 0 ]]; then
    echo "Error: No valid messages in $FEED_TXT"
    exit 1
fi

# Build the Messages array lines
ini_lines=()
for i in "${!messages[@]}"; do
    # Escape double quotes and backslashes for .ini
    escaped="${messages[i]//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    ini_lines+=("Messages($i)=\"$escaped\"")
done

# Create or update the ini file
# We replace the entire [MutTechDirector.DirectorFeed] section
section_header="[MutTechDirector.DirectorFeed]"

if [[ -f "$INI_FILE" ]]; then
    # Remove existing section if present
    awk -v section="$section_header" '
        $0 == section { in_section=1; next }
        in_section && /^\[.*\]/ { in_section=0 }
        !in_section { print }
    ' "$INI_FILE" > "$INI_FILE.tmp"
    mv "$INI_FILE.tmp" "$INI_FILE"
fi

# Append the new section
{
    echo ""
    echo "$section_header"
    printf '%s\n' "${ini_lines[@]}"
} >> "$INI_FILE"

echo "Updated $INI_FILE with ${#messages[@]} messages from $FEED_TXT"