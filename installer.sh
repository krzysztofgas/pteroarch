#!/usr/bin/env bash
set -uo pipefail

INSTALLER_VERSION="2.0.0"
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

# ── UI helpers ──
init_ui() {
    if [[ -t 1 ]]; then
        B=$'\e[1m'; DIM=$'\e[2m'; R=$'\e[0m'
        RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'
    else
        B=''; DIM=''; R=''; RED=''; GRN=''; YEL=''; CYN=''
    fi
    if [[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *[Uu][Tt][Ff]-8* || "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *[Uu][Tt][Ff]8* ]]; then
        OK_SYM="✓"; BAD_SYM="✗"; WARN_SYM="!"; SPIN_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); DOT="·"
    else
        OK_SYM="OK"; BAD_SYM="X"; WARN_SYM="!"; SPIN_FRAMES=('|' '/' '-' '\'); DOT="-"
    fi
    COLS=$(tput cols 2>/dev/null || echo 80)
    [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
    ((COLS > 100)) && COLS=100
    ((COLS < 50)) && COLS=50
    
    if { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; else TTY=/dev/stdin; fi
}

cls()   { [[ -t 1 ]] && printf '\e[H\e[2J'; return 0; }
rule()  { local l; printf -v l '%*s' "$((COLS - 4))" ''; printf '  %s%s%s\n' "$DIM" "${l// /─}" "$R"; }
say()   { printf '%s\n' "$*" | fold -s -w "$((COLS - 4))" | sed 's/^/  /'; }
dim()   { printf '%s\n' "$*" | fold -s -w "$((COLS - 6))" | sed "s/^/  ${DIM}/; s/\$/${R}/"; }
hint()  { printf '%s\n' "$*" | fold -s -w "$((COLS - 10))" | sed "s/^/      ${DIM}/; s/\$/${R}/"; }
ok()    { printf '  %s%s%s %s\n' "$GRN" "$OK_SYM" "$R" "$*"; }
warn()  { printf '  %s%s%s %s\n' "$YEL" "$WARN_SYM" "$R" "$*"; }
err()   { printf '  %s%s%s %s\n' "$RED" "$BAD_SYM" "$R" "$*"; }
die()   { echo; err "$*"; exit 1; }
blank() { echo; }
kv()    { printf '    %s%-22s%s %s\n' "$DIM" "$1" "$R" "$2"; }

header() {
    cls
    printf '\n  %s%sPteroArch%s %s· Pterodactyl for Arch Linux%s  %s%s%s\n' "$B" "$CYN" "$R" "$DIM" "$R" "$DIM" "${2:-}" "$R"
    rule
    printf '  %s%s%s\n\n' "$B" "$1" "$R"
}

die_input() { echo; die "Input closed - stopping. Nothing after this point was changed."; }

trim() { local s=$1; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

ask() {
    local __var=$1 prompt=$2 def=${3-} val=${4-} msg=${5-"That doesn't look right - try again."} ans
    while true; do
        if [[ -n $def ]]; then printf '  %s%s%s %s[%s]%s: ' "$B" "$prompt" "$R" "$DIM" "$def" "$R"
    else printf '  %s%s%s: ' "$B" "$prompt" "$R"; fi
        IFS= read -r ans <"$TTY" || die_input
        ans=$(trim "${ans:-$def}")
        if [[ -z $ans ]]; then err "This one can't be empty."; continue; fi
        if [[ -n $val ]] && ! "$val" "$ans"; then err "$msg"; continue; fi
        printf -v "$__var" '%s' "$ans"
        return 0
    done
}

ask_opt() {
    local __var=$1 prompt=$2 def=${3-} ans
    if [[ -n $def ]]; then printf '  %s%s%s %s[%s]%s: ' "$B" "$prompt" "$R" "$DIM" "$def" "$R"
else printf '  %s%s%s %s(optional)%s: ' "$B" "$prompt" "$R" "$DIM" "$R"; fi
    IFS= read -r ans <"$TTY" || die_input
    printf -v "$__var" '%s' "$(trim "${ans:-$def}")"
}

ask_yn() {
    local q=$1 def=${2:-Y} ans hint
    [[ $def == Y ]] && hint="Y/n" || hint="y/N"
    while true; do
        printf '  %s%s%s %s[%s]%s: ' "$B" "$q" "$R" "$DIM" "$hint" "$R"
        IFS= read -r ans <"$TTY" || die_input
        ans=$(trim "${ans:-$def}")
case ${ans,,} in y|yes) return 0 ;; n|no) return 1 ;; esac
err "Please answer y or n."
done
}

choose() {
local __var=$1 def=$2; shift 2
local i=1 defidx=1 opt key label hint ans
local -a keys=()
for opt in "$@"; do
    IFS='|' read -r key label hint <<<"$opt"
    keys+=("$key")
    [[ $key == "$def" ]] && defidx=$i
    printf '    %s%d)%s %s\n' "$B" "$i" "$R" "$label"
    [[ -n $hint ]] && printf '%s\n' "$hint" | fold -s -w "$((COLS - 12))" | sed "s/^/       ${DIM}/; s/\$/${R}/"
    i=$((i + 1))
  done
  while true; do
    printf '  %sChoose%s %s[%d]%s: ' "$B" "$R" "$DIM" "$defidx" "$R"
    IFS= read -r ans <"$TTY" || die_input
    ans=$(trim "${ans:-$defidx}")
    if [[ $ans =~ ^[0-9]+$ ]] && ((ans >= 1 && ans <= ${#keys[@]})); then
      printf -v "$__var" '%s' "${keys[ans - 1]}"
      return 0
    fi
    err "Pick a number from 1 to ${#keys[@]}."
  done
}

ask_password() {
  local __var=$1 prompt=$2 gen=$3 val=$4 msg=$5 p1 p2 extra=''
  PW_WAS_GENERATED=false
  [[ $gen == true ]] && extra=" ${DIM}(leave empty to generate one)${R}"
  while true; do
    printf '  %s%s%s%s: ' "$B" "$prompt" "$R" "$extra"
    IFS= read -rs p1 <"$TTY" || die_input; echo
    if [[ -z $p1 && $gen == true ]]; then
      printf -v "$__var" '%s' "$(gen_password)"; PW_WAS_GENERATED=true
      ok "A strong password was generated. It will be shown at the end."
      return 0
    fi
    if ! "$val" "$p1"; then err "$msg"; continue; fi
    printf '  %sType it again%s: ' "$B" "$R"
    IFS= read -rs p2 <"$TTY" || die_input; echo
    if [[ $p1 != "$p2" ]]; then err "The two entries didn't match."; continue; fi
    printf -v "$__var" '%s' "$p1"
    return 0
  done
}

pause() { printf '\n  %sPress Enter to continue…%s' "$DIM" "$R"; IFS= read -r _ <"$TTY" || die_input; }

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
is_email()    { [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
is_ipv4()     {
  [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local o; for o in "${BASH_REMATCH[@]:1}"; do ((10#$o <= 255)) || return 1; done
}
is_fqdn()     { [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
is_port()     { [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
is_pos_int()  { [[ $1 =~ ^[0-9]{1,9}$ ]] && ((10#$1 > 0)); }
is_tz()       { [[ $1 == UTC ]] || { [[ $1 =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$ ]] && [[ -f /usr/share/zoneinfo/$1 ]]; }; }
is_username() { [[ $1 =~ ^[a-z0-9][a-z0-9_.-]+[a-z0-9]$ ]] && ((${#1} <= 191)); }
is_name()     { [[ -n $1 && ${#1} -le 191 && $1 != *\"* && $1 != *\'* && $1 != *\\* ]]; }
is_password() { ((${#1} >= 8)) && [[ $1 =~ [A-Z] && $1 =~ [0-9] ]]; }
is_any_pw()   { [[ -n $1 ]]; }
is_url()      { [[ $1 =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]]; }
is_token()    { [[ $1 =~ ^[A-Za-z0-9_.-]{16,}$ ]]; }
is_node_name(){ [[ $1 =~ ^[A-Za-z0-9_\ .-]{1,100}$ ]]; }
is_loc_short(){ [[ $1 =~ ^[A-Za-z0-9_.-]{1,60}$ ]]; }
is_port_range() {
  [[ $1 =~ ^([0-9]{4,5})-([0-9]{4,5})$ ]] || return 1
  local lo=$((10#${BASH_REMATCH[1]})) hi=$((10#${BASH_REMATCH[2]}))
  ((lo > 1024 && hi <= 65535 && lo < hi && hi - lo + 1 <= 1000))
}
is_smtp_enc() { [[ $1 == tls || $1 == ssl || $1 == none ]]; }

# ── System facts ──
detect_facts() {
  TOTAL_MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  FREE_DISK_MB=$(df -Pm /var/lib 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
  FREE_ROOT_MB=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
  PRIMARY_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
  LOCAL_IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | sort -u | tr '\n' ' ')
  PUBLIC_IP=$(curl -4 -fsS --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]' || true)
  is_ipv4 "${PUBLIC_IP:-x}" || PUBLIC_IP=''
  SYSTEM_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  [[ -z $SYSTEM_TZ ]] && SYSTEM_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
  is_tz "${SYSTEM_TZ:-x}" || SYSTEM_TZ=UTC
  case "$(uname -m)" in
    x86_64) WINGS_ARCH=amd64 ;; aarch64) WINGS_ARCH=arm64 ;; *) WINGS_ARCH='' ;;
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
    PHP_BIN=/usr/bin/php; PHP_CONF_D=/etc/php/conf.d; FPM_SERVICE=php-fpm
    FPM_SOCK=/run/php-fpm/php-fpm.sock; PHP_PKGS=(php php-fpm php-gd php-sodium)
  else
    PHP_BIN=/usr/bin/php-legacy; PHP_CONF_D=/etc/php-legacy/conf.d; FPM_SERVICE=php-fpm-legacy
    FPM_SOCK=/run/php-fpm-legacy/php-fpm.sock; PHP_PKGS=(php-legacy php-legacy-fpm php-legacy-gd php-legacy-sodium)
  fi
}

panel_url() { if [[ $USE_SSL == true ]]; then printf 'https://%s' "$PANEL_HOST"; else printf 'http://%s' "$PANEL_HOST"; fi; }

mode_label() {
  case $MODE in
    full)  echo "Panel + Wings on this machine" ;;
    panel) echo "Panel only" ;;
    wings) echo "Wings only (node for an existing panel)" ;;
  esac
}

# ── State ──
save_kv_file() {
  local f=$1; shift
  local v
  ( umask 077; : >"$f"; for v in "$@"; do printf '%s=%q\n' "$v" "${!v}" >>"$f"; done )
}
save_answers()   { $DRY_RUN && return 0; mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"; save_kv_file "$ANSWERS_FILE" "${ANSWER_VARS[@]}"; }
# shellcheck disable=SC1090
load_answers()   { source "$ANSWERS_FILE"; }
# shellcheck disable=SC1090
load_runtime()   { [[ -f $RUNTIME_FILE ]] && source "$RUNTIME_FILE"; return 0; }
runtime_set()    { ( umask 077; printf '%s=%q\n' "$1" "$2" >>"$RUNTIME_FILE" ); }
is_done()        { [[ -f $DONE_FILE ]] && grep -qx "$1" "$DONE_FILE"; }
mark_done()      { echo "$1" >>"$DONE_FILE"; }

# ── Wizard ──
STEP_N=0; STEP_TOTAL=0
next_step() {
  STEP_N=$((STEP_N + 1))
  if ((STEP_TOTAL > 0)); then header "$1" "Step $STEP_N of $STEP_TOTAL"
  elif ((STEP_TOTAL < 0)); then header "$1" "Editing"
  else header "$1" "Step $STEP_N"; fi
}

wz_welcome() {
  header "Welcome"
  say "PteroArch sets up Pterodactyl, a web panel for running game servers in Docker containers. It has two parts:"
  blank
  kv "Panel" "the website you log into (PHP, MariaDB, Valkey, Nginx)"
  kv "Wings" "the agent that runs game servers in Docker"
  blank
  say "You'll answer a few questions first. Nothing is changed until you confirm on the review screen. The install itself usually takes 5–15 minutes."
  blank
  say "If a step fails, you can retry it, skip it, or quit. Quitting is safe: run the script again and it continues where it stopped."
  $DRY_RUN && { blank; warn "Dry run: you'll see the full plan at the end, but nothing will be installed."; }
  blank
  printf '  %sChecking this machine…%s\n' "$DIM" "$R"
  detect_facts
  preflight
}

PF_FAIL=0
pf() {
  case $1 in
    ok)   ok "$2" ;;
    warn) warn "$2" ;;
    fail) err "$2"; PF_FAIL=1 ;;
  esac
  [[ -n ${3:-} ]] && hint "$3"
  return 0
}

preflight() {
  PF_FAIL=0
  local soft=fail; $DRY_RUN && soft=warn

  if [[ $EUID -eq 0 ]]; then pf ok "Running as root"; else pf "$soft" "Not running as root" "Run it with: sudo bash $0"; fi

  local id='' like=''
  if [[ -r /etc/os-release ]]; then
    id=$(. /etc/os-release; echo "${ID:-}"); like=$(. /etc/os-release; echo "${ID_LIKE:-}")
  fi
  if [[ $id == arch ]]; then pf ok "Arch Linux detected"
  elif [[ " $like " == *" arch "* ]]; then pf warn "Arch-based distro detected ($id)" "Written for Arch; derivatives with delayed repos (e.g. Manjaro) may lack php-legacy 8.3 or valkey."
  else pf "$soft" "This is not Arch Linux (${id:-unknown})" "This installer only supports Arch Linux."; fi

  if [[ -d /run/systemd/system ]]; then pf ok "systemd is running"; else pf "$soft" "systemd is not running" "Containers without systemd (e.g. plain Docker) aren't supported."; fi

  if [[ -n $WINGS_ARCH ]]; then pf ok "CPU architecture: $(uname -m)"; else pf "$soft" "Unsupported CPU architecture: $(uname -m)" "Wings only ships for x86_64 and aarch64."; fi

  if [[ -e /var/lib/pacman/db.lck ]]; then pf "$soft" "pacman is locked (/var/lib/pacman/db.lck)" "Another package operation is running. Wait for it, or remove the lock if it's stale."; fi

  if curl -fsS --max-time 10 -o /dev/null https://github.com 2>/dev/null; then pf ok "Internet access works (github.com reachable)"
  else pf "$soft" "Can't reach github.com" "The panel and Wings are downloaded from GitHub. Check DNS / network."; fi

  if ((TOTAL_MEM_MB >= 2048)); then pf ok "Memory: ${TOTAL_MEM_MB} MB"
  elif ((TOTAL_MEM_MB >= 1024)); then pf warn "Memory: ${TOTAL_MEM_MB} MB" "Enough for the panel; game servers will need more."
  else pf warn "Memory: ${TOTAL_MEM_MB} MB" "Under 1 GB - installing PHP dependencies may run out of memory."; fi

  if ((FREE_ROOT_MB >= 5120)); then pf ok "Free disk on /: $((FREE_ROOT_MB / 1024)) GB"
  else pf warn "Free disk on /: ${FREE_ROOT_MB} MB" "At least 5 GB is recommended, plus space for game servers."; fi

  local virt; virt=$(systemd-detect-virt 2>/dev/null || true)
  case $virt in
    openvz|lxc|lxc-libvirt) pf warn "Virtualization: $virt" "Docker (and so Wings) usually doesn't work in $virt containers. Panel-only is fine." ;;
    ''|none) pf ok "Running on bare metal" ;;
    *) pf ok "Virtualization: $virt" ;;
  esac

  if $KERNEL_PENDING_REBOOT; then
    pf warn "The running kernel ($(uname -r)) has been upgraded on disk" "Docker and the firewall need kernel modules for the running kernel. Reboot first, then run this again."
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
    PANEL_VERSION=$(latest_panel_version)
    if [[ -n $PANEL_VERSION ]]; then pf ok "Newest panel release: $PANEL_VERSION"
    else PANEL_VERSION=$DEFAULT_PANEL_VERSION; pf warn "Couldn't confirm the newest 1.x release" "Using $PANEL_VERSION. Set PANEL_VERSION=vX.Y.Z to pick another."; fi
  else
    pf ok "Panel release (from PANEL_VERSION): $PANEL_VERSION"
  fi

  blank
  if ((PF_FAIL)); then die "Fix the problems marked $BAD_SYM above and run the installer again."; fi
  if $KERNEL_PENDING_REBOOT && ! $DRY_RUN; then
    if ask_yn "Reboot now? (recommended - afterwards, run this installer again)" Y; then
      say "Rebooting…"; systemctl reboot; exit 0
    fi
  fi
  pause
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
    [[ $MODE == quit ]] && { say "Nothing was changed."; exit 0; }
  else
    choose MODE "${MODE:-full}" \
      "full|Panel + Wings on this machine (recommended for a single server)|Everything on one box. Simplest setup." \
      "panel|Panel only|Run game servers on other machines (install Wings there later with this script)." \
      "wings|Wings only - make this machine a node for an existing panel|You'll need access to the panel's admin area."
  fi
  case $MODE in
    full)  STEP_TOTAL=6 ;;
    panel) STEP_TOTAL=5 ;;
    wings) STEP_TOTAL=3 ;;
  esac
}

dns_hint() {
  local ips; ips=$(resolve_a "$1")
  if [[ -z $ips ]]; then
    warn "$1 doesn't resolve yet."
    local target=${PUBLIC_IP:-$PRIMARY_IP}
    hint "Create an A record pointing to ${target:-this server} before installing, or Let's Encrypt will fail."
    return 1
  fi
  local ip match=false
  for ip in $ips; do
    [[ $ip == "$PUBLIC_IP" || " $LOCAL_IPS " == *" $ip "* ]] && match=true
  done
  if $match; then ok "$1 points to this server ($ips)"; return 0; fi
  warn "$1 resolves to $ips, but this server is ${PUBLIC_IP:-$PRIMARY_IP}."
  hint "If you use a proxy such as Cloudflare, set it to 'DNS only' (grey cloud): Wings and Let's Encrypt need a direct connection."
  return 1
}

wz_address() {
  next_step "How will people reach the panel?"
  say "A domain name (like panel.example.com) is strongly recommended: it lets PteroArch get a free HTTPS certificate from Let's Encrypt. Browsers and Wings need HTTPS to talk to each other safely."
  blank
  local kind
  choose kind "$([[ $PANEL_HOST_IS_IP == true ]] && echo ip || echo domain)" \
    "domain|I have a domain name pointing at this server|" \
    "ip|Use the IP address only (HTTP, no encryption - fine for testing on a LAN)|"
  blank
  if [[ $kind == domain ]]; then
    local prev=''; is_fqdn "${PANEL_HOST:-x}" && prev=$PANEL_HOST
    PANEL_HOST_IS_IP=false
    while true; do
      ask PANEL_HOST "Panel domain" "$prev" is_fqdn "Enter a domain like panel.example.com (no http://, no path)."
      PANEL_HOST=${PANEL_HOST,,}
      if dns_hint "$PANEL_HOST"; then break; fi
      ask_yn "Continue with this domain anyway?" N && break
      prev=$PANEL_HOST
    done
    blank
    say "HTTPS with a free Let's Encrypt certificate needs ports 80 and 443 open to the internet."
    if ask_yn "Get a Let's Encrypt certificate (HTTPS)?" Y; then
      USE_SSL=true
      ask LE_EMAIL "Email for Let's Encrypt expiry notices" "${LE_EMAIL:-${ADMIN_EMAIL:-}}" is_email "Enter a valid email address."
    else
      USE_SSL=false
      warn "Without HTTPS, passwords travel unencrypted. You can add a certificate later with: certbot --nginx -d $PANEL_HOST"
    fi
  else
    PANEL_HOST_IS_IP=true; USE_SSL=false
    ask PANEL_HOST "IP address of this server" "${PUBLIC_IP:-$PRIMARY_IP}" is_ipv4 "Enter an IPv4 address like 203.0.113.10."
  fi
}

wz_settings() {
  next_step "Panel settings"
  say "PHP version. Pterodactyl 1.x is officially tested on PHP 8.2 and 8.3."
  choose PHP_FLAVOR "${PHP_FLAVOR:-legacy}" \
    "legacy|php-legacy (PHP 8.3) - recommended|The version upstream tests and ships in its Docker image." \
    "current|php (PHP 8.5, Arch's main PHP)|Newer, but not tested upstream. Pick this only if you need the main php package."
  set_php_vars
  blank
  say "Timezone for schedules and timestamps (e.g. Europe/Warsaw, America/New_York)."
  ask TIMEZONE "Timezone" "${TIMEZONE:-$SYSTEM_TZ}" is_tz "Not a known timezone. Use Region/City, e.g. Europe/Berlin, or UTC."
  blank
  say "Pterodactyl can send anonymous usage statistics to its developers."
  if ask_yn "Send anonymous telemetry?" "$([[ $TELEMETRY == 1 ]] && echo Y || echo N)"; then TELEMETRY=1; else TELEMETRY=0; fi
  blank
  say "Email is used for password resets and account invites. You can skip this now and run 'php artisan p:environment:mail' later."
  if ask_yn "Set up outgoing email (SMTP) now?" "$([[ $MAIL_SETUP == yes ]] && echo Y || echo N)"; then
    MAIL_SETUP=yes
    ask SMTP_HOST "SMTP server" "${SMTP_HOST:-}" is_node_host "Enter a hostname like smtp.example.com."
    ask SMTP_ENC "Encryption (tls / ssl / none)" "${SMTP_ENC:-tls}" is_smtp_enc "Type tls, ssl or none."
    local defport=587; [[ $SMTP_ENC == ssl ]] && defport=465; [[ $SMTP_ENC == none ]] && defport=25
    ask SMTP_PORT "SMTP port" "${SMTP_PORT:-$defport}" is_port "Enter a port number."
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
  ask ADMIN_EMAIL "Email" "${ADMIN_EMAIL:-$LE_EMAIL}" is_email "Enter a valid email address."
  ask ADMIN_USERNAME "Username" "${ADMIN_USERNAME:-admin}" is_username "Use 3+ lowercase letters, numbers, '.', '-' or '_' (start and end with a letter or number)."
  ask ADMIN_FIRST "First name" "${ADMIN_FIRST:-Admin}" is_name "Avoid quotes and backslashes."
  ask ADMIN_LAST "Last name" "${ADMIN_LAST:-User}" is_name "Avoid quotes and backslashes."
  blank
  say "Password: at least 8 characters, with an uppercase letter and a number."
  ask_password ADMIN_PASSWORD "Password" true is_password "Needs 8+ characters, including an uppercase letter and a number."
  ADMIN_PASSWORD_GENERATED=$PW_WAS_GENERATED
  [[ -z $LE_EMAIL ]] && LE_EMAIL=$ADMIN_EMAIL
  return 0
}

wz_node() {
  next_step "Game server node (Wings on this machine)"
  say "PteroArch will register this machine in the panel as a node, configure Wings, and start it."
  blank
  ask NODE_NAME "Node name" "${NODE_NAME:-$(cut -c1-60 /proc/sys/kernel/hostname 2>/dev/null || echo local)}" is_node_name "Letters, numbers, spaces, '.', '-' and '_' only (max 100)."
  is_node_name "$NODE_NAME" || NODE_NAME=local
  ask NODE_LOCATION "Location code (a short label, e.g. eu1 or home)" "${NODE_LOCATION:-main}" is_loc_short "Letters, numbers, '.', '-' and '_' only (max 60)."
  blank
  local mem_def=$((TOTAL_MEM_MB - 1024)); ((mem_def < 512)) && mem_def=$TOTAL_MEM_MB
  local disk_def=$((FREE_DISK_MB * 9 / 10)); ((disk_def < 1024)) && disk_def=1024
  say "How much of this machine game servers may use in total. The panel and database need roughly 1 GB of RAM for themselves."
  ask NODE_MEMORY "Memory for game servers (MB)" "${NODE_MEMORY:-$mem_def}" is_pos_int "Enter a number of megabytes."
  ask NODE_DISK "Disk for game servers (MB)" "${NODE_DISK:-$disk_def}" is_pos_int "Enter a number of megabytes."
  blank
  say "Each game server needs a port (an 'allocation'). PteroArch can add a range now, e.g. 25565-25600 for Minecraft. Max 1000 ports, all above 1024."
  if ask_yn "Add a port range now?" Y; then
    ask ALLOC_RANGE "Port range" "${ALLOC_RANGE:-25565-25600}" is_port_range "Use FROM-TO, e.g. 25565-25600 (above 1024, at most 1000 ports)."
    ask ALLOC_IP "IP that game servers listen on" "${ALLOC_IP:-${PRIMARY_IP:-0.0.0.0}}" is_ipv4 "Enter an IPv4 address of this machine."
    if [[ $ALLOC_IP != 0.0.0.0 && -n $LOCAL_IPS && " $LOCAL_IPS " != *" $ALLOC_IP "* ]]; then
      warn "$ALLOC_IP isn't on any interface here (${LOCAL_IPS% }). Behind NAT, use the local IP; players connect via the panel host name."
    fi
  else
    ALLOC_RANGE=''
    hint "You can add ports later under Admin → Nodes → your node → Allocation."
  fi
  if [[ $USE_SSL == true ]]; then
    blank; dim "Wings will use $PANEL_HOST with the same Let's Encrypt certificate as the panel."
  fi
}

parse_deploy_cmd() {
  local s=$1
  s=${s//\"/}; s=${s//\'/}
  [[ $s =~ --panel-url[=[:space:]]+([^[:space:]]+) ]] && W_PANEL_URL=${BASH_REMATCH[1]%/}
  [[ $s =~ --token[=[:space:]]+([^[:space:]]+) ]] && W_TOKEN=${BASH_REMATCH[1]}
  [[ $s =~ --node[=[:space:]]+([0-9]+) ]] && W_NODE_ID=${BASH_REMATCH[1]}
  is_url "${W_PANEL_URL:-x}" && is_token "${W_TOKEN:-x}" && [[ -n ${W_NODE_ID:-} ]]
}

wz_wings_remote() {
  next_step "Connect this machine to your panel"
  say "First create the node in your panel: Admin → Locations (create one if needed), then Admin → Nodes → Create New. Use this machine's domain as the node's FQDN, and choose 'Use SSL Connection' if your panel uses HTTPS."
  blank
  ask W_FQDN "This node's domain (or IP if the node doesn't use SSL)" "${W_FQDN:-${PUBLIC_IP:-$PRIMARY_IP}}" \
    is_node_host "Enter a domain like node1.example.com, or an IPv4 address."
  W_FQDN=${W_FQDN,,}
  if is_fqdn "$W_FQDN"; then
    dns_hint "$W_FQDN" || true
    blank
    say "If the node uses SSL in the panel (required when the panel uses HTTPS), Wings needs a certificate for $W_FQDN. Port 80 must be reachable for Let's Encrypt."
    if ask_yn "Get a Let's Encrypt certificate for $W_FQDN?" "$([[ $W_SSL == false ]] && echo N || echo Y)"; then
      W_SSL=true
      ask LE_EMAIL "Email for Let's Encrypt expiry notices" "${LE_EMAIL:-}" is_email "Enter a valid email address."
    else W_SSL=false; fi
  else
    W_SSL=false
    warn "With an IP address the node can't use SSL. That only works if your panel also runs over plain HTTP."
  fi
  blank
  ask WINGS_PORT "Wings API port (as set on the node)" "${WINGS_PORT:-8080}" is_port "Enter a port number."
  ask SFTP_PORT "Wings SFTP port (as set on the node)" "${SFTP_PORT:-2022}" is_port "Enter a port number."
  blank
  say "How should Wings get its configuration?"
  choose W_CONFIG_METHOD "${W_CONFIG_METHOD:-deploy}" \
    "deploy|Paste the auto-deploy command (recommended)|In the panel: Admin → Nodes → your node → Configuration → Generate Token. It looks like: wings configure --panel-url … --token … --node …" \
    "paste|Paste the configuration file|Copy the YAML from the node's Configuration tab." \
    "later|Skip - I'll put /etc/pterodactyl/config.yml in place myself|Wings is installed but not started."
  blank
  case $W_CONFIG_METHOD in
    deploy)
      while true; do
        local line
        printf '  %sPaste the command%s: ' "$B" "$R"
        IFS= read -r line <"$TTY" || die_input
        if parse_deploy_cmd "$line"; then
          ok "Panel $W_PANEL_URL, node #$W_NODE_ID"
          if curl -fsS --max-time 10 -o /dev/null "$W_PANEL_URL" 2>/dev/null; then ok "The panel is reachable from here."
          else warn "Couldn't reach $W_PANEL_URL from this machine. Wings must be able to reach it."; fi
          break
        fi
        err "Couldn't find --panel-url, --token and --node in that. Copy the whole command from the panel."
      done ;;
    paste)
      say "Paste the YAML, then type END on its own line and press Enter:"
      local text='' l
      while IFS= read -r l <"$TTY"; do [[ $l == END ]] && break; text+="$l"$'\n'; done
      if [[ $text != *"token:"* || $text != *"remote:"* ]]; then
        warn "That doesn't look like a Wings config (no 'token:' / 'remote:'). You can edit this section on the review screen."
      fi
      W_CONFIG_TEXT=$text ;;
    later) ;;
  esac
  W_OVERRIDE=false
  if [[ -f /etc/pterodactyl/config.yml && $W_CONFIG_METHOD != later ]]; then
    blank
    if ask_yn "An existing /etc/pterodactyl/config.yml will be replaced. OK?" N; then W_OVERRIDE=true
    else W_CONFIG_METHOD=later; warn "Keeping the existing configuration."; fi
  fi
  blank
  if ask_yn "Open a port range for game servers in the firewall?" "$([[ -n $FW_GAME_RANGE ]] && echo Y || echo N)"; then
    ask FW_GAME_RANGE "Port range" "${FW_GAME_RANGE:-25565-25600}" is_port_range "Use FROM-TO, e.g. 25565-25600."
  else FW_GAME_RANGE=''; fi
}
is_node_host() { is_fqdn "$1" || is_ipv4 "$1"; }

fw_ports_list() {
  local l="SSH ${SSH_PORT}/tcp"
  if has_panel; then l+=", HTTP 80"; [[ $USE_SSL == true ]] && l+=", HTTPS 443"; fi
  if [[ $MODE == wings && $W_SSL == true ]]; then l+=", HTTP 80 (certificate renewals)"; fi
  if has_wings; then l+=", Wings ${WINGS_PORT}, SFTP ${SFTP_PORT}"; fi
  local gr=$ALLOC_RANGE; [[ $MODE == wings ]] && gr=$FW_GAME_RANGE
  [[ -n $gr ]] && l+=", games ${gr} (tcp+udp)"
  printf '%s' "$l"
}

wz_firewall() {
  next_step "Firewall"
  local active=''
  systemctl is-active --quiet firewalld 2>/dev/null && active=firewalld
  if [[ -z $active ]] && command -v ufw >/dev/null 2>&1; then
    local st; st=$(ufw status 2>/dev/null || true)
    [[ $st == *"Status: active"* ]] && active=ufw
  fi
  say "Arch has no firewall by default. PteroArch can set one up that only allows what Pterodactyl needs."
  [[ -n $active ]] && { blank; ok "$active is already active - the needed ports will be added to it."; }
  blank
  ask SSH_PORT "SSH port to keep open (so you don't lock yourself out)" "${SSH_PORT:-${SSH_DETECTED:-22}}" is_port "Enter a port number."
  blank
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
    full)  wz_address; wz_settings; wz_admin; wz_node; wz_firewall ;;
    panel) wz_address; wz_settings; wz_admin; wz_firewall ;;
    wings) wz_wings_remote; wz_firewall ;;
  esac
}

mask() { [[ -n $1 ]] && echo "•••••••• (hidden)" || echo "-"; }

review() {
  while true; do
    header "Review - nothing has been changed yet"
    printf '  %s1)%s %sInstall type%s\n' "$B" "$R" "$B" "$R"
    kv "Components" "$(mode_label)"
    has_panel && kv "Panel release" "$PANEL_VERSION"
    has_wings && kv "Wings release" "latest"
    local n=2
    if has_panel; then
      blank; printf '  %s2)%s %sPanel address%s\n' "$B" "$R" "$B" "$R"
      kv "URL" "$(panel_url)"
      kv "HTTPS" "$([[ $USE_SSL == true ]] && echo "Let's Encrypt ($LE_EMAIL)" || echo "no")"
      blank; printf '  %s3)%s %sPanel settings%s\n' "$B" "$R" "$B" "$R"
      kv "PHP" "$([[ $PHP_FLAVOR == current ]] && echo "php (8.5)" || echo "php-legacy (8.3)")"
      kv "Timezone" "$TIMEZONE"
      kv "Telemetry" "$([[ $TELEMETRY == 1 ]] && echo on || echo off)"
      if [[ $MAIL_SETUP == yes ]]; then kv "Email" "$SMTP_HOST:$SMTP_PORT ($SMTP_ENC), from $MAIL_FROM"; else kv "Email" "not configured"; fi
      kv "Database" "MariaDB, database 'panel', user 'pterodactyl' (password generated)"
      blank; printf '  %s4)%s %sAdministrator%s\n' "$B" "$R" "$B" "$R"
      kv "Username" "$ADMIN_USERNAME"
      kv "Email" "$ADMIN_EMAIL"
      kv "Name" "$ADMIN_FIRST $ADMIN_LAST"
      kv "Password" "$([[ $ADMIN_PASSWORD_GENERATED == true ]] && echo "generated - shown at the end" || mask "$ADMIN_PASSWORD")"
      n=5
    fi
    if [[ $MODE == full ]]; then
      blank; printf '  %s5)%s %sNode%s\n' "$B" "$R" "$B" "$R"
      kv "Name / location" "$NODE_NAME / $NODE_LOCATION"
      kv "Address" "$([[ $USE_SSL == true ]] && echo https || echo http)://$PANEL_HOST:$WINGS_PORT (SFTP $SFTP_PORT)"
      kv "Memory / disk" "${NODE_MEMORY} MB / ${NODE_DISK} MB"
      kv "Ports" "$([[ -n $ALLOC_RANGE ]] && echo "$ALLOC_RANGE on $ALLOC_IP" || echo "none yet")"
      n=6
    elif [[ $MODE == wings ]]; then
      blank; printf '  %s2)%s %sNode%s\n' "$B" "$R" "$B" "$R"
      kv "Node address" "$W_FQDN"
      kv "Certificate" "$([[ $W_SSL == true ]] && echo "Let's Encrypt ($LE_EMAIL)" || echo "none")"
      kv "Ports" "Wings $WINGS_PORT, SFTP $SFTP_PORT"
      case $W_CONFIG_METHOD in
        deploy) kv "Configuration" "auto-deploy from $W_PANEL_URL (node #$W_NODE_ID)" ;;
        paste)  kv "Configuration" "pasted YAML ($(printf '%s' "$W_CONFIG_TEXT" | wc -l) lines)" ;;
        later)  kv "Configuration" "you'll add it yourself; Wings won't be started" ;;
      esac
      n=3
    fi
    blank; printf '  %s%d)%s %sFirewall%s\n' "$B" "$n" "$R" "$B" "$R"
    if [[ $FW == none ]]; then kv "Firewall" "leave as is (open these yourself: $(fw_ports_list))"
    else kv "Firewall" "$FW"; kv "Open ports" "$(fw_ports_list)"; fi
    blank; rule
    say "The install starts with a full system upgrade (pacman -Syu), because Arch doesn't support partial upgrades."
    blank
    printf '  %sEnter%s to install · %s1-%d%s to change a section · %sq%s to quit: ' "$B" "$R" "$B" "$n" "$R" "$B" "$R"
    local ans; IFS= read -r ans <"$TTY" || die_input
    ans=$(trim "$ans")
    case $ans in
      '') return 0 ;;
      q|Q) blank; say "Nothing was changed."; exit 0 ;;
      1) local old=$MODE; STEP_TOTAL=-1; STEP_N=0; wz_mode
         if [[ $MODE != "$old" ]]; then wizard_rest; fi ;;
      *)
        STEP_TOTAL=-1; STEP_N=0
        case "$MODE:$ans" in
          full:2|panel:2) wz_address ;;
          full:3|panel:3) wz_settings ;;
          full:4|panel:4) wz_admin ;;
          full:5) wz_node ;;
          full:6|panel:5) wz_firewall ;;
          wings:2) wz_wings_remote ;;
          wings:3) wz_firewall ;;
          *) err "Type a number from 1 to $n, press Enter, or q."; sleep 1 ;;
        esac ;;
    esac
  done
}

wizard_rest() {
  local total=$STEP_TOTAL
  case $MODE in full) total=6 ;; panel) total=5 ;; wings) total=3 ;; esac
  STEP_TOTAL=$total; STEP_N=1
  case $MODE in
    full)  wz_address; wz_settings; wz_admin; wz_node; wz_firewall ;;
    panel) wz_address; wz_settings; wz_admin; wz_firewall ;;
    wings) wz_wings_remote; wz_firewall ;;
  esac
}

# ── Task engine ──
TASK_IDS=(); TASK_TITLES=(); TASK_FNS=()
add_task() { TASK_IDS+=("$1"); TASK_TITLES+=("$2"); TASK_FNS+=("$3"); }

build_tasks() {
  TASK_IDS=(); TASK_TITLES=(); TASK_FNS=()
  add_task packages "Upgrade the system and install packages" t_packages
  [[ $FW != none ]] && add_task firewall "Configure the firewall ($FW)" t_firewall
  if has_panel; then
    add_task php      "Configure PHP" t_php
    add_task mariadb  "Set up MariaDB and the panel database" t_mariadb
    add_task valkey   "Start Valkey (Redis)" t_valkey
    add_task panel_dl "Download Pterodactyl Panel $PANEL_VERSION" t_panel_download
    add_task composer "Install the panel's PHP dependencies" t_composer
    add_task panel_cfg "Configure the panel and create your admin account" t_panel_configure
    add_task workers  "Set up the queue worker and scheduler" t_workers
    add_task nginx    "Configure Nginx" t_nginx
    [[ $USE_SSL == true ]] && add_task ssl "Get a Let's Encrypt certificate" t_ssl
  fi
  if has_wings; then
    add_task docker "Start Docker" t_docker
    add_task wings_bin "Install Wings" t_wings_bin
    if [[ $MODE == full ]]; then
      add_task node "Create the node and generate Wings' configuration" t_node
    else
      [[ $W_CONFIG_METHOD != later ]] && add_task wings_cfg "Write Wings' configuration" t_wings_config
      [[ $W_SSL == true ]] && add_task wings_ssl "Get a Let's Encrypt certificate for $W_FQDN" t_wings_ssl
    fi
    add_task wings_start "Start Wings" t_wings_start
  fi
}

note() { echo ">> $*"; printf '%s' "$*" >"$STATUS_FILE" 2>/dev/null || true; }

spinner() {
  local pid=$1 label=$2 i=0 start=$SECONDS el sub max line
  printf '\e[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    sub=$(cat "$STATUS_FILE" 2>/dev/null || true)
    el=$((SECONDS - start))
    max=$((COLS - ${#label} - 16)); ((max < 0)) && max=0
    ((${#sub} > max)) && sub="${sub:0:max}…"
    printf -v line '%s %s  %s%s%d:%02d%s' "${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}" "$label" "$DIM" "${sub:+$sub $DOT }" $((el / 60)) $((el % 60)) "$R"
    printf '\r\e[K  %s' "$line"
    i=$((i + 1)); sleep 0.2
  done
  printf '\r\e[K\e[?25h'
}

CHILD_PID=''
run_task() {
  local idx=$1 total=$2 id=$3 title=$4 fn=$5 rc start_line t0 label
  label="[$idx/$total] $title"
  while true; do
    start_line=$(wc -l <"$LOG_FILE")
    printf '\n===== %s  %s (%s) =====\n' "$(date '+%F %T')" "$title" "$id" >>"$LOG_FILE"
    : >"$STATUS_FILE"
    t0=$SECONDS
    if $VERBOSE || [[ ! -t 1 ]]; then
      printf '  %s%s%s\n' "$B" "$label" "$R"
      ( set -Eeuo pipefail; trap 'echo "!! failed (exit $?) at: $BASH_COMMAND" >&2' ERR; "$fn" ) 2>&1 | tee -a "$LOG_FILE" | { if $VERBOSE; then sed "s/^/    ${DIM}/; s/\$/${R}/"; else cat >/dev/null; fi; }
      rc=${PIPESTATUS[0]}
    else
      ( set -Eeuo pipefail; trap 'echo "!! failed (exit $?) at: $BASH_COMMAND" >&2' ERR; "$fn" ) >>"$LOG_FILE" 2>&1 </dev/null &
      CHILD_PID=$!
      spinner "$CHILD_PID" "$label"
      wait "$CHILD_PID"; rc=$?
      CHILD_PID=''
    fi
    local el=$((SECONDS - t0))
    if ((rc == 0)); then
      mark_done "$id"; load_runtime
      printf '  %s%s%s %s %s(%d:%02d)%s\n' "$GRN" "$OK_SYM" "$R" "$label" "$DIM" $((el / 60)) $((el % 60)) "$R"
      return 0
    fi
    printf '  %s%s %s%s\n' "$RED" "$BAD_SYM" "$label" "$R"
    blank
    printf '  %sLast lines of output:%s\n' "$B" "$R"
    tail -n +"$((start_line + 1))" "$LOG_FILE" | tail -n 18 | cut -c1-$((COLS + 40)) | sed "s/^/    ${DIM}/; s/\$/${R}/"
    blank
    hint_for "$id"
    local act
    while true; do
      choose act retry \
        "retry|Retry this step|Fix the cause (another terminal is handy), then retry." \
        "skip|Skip this step and continue|Later steps may fail if they depend on it." \
        "log|Show the full log of this step|" \
        "quit|Quit (run the installer again later to resume)|"
      case $act in
        log) tail -n +"$((start_line + 1))" "$LOG_FILE" | less -R 2>/dev/null || tail -n +"$((start_line + 1))" "$LOG_FILE"; continue ;;
        *) break ;;
      esac
    done
    case $act in
      retry) blank; continue ;;
      skip)  warn "Skipped: $title"; echo "skipped:$id" >>"$DONE_FILE"; return 0 ;;
      quit)  blank; say "Stopped. Your answers are saved - run the installer again to resume. Log: $LOG_FILE"; exit 1 ;;
    esac
  done
}

hint_for() {
  case $1 in
    packages) dim "Common causes: outdated mirrors (try: reflector or edit /etc/pacman.d/mirrorlist), a full disk, or a package conflict pacman wants you to confirm. Running 'pacman -Syu' yourself shows the question." ;;
    mariadb)  dim "If MariaDB's root user has a password, put it in /root/.my.cnf ([client] / password=…) and retry." ;;
    composer) dim "Usually a missing PHP extension or too little memory. The log names the extension." ;;
    ssl|wings_ssl) dim "Let's Encrypt must reach this machine on port 80 at the domain you entered. Check the DNS A record, any provider firewall, and that Cloudflare proxying is off. 'Skip' leaves HTTPS unconfigured; fix it later with certbot." ;;
    wings_start) dim "See 'journalctl -u wings -n 50'. Wings must reach the panel URL, and its certificate files must exist." ;;
    firewall) dim "If modules are missing, the kernel was probably upgraded: reboot and run the installer again." ;;
    docker)   dim "If the kernel was upgraded during this install, reboot and run the installer again." ;;
  esac
  return 0
}

run_all_tasks() {
  local total=${#TASK_IDS[@]} i done_count=0
  load_runtime
  for ((i = 0; i < total; i++)); do is_done "${TASK_IDS[i]}" && done_count=$((done_count + 1)); done
  header "Installing" "$total steps"
  [[ $done_count -gt 0 ]] && { dim "Resuming - finished steps are skipped."; blank; }
  dim "Detailed log: $LOG_FILE"
  blank
  for ((i = 0; i < total; i++)); do
    local id=${TASK_IDS[i]}
    if is_done "$id"; then
      printf '  %s%s [%d/%d] %s (already done)%s\n' "$DIM" "$OK_SYM" $((i + 1)) "$total" "${TASK_TITLES[i]}" "$R"
      continue
    fi
    if grep -qx "skipped:$id" "$DONE_FILE" 2>/dev/null; then
      printf '  %s%s [%d/%d] %s (skipped earlier - trying again)%s\n' "$DIM" "$WARN_SYM" $((i + 1)) "$total" "${TASK_TITLES[i]}" "$R"
      sed -i "/^skipped:$id\$/d" "$DONE_FILE"
    fi
    run_task $((i + 1)) "$total" "$id" "${TASK_TITLES[i]}" "${TASK_FNS[i]}"
    [[ $id == packages ]] && after_packages
  done
}

after_packages() {
  if [[ ! -d /usr/lib/modules/$(uname -r) ]] && { has_wings || [[ $FW != none ]]; }; then
    blank
    warn "The upgrade installed a new kernel. Docker and the firewall need a reboot to load their kernel modules."
    if ask_yn "Reboot now? Run the installer again afterwards to continue." Y; then
      say "Rebooting… then run: bash $0"
      sleep 2; systemctl reboot; exit 0
    fi
    warn "Continuing without a reboot - the firewall or Docker steps may fail."
  fi
}

on_interrupt() {
  if [[ -n $CHILD_PID ]]; then pkill -TERM -P "$CHILD_PID" 2>/dev/null; kill "$CHILD_PID" 2>/dev/null; fi
  printf '\e[?25h'
  echo
  if [[ -f $ANSWERS_FILE ]]; then warn "Interrupted. Run the installer again to resume."; else warn "Cancelled. Nothing was changed."; fi
  exit 130
}

# ── Tasks ──
art() {
  mkdir -p "$ART_HOME"; chown "$WEB_USER:$WEB_USER" "$ART_HOME"
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
  if has_panel; then tcp+=(80); [[ $USE_SSL == true ]] && tcp+=(443); fi
  [[ $MODE == wings && $W_SSL == true ]] && tcp+=(80)
  has_wings && tcp+=("$WINGS_PORT" "$SFTP_PORT")
  local gr=$ALLOC_RANGE; [[ $MODE == wings ]] && gr=$FW_GAME_RANGE
  local p
  if [[ $FW == ufw ]]; then
    note "Adding ufw rules"
    ufw default deny incoming
    ufw default allow outgoing
    for p in "${tcp[@]}"; do ufw allow "$p/tcp"; done
    if [[ -n $gr ]]; then ufw allow "${gr/-/:}/tcp"; ufw allow "${gr/-/:}/udp"; fi
    note "Enabling ufw"
    ufw --force enable
    systemctl enable ufw
    ufw status verbose
  else
    note "Adding firewalld rules"
    systemctl enable --now firewalld
    for p in "${tcp[@]}"; do firewall-cmd --permanent --add-port="$p/tcp"; done
    if [[ -n $gr ]]; then firewall-cmd --permanent --add-port="$gr/tcp"; firewall-cmd --permanent --add-port="$gr/udp"; fi
    firewall-cmd --reload
    firewall-cmd --list-all
  fi
}

t_php() {
  local ini=$PHP_CONF_D/90-pterodactyl.ini ext
  mkdir -p "$PHP_CONF_D"
  : >"$ini"
  local mods; mods=$("$PHP_BIN" -m 2>/dev/null)
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
  local ver; ver=$("$PHP_BIN" -v 2>&1)
  if grep -qi 'warning' <<<"$ver"; then echo "$ver"; echo "PHP prints warnings - check $ini and php.ini"; return 1; fi
  mods=$("$PHP_BIN" -m)
  local missing=()
  for ext in bcmath ctype curl dom fileinfo gd iconv intl mbstring mysqli openssl pdo_mysql posix sockets sodium tokenizer xml zip; do
    grep -qix "$ext" <<<"$mods" || missing+=("$ext")
  done
  if ((${#missing[@]})); then echo "Missing PHP extensions: ${missing[*]}"; return 1; fi
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
  for i in $(seq 1 30); do mariadb -u root -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
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
  local tmp; tmp=$(mktemp -d)
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
  local expected; expected=$(curl -fsSL --retry 3 https://getcomposer.org/download/latest-stable/composer.phar.sha256 | awk '{print $1}')
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
    local enc=$SMTP_ENC; [[ $enc == none ]] && enc=''
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
  local scheme=http; [[ $USE_SSL == true ]] && scheme=https
  note "Location '$NODE_LOCATION'"
  local loc_id; loc_id=$(sql "SELECT id FROM panel.locations WHERE short='${NODE_LOCATION}' LIMIT 1")
  if [[ -z $loc_id ]]; then
    art p:location:make --no-interaction --short="$NODE_LOCATION" --long="Created by PteroArch"
    loc_id=$(sql "SELECT id FROM panel.locations WHERE short='${NODE_LOCATION}' LIMIT 1")
  fi
  note "Node '$NODE_NAME'"
  local node_id; node_id=$(sql "SELECT id FROM panel.nodes WHERE name='${NODE_NAME}' LIMIT 1")
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
    local alias=''; [[ $PANEL_HOST_IS_IP == false ]] && alias=$PANEL_HOST
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
  local want; want=$(awk '/^[[:space:]]+cert:/ {print $2; exit}' /etc/pterodactyl/config.yml)
  echo "Certificate path in config: ${want:-none}"
}

t_wings_ssl() {
  local domain=$W_FQDN cfg=/etc/pterodactyl/config.yml
  if [[ -f $cfg ]]; then
    local d; d=$(sed -n 's#^[[:space:]]*cert:[[:space:]]*/etc/letsencrypt/live/\([^/]*\)/fullchain.pem.*#\1#p' "$cfg" | head -1)
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
svc_line() {
  if systemctl is-active --quiet "$1"; then ok "$2"; else err "$2 ${DIM}(systemctl status $1)${R}"; fi
}

finish() {
  load_runtime
  header "Finished" "$(date '+%F %T')"
  local skipped; skipped=$(grep -c '^skipped:' "$DONE_FILE" 2>/dev/null || true)
  printf '  %sServices%s\n' "$B" "$R"
  if has_panel; then
    svc_line nginx "Nginx"; svc_line "$FPM_SERVICE" "PHP-FPM"; svc_line mariadb "MariaDB"; svc_line valkey "Valkey"
    svc_line pteroq "Queue worker"; svc_line ptero-schedule.timer "Scheduler timer"
  fi
  if has_wings; then
    svc_line docker "Docker"
    if [[ ${WINGS_STATE:-} == notconfigured ]]; then warn "Wings installed, waiting for /etc/pterodactyl/config.yml"
    else svc_line wings "Wings"; fi
  fi
  [[ $FW == ufw ]] && svc_line ufw "Firewall (ufw)"
  [[ $FW == firewalld ]] && svc_line firewalld "Firewall (firewalld)"
  ((skipped > 0)) && warn "$skipped step(s) were skipped - see above and the log."

  if has_panel; then
    local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$(panel_url)/auth/login" 2>/dev/null || true)
    [[ $code == 000 && $PANEL_HOST_IS_IP == false ]] && code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
      --resolve "$PANEL_HOST:443:127.0.0.1" --resolve "$PANEL_HOST:80:127.0.0.1" "$(panel_url)/auth/login" 2>/dev/null || true)
    if [[ $code == 200 ]]; then ok "The panel answers at $(panel_url)"; else warn "The panel login page returned HTTP ${code:-none}"; fi
  fi
  if [[ $MODE == full && ${WINGS_STATE:-} == running ]]; then
    local scheme=http; [[ $USE_SSL == true ]] && scheme=https
    local wc; wc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$scheme://$PANEL_HOST:$WINGS_PORT/api/system" 2>/dev/null || true)
    if [[ $wc == 401 ]]; then ok "Wings answers on port $WINGS_PORT"; else warn "Wings API returned HTTP ${wc:-none} (expected 401)"; fi
  fi

  if has_panel; then
    ( umask 077
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
      } >"$CRED_FILE" )
    blank
    printf '  %sLog in%s\n' "$B" "$R"
    kv "URL" "$(panel_url)"
    kv "Username" "$ADMIN_USERNAME"
    kv "Password" "$ADMIN_PASSWORD"
    hint "Saved (root-only) to $CRED_FILE, along with the database password."
  fi

  blank
  printf '  %sNext steps%s\n' "$B" "$R"
  case $MODE in
    full)
      say "1. Log in and open Admin → Nodes. '$NODE_NAME' should show a green heart."
      [[ -z $ALLOC_RANGE ]] && say "2. Add ports under Admin → Nodes → $NODE_NAME → Allocation." || say "2. Ports $ALLOC_RANGE are ready for game servers."
      say "3. Create a server: Admin → Servers → Create New, and pick an egg (e.g. Minecraft → Paper)." ;;
    panel)
      say "1. Log in, create a Location and a Node (Admin → Nodes)."
      say "2. On each game-server machine, run this installer and choose 'Wings only'." ;;
    wings)
      if [[ ${WINGS_STATE:-} == notconfigured ]]; then
        say "1. Put the node's configuration in /etc/pterodactyl/config.yml, then run: systemctl enable --now wings"
      else
        say "1. In the panel, Admin → Nodes should show this node with a green heart."
      fi
      say "2. Add ports for game servers under the node's Allocation tab." ;;
  esac
  blank
  dim "Useful: journalctl -u wings -f · systemctl status pteroq · tail $PANEL_DIR/storage/logs/laravel-\$(date +%F).log"
  dim "Install log: $LOG_FILE"

  rm -f "$ANSWERS_FILE" "$RUNTIME_FILE" "$STATUS_FILE"
  date '+%F %T' >"$STATE_DIR/completed"
  blank
}

print_plan() {
  header "Dry run - the plan"
  local i
  for ((i = 0; i < ${#TASK_IDS[@]}; i++)); do printf '  %2d. %s\n' $((i + 1)) "${TASK_TITLES[i]}"; done
  blank
  [[ ${PHP_PKGS+set} == set ]] && has_panel && dim "PHP packages: ${PHP_PKGS[*]}"
  dim "Nothing was changed. Run without --dry-run (as root) to install."
  blank
}

usage() {
  cat <<EOF
PteroArch v$INSTALLER_VERSION - Pterodactyl Panel + Wings installer for Arch Linux

Usage: bash $0 [--dry-run] [--verbose]

  --dry-run   Answer the questions and see the plan. Nothing is installed.
  --verbose   Show command output while installing instead of a spinner.
  -h, --help  Show this help.

Environment:
  PANEL_VERSION=vX.Y.Z   Install this panel release instead of the newest 1.x.

Progress is saved in $STATE_DIR; run the script again to resume.
Log: $LOG_FILE
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
      --verbose|-v) VERBOSE=true ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $a"; usage; exit 2 ;;
    esac
  done
  [[ -n $PANEL_VERSION_OVERRIDE && ! $PANEL_VERSION_OVERRIDE =~ ^v1\.[0-9]+\.[0-9]+$ ]] && { echo "PANEL_VERSION must look like v1.15.2"; exit 2; }

  init_ui
  trap on_interrupt INT TERM

  if ! $DRY_RUN; then
    [[ $EUID -eq 0 ]] || { err "Please run as root: sudo bash $0"; exit 1; }
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
    touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
  fi

  local resuming=false
  if ! $DRY_RUN && [[ -f $ANSWERS_FILE ]]; then
    load_answers; set_php_vars
    header "Unfinished installation found"
    local d=0 t
    [[ -f $DONE_FILE ]] && d=$(grep -vc '^skipped:' "$DONE_FILE" || true)
    say "A previous run stopped part-way ($d step(s) finished)."
    kv "Install type" "$(mode_label)"
    has_panel && kv "Panel" "$(panel_url)"
    blank
    choose t resume \
      "resume|Resume where it stopped (recommended)|" \
      "restart|Start over with new answers|Already-installed parts are reused; finished steps run again." \
      "quit|Quit|"
    case $t in
      resume) resuming=true; printf '  %sChecking this machine…%s\n' "$DIM" "$R"; detect_facts ;;
      restart) rm -f "$DONE_FILE" "$RUNTIME_FILE"; OWN_STATE=true ;;
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
  if $DRY_RUN; then print_plan; exit 0; fi

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