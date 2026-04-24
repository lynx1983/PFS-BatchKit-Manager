#!/usr/bin/env bash
# =============================================================================
# PFS-BatchKit-Manager v1.2.0  –  macOS Bash port
# Original Windows CMD/Batch version by GDX
# Requires: hdl_dump, pfsshell, pfsfuse (in BAT/), 7zz, gsed, curl
# Run install_deps.sh from the project root to install all dependencies.
# =============================================================================

# ---- Bash 3.2 compatibility helper (macOS ships bash 3.2, no ${var,,}) ----
tolower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# ---- Require sudo (admin) ----
if [[ "$EUID" -ne 0 ]]; then
    echo "Requesting administrator privileges..."
    exec sudo bash "$0" "$@"
fi

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAT="$SCRIPT_DIR/BAT"
TMP="$SCRIPT_DIR/TMP"
CACHE="$BAT/__Cache"
LOG="$SCRIPT_DIR/LOG"
SETTINGS="$SCRIPT_DIR/settings.ini"

# ---- Tool paths ----
HDL_DUMP="$BAT/hdl_dump"
HDL_DUMP_STABLE="$BAT/hdl_dump_stable"
PFSSHELL="$BAT/pfsshell"
PFSFUSE="$BAT/pfsfuse"
SEVENZIP="$BAT/7-Zip/7zz"

# ---- GNU sed ----
if command -v gsed &>/dev/null; then SED="gsed"; else SED="sed"; fi

# ---- ANSI color codes (Windows Diagbox gd XX equivalents) ----
C_RESET='\033[0m'
C_WHITE='\033[1;37m'    # 0f
C_CYAN='\033[0;36m'     # 03
C_RED='\033[0;31m'      # 0c
C_GREEN='\033[0;32m'    # 0a
C_YELLOW='\033[1;33m'   # 0e
C_ORANGE='\033[0;33m'   # 06
C_MAGENTA='\033[0;35m'  # 0d
C_BLUE='\033[0;34m'     # 01
C_GRAY='\033[0;37m'     # 07

# ---- Color shortcuts ----
cw() { echo -en "${C_WHITE}";   }  # white / bright
cc() { echo -en "${C_CYAN}";    }  # cyan
cr() { echo -en "${C_RED}";     }  # red
cg() { echo -en "${C_GREEN}";   }  # green
cy() { echo -en "${C_YELLOW}";  }  # yellow
co() { echo -en "${C_ORANGE}";  }  # orange/dark-yellow
cm() { echo -en "${C_MAGENTA}"; }  # magenta
cn() { echo -en "${C_RESET}";   }  # normal reset

# ---- Variables ----
VERSION="1.2.0"
hdl_path=""
pfsshell_path=""
NumberPS2HDD=""
ModelePS2HDD=""
TotalHDD_Size=""
TotalHDD_Size_fmt=""
TotalHDD_Used=""
TotalHDD_Available=""
TotalHDD_Percentage=""
PSX2DESR_HDD=""
PSBBN_Installed=""
OPLPART="__common"
CUSTOM_OPLPART=""
TitlesLang="English"
DBLang="En"
update=""
GithubUPDATE=""

# ---- Helper: press Enter to continue ----
press_enter() { cw; read -r -p "${1:-Press Enter to continue...}"; cn; }

# ---- Helper: choice function (replaces CHOICE /C) ----
# Usage: choice "YN" → sets CHOICE_RESULT to 1-based index
choice() {
    local chars; chars=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local prompt="${2:-Select Option:}"
    local c
    while true; do
        cw; read -r -p "$prompt " c; cn
        c=$(echo "$c" | tr '[:lower:]' '[:upper:]')
        local idx=1
        for (( i=0; i<${#chars}; i++ )); do
            ch="${chars:$i:1}"
            if [[ "$c" == "$ch" ]]; then
                CHOICE_RESULT=$idx
                return
            fi
            (( idx++ ))
        done
        echo "Invalid input. Choose from: $chars"
    done
}

# ---- Helper: yes/no shortcut ----
# Returns 0 for Y, 1 for N
ask_yn() {
    local prompt="${1:-Confirm? [Y/N]}"
    choice "YN" "$prompt"
    return $(( CHOICE_RESULT - 1 ))
}

# ---- Helper: header banner ----
header() {
    clear
    cw; echo "PFS BatchKit Manager v${VERSION} By GDX"
    echo "-------------------------------------------------------------------------------------------------------------"
    cn
    _print_hdd_status
    cw; echo "-------------------------------------------------------------------------------------------------------------"; cn
}

# ---- Helper: print HDD status line ----
_print_hdd_status() {
    if [[ -n "$hdl_path" ]]; then
        cc; echo "[$hdl_path $ModelePS2HDD] - [Total: $TotalHDD_Size_fmt - Used: $TotalHDD_Used $TotalHDD_Percentage - Free: $TotalHDD_Available] - [Loaded: $OPLPART]"; cn
    else
        cr; echo "[NO DEVICE] PLEASE RELOAD HDD"; cn
    fi
}

# ---- Helper: scan HDD availability (quick re-check) ----
_verify_hdd() {
    if [[ -z "$hdl_path" ]]; then
        scan_ps2_hdd; return $?
    fi
    if ! "$HDL_DUMP" toc "$hdl_path" >/dev/null 2>&1; then
        hdl_path=""
        scan_ps2_hdd; return $?
    fi
    return 0
}

# ---- Helper: require HDD ----
_require_hdd() {
    if [[ -z "$hdl_path" ]]; then
        scan_ps2_hdd
        [[ -z "$hdl_path" ]] && { press_enter; return 1; }
    fi
    return 0
}

# ---- Helper: pfsshell pipe wrapper ----
pfsshell_run() {
    # $1 = commands string (multi-line)
    printf '%s\n' "$1" | "$PFSSHELL" 2>/dev/null
}

# ---- Helper: mb/gb formatter ----
_fmt_size() {
    local n="${1//[^0-9]/}"
    [[ -z "$n" || "$n" -eq 0 ]] && echo "0MB" && return
    if (( n < 1000 )); then echo "${n}MB"
    else printf "%d.%03dGB\n" $((n/1000)) $((n%1000)); fi
}

# ---- Helper: reload HDD cache ----
# Must write current hdl_path/pfsshell_path to HDD.env BEFORE calling the
# cache script, because the child process has no access to our variables.
reload_hdd_cache() {
    mkdir -p "$CACHE"
    cat > "$CACHE/HDD.env" <<EOF
hdl_path="$hdl_path"
pfsshell_path="$pfsshell_path"
NumberPS2HDD="$NumberPS2HDD"
ModelePS2HDD="$ModelePS2HDD"
TotalHDD_Size="$TotalHDD_Size"
TotalHDD_Size_fmt="$TotalHDD_Size_fmt"
OPLPART="$OPLPART"
CUSTOM_OPLPART="$CUSTOM_OPLPART"
EOF
    bash "$BAT/__ReloadHDD_cache.sh"
    [[ -f "$CACHE/HDD.env" ]] && source "$CACHE/HDD.env"
}

# ---- Helper: load settings ----
load_settings() {
    [[ -f "$SETTINGS" ]] && source "$SETTINGS"
    [[ -f "$CACHE/HDD.env" ]] && source "$CACHE/HDD.env"
    # Strip stray carriage returns that may come from CRLF files on PS2 HDD
    OPLPART="${OPLPART//$'\r'/}"
    CUSTOM_OPLPART="${CUSTOM_OPLPART//$'\r'/}"
}

# ---- Helper: save settings ----
save_settings() {
    echo "TitlesLang=$TitlesLang"       > "$SETTINGS"
    echo "DBLang=$DBLang"              >> "$SETTINGS"
    echo "OPLPART=$OPLPART"            >> "$SETTINGS"
    echo "CUSTOM_OPLPART=$CUSTOM_OPLPART" >> "$SETTINGS"
}

# ---- Helper: check connectivity ----
_ping_host() {
    # macOS ping: -W is in milliseconds (unlike Linux where it is seconds)
    ping -c 1 -W 2000 -t 2 "$1" &>/dev/null
}

# ---- Detect macOS disk device for hdl_dump ----
# macOS hdl_dump has no "query" command; we enumerate disks with diskutil
# and probe each with "hdl_dump toc" to see if it is a PS2 HDD.
_list_ps2_hdds() {
    while IFS= read -r disk; do
        local dev="/dev/$disk"
        # hdl_dump toc exits 0 only for a valid PS2 HDD
        if "$HDL_DUMP" toc "$dev" >/dev/null 2>&1; then
            local model; model=$(diskutil info "$dev" 2>/dev/null \
                | grep -E "Device / Media Name|Media Name:" \
                | head -1 | awk -F: '{print $2}' | xargs)
            local size_mb; size_mb=$(_get_disk_size_mb "$dev")
            echo "$dev   $model   ${size_mb}MB   Playstation 2 HDD"
        fi
    done < <(diskutil list 2>/dev/null \
        | grep "^/dev/disk" | grep -v "^/dev/disk0" \
        | awk '{print $1}' | sed 's|/dev/||')
}

_get_disk_model() {
    local dev="${1##/dev/}"      # strip /dev/
    dev="${dev#r}"               # strip leading r (rdiskN → diskN)
    diskutil info "/dev/$dev" 2>/dev/null \
        | grep -E "Device / Media Name|Media Name:" \
        | head -1 | awk -F: '{print $2}' | xargs
}

_get_disk_size_mb() {
    local dev="${1##/dev/}"
    dev="${dev#r}"
    local bytes
    bytes=$(diskutil info "/dev/$dev" 2>/dev/null \
        | grep "Disk Size" | grep -oE '[0-9]+ Bytes' | grep -oE '[0-9]+')
    [[ -n "$bytes" ]] && echo $(( bytes / 1048576 )) || echo "0"
}

# =============================================================================
# INIT
# =============================================================================
init_dirs() {
    for d in APPS ART CD CFG CHT DVD LNG LOG POPS THM VMC TMP; do
        mkdir -p "$SCRIPT_DIR/$d"
    done
    mkdir -p "$SCRIPT_DIR/POPS/VMC"
    mkdir -p "$SCRIPT_DIR/POPS-Binaries"
    mkdir -p "$SCRIPT_DIR/HDD-OSD/__sysconf"
    mkdir -p "$SCRIPT_DIR/HDD-OSD/__system"
    mkdir -p "$SCRIPT_DIR/HDD-OSD/__common/OPL"
    mkdir -p "$SCRIPT_DIR/HDD-OSD/PP.HEADER/PFS/res/image"
    mkdir -p "$CACHE"
    mkdir -p "$TMP"
    chflags hidden "$BAT" 2>/dev/null || true   # hide BAT folder (macOS equivalent of attrib +h)
}

# Move PS1 games if script crashed mid-transfer
_recover_pops() {
    if [[ -d "$SCRIPT_DIR/POPS/Temp" ]]; then
        find "$SCRIPT_DIR/POPS/Temp" \( -name "*.VCD" -o -name "*.CUE" -o -name "*.BIN" \) \
            -exec mv {} "$SCRIPT_DIR/POPS/" \; 2>/dev/null
        rm -rf "$SCRIPT_DIR/POPS/Temp"
    fi
    for f in TROJAN_?.BIN PATCH_?.BIN CHEATS.TXT Readme.txt; do
        rm -f "$SCRIPT_DIR/POPS/$f" 2>/dev/null
    done
}

# =============================================================================
# UPDATE CHECK
# =============================================================================
check_for_updates() {
    [[ -n "$GithubUPDATE" ]] && return
    echo "Checking for updates..."
    if ! _ping_host github.com; then
        cr; echo "Unable to PING github.com!"; cn
        return
    fi

    local tmp_bat="$TMP/!PFS-BatchKit-Manager2.sh"
    curl -s -L "https://raw.githubusercontent.com/GDX-X/PFS-BatchKit-Manager/main/PFS-BatchKit-Manager/!PFS-BatchKit-Manager.bat" \
        -o "$tmp_bat" 2>/dev/null
    [[ ! -s "$tmp_bat" ]] && rm -f "$tmp_bat" && return

    local md5_new md5_cur
    md5_new=$(md5 -q "$tmp_bat" 2>/dev/null || md5sum "$tmp_bat" 2>/dev/null | cut -d' ' -f1)
    md5_cur=$(md5 -q "$SCRIPT_DIR/!PFS-BatchKit-Manager.bat" 2>/dev/null \
              || md5sum "$SCRIPT_DIR/!PFS-BatchKit-Manager.bat" 2>/dev/null | cut -d' ' -f1)

    if [[ -n "$md5_new" && "$md5_new" != "$md5_cur" ]]; then
        update="UPDATE AVAILABLE"
    else
        update=""
        rm -f "$tmp_bat"
    fi
    GithubUPDATE=1
}

# =============================================================================
# DB LANGUAGE SETTINGS
# =============================================================================
db_lang_settings() {
    local UpdateDB_local="${UpdateDB:-}"
    load_settings

    if [[ -z "$UpdateDB_local" ]]; then
        clear
        [[ -z "$TitlesLang" ]] && TitlesLang="NONE"
        cw; echo "Database languages - Current: $TitlesLang"
        echo "---------------------------------------------------"
        echo ""
        echo "Choose the database language you want to use"
        echo "Will be used for game information:"
        echo "Title / Release / Descriptions"
        echo ""
        cy; echo "NOTE: Some titles may not be translated"; cn
        echo "---------------------------------------------------"
        echo ""
        echo "1 English (Default)"
        echo "2 French"
        echo "3 German"
        echo "4 Spanish"
        echo "5 Italian"
        echo "6 Portuguese"
        echo ""
        choice "123456" "Select Option:"
        case $CHOICE_RESULT in
            1) DBLang="En"; TitlesLang="English"    ;;
            2) DBLang="Fr"; TitlesLang="French"     ;;
            3) DBLang="De"; TitlesLang="German"     ;;
            4) DBLang="Es"; TitlesLang="Spanish"    ;;
            5) DBLang="It"; TitlesLang="Italian"    ;;
            6) DBLang="Pt"; TitlesLang="Portuguese" ;;
        esac
        save_settings
    fi

    echo ""
    echo "Downloading latest database updates..."
    if ! _ping_host github.com; then
        cr; echo "Unable to PING!"; cn
        return
    fi

    local db_archive="$TMP/OPL-Games-Infos-Database-Project.7z"
    curl -L --progress-bar \
        "https://github.com/GDX-X/OPL-Games-Infos-Database-Project/releases/download/Latest/OPL-Games-Infos-Database-Project.7z" \
        -o "$db_archive" 2>/dev/null

    if [[ -s "$db_archive" ]]; then
        mv "$db_archive" "$BAT/"
        for dbtype in PS1 PS2; do
            "$SEVENZIP" e -bso0 "$BAT/OPL-Games-Infos-Database-Project.7z" \
                -o"$TMP" "${dbtype}DB_${DBLang}.xml" -r -y >/dev/null 2>&1
            "$SED" -i'' 's/\&amp;/\&/g' "$TMP/${dbtype}DB_${DBLang}.xml" 2>/dev/null || true
            mv "$TMP/${dbtype}DB_${DBLang}.xml" "$BAT/${dbtype}DB.xml" 2>/dev/null || true
        done
    fi
}

# =============================================================================
# SCAN PS2 HDD
# =============================================================================
scan_ps2_hdd() {
    clear
    rm -rf "$CACHE" && mkdir -p "$CACHE"
    mkdir -p "$TMP"

    cw; echo ""
    echo "Scanning for Playstation 2 HDDs:"
    echo "---------------------------------------------------"
    cn

    local hdd_list
    hdd_list=$(_list_ps2_hdds)
    local total
    total=$(echo "$hdd_list" | grep -c "Playstation 2 HDD" 2>/dev/null || echo 0)

    if [[ "$total" -eq 0 ]]; then
        cr; echo "        Playstation 2 HDD Not Detected"
        echo "        Drive Must Be Formatted First"; cn
        echo ""
        press_enter
        return 1
    fi

    if [[ "$total" -gt 1 ]]; then
        cc; echo "$hdd_list"; cn
        cy; echo ""
        echo "Several HDDs in PS2 format have been detected."
        echo ""
        echo "Enter the disk number (e.g. for /dev/disk2, type: 2)"
        cn
        cw; read -r -p "Select Option: " NumberPS2HDD; cn
        [[ -z "$NumberPS2HDD" ]] && return 0
        hdl_path="/dev/disk${NumberPS2HDD}"

        if ! "$HDL_DUMP" toc "$hdl_path" >/dev/null 2>&1; then
            cr; echo ""; echo "        HDD Not Detected"; echo ""; cn
            rm -rf "$CACHE"
            press_enter
            return 1
        fi
    else
        hdl_path=$(echo "$hdd_list" | awk '{print $1}' | head -1)
        NumberPS2HDD="${hdl_path//[^0-9]/}"
    fi

    # Use raw disk for direct access (better throughput)
    # pfsshell and hdl_dump on macOS can use /dev/rdiskN
    local raw_path="/dev/rdisk${NumberPS2HDD}"
    [[ -b "$raw_path" ]] && pfsshell_path="$raw_path" || pfsshell_path="$hdl_path"

    # Disk model
    ModelePS2HDD=$(_get_disk_model "$hdl_path")
    ModelePS2HDD="${ModelePS2HDD//USB Device/}"
    ModelePS2HDD="${ModelePS2HDD//Disk Device/}"
    ModelePS2HDD="${ModelePS2HDD#"${ModelePS2HDD%%[! ]*}"}"  # trim leading spaces

    # Disk size from hdl_dump toc ("Total slice size: XXXXMB free: XXXXMB")
    local toc_last
    toc_last=$("$HDL_DUMP" toc "$hdl_path" 2>/dev/null | grep "Total slice size:" | head -1)
    TotalHDD_Size=$(echo "$toc_last" | grep -oE '[0-9]+MB' | head -1 | tr -d 'MB')
    [[ -z "$TotalHDD_Size" ]] && TotalHDD_Size=$(_get_disk_size_mb "$hdl_path")
    TotalHDD_Size_fmt=$(_fmt_size "$TotalHDD_Size")

    cw
    echo "Model: [$ModelePS2HDD]"
    echo "Drive: [$pfsshell_path]"
    echo "Size:  [$TotalHDD_Size_fmt]"
    cn

    # Unmount disk partitions before direct access
    echo "Unmounting disk partitions for direct access..."
    diskutil unmountDisk "$hdl_path" >/dev/null 2>&1 || true

    reload_hdd_cache
    return 0
}

# =============================================================================
# MAIN MENU
# =============================================================================
main_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Main Menu |=====]"
        echo ""
        echo " [1]  Install PS1 Games"
        echo " [2]  Install PS2 Games"
        echo ""
        echo " [3]  OPL Management"
        echo " [4]  POPS Management"
        echo " [5]  Games Management"
        echo " [6]  Downloads/Update Management"
        echo " [7]  Networking OnlinePlay"
        echo ""
        echo " [8]  OSD/XMB Management"
        echo " [9]  HDD Management"
        echo ""
        echo " [11] Exit"
        echo " [12] About"
        echo " [13] Change/Reload HDD"
        echo " [14] Settings"
        echo ""
        cy; echo " [15] Donate"
        cw
        if [[ -n "$update" ]]; then
            cg; echo " [20] $update"; cw
        else
            echo " [20] Check for Updates"
        fi
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  transfer_ps1_games ;;
            2)  transfer_ps2_games ;;
            3)  opl_management ;;
            4)  pops_management ;;
            5)  games_management ;;
            6)  downloads_menu ;;
            7)  ps2_online_menu ;;
            8)  hdd_osd_menu ;;
            9)  hdd_management_menu ;;
            11) echo "Goodbye!"; exit 0 ;;
            12) about_menu ;;
            13) scan_ps2_hdd ;;
            14) settings_menu ;;
            15) open "https://ko-fi.com/J3J6PIQ9O" ;;
            20) check_for_updates; update="" ;;
        esac
    done
}

# =============================================================================
# ABOUT
# =============================================================================
about_menu() {
    while true; do
        header
        cw
        echo ""
        echo " [=====| ABOUT ME |=====]"
        echo ""
        echo "I was inspired by the scripts of NeMesiS, Dekkit and Rs1n to make this script"
        echo ""
        echo "This batch script is intended to help and automate operations on the PS2 hard drive!"
        echo ""
        echo "Many thanks to the PS2 community for contributing the programs used to create these scripts!"
        echo ""
        echo "                                                           _______"
        echo "                                                          /      /|"
        echo " [1]  My Twitter                                         / PS2  / |"
        echo " [3]  My Youtube Channel                                /      /  |"
        echo " [4]  My Github                                        !------!   |"
        echo " [5]  Donate                                           !      !   |"
        echo " [6]  Special Thanks                                   !      ! = |"
        echo " [7]  Official PS2 Forum                               !      ! = |"
        echo " [8]  Official PS2 Discord                             !      ! = |"
        echo " [9]  PS2 Space Discord                                !      ! = |"
        echo ""
        echo " [10] Back to main menu"
        echo " [11] Exit"
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  open "https://twitter.com/GDX_SM" ;;
            3)  open "https://www.youtube.com/user/GDXTV/videos" ;;
            4)  open "https://github.com/GDX-X/PFS-BatchKit-Manager" ;;
            5)  open "https://ko-fi.com/J3J6PIQ9O" ;;
            6)  clear; [[ -f "$SCRIPT_DIR/Credits.txt" ]] && cat "$SCRIPT_DIR/Credits.txt"; press_enter ;;
            7)  open "https://www.psx-place.com/forums/#playstation-2-forums.6" ;;
            8)  open "https://discord.gg/PWGvKXjRgy" ;;
            9)  open "https://discord.gg/3yEp3ubcG2" ;;
            10) return ;;
            11) exit 0 ;;
        esac
    done
}

# =============================================================================
# SETTINGS MENU
# =============================================================================
settings_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Settings |=====]"
        echo ""
        echo " [1] Change database language - [$TitlesLang]"
        echo " [2] Download the latest database"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  ChangeDBLang="Yes"; UpdateDB=""; db_lang_settings; ChangeDBLang="" ;;
            2)  ChangeDBLang="Yes"; UpdateDB="Yes"; db_lang_settings; ChangeDBLang=""; UpdateDB="" ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# OPL MANAGEMENT
# =============================================================================
opl_management() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| OPL Management |=====]"
        echo ""
        echo " [1] Transfer OPL Resources"
        echo " [2] Extract OPL Resources"
        echo " [3] Create Cheat file with mastercode"
        echo " [4] Create Virtual Memory Card"
        echo " [5] Create shortcuts for your APPs or PS1 games in APPS tab"
        echo ""
        echo " [9] Change OPL Resources Partition"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  _require_hdd && transfer_opl_resources ;;
            2)  _require_hdd && backup_opl_resources ;;
            3)  bash "$BAT/make_cheat_mastercode.bat" 2>/dev/null \
                  || echo "[macOS] make_cheat_mastercode – see BAT/ folder" && press_enter ;;
            4)  _require_hdd && create_vmc ;;
            5)  _require_hdd && create_shortcuts_opl ;;
            9)  _require_hdd && change_opl_partition ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# POPS MANAGEMENT
# =============================================================================
pops_management() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| POPS Management |=====]"
        echo ""
        echo " [1] Transfer POPS Binaries"
        echo " [2] Transfer/Extract POPS VMC"
        echo " [3] Assign titles database for your .VCDs"
        [[ -f "$SCRIPT_DIR/POPS-Binaries/Hugopocked_POPStarter_Fixes.zip" ]] \
            && echo " [9] Apply HugoPocked's patches"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  _require_hdd && transfer_pops_binaries ;;
            2)  _require_hdd && transfer_backup_pops_vmc ;;
            3)  _require_hdd && rename_vcd_db ;;
            9)  [[ -f "$SCRIPT_DIR/POPS-Binaries/Hugopocked_POPStarter_Fixes.zip" ]] \
                    && _require_hdd && pops_hugo_patch ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# GAMES MANAGEMENT
# =============================================================================
games_management() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Games Management |=====]"
        echo ""
        echo " [1] Convert a game"
        echo " [2] Extract a game"
        echo " [3] Copy a game"
        echo " [4] Delete a game"
        echo " [5] Rename a game"
        echo " [6] Export game list"
        echo ""
        echo " [8] Dump your CD/DVD-ROM PS1 & PS2"
        echo " [9] Check MD5 Hash of your PS2 .ISO/.BIN with the redump database"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  conversion_menu ;;
            2)  _require_hdd && extract_game ;;
            3)  _require_hdd && copy_ps2_games_hdd ;;
            4)  _require_hdd && delete_game ;;
            5)  _require_hdd && rename_game ;;
            6)  _require_hdd && export_game_list ;;
            8)  dump_cd_dvd ;;
            9)  _require_hdd && check_md5_hash ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# CONVERSION MENU
# =============================================================================
conversion_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Conversion Menu |=====]"
        echo ""
        echo " [1] Convert .BIN to .VCD  (Only for PS1 Games) (Multi-Tracks Compatible)"
        echo " [2] Convert .VCD to .BIN  (Only for PS1 Games)"
        echo " [3] Convert .BIN to .ISO  (Only for PS2 Games)"
        echo " [4] Convert Multi-Tracks .BIN to Single .BIN"
        echo " [5] Compress/Decompress .ZSO  (Only for PS2 Games)"
        echo ""
        echo " [9] Restore Single .BIN to Multi-Tracks"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  Convert="BIN2VCD";    GameType="PS1"; convert_tools ;;
            2)  UnConvert="VCD2BIN";  GameType="PS1"; convert_tools ;;
            3)  Convert="BIN2ISO";    GameType="PS2"; convert_tools ;;
            4)  Convert="multibin2bin"; GameType="PS1"; convert_tools ;;
            5)  Convert="ISO2ZSO";    GameType="PS2"; UnConvert="yes"; convert_tools ;;
            9)  Convert="bin2split";  GameType="PS1"; split="-s"; convert_tools ;;
            10) return ;;
            11) return ;;  # Returns to games_management which returns to main
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# DOWNLOADS MENU
# =============================================================================
downloads_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Downloads Management |=====]"
        echo ""
        echo " [1] Applications"
        echo " [2] Artworks"
        echo " [3] Configs"
        echo " [4] Cheats"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  checkappsupdate="yes"; download_apps_menu ;;
            2)  _require_hdd && download_art ;;
            3)  _require_hdd && download_cfg ;;
            4)  download_cheats_menu ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

download_cheats_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Cheats Downloads Management |=====]"
        echo ""
        echo " [1] Rockstar Games Uncensored Cheats"
        echo " [2] Widescreen Cheats (4/3 to 16/9)"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  open "https://github.com/GDX-X/Rockstar-Games-Uncensored-PS2" ;;
            2)  open "https://github.com/PS2-Widescreen/OPL-Widescreen-Cheats" ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

download_apps_menu() {
    # Check for APPS database update
    if [[ -n "$checkappsupdate" ]]; then
        cd "$TMP" 2>/dev/null || true
        clear
        echo ""
        echo "Checking for APPS Database updates..."
        if _ping_host github.com; then
            curl -s "https://raw.githubusercontent.com/GDX-X/PFS-BatchKit-Manager/main/PFS-BatchKit-Manager/BAT/APPS.BAT" \
                -o "$TMP/APPS.BAT" 2>/dev/null
            [[ ! -s "$TMP/APPS.BAT" ]] && rm -f "$TMP/APPS.BAT"
            if [[ -f "$TMP/APPS.BAT" ]]; then
                local md5_new md5_cur
                md5_new=$(md5 -q "$TMP/APPS.BAT" 2>/dev/null || md5sum "$TMP/APPS.BAT" | cut -d' ' -f1)
                md5_cur=$(md5 -q "$BAT/APPS.BAT" 2>/dev/null  || md5sum "$BAT/APPS.BAT" 2>/dev/null | cut -d' ' -f1)
                if [[ "$md5_new" != "$md5_cur" ]]; then
                    echo "Updating..."
                    mv "$TMP/APPS.BAT" "$BAT/"
                    curl -s "https://raw.githubusercontent.com/GDX-X/PFS-BatchKit-Manager/main/PFS-BatchKit-Manager/BAT/APPS.zip" \
                        -o "$TMP/APPS.zip" 2>/dev/null
                    [[ -s "$TMP/APPS.zip" ]] && mv "$TMP/APPS.zip" "$BAT/"
                    curl -s "https://raw.githubusercontent.com/GDX-X/PFS-BatchKit-Manager/main/PFS-BatchKit-Manager/BAT/APPDB.xml" \
                        -o "$TMP/APPDB.xml" 2>/dev/null
                    [[ -s "$TMP/APPDB.xml" ]] && mv "$TMP/APPDB.xml" "$BAT/"
                fi
            fi
        else
            cr; echo "Unable to PING!"; cn
        fi
        checkappsupdate=""
    fi
    rm -rf "$TMP" && mkdir -p "$TMP"

    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Applications Downloads Management |=====]"
        echo ""
        echo " [1] Open PS2 Loader"
        echo " [2] wLaunchELF"
        echo " [3] Utilities"
        echo " [4] Emulators"
        echo " [5] MultiMedia"
        echo " [6] Hardware"
        echo ""
        echo " [9] Update APPS (Already installed as partition)"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        # Note: APPS.BAT is a Windows batch file; on macOS we show a note
        case "$choice" in
            1|2|3|4|5|6)
                cy; echo ""
                echo "[macOS] Application downloads are defined in BAT/APPS.BAT (Windows format)."
                echo "Please manually download the desired application and place it in APPS/ folder."
                cn; press_enter ;;
            9)  _require_hdd && update_part_apps ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# HDD-OSD MENU
# =============================================================================
hdd_osd_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| OSD/XMB Management |=====]"
        echo ""
        echo " [1] Install HDD-OSD (Browser 2.0)"
        echo " [2] Uninstall HDD-OSD"
        echo " [3] Partitions Management"
        echo " [4] FreeHDBoot Management"
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  _require_hdd && install_hdd_osd ;;
            2)  _require_hdd && uninstall_hdd_osd ;;
            3)  _require_hdd && hdd_osd_part_management ;;
            4)  _require_hdd && freehd_boot_management ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

hdd_osd_part_management() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| HDD-OSD/PSBBN/XMB Partitions Management |=====]"
        echo ""
        echo " [1] Transfer PS1 Games (Install as Partition)"
        echo " [2] Transfer Custom ELF APPS (Install as Partition)"
        echo " [3] Hide Partition (Hide partitions in HDD-OSD)"
        echo " [4] Unhide Partition (Show partitions in HDD-OSD)"
        echo " [5] Rename a title (Displayed in HDD-OSD, PSBBN, XMB Menu)"
        echo ""
        echo " [8] Extract/Inject Partition Resources Header"
        echo " [9] Update Partition Resources Header"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  transfer_ps1_games_hddosd ;;
            2)  transfer_apps_part ;;
            3)  pphide_unhide "hide"   "-hide"   ;;
            4)  pphide_unhide "unhide" "-unhide"  ;;
            5)  rename_title_hddosd ;;
            8)  custom_pp_header ;;
            9)  update_pp_header ;;
            10) return ;;
            11) main_menu; return ;;
            12) exit 0 ;;
        esac
    done
}

freehd_boot_management() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| FreeHDBoot Management |=====]"
        echo ""
        echo " [1] Fix Graphical Corruption OSD"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  freehd_boot_fix_osd_corruption ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# PS2 ONLINE MENU
# =============================================================================
ps2_online_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Networking OnlinePlay |=====]"
        echo ""
        echo " [1] Discord Retro-Online"
        echo " [2] Discord PS2 Online Gaming"
        echo " [3] Show PS2 Games Compatibles"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  open "https://discord.gg/kxXJjrZaSP" ;;
            2)  open "https://discord.gg/t2JY9awkwD" ;;
            3)  open "https://docs.google.com/spreadsheets/d/1bbxOGm4dPxZ4Vbzyu3XxBnZmuPx3Ue-cPqBeTxtnvkQ" ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# =============================================================================
# HDD MANAGEMENT MENU
# =============================================================================
hdd_management_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| HDD Management |=====]"
        echo ""
        echo " [1] Create a Partition"
        echo " [2] Delete a Partition"
        echo " [3] Blank a Partition"
        echo " [4] Show Partition Informations"
        echo " [5] Backup or Inject PS2 MBR Program"
        echo " [6] Explore PS2 HDD (Mount PFS partition)"
        echo " [7] NBD Server (Network access to PS2 HDD)"
        co; echo " [8] Hack your HDD To PS2 Format"
        cr; echo " [9] Format HDD To PS2 Format"
        cw
        echo ""
        echo " [10] Back"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  _require_hdd && create_del_part "Create" "mkpart" ;;
            2)  _require_hdd && create_del_part "Delete" "rmpart" ;;
            3)  _require_hdd && blank_partition ;;
            4)  _require_hdd && show_partition_infos ;;
            5)  _require_hdd && mbr_program ;;
            6)  ps2_hdd_explore ;;
            7)  nbd_server_menu ;;
            8)  hack_hdd_to_ps2 ;;
            9)  format_hdd_to_ps2 ;;
            10) return ;;
            12) exit 0 ;;
        esac
    done
}

# ---- Partition Infos Menu ----
show_partition_infos() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Partition Informations |=====]"
        echo ""
        echo " [1] Show PS1 Games Partitions Table"
        echo " [2] Show PS2 Games Partitions Table"
        echo " [3] Show APP Homebrew Partitions Table"
        echo " [4] Show PFS System Partitions Table"
        echo ""
        echo " [8] Show Total POPS Partitions Size"
        echo " [9] Show Total Partitions Size"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  ShowPartitionList="PS1 Games";   partition_info_list ;;
            2)  ShowPartitionList="PS2 Games";   partition_info_list ;;
            3)  ShowPartitionList="APP";          partition_info_list ;;
            4)  ShowPartitionList="System";       partition_info_list ;;
            8)  ShowPartitionList="Total POPS Size"; partition_info_list ;;
            9)  ShowPartitionList="Total Size";  partition_info_list ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

partition_info_list() {
    clear
    mkdir -p "$TMP"
    cw; echo ""; echo "[$ShowPartitionList]"; echo "---------------------------------------------------"; cn

    case "$ShowPartitionList" in
        "PS1 Games")
            grep "\.POPS\." "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null \
                | cut -c30-250 | sort
            ;;
        "PS2 Games")
            grep "0x1337" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null \
                | cut -c30-250 | sort
            ;;
        "APP")
            grep "PP.APPS-" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null \
                | cut -c30-250 | sort
            ;;
        "System")
            grep -v "0x1337" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null \
                | grep -v "\.POPS\." | grep -v "PP.APPS-" \
                | cut -c30-250 | sort
            ;;
        "Total POPS Size")
            local total=0
            while IFS= read -r line; do
                local mb
                mb=$(echo "$line" | awk '{print $1}' | grep -oE '^[0-9]+')
                [[ -n "$mb" ]] && (( total += mb )) || true
            done < <(grep "\.POPS\." "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null | cut -c1-29)
            cg; echo "Total POPS Size: $(_fmt_size $total)"; cn
            ;;
        "Total Size")
            local total=0
            grep "Total slice size:" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null | head -1
            ;;
    esac

    echo ""
    press_enter
}

# =============================================================================
# PS2 HDD EXPLORE (pfsfuse / macFUSE)
# =============================================================================
ps2_hdd_explore() {
    while true; do
        load_settings
        mkdir -p "$TMP"
        header
        cw
        echo ""
        echo " [=====| Explore PS2 HDD |=====]"
        echo ""
        echo " [1] Mount Partition from PS2 HDD"
        echo " [2] Mount Partition from IMAGE file"
        echo " [3] Unmount All Partitions"
        echo ""
        echo " [8] Check macFUSE / pfsfuse status"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        echo "------------------------------------------"
        cn
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  _require_hdd && mount_pfs_partition "$pfsshell_path" ;;
            2)  mount_pfs_partition_img ;;
            3)  unmount_all_pfs ;;
            8)  check_macfuse_status ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

mount_pfs_partition() {
    local device="$1"
    echo ""
    echo "Available partitions:"
    "$HDL_DUMP" toc "$hdl_path" 2>/dev/null | grep -v "^$" | head -40
    echo ""
    cw; read -r -p "Enter partition name to mount (e.g. __common, +OPL): " part_name; cn
    [[ -z "$part_name" ]] && return

    local mount_point="/Volumes/PS2_${part_name//[^A-Za-z0-9]/_}"
    mkdir -p "$mount_point"

    echo "Mounting $part_name → $mount_point"
    echo "This requires macFUSE to be installed."
    echo ""

    if [[ ! -f "$PFSFUSE_BIN" ]]; then
        cr; echo "pfsfuse not found at $PFSFUSE_BIN"; cn
        press_enter; return
    fi

    "$PFSFUSE" "--partition=$part_name" "$device" "$mount_point" \
        -o "volname=$part_name" &

    sleep 2
    if mount | grep -q "$mount_point"; then
        cg; echo "Mounted successfully: $mount_point"
        echo "Open in Finder:"; cn
        open "$mount_point"
    else
        cr; echo "Mount failed. Make sure macFUSE is installed (run install_deps.sh)"; cn
    fi
    press_enter
}

mount_pfs_partition_img() {
    echo ""
    cw; read -r -p "Enter path to PS2 image file (.img/.bin): " img_path; cn
    [[ -z "$img_path" || ! -f "$img_path" ]] && { cr; echo "File not found."; cn; press_enter; return; }
    cw; read -r -p "Enter partition name to mount (e.g. __common): " part_name; cn
    [[ -z "$part_name" ]] && return

    local mount_point="/Volumes/PS2_IMG_${part_name//[^A-Za-z0-9]/_}"
    mkdir -p "$mount_point"
    "$PFSFUSE" "--partition=$part_name" "$img_path" "$mount_point" \
        -o "volname=$part_name" &
    sleep 2
    mount | grep -q "$mount_point" \
        && { cg; echo "Mounted: $mount_point"; open "$mount_point"; cn; } \
        || { cr; echo "Mount failed."; cn; }
    press_enter
}

unmount_all_pfs() {
    echo ""
    echo "Unmounting all PS2 PFS volumes..."
    while IFS= read -r mp; do
        echo "  Unmounting: $mp"
        diskutil unmount "$mp" 2>/dev/null || umount "$mp" 2>/dev/null || true
    done < <(mount | grep "/Volumes/PS2_" | awk '{print $3}')
    cg; echo "Done."; cn
    press_enter
}

check_macfuse_status() {
    clear
    echo ""
    cw; echo "macFUSE / pfsfuse Status:"; cn
    echo "---------------------------------------------------"
    if [[ -f "$PFSFUSE" ]]; then
        cg; echo "  pfsfuse : $PFSFUSE"; cn
    else
        cr; echo "  pfsfuse : NOT FOUND ($PFSFUSE)"; cn
    fi
    if system_profiler SPExtensionsDataType 2>/dev/null | grep -qi "macfuse\|fuse"; then
        cg; echo "  macFUSE : Installed"; cn
    else
        cr; echo "  macFUSE : NOT detected (run install_deps.sh)"; cn
    fi
    echo ""
    press_enter
}

# =============================================================================
# NBD SERVER MENU  (macOS: uses nbd-client)
# =============================================================================
nbd_server_menu() {
    while true; do
        load_settings
        header
        cw
        echo ""
        echo " [=====| Network Block Device (NBD) |=====]"
        echo ""
        echo " [1] Mount PS2 HDD via NBD"
        echo " [2] Unmount PS2 HDD (NBD)"
        echo " [3] Show mounted NBD devices"
        echo ""
        echo " [10] Back"
        echo " [11] Back to main menu"
        echo " [12] Exit"
        echo ""
        co; echo "  NOTE: Start NBD Server on PS2 via OPL first"
        echo "  Compatible OPL: https://raw.githubusercontent.com/GDX-X/PFS-BatchKit-Manager"
        echo "                  /main/PFS-BatchKit-Manager/HDD-OSD/OPNPS2LD.ELF"
        cn
        echo "------------------------------------------"
        read -r -p "Select Option: " choice
        case "$choice" in
            1)  nbd_mount ;;
            2)  nbd_unmount ;;
            3)  nbd_list ;;
            10) return ;;
            11) return ;;
            12) exit 0 ;;
        esac
    done
}

nbd_mount() {
    echo ""
    cw; read -r -p "Enter your PS2 NBD server IP: " nbdip; cn
    [[ -z "$nbdip" ]] && return
    clear
    echo "Connecting to $nbdip..."
    echo ""

    # macOS: use nbd-client (brew install nbd)
    local nbd_dev="/dev/nbd0"
    if ! command -v nbd-client &>/dev/null; then
        cr; echo "nbd-client not found. Install with: brew install nbd"; cn
        press_enter; return
    fi

    nbd-client "$nbdip" 10809 "$nbd_dev" 2>&1
    if [[ $? -eq 0 ]]; then
        cg; echo "NBD device connected: $nbd_dev"
        echo "Scanning for PS2 HDD..."; cn
        hdl_path="$nbd_dev"
        pfsshell_path="$nbd_dev"
        ModelePS2HDD="NBD $nbdip"
        reload_hdd_cache
        press_enter
    else
        cr; echo "Failed to connect to $nbdip"; cn
        press_enter
    fi
}

nbd_unmount() {
    if ! command -v nbd-client &>/dev/null; then
        cr; echo "nbd-client not found."; cn; press_enter; return
    fi
    nbd-client -d "/dev/nbd0" 2>&1 && cg || cr
    echo "NBD device unmounted."; cn
    hdl_path=""
    press_enter
}

nbd_list() {
    clear
    echo ""
    echo "Active NBD connections:"
    ls /dev/nbd* 2>/dev/null || echo "  No NBD devices found"
    echo ""
    press_enter
}

# =============================================================================
# TRANSFER PS2 GAMES
# =============================================================================
transfer_ps2_games() {
    clear
    mkdir -p "$TMP"
    load_settings

    local transferHDLServ=""

    if [[ -z "$hdl_path" ]]; then
        cy; echo ""
        echo "Do you want to install your games over the network with hdl_svr?"
        echo "It is an alternative to NBD Server"
        echo "But some features will not be available like file transfer"
        cn; echo ""
        if ask_yn; then
            transferHDLServ="yes"
        else
            rm -rf "$TMP" && mkdir -p "$TMP"
            scan_ps2_hdd; return
        fi
    fi

    if [[ -z "$transferHDLServ" ]]; then
        cy; echo ""; echo ""; echo "Scanning for Playstation 2 HDDs:"
        echo "---------------------------------------------------"; cn
        if ! "$HDL_DUMP" toc "$hdl_path" >/dev/null 2>&1; then
            hdl_path=""
            scan_ps2_hdd; return
        fi
        cc; echo "       [$hdl_path $TotalHDD_Size_fmt - $ModelePS2HDD]"; cn

        cw; echo ""; echo ""; echo "Install PS2 Games:"
        echo "---------------------------------------------------"; cn
        cg; echo "         1) Yes"; cr; echo "         2) No"; cn; echo ""
        choice "12" "Select Option:"
        [[ $CHOICE_RESULT -eq 2 ]] && return
    else
        cp "$BAT/hdl_svr_093.elf" "$SCRIPT_DIR/" 2>/dev/null || true
        echo ""
        echo "1 - Launch hdl_svr_093.elf with wLaunchELF"
        echo "2 - Once launched, type IP address here"
        cw; read -r -p "Enter IP address of the Playstation 2: " hdl_path; cn
        if ! ping -c 1 -W 2 "$hdl_path" &>/dev/null; then
            cr; echo "Unable to ping $hdl_path"; cn
            press_enter; return
        fi
    fi

    # Choose game directory
    clear; echo ""
    cy; echo "Do you want to change the default directory?"
    echo "(Useful if your games are on another drive or path)"; cn; echo ""
    local HDDPATH=""
    if ask_yn; then
        echo "Example: /Volumes/Games/PS2"
        cw; read -r -p "Enter the path where your PS2 Games are located: " HDDPATH; cn
    fi

    local filepath_list=()
    if [[ -n "$HDDPATH" && -d "$HDDPATH" ]]; then
        while IFS= read -r f; do filepath_list+=("$f"); done \
            < <(find "$HDDPATH" -maxdepth 1 -type f \( -iname "*.iso" -o -iname "*.cue" \
                -o -iname "*.zso" -o -iname "*.7z" -o -iname "*.zip" -o -iname "*.rar" \) | sort)
    else
        HDDPATH="$SCRIPT_DIR"
        while IFS= read -r f; do filepath_list+=("$f"); done \
            < <(find "$SCRIPT_DIR/DVD" "$SCRIPT_DIR/CD" -maxdepth 1 -type f \
                \( -iname "*.iso" -o -iname "*.cue" -o -iname "*.zso" \
                   -o -iname "*.7z" -o -iname "*.zip" -o -iname "*.rar" \) 2>/dev/null | sort)
    fi

    # Title database
    local usedb="yes"
    echo ""; cy
    echo "Do you want to use the title database for your games? [Yes recommended]"; cn
    echo "If you choose NO the file names will be used as titles."
    if ask_yn; then usedb="yes"; else usedb="no"; fi

    local gameid_file="$TMP/gameid.txt"
    local gameid_osd_file="$TMP/gameid_HDD-OSD.txt"
    if [[ "$usedb" == "yes" ]]; then
        local db_file="$BAT/TitlesDB/TitlesDB_PS2_${TitlesLang}.txt"
        [[ ! -f "$db_file" ]] && db_file="$BAT/TitlesDB/TitlesDB_PS2_English.txt"
        iconv -f utf8 -t ascii//TRANSLIT//IGNORE "$db_file" > "$gameid_file" 2>/dev/null || cp "$db_file" "$gameid_file"
        cp "$db_file" "$gameid_osd_file" 2>/dev/null || true
    fi

    # Installation settings
    local InjectKELF="no" InfoGameConfig="Yes" ConvZSO="no" LZ4HC="" GameHide=""

    echo ""; cy; echo "Do you want to use recommended installation settings?"; cn
    echo "If you put no, you can customize the installation."
    if ask_yn; then
        InfoGameConfig="Yes"
    else
        echo "---------------------------------------------------"; echo ""
        cy; echo "Do you want to inject OPL-Launcher? (Optional)"; cn
        echo "Allows you to launch your game from HDD-OSD (Browser 2.0)"
        if ask_yn; then InjectKELF="yes"
            if [[ "$InjectKELF" == "yes" ]]; then
                cy; echo "Do you want to hide PS2 game partitions in HDD-OSD?"; cn
                ask_yn && GameHide="-hide"
            fi
        fi
        cy; echo "Do you want to add game information in CFG for OPL? (Optional)"; cn
        echo "Like: Title, Description, Developer"
        ask_yn && InfoGameConfig="Yes" || InfoGameConfig=""

        echo ""; cy; echo "Compress your games in .ZSO? (EXPERIMENTAL)"; cn
        co; echo "NOTE: Requires latest OPL development build"; cn
        ask_yn && ConvZSO="yes" || ConvZSO="no"

        if [[ "$ConvZSO" == "yes" ]]; then
            echo ""; echo "1. Normal Compression"; echo "2. Max Compression LZ4 HC"
            choice "12" "Select Option:"
            [[ $CHOICE_RESULT -eq 2 ]] && LZ4HC="--lz4hc"
        fi
    fi

    # Download Compatibility Database
    echo "Please wait..."
    local compat_db="$BAT/PS2-OPL-CFG-Compatibility-Database.7z"
    if _ping_host github.com; then
        curl -L --progress-bar \
            "https://github.com/GDX-X/PS2-OPL-CFG-Compatibility-Database/releases/download/Latest/PS2-OPL-CFG-Compatibility-Database.7z" \
            -o "$TMP/PS2-OPL-CFG-Compatibility-Database.7z" 2>/dev/null
        [[ -s "$TMP/PS2-OPL-CFG-Compatibility-Database.7z" ]] \
            && mv "$TMP/PS2-OPL-CFG-Compatibility-Database.7z" "$BAT/"
    fi

    echo "---------------------------------------------------"
    > "$TMP/cfg.id"
    local gamecount=0

    for fpath in "${filepath_list[@]}"; do
        (( gamecount++ ))
        local fname="${fpath%.*}"
        local filename="$(basename "$fpath")"
        local ext; ext=$(echo "${fpath##*.}" | tr '[:lower:]' '[:upper:]')
        local fdir="$(dirname "$fpath")"
        local disctype="unknown"
        local gameid="" title="" region="" dbtitle="" compressed="" DelExtracted=""
        local Game_Installed=""

        echo ""; echo ""
        echo "$gamecount - $filename"
        cd "$fdir" || continue

        # Extract archive
        case "$(tolower "$ext")" in
            zip|7z|rar)
                compressed="$(tolower "$ext")"
                local tmpext="$fdir/~TMP~_${gamecount}"
                mkdir -p "$tmpext"
                "$SEVENZIP" x -bso0 "$fpath" -o"$tmpext" >/dev/null 2>&1
                local inner
                inner=$(find "$tmpext" -maxdepth 2 -type f \( -iname "*.iso" -o -iname "*.cue" -o -iname "*.zso" \) | head -1)
                if [[ -n "$inner" ]]; then
                    mv "$tmpext/"* "$fdir/" 2>/dev/null || true
                    filename="$(basename "$inner")"
                    fname="${filename%.*}"
                    ext=$(echo "${filename##*.}" | tr '[:lower:]' '[:upper:]')
                    DelExtracted="yes"
                fi
                rm -rf "$tmpext"
                ;;
        esac

        # Convert BIN/CUE to ISO if needed for ZSO
        local multitrack=""
        local track_pattern="$fdir/${fname} (Track"
        if ls "$fdir/"*"Track"*".bin" &>/dev/null 2>/dev/null; then
            multitrack="Yes"
            # binmerge not available on macOS by default – skip multi-track merge
            cy; echo "  Multi-track BIN detected – merge not supported on macOS yet"; cn
        fi

        case "$(tolower "$ext")" in
            cue) ext="CUE" ;;
            iso) ext="ISO" ;;
            zso) ext="ZSO"
                if [[ -f "$fdir/$fname.zso" ]]; then
                    "$BAT/ziso" --cache-size 4 --replace $LZ4HC -i "$fname.zso" -o "$fname.iso" 2>/dev/null \
                        && ext="ISO" || true
                fi ;;
        esac

        # Get disc info
        if [[ -n "$ext" ]]; then
            "$HDL_DUMP" cdvd_info2 "$fname.$ext" > "$TMP/cdvd_info.txt" 2>/dev/null || true
            while IFS= read -r line; do
                [[ "$line" == *"CD"* ]]          && disctype="CD"
                [[ "$line" == *"DVD"* ]]          && disctype="DVD"
                [[ "$line" == *"dual-layer"* ]]   && disctype="DVD"
            done < "$TMP/cdvd_info.txt"
        fi

        # Get game ID
        gameid=$(grep -oE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}' "$TMP/cdvd_info.txt" 2>/dev/null | head -1)

        # Get title from DB
        if [[ "$usedb" == "yes" && -n "$gameid" && -f "$gameid_file" ]]; then
            dbtitle=$(grep "^$gameid" "$gameid_file" 2>/dev/null | cut -d' ' -f2- | head -1)
            dbtitle="${dbtitle%" "}"   # trim trailing space
        fi
        if [[ -n "$dbtitle" ]]; then title="$dbtitle"; else title="$fname"; fi

        # Detect region
        if [[ -n "$gameid" ]]; then
            local rc="${gameid:2:1}"
            case "$rc" in
                A) region="NTSC-A" ;; C) region="NTSC-C" ;; E) region="PAL"    ;;
                K) region="NTSC-K" ;; P) region="NTSC-J" ;; U) region="NTSC-U/C" ;;
                *) region="X"      ;;
            esac
        fi

        if [[ "$disctype" == "unknown" ]]; then
            cr; echo "  WARNING: Unable to determine disc type! File ignored."; cn
            echo "$(date) - \"$filename\"" >> "$SCRIPT_DIR/__Not_Installed_PS2.txt"
            continue
        fi

        # ZSO conversion
        if [[ "$ConvZSO" == "yes" && ! -f "$fdir/$fname.zso" ]]; then
            if [[ "$disctype" == "CD" ]]; then
                if [[ -f "$fname.bin" ]] && ! [[ -f "$fname.iso" ]]; then
                    "$BAT/bchunk" "$fname.bin" "$fname.cue" "$fname" >/dev/null 2>&1
                    mv "${fname}01.iso" "$fname.iso" 2>/dev/null || true
                fi
                [[ -f "$BAT/ziso" ]] && "$BAT/ziso" --cache-size 4 --replace $LZ4HC --hdl-fix \
                    -i "$fname.iso" -o "$fname.zso" 2>/dev/null || true
            else
                [[ -f "$BAT/ziso" ]] && "$BAT/ziso" --cache-size 4 --replace $LZ4HC --hdl-fix \
                    -i "$fname.iso" -o "$fname.zso" 2>/dev/null || true
            fi
        fi

        # File size
        local size
        if   [[ -f "$fname.zso" && "$ConvZSO" == "yes" ]]; then size=$(du -sh "$fname.zso" | cut -f1)
        elif [[ "$ext" == "ISO" ]]; then size=$(du -sh "$fname.iso" | cut -f1)
        elif [[ "$ext" == "CUE" ]]; then size=$(du -sh "$fname.bin" | cut -f1)
        else size="?"; fi

        echo "---------------------------------------------------"
        echo "Title:    [$title]"
        echo "Gameid:   [$gameid]"
        echo "Region:   [$region]"
        echo "DiscType: [$disctype]"
        echo "Format:   [$ext]"
        echo "Size:     [$size]"
        echo "---------------------------------------------------"

        # Adjust ext for ZSO install
        local install_ext="$ext"
        [[ -f "$fname.zso" && "$ConvZSO" == "yes" ]] && install_ext="ISO"

        # Install to HDD
        echo "           Installing..."
        cm
        local hdl_cmd="$HDL_DUMP"
        [[ "$ConvZSO" != "yes" ]] && hdl_cmd="$HDL_DUMP_STABLE"
        [[ ! -f "$HDL_DUMP_STABLE" ]] && hdl_cmd="$HDL_DUMP"

        if [[ -z "$Game_Installed" ]]; then
            "$hdl_cmd" "inject_$(tolower "$disctype")" "$hdl_path" "$title" "$fname.$install_ext" \
                "$gameid" "*u4" $GameHide 2>&1 || true
        else
            echo "$hdl_path partition with such name already exists: \"$title\""
        fi
        cn

        # Partition name for modify_header
        local gameid2="${gameid//_/-}"; gameid2="${gameid2/./}"
        local gpart_name
        gpart_name=$(echo "$title" | tr -dc 'A-Za-z0-9. ' | tr '[:lower:]' '[:upper:]' \
            | tr ' ' '_' | cut -c1-22)
        gpart_name="PP.${gameid2}..${gpart_name}"
        gpart_name="${gpart_name:0:32}"
        [[ -n "$GameHide" ]] && gpart_name="__.${gpart_name:3}"

        [[ "$InjectKELF" == "yes" ]] && cp "$BAT/boot.kelf" "$fdir/" 2>/dev/null || true
        "$HDL_DUMP" modify_header "$hdl_path" "$gpart_name" >/dev/null 2>&1 || true

        # Game info CFG
        rm -f "$SCRIPT_DIR/CFG/$gameid.cfg"
        if [[ "$InfoGameConfig" == "Yes" && -f "$BAT/PS2DB.xml" ]]; then
            "$SED" -n "/<game serial=\"$gameid2\">/{:a;N;/<\/game>/!ba;s/.*<game serial=\"$gameid2\">\(.*\)<\/game>.*/\1/p}" \
                "$BAT/PS2DB.xml" 2>/dev/null \
                | "$SED" -e 's/<\([^>]*\)>\([^<]*\)<\/\1>/\1=\2/g; s/<\([^>]*\) \/>/\1=/g; s/^[ \t]*//; s/[ \t]*$//; /^$/d' \
                > "$SCRIPT_DIR/CFG/$gameid.cfg" 2>/dev/null || true
        fi

        # Compatibility settings
        if [[ -f "$compat_db" ]]; then
            "$SEVENZIP" e -bso0 "$compat_db" -o"$TMP" "HDD/$gameid.cfg" -r -y >/dev/null 2>&1 || true
            [[ -f "$TMP/$gameid.cfg" ]] \
                && grep -iE "^[$]|Modes=" "$TMP/$gameid.cfg" >> "$SCRIPT_DIR/CFG/$gameid.cfg" 2>/dev/null || true
        fi

        # Fix title in CFG
        if [[ -f "$SCRIPT_DIR/CFG/$gameid.cfg" ]]; then
            local titlecfg
            titlecfg=$(echo "$title" | iconv -f utf-8 -t utf-8 2>/dev/null || echo "$title")
            "$SED" -i'' "s/Title=.*/Title=$titlecfg/" "$SCRIPT_DIR/CFG/$gameid.cfg" 2>/dev/null || true
            # Truncate Description to 254 chars
            "$SED" -i'' 's/Description=\(.\{1,254\}\).*/Description=\1/' "$SCRIPT_DIR/CFG/$gameid.cfg" 2>/dev/null || true
        fi

        echo "$gameid" >> "$TMP/cfg.id"
        # Cleanup
        [[ -n "$DelExtracted" ]] && rm -f "$fname.cue" "$fname.bin" "$fname.iso" "$fname.zso" 2>/dev/null || true
        rm -f "$fdir"/*.ico "$fdir"/*.sys "$fdir/boot.kelf" 2>/dev/null || true
        cn
        echo "---------------------------------------------------"
    done

    # Push CFG files to OPL partition via pfsshell
    if [[ -s "$TMP/cfg.id" ]]; then
        cd "$SCRIPT_DIR/CFG"
        local pfs_cfg_cmds="device $pfsshell_path
mount $OPLPART"
        [[ -n "$CUSTOM_OPLPART" ]] && pfs_cfg_cmds+="
mkdir OPL
cd OPL"
        pfs_cfg_cmds+="
mkdir CFG
cd CFG"
        while IFS= read -r gid; do
            pfs_cfg_cmds+="
rm $gid
put $gid"
        done < "$TMP/cfg.id"
        pfs_cfg_cmds+="
cd ..
rm games.bin
umount
exit"
        pfsshell_run "$pfs_cfg_cmds" >/dev/null 2>&1
    fi

    echo ""
    echo "Reloading HDD Cache..."
    reload_hdd_cache

    cw; echo ""; echo ""; echo "---------------------------------------------------"
    cg; echo "Completed..."; echo ""; cn
    rm -rf "$TMP" && mkdir -p "$TMP"
    press_enter
}

# =============================================================================
# TRANSFER PS1 GAMES (POPS)
# =============================================================================
transfer_ps1_games() {
    clear
    mkdir -p "$TMP"
    load_settings
    _require_hdd || return

    local HDDPATH="$SCRIPT_DIR/POPS"
    cy; echo ""; echo "Do you want to change the default directory?"; cn
    echo "(Useful if your games are on another drive or path)"
    if ask_yn; then
        cw; read -r -p "Enter path to PS1 games (.VCD files): " HDDPATH; cn
    fi

    [[ -z "$HDDPATH" || ! -d "$HDDPATH" ]] && HDDPATH="$SCRIPT_DIR/POPS"
    mkdir -p "$HDDPATH/Temp"

    # Use title DB
    local usedb="yes"
    cy; echo "Use title database for your games? [Yes recommended]"; cn
    ask_yn || usedb="no"
    local gameid_file="$TMP/gameid_ps1.txt"
    [[ "$usedb" == "yes" ]] && cp "$BAT/TitlesDB/TitlesDB_PS1_English.txt" "$gameid_file" 2>/dev/null || true

    # Check POPS.ELF
    local POPS_ELF=""
    for p in "$SCRIPT_DIR/POPS-Binaries/POPS.ELF" "$SCRIPT_DIR/POPS-Binaries/POPSTARTER.ELF"; do
        [[ -f "$p" ]] && POPS_ELF="$p" && break
    done
    if [[ -z "$POPS_ELF" ]]; then
        cr; echo "POPS.ELF / POPSTARTER.ELF not found in POPS-Binaries/!"
        echo "For copyright reasons these files cannot be provided."
        echo "Please obtain them manually and place in POPS-Binaries/"; cn
        press_enter; return
    fi

    # Generate pfsshell init for POPS partition
    local pops_partition="__.POPS"
    local pops_cmds_prefix="device $pfsshell_path
mount $pops_partition"

    local gamecount=0
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        (( gamecount++ ))
        local fname="$(basename "${fpath%.*}")"
        local ext; ext=$(echo "${fpath##*.}" | tr '[:lower:]' '[:upper:]')
        local fdir="$(dirname "$fpath")"
        local filename="$(basename "$fpath")"

        echo ""; echo "$gamecount - $filename"
        cd "$fdir" || continue

        # Get game ID from filename (XXXX_NNN.NN format)
        local gameid
        gameid=$(echo "$fname" | grep -oE '[A-Z]{4}[_-][0-9]{3}\.[0-9]{2}' | head -1 \
                 || echo "$fname" | grep -oE '[A-Z]{3}[0-9]{5}\.[0-9]{3}' | head -1)
        gameid="${gameid//-/_}"

        # Lookup title in DB
        local title="$fname"
        if [[ "$usedb" == "yes" && -n "$gameid" && -f "$gameid_file" ]]; then
            local dbtitle
            dbtitle=$(grep "^$gameid" "$gameid_file" 2>/dev/null | cut -d' ' -f2- | head -1)
            [[ -n "$dbtitle" ]] && title="${dbtitle%" "}"
        fi

        # Prefix for POPS (gameid is used as partition identifier)
        local pops_id="${gameid//./_}"
        local pops_id_short="${pops_id:0:11}"

        # Check if already installed
        local already_installed=""
        grep -qF "$pops_id_short" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null && already_installed="yes"

        if [[ -n "$already_installed" ]]; then
            cy; echo "  A game with this name is already installed"; cn
            continue
        fi

        echo "           Installing..."

        # Prepare temp files
        cp "$POPS_ELF" "$HDDPATH/Temp/${fname}.ELF" 2>/dev/null || true

        # title.cfg
        {
            echo "title=$title" | "$SED" -E 's/[A-Z]{4}[_-][0-9]{3}\.[0-9]{2}\.//g'
            echo "boot=${fname}.ELF"
        } > "$HDDPATH/Temp/title.cfg"

        # Add PS1DB game info if available
        if [[ -f "$BAT/PS1DB.xml" && -n "$gameid" ]]; then
            local ps1id1="${gameid:0:4}-${gameid:5:3}${gameid:9:2}"
            "$SED" -n "/<game serial=\"$ps1id1\">/{:a;N;/<\/game>/!ba;s/.*<game serial=\"$ps1id1\">\(.*\)<\/game>.*/\1/p}" \
                "$BAT/PS1DB.xml" 2>/dev/null \
                | "$SED" 's/<\([^>]*\)>\([^<]*\)<\/\1>/\1=\2/g; s/<\([^>]*\) \/>/\1=/g; /^$/d' \
                >> "$HDDPATH/Temp/title.cfg" 2>/dev/null || true
        fi

        # Build pfsshell commands for this game
        local pfs_cmds="$pops_cmds_prefix
lcd $HDDPATH/Temp
mkdir $pops_id_short
cd $pops_id_short
put title.cfg
put ${fname}.ELF"

        if [[ "$ext" == "VCD" ]]; then
            # Install VCD to __.POPS partition
            pfs_cmds+="
umount
device $pfsshell_path
mount $pops_partition
lcd $HDDPATH
put ${fname}.VCD
umount"
        fi
        pfs_cmds+="
exit"

        pfsshell_run "$pfs_cmds" > "$LOG/PFS-POPS-${gamecount}.log" 2>&1 || true
        cp "$HDDPATH/Temp/"*.VCD "$HDDPATH/" 2>/dev/null || true
        rm -rf "$HDDPATH/Temp"

        echo "           Completed..."
        echo "---------------------------------------------------"
    done < <(find "$HDDPATH" -maxdepth 1 -type f -iname "*.vcd" | sort)

    cd "$SCRIPT_DIR"
    rm -rf "$TMP" && mkdir -p "$TMP"
    rm -rf "$HDDPATH/Temp"

    cw; echo ""; echo ""; echo "---------------------------------------------------"
    cg; echo "Completed..."; echo ""; cn
    press_enter
}

# =============================================================================
# TRANSFER OPL RESOURCES (APPS/ART/CFG/CHT/LNG/THM/VMC)
# =============================================================================
transfer_opl_resources() {
    clear; mkdir -p "$TMP"; load_settings

    local pfs_apps="" pfs_art="" pfs_cfg="" pfs_cht="" pfs_lng="" pfs_thm="" pfs_vmc=""
    local choices_log="$TMP/pfs-choice.log"; > "$choices_log"

    for item in "Transfer Applications:APPS:pfs_apps" \
                "Transfer Artworks:ART:pfs_art" \
                "Transfer Configs:CFG:pfs_cfg" \
                "Transfer Cheats:CHT:pfs_cht" \
                "Transfer Languages:LNG:pfs_lng" \
                "Transfer Themes:THM:pfs_thm" \
                "Transfer Virtual Memory Cards:VMC:pfs_vmc"; do
        IFS=':' read -r label folder var <<< "$item"
        echo ""; cw; echo "$label: [$folder]"
        echo "---------------------------------------------------"; cn
        cg; echo "         1) Yes"; cr; echo "         2) No"; cn; echo ""
        choice "123" "Select Option:"
        if [[ $CHOICE_RESULT -eq 1 ]]; then
            eval "$var=yes"
            echo "$folder" >> "$choices_log"
        fi
    done

    # Check OPL partition exists
    echo ""
    cy; echo "Detecting OPL Resources Partition:"; cn
    echo "---------------------------------------------------"
    if ! grep -qw "$OPLPART" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null; then
        cr; echo "  $OPLPART - Partition NOT Detected"
        echo "  Partition Must Be Created"; cn
        rm -rf "$TMP"; press_enter; opl_management; return
    fi
    cg; echo "  $OPLPART - Partition Detected"; cn

    press_enter; clear

    # Transfer each selected category
    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue
        local src="$SCRIPT_DIR/$folder"
        [[ ! -d "$src" ]] && { echo "  $folder - Source Not Detected..."; continue; }
        [[ -z "$(ls -A "$src" 2>/dev/null)" ]] && { echo "  $folder - Source Empty..."; continue; }

        echo ""; echo "Installing $folder..."
        echo "---------------------------------------------------"

        # Build recursive pfsshell put script using find
        local pfs_script="$TMP/pfs-${folder}.txt"
        {
            echo "device $pfsshell_path"
            echo "mount $OPLPART"
            [[ -n "$CUSTOM_OPLPART" ]] && echo "mkdir OPL" && echo "cd OPL"
            echo "mkdir $folder"
            echo "cd $folder"
        } > "$pfs_script"

        # Use find to enumerate files and build pfsshell commands
        _build_pfs_put_tree "$src" "$src" >> "$pfs_script"

        {
            echo "ls -l"
            echo "umount"
            echo "exit"
        } >> "$pfs_script"

        cat "$pfs_script" | "$PFSSHELL" 2>&1 \
            | grep -i "drwx" | "$SED" '1,2d' > "$LOG/PFS-${folder}.log"
        echo "  $folder Completed..."
    done < "$choices_log"

    rm -rf "$TMP"; mkdir -p "$TMP"
    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "Completed..."; echo ""; cn
    press_enter
}

# Helper: builds pfsshell lcd/cd/put/lcd../cd.. commands for a directory tree
_build_pfs_put_tree() {
    local base_dir="$1"
    local current_dir="$2"

    # Files in current dir
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        local rel="${f#$current_dir/}"
        [[ "$rel" == */* ]] && continue  # subdirectory file, handled recursively
        echo "put \"$rel\""
    done < <(find "$current_dir" -maxdepth 1 -type f | sort)

    # Subdirectories
    while IFS= read -r subdir; do
        [[ -d "$subdir" ]] || continue
        local dirname="$(basename "$subdir")"
        echo "mkdir \"$dirname\""
        echo "lcd \"$dirname\""
        echo "cd \"$dirname\""
        _build_pfs_put_tree "$base_dir" "$subdir"
        echo "lcd .."
        echo "cd .."
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d | sort)
}

# =============================================================================
# BACKUP / EXTRACT OPL RESOURCES
# =============================================================================
backup_opl_resources() {
    clear; mkdir -p "$TMP"; load_settings

    local choices_log="$TMP/pfs-choice.log"; > "$choices_log"

    for item in "Extract Artwork:ART" "Extract Configs:CFG" \
                "Extract Cheats:CHT" "Extract Virtual Memory Cards:VMC"; do
        IFS=':' read -r label folder <<< "$item"
        echo ""; cw; echo "$label: [$folder]"
        echo "---------------------------------------------------"; cn
        cg; echo "         1) Yes"; cr; echo "         2) No"; cn; echo ""
        choice "12" "Select Option:"
        [[ $CHOICE_RESULT -eq 1 ]] && echo "$folder" >> "$choices_log"
    done

    # Check OPL partition
    if ! grep -qw "$OPLPART" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null; then
        cr; echo "  $OPLPART - Partition NOT Detected"; cn
        rm -rf "$TMP"; press_enter; return
    fi
    press_enter; clear

    while IFS= read -r folder; do
        [[ -z "$folder" ]] && continue
        mkdir -p "$SCRIPT_DIR/$folder"
        echo ""; echo "Extracting $folder..."
        echo "---------------------------------------------------"

        # List files in partition
        local pfs_list="$TMP/pfs-list.txt"
        {
            echo "device $pfsshell_path"
            echo "mount $OPLPART"
            [[ -n "$CUSTOM_OPLPART" ]] && echo "cd OPL"
            echo "cd $folder"
            echo "ls"
            echo "umount"
            echo "exit"
        } | "$PFSSHELL" 2>/dev/null \
            | grep -iE '\.(png|jpg|cfg|cht|bin)$' \
            | "$SED" 's/.*/"\0"/' > "$TMP/pfs-tmp.log"

        # Extract files
        {
            echo "device $pfsshell_path"
            echo "mount $OPLPART"
            [[ -n "$CUSTOM_OPLPART" ]] && echo "cd OPL"
            echo "cd $folder"
            echo "lcd $SCRIPT_DIR/$folder"
            "$SED" 's/^/get /' "$TMP/pfs-tmp.log"
            echo "umount"
            echo "exit"
        } | "$PFSSHELL" >/dev/null 2>&1
        echo "  $folder Completed..."
    done < "$choices_log"

    rm -rf "$TMP"; mkdir -p "$TMP"
    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "Extraction Completed..."; echo ""; cn
    press_enter
}

# =============================================================================
# CREATE / DELETE PARTITION
# =============================================================================
create_del_part() {
    local Part_Option="$1"  # "Create" or "Delete"
    local PFS_Option="$2"   # "mkpart" or "rmpart"
    clear; mkdir -p "$TMP"; load_settings

    echo ""; cw; echo "$Part_Option Partition:"
    echo "---------------------------------------------------"; cn

    cw; read -r -p "Enter partition name: " part_name; cn
    [[ -z "$part_name" ]] && return

    if [[ "$Part_Option" == "Create" ]]; then
        echo ""; echo "Partition size examples: 128M, 256M, 512M, 1G, 4G"
        cw; read -r -p "Enter partition size: " part_size; cn
        [[ -z "$part_size" ]] && return
    fi

    echo ""
    if [[ "$Part_Option" == "Create" ]]; then
        cy; echo "Creating partition: $part_name ($part_size)"; cn
        {
            echo "device $pfsshell_path"
            echo "mkpart $part_name $part_size"
            echo "exit"
        } | "$PFSSHELL" 2>&1
    else
        cr; echo "Deleting partition: $part_name"
        ask_yn "Are you sure you want to delete '$part_name'? [Y/N]" || return
        echo "Deleting..."; cn
        {
            echo "device $pfsshell_path"
            echo "rmpart $part_name"
            echo "exit"
        } | "$PFSSHELL" 2>&1
    fi

    echo ""
    echo "Reloading HDD Cache..."
    reload_hdd_cache
    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "$Part_Option Completed..."; echo ""; cn
    press_enter
}

# =============================================================================
# FORMAT HDD TO PS2 FORMAT
# =============================================================================
format_hdd_to_ps2() {
    clear; mkdir -p "$TMP"

    cy; echo ""; echo "Scanning disks:"; echo "---------------------------------------------------"; cn
    echo ""
    diskutil list 2>/dev/null | grep -v "PHYSICALDRIVE0\|disk0" | grep -v "^/dev/disk0"
    echo ""
    cr; echo "WARNING: MAKE SURE YOU CHOOSE THE RIGHT HARD DRIVE"
    echo "Disclaimer: I cannot be held responsible for improper use."
    cr; echo ""

    echo "Available disks (DO NOT select disk0 – your system disk):"
    diskutil list 2>/dev/null | grep "^/dev/disk" | grep -v "^/dev/disk0"
    echo ""
    echo "Enter disk number (e.g. for /dev/disk2, type: 2)"
    echo "Or type 'q' to go back"
    echo ""
    cw; read -r -p "Select disk: " disk_num; cn
    [[ -z "$disk_num" || "$disk_num" == "q" ]] && return

    local target_disk="/dev/disk${disk_num}"
    local target_rdisk="/dev/rdisk${disk_num}"

    if [[ "$disk_num" == "0" ]]; then
        cr; echo "Refusing to format disk0 (system disk)!"; cn; press_enter; return
    fi

    echo ""
    diskutil info "$target_disk" 2>/dev/null | grep -E "Device|Media Name|Size" | head -5
    echo ""
    cr; echo "Are you SURE you want to FORMAT $target_disk to PS2 format?"
    echo "This is IRREVERSIBLE!"; cn
    ask_yn || return
    ask_yn "FINAL CONFIRMATION: Format $target_disk? [Y/N]" || return

    if [[ "$PSX2DESR_HDD" == "Yes" ]]; then
        cr; echo "PSX DESR HDD Detected – you should not format your PSX HDD!"
        echo "ABORTED OPERATION"; cn; press_enter; return
    fi

    echo ""; echo "Formatting HDD to PS2 format..."
    # Unmount all partitions
    diskutil unmountDisk "$target_disk" 2>/dev/null || true

    {
        echo "device $target_rdisk"
        echo "initialize yes"
        echo "exit"
    } | "$PFSSHELL" 2>&1

    # Re-mount disk to make it visible
    diskutil mountDisk "$target_disk" 2>/dev/null || true

    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "Formatting Completed..."; echo ""; cn
    press_enter
}

# =============================================================================
# HACK HDD TO PS2 FORMAT (MBR injection)
# =============================================================================
hack_hdd_to_ps2() {
    clear; mkdir -p "$TMP"

    if [[ ! -f "$BAT/mbr.img" ]]; then
        cr; echo "mbr.img not found in BAT/"; cn; press_enter; return
    fi

    cy; echo ""; echo "Scanning disks:"; echo "---------------------------------------------------"; cn
    diskutil list 2>/dev/null | grep "^/dev/disk" | grep -v "^/dev/disk0"
    echo ""
    cr; echo "WARNING: MAKE SURE YOU CHOOSE THE RIGHT HARD DRIVE"; cn
    echo "Enter disk number (e.g. 2 for /dev/disk2) or 'q' to cancel:"
    cw; read -r -p "Select disk: " disk_num; cn
    [[ -z "$disk_num" || "$disk_num" == "q" ]] && return
    [[ "$disk_num" == "0" ]] && { cr; echo "Refusing to hack disk0!"; cn; press_enter; return; }

    local target_rdisk="/dev/rdisk${disk_num}"

    echo ""
    cr; echo "ARE YOU SURE you want to HACK $target_rdisk?"
    echo "This writes an MBR and is intended only as a PS2 boot entry point."; cn
    ask_yn || return
    ask_yn "FINAL CONFIRMATION [Y/N]" || return

    if [[ "$PSX2DESR_HDD" == "Yes" ]]; then
        cr; echo "PSX DESR HDD Detected – you should not modify the MBR of your PSX HDD!"
        echo "ABORTED OPERATION"; cn; press_enter; return
    fi

    diskutil unmountDisk "/dev/disk${disk_num}" 2>/dev/null || true
    echo ""; echo "Writing MBR..."
    dd if="$BAT/mbr.img" of="$target_rdisk" bs=512 count=1 2>&1
    diskutil mountDisk "/dev/disk${disk_num}" 2>/dev/null || true

    # Extract !COPY_TO_USB_ROOT if available
    if [[ -f "$BAT/!COPY_TO_USB_ROOT.7z" ]]; then
        rm -rf "$SCRIPT_DIR/!COPY_TO_USB_ROOT"
        "$SEVENZIP" x -bso0 "$BAT/!COPY_TO_USB_ROOT.7z" -o"$SCRIPT_DIR/!COPY_TO_USB_ROOT" >/dev/null 2>&1
    fi

    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "MBR Hack Completed..."; echo ""
    echo "Next steps:"
    echo "1. Put your HDD in your PS2 and format with wLaunchELF"
    echo "   FileBrowser > MISC > HDDManager > R1 > Format"
    echo "2. Copy !COPY_TO_USB_ROOT contents to USB drive root (FAT32)"
    echo "3. Install FreeHDBoot from USB via wLaunchELF"; cn
    press_enter
}

# =============================================================================
# MBR PROGRAM (backup/inject)
# =============================================================================
mbr_program() {
    clear; mkdir -p "$TMP"; load_settings

    echo ""; cw; echo "Backup or Inject MBR Program:"; echo "---------------------------------------------------"; cn
    cg; echo "         1) Backup MBR"; cr; echo "         2) Cancel"; cy; echo "         3) Inject MBR"; cn; echo ""
    choice "123" "Select Option:"
    case $CHOICE_RESULT in
        1) "$HDL_DUMP" dump_mbr "$hdl_path" "$SCRIPT_DIR/__MBR.KELF" 2>&1
           [[ -f "$SCRIPT_DIR/__MBR.KELF" ]] \
               && { cg; echo "> $SCRIPT_DIR/__MBR.KELF"; cn; } \
               || { cr; echo "__MBR.KELF not created"; cn; }
           ;;
        2) return ;;
        3) [[ ! -f "$SCRIPT_DIR/__MBR.KELF" ]] \
               && { cr; echo "__MBR.KELF not found!"; cn; press_enter; return; }
           "$HDL_DUMP" inject_mbr "$hdl_path" "$SCRIPT_DIR/__MBR.KELF" 2>&1
           reload_hdd_cache
           ;;
    esac
    press_enter
}

# =============================================================================
# BLANK PARTITION
# =============================================================================
blank_partition() {
    clear; load_settings
    echo ""; cw; echo "Blank a Partition (fills with zeros):"; cn; echo ""
    "$HDL_DUMP" toc "$hdl_path" 2>/dev/null | head -50
    echo ""
    cw; read -r -p "Enter partition name to blank: " part_name; cn
    [[ -z "$part_name" ]] && return
    cr; echo "Are you sure you want to blank '$part_name'? This is irreversible!"; cn
    ask_yn || return
    {
        echo "device $pfsshell_path"
        echo "mount $part_name"
        echo "rmdir ."
        echo "umount"
        echo "exit"
    } | "$PFSSHELL" 2>&1
    reload_hdd_cache
    cg; echo "Done."; cn; press_enter
}

# =============================================================================
# COPY PS2 GAMES HDD → HDD
# =============================================================================
copy_ps2_games_hdd() {
    clear; mkdir -p "$TMP"; load_settings

    local hdlhdd="$hdl_path"
    cy; echo ""; echo "Scanning for second PS2 HDD:"; cn
    _list_ps2_hdds | grep -v "$hdlhdd"
    echo ""
    echo "Enter disk number of DESTINATION HDD (e.g. 2 for /dev/disk2, or 'q' to cancel):"
    cw; read -r -p "Destination disk number: " dst_num; cn
    [[ -z "$dst_num" || "$dst_num" == "q" ]] && return

    local hdlhdd2="/dev/disk${dst_num}"
    if [[ "$hdlhdd2" == "$hdlhdd" ]]; then
        co; echo "You cannot use the same HDD as destination!"; cn; press_enter; return
    fi

    if ! "$HDL_DUMP" toc "$hdlhdd2" >/dev/null 2>&1; then
        cr; echo "Destination disk is not a PS2 HDD or not accessible."; cn
        press_enter; return
    fi

    echo ""
    cy; echo "HDD 1 (Source):"; cn
    diskutil info "$hdlhdd"  2>/dev/null | grep -E "Device:|Media Name:|Disk Size:" | head -3
    echo ""
    cy; echo "HDD 2 (Destination):"; cn
    diskutil info "$hdlhdd2" 2>/dev/null | grep -E "Device:|Media Name:|Disk Size:" | head -3
    echo ""

    ask_yn "Confirm? [Y/N]" || return

    # Build game list from source
    echo ""; echo "Scanning game list..."
    local gamelist_file="$TMP/GamelistPS2HDD1.txt"
    "$HDL_DUMP" hdl_toc "$hdlhdd" 2>/dev/null \
        | "$SED" 's/.\{46\}//' \
        | "$SED" '1d; $d' \
        | cut -c35-500 \
        | sort -k2 > "$gamelist_file"

    echo ""; cat "$gamelist_file"
    echo ""
    echo "---------------------------------------------------"
    echo "1. Proceed to copy"
    echo "2. Back"
    echo ""
    choice "12" "Select Option:"
    [[ $CHOICE_RESULT -eq 2 ]] && return

    echo ""; ask_yn "Install in alphabetical order? [Y/N]" \
        && sort -k2 "$gamelist_file" > "$TMP/GameSelectedList.txt" \
        || cp "$gamelist_file" "$TMP/GameSelectedList.txt"

    while IFS= read -r game_entry; do
        local game_id; game_id=$(echo "$game_entry" | awk '{print $1}')
        echo ""
        echo "Copying: $game_entry"
        "$HDL_DUMP_STABLE" copy_hdd "$hdlhdd" "$hdlhdd2" "$game_id" 2>&1 || \
        "$HDL_DUMP" copy_hdd "$hdlhdd" "$hdlhdd2" "$game_id" 2>&1 || true
    done < "$TMP/GameSelectedList.txt"

    cd "$SCRIPT_DIR"
    rm -rf "$TMP"; mkdir -p "$TMP"
    cw; echo ""; echo "---------------------------------------------------"
    cg; echo "Copy Completed..."; echo ""; cn
    press_enter
}

# =============================================================================
# CONVERT TOOLS
# =============================================================================
convert_tools() {
    clear; mkdir -p "$TMP"
    local src_dir=""
    [[ "$GameType" == "PS1" ]] && src_dir="$SCRIPT_DIR/POPS" || src_dir="$SCRIPT_DIR/DVD"

    cy; echo "Do you want to change the source directory?"; cn
    ask_yn && { cw; read -r -p "Enter path: " src_dir; cn; }
    [[ ! -d "$src_dir" ]] && { cr; echo "Directory not found."; cn; press_enter; Convert="" UnConvert="" split=""; return; }

    echo ""; echo "Converting files in: $src_dir"
    echo "Convert mode: $Convert${UnConvert:+/$UnConvert}"
    echo "---------------------------------------------------"

    case "$Convert$UnConvert" in
        "BIN2VCD")
            while IFS= read -r cue_file; do
                local base="${cue_file%.*}"
                echo "Converting: $(basename $cue_file)"
                [[ -f "$BAT/CUE2POPS" ]] \
                    && "$BAT/CUE2POPS" "$cue_file" "$base.VCD" 2>&1 \
                    || { cy; echo "  [macOS] CUE2POPS not available. Skipping $cue_file"; cn; }
            done < <(find "$src_dir" -maxdepth 1 -iname "*.cue" | sort)
            ;;
        "VCD2BIN")
            while IFS= read -r vcd_file; do
                local base="${vcd_file%.*}"
                echo "Converting: $(basename $vcd_file)"
                [[ -f "$BAT/bchunk" ]] \
                    && "$BAT/bchunk" "$vcd_file" "${base}.cue" "$base" 2>&1 \
                    || bchunk "$vcd_file" "${base}.cue" "$base" 2>&1 || \
                    { cy; echo "  [macOS] bchunk not found (brew install bchunk)"; cn; }
            done < <(find "$src_dir" -maxdepth 1 -iname "*.vcd" | sort)
            ;;
        "BIN2ISO")
            while IFS= read -r cue_file; do
                local base="${cue_file%.*}"
                echo "Converting: $(basename $cue_file)"
                bchunk "$base.bin" "$cue_file" "$base" 2>&1 \
                    && mv "${base}01.iso" "$base.iso" 2>/dev/null || true
            done < <(find "$src_dir" -maxdepth 1 -iname "*.cue" | sort)
            ;;
        "ISO2ZSOyes")
            while IFS= read -r iso_file; do
                local base="${iso_file%.*}"
                echo "Compressing: $(basename $iso_file)"
                [[ -f "$BAT/ziso" ]] \
                    && "$BAT/ziso" --cache-size 4 --replace $LZ4HC -i "$iso_file" -o "$base.zso" 2>&1 \
                    || { cy; echo "  [macOS] ziso not found in BAT/"; cn; }
                [[ -f "$BAT/ziso" && "$UnConvert" == "yes" ]] \
                    && [[ -f "$base.zso" ]] && rm -f "$iso_file" || true
            done < <(find "$src_dir" -maxdepth 1 \( -iname "*.iso" -o -iname "*.zso" \) | sort)
            ;;
    esac

    Convert="" UnConvert="" split=""
    cg; echo ""; echo "Conversion complete."; cn
    press_enter
}

# =============================================================================
# DELETE GAME
# =============================================================================
delete_game() {
    clear; load_settings
    echo ""; cw; echo "Delete a PS2 Game:"; cn
    echo "---------------------------------------------------"
    # Show partition names (format: PP.SLUS-12345..TITLE)
    "$HDL_DUMP" toc "$hdl_path" 2>/dev/null | grep "0x1337" | cut -c30-250 | head -50
    echo ""
    cy; echo "Enter the PARTITION NAME as shown above (e.g. PP.SLUS-12345..TITLE)"
    echo "Or the game ID prefix (e.g. SLUS-12345)"; cn
    cw; read -r -p "Enter partition name: " del_part; cn
    [[ -z "$del_part" ]] && return

    cr; echo "Are you sure you want to delete '$del_part'?"; cn
    ask_yn || return
    # hdl_dump has no "del" on macOS — use pfsshell rmpart
    printf "device %s\nrmpart \"%s\"\nexit\n" "$pfsshell_path" "$del_part" \
        | "$PFSSHELL" 2>&1
    reload_hdd_cache
    cg; echo "Game deleted."; cn
    press_enter
}

# =============================================================================
# RENAME GAME
# =============================================================================
rename_game() {
    clear; load_settings
    echo ""; cw; echo "Rename a PS2 Game:"; cn
    echo "---------------------------------------------------"
    "$HDL_DUMP" hdl_toc "$hdl_path" 2>/dev/null | head -50
    echo ""
    cw; read -r -p "Enter game ID to rename (e.g. SLUS_123.45): " ren_gameid; cn
    [[ -z "$ren_gameid" ]] && return
    cw; read -r -p "Enter new title: " new_title; cn
    [[ -z "$new_title" ]] && return

    # macOS hdl_dump uses "modify" instead of "rename"
    "$HDL_DUMP" modify "$hdl_path" "$ren_gameid" "$new_title" 2>&1
    reload_hdd_cache
    cg; echo "Game renamed."; cn
    press_enter
}

# =============================================================================
# EXTRACT GAME
# =============================================================================
extract_game() {
    clear; load_settings; mkdir -p "$TMP"
    echo ""; cw; echo "Extract a PS2 Game:"; cn
    echo "---------------------------------------------------"
    cat "$CACHE/PARTITION_HDL_GAME.txt" 2>/dev/null | head -50
    echo ""
    cw; read -r -p "Enter game ID to extract: " ext_gameid; cn
    [[ -z "$ext_gameid" ]] && return

    local dest="$SCRIPT_DIR/DVD"
    cy; echo "Extract to DVD folder? [Y] or enter custom path [N]"; cn
    ask_yn || { cw; read -r -p "Enter destination path: " dest; cn; }
    mkdir -p "$dest"

    echo "Extracting $ext_gameid → $dest"
    "$HDL_DUMP" extract "$hdl_path" "$ext_gameid" "$dest/" 2>&1
    cg; echo ""; echo "Extraction complete."; cn
    press_enter
}

# =============================================================================
# EXPORT GAME LIST
# =============================================================================
export_game_list() {
    local out="$SCRIPT_DIR/GamesList_Export.txt"
    cat "$CACHE/PS2_GAMES_HDD.txt" 2>/dev/null > "$out"
    cg; echo ""; echo "Game list exported to: $out"; cn
    open "$SCRIPT_DIR"
    press_enter
}

# =============================================================================
# CHECK MD5 HASH
# =============================================================================
check_md5_hash() {
    clear; load_settings
    echo ""; cw; echo "Check MD5 Hash (Redump):"; cn; echo ""
    cw; read -r -p "Drag & drop your .ISO or .BIN file here: " iso_file; cn
    iso_file="${iso_file//\'/}"   # remove quotes if dragged
    [[ ! -f "$iso_file" ]] && { cr; echo "File not found."; cn; press_enter; return; }

    echo "Computing MD5..."
    local md5
    md5=$(md5 -q "$iso_file" 2>/dev/null || md5sum "$iso_file" | cut -d' ' -f1)
    cg; echo "MD5: $md5"; cn
    echo ""
    echo "Compare at: https://redump.org/discs/quicksearch/$md5"
    open "https://redump.org/discs/quicksearch/$md5"
    press_enter
}

# =============================================================================
# DUMP CD/DVD
# =============================================================================
dump_cd_dvd() {
    clear
    cy; echo "Dump CD/DVD-ROM:"; cn; echo ""
    echo "DiscImageCreator is not available on macOS."
    echo "Alternative tools for macOS:"
    echo "  - cdrdao  (brew install cdrdao)"
    echo "  - dd with /dev/rdiskN"
    echo ""
    echo "Example with dd:"
    echo "  sudo dd if=/dev/rdisk2 of=game.iso bs=2048"
    echo ""
    press_enter
}

# =============================================================================
# POPS BINARIES TRANSFER
# =============================================================================
transfer_pops_binaries() {
    clear; mkdir -p "$TMP"; load_settings

    local pops_dir="$SCRIPT_DIR/POPS-Binaries"
    [[ ! -d "$pops_dir" ]] && { cr; echo "POPS-Binaries folder not found."; cn; press_enter; return; }

    echo ""; echo "Transferring POPS Binaries to PS2 HDD..."
    echo "Binaries: POPS.ELF, IOPRP252.IMG"
    echo ""

    for f in POPS.ELF IOPRP252.IMG; do
        [[ ! -f "$pops_dir/$f" ]] && { cy; echo "  $f not found – skipping"; cn; continue; }
        echo "  Installing: $f"
        {
            echo "device $pfsshell_path"
            echo "mount __common"
            echo "lcd $pops_dir"
            echo "put $f"
            echo "umount"
            echo "exit"
        } | "$PFSSHELL" >/dev/null 2>&1
        cg; echo "  $f installed"; cn
    done

    reload_hdd_cache
    cg; echo ""; echo "Completed."; cn
    press_enter
}

# =============================================================================
# POPS VMC TRANSFER/BACKUP
# =============================================================================
transfer_backup_pops_vmc() {
    clear; mkdir -p "$TMP"; load_settings

    echo ""; cw; echo "POPS Virtual Memory Cards: [VMC]"
    echo "---------------------------------------------------"; cn
    cg; echo "         1) Transfer VMC to HDD"
    cr; echo "         2) Cancel"
    cy; echo "         3) Extract VMC from HDD"; cn; echo ""
    choice "123" "Select Option:"
    case $CHOICE_RESULT in
        1) _pops_vmc_install ;;
        2) return ;;
        3) _pops_vmc_extract ;;
    esac
}

_pops_vmc_install() {
    local vmc_dir="$SCRIPT_DIR/POPS/VMC"
    [[ ! -d "$vmc_dir" || -z "$(ls -A "$vmc_dir" 2>/dev/null)" ]] \
        && { echo "  POPS-VMC - Source Not Detected..."; press_enter; return; }
    clear; echo "Installing POPS VMC..."
    {
        echo "device $pfsshell_path"
        echo "mount __common"
        echo "mkdir POPS"
        echo "cd POPS"
    } > "$TMP/pfs-popsvmc.txt"
    find "$vmc_dir" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r subdir; do
        local dn="$(basename "$subdir")"
        {
            echo "mkdir \"$dn\""
            echo "lcd \"$subdir\""
            echo "cd \"$dn\""
            find "$subdir" -maxdepth 1 -type f | sort | while IFS= read -r f; do
                echo "put \"$(basename "$f")\""
            done
            echo "lcd .."
            echo "cd .."
        } >> "$TMP/pfs-popsvmc.txt"
    done
    { echo "ls -l"; echo "umount"; echo "exit"; } >> "$TMP/pfs-popsvmc.txt"
    cat "$TMP/pfs-popsvmc.txt" | "$PFSSHELL" 2>&1 \
        | grep -i "drwx" | "$SED" '1,2d' > "$LOG/PFS-POPS-VMC.log"
    cg; echo "VMC Transfer Completed."; cn; press_enter
}

_pops_vmc_extract() {
    mkdir -p "$SCRIPT_DIR/POPS/VMC"
    clear; echo "Extracting POPS VMC..."
    local vmc_dirs
    vmc_dirs=$(printf "device %s\nmount __common\ncd POPS\nls -l\numount\nexit\n" "$pfsshell_path" \
        | "$PFSSHELL" 2>/dev/null | grep -i "drwx" | "$SED" '1,2d' | cut -c42-500 | tr -d '/')
    while IFS= read -r vmc_dir; do
        [[ -z "$vmc_dir" ]] && continue
        mkdir -p "$SCRIPT_DIR/POPS/VMC/$vmc_dir"
        local files
        files=$(printf "device %s\nmount __common\ncd POPS\ncd \"%s\"\nls -l\numount\nexit\n" \
            "$pfsshell_path" "$vmc_dir" | "$PFSSHELL" 2>/dev/null \
            | grep -i "\-rw-" | cut -c42-500)
        while IFS= read -r vmc_file; do
            [[ -z "$vmc_file" ]] && continue
            printf "device %s\nmount __common\ncd POPS\ncd \"%s\"\nlcd %s\nget \"%s\"\numount\nexit\n" \
                "$pfsshell_path" "$vmc_dir" "$SCRIPT_DIR/POPS/VMC/$vmc_dir" "$vmc_file" \
                | "$PFSSHELL" >/dev/null 2>&1
        done <<< "$files"
    done <<< "$vmc_dirs"
    cg; echo "VMC Extraction Completed."; cn; press_enter
}

# =============================================================================
# RENAME VCD (Assign DB titles)
# =============================================================================
rename_vcd_db() {
    clear; load_settings
    local pops_dir="$SCRIPT_DIR/POPS"
    echo ""; cw; echo "Assign titles database to .VCD files:"; cn; echo ""
    local db_file="$BAT/TitlesDB/TitlesDB_PS1_English.txt"
    [[ ! -f "$db_file" ]] && { cr; echo "PS1 title database not found."; cn; press_enter; return; }

    local count=0
    while IFS= read -r vcd; do
        local fname="$(basename "${vcd%.*}")"
        local gameid="${fname//-/_}"
        local title
        title=$(grep "^${gameid:0:11}" "$db_file" 2>/dev/null | cut -d' ' -f2- | head -1)
        if [[ -n "$title" ]]; then
            local new_name="${gameid:0:11} ${title}.VCD"
            if [[ "$fname.VCD" != "$new_name" ]]; then
                mv "$vcd" "$pops_dir/$new_name" 2>/dev/null && (( count++ )) || true
                echo "  Renamed: $fname → $new_name"
            fi
        fi
    done < <(find "$pops_dir" -maxdepth 1 -iname "*.vcd" | sort)

    cg; echo ""; echo "Renamed $count files."; cn
    press_enter
}

# =============================================================================
# INSTALL HDD-OSD
# =============================================================================
install_hdd_osd() {
    clear; mkdir -p "$TMP"; load_settings

    local osd_archive=""
    for ext in 7z zip; do
        [[ -f "$SCRIPT_DIR/hddosd-1.10-u.$ext" ]] && osd_archive="$SCRIPT_DIR/hddosd-1.10-u.$ext" && break
        [[ -f "$TMP/hddosd-1.10-u.$ext" ]]         && osd_archive="$TMP/hddosd-1.10-u.$ext" && break
    done

    if [[ -z "$osd_archive" ]]; then
        cr; echo "hddosd-1.10-u.7z not found!"
        echo "Place hddosd-1.10-u.7z in the script folder."
        echo "MD5: 403202A03B910FB6FBD522D6AB5007E7"
        cn; press_enter; return
    fi

    echo ""; echo "Installing HDD-OSD..."
    "$SEVENZIP" x -bso0 "$osd_archive" -o"$TMP/hddosd" -y >/dev/null 2>&1

    echo ""
    echo "Transferring HDD-OSD files..."
    for part in __sysconf __system __common; do
        local src="$TMP/hddosd/$part"
        [[ ! -d "$src" ]] && continue
        {
            echo "device $pfsshell_path"
            echo "mount $part"
        } > "$TMP/pfs-osd-${part}.txt"
        _build_pfs_put_tree "$src" "$src" >> "$TMP/pfs-osd-${part}.txt"
        { echo "umount"; echo "exit"; } >> "$TMP/pfs-osd-${part}.txt"
        cat "$TMP/pfs-osd-${part}.txt" | "$PFSSHELL" >/dev/null 2>&1
        cg; echo "  $part – done"; cn
    done

    rm -rf "$TMP/hddosd"
    reload_hdd_cache
    cg; echo ""; echo "HDD-OSD Installation Completed!"; cn
    press_enter
}

# =============================================================================
# UNINSTALL HDD-OSD
# =============================================================================
uninstall_hdd_osd() {
    clear; load_settings
    cr; echo ""; echo "Uninstall HDD-OSD?"
    echo "This will remove __sysconf partition contents."; cn
    ask_yn || return
    {
        echo "device $pfsshell_path"
        echo "mount __sysconf"
        echo "rmdir ."
        echo "umount"
        echo "exit"
    } | "$PFSSHELL" >/dev/null 2>&1
    reload_hdd_cache
    cg; echo "HDD-OSD uninstalled."; cn
    press_enter
}

# =============================================================================
# HIDE / UNHIDE PARTITION
# =============================================================================
pphide_unhide() {
    local action="$1"   # hide/unhide
    local flag="$2"     # -hide / -unhide
    clear; load_settings
    echo ""; cw; echo "${action} a partition:"; cn; echo ""
    "$HDL_DUMP" toc "$hdl_path" 2>/dev/null | grep "0x1337" | cut -c30-250 | head -50
    echo ""
    cw; read -r -p "Enter game ID (e.g. SLUS_123.45): " part_name; cn
    [[ -z "$part_name" ]] && return
    # macOS: use "modify" with -hide / -unhide flag
    "$HDL_DUMP" modify "$hdl_path" "$part_name" "$flag" 2>&1
    reload_hdd_cache
    cg; echo "Done."; cn; press_enter
}

# =============================================================================
# UPDATE PARTITION RESOURCES HEADER (PP.HEADER)
# =============================================================================
update_pp_header() {
    clear; mkdir -p "$TMP"; load_settings

    echo ""; cw; echo "Update Partition Resources Header:"; cn; echo ""
    echo "This updates Title, Icons, Gameinfo, ART, OPL-Launcher for PS2 game partitions."
    echo ""

    local header_archive="$BAT/HDD-OSD_SAMPLE_HEADER.zip"
    [[ ! -f "$header_archive" ]] && { cr; echo "HDD-OSD_SAMPLE_HEADER.zip not found in BAT/"; cn; press_enter; return; }

    echo "Select games to update (press Enter to process all):"
    cat "$CACHE/PARTITION_HDL_GAME.txt" 2>/dev/null | head -60
    echo ""
    cw; read -r -p "Enter game ID (or press Enter for all): " filter_id; cn

    local gamelist="$TMP/pp_update_list.txt"
    if [[ -n "$filter_id" ]]; then
        grep "$filter_id" "$CACHE/PARTITION_HDL_GAME.txt" 2>/dev/null > "$gamelist"
    else
        cp "$CACHE/PARTITION_HDL_GAME.txt" "$gamelist" 2>/dev/null || true
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local gameid; gameid=$(echo "$line" | grep -oE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}' | head -1)
        local part_name; part_name=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
        [[ -z "$gameid" || -z "$part_name" ]] && continue

        echo "  Updating: $part_name ($gameid)"
        "$HDL_DUMP" modify_header "$hdl_path" "$part_name" >/dev/null 2>&1 || true
    done < "$gamelist"

    reload_hdd_cache
    cg; echo ""; echo "PP Header update completed."; cn
    press_enter
}

custom_pp_header() {
    cy; echo ""; echo "Custom PP Header: Extract/Inject partition resources."; cn
    echo ""; echo "Available partitions:"
    "$HDL_DUMP" toc "$hdl_path" 2>/dev/null | grep "0x1337" | cut -c30-250 | head -30
    echo ""
    cw; read -r -p "Enter partition name: " part_name; cn
    [[ -z "$part_name" ]] && return

    echo "1. Backup (dump) partition header"
    echo "2. Inject partition header"
    choice "12" "Select Option:"
    case $CHOICE_RESULT in
        1) "$HDL_DUMP" dump_header "$hdl_path" "$part_name" >/dev/null 2>&1
           cg; echo "Header backed up."; cn ;;
        2) "$HDL_DUMP" modify_header "$hdl_path" "$part_name" >/dev/null 2>&1
           cg; echo "Header injected."; cn ;;
    esac
    press_enter
}

# =============================================================================
# RENAME TITLE IN HDD-OSD
# =============================================================================
rename_title_hddosd() {
    clear; load_settings
    echo ""; "$HDL_DUMP" hdl_toc "$hdl_path" 2>/dev/null | head -50
    echo ""
    cw; read -r -p "Enter game ID to rename (e.g. SLUS_123.45): " part_name; cn
    [[ -z "$part_name" ]] && return
    cw; read -r -p "Enter new title: " new_title; cn
    [[ -z "$new_title" ]] && return
    # macOS: use "modify" instead of "rename"
    "$HDL_DUMP" modify "$hdl_path" "$part_name" "$new_title" 2>&1
    reload_hdd_cache
    cg; echo "Title renamed."; cn; press_enter
}

# =============================================================================
# TRANSFER APPS AS PFS PARTITION
# =============================================================================
transfer_apps_part() {
    clear; mkdir -p "$TMP"; load_settings
    local apps_dir="$SCRIPT_DIR/APPS"
    [[ ! -d "$apps_dir" || -z "$(ls -A "$apps_dir" 2>/dev/null)" ]] \
        && { cr; echo "APPS folder empty."; cn; press_enter; return; }

    cw; read -r -p "Enter partition name for APP (e.g. PP.APPS-MYAPP): " part_name; cn
    [[ -z "$part_name" ]] && return
    cw; read -r -p "Enter partition size (e.g. 64M): " part_size; cn
    [[ -z "$part_size" ]] && return

    # Create partition
    printf "device %s\nmkpart %s %s\nexit\n" "$pfsshell_path" "$part_name" "$part_size" \
        | "$PFSSHELL" >/dev/null 2>&1

    # Transfer files
    {
        echo "device $pfsshell_path"
        echo "mount $part_name"
        echo "lcd $apps_dir"
    } > "$TMP/pfs-appspart.txt"
    _build_pfs_put_tree "$apps_dir" "$apps_dir" >> "$TMP/pfs-appspart.txt"
    { echo "umount"; echo "exit"; } >> "$TMP/pfs-appspart.txt"
    cat "$TMP/pfs-appspart.txt" | "$PFSSHELL" >/dev/null 2>&1

    reload_hdd_cache
    cg; echo "APP partition created and populated."; cn; press_enter
}

# =============================================================================
# TRANSFER PS1 GAMES AS PFS PARTITION (for HDD-OSD/PSBBN)
# =============================================================================
transfer_ps1_games_hddosd() {
    clear; mkdir -p "$TMP"; load_settings
    echo ""; cy; echo "Transfer PS1 Games as Partition (for HDD-OSD/PSBBN/XMB):"; cn
    echo "Place your .VCD files in POPS/ folder first."
    echo ""
    transfer_ps1_games
}

# =============================================================================
# FREEHDB OSD CORRUPTION FIX
# =============================================================================
freehd_boot_fix_osd_corruption() {
    clear; load_settings
    echo ""; echo "Fix FreeHDBoot Graphical OSD Corruption..."
    {
        echo "device $pfsshell_path"
        echo "mount __sysconf"
        echo "rm osdmain.elf"
        echo "umount"
        echo "exit"
    } | "$PFSSHELL" >/dev/null 2>&1
    reload_hdd_cache
    cg; echo "Done."; cn; press_enter
}

# =============================================================================
# CREATE VMC (Virtual Memory Card)
# =============================================================================
create_vmc() {
    clear; load_settings; mkdir -p "$SCRIPT_DIR/VMC"
    echo ""; cw; echo "Create Virtual Memory Card (VMC):"; cn; echo ""
    cw; read -r -p "Enter VMC name (without extension): " vmc_name; cn
    [[ -z "$vmc_name" ]] && return

    echo "1. 8 MB  (standard)"
    echo "2. 16 MB"
    echo "3. 32 MB"
    choice "123" "Select size:"
    local vmc_size
    case $CHOICE_RESULT in
        1) vmc_size="8M"  ;;
        2) vmc_size="16M" ;;
        3) vmc_size="32M" ;;
    esac

    local vmc_file="$SCRIPT_DIR/VMC/${vmc_name}.bin"
    echo "Creating VMC: $vmc_file ($vmc_size)"
    dd if=/dev/zero of="$vmc_file" bs=1M count="${vmc_size//[^0-9]/}" 2>&1
    cg; echo "VMC created: $vmc_file"; cn
    press_enter
}

# =============================================================================
# CREATE OPL SHORTCUTS
# =============================================================================
create_shortcuts_opl() {
    cy; echo ""; echo "Create shortcuts for APPs or PS1 games in OPL APPS tab:"; cn
    echo "Feature: creates title.cfg entries in OPL partition APPS folder."
    echo ""; press_enter
}

# =============================================================================
# CHANGE OPL PARTITION
# =============================================================================
change_opl_partition() {
    clear; load_settings
    echo ""; cw; echo "Change OPL Resources Partition:"; cn
    echo "Current: $OPLPART"
    echo ""; echo "Common options: __common, +OPL"
    cw; read -r -p "Enter new OPL partition name: " new_opl; cn
    [[ -z "$new_opl" ]] && return

    OPLPART="$new_opl"
    [[ "$OPLPART" == "+OPL" ]] && CUSTOM_OPLPART="" || CUSTOM_OPLPART="Yes"

    mkdir -p "$SCRIPT_DIR/HDD-OSD/__common/OPL"
    echo "hdd_partition=$OPLPART" > "$SCRIPT_DIR/HDD-OSD/__common/OPL/conf_hdd.cfg"

    {
        echo "device $pfsshell_path"
        echo "mount __common"
        echo "mkdir OPL"
        echo "cd OPL"
        echo "lcd $SCRIPT_DIR/HDD-OSD/__common/OPL"
        echo "put conf_hdd.cfg"
        echo "umount"
        echo "exit"
    } | "$PFSSHELL" >/dev/null 2>&1

    # Persist to settings and current-session cache
    save_settings
    reload_hdd_cache

    cg; echo "OPL partition changed to: $OPLPART"; cn
    press_enter
}

# =============================================================================
# DOWNLOAD ART
# =============================================================================
download_art() {
    clear; load_settings
    mkdir -p "$TMP" "$SCRIPT_DIR/ART"

    # ---- Art type ----
    cw; echo ""; echo "Download ARTs:"
    echo "---------------------------------------------------"; cn
    cg; echo "        1) Yes (For PS2 Games)"; cn
    cr; echo "        2) No"; cn
    cy; echo "        3) Yes (For PS1 Games)"; cn
    echo ""
    read -r -p "Select Option [1/2/3]: " _ch
    local ARTType
    case "$_ch" in
        1) ARTType="PS2" ;;
        3) ARTType="PS1" ;;
        *) return ;;
    esac

    # ---- Device ----
    cy; echo ""; echo "What device will you be using?"; cn
    echo "  1 = HDD (Internal)"
    echo "  2 = USB"
    read -r -p "Select Option [1/2]: " _ch
    local device HDDPFS HDDPATH
    case "$_ch" in
        1) device="HDD"; HDDPFS="Yes"; HDDPATH="$SCRIPT_DIR" ;;
        2) device="USB"; HDDPFS=""
           cy; echo "Do you want to change the default directory?"; cn
           echo "(Useful if your games are on another drive)"
           read -r -p "[y/N]: " _yn
           if [[ "$_yn" =~ ^[Yy]$ ]]; then
               read -r -p "Enter full path (e.g. /Volumes/MyDrive): " HDDPATH
               [[ -z "$HDDPATH" ]] && HDDPATH="$SCRIPT_DIR"
           else
               HDDPATH="$SCRIPT_DIR"
           fi ;;
        *) return ;;
    esac

    # ---- Update mode ----
    cw; echo ""; echo "Download ARTs for all $ARTType installed games?"
    echo "---------------------------------------------------"; cn
    cg; echo "        1) Yes (Update Missing ART)"; cn
    cr; echo "        2) No"; cn
    cy; echo "        3) Yes (Replace ART)"; cn
    echo ""
    read -r -p "Select Option [1/2/3]: " _ch
    local UpdateOnlyMissingART
    case "$_ch" in
        1) UpdateOnlyMissingART="Yes" ;;
        2) return ;;
        3) UpdateOnlyMissingART="No" ;;
        *) return ;;
    esac

    # ---- PS1 OPL APPS TAB ----
    local OPLAPPSTAB="No"
    if [[ "$ARTType" == "PS1" ]]; then
        cy; echo ""
        echo "Do you want to download ARTs for PS1 shortcuts for OPL APPS TAB?"; cn
        read -r -p "[y/N]: " _yn
        [[ "$_yn" =~ ^[Yy]$ ]] && OPLAPPSTAB="Yes"
    fi

    # ---- Transfer to OPL partition (HDD only) ----
    local TransferART="No"
    if [[ "$HDDPFS" == "Yes" ]]; then
        cy; echo ""
        echo "Do you want to transfer the ARTs to the OPL Resources Partition after the update?"; cn
        read -r -p "[y/N]: " _yn
        [[ "$_yn" =~ ^[Yy]$ ]] && TransferART="Yes"
    fi

    # ---- Local ART.zip ----
    local uselocalART="no"
    if [[ -f "$SCRIPT_DIR/ART.zip" ]]; then
        cy; echo ""; echo "ART.zip detected – do you want to use it?"; cn
        read -r -p "[y/N]: " _yn
        [[ "$_yn" =~ ^[Yy]$ ]] && uselocalART="yes"
    fi

    # ---- Connectivity check ----
    local DownloadART="no"
    if [[ "$uselocalART" == "no" ]]; then
        echo ""; echo "Checking internet connection for ART..."
        if ! _ping_host archive.org; then
            cr; echo "Unable to PING!"; cn
            if [[ -f "$SCRIPT_DIR/ART.zip" ]]; then
                uselocalART="yes"
            else
                press_enter; return
            fi
        else
            curl -L -s \
                "https://archive.org/download/OPLM_ART_2024_09/OPLM_ART_2024_09.zip/PS1%2FSCES_000.01%2FSCES_000.01_COV.png" \
                -o "$TMP/SCES_000.01_COV.png" 2>/dev/null
            [[ ! -s "$TMP/SCES_000.01_COV.png" ]] && rm -f "$TMP/SCES_000.01_COV.png"
            if [[ ! -f "$TMP/SCES_000.01_COV.png" ]]; then
                cr; echo ""; echo "Unable to connect to archive.org"; cn
                if [[ -f "$SCRIPT_DIR/ART.zip" ]]; then
                    uselocalART="yes"
                    echo "Switching to offline mode (ART.zip)"
                    press_enter
                else
                    press_enter; return
                fi
            else
                DownloadART="yes"
                rm -f "$TMP/SCES_000.01_COV.png"
            fi
        fi
    fi

    # ---- HDD: verify partitions ----
    local POPSPART=""
    if [[ "$HDDPFS" == "Yes" ]]; then
        _require_hdd || return

        echo ""; echo "Detecting OPL Resources Partition:"
        echo "---------------------------------------------------"
        local opl_found
        opl_found=$(grep -ow "$OPLPART" "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null | head -1)
        if [[ "$opl_found" == "$OPLPART" ]]; then
            cg; echo "           $OPLPART - Partition Detected"; cn
        else
            cr; echo "        $OPLPART - Partition NOT Detected"
            echo "            Partition Must Be Created"; cn
            press_enter; return
        fi

        if [[ "$ARTType" == "PS1" ]]; then
            echo ""; echo "Detecting POPS Partition:"
            echo "---------------------------------------------------"
            POPSPART=$(grep -oE '__.POPS[0-9]?' "$CACHE/PARTITION_PS2HDD.txt" 2>/dev/null | head -1)
            if [[ -n "$POPSPART" ]]; then
                cg; echo "                Partition - Detected ($POPSPART)"; cn
            else
                cr; echo "             No POPS partition detected"
                echo "              Partition Must Be Created"; cn
                press_enter; return
            fi
            press_enter
        fi
    fi

    # ---- Build game list ----
    clear
    cw; echo ""; echo "Scanning Games List:"
    echo "---------------------------------------------------"; cn

    local games_list="$TMP/${ARTType}Games.txt"
    rm -f "$games_list"; touch "$games_list"

    if [[ "$ARTType" == "PS1" ]]; then
        if [[ "$device" == "HDD" ]]; then
            # List VCD files from POPS partition via pfsshell
            local pfs_pops_cmds="device $pfsshell_path
mount $POPSPART
ls
umount
exit"
            pfsshell_run "$pfs_pops_cmds" 2>&1 \
                | grep -iE '\.VCD$' \
                | grep -iE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}' \
                | sed -E 's/\.[^.]*$//; s/([A-Z]+_[0-9]+\.[0-9]+)\./\1 /' \
                >> "$games_list"
        else
            # USB: parse VCD files
            local pops_dir="$HDDPATH/POPS"
            if [[ -d "$pops_dir" ]]; then
                while IFS= read -r vcd; do
                    local vcd_base; vcd_base=$(basename "${vcd%.*}")
                    local gameid=""
                    if [[ -x "$BAT/UPSX_SID" ]]; then
                        gameid=$("$BAT/UPSX_SID" "$vcd" -1 2>/dev/null | tr -d '[:space:]')
                    fi
                    [[ -z "$gameid" ]] && \
                        gameid=$(echo "$vcd_base" | grep -oE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}' | head -1)
                    [[ -n "$gameid" ]] && echo "$gameid $vcd_base" >> "$games_list"
                done < <(find "$pops_dir" -maxdepth 1 -iname "*.VCD" 2>/dev/null | sort)
            fi
        fi
    else
        # PS2
        if [[ "$device" == "HDD" ]]; then
            if [[ -f "$CACHE/PS2_GAMES_HDD.txt" ]]; then
                grep -v "^type" "$CACHE/PS2_GAMES_HDD.txt" \
                    | grep -oE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}.*' \
                    | sed 's/  */ /g' \
                    >> "$games_list"
            fi
        else
            # USB: scan DVD/ and CD/ folders
            for _d in DVD CD; do
                local _folder="$HDDPATH/$_d"
                [[ ! -d "$_folder" ]] && continue
                while IFS= read -r isofile; do
                    local fname; fname=$(basename "${isofile%.*}")
                    local gameid=""
                    [[ -x "$HDL_DUMP" ]] && \
                        gameid=$("$HDL_DUMP" cdvd_info2 "$isofile" 2>/dev/null \
                            | grep -oE '[A-Z]{4}_[0-9]{3}\.[0-9]{2}' | head -1)
                    [[ -n "$gameid" ]] && echo "$gameid $fname" >> "$games_list"
                done < <(find "$_folder" -maxdepth 1 \( -iname "*.iso" -o -iname "*.cue" \) 2>/dev/null | sort)
            done
            # UL format
            if [[ -f "$HDDPATH/ul.cfg" ]]; then
                grep -aP '[\x20-\x7E]' "$HDDPATH/ul.cfg" 2>/dev/null \
                    | paste - - \
                    | awk '{print $NF, $1, $2}' \
                    | cut -c4-150 \
                    >> "$games_list" || true
            fi
        fi
    fi

    sort -k2 "$games_list" -o "$games_list" 2>/dev/null || true

    # ---- Scan existing ART files ----
    mkdir -p "$HDDPATH/ART"
    local art_files_list="$TMP/ARTFiles.txt"
    rm -f "$art_files_list"; touch "$art_files_list"

    if [[ "$HDDPFS" == "Yes" && "$UpdateOnlyMissingART" == "Yes" ]]; then
        echo ""; echo "Scanning Artwork Files on OPL partition..."
        echo "---------------------------------------------------"
        local pfs_scan_cmds="device $pfsshell_path
mount $OPLPART"
        if [[ -n "$CUSTOM_OPLPART" ]]; then
            pfs_scan_cmds+="
mkdir OPL
cd OPL"
        fi
        pfs_scan_cmds+="
cd ART
ls
cd ..
umount
exit"
        pfsshell_run "$pfs_scan_cmds" 2>&1 \
            | grep -iE '\.(png|jpg)$' \
            > "$art_files_list"
        echo "        Completed..."
    else
        find "$HDDPATH/ART" -maxdepth 1 \( -iname "*.png" -o -iname "*.jpg" \) \
            2>/dev/null -exec basename {} \; > "$art_files_list" || true
    fi

    # ---- Per-game download loop ----
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local Gameid; Gameid=$(echo "$line" | awk '{print $1}')
        local Gamename; Gamename=$(echo "$line" | cut -d' ' -f2-)
        [[ -z "$Gameid" ]] && continue

        echo ""; echo "$Gamename"
        echo "$Gameid"
        mkdir -p "$TMP/${ARTType}/$Gameid"

        local _art_file
        for _art_file in \
            "${Gameid}_COV.png" \
            "${Gameid}_COV2.png" \
            "${Gameid}_ICO.png" \
            "${Gameid}_LAB.png" \
            "${Gameid}_LGO.png" \
            "${Gameid}_BG_00.png" \
            "${Gameid}_SCR_00.png" \
            "${Gameid}_SCR_01.png"
        do
            local ART_NAME="$_art_file"
            local ART_NAME2="${ART_NAME%.png}"

            # Rename BG/SCR files (OPL convention)
            [[ "$ART_NAME2" == "${Gameid}_BG_00"  ]] && ART_NAME2="${Gameid}_BG"
            [[ "$ART_NAME2" == "${Gameid}_SCR_00" ]] && ART_NAME2="${Gameid}_SCR"
            [[ "$ART_NAME2" == "${Gameid}_SCR_01" ]] && ART_NAME2="${Gameid}_SCR2"

            # OPL APPS TAB renaming (PS1 only)
            if [[ "$OPLAPPSTAB" == "Yes" ]]; then
                local _suffix="${ART_NAME2:11}"   # strip 11-char game ID prefix
                if [[ "$device" == "USB" ]]; then
                    ART_NAME2="XX.${Gamename}.ELF${_suffix}"
                else
                    ART_NAME2="${Gameid}.${Gamename}.ELF${_suffix}"
                fi
            fi

            # Replace mode: wipe existing entry
            if [[ "$UpdateOnlyMissingART" == "No" ]]; then
                > "$art_files_list"
                rm -f "$HDDPATH/ART/${ART_NAME2}.png" 2>/dev/null || true
            fi

            # Skip if already present
            grep -qw "${ART_NAME2}.png" "$art_files_list" 2>/dev/null && continue

            local dl_dest="$TMP/${ARTType}/$Gameid/$ART_NAME"

            # 1) Try custom ART pack
            local custom_zip="$BAT/ART_CUSTOM_GAMEID.zip"
            if [[ -f "$custom_zip" ]]; then
                "$SEVENZIP" e -bso0 "$custom_zip" \
                    -o"$TMP/${ARTType}/$Gameid" \
                    "${ARTType}/${ART_NAME}" -r -y >/dev/null 2>&1 || true
            fi

            # 2) Download or extract from local pack
            if [[ ! -s "$dl_dest" ]]; then
                if [[ "$uselocalART" == "no" ]]; then
                    local _url="https://archive.org/download/OPLM_ART_2024_09/OPLM_ART_2024_09.zip/${ARTType}%2F${Gameid}%2F${ART_NAME}"
                    curl -s "$_url" -o "$dl_dest" 2>/dev/null
                else
                    "$SEVENZIP" x -bso0 "$SCRIPT_DIR/ART.zip" \
                        -o"$TMP" "${ARTType}/${Gameid}/${ART_NAME}" -r -y >/dev/null 2>&1 || true
                fi
            fi

            # 3) Move if successful
            if [[ -s "$dl_dest" ]]; then
                mv "$dl_dest" "$HDDPATH/ART/${ART_NAME2}.png" 2>/dev/null || true
                if [[ -f "$HDDPATH/ART/${ART_NAME2}.png" ]]; then
                    co; echo "  + ${ART_NAME2}.png"; cn
                fi
            else
                rm -f "$dl_dest" 2>/dev/null || true
            fi
        done

        rm -rf "$TMP/${ARTType}/$Gameid"

    done < "$games_list"

    # ---- Optional: transfer ART folder to OPL partition ----
    if [[ "$HDDPFS" == "Yes" && "$TransferART" == "Yes" ]]; then
        echo ""; echo "---------------------------------------------------"
        cw; echo "        Creating transfer queue..."; cn

        local pfs_put_cmds="device $pfsshell_path
mount $OPLPART"
        if [[ -n "$CUSTOM_OPLPART" ]]; then
            pfs_put_cmds+="
mkdir OPL
cd OPL"
        fi
        pfs_put_cmds+="
mkdir ART
cd ART"

        cd "$HDDPATH/ART" 2>/dev/null || true
        while IFS= read -r _artf; do
            [[ -z "$_artf" ]] && continue
            pfs_put_cmds+="
put \"$_artf\""
        done < <(find . -maxdepth 1 \( -name "*.png" -o -name "*.jpg" \) 2>/dev/null \
                    | sed 's|^\./||' | sort)
        pfs_put_cmds+="
ls -l
umount
exit"
        cd "$SCRIPT_DIR" 2>/dev/null || true

        cw; echo "        Installing queue..."; cn
        mkdir -p "$LOG"
        pfsshell_run "$pfs_put_cmds" 2>&1 \
            | grep -iE '\.(png|jpg)$' \
            > "$LOG/PFS-ART.log"
        echo "        Completed."
    fi

    rm -rf "$TMP" && mkdir -p "$TMP"

    echo ""; echo "---------------------------------------------------"
    cg; echo "Downloading completed..."; cn
    echo ""
    press_enter
}

# =============================================================================
# DOWNLOAD CFG
# =============================================================================
download_cfg() {
    clear; load_settings
    echo ""; echo "Download CFG compatibility database..."
    if _ping_host github.com; then
        local compat_db="$TMP/PS2-OPL-CFG-Compatibility-Database.7z"
        curl -L --progress-bar \
            "https://github.com/GDX-X/PS2-OPL-CFG-Compatibility-Database/releases/download/Latest/PS2-OPL-CFG-Compatibility-Database.7z" \
            -o "$compat_db" 2>/dev/null
        [[ -s "$compat_db" ]] && mv "$compat_db" "$BAT/" && cg && echo "CFG database updated!" && cn \
            || { cr; echo "Download failed."; cn; }
    else
        cr; echo "No internet connection."; cn
    fi
    press_enter
}

# =============================================================================
# UPDATE APPS PARTITION
# =============================================================================
update_part_apps() {
    _require_hdd || return
    clear; load_settings
    echo ""; echo "Updating APPS partition..."
    transfer_opl_resources
}

# =============================================================================
# POPS HUGO PATCH
# =============================================================================
pops_hugo_patch() {
    clear; load_settings
    echo ""; echo "Applying HugoPocked's POPStarter patches..."
    local zip="$SCRIPT_DIR/POPS-Binaries/Hugopocked_POPStarter_Fixes.zip"
    mkdir -p "$TMP/hugopatch"
    "$SEVENZIP" x -bso0 "$zip" -o"$TMP/hugopatch" >/dev/null 2>&1
    cp "$TMP/hugopatch/"*.ELF "$SCRIPT_DIR/POPS-Binaries/" 2>/dev/null || true
    rm -rf "$TMP/hugopatch"
    cg; echo "Patches applied."; cn
    press_enter
}

# =============================================================================
# ENTRY POINT
# =============================================================================
init_dirs
_recover_pops
rm -rf "$TMP" && mkdir -p "$TMP"

# Check tools availability
if [[ ! -f "$HDL_DUMP" ]]; then
    cr; echo ""
    echo "hdl_dump not found at: $HDL_DUMP"
    echo "Run install_deps.sh from the project root to download tools."; cn
    echo ""
    press_enter
fi

# Initial DB language setup if no settings
if [[ ! -f "$SETTINGS" ]]; then
    db_lang_settings
fi

# Load settings
load_settings

# Update check (non-blocking)
check_for_updates &
wait $! 2>/dev/null || true

# Initial HDD scan
scan_ps2_hdd

# Main loop
main_menu
