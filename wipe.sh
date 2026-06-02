#!/bin/bash

set -o pipefail

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------- Paths ----------
LOG_FILE="/var/log/sgm_softwipe.log"

# ---------- Logging ----------
log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || ts="??:??:??"
    echo "[$ts] $*" >> "$LOG_FILE" 2>/dev/null
}

banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗"
    echo -e "║       SGM VPS Data Wipe Tool          ║"
    echo -e "╚════════════════════════════════════════╝${NC}"
    echo
}

check_root() {
    [ "$EUID" -eq 0 ] || { echo -e "${RED}❌ This script must be run as root.${NC}" >&2; exit 1; }
}

# ---------- Pre‑check (returns 0 if ok, 1 if should abort) ----------
pre_check() {
    echo -e "${YELLOW}🔍 Running pre‑wipe safety checks...${NC}\n"

    # Container detection
    local virt
    virt=$(systemd-detect-virt 2>/dev/null) || virt="unknown"
    echo -n "  → Virtualisation: $virt   "
    case "$virt" in
        openvz|lxc|container|docker)
            echo -e "${RED}CONTAINER DETECTED${NC}"
            echo -e "${YELLOW}    ⚠️  Stopping services inside a container can affect the host.${NC}"
            echo -ne "${YELLOW}    Proceed anyway? (y/n): ${NC}"
            read -r proceed
            [ "$proceed" != "y" ] && { echo -e "${YELLOW}Wipe aborted.${NC}"; sleep 1; return 1; } ;;
        *) echo -e "${GREEN}OK${NC}" ;;
    esac

    # Writable filesystem test
    if ! touch /tmp/.sgm_write_test 2>/dev/null; then
        echo -e "${RED}❌ Root filesystem is read‑only. Cannot wipe.${NC}"
        sleep 2
        return 1
    fi
    rm -f /tmp/.sgm_write_test

    echo -e "${GREEN}✅ Pre‑checks passed.${NC}"
    echo
    return 0
}

# ---------- Confirmation (returns 0 if confirmed, 1 if not) ----------
confirm_wipe() {
    echo -e "${RED}⚠️  This will permanently delete:${NC}"
    echo -e "   • All user data in /home, /root, /srv, /opt, /usr/local"
    echo -e "   • All logs, caches, temporary files"
    echo -e "   • All running non‑system services"
    echo -e "   • All user‑created cron jobs"
    echo -e "   • RAM caches and swap contents"
    echo -e "${GREEN}The core operating system, SSH, and networking will remain.${NC}"
    echo
    echo -ne "${RED}Proceed? (y/n): ${NC}"
    read -r confirm
    case "$confirm" in
        y|Y|yes|YES) return 0 ;;
        *) echo -e "${YELLOW}Wipe cancelled.${NC}"; sleep 1; return 1 ;;
    esac
}

# ---------- Stop non‑essential services ----------
stop_services() {
    echo -e "${YELLOW}[1/6] Stopping non‑essential services...${NC}"
    local keep_services=(
        sshd ssh networking NetworkManager systemd-journald
        systemd-udevd systemd-resolved dbus-broker dbus
        rsyslog syslog-ng cron atd
    )

    local running_services
    running_services=$(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}')

    for svc in $running_services; do
        local keep=0
        for k in "${keep_services[@]}"; do
            if [[ "$svc" == "$k.service" || "$svc" == "$k" ]]; then
                keep=1
                break
            fi
        done
        if [ "$keep" -eq 1 ]; then
            log "Keeping service: $svc"
            continue
        fi

        echo -n "  Stopping $svc ... "
        if systemctl stop "$svc" 2>/dev/null; then
            systemctl disable "$svc" 2>/dev/null || true
            echo -e "${GREEN}done${NC}"
            log "Stopped & disabled $svc"
        else
            echo -e "${RED}failed${NC}"
            log "Failed to stop $svc"
        fi
    done
    echo -e "${GREEN}✅ Services stopped.${NC}"
}

# ---------- Kill user processes ----------
kill_user_procs() {
    echo -e "${YELLOW}[2/6] Terminating user processes...${NC}"

    local users
    users=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)

    for user in $users; do
        if ! pgrep -u "$user" &>/dev/null; then
            continue
        fi
        echo -n "  Killing processes of $user ... "
        pkill -u "$user" 2>/dev/null || true
        sleep 2
        pkill -9 -u "$user" 2>/dev/null || true
        echo -e "${GREEN}done${NC}"
        log "Killed all processes for $user"
    done

    if command -v lsof &>/dev/null; then
        echo -n "  Killing processes with deleted files ... "
        lsof -nP 2>/dev/null | grep '(deleted)' | awk '{print $2}' | sort -u | xargs -r kill -9 2>/dev/null || true
        echo -e "${GREEN}done${NC}"
    fi

    echo -e "${GREEN}✅ User processes terminated.${NC}"
}

# ---------- Wipe data directories ----------
wipe_data() {
    echo -e "${YELLOW}[3/6] Wiping data directories...${NC}"

    local dirs_to_empty=(
        /home /root /tmp /var/tmp /var/log /var/cache
        /srv /opt /usr/local /var/mail /var/spool/mail
    )

    for dir in "${dirs_to_empty[@]}"; do
        if [ -d "$dir" ]; then
            echo -n "  Emptying $dir ... "
            find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
            rm -rf "$dir"/.[!.]* "$dir"/..?* 2>/dev/null || true
            echo -e "${GREEN}done${NC}"
            log "Emptied $dir"
        fi
    done

    echo -n "  Clearing package manager caches ... "
    if command -v apt-get &>/dev/null; then apt-get clean -y 2>/dev/null; fi
    if command -v yum &>/dev/null; then yum clean all 2>/dev/null; fi
    if command -v dnf &>/dev/null; then dnf clean all 2>/dev/null; fi
    if command -v zypper &>/dev/null; then zypper clean -a 2>/dev/null; fi
    if command -v pacman &>/dev/null; then pacman -Scc --noconfirm 2>/dev/null; fi
    echo -e "${GREEN}done${NC}"
    log "Package caches cleared."

    echo -e "${GREEN}✅ Data directories wiped.${NC}"
}

# ---------- Clear crontabs ----------
clear_cron() {
    echo -e "${YELLOW}[4/6] Removing user crontabs...${NC}"
    if [ -d /var/spool/cron/crontabs ]; then
        rm -f /var/spool/cron/crontabs/* 2>/dev/null
    fi
    rm -f /var/spool/cron/* 2>/dev/null
    rm -f /var/spool/anacron/* 2>/dev/null

    if command -v atrm &>/dev/null; then
        atq | awk '{print $1}' | xargs -r atrm 2>/dev/null || true
    fi
    echo -e "${GREEN}✅ Cron & at jobs cleared.${NC}"
    log "Crontabs removed."
}

# ---------- Clear RAM & swap ----------
clear_memory() {
    echo -e "${YELLOW}[5/6] Clearing memory caches & swap...${NC}"

    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && \
        echo -e "  → Page cache cleared." || \
        echo -e "  → Failed to clear page cache."

    echo -n "  → Cycling swap ... "
    local swap_devs
    swap_devs=$(swapon --noheadings --show=NAME 2>/dev/null)
    if [ -n "$swap_devs" ]; then
        swapoff -a 2>/dev/null
        sleep 1
        for dev in $swap_devs; do
            swapon "$dev" 2>/dev/null || true
        done
        echo -e "${GREEN}done${NC}"
        log "Swap cycled."
    else
        echo -e "${YELLOW}no swap active${NC}"
    fi

    echo -e "${GREEN}✅ Memory cleared.${NC}"
}

# ---------- Restart logging ----------
restart_essentials() {
    echo -e "${YELLOW}[6/6] Restarting essential logging...${NC}"

    if systemctl is-active --quiet rsyslog; then
        systemctl restart rsyslog 2>/dev/null && log "rsyslog restarted."
    elif systemctl is-active --quiet syslog-ng; then
        systemctl restart syslog-ng 2>/dev/null && log "syslog-ng restarted."
    fi

    systemctl restart systemd-journald 2>/dev/null || true
    echo -e "${GREEN}✅ Essential services operational.${NC}"
}

# ---------- Full Wipe sequence ----------
perform_wipe() {
    log "===== Soft‑wipe started ====="
    stop_services
    kill_user_procs
    wipe_data
    clear_cron
    clear_memory
    restart_essentials
    log "===== Soft‑wipe completed ====="

    echo
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ Soft‑Wipe Complete                  ║${NC}"
    echo -e "${GREEN}║   All user data, services, and caches     ║${NC}"
    echo -e "${GREEN}║   have been removed.                      ║${NC}"
    echo -e "${GREEN}║   The VPS is now clean.                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Recommended: reboot now to clear in‑memory residuals.${NC}"
    echo -ne "${YELLOW}Reboot? (y/n): ${NC}"
    read -r reboot_ans
    if [ "$reboot_ans" = "y" ]; then
        log "Rebooting by user request."
        reboot
    else
        echo -e "${YELLOW}You can reboot manually later with: reboot${NC}"
    fi
}

# ---------- Live System Info Dashboard ----------
live_system_info() {
    # Trap to break out of the live loop on Ctrl+C
    trap 'return' SIGINT SIGTERM

    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════╗"
        echo -e "║        Live System Dashboard           ║"
        echo -e "╚════════════════════════════════════════╝${NC}"
        echo -e "Press any key to exit.\n"

        # CPU
        echo -e "${PURPLE}━━━ CPU ━━━━━━━━━━${NC}"
        lscpu 2>/dev/null | grep -E 'Model name|Socket|Core|Thread|CPU MHz|Virtualiz' | head -3
        echo
        # Memory
        echo -e "${PURPLE}━━━ Memory ━━━━━━━━${NC}"
        free -h 2>/dev/null | head -2
        echo
        # Disk
        echo -e "${PURPLE}━━━ Disk Usage (df -h) ━━━${NC}"
        df -h -x tmpfs -x devtmpfs 2>/dev/null | grep -v 'Filesystem' | column -t
        echo
        # Swap
        echo -e "${PURPLE}━━━ Swap ━━━━━━━━━━${NC}"
        swapon --show 2>/dev/null || echo "(no swap)"
        echo
        # Network
        echo -e "${PURPLE}━━━ Network ━━━━━━━${NC}"
        ip -br addr 2>/dev/null || ip addr 2>/dev/null | head -10
        echo
        # Load / Uptime
        echo -e "${PURPLE}━━━ Load & Uptime ━━━${NC}"
        uptime
        echo

        # Wait 0.5s for a keypress; if one is detected, break out
        read -t 0.5 -n 1 && break
    done
    trap - SIGINT SIGTERM   # Reset trap
}

# ---------- Static System Info (fallback or optional) ----------
system_info() {
    banner
    echo -e "${YELLOW}📊 System Information${NC}\n"
    live_system_info
}

# ============================================================
# MAIN MENU
# ============================================================
main() {
    check_root
    mkdir -p "$(dirname "$LOG_FILE")"
    log "===== SGM Data Wipe Tool started (PID $$) ====="

    trap 'echo -e "\n${YELLOW}Interrupted.${NC}"; exit 1' SIGINT SIGTERM

    while true; do
        banner
        echo -e "${YELLOW}Choose an option:${NC}\n"
        echo -e "${RED}[1]${NC}  🧹 Wipe VPS Data"
        echo -e "${BLUE}[2]${NC}  📊 Live System Info"
        echo -e "${CYAN}[3]${NC}  🚪 Exit\n"
        echo -ne "${PURPLE}Choice [1-3]: ${NC}"
        read -r choice

        case $choice in
            1)
                banner
                if pre_check; then
                    if confirm_wipe; then
                        # Disable interrupts during wipe
                        trap '' SIGINT SIGTERM
                        perform_wipe
                        trap 'echo -e "\n${YELLOW}Interrupted.${NC}"; exit 1' SIGINT SIGTERM
                    fi
                fi
                ;;
            2)
                system_info
                ;;
            3)
                echo -e "${GREEN}Goodbye.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    done
}

main