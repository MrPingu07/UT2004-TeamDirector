#!/bin/bash
# feed2ini.sh - Convert feed.txt to MutTechDirector.ini [MutTechDirector.DirectorFeed] section
#
# UE2 config format note: Messages is a *dynamic* array (var config array<string>),
# and UT2004 reads those as repeated bare keys, not indexed keys:
#     Messages=FIRST MESSAGE
#     Messages=SECOND MESSAGE
# The "Messages(0)=..." form only works for static arrays (e.g. Aliases[0] in
# User.ini), so using it here leaves the class defaults in place.

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
# The "|| [[ -n $line ]]" keeps a final line that lacks a trailing newline.
while IFS= read -r line || [[ -n "$line" ]]; do
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

# Build the Messages array lines.  Dynamic array config entries are repeated
# bare keys: "Messages=value".  Values are unquoted, as UT2004 itself writes
# string config entries that way.
ini_lines=()
for msg in "${messages[@]}"; do
    ini_lines+=("Messages=$msg")
done

# Create or update the ini file
# We replace the entire [MutTechDirector.DirectorFeed] section
section_header="[MutTechDirector.DirectorFeed]"

if [[ -f "$INI_FILE" ]]; then
    # Remove existing section if present, then drop trailing blank lines so
    # repeated runs do not pile up empty lines before the section we append.
    awk -v section="$section_header" '
        $0 == section { in_section=1; next }
        in_section && /^\[.*\]/ { in_section=0 }
        !in_section { print }
    ' "$INI_FILE" \
    | awk 'NF { while (b) { print ""; b-- } print; next } { b++ }' \
    > "$INI_FILE.tmp"
    mv "$INI_FILE.tmp" "$INI_FILE"
fi

# Append the new section
{
    echo ""
    echo "$section_header"
    printf '%s\n' "${ini_lines[@]}"
} >> "$INI_FILE"

echo "Updated $INI_FILE with ${#messages[@]} messages from $FEED_TXT"