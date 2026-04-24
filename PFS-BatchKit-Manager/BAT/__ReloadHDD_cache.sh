#!/usr/bin/env bash
# =============================================================================
# __ReloadHDD_cache.sh  –  macOS equivalent of __ReloadHDD_cache.bat
# Creates BAT/__Cache/HDD.env with all HDD state variables.
# Called from the main script; variables are exported via HDD.env.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAT="$SCRIPT_DIR/BAT"
TMP="$SCRIPT_DIR/TMP"
CACHE="$BAT/__Cache"

HDL_DUMP="$BAT/hdl_dump"
PFSSHELL="$BAT/pfsshell"

# Use GNU sed if available (gsed), otherwise BSD sed
if command -v gsed &>/dev/null; then SED="gsed"; else SED="sed"; fi

mkdir -p "$CACHE" "$TMP"

# Source previously detected HDD path
[[ -f "$CACHE/HDD.env" ]] && source "$CACHE/HDD.env"

if [[ -z "$hdl_path" ]]; then
    echo "No HDD path set – run scan first."
    exit 1
fi

echo "Creating Partition Cache..."
"$HDL_DUMP" toc "$hdl_path" > "$CACHE/PARTITION_PS2HDD.txt" 2>&1
if [[ $? -ne 0 ]]; then
    echo ""
    echo "An error occurred!"
    echo "Playstation 2 HDD not recognized! Try to repair it with HDD Checker."
    echo "Or format the HDD with wLaunchELF"
    rm -f "$CACHE"/*.* 2>/dev/null
    exit 1
fi

echo "Creating Game Cache..."
"$HDL_DUMP" hdl_toc "$hdl_path" > "$CACHE/PS2_GAMES_HDD.txt" 2>&1

# ---- PS2 Games list ----
"$SED" 's/.\{46\}//' "$CACHE/PS2_GAMES_HDD.txt" \
    | "$SED" '1d; $d' \
    | cut -c35-500 > "$TMP/PS2GAMES.txt" 2>/dev/null

grep "0x1337" "$CACHE/PARTITION_PS2HDD.txt" \
    | cut -c30-250 \
    | "$SED" 's/^/|/' > "$TMP/PARTITION_HDL.txt" 2>/dev/null

paste -d " " "$TMP/PS2GAMES.txt" "$TMP/PARTITION_HDL.txt" \
    | sort -k2 > "$CACHE/PARTITION_HDL_GAME.txt" 2>/dev/null
"$SED" -i'' "s/ |/|/g" "$CACHE/PARTITION_HDL_GAME.txt" 2>/dev/null

# ---- PS1 (POPS) Games list ----
grep "\.POPS\." "$CACHE/PARTITION_PS2HDD.txt" \
    | cut -c30-250 \
    | cut -c4-13 \
    | "$SED" 's/-/_/g; s/.\{8\}/&./' > "$TMP/POPS_GAMES_ID.txt" 2>/dev/null

grep "\.POPS\." "$CACHE/PARTITION_PS2HDD.txt" \
    | cut -c30-250 \
    | "$SED" 's/^/|/' > "$TMP/PARTITION_POPS.txt" 2>/dev/null

> "$TMP/PS1GAMES.txt"
while IFS= read -r game_id; do
    [[ -z "$game_id" ]] && continue
    match=$(grep "$game_id" "$BAT/TitlesDB/TitlesDB_PS1_English.txt" 2>/dev/null | head -1)
    if [[ -z "$match" ]]; then
        echo "$game_id __UNKNOW" >> "$TMP/PS1GAMES.txt"
    else
        echo "$match" >> "$TMP/PS1GAMES.txt"
    fi
    "$SED" -i'' "s/$game_id __UNKNOW//g" "$TMP/PS1GAMES.txt" 2>/dev/null
done < "$TMP/POPS_GAMES_ID.txt"

if [[ ! -s "$TMP/PS1GAMES.txt" ]]; then
    > "$CACHE/PARTITION_POPS_GAME.txt"
else
    paste -d " " "$TMP/PS1GAMES.txt" "$TMP/PARTITION_POPS.txt" 2>/dev/null \
        | sort -k2 > "$CACHE/PARTITION_POPS_GAME.txt"
    "$SED" -i'' 's/ |/|/g; s/^|//g; s/\^//g' "$CACHE/PARTITION_POPS_GAME.txt"
fi

# ---- APPS list ----
grep "PP.APPS-" "$CACHE/PARTITION_PS2HDD.txt" \
    | cut -c30-250 | cut -c4-13 \
    | "$SED" 's/-/_/g; s/.\{8\}/&./' > "$TMP/APPS_ID.txt" 2>/dev/null

grep "PP.APPS-" "$CACHE/PARTITION_PS2HDD.txt" \
    | cut -c30-250 \
    | "$SED" 's/^/|/' > "$TMP/PARTITION_APPS.txt" 2>/dev/null

> "$TMP/APPS.txt"
while IFS= read -r app_id; do
    [[ -z "$app_id" ]] && continue
    match=$(grep "$app_id" "$BAT/TitlesDB/TitlesDB_APP.txt" 2>/dev/null | head -1)
    if [[ -z "$match" ]]; then
        echo "$app_id __UNKNOW" >> "$TMP/APPS.txt"
    else
        echo "$match" >> "$TMP/APPS.txt"
    fi
    "$SED" -i'' "s/$app_id __UNKNOW//g" "$TMP/APPS.txt" 2>/dev/null
done < "$TMP/APPS_ID.txt"

if [[ ! -s "$TMP/APPS.txt" ]]; then
    > "$CACHE/PARTITION_APPS.txt"
else
    paste -d " " "$TMP/APPS.txt" "$TMP/PARTITION_APPS.txt" 2>/dev/null \
        | sort -k2 > "$CACHE/PARTITION_APPS.txt"
    "$SED" -i'' 's/ |/|/g; s/^|//g; s/\^//g' "$CACHE/PARTITION_APPS.txt"
fi

# ---- HDD Size totals ----
total_line=$(grep "Total slice size:" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null | head -1)
TotalHDD_Used=$(echo "$total_line" | awk '{print $6}')
TotalHDD_Available=$(echo "$total_line" | awk '{print $8}')

_fmt_mb() {
    local raw="${1//[^0-9]/}"
    if [[ -z "$raw" || "$raw" -eq 0 ]]; then echo "0MB"; return; fi
    if [[ "$raw" -lt 1000 ]]; then echo "${raw}MB"
    else printf "%d.%03dGB\n" $((raw/1000)) $((raw%1000)); fi
}

TotalHDD_Used_num="${TotalHDD_Used//[^0-9]/}"
TotalHDD_Available_num="${TotalHDD_Available//[^0-9]/}"

TotalHDD_Used_fmt=$(_fmt_mb "$TotalHDD_Used_num")
TotalHDD_Available_fmt=$(_fmt_mb "$TotalHDD_Available_num")

if [[ -n "$TotalHDD_Size" && "$TotalHDD_Size" -gt 0 ]]; then
    pct=$(( TotalHDD_Used_num * 100 / TotalHDD_Size ))
    TotalHDD_Percentage="${pct}%%"
else
    TotalHDD_Percentage="?%%"
fi

# ---- OPL Resource Partition ----
{
    echo "device $pfsshell_path"
    echo "mount __common"
    echo "cd OPL"
    echo "lcd $TMP"
    echo "get conf_hdd.cfg"
    echo "cd .."
    echo "umount"
    echo "exit"
} | "$PFSSHELL" >/dev/null 2>&1

if [[ ! -f "$TMP/conf_hdd.cfg" ]]; then
    OPLPART="__common"
else
    # cut -d= -f2 + tr -d '\r' strips Windows CRLF that pfsshell may carry over
    OPLPART=$(grep "hdd_partition=" "$TMP/conf_hdd.cfg" 2>/dev/null \
        | head -1 | cut -d= -f2 | tr -d '\r')
    [[ -z "$OPLPART" ]] && OPLPART="__common"
fi

echo "hdd_partition=$OPLPART" > "$SCRIPT_DIR/HDD-OSD/__common/OPL/conf_hdd.cfg"

if [[ "$OPLPART" == "+OPL" ]]; then
    CUSTOM_OPLPART=""
else
    CUSTOM_OPLPART="Yes"
fi

# Write conf_hdd.cfg to __common partition if missing
if [[ ! -f "$TMP/conf_hdd.cfg" ]]; then
    {
        echo "device $pfsshell_path"
        echo "mount __common"
        echo "mkdir OPL"
        echo "cd OPL"
        echo "lcd $SCRIPT_DIR/HDD-OSD/__common/OPL"
        echo "put conf_hdd.cfg"
        echo "cd .."
        echo "umount"
        echo "exit"
    } | "$PFSSHELL" >/dev/null 2>&1
fi

# ---- Detect PSX DESR HDD ----
{
    echo "device $pfsshell_path"
    echo "mount __system"
    echo "lcd $TMP"
    echo "get main.xml"
    echo "get psxmain.xml"
    echo "umount"
    echo "exit"
} | "$PFSSHELL" >/dev/null 2>&1

[[ -f "$TMP/psxmain.xml" ]] && mv "$TMP/psxmain.xml" "$TMP/main.xml"
if [[ -f "$TMP/main.xml" ]]; then PSX2DESR_HDD="Yes"; else PSX2DESR_HDD="No"; fi

# ---- Detect PSBBN ----
PSBBN_Installed="No"
psbbn_output=$(printf "device %s\nmount __system\nls\numount\nexit\n" "$pfsshell_path" \
    | "$PFSSHELL" 2>/dev/null | grep -m1 "p2lboot")
[[ "$psbbn_output" == *"p2lboot"* ]] && PSBBN_Installed="Yes"

# ---- Write HDD.env (sourceable by bash) ----
cat > "$CACHE/HDD.env" <<EOF
hdl_path="$hdl_path"
pfsshell_path="$pfsshell_path"
NumberPS2HDD="$NumberPS2HDD"
ModelePS2HDD="$ModelePS2HDD"
TotalHDD_Size_fmt="$TotalHDD_Size_fmt"
TotalHDD_Size="$TotalHDD_Size"
TotalHDD_Used="$TotalHDD_Used_fmt"
TotalHDD_Available="$TotalHDD_Available_fmt"
TotalHDD_Percentage="$TotalHDD_Percentage"
PSX2DESR_HDD="$PSX2DESR_HDD"
PSBBN_Installed="$PSBBN_Installed"
OPLPART="$OPLPART"
CUSTOM_OPLPART="$CUSTOM_OPLPART"
EOF

echo "Cache created successfully."
