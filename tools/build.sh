#!/usr/bin/env bash
#
# tools/build.sh - build + install MutTechDirector into the local UT2004 copy
# (Windows edition driven through Wine).
#
# Safe by design: UT2004.ini is backed up before the temporary EditPackages
# entry is added and restored on exit, so a failed build never leaves the
# game install with a dangling package registration.
#
# Steps:
#   1. sync source/MutTechDirector/Classes/*.uc -> $UT2004_DIR/MutTechDirector/Classes
#   2. temporarily append EditPackages=MutTechDirector to UT2004.ini
#   3. compile with "ucc make" (Wine)  => System/MutTechDirector.u
#   4. generate the mutator cache      => System/MutTechDirector.ucl
#   5. install the localization and feed config files
#      => System/MutTechDirector.int and System/MutTechDirector.ini
#   6. restore UT2004.ini and keep a prebuilt copy of the package
#
# Requirements: wine with access to the game's drive mapping; UT2004_DIR can
# point at any Windows-edition UT2004 install.
#
set -euo pipefail

UTDIR="${UT2004_DIR:-$HOME/Juegos/UT2004}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="MutTechDirector"
SYSTEM="$UTDIR/System"
INI="$SYSTEM/UT2004.ini"

if [ ! -f "$SYSTEM/UCC.exe" ]; then
    echo "ERROR: UCC.exe not found in $SYSTEM (set UT2004_DIR)" >&2
    exit 1
fi
if [ ! -f "$INI" ]; then
    echo "ERROR: UT2004.ini not found in $SYSTEM" >&2
    exit 1
fi

echo "==> game   : $UTDIR"
echo "==> source : $ROOT/source/$PKG/Classes"

# --- 1) sync classes (wipe first: stale renamed classes must not linger) -----
rm -rf "$UTDIR/$PKG/Classes"
mkdir -p "$UTDIR/$PKG/Classes"
cp -f "$ROOT/source/$PKG/Classes/"*.uc "$UTDIR/$PKG/Classes/"

# --- 2) EditPackages bookkeeping (with guaranteed restore) -------------------
BACKUP="$(mktemp "${TMPDIR:-/tmp}/UT2004.ini.${PKG}.XXXXXX")"
cp -f "$INI" "$BACKUP"
restore_ini() { cp -f "$BACKUP" "$INI"; rm -f "$BACKUP"; }
trap restore_ini EXIT INT TERM

python3 - "$INI" "$PKG" <<'PY'
import io, re, sys
path, pkg = sys.argv[1], sys.argv[2]
text = io.open(path, encoding='latin-1', errors='replace').read()

m = re.search(r'^\[Editor\.EditorEngine\]\s*$', text, re.M | re.I)
if not m:
    sys.exit("ERROR: [Editor.EditorEngine] not found in UT2004.ini")

start = m.end()
end = re.search(r'^\[\w[\w.]*\]\s*$', text[start:], re.M)
end = start + end.start() if end else len(text)
block = text[start:end]

lines = block.splitlines(True)
seen, kept, last_edit = set(), [], -1
for ln in lines:
    p = re.match(r'^(\s*EditPackages\w*)(\s*=\s*)(\S+)\s*$', ln, re.I)
    if p:
        name = p.group(3).strip()
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        if p.group(1).lower() == 'editpackages':
            last_edit = len(kept)
    kept.append(ln)

# The package must be compiled *after* its dependencies, so append it at the
# end of the EditPackages list rather than at the top of the section.
if pkg.lower() not in seen:
    kept.insert(last_edit + 1, "EditPackages=%s\n" % pkg)

text = text[:start] + ''.join(kept) + text[end:]
io.open(path, 'w', encoding='latin-1', errors='replace').write(text)
print("EditPackages ok: %s registered for this build" % pkg)
PY

# --- 3) compile --------------------------------------------------------------
# ucc make can consider a package "up to date" after a rename, so always
# rebuild this single package from scratch.
rm -f "$SYSTEM/$PKG.u"
cd "$SYSTEM"
set +e
BUILD_LOG="$(wine UCC.exe make 2>&1 | grep -Ev "fixme:|wineboot|winediag")"
set -e
printf '%s\n' "$BUILD_LOG"
if [ ! -f "$SYSTEM/$PKG.u" ] || printf '%s\n' "$BUILD_LOG" | grep -q "Compile aborted due to errors"; then
    echo "ERROR: $PKG.u was not produced; UT2004.ini has been restored" >&2
    exit 1
fi
echo "==> compiled: $SYSTEM/$PKG.u"

# --- 4) mutator cache (.ucl) -------------------------------------------------
wine UCC.exe exportcache "$PKG.u" 2>&1 | grep -Ev "fixme:|wineboot|winediag" || true
test -f "$PKG.ucl" || echo "WARN: $PKG.ucl not produced (the Object= line in the .int still covers mutator lists)"

# --- 5) localization and feed config ----------------------------------------
cp -f "$ROOT/install/$PKG.int" "$SYSTEM/$PKG.int"
cp -f "$ROOT/install/$PKG.ini" "$SYSTEM/$PKG.ini"

# --- 6) keep a release copy --------------------------------------------------
mkdir -p "$ROOT/prebuilt/System"
cp -f "$SYSTEM/$PKG.u" "$ROOT/prebuilt/System/$PKG.u"
if [ -f "$SYSTEM/$PKG.ucl" ]; then
    cp -f "$SYSTEM/$PKG.ucl" "$ROOT/prebuilt/System/$PKG.ucl"
fi
{
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$ROOT/prebuilt/BUILD"

echo "==> installed: $PKG.u / $PKG.int / $PKG.ini in $SYSTEM"
echo "==> done. Pick 'MutTech Director' in the mutator list."
