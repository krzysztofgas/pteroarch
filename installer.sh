#!/usr/bin/env bash
set -uo pipefail

INSTALLER_VERSION="2.1.0"
DEFAULT_PANEL_VERSION="v1.15.2"

PANEL_DIR=/var/www/pterodactyl
WEB_USER=http
STATE_DIR=/root/.pteroarch
ANSWERS_FILE=$STATE_DIR/answers.env
RUNTIME_FILE=$STATE_DIR/runtime.env
DONE_FILE=$STATE_DIR/done
STATUS_FILE=$STATE_DIR/status
LOG_FILE=/var/log/pteroarch.log
CRED_FILE=/root/pterodactyl-credentials.txt
TOOLS_DIR=/usr/local/lib/pteroarch
ART_HOME=$TOOLS_DIR/artisan-home
HOSTS_MARK="# added by PteroArch"

DRY_RUN=false
VERBOSE=false
OWN_STATE=false
NO_COLOR_FLAG=false
NO_ANIM_FLAG=false
HELP=''
SPIN_OUT=''
INSTALL_T0=0

ANSWER_VARS=(
    MODE PANEL_VERSION
    PANEL_HOST PANEL_HOST_IS_IP USE_SSL LE_EMAIL
    PHP_FLAVOR TIMEZONE TELEMETRY
    MAIL_SETUP SMTP_HOST SMTP_PORT SMTP_ENC SMTP_USER SMTP_PASS MAIL_FROM MAIL_FROM_NAME
    ADMIN_EMAIL ADMIN_USERNAME ADMIN_FIRST ADMIN_LAST ADMIN_PASSWORD ADMIN_PASSWORD_GENERATED
    DB_PASS
    NODE_NAME NODE_LOCATION NODE_MEMORY NODE_DISK ALLOC_IP ALLOC_RANGE WINGS_PORT SFTP_PORT
    W_CONFIG_METHOD W_PANEL_URL W_TOKEN W_NODE_ID W_CONFIG_TEXT W_OVERRIDE W_SSL W_FQDN
    FW SSH_PORT FW_GAME_RANGE
)
for __v in "${ANSWER_VARS[@]}"; do printf -v "$__v" '%s' ''; done
unset __v
WINGS_PORT=8080
SFTP_PORT=2022

LOGO=(
    '   ___  __               ___           __'
    '  / _ \/ /____ _______  / _ | ________/ /'
    ' / ___/ __/ -_) __/ _ \/ __ |/ __/ __/ _ \'
    '/_/   \__/\__/_/  \___/_/ |_/_/  \__/_//_/'
)

# ── Look & feel ──
init_ui() {
    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    UNICODE=false
    [[ ${loc^^} == *UTF-8* || ${loc^^} == *UTF8* ]] && UNICODE=true

    USE_COLOR=true
    ANIM=true
    [[ -t 1 ]] || {
        USE_COLOR=false
        ANIM=false
    }
    [[ ${TERM:-dumb} == dumb ]] && {
        USE_COLOR=false
        ANIM=false
    }
    [[ -n ${NO_COLOR:-} ]] && USE_COLOR=false
    $NO_COLOR_FLAG && USE_COLOR=false
    $NO_ANIM_FLAG && ANIM=false

    R='' B='' ACC='' ACC2='' GRN='' YEL='' RED='' MAG='' GRY='' BADGE='' BAR_ON='' BAR_OFF=''
    PALETTE=('')
    if $USE_COLOR; then
        R=$'\e[0m'
        B=$'\e[1m'
        local n
        n=$(tput colors 2>/dev/null || echo 8)
        [[ $n =~ ^[0-9]+$ ]] || n=8
        if ((n >= 256)) || [[ ${COLORTERM:-} == *truecolor* || ${COLORTERM:-} == *24bit* ]]; then
            ACC=$'\e[38;5;39m'
            ACC2=$'\e[38;5;81m'
            GRN=$'\e[38;5;78m'
            YEL=$'\e[38;5;221m'
            RED=$'\e[38;5;203m'
            MAG=$'\e[38;5;177m'
            GRY=$'\e[38;5;244m'
            BADGE=$'\e[1;38;5;231;48;5;25m'
            BAR_ON=$'\e[38;5;39m'
            BAR_OFF=$'\e[38;5;239m'
            PALETTE=($'\e[38;5;51m' $'\e[38;5;45m' $'\e[38;5;39m' $'\e[38;5;33m' $'\e[38;5;63m' $'\e[38;5;99m' $'\e[38;5;135m')
        else
            ACC=$'\e[34m'
            ACC2=$'\e[36m'
            GRN=$'\e[32m'
            YEL=$'\e[33m'
            RED=$'\e[31m'
            MAG=$'\e[35m'
            GRY=$'\e[2m'
            BADGE=$'\e[1;37;44m'
            BAR_ON=$'\e[36m'
            BAR_OFF=$'\e[2m'
            PALETTE=($'\e[36m' $'\e[36m' $'\e[34m' $'\e[34m' $'\e[35m')
        fi
    fi

    if $UNICODE; then
        I_OK="✔"
        I_BAD="✖"
        I_WARN="▲"
        I_INFO="ℹ"
        I_ARROW="❯"
        I_DOT="·"
        I_BUL="•"
        I_ENTER="↵"
        I_SKIP="↷"
        I_ELL="…"
        H="─"
        HB="━"
        BAR_F="━"
        BAR_E="─"
        BX_TL="╭"
        BX_TR="╮"
        BX_BL="╰"
        BX_BR="╯"
        BX_V="│"
        SPIN_FRAMES=(◜ ◠ ◝ ◞ ◡ ◟)
        SPARKS=("✦" "✧" "⋆" "✶" "·")
    else
        I_OK="+"
        I_BAD="x"
        I_WARN="!"
        I_INFO="i"
        I_ARROW=">"
        I_DOT="."
        I_BUL="*"
        I_ENTER=">"
        I_SKIP="~"
        I_ELL="..."
        H="-"
        HB="="
        BAR_F="#"
        BAR_E="-"
        BX_TL="+"
        BX_TR="+"
        BX_BL="+"
        BX_BR="+"
        BX_V="|"
        SPIN_FRAMES=('|' '/' '-' '\')
        SPARKS=("*" "+" ".")
    fi

    COLS=$(tput cols 2>/dev/null || echo 80)
    [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
    ((COLS > 100)) && COLS=100
    ((COLS < 50)) && COLS=50

    if { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; else TTY=/dev/stdin; fi
    STTY_ORIG=''
    [[ $TTY == /dev/tty ]] && STTY_ORIG=$(stty -g <"$TTY" 2>/dev/null)
}

restore_tty() {
    [[ -n ${STTY_ORIG:-} ]] && stty "$STTY_ORIG" <"$TTY" 2>/dev/null
    [[ -t 1 ]] && printf '%s\e[?25h' "${R:-}"
    return 0
}

repeat() {
    local s
    printf -v s '%*s' "$2" ''
    printf '%s' "${s// /$1}"
}
strip() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }
fmt_time() { printf '%d:%02d' $(($1 / 60)) $(($1 % 60)); }
nap() {
    $ANIM && sleep "$1"
    return 0
}

cls() {
    [[ -t 1 ]] && printf '\e[H\e[2J'
    return 0
}
rule() { printf '  %s%s%s\n' "$GRY" "$(repeat "$H" $((COLS - 4)))" "$R"; }
say() { printf '%s\n' "$*" | fold -s -w "$((COLS - 4))" | sed 's/^/  /'; }
dim() { printf '%s\n' "$*" | fold -s -w "$((COLS - 6))" | sed "s/^/  ${GRY}/; s/\$/${R}/"; }
hint() { printf '%s\n' "$*" | fold -s -w "$((COLS - 10))" | sed "s/^/      ${GRY}/; s/\$/${R}/"; }
ok() { printf '  %s%s%s %s\n' "$GRN" "$I_OK" "$R" "$*"; }
warn() { printf '  %s%s%s %s\n' "$YEL" "$I_WARN" "$R" "$*"; }
err() { printf '  %s%s%s %s\n' "$RED" "$I_BAD" "$R" "$*"; }
info() { printf '  %s%s%s %s\n' "$ACC2" "$I_INFO" "$R" "$*"; }
die() {
    echo
    err "$*"
    exit 1
}
blank() { echo; }
kv() {
    local first=true l
    while IFS= read -r l; do
        if $first; then
            printf '    %s%-22s%s %s\n' "$GRY" "$1" "$R" "$l"
            first=false
        else printf '    %-22s %s\n' '' "$l"; fi
    done < <(printf '%s\n' "$2" | fold -s -w $((COLS - 31)))
}
title() { printf '  %s%s%s\n' "$B" "$*" "$R"; }

box() {
    local c=$1 ttl=$2
    shift 2
    local w=$((COLS - 6)) inner=$((COLS - 10)) line plain pad para fill
    if [[ -n $ttl ]]; then
        fill=$((w - ${#ttl} - 5))
        ((fill < 0)) && fill=0
        printf '  %s\n' "${c}${BX_TL}${H}${R} ${B}${ttl}${R} ${c}$(repeat "$H" "$fill")${BX_TR}${R}"
    else
        printf '  %s\n' "${c}${BX_TL}$(repeat "$H" $((w - 2)))${BX_TR}${R}"
    fi
    for para in "$@"; do
        while IFS= read -r line; do
            plain=$(strip "$line")
            pad=$((inner - ${#plain}))
            ((pad < 0)) && pad=0
            printf '  %s%s%s %s%*s %s%s%s\n' "$c" "$BX_V" "$R" "$line" "$pad" '' "$c" "$BX_V" "$R"
        done < <(if [[ $para == *$'\e'* ]]; then printf '%s\n' "$para"; else printf '%s\n' "$para" | fold -s -w "$inner"; fi)
    done
    printf '  %s\n' "${c}${BX_BL}$(repeat "$H" $((w - 2)))${BX_BR}${R}"
}

header() {
    local ttl=$1 ctx=${2:-} n=${3:-0} total=${4:-0} brand w=$((COLS - 4))
    cls
    blank
    if $USE_COLOR; then brand="${BADGE} PteroArch ${R}"; else brand="[ PteroArch ]"; fi
    printf '  %s' "$brand"
    ((COLS >= 72)) && printf ' %sPterodactyl for Arch Linux%s' "$GRY" "$R"
    [[ -n $ctx ]] && printf '  %s%s%s %s%s%s' "$GRY" "$I_DOT" "$R" "$ACC2" "$ctx" "$R"
    printf '\n'
    if ((total > 0)); then
        local f=$((w * n / total))
        printf '  %s%s%s%s%s\n' "$BAR_ON" "$(repeat "$HB" "$f")" "$BAR_OFF" "$(repeat "$H" $((w - f)))" "$R"
    else
        rule
    fi
    blank
    printf '  %s%s%s %s%s%s\n\n' "$ACC" "$I_ARROW" "$R" "$B" "$ttl" "$R"
}

show_logo() {
    local row line i col out
    for row in "${!LOGO[@]}"; do
        line=${LOGO[row]}
        if $USE_COLOR; then
            out=''
            for ((i = 0; i < ${#line}; i += 6)); do
                col=$(((i / 6 + row) % ${#PALETTE[@]}))
                out+="${PALETTE[col]}${line:i:6}"
            done
            printf '  %s%s%s\n' "$B" "$out" "$R"
        else
            printf '  %s\n' "$line"
        fi
        nap 0.07
    done
}

typewrite() {
    if $ANIM; then
        local i
        for ((i = 0; i < ${#1}; i++)); do
            printf '%s' "${1:i:1}"
            sleep 0.012
        done
        printf '\n'
    else
        printf '%s\n' "$1"
    fi
}

spin_run() {
    local label=$1
    shift
    local tmp rc
    tmp=$(mktemp)
    ((${#label} > COLS - 8)) && label="${label:0:$((COLS - 11))}$I_ELL"
    if $ANIM; then
        "$@" >"$tmp" 2>/dev/null &
        local pid=$! i=0
        printf '\e[?25l'
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r\e[K  %s%s%s %s%s%s' "$ACC2" "${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}" "$R" "$GRY" "$label" "$R"
            i=$((i + 1))
            sleep 0.08
        done
        printf '\r\e[K\e[?25h'
        wait "$pid"
    else
        "$@" >"$tmp" 2>/dev/null
    fi
    rc=$?
    SPIN_OUT=$(<"$tmp")
    rm -f "$tmp"
    return "$rc"
}

celebrate() {
    $ANIM || return 0
    local i j line w=$((COLS - 4))
    printf '\e[?25l'
    for ((i = 0; i < 16; i++)); do
        line=''
        for ((j = 0; j < w; j += 2)); do
            if ((RANDOM % 5 == 0)); then
                line+="${PALETTE[RANDOM % ${#PALETTE[@]}]}${SPARKS[RANDOM % ${#SPARKS[@]}]} "
            else
                line+="  "
            fi
        done
        printf '\r  %s%s' "$line" "$R"
        sleep 0.07
    done
    printf '\r\e[K\e[?25h'
}

# ── Questions ──
die_input() {
    printf '%s' "$R"
    echo
    die "Input closed - stopping. Nothing after this point was changed."
}

trim() {
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

prompt_line() {
    local q=$1 d=$2 h=''
    [[ -n ${3:-} ]] && h=" ${GRY}(?)${R}"
    printf '  %s%s%s %s%s%s%s' "$ACC" "$I_ARROW" "$R" "$B" "$q" "$R" "$h"
    [[ -n $d ]] && printf ' %s[%s]%s' "$GRY" "$d" "$R"
    printf ': %s' "$ACC2"
}

read_line() {
    local __l
    IFS= read -r __l <"$TTY" || die_input
    printf '%s' "$R"
    printf -v "$1" '%s' "$__l"
}

read_secret() {
    local __s='' __c
    if [[ $TTY == /dev/tty ]]; then
        stty -echo <"$TTY" 2>/dev/null
        while true; do
            IFS= read -rsn1 __c <"$TTY" || {
                stty echo <"$TTY" 2>/dev/null
                die_input
            }
            case $__c in
            '') break ;;
            $'\x7f' | $'\b') if [[ -n $__s ]]; then
                __s=${__s%?}
                printf '\b \b'
            fi ;;
            $'\e') IFS= read -rsn2 -t 0.02 __c <"$TTY" || true ;;
            $'\x04') ;;
            *)
                __s+=$__c
                printf '%s' "$I_BUL"
                ;;
            esac
        done
        stty echo <"$TTY" 2>/dev/null
    else
        IFS= read -rs __s <"$TTY" || die_input
    fi
    printf '%s\n' "$R"
    printf -v "$1" '%s' "$__s"
}

show_help() {
    if [[ -n ${1:-} ]]; then box "$ACC2" "Help" "$1"; else info "No extra help here - the text above says it all."; fi
}

ask() {
    local __var=$1 prompt=$2 def=${3-} val=${4-} msg=${5-"That doesn't look right - try again."} ans help=$HELP
    HELP=''
    while true; do
        prompt_line "$prompt" "$def" "$help"
        read_line ans
        ans=$(trim "$ans")
        if [[ $ans == '?' ]]; then
            show_help "$help"
            continue
        fi
        ans=${ans:-$def}
        if [[ -z $ans ]]; then
            err "This one can't be empty."
            continue
        fi
        if [[ -n $val ]] && ! "$val" "$ans"; then
            err "$msg"
            continue
        fi
        printf -v "$__var" '%s' "$ans"
        return 0
    done
}

ask_opt() {
    local __var=$1 prompt=$2 def=${3-} ans help=$HELP shown
    HELP=''
    shown=${def:-optional - Enter to skip}
    while true; do
        prompt_line "$prompt" "$shown" "$help"
        read_line ans
        ans=$(trim "$ans")
        if [[ $ans == '?' ]]; then
            show_help "$help"
            continue
        fi
        printf -v "$__var" '%s' "${ans:-$def}"
        return 0
    done
}

ask_yn() {
    local q=$1 def=${2:-Y} ans opts help=$HELP
    HELP=''
    if [[ $def == Y ]]; then opts="${B}Y${R}${GRY}/n"; else opts="y/${B}N${R}${GRY}"; fi
    while true; do
        prompt_line "$q" "$opts" "$help"
        read_line ans
        ans=$(trim "$ans")
        if [[ $ans == '?' ]]; then
            show_help "$help"
            continue
        fi
        ans=${ans:-$def}
        case ${ans,,} in
        y | yes) return 0 ;;
        n | no) return 1 ;;
        esac
        err "Please answer y (yes) or n (no)."
    done
}

choose() {
    local __var=$1 def=$2
    shift 2
    local i=1 defidx=1 opt key label hnt ans help=$HELP
    local -a keys=()
    HELP=''
    for opt in "$@"; do
        IFS='|' read -r key label hnt <<<"$opt"
        keys+=("$key")
        [[ $key == "$def" ]] && defidx=$i
        i=$((i + 1))
    done
    i=1
    for opt in "$@"; do
        IFS='|' read -r key label hnt <<<"$opt"
        if ((i == defidx)); then
            printf '    %s%s%d%s  %s%s%s %s(default)%s\n' "$B" "$ACC" "$i" "$R" "$B" "$label" "$R" "$GRY" "$R"
        else
            printf '    %s%d%s  %s\n' "$ACC" "$i" "$R" "$label"
        fi
        [[ -n $hnt ]] && printf '%s\n' "$hnt" | fold -s -w "$((COLS - 12))" | sed "s/^/       ${GRY}/; s/\$/${R}/"
        i=$((i + 1))
    done
    while true; do
        prompt_line "Your choice" "$defidx" "$help"
        read_line ans
        ans=$(trim "$ans")
        if [[ $ans == '?' ]]; then
            show_help "$help"
            continue
        fi
        ans=${ans:-$defidx}
        if [[ $ans =~ ^[0-9]+$ ]] && ((ans >= 1 && ans <= ${#keys[@]})); then
            printf -v "$__var" '%s' "${keys[ans - 1]}"
            return 0
        fi
        for key in "${keys[@]}"; do
            if [[ ${ans,,} == "$key" ]]; then
                printf -v "$__var" '%s' "$key"
                return 0
            fi
        done
        err "Type a number from 1 to ${#keys[@]}."
    done
}

ask_password() {
    local __var=$1 prompt=$2 gen=$3 val=$4 msg=$5 p1 p2 help=$HELP def=''
    HELP=''
    PW_WAS_GENERATED=false
    [[ $gen == true ]] && def="Enter = generate one for me"
    while true; do
        prompt_line "$prompt" "$def" "$help"
        read_secret p1
        if [[ $p1 == '?' ]]; then
            show_help "$help"
            continue
        fi
        if [[ -z $p1 && $gen == true ]]; then
            printf -v "$__var" '%s' "$(gen_password)"
            PW_WAS_GENERATED=true
            ok "A strong password was generated - you'll see it at the end."
            return 0
        fi
        if ! "$val" "$p1"; then
            err "$msg"
            continue
        fi
        prompt_line "Type it again" "" ""
        read_secret p2
        if [[ $p1 != "$p2" ]]; then
            err "The two entries didn't match - let's try again."
            continue
        fi
        printf -v "$__var" '%s' "$p1"
        ok "Password set."
        return 0
    done
}

tz_search() {
    local q=${1// /_} out exact
    [[ $q =~ ^[A-Za-z_/+-]+$ ]] || return 0
    out=$(find /usr/share/zoneinfo \( -path '*/posix' -o -path '*/right' \) -prune -o -type f -iname "*${q##*/}*" -print 2>/dev/null |
        sed 's#^/usr/share/zoneinfo/##' | grep -E '^[A-Za-z_]+/[A-Za-z0-9_+/-]+$' | grep -v '^Etc/' | sort)
    exact=$(grep -ix -- "$q" <<<"$out" | head -1)
    if [[ -n $exact ]]; then printf '%s\n' "$exact"; else printf '%s\n' "$out" | sed '/^$/d' | head -12; fi
}

ask_tz() {
    local __var=$1 def=$2 ans help=$HELP
    local -a m=()
    HELP=''
    while true; do
        prompt_line "Timezone" "$def" "$help"
        read_line ans
        ans=$(trim "$ans")
        if [[ $ans == '?' ]]; then
            show_help "$help"
            continue
        fi
        ans=${ans:-$def}
        if is_tz "$ans"; then
            printf -v "$__var" '%s' "$ans"
            return 0
        fi
        mapfile -t m < <(tz_search "$ans")
        if ((${#m[@]} == 1)); then
            ok "Found it: ${m[0]}"
            printf -v "$__var" '%s' "${m[0]}"
            return 0
        elif ((${#m[@]} > 1)); then
            warn "A few timezones match \"$ans\" - type the one you mean:"
            printf "      ${ACC2}%s${R}\n" "${m[@]}"
        else
            err "Couldn't find \"$ans\". Try a big city near you (e.g. Berlin, New_York, Tokyo) or UTC."
        fi
    done
}

pause() {
    local x
    printf '\n  %s%s %s%s' "$GRY" "$I_ENTER" "${1:-Press Enter to continue}" "$R"
    read_line x
    : "$x"
}

gen_password() {
    local p
    while :; do
        p=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20)
        [[ $p =~ [A-Z] && $p =~ [a-z] && $p =~ [0-9] ]] && break
    done
    printf '%s' "$p"
}
gen_hex() { LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c "${1:-32}"; }

# ── Validators ──
is_email() { [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
is_ipv4() {
    [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1}"; do ((10#$o <= 255)) || return 1; done
}
is_fqdn() { [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
is_node_host() { is_fqdn "$1" || is_ipv4 "$1"; }
is_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
is_pos_int() { [[ $1 =~ ^[0-9]{1,9}$ ]] && ((10#$1 > 0)); }
is_tz() { [[ $1 == UTC ]] || { [[ $1 =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$ ]] && [[ -f /usr/share/zoneinfo/$1 ]]; }; }
is_username() { [[ $1 =~ ^[a-z0-9][a-z0-9_.-]+[a-z0-9]$ ]] && ((${#1} <= 191)); }
is_name() { [[ -n $1 && ${#1} -le 191 && $1 != *\"* && $1 != *\'* && $1 != *\\* ]]; }
is_password() { ((${#1} >= 8)) && [[ $1 =~ [A-Z] && $1 =~ [0-9] ]]; }
is_any_pw() { [[ -n $1 ]]; }
is_url() { [[ $1 =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]]; }
is_token() { [[ $1 =~ ^[A-Za-z0-9_.-]{16,}$ ]]; }
is_node_name() { [[ $1 =~ ^[A-Za-z0-9_\ .-]{1,100}$ ]]; }
is_loc_short() { [[ $1 =~ ^[A-Za-z0-9_.-]{1,60}$ ]]; }
is_port_range() {
    [[ $1 =~ ^([0-9]{4,5})-([0-9]{4,5})$ ]] || return 1
    local lo=$((10#${BASH_REMATCH[1]})) hi=$((10#${BASH_REMATCH[2]}))
    ((lo > 1024 && hi <= 65535 && lo < hi && hi - lo + 1 <= 1000))
}
is_smtp_enc() { [[ $1 == tls || $1 == ssl || $1 == none ]]; }

# ── System facts ──
fetch_public_ip() { curl -4 -fsS --max-time 5 https://ipv4.icanhazip.com | tr -d '[:space:]'; }

detect_facts() {
    TOTAL_MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    FREE_DISK_MB=$(df -Pm /var/lib 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    FREE_ROOT_MB=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    PRIMARY_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    LOCAL_IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | sort -u | tr '\n' ' ')
    PUBLIC_IP=''
    spin_run "Looking up this machine's public IP address" fetch_public_ip && PUBLIC_IP=$SPIN_OUT
    is_ipv4 "${PUBLIC_IP:-x}" || PUBLIC_IP=''
    SYSTEM_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    [[ -z $SYSTEM_TZ ]] && SYSTEM_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
    is_tz "${SYSTEM_TZ:-x}" || SYSTEM_TZ=UTC
    case "$(uname -m)" in
    x86_64) WINGS_ARCH=amd64 ;;
    aarch64) WINGS_ARCH=arm64 ;;
    *) WINGS_ARCH='' ;;
    esac
    SSH_DETECTED=''
    if [[ -n ${SSH_CONNECTION:-} ]]; then SSH_DETECTED=${SSH_CONNECTION##* }; fi
    if [[ -z $SSH_DETECTED ]]; then
        SSH_DETECTED=$(ss -Htlnp 2>/dev/null | awk '/"sshd"/ {n=split($4,a,":"); print a[n]; exit}')
    fi
    KERNEL_PENDING_REBOOT=false
    [[ -d /usr/lib/modules/$(uname -r) ]] || KERNEL_PENDING_REBOOT=true
}

resolve_a() { getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' '; }

port_owner() {
    ss -Htlnp "sport = :$1" 2>/dev/null | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -1
}

latest_panel_version() {
    local url tag
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 15 https://github.com/pterodactyl/panel/releases/latest 2>/dev/null || true)
    tag=${url##*/}
    [[ $tag =~ ^v1\.[0-9]+\.[0-9]+$ ]] && printf '%s' "$tag"
}

has_panel() { [[ $MODE == full || $MODE == panel ]]; }
has_wings() { [[ $MODE == full || $MODE == wings ]]; }

set_php_vars() {
    if [[ ${PHP_FLAVOR:-legacy} == current ]]; then
        PHP_BIN=/usr/bin/php
        PHP_CONF_D=/etc/php/conf.d
        FPM_SERVICE=php-fpm
        FPM_SOCK=/run/php-fpm/php-fpm.sock
        PHP_PKGS=(php php-fpm php-gd php-sodium)
    else
        PHP_BIN=/usr/bin/php-legacy
        PHP_CONF_D=/etc/php-legacy/conf.d
        FPM_SERVICE=php-fpm-legacy
        FPM_SOCK=/run/php-fpm-legacy/php-fpm.sock
        PHP_PKGS=(php-legacy php-legacy-fpm php-legacy-gd php-legacy-sodium)
    fi
}

panel_url() { if [[ $USE_SSL == true ]]; then printf 'https://%s' "$PANEL_HOST"; else printf 'http://%s' "$PANEL_HOST"; fi; }

mode_label() {
    case $MODE in
    full) echo "Panel + Wings on this machine" ;;
    panel) echo "Panel only" ;;
    wings) echo "Wings only (node for an existing panel)" ;;
    esac
}

# ── State ──
save_kv_file() {
    local f=$1
    shift
    local v
    (
        umask 077
        : >"$f"
        for v in "$@"; do printf '%s=%q\n' "$v" "${!v}" >>"$f"; done
    )
}
save_answers() {
    $DRY_RUN && return 0
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    save_kv_file "$ANSWERS_FILE" "${ANSWER_VARS[@]}"
}
# shellcheck disable=SC1090
load_answers() { source "$ANSWERS_FILE"; }
# shellcheck disable=SC1090
load_runtime() {
    [[ -f $RUNTIME_FILE ]] && source "$RUNTIME_FILE"
    return 0
}
runtime_set() { (
    umask 077
    printf '%s=%q\n' "$1" "$2" >>"$RUNTIME_FILE"
); }
is_done() { [[ -f $DONE_FILE ]] && grep -qx "$1" "$DONE_FILE"; }
mark_done() { echo "$1" >>"$DONE_FILE"; }

# ── Wizard ──
STEP_N=0
STEP_TOTAL=0
next_step() {
    STEP_N=$((STEP_N + 1))
    if ((STEP_TOTAL > 0)); then
        header "$1" "Step $STEP_N of $STEP_TOTAL" "$STEP_N" "$STEP_TOTAL"
    elif ((STEP_TOTAL < 0)); then
        header "$1" "Editing"
    else header "$1" "Step $STEP_N"; fi
}

wz_welcome() {
    cls
    blank
    show_logo
    blank
    printf '  %s' "$ACC2"
    typewrite "Pterodactyl Panel + Wings, the easy way - for Arch Linux"
    printf '%s' "$R"
    blank
    say "Hi! PteroArch installs Pterodactyl: a web panel for running game servers (Minecraft, Rust, Valheim and many more) in Docker containers."
    blank
    kv "Panel" "the website you log into to manage everything"
    kv "Wings" "the helper that actually runs your game servers"
    blank
    title "How this works"
    printf '    %s%s1%s  Answer a few questions %s(about 2 minutes)%s\n' "$B" "$ACC" "$R" "$GRY" "$R"
    printf '    %s%s2%s  Check your answers on a review screen %s(nothing changes before that)%s\n' "$B" "$ACC" "$R" "$GRY" "$R"
    printf '    %s%s3%s  Sit back while PteroArch installs everything %s(5-15 minutes)%s\n' "$B" "$ACC" "$R" "$GRY" "$R"
    blank
    box "$ACC" "Tips" \
        "$I_BUL Press Enter to accept the suggestion shown in [brackets]." \
        "$I_BUL See (?) after a question? Type ? and press Enter for help." \
        "$I_BUL Press Ctrl+C any time to stop. An interrupted install can be resumed."
    if $DRY_RUN; then
        blank
        warn "Dry run: you'll see the full plan at the end, but nothing will be installed."
    fi
    pause "Press Enter to check this machine"

    header "Checking this machine" "Getting ready"
    detect_facts
    preflight
}

PF_FAIL=0
PF_WARN=0
pf() {
    case $1 in
    ok) ok "$2" ;;
    warn)
        warn "$2"
        PF_WARN=$((PF_WARN + 1))
        ;;
    fail)
        err "$2"
        PF_FAIL=1
        ;;
    esac
    [[ -n ${3:-} ]] && hint "$3"
    nap 0.05
    return 0
}

preflight() {
    PF_FAIL=0
    PF_WARN=0
    local soft=fail
    $DRY_RUN && soft=warn

    if [[ $EUID -eq 0 ]]; then pf ok "Running as root"; else pf "$soft" "Not running as root" "Run it with: sudo bash $0"; fi

    local id='' like=''
    if [[ -r /etc/os-release ]]; then
        id=$(
            . /etc/os-release
            echo "${ID:-}"
        )
        like=$(
            . /etc/os-release
            echo "${ID_LIKE:-}"
        )
    fi
    if [[ $id == arch ]]; then
        pf ok "Arch Linux detected"
    elif [[ " $like " == *" arch "* ]]; then
        pf warn "Arch-based distro detected ($id)" "Written for Arch; derivatives with delayed repos (e.g. Manjaro) may lack php-legacy 8.3 or valkey."
    else pf "$soft" "This is not Arch Linux (${id:-unknown})" "This installer only supports Arch Linux."; fi

    if [[ -d /run/systemd/system ]]; then pf ok "systemd is running"; else pf "$soft" "systemd is not running" "Containers without systemd (e.g. plain Docker) aren't supported."; fi

    if [[ -n $WINGS_ARCH ]]; then pf ok "CPU architecture: $(uname -m)"; else pf "$soft" "Unsupported CPU architecture: $(uname -m)" "Wings only ships for x86_64 and aarch64."; fi

    if [[ -e /var/lib/pacman/db.lck ]]; then pf "$soft" "pacman is busy (/var/lib/pacman/db.lck exists)" "Another package install is running. Wait for it to finish, or remove the lock file if nothing is running."; fi

    if spin_run "Checking the internet connection" curl -fsS --max-time 10 -o /dev/null https://github.com; then
        pf ok "Internet connection works"
    else pf "$soft" "Can't reach github.com" "The panel and Wings are downloaded from GitHub. Check the network / DNS settings."; fi

    if ((TOTAL_MEM_MB >= 2048)); then
        pf ok "Memory: ${TOTAL_MEM_MB} MB"
    elif ((TOTAL_MEM_MB >= 1024)); then
        pf warn "Memory: ${TOTAL_MEM_MB} MB" "Enough for the panel; game servers will need more."
    else pf warn "Memory: ${TOTAL_MEM_MB} MB" "Under 1 GB - installing PHP dependencies may run out of memory."; fi

    if ((FREE_ROOT_MB >= 5120)); then
        pf ok "Free disk space: $((FREE_ROOT_MB / 1024)) GB"
    else pf warn "Free disk space: ${FREE_ROOT_MB} MB" "At least 5 GB is recommended, plus space for game servers."; fi

    local virt
    virt=$(systemd-detect-virt 2>/dev/null || true)
    case $virt in
    openvz | lxc | lxc-libvirt) pf warn "Virtualization: $virt" "Docker (and so Wings) usually doesn't work in $virt containers. Panel-only is fine." ;;
    '' | none) pf ok "Running on bare metal" ;;
    *) pf ok "Virtualization: $virt" ;;
    esac

    if $KERNEL_PENDING_REBOOT; then
        pf warn "A newer kernel is installed but not running yet" "Docker and the firewall need the running kernel's modules. Reboot first, then run this again."
    fi

    local p o
    for p in 80 443; do
        o=$(port_owner "$p")
        [[ -n $o && $o != nginx ]] && pf warn "Port $p is already used by '$o'" "The panel's web server needs it."
    done
    for p in 8080 2022; do
        o=$(port_owner "$p")
        [[ -n $o && $o != wings ]] && pf warn "Port $p is already used by '$o'" "Wings uses it by default (you can change Wings' ports later)."
    done

    if [[ -e $PANEL_DIR ]] && ! $OWN_STATE; then pf warn "A panel already exists at $PANEL_DIR" "Panel install options are disabled so it isn't overwritten."; fi
    if [[ -f /etc/pterodactyl/config.yml ]]; then pf warn "Wings is already configured (/etc/pterodactyl/config.yml)"; fi

    PANEL_VERSION=${PANEL_VERSION_OVERRIDE:-}
    if [[ -z $PANEL_VERSION ]]; then
        spin_run "Finding the newest panel release" latest_panel_version
        PANEL_VERSION=$SPIN_OUT
        if [[ -n $PANEL_VERSION ]]; then
            pf ok "Newest panel release: $PANEL_VERSION"
        else
            PANEL_VERSION=$DEFAULT_PANEL_VERSION
            pf warn "Couldn't confirm the newest 1.x release" "Using $PANEL_VERSION. Set PANEL_VERSION=vX.Y.Z to pick another."
        fi
    else
        pf ok "Panel release (from PANEL_VERSION): $PANEL_VERSION"
    fi

    blank
    if ((PF_FAIL)); then die "Fix the problems marked $I_BAD above and run the installer again."; fi
    if ((PF_WARN == 0)); then
        printf '  %s%s Everything looks good!%s\n' "$GRN$B" "$I_OK" "$R"
    else
        printf '  %s%s %d thing(s) to keep in mind%s %s- see the %s notes above.%s\n' "$YEL$B" "$I_WARN" "$PF_WARN" "$R" "$GRY" "$I_WARN" "$R"
    fi
    if $KERNEL_PENDING_REBOOT && ! $DRY_RUN; then
        blank
        if ask_yn "Reboot now? (recommended - afterwards, run this installer again)" Y; then
            say "Rebooting$I_ELL"
            systemctl reboot
            exit 0
        fi
    fi
    pause "Press Enter to start the questions"
}

wz_mode() {
    next_step "What do you want to install?"
    local panel_exists=false
    [[ -e $PANEL_DIR ]] && ! $OWN_STATE && panel_exists=true
    if $panel_exists; then
        warn "A panel already exists at $PANEL_DIR, so only the Wings option is available."
        blank
        choose MODE wings \
            "wings|Wings only - make this machine a node for an existing panel|You'll need access to the panel's admin area." \
            "quit|Quit|"
        [[ $MODE == quit ]] && {
            say "Nothing was changed."
            exit 0
        }
    else
        HELP="Not sure? Pick 1. The 'panel' is the website, 'Wings' is the program that runs the game servers. On a single server you want both. Pick 3 only if you already have a panel running on another machine."
        choose MODE "${MODE:-full}" \
            "full|Panel + Wings on this machine|Everything on one box. The simplest setup - recommended." \
            "panel|Panel only|Run game servers on other machines (install Wings there later with PteroArch)." \
            "wings|Wings only - make this machine a node for an existing panel|You'll need access to the panel's admin area."
    fi
    case $MODE in
    full) STEP_TOTAL=6 ;;
    panel) STEP_TOTAL=5 ;;
    wings) STEP_TOTAL=3 ;;
    esac
}

dns_hint() {
    local ips
    spin_run "Looking up $1" resolve_a "$1"
    ips=$(trim "$SPIN_OUT")
    if [[ -z $ips ]]; then
        warn "$1 doesn't point anywhere yet."
        local target=${PUBLIC_IP:-$PRIMARY_IP}
        hint "Create an A record for it pointing to ${target:-this server} at your domain provider, or Let's Encrypt will fail. DNS changes can take a few minutes."
        return 1
    fi
    local ip match=false
    for ip in $ips; do
        [[ $ip == "$PUBLIC_IP" || " $LOCAL_IPS " == *" $ip "* ]] && match=true
    done
    if $match; then
        ok "$1 points to this server ($ips)"
        return 0
    fi
    warn "$1 points to $ips, but this server is ${PUBLIC_IP:-$PRIMARY_IP}."
    hint "If you use a proxy such as Cloudflare, set it to 'DNS only' (grey cloud): Wings and Let's Encrypt need a direct connection."
    return 1
}

wz_address() {
    next_step "How will people reach the panel?"
    say "A domain name (like panel.example.com) is strongly recommended: it lets PteroArch get a free HTTPS certificate, so passwords are sent encrypted."
    blank
    local kind
    HELP="A domain is a name like panel.example.com that points to your server's IP address. You create it at your domain provider with an 'A record'. No domain? Pick 2 - it works fine for testing at home, just without encryption."
    choose kind "$([[ $PANEL_HOST_IS_IP == true ]] && echo ip || echo domain)" \
        "domain|I have a domain name pointing at this server|" \
        "ip|Use the IP address only|No HTTPS - fine for testing on a home network."
    blank
    if [[ $kind == domain ]]; then
        local prev=''
        is_fqdn "${PANEL_HOST:-x}" && prev=$PANEL_HOST
        PANEL_HOST_IS_IP=false
        while true; do
            HELP="Type just the name, like panel.example.com - no https:// and no slashes. It should already point to this server's public IP address."
            ask PANEL_HOST "Panel domain" "$prev" is_fqdn "Enter a domain like panel.example.com (no http://, no path)."
            PANEL_HOST=${PANEL_HOST,,}
            if dns_hint "$PANEL_HOST"; then break; fi
            ask_yn "Continue with this domain anyway?" N && break
            prev=$PANEL_HOST
        done
        blank
        say "HTTPS with a free Let's Encrypt certificate needs ports 80 and 443 open to the internet."
        HELP="HTTPS encrypts the connection, so nobody can read passwords on the way. Let's Encrypt certificates are free, and PteroArch sets up automatic renewal. Say yes unless this is just a quick test."
        if ask_yn "Get a free Let's Encrypt certificate (HTTPS)?" Y; then
            USE_SSL=true
            HELP="Let's Encrypt only emails you if a certificate is about to expire and renewing it keeps failing. Any address you read works."
            ask LE_EMAIL "Email for certificate notices" "${LE_EMAIL:-${ADMIN_EMAIL:-}}" is_email "Enter a valid email address, like you@example.com."
        else
            USE_SSL=false
            warn "Without HTTPS, passwords travel unencrypted. You can add a certificate later with: certbot --nginx -d $PANEL_HOST"
        fi
    else
        PANEL_HOST_IS_IP=true
        USE_SSL=false
        HELP="This is the address you'll type into your browser. The suggestion is this machine's public IP. On a home network you probably want the local one (like 192.168.1.20)."
        ask PANEL_HOST "IP address of this server" "${PUBLIC_IP:-$PRIMARY_IP}" is_ipv4 "Enter an IPv4 address like 203.0.113.10."
    fi
}

wz_settings() {
    next_step "Panel settings"
    say "Which PHP should the panel run on? Pterodactyl 1.x is officially tested on PHP 8.2 and 8.3."
    HELP="PHP is the language the panel is written in. Pick 1 unless you know you need Arch's newest PHP for something else on this machine."
    choose PHP_FLAVOR "${PHP_FLAVOR:-legacy}" \
        "legacy|php-legacy (PHP 8.3) - recommended|The version the Pterodactyl team tests and uses in its own Docker image." \
        "current|php (PHP 8.5, Arch's main PHP)|Newer, but not tested by the Pterodactyl team."
    set_php_vars
    blank
    say "Timezone for schedules and timestamps. You can type a city, like Warsaw or New York."
    HELP="Used for scheduled tasks (like nightly restarts) and for times shown in the panel. Type a city name and PteroArch finds the full timezone name, or type UTC."
    ask_tz TIMEZONE "${TIMEZONE:-$SYSTEM_TZ}"
    blank
    say "Pterodactyl can send anonymous usage statistics to its developers."
    HELP="If yes, the panel sends anonymous numbers (no personal data) to the Pterodactyl developers to help them improve it. Either answer is fine."
    if ask_yn "Send anonymous usage statistics?" "$([[ $TELEMETRY == 1 ]] && echo Y || echo N)"; then TELEMETRY=1; else TELEMETRY=0; fi
    blank
    say "Email is used for password resets and account invites. You can skip this and set it up later."
    HELP="The panel works fine without email - you just can't send password-reset or invite emails. To set it up later, run: cd $PANEL_DIR && php artisan p:environment:mail"
    if ask_yn "Set up outgoing email (SMTP) now?" "$([[ $MAIL_SETUP == yes ]] && echo Y || echo N)"; then
        MAIL_SETUP=yes
        HELP="Your email provider tells you this, e.g. smtp.gmail.com. Gmail and Outlook need an 'app password' instead of your normal password."
        ask SMTP_HOST "SMTP server" "${SMTP_HOST:-}" is_node_host "Enter a hostname like smtp.example.com."
        HELP="Most providers use tls (port 587). Some use ssl (port 465). 'none' is only for local mail servers."
        ask SMTP_ENC "Encryption (tls / ssl / none)" "${SMTP_ENC:-tls}" is_smtp_enc "Type tls, ssl or none."
        local defport=587
        [[ $SMTP_ENC == ssl ]] && defport=465
        [[ $SMTP_ENC == none ]] && defport=25
        ask SMTP_PORT "SMTP port" "${SMTP_PORT:-$defport}" is_port "Enter a port number, like 587."
        ask_opt SMTP_USER "SMTP username" "${SMTP_USER:-}"
        if [[ -n $SMTP_USER ]]; then ask_password SMTP_PASS "SMTP password" false is_any_pw "The password can't be empty."; else SMTP_PASS=''; fi
        local from_def=${MAIL_FROM:-}
        [[ -z $from_def && $PANEL_HOST_IS_IP == false ]] && from_def="no-reply@$PANEL_HOST"
        ask MAIL_FROM "Send emails from address" "$from_def" is_email "Enter a valid email address."
        ask MAIL_FROM_NAME "Sender name" "${MAIL_FROM_NAME:-Pterodactyl Panel}" is_name "Avoid quotes and backslashes."
    else
        MAIL_SETUP=no
    fi
}

wz_admin() {
    next_step "Your administrator account"
    say "This is the account you'll log into the panel with."
    blank
    ask ADMIN_EMAIL "Email" "${ADMIN_EMAIL:-$LE_EMAIL}" is_email "Enter a valid email address, like you@example.com."
    HELP="You can log in with the username or the email. Usernames are lowercase, at least 3 characters, and may contain . - and _"
    ask ADMIN_USERNAME "Username" "${ADMIN_USERNAME:-admin}" is_username "Use 3+ lowercase letters, numbers, '.', '-' or '_' (start and end with a letter or number)."
    ask ADMIN_FIRST "First name" "${ADMIN_FIRST:-Admin}" is_name "Avoid quotes and backslashes."
    ask ADMIN_LAST "Last name" "${ADMIN_LAST:-User}" is_name "Avoid quotes and backslashes."
    blank
    say "Password: at least 8 characters, with an uppercase letter and a number. Or just press Enter and PteroArch makes a strong one for you."
    HELP="Leave it empty and press Enter to get a strong random password. It's shown at the end and saved in $CRED_FILE (only root can read it)."
    ask_password ADMIN_PASSWORD "Password" true is_password "Needs 8+ characters, including an uppercase letter and a number."
    ADMIN_PASSWORD_GENERATED=$PW_WAS_GENERATED
    [[ -z $LE_EMAIL ]] && LE_EMAIL=$ADMIN_EMAIL
    return 0
}

wz_node() {
    next_step "Game server node (Wings on this machine)"
    say "PteroArch will register this machine in the panel as a 'node' (a machine that runs game servers), configure Wings, and start it."
    blank
    HELP="Just a label you'll see in the panel. The machine's hostname is a good choice."
    ask NODE_NAME "Node name" "${NODE_NAME:-$(cut -c1-60 /proc/sys/kernel/hostname 2>/dev/null || echo local)}" is_node_name "Letters, numbers, spaces, '.', '-' and '_' only (max 100)."
    is_node_name "$NODE_NAME" || NODE_NAME=local
    HELP="Locations group nodes, for example by city or data center. With a single server, the default is perfect."
    ask NODE_LOCATION "Location code (a short label, e.g. eu1 or home)" "${NODE_LOCATION:-main}" is_loc_short "Letters, numbers, '.', '-' and '_' only (max 60)."
    blank
    local mem_def=$((TOTAL_MEM_MB - 1024))
    ((mem_def < 512)) && mem_def=$TOTAL_MEM_MB
    local disk_def=$((FREE_DISK_MB * 9 / 10))
    ((disk_def < 1024)) && disk_def=1024
    say "How much of this machine may game servers use in total? The panel and database need about 1 GB of RAM for themselves."
    HELP="The panel won't let you create game servers that together use more than this. 1024 MB = 1 GB. You can change it later under Admin > Nodes."
    ask NODE_MEMORY "Memory for game servers (MB)" "${NODE_MEMORY:-$mem_def}" is_pos_int "Enter a number of megabytes, like 4096."
    HELP="Disk space game servers may use together, in megabytes. 10240 MB = 10 GB. You can change it later."
    ask NODE_DISK "Disk for game servers (MB)" "${NODE_DISK:-$disk_def}" is_pos_int "Enter a number of megabytes, like 20480."
    blank
    say "Each game server needs its own network port (an 'allocation'). PteroArch can add a range of them now."
    HELP="Minecraft uses port 25565 by default, so 25565-25600 gives you 36 ports to hand out to game servers. Up to 1000 ports, all above 1024."
    if ask_yn "Add a port range now?" Y; then
        HELP="Format: FROM-TO, for example 25565-25600. Up to 1000 ports, all above 1024."
        ask ALLOC_RANGE "Port range" "${ALLOC_RANGE:-25565-25600}" is_port_range "Use FROM-TO, e.g. 25565-25600 (above 1024, at most 1000 ports)."
        HELP="The address game servers listen on. Use this machine's own address (the suggestion). Behind a home router that's the local address, like 192.168.1.20."
        ask ALLOC_IP "IP that game servers listen on" "${ALLOC_IP:-${PRIMARY_IP:-0.0.0.0}}" is_ipv4 "Enter an IPv4 address of this machine."
        if [[ $ALLOC_IP != 0.0.0.0 && -n $LOCAL_IPS && " $LOCAL_IPS " != *" $ALLOC_IP "* ]]; then
            warn "$ALLOC_IP isn't on any network interface here (${LOCAL_IPS% }). Behind NAT, use the local IP; players connect via the panel host name."
        fi
    else
        ALLOC_RANGE=''
        hint "You can add ports later under Admin > Nodes > your node > Allocation."
    fi
    if [[ $USE_SSL == true ]]; then
        blank
        info "Wings will use $PANEL_HOST with the same certificate as the panel."
    fi
}

parse_deploy_cmd() {
    local s=$1
    s=${s//\"/}
    s=${s//\'/}
    [[ $s =~ --panel-url[=[:space:]]+([^[:space:]]+) ]] && W_PANEL_URL=${BASH_REMATCH[1]%/}
    [[ $s =~ --token[=[:space:]]+([^[:space:]]+) ]] && W_TOKEN=${BASH_REMATCH[1]}
    [[ $s =~ --node[=[:space:]]+([0-9]+) ]] && W_NODE_ID=${BASH_REMATCH[1]}
    is_url "${W_PANEL_URL:-x}" && is_token "${W_TOKEN:-x}" && [[ -n ${W_NODE_ID:-} ]]
}

wz_wings_remote() {
    next_step "Connect this machine to your panel"
    box "$ACC" "Before you continue" \
        "In your panel, create the node first:" \
        "1. Admin > Locations - create one if you have none" \
        "2. Admin > Nodes > Create New - use this machine's domain as the FQDN, and pick 'Use SSL Connection' if your panel uses HTTPS"
    blank
    HELP="The address the panel and your players' browsers use to reach this machine. Enter exactly what you put in the node's FQDN field in the panel."
    ask W_FQDN "This node's domain (or IP if the node doesn't use SSL)" "${W_FQDN:-${PUBLIC_IP:-$PRIMARY_IP}}" \
        is_node_host "Enter a domain like node1.example.com, or an IPv4 address."
    W_FQDN=${W_FQDN,,}
    if is_fqdn "$W_FQDN"; then
        dns_hint "$W_FQDN" || true
        blank
        say "If the node uses SSL in the panel (needed when the panel uses HTTPS), Wings needs a certificate for $W_FQDN. Port 80 must be reachable for Let's Encrypt."
        HELP="Say yes if you ticked 'Use SSL Connection' for this node in the panel. Browsers refuse to talk to an unencrypted node from an HTTPS panel."
        if ask_yn "Get a free Let's Encrypt certificate for $W_FQDN?" "$([[ $W_SSL == false ]] && echo N || echo Y)"; then
            W_SSL=true
            ask LE_EMAIL "Email for certificate notices" "${LE_EMAIL:-}" is_email "Enter a valid email address."
        else
            W_SSL=false
        fi
    else
        W_SSL=false
        warn "With an IP address the node can't use SSL. That only works if your panel also runs over plain HTTP."
    fi
    blank
    HELP="Only change these if you changed them on the node in the panel. The defaults are 8080 and 2022."
    ask WINGS_PORT "Wings API port (as set on the node)" "${WINGS_PORT:-8080}" is_port "Enter a port number."
    ask SFTP_PORT "Wings SFTP port (as set on the node)" "${SFTP_PORT:-2022}" is_port "Enter a port number."
    blank
    say "How should Wings get its configuration?"
    HELP="The auto-deploy command is the easiest: in your panel go to Admin > Nodes > (this node) > Configuration > Generate Token, copy the whole command and paste it here."
    choose W_CONFIG_METHOD "${W_CONFIG_METHOD:-deploy}" \
        "deploy|Paste the auto-deploy command (recommended)|Panel: Admin > Nodes > your node > Configuration > Generate Token. It looks like: wings configure --panel-url ... --token ... --node ..." \
        "paste|Paste the configuration file|Copy the YAML from the node's Configuration tab." \
        "later|Skip - I'll put /etc/pterodactyl/config.yml in place myself|Wings is installed but not started."
    blank
    case $W_CONFIG_METHOD in
    deploy)
        local line
        while true; do
            prompt_line "Paste the command" "" ""
            read_line line
            if parse_deploy_cmd "$line"; then
                ok "Got it: panel $W_PANEL_URL, node #$W_NODE_ID"
                if spin_run "Contacting the panel" curl -fsS --max-time 10 -o /dev/null "$W_PANEL_URL"; then
                    ok "The panel is reachable from here."
                else warn "Couldn't reach $W_PANEL_URL from this machine. Wings must be able to reach it."; fi
                break
            fi
            err "Couldn't find --panel-url, --token and --node in that. Copy the whole command from the panel."
        done
        ;;
    paste)
        info "Paste the YAML, then type END on its own line and press Enter:"
        local text='' l
        while IFS= read -r l <"$TTY"; do
            [[ $l == END ]] && break
            text+="$l"$'\n'
        done
        if [[ $text != *"token:"* || $text != *"remote:"* ]]; then
            warn "That doesn't look like a Wings config (no 'token:' / 'remote:'). You can change it on the review screen."
        else
            ok "Configuration received ($(printf '%s' "$text" | wc -l) lines)."
        fi
        W_CONFIG_TEXT=$text
        ;;
    later) ;;
    esac
    W_OVERRIDE=false
    if [[ -f /etc/pterodactyl/config.yml && $W_CONFIG_METHOD != later ]]; then
        blank
        if ask_yn "An existing /etc/pterodactyl/config.yml will be replaced. OK?" N; then
            W_OVERRIDE=true
        else
            W_CONFIG_METHOD=later
            warn "Keeping the existing configuration."
        fi
    fi
    blank
    HELP="Players connect to game servers on these ports. Use the same range you set up under the node's Allocation tab in the panel."
    if ask_yn "Open a port range for game servers in the firewall?" "$([[ -n $FW_GAME_RANGE ]] && echo Y || echo N)"; then
        ask FW_GAME_RANGE "Port range" "${FW_GAME_RANGE:-25565-25600}" is_port_range "Use FROM-TO, e.g. 25565-25600."
    else
        FW_GAME_RANGE=''
    fi
}

fw_ports_list() {
    local l="SSH ${SSH_PORT}/tcp"
    if has_panel; then
        l+=", HTTP 80"
        [[ $USE_SSL == true ]] && l+=", HTTPS 443"
    fi
    if [[ $MODE == wings && $W_SSL == true ]]; then l+=", HTTP 80 (certificate renewals)"; fi
    if has_wings; then l+=", Wings ${WINGS_PORT}, SFTP ${SFTP_PORT}"; fi
    local gr=$ALLOC_RANGE
    [[ $MODE == wings ]] && gr=$FW_GAME_RANGE
    [[ -n $gr ]] && l+=", games ${gr} (tcp+udp)"
    printf '%s' "$l"
}

wz_firewall() {
    next_step "Firewall"
    local active=''
    systemctl is-active --quiet firewalld 2>/dev/null && active=firewalld
    if [[ -z $active ]] && command -v ufw >/dev/null 2>&1; then
        local st
        st=$(ufw status 2>/dev/null || true)
        [[ $st == *"Status: active"* ]] && active=ufw
    fi
    say "A firewall blocks every incoming connection except the ones you allow. Arch has none by default; PteroArch can set one up that only allows what Pterodactyl needs."
    [[ -n $active ]] && {
        blank
        ok "$active is already active - the needed ports will be added to it."
    }
    blank
    HELP="SSH is how you log into this server remotely. This port stays open so you don't lock yourself out. The suggestion is the port you're connected on right now."
    ask SSH_PORT "SSH port to keep open (so you don't lock yourself out)" "${SSH_PORT:-${SSH_DETECTED:-22}}" is_port "Enter a port number, usually 22."
    blank
    HELP="ufw is a simple, popular firewall. Pick 'Don't touch' if your hosting provider already filters traffic, or if you manage nftables/iptables yourself."
    if [[ $active == firewalld ]]; then
        choose FW "${FW:-firewalld}" "firewalld|Add the ports to firewalld|" "none|Don't touch the firewall|"
    else
        choose FW "${FW:-${active:-ufw}}" \
            "ufw|Use ufw$([[ $active == ufw ]] && echo ' (already active)' || echo ' (installs it)')|Allows only the ports listed below; everything else incoming is blocked." \
            "none|Don't touch the firewall|Choose this if you manage nftables/iptables yourself or your host has a firewall."
    fi
    blank
    dim "Ports: $(fw_ports_list)"
    if [[ $FW != none ]] && has_wings; then
        dim "Note: Docker publishes game-server ports itself, so they're reachable even where the firewall would block them."
    fi
}

wizard_steps() {
    STEP_N=0
    wz_mode
    case $MODE in
    full)
        wz_address
        wz_settings
        wz_admin
        wz_node
        wz_firewall
        ;;
    panel)
        wz_address
        wz_settings
        wz_admin
        wz_firewall
        ;;
    wings)
        wz_wings_remote
        wz_firewall
        ;;
    esac
}

mask() { [[ -n $1 ]] && echo "$(repeat "$I_BUL" 8) (hidden)" || echo "-"; }

sec() {
    blank
    if $USE_COLOR; then
        printf '  %s %d %s %s%s%s\n' "$BADGE" "$1" "$R" "$B" "$2" "$R"
    else printf '  [%d] %s\n' "$1" "$2"; fi
}

review() {
    while true; do
        header "Review - nothing has been changed yet" "Almost there"
        say "Here's everything PteroArch will set up. Want to change something? Type its number."
        sec 1 "Install type"
        kv "Components" "$(mode_label)"
        has_panel && kv "Panel release" "$PANEL_VERSION"
        has_wings && kv "Wings release" "latest"
        local n=2
        if has_panel; then
            sec 2 "Panel address"
            kv "URL" "${ACC2}$(panel_url)${R}"
            kv "HTTPS" "$([[ $USE_SSL == true ]] && echo "Let's Encrypt ($LE_EMAIL)" || echo "no")"
            sec 3 "Panel settings"
            kv "PHP" "$([[ $PHP_FLAVOR == current ]] && echo "php (8.5)" || echo "php-legacy (8.3)")"
            kv "Timezone" "$TIMEZONE"
            kv "Statistics" "$([[ $TELEMETRY == 1 ]] && echo on || echo off)"
            if [[ $MAIL_SETUP == yes ]]; then kv "Email" "$SMTP_HOST:$SMTP_PORT ($SMTP_ENC), from $MAIL_FROM"; else kv "Email" "not configured"; fi
            kv "Database" "MariaDB, database 'panel' (password generated)"
            sec 4 "Administrator"
            kv "Username" "$ADMIN_USERNAME"
            kv "Email" "$ADMIN_EMAIL"
            kv "Name" "$ADMIN_FIRST $ADMIN_LAST"
            kv "Password" "$([[ $ADMIN_PASSWORD_GENERATED == true ]] && echo "generated - shown at the end" || mask "$ADMIN_PASSWORD")"
            n=5
        fi
        if [[ $MODE == full ]]; then
            sec 5 "Node"
            kv "Name / location" "$NODE_NAME / $NODE_LOCATION"
            kv "Address" "$([[ $USE_SSL == true ]] && echo https || echo http)://$PANEL_HOST:$WINGS_PORT (SFTP $SFTP_PORT)"
            kv "Memory / disk" "${NODE_MEMORY} MB / ${NODE_DISK} MB"
            kv "Ports" "$([[ -n $ALLOC_RANGE ]] && echo "$ALLOC_RANGE on $ALLOC_IP" || echo "none yet")"
            n=6
        elif [[ $MODE == wings ]]; then
            sec 2 "Node"
            kv "Node address" "$W_FQDN"
            kv "Certificate" "$([[ $W_SSL == true ]] && echo "Let's Encrypt ($LE_EMAIL)" || echo "none")"
            kv "Ports" "Wings $WINGS_PORT, SFTP $SFTP_PORT"
            case $W_CONFIG_METHOD in
            deploy) kv "Configuration" "auto-deploy from $W_PANEL_URL (node #$W_NODE_ID)" ;;
            paste) kv "Configuration" "pasted YAML ($(printf '%s' "$W_CONFIG_TEXT" | wc -l) lines)" ;;
            later) kv "Configuration" "you'll add it yourself; Wings won't be started" ;;
            esac
            n=3
        fi
        sec "$n" "Firewall"
        if [[ $FW == none ]]; then
            kv "Firewall" "leave as is"
            kv "Open these yourself" "$(fw_ports_list)"
        else
            kv "Firewall" "$FW"
            kv "Open ports" "$(fw_ports_list)"
        fi
        blank
        rule
        dim "The install starts with a full system upgrade (pacman -Syu), because Arch doesn't support partial upgrades."
        blank
        printf '  %s%s Enter%s start installing   %s1-%d%s change a section   %sq%s quit\n' "$GRN$B" "$I_ENTER" "$R" "$ACC$B" "$n" "$R" "$ACC$B" "$R"
        prompt_line "Your choice" "Enter" ""
        local ans
        read_line ans
        ans=$(trim "$ans")
        case $ans in
        '') return 0 ;;
        q | Q)
            blank
            if ask_yn "Quit without installing anything?" N; then
                blank
                say "No problem - nothing was changed. See you next time!"
                exit 0
            fi
            ;;
        1)
            local old=$MODE
            STEP_TOTAL=-1
            STEP_N=0
            wz_mode
            if [[ $MODE != "$old" ]]; then wizard_rest; fi
            ;;
        *)
            STEP_TOTAL=-1
            STEP_N=0
            case "$MODE:$ans" in
            full:2 | panel:2) wz_address ;;
            full:3 | panel:3) wz_settings ;;
            full:4 | panel:4) wz_admin ;;
            full:5) wz_node ;;
            full:6 | panel:5) wz_firewall ;;
            wings:2) wz_wings_remote ;;
            wings:3) wz_firewall ;;
            *)
                err "Type a number from 1 to $n, press Enter, or q."
                sleep 1
                ;;
            esac
            ;;
        esac
    done
}

wizard_rest() {
    local total=$STEP_TOTAL
    case $MODE in
    full) total=6 ;;
    panel) total=5 ;;
    wings) total=3 ;;
    esac
    STEP_TOTAL=$total
    STEP_N=1
    case $MODE in
    full)
        wz_address
        wz_settings
        wz_admin
        wz_node
        wz_firewall
        ;;
    panel)
        wz_address
        wz_settings
        wz_admin
        wz_firewall
        ;;
    wings)
        wz_wings_remote
        wz_firewall
        ;;
    esac
}

# ── Task engine ──
TASK_IDS=()
TASK_TITLES=()
TASK_FNS=()
TASK_EST=()
add_task() {
    TASK_IDS+=("$1")
    TASK_TITLES+=("$2")
    TASK_FNS+=("$3")
    TASK_EST+=("${4:-}")
}

build_tasks() {
    TASK_IDS=()
    TASK_TITLES=()
    TASK_FNS=()
    TASK_EST=()
    add_task packages "Upgrade the system and install packages" t_packages "2-10 min"
    [[ $FW != none ]] && add_task firewall "Configure the firewall ($FW)" t_firewall
    if has_panel; then
        add_task php "Configure PHP" t_php
        add_task mariadb "Set up MariaDB and the panel database" t_mariadb
        add_task valkey "Start Valkey (Redis)" t_valkey
        add_task panel_dl "Download Pterodactyl Panel $PANEL_VERSION" t_panel_download "under a minute"
        add_task composer "Install the panel's PHP dependencies" t_composer "2-5 min"
        add_task panel_cfg "Configure the panel and create your admin account" t_panel_configure "about a minute"
        add_task workers "Set up the queue worker and scheduler" t_workers
        add_task nginx "Configure Nginx" t_nginx
        [[ $USE_SSL == true ]] && add_task ssl "Get a Let's Encrypt certificate" t_ssl "under a minute"
    fi
    if has_wings; then
        add_task docker "Start Docker" t_docker
        add_task wings_bin "Install Wings" t_wings_bin "under a minute"
        if [[ $MODE == full ]]; then
            add_task node "Create the node and generate Wings' configuration" t_node
        else
            [[ $W_CONFIG_METHOD != later ]] && add_task wings_cfg "Write Wings' configuration" t_wings_config
            [[ $W_SSL == true ]] && add_task wings_ssl "Get a Let's Encrypt certificate for $W_FQDN" t_wings_ssl "under a minute"
        fi
        add_task wings_start "Start Wings" t_wings_start
    fi
}

note() {
    echo ">> $*"
    printf '%s' "$*" >"$STATUS_FILE" 2>/dev/null || true
}

spinner() {
    local pid=$1 idx=$2 total=$3 ttl=$4 est=$5 i=0 drawn=false t0=$SECONDS
    local w=$((COLS - 20))
    ((w < 10)) && w=10
    local seg_a=$((w * (idx - 1) / total)) seg_b=$((w * idx / total))
    local el tstr sub frame t avail line1 bar p maxt
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        el=$((SECONDS - t0))
        tstr=$(fmt_time "$el")
        sub=$(cat "$STATUS_FILE" 2>/dev/null || true)
        [[ -z $sub && -n $est ]] && sub="usually $est"
        frame=${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}
        t=$ttl
        maxt=$((COLS - 10 - ${#tstr}))
        ((${#t} > maxt)) && t="${t:0:$((maxt - ${#I_ELL}))}$I_ELL"
        avail=$((COLS - 2 - 2 - ${#t} - 2 - ${#tstr} - 4))
        if ((avail < 8)); then
            sub=''
        elif ((${#sub} > avail)); then sub="${sub:0:$((avail - ${#I_ELL}))}$I_ELL"; fi
        line1="${ACC2}${frame}${R} ${B}${t}${R}  ${GRY}${sub:+$sub $I_DOT }${tstr}${R}"
        bar="${BAR_ON}$(repeat "$BAR_F" "$seg_a")"
        for ((p = seg_a; p < seg_b; p++)); do
            if ((((p - i % 4 + 4) % 4) < 2)); then bar+="${ACC2}${BAR_F}"; else bar+="${BAR_OFF}${BAR_E}"; fi
        done
        bar+="${BAR_OFF}$(repeat "$BAR_E" $((w - seg_b)))${R}"
        $drawn && printf '\e[1A'
        printf '\r\e[K  %s\n\r\e[K    %s %s%d/%d%s' "$line1" "$bar" "$GRY" $((idx - 1)) "$total" "$R"
        drawn=true
        i=$((i + 1))
        sleep 0.1
    done
    $drawn && printf '\r\e[K\e[1A\r\e[K'
    printf '\e[?25h'
}

done_line() {
    local kind=$1 idx=$2 total=$3 ttl=$4 secs=${5:-} icon c right='' cnt dots
    case $kind in
    ok) icon=$I_OK c=$GRN ;;
    bad) icon=$I_BAD c=$RED ;;
    skip) icon=$I_SKIP c=$YEL ;;
    old) icon=$I_OK c=$GRY ;;
    esac
    [[ -n $secs ]] && right=$(fmt_time "$secs")
    [[ $kind == old ]] && right="done earlier"
    cnt="$idx/$total"
    dots=$((COLS - 2 - ${#icon} - 1 - ${#ttl} - 2 - ${#cnt} - 1 - ${#right} - 2))
    ((dots < 1)) && dots=1
    if [[ $kind == old ]]; then
        printf '  %s%s %s %s %s %s%s\n' "$GRY" "$icon" "$ttl" "$(repeat "$I_DOT" "$dots")" "$cnt" "$right" "$R"
    else
        printf '  %s%s%s %s %s%s %s %s%s\n' "$c" "$icon" "$R" "$ttl" "$GRY" "$(repeat "$I_DOT" "$dots")" "$cnt" "$right" "$R"
    fi
}

CHILD_PID=''
run_task() {
    local idx=$1 total=$2 id=$3 ttl=$4 fn=$5 est=$6 rc start_line t0
    while true; do
        start_line=$(wc -l <"$LOG_FILE")
        printf '\n===== %s  %s (%s) =====\n' "$(date '+%F %T')" "$ttl" "$id" >>"$LOG_FILE"
        : >"$STATUS_FILE"
        t0=$SECONDS
        if $VERBOSE || ! $ANIM; then
            printf '  %s%s%s %s%s%s %s(%d/%d%s)%s\n' "$ACC2" "$I_ARROW" "$R" "$B" "$ttl" "$R" "$GRY" "$idx" "$total" "${est:+, usually $est}" "$R"
            (
                set -Eeuo pipefail
                trap 'echo "!! failed (exit $?) at: $BASH_COMMAND" >&2' ERR
                "$fn"
            ) 2>&1 | tee -a "$LOG_FILE" |
                { if $VERBOSE; then sed "s/^/    ${GRY}${BX_V} /; s/\$/${R}/"; else cat >/dev/null; fi; }
            rc=${PIPESTATUS[0]}
        else
            (
                set -Eeuo pipefail
                trap 'echo "!! failed (exit $?) at: $BASH_COMMAND" >&2' ERR
                "$fn"
            ) >>"$LOG_FILE" 2>&1 </dev/null &
            CHILD_PID=$!
            spinner "$CHILD_PID" "$idx" "$total" "$ttl" "$est"
            wait "$CHILD_PID"
            rc=$?
            CHILD_PID=''
        fi
        local el=$((SECONDS - t0))
        if ((rc == 0)); then
            mark_done "$id"
            load_runtime
            done_line ok "$idx" "$total" "$ttl" "$el"
            return 0
        fi
        done_line bad "$idx" "$total" "$ttl" "$el"
        blank
        local out
        out=$(tail -n +"$((start_line + 3))" "$LOG_FILE" | tail -n 12 | cut -c1-$((COLS - 10)))
        box "$RED" "This step failed - here's what it printed" "${out:-"(no output)"}"
        local h
        h=$(hint_for "$id")
        [[ -n $h ]] && {
            blank
            box "$YEL" "What usually helps" "$h"
        }
        blank
        local act
        while true; do
            choose act retry \
                "retry|Try again|Fix the cause first (a second terminal is handy), then retry." \
                "skip|Skip this step and continue|Later steps may fail if they depend on it." \
                "log|Show the full output of this step|" \
                "quit|Stop for now|Your answers are saved - run PteroArch again later to resume."
            case $act in
            log)
                tail -n +"$((start_line + 1))" "$LOG_FILE" | less -R 2>/dev/null || tail -n +"$((start_line + 1))" "$LOG_FILE"
                continue
                ;;
            *) break ;;
            esac
        done
        case $act in
        retry)
            blank
            continue
            ;;
        skip)
            done_line skip "$idx" "$total" "$ttl (skipped)"
            echo "skipped:$id" >>"$DONE_FILE"
            return 0
            ;;
        quit)
            blank
            info "Stopped. Your answers are saved - run PteroArch again to continue where you left off."
            hint "Full log: $LOG_FILE"
            exit 1
            ;;
        esac
    done
}

hint_for() {
    case $1 in
    packages) echo "Common causes: outdated mirrors (refresh them with 'reflector' or edit /etc/pacman.d/mirrorlist), a full disk, or a package conflict pacman wants you to confirm. Running 'pacman -Syu' yourself shows the question." ;;
    mariadb) echo "If MariaDB's root user has a password, put it in /root/.my.cnf (a [client] section with password=...) and try again." ;;
    composer) echo "Usually a missing PHP extension or too little memory. The output above names the extension." ;;
    ssl | wings_ssl) echo "Let's Encrypt must reach this machine on port 80 at the domain you entered. Check the domain's A record, your provider's firewall, and that Cloudflare proxying is off. 'Skip' leaves HTTPS unconfigured; you can fix it later with certbot." ;;
    wings_start) echo "Check 'journalctl -u wings -n 50'. Wings must be able to reach the panel URL, and its certificate files must exist." ;;
    firewall) echo "If kernel modules are missing, the kernel was probably upgraded: reboot and run PteroArch again - it continues where it stopped." ;;
    docker) echo "If the kernel was upgraded during this install, reboot and run PteroArch again - it continues where it stopped." ;;
    esac
    return 0
}

run_all_tasks() {
    local total=${#TASK_IDS[@]} i done_count=0
    load_runtime
    INSTALL_T0=$SECONDS
    for ((i = 0; i < total; i++)); do is_done "${TASK_IDS[i]}" && done_count=$((done_count + 1)); done
    header "Installing" "$total steps"
    if ((done_count > 0)); then
        info "Welcome back! $done_count finished step(s) will be skipped."
        blank
    fi
    box "$ACC" "" \
        "Sit back - this usually takes 5-15 minutes. Please keep this window open." \
        "Curious? Watch the details in a second terminal: tail -f $LOG_FILE"
    blank
    for ((i = 0; i < total; i++)); do
        local id=${TASK_IDS[i]}
        if is_done "$id"; then
            done_line old $((i + 1)) "$total" "${TASK_TITLES[i]}"
            continue
        fi
        if grep -qx "skipped:$id" "$DONE_FILE" 2>/dev/null; then
            info "Skipped last time - trying \"${TASK_TITLES[i]}\" again."
            sed -i "/^skipped:$id\$/d" "$DONE_FILE"
        fi
        run_task $((i + 1)) "$total" "$id" "${TASK_TITLES[i]}" "${TASK_FNS[i]}" "${TASK_EST[i]}"
        [[ $id == packages ]] && after_packages
    done
}

after_packages() {
    if [[ ! -d /usr/lib/modules/$(uname -r) ]] && { has_wings || [[ $FW != none ]]; }; then
        blank
        box "$YEL" "A reboot is needed" \
            "The upgrade installed a new kernel. Docker and the firewall need a reboot to load their kernel modules." \
            "After the reboot, run PteroArch again - it continues right where it stopped."
        if ask_yn "Reboot now?" Y; then
            say "Rebooting$I_ELL see you in a minute! Then run: sudo bash $0"
            sleep 2
            systemctl reboot
            exit 0
        fi
        warn "Continuing without a reboot - the firewall or Docker steps may fail."
    fi
}

on_interrupt() {
    if [[ -n $CHILD_PID ]]; then
        pkill -TERM -P "$CHILD_PID" 2>/dev/null
        kill "$CHILD_PID" 2>/dev/null
    fi
    stty echo <"$TTY" 2>/dev/null
    printf '%s\e[?25h\n' "$R"
    if [[ -f $ANSWERS_FILE ]]; then
        warn "Stopped. Run PteroArch again to continue where you left off."
    else
        warn "Cancelled - nothing was changed."
    fi
    exit 130
}

# ── Tasks ──
art() {
    mkdir -p "$ART_HOME"
    chown "$WEB_USER:$WEB_USER" "$ART_HOME"
    (cd "$PANEL_DIR" && runuser -u "$WEB_USER" -- env HOME="$ART_HOME" "$PHP_BIN" artisan "$@")
}
sql() { mariadb -N -B -u root -e "$1"; }

set_env() {
    local f=$PANEL_DIR/.env
    if grep -q "^$1=" "$f"; then sed -i "s|^$1=.*|$1=$2|" "$f"; else echo "$1=$2" >>"$f"; fi
}

t_packages() {
    local -a pkgs=(curl tar unzip openssl ca-certificates iproute2 less)
    if has_panel; then
        pkgs+=(nginx mariadb valkey "${PHP_PKGS[@]}")
        [[ $USE_SSL == true ]] && pkgs+=(certbot certbot-nginx)
    fi
    if has_wings; then pkgs+=(docker); fi
    [[ $MODE == wings && $W_SSL == true ]] && pkgs+=(certbot)
    [[ $FW == ufw ]] && pkgs+=(ufw)
    [[ $FW == firewalld ]] && pkgs+=(firewalld)
    note "pacman -Syu + ${#pkgs[@]} packages"
    pacman -Syu --noconfirm --needed "${pkgs[@]}"
}

t_firewall() {
    local -a tcp=("$SSH_PORT")
    if has_panel; then
        tcp+=(80)
        [[ $USE_SSL == true ]] && tcp+=(443)
    fi
    [[ $MODE == wings && $W_SSL == true ]] && tcp+=(80)
    has_wings && tcp+=("$WINGS_PORT" "$SFTP_PORT")
    local gr=$ALLOC_RANGE
    [[ $MODE == wings ]] && gr=$FW_GAME_RANGE
    local p
    if [[ $FW == ufw ]]; then
        note "Adding ufw rules"
        ufw default deny incoming
        ufw default allow outgoing
        for p in "${tcp[@]}"; do ufw allow "$p/tcp"; done
        if [[ -n $gr ]]; then
            ufw allow "${gr/-/:}/tcp"
            ufw allow "${gr/-/:}/udp"
        fi
        note "Enabling ufw"
        ufw --force enable
        systemctl enable ufw
        ufw status verbose
    else
        note "Adding firewalld rules"
        systemctl enable --now firewalld
        for p in "${tcp[@]}"; do firewall-cmd --permanent --add-port="$p/tcp"; done
        if [[ -n $gr ]]; then
            firewall-cmd --permanent --add-port="$gr/tcp"
            firewall-cmd --permanent --add-port="$gr/udp"
        fi
        firewall-cmd --reload
        firewall-cmd --list-all
    fi
}

t_php() {
    local ini=$PHP_CONF_D/90-pterodactyl.ini ext
    mkdir -p "$PHP_CONF_D"
    : >"$ini"
    local mods
    mods=$("$PHP_BIN" -m 2>/dev/null)
    {
        echo "; Managed by PteroArch"
        for ext in bcmath curl gd iconv intl mysqli pdo_mysql sockets sodium zip; do
            grep -qix "$ext" <<<"$mods" || echo "extension=$ext"
        done
        grep -qi '^Zend OPcache$' <<<"$mods" || echo "zend_extension=opcache"
        echo "memory_limit = 256M"
        echo "session.upload_progress.enabled = Off"
    } >"$ini.new"
    mv "$ini.new" "$ini"
    cat "$ini"
    note "Checking PHP extensions"
    local ver
    ver=$("$PHP_BIN" -v 2>&1)
    if grep -qi 'warning' <<<"$ver"; then
        echo "$ver"
        echo "PHP prints warnings - check $ini and php.ini"
        return 1
    fi
    mods=$("$PHP_BIN" -m)
    local missing=()
    for ext in bcmath ctype curl dom fileinfo gd iconv intl mbstring mysqli openssl pdo_mysql posix sockets sodium tokenizer xml zip; do
        grep -qix "$ext" <<<"$mods" || missing+=("$ext")
    done
    if ((${#missing[@]})); then
        echo "Missing PHP extensions: ${missing[*]}"
        return 1
    fi
    "$PHP_BIN" -v
    note "Starting $FPM_SERVICE"
    systemctl enable "$FPM_SERVICE"
    systemctl restart "$FPM_SERVICE"
}

t_mariadb() {
    if [[ ! -d /var/lib/mysql/mysql ]]; then
        note "Initialising MariaDB"
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
    mkdir -p /etc/my.cnf.d
    cat >/etc/my.cnf.d/zz-pterodactyl.cnf <<'EOF'
# Managed by PteroArch
[mysqld]
bind-address = 127.0.0.1
EOF
    note "Starting MariaDB"
    systemctl enable mariadb
    systemctl restart mariadb
    local i
    for i in $(seq 1 30); do
        mariadb -u root -e 'SELECT 1' >/dev/null 2>&1 && break
        sleep 1
    done
    if ! mariadb -u root -e 'SELECT 1' >/dev/null; then
        echo "Can't log into MariaDB as root through the local socket."
        return 1
    fi
    note "Creating database and user"
    mariadb -u root <<SQL
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
}

t_valkey() {
    systemctl enable valkey
    systemctl restart valkey
    sleep 1
    valkey-cli ping
}

t_panel_download() {
    local tmp
    tmp=$(mktemp -d)
    note "Downloading panel.tar.gz"
    curl -fL --retry 3 -o "$tmp/panel.tar.gz" "https://github.com/pterodactyl/panel/releases/download/${PANEL_VERSION}/panel.tar.gz"
    mkdir -p "$PANEL_DIR"
    note "Extracting"
    tar -xzf "$tmp/panel.tar.gz" -C "$PANEL_DIR"
    rm -rf "$tmp"
    chmod -R 755 "$PANEL_DIR"/storage/* "$PANEL_DIR"/bootstrap/cache/
    [[ -f $PANEL_DIR/.env ]] || cp "$PANEL_DIR/.env.example" "$PANEL_DIR/.env"
    chmod 640 "$PANEL_DIR/.env"
}

t_composer() {
    mkdir -p "$TOOLS_DIR"
    note "Downloading Composer"
    curl -fsSL --retry 3 -o "$TOOLS_DIR/composer.phar.new" https://getcomposer.org/download/latest-stable/composer.phar
    local expected
    expected=$(curl -fsSL --retry 3 https://getcomposer.org/download/latest-stable/composer.phar.sha256 | awk '{print $1}')
    echo "$expected  $TOOLS_DIR/composer.phar.new" | sha256sum -c -
    mv "$TOOLS_DIR/composer.phar.new" "$TOOLS_DIR/composer.phar"
    note "composer install (takes a few minutes)"
    cd "$PANEL_DIR"
    COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/root/.config/composer \
        "$PHP_BIN" "$TOOLS_DIR/composer.phar" install --no-dev --optimize-autoloader --no-interaction --no-progress
    chown -R "$WEB_USER:$WEB_USER" "$PANEL_DIR"
}

t_panel_configure() {
    chown -R "$WEB_USER:$WEB_USER" "$PANEL_DIR"
    if ! grep -q '^APP_KEY=base64:' "$PANEL_DIR/.env"; then
        note "Generating the application key"
        art key:generate --force
    else
        echo "APP_KEY already set - keeping it (it encrypts stored secrets)."
    fi
    note "Writing panel settings"
    art p:environment:setup --no-interaction \
        --author="$ADMIN_EMAIL" --url="$(panel_url)" --timezone="$TIMEZONE" \
        --cache=redis --session=redis --queue=redis \
        --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 \
        --settings-ui=true --telemetry="$TELEMETRY"
    if [[ $TELEMETRY == 1 ]]; then set_env PTERODACTYL_TELEMETRY_ENABLED true; else set_env PTERODACTYL_TELEMETRY_ENABLED false; fi
    note "Writing database settings"
    art p:environment:database --no-interaction \
        --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password="$DB_PASS"
    if [[ $MAIL_SETUP == yes ]]; then
        note "Writing email settings"
        local enc=$SMTP_ENC
        [[ $enc == none ]] && enc=''
        art p:environment:mail --no-interaction --driver=smtp \
            --email="$MAIL_FROM" --from="$MAIL_FROM_NAME" --host="$SMTP_HOST" --port="$SMTP_PORT" \
            --username="$SMTP_USER" --password="$SMTP_PASS" --encryption="$enc"
    fi
    note "Creating database tables (can take a minute)"
    art migrate --seed --force
    note "Creating your admin account"
    local count
    count=$(sql "SELECT COUNT(*) FROM panel.users WHERE username='${ADMIN_USERNAME}' OR email='${ADMIN_EMAIL}'")
    if [[ $count == 0 ]]; then
        art p:user:make --no-interaction --email="$ADMIN_EMAIL" --username="$ADMIN_USERNAME" \
            --name-first="$ADMIN_FIRST" --name-last="$ADMIN_LAST" --password="$ADMIN_PASSWORD" --admin=1
    else
        echo "A user with that username or email already exists - not creating another."
    fi
    chown -R "$WEB_USER:$WEB_USER" "$PANEL_DIR"
    chmod 640 "$PANEL_DIR/.env"
}

t_workers() {
    cat >/etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=network.target valkey.service mariadb.service

[Service]
User=${WEB_USER}
Group=${WEB_USER}
Restart=always
ExecStart=${PHP_BIN} ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    cat >/etc/systemd/system/ptero-schedule.service <<EOF
[Unit]
Description=Pterodactyl scheduler (artisan schedule:run)

[Service]
Type=oneshot
User=${WEB_USER}
Group=${WEB_USER}
ExecStart=${PHP_BIN} ${PANEL_DIR}/artisan schedule:run
EOF
    cat >/etc/systemd/system/ptero-schedule.timer <<'EOF'
[Unit]
Description=Run the Pterodactyl scheduler every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now pteroq.service ptero-schedule.timer
    systemctl restart pteroq.service
    sleep 2
    systemctl is-active pteroq.service
}

t_nginx() {
    mkdir -p /etc/nginx/conf.d
    if ! grep -Eq 'include[[:space:]]+/etc/nginx/conf\.d/\*\.conf' /etc/nginx/nginx.conf; then
        note "Adding conf.d include to nginx.conf"
        [[ -f /etc/nginx/nginx.conf.pre-pterodactyl ]] || cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.pre-pterodactyl
        sed -i -E '0,/^[[:space:]]*http[[:space:]]*\{/s//&\n    include \/etc\/nginx\/conf.d\/*.conf;/' /etc/nginx/nginx.conf
    fi
    note "Writing the site config"
    cat >/etc/nginx/conf.d/pterodactyl.conf <<EOF
# Managed by PteroArch
server {
    listen 80;
    server_name ${PANEL_HOST};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:${FPM_SOCK};
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
}

install_renew_hook() {
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat >/etc/letsencrypt/renewal-hooks/deploy/pterodactyl.sh <<'EOF'
#!/bin/sh
# Managed by PteroArch
systemctl is-active --quiet nginx && systemctl reload nginx
systemctl is-active --quiet wings && systemctl restart wings
exit 0
EOF
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/pterodactyl.sh
    systemctl enable --now certbot-renew.timer
}

t_ssl() {
    note "Requesting a certificate for $PANEL_HOST"
    certbot --nginx --non-interactive --agree-tos --no-eff-email -m "$LE_EMAIL" \
        --cert-name "$PANEL_HOST" -d "$PANEL_HOST" --redirect
    install_renew_hook
    test -f "/etc/letsencrypt/live/$PANEL_HOST/fullchain.pem"
}

t_docker() {
    systemctl enable --now docker
    docker info >/dev/null
    docker info --format 'Docker {{.ServerVersion}}, cgroup v{{.CgroupVersion}}, storage {{.Driver}}'
}

t_wings_bin() {
    note "Downloading Wings"
    curl -fL --retry 3 -o /usr/local/bin/wings.new \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
    chmod 755 /usr/local/bin/wings.new
    /usr/local/bin/wings.new version
    mv /usr/local/bin/wings.new /usr/local/bin/wings
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl/volumes /var/log/pterodactyl
    cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

t_node() {
    local scheme=http
    [[ $USE_SSL == true ]] && scheme=https
    note "Location '$NODE_LOCATION'"
    local loc_id
    loc_id=$(sql "SELECT id FROM panel.locations WHERE short='${NODE_LOCATION}' LIMIT 1")
    if [[ -z $loc_id ]]; then
        art p:location:make --no-interaction --short="$NODE_LOCATION" --long="Created by PteroArch"
        loc_id=$(sql "SELECT id FROM panel.locations WHERE short='${NODE_LOCATION}' LIMIT 1")
    fi
    note "Node '$NODE_NAME'"
    local node_id
    node_id=$(sql "SELECT id FROM panel.nodes WHERE name='${NODE_NAME}' LIMIT 1")
    if [[ -z $node_id ]]; then
        art p:node:make --no-interaction \
            --name="$NODE_NAME" --description="Wings on the panel host" --locationId="$loc_id" \
            --fqdn="$PANEL_HOST" --scheme="$scheme" --public=1 --proxy=0 --maintenance=0 \
            --maxMemory="$NODE_MEMORY" --overallocateMemory=0 --maxDisk="$NODE_DISK" --overallocateDisk=0 \
            --uploadSize=100 --daemonListeningPort="$WINGS_PORT" --daemonSFTPPort="$SFTP_PORT" \
            --daemonBase=/var/lib/pterodactyl/volumes
        node_id=$(sql "SELECT id FROM panel.nodes WHERE name='${NODE_NAME}' LIMIT 1")
    fi
    [[ -n $node_id ]]
    runtime_set NODE_ID "$node_id"
    if [[ -n $ALLOC_RANGE ]]; then
        note "Adding ports $ALLOC_RANGE"
        local alias=''
        [[ $PANEL_HOST_IS_IP == false ]] && alias=$PANEL_HOST
        art tinker --execute="app(\Pterodactyl\Services\Allocations\AssignmentService::class)->handle(\Pterodactyl\Models\Node::findOrFail(${node_id}), ['allocation_ip' => '${ALLOC_IP}', 'allocation_alias' => '${alias}' ?: null, 'allocation_ports' => ['${ALLOC_RANGE}']]); echo 'allocations ok';"
        sql "SELECT COUNT(*) FROM panel.allocations WHERE node_id=${node_id}"
    fi
    note "Writing /etc/pterodactyl/config.yml"
    mkdir -p /etc/pterodactyl
    art p:node:configuration "$node_id" --format=yaml >/etc/pterodactyl/config.yml.new
    grep -q '^token:' /etc/pterodactyl/config.yml.new
    mv /etc/pterodactyl/config.yml.new /etc/pterodactyl/config.yml
    chmod 600 /etc/pterodactyl/config.yml
}

t_wings_config() {
    mkdir -p /etc/pterodactyl
    if [[ $W_CONFIG_METHOD == deploy ]]; then
        note "Fetching the configuration from the panel"
        local -a args=(configure --panel-url "$W_PANEL_URL" --token "$W_TOKEN" --node "$W_NODE_ID")
        [[ $W_OVERRIDE == true ]] && args+=(--override)
        (cd /etc/pterodactyl && /usr/local/bin/wings "${args[@]}")
    else
        printf '%s' "$W_CONFIG_TEXT" >/etc/pterodactyl/config.yml.new
        grep -q 'token:' /etc/pterodactyl/config.yml.new
        mv /etc/pterodactyl/config.yml.new /etc/pterodactyl/config.yml
    fi
    chmod 600 /etc/pterodactyl/config.yml
    local want
    want=$(awk '/^[[:space:]]+cert:/ {print $2; exit}' /etc/pterodactyl/config.yml)
    echo "Certificate path in config: ${want:-none}"
}

t_wings_ssl() {
    local domain=$W_FQDN cfg=/etc/pterodactyl/config.yml
    if [[ -f $cfg ]]; then
        local d
        d=$(sed -n 's#^[[:space:]]*cert:[[:space:]]*/etc/letsencrypt/live/\([^/]*\)/fullchain.pem.*#\1#p' "$cfg" | head -1)
        [[ -n $d ]] && domain=$d
    fi
    note "Requesting a certificate for $domain"
    local -a auth=(--standalone)
    if systemctl is-active --quiet nginx; then
        pacman -S --needed --noconfirm certbot-nginx
        auth=(--nginx)
    fi
    certbot certonly "${auth[@]}" --non-interactive --agree-tos --no-eff-email -m "$LE_EMAIL" \
        --cert-name "$domain" -d "$domain"
    install_renew_hook
}

t_wings_start() {
    local cfg=/etc/pterodactyl/config.yml
    if [[ ! -f $cfg ]]; then
        echo "No $cfg yet - Wings is installed but not started."
        runtime_set WINGS_STATE notconfigured
        return 0
    fi
    local ssl cert
    ssl=$(awk '/^[[:space:]]+ssl:/ {f=1; next} f && /enabled:/ {print $2; exit}' "$cfg")
    cert=$(awk '/^[[:space:]]+cert:/ {print $2; exit}' "$cfg")
    if [[ $ssl == true && ! -f $cert ]]; then
        echo "Wings is set to use SSL but $cert doesn't exist yet."
        runtime_set WINGS_STATE nocert
        return 1
    fi
    if [[ $MODE == full && $PANEL_HOST_IS_IP == false ]]; then
        note "Checking that this machine can reach the panel"
        if ! curl -fsS --max-time 10 -o /dev/null "$(panel_url)/"; then
            if curl -fsS --max-time 10 -o /dev/null --resolve "$PANEL_HOST:443:127.0.0.1" --resolve "$PANEL_HOST:80:127.0.0.1" "$(panel_url)/"; then
                echo "The panel is only reachable locally via 127.0.0.1 (no NAT loopback). Adding an /etc/hosts entry."
                grep -q "$HOSTS_MARK" /etc/hosts || echo "127.0.0.1 $PANEL_HOST $HOSTS_MARK" >>/etc/hosts
            else
                echo "Warning: this machine can't reach $(panel_url) - Wings may fail to start."
            fi
        fi
    fi
    note "Starting Wings"
    systemctl enable wings
    systemctl restart wings
    sleep 6
    if ! systemctl is-active --quiet wings; then
        journalctl -u wings -n 40 --no-pager || true
        return 1
    fi
    runtime_set WINGS_STATE running
    journalctl -u wings -n 15 --no-pager || true
}

# ── Finish ──
HEALTH_BAD=0
HEALTH=()
svc_add() {
    if systemctl is-active --quiet "$1"; then
        HEALTH+=("ok|$2")
    else
        HEALTH+=("bad|$2 ${GRY}(check: systemctl status $1)${R}")
        HEALTH_BAD=$((HEALTH_BAD + 1))
    fi
}

finish() {
    load_runtime
    HEALTH_BAD=0
    HEALTH=()
    local skipped total_time
    skipped=$(grep -c '^skipped:' "$DONE_FILE" 2>/dev/null || true)
    total_time=$(fmt_time $((SECONDS - INSTALL_T0)))

    if has_panel; then
        svc_add nginx "Web server (Nginx)"
        svc_add "$FPM_SERVICE" "PHP"
        svc_add mariadb "Database (MariaDB)"
        svc_add valkey "Cache (Valkey)"
        svc_add pteroq "Queue worker"
        svc_add ptero-schedule.timer "Scheduler"
    fi
    if has_wings; then
        svc_add docker "Docker"
        if [[ ${WINGS_STATE:-} == notconfigured ]]; then
            HEALTH+=("warn|Wings is installed, waiting for /etc/pterodactyl/config.yml")
        else svc_add wings "Wings"; fi
    fi
    [[ $FW == ufw ]] && svc_add ufw "Firewall (ufw)"
    [[ $FW == firewalld ]] && svc_add firewalld "Firewall (firewalld)"

    local code='' wc=''
    if has_panel; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$(panel_url)/auth/login" 2>/dev/null || true)
        [[ $code == 000 && $PANEL_HOST_IS_IP == false ]] && code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
            --resolve "$PANEL_HOST:443:127.0.0.1" --resolve "$PANEL_HOST:80:127.0.0.1" "$(panel_url)/auth/login" 2>/dev/null || true)
        if [[ $code == 200 ]]; then
            HEALTH+=("ok|The panel answers at $(panel_url)")
        else
            HEALTH+=("warn|The panel login page returned HTTP ${code:-nothing}")
            HEALTH_BAD=$((HEALTH_BAD + 1))
        fi
    fi
    if [[ $MODE == full && ${WINGS_STATE:-} == running ]]; then
        local scheme=http
        [[ $USE_SSL == true ]] && scheme=https
        wc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$scheme://$PANEL_HOST:$WINGS_PORT/api/system" 2>/dev/null || true)
        if [[ $wc == 401 ]]; then
            HEALTH+=("ok|Wings answers on port $WINGS_PORT")
        else
            HEALTH+=("warn|Wings returned HTTP ${wc:-nothing} (expected 401)")
            HEALTH_BAD=$((HEALTH_BAD + 1))
        fi
    fi
    ((skipped > 0)) && HEALTH+=("warn|$skipped step(s) were skipped - run PteroArch again to retry them.")

    local all_good=true
    ((skipped > 0 || HEALTH_BAD > 0)) && all_good=false

    if $all_good; then
        header "All done!" "installed in $total_time"
        celebrate
        printf '  %s%s Pterodactyl is installed and running.%s\n' "$GRN$B" "$I_OK" "$R"
    else
        header "Finished, with a few things to check" "took $total_time"
        printf '  %s%s Almost there - look at the items marked %s or %s below.%s\n' "$YEL$B" "$I_WARN" "$I_BAD" "$I_WARN" "$R"
    fi
    blank

    title "Health check"
    local item
    for item in "${HEALTH[@]}"; do
        case ${item%%|*} in
        ok) ok "${item#*|}" ;;
        bad) err "${item#*|}" ;;
        warn) warn "${item#*|}" ;;
        esac
        nap 0.04
    done

    if has_panel; then
        (
            umask 077
            {
                echo "Pterodactyl - installed $(date '+%F %T') by PteroArch"
                echo
                echo "Panel URL       : $(panel_url)"
                echo "Admin username  : $ADMIN_USERNAME"
                echo "Admin email     : $ADMIN_EMAIL"
                echo "Admin password  : $ADMIN_PASSWORD"
                echo
                echo "Database        : panel (user pterodactyl @ 127.0.0.1)"
                echo "DB password     : $DB_PASS"
                echo "Panel directory : $PANEL_DIR   (back up $PANEL_DIR/.env - its APP_KEY decrypts stored secrets)"
            } >"$CRED_FILE"
        )
        blank
        box "$GRN" "Your login" \
            "${GRY}Open     ${R} ${B}${ACC2}$(panel_url)${R}" \
            "${GRY}Username ${R} ${B}${ADMIN_USERNAME}${R}" \
            "${GRY}Password ${R} ${B}${ADMIN_PASSWORD}${R}" \
            "" \
            "Also saved in $CRED_FILE (only root can read it)."
    fi

    blank
    title "Next steps"
    local -a steps=()
    case $MODE in
    full)
        steps+=("Log in and open Admin > Nodes. '$NODE_NAME' should show a green heart.")
        if [[ -z $ALLOC_RANGE ]]; then
            steps+=("Add ports under Admin > Nodes > $NODE_NAME > Allocation.")
        else steps+=("Ports $ALLOC_RANGE are ready for game servers."); fi
        steps+=("Create a server: Admin > Servers > Create New, and pick an egg (a game template, e.g. Minecraft > Paper).")
        ;;
    panel)
        steps+=("Log in, then create a Location and a Node (Admin > Nodes).")
        steps+=("On each game-server machine, run PteroArch and choose 'Wings only'.")
        ;;
    wings)
        if [[ ${WINGS_STATE:-} == notconfigured ]]; then
            steps+=("Put the node's configuration in /etc/pterodactyl/config.yml, then run: systemctl enable --now wings")
        else
            steps+=("In the panel, Admin > Nodes should show this node with a green heart.")
        fi
        steps+=("Add ports for game servers under the node's Allocation tab.")
        ;;
    esac
    local k
    for k in "${!steps[@]}"; do
        printf '    %s%s%d%s  ' "$B" "$ACC" $((k + 1)) "$R"
        printf '%s\n' "${steps[k]}" | fold -s -w $((COLS - 12)) | sed '2,$s/^/       /'
    done
    blank
    title "Handy commands"
    kv "Wings live log" "journalctl -u wings -f"
    kv "Panel status" "systemctl status pteroq"
    kv "Install log" "$LOG_FILE"

    rm -f "$ANSWERS_FILE" "$RUNTIME_FILE" "$STATUS_FILE"
    date '+%F %T' >"$STATE_DIR/completed"
    blank
    $all_good && {
        printf '  %sHappy hosting!%s\n' "$MAG$B" "$R"
        blank
    }
}

print_plan() {
    header "Dry run - here's the plan" "Nothing was changed"
    local i
    for ((i = 0; i < ${#TASK_IDS[@]}; i++)); do
        printf '  %s%s%2d%s  %s' "$B" "$ACC" $((i + 1)) "$R" "${TASK_TITLES[i]}"
        [[ -n ${TASK_EST[i]} ]] && printf '  %s(usually %s)%s' "$GRY" "${TASK_EST[i]}" "$R"
        printf '\n'
    done
    blank
    [[ ${PHP_PKGS+set} == set ]] && has_panel && dim "PHP packages: ${PHP_PKGS[*]}"
    ok "Looks good? Run it for real with: sudo bash $0"
    blank
}

usage() {
    local b='' a='' g='' r=''
    if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
        b=$'\e[1m'
        a=$'\e[38;5;39m'
        g=$'\e[2m'
        r=$'\e[0m'
    fi
    cat <<EOF

  ${b}${a}PteroArch${r} v$INSTALLER_VERSION ${g}- Pterodactyl Panel + Wings installer for Arch Linux${r}

  ${b}Usage${r}
    sudo bash $0 ${g}[options]${r}

  ${b}Options${r}
    ${a}--dry-run${r}     Answer the questions and see the plan. Nothing is installed.
    ${a}--verbose${r}     Show every command's output while installing.
    ${a}--no-color${r}    Plain text without colors (NO_COLOR=1 works too).
    ${a}--no-anim${r}     No spinners or animations.
    ${a}-h, --help${r}    Show this help.

  ${b}Environment${r}
    ${a}PANEL_VERSION${r}=vX.Y.Z   Install this panel release instead of the newest 1.x.

  ${b}Good to know${r}
    ${g}Type ? at any question marked (?) for help.${r}
    ${g}Progress is saved in $STATE_DIR - run it again to resume.${r}
    ${g}Log: $LOG_FILE${r}

EOF
}

# ── Main ──
main() {
    PANEL_VERSION_OVERRIDE=${PANEL_VERSION:-}
    PANEL_VERSION=''
    local a
    for a in "$@"; do
        case $a in
        --dry-run) DRY_RUN=true ;;
        --verbose | -v) VERBOSE=true ;;
        --no-color | --no-colour) NO_COLOR_FLAG=true ;;
        --no-anim | --no-animation | --no-animations) NO_ANIM_FLAG=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $a"
            usage
            exit 2
            ;;
        esac
    done
    [[ -n $PANEL_VERSION_OVERRIDE && ! $PANEL_VERSION_OVERRIDE =~ ^v1\.[0-9]+\.[0-9]+$ ]] && {
        echo "PANEL_VERSION must look like v1.15.2"
        exit 2
    }

    init_ui
    trap restore_tty EXIT
    trap on_interrupt INT TERM

    if ! $DRY_RUN; then
        [[ $EUID -eq 0 ]] || {
            err "PteroArch needs root rights. Run it like this: ${B}sudo bash $0${R}"
            exit 1
        }
        mkdir -p "$STATE_DIR"
        chmod 700 "$STATE_DIR"
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
    fi

    local resuming=false
    if ! $DRY_RUN && [[ -f $ANSWERS_FILE ]]; then
        load_answers
        set_php_vars
        header "Welcome back!" "Unfinished installation found"
        local d=0 t
        [[ -f $DONE_FILE ]] && d=$(grep -vc '^skipped:' "$DONE_FILE" || true)
        say "A previous run stopped part-way ($d step(s) finished). No worries - you can pick up right where it stopped."
        blank
        kv "Install type" "$(mode_label)"
        has_panel && kv "Panel" "$(panel_url)"
        blank
        choose t resume \
            "resume|Continue where it stopped (recommended)|" \
            "restart|Start over with new answers|Your previous answers become the suggestions; parts already installed are reused." \
            "quit|Quit|"
        case $t in
        resume)
            resuming=true
            blank
            detect_facts
            ;;
        restart)
            rm -f "$DONE_FILE" "$RUNTIME_FILE"
            OWN_STATE=true
            ;;
        quit) exit 0 ;;
        esac
    elif ! $DRY_RUN && [[ -f $STATE_DIR/completed && ! -e $PANEL_DIR && ! -f /etc/pterodactyl/config.yml ]]; then
        rm -f "$STATE_DIR/completed"
    fi

    if ! $resuming; then
        wz_welcome
        wizard_steps
        [[ -z $DB_PASS ]] && DB_PASS=$(gen_hex 32)
        set_php_vars
        review
    fi

    build_tasks
    if $DRY_RUN; then
        print_plan
        exit 0
    fi

    save_answers
    : >>"$DONE_FILE"
    {
        echo
        echo "################ PteroArch v$INSTALLER_VERSION - $(date '+%F %T') - mode $MODE ################"
    } >>"$LOG_FILE"
    run_all_tasks
    finish
}

main "$@"
