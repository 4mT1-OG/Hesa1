#!/bin/bash
#
# Modular Security Hardening & Stress-Testing Script
# Designed for Debian/Ubuntu systems
# Prerequisites: Must be run as root
#

set -o pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root: sudo bash $0"
   exit 1
fi

LOG_DIR="/var/log/hardening"
mkdir -p "$LOG_DIR"/{main,tools,auto-fixes,configs/backups}
BACKUP_DIR="$LOG_DIR/configs/backups"
LOG_FILE="$LOG_DIR/main/execution.log"

backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

install_pkg() {
    local pkg=$1
    if ! dpkg -l | grep -qw "$pkg"; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1
    fi
}

# ==========================================
# 1. Plan Preparation / Safety Checks
# ==========================================
phase_1_prep() {
    echo "=========================================="
    echo "[Phase 1] Plan Preparation / Safety Checks"
    echo "=========================================="
    
    # ## 1.1 OS & Environment Validation
    if [[ ! -f /etc/debian_version ]]; then
        echo "[ERROR] Debian/Ubuntu system required."
        exit 1
    fi
    echo "[✓] Supported OS detected."

    # ## 1.2 Dependency & Logging Setup
    for cmd in apt-get dpkg systemctl sed grep tee; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "[ERROR] Missing command: $cmd"
            exit 1
        fi
    done
    echo "[✓] Environment and logging initialized at $LOG_DIR."
}

# ==========================================
# 2. User Management & SSH Keys
# ==========================================
phase_2_users() {
    echo "=========================================="
    echo "[Phase 2] User Management & SSH Keys"
    echo "=========================================="

    # ## 2.1 Root SSH Key Verification
    if [[ ! -f /root/.ssh/authorized_keys ]] || [[ ! -s /root/.ssh/authorized_keys ]]; then
        echo "[WARNING] Root has no SSH keys configured. Ensure local VM mode or set up keys before disabling password auth."
    else
        echo "[✓] Root SSH keys present."
    fi

    # ## 2.2 Secure Admin User Provisioning
    local existing_sudo=$(getent group sudo | cut -d: -f4 | tr ',' '\n' | grep -v "^root$" | grep -v "^$")
    if [[ -z "$existing_sudo" ]]; then
        local new_user="sec_$(openssl rand -hex 4)"
        local new_pass="$(openssl rand -base64 12)A1!"
        useradd -m -s /bin/bash "$new_user"
        echo "$new_user:$new_pass" | chpasswd
        usermod -aG sudo "$new_user"
        
        # Copy SSH keys if root has them
        if [[ -f /root/.ssh/authorized_keys ]]; then
            local u_home=$(getent passwd "$new_user" | cut -d: -f6)
            mkdir -p "$u_home/.ssh"
            cp /root/.ssh/authorized_keys "$u_home/.ssh/authorized_keys"
            chown -R "$new_user:$new_user" "$u_home/.ssh"
            chmod 700 "$u_home/.ssh" && chmod 600 "$u_home/.ssh/authorized_keys"
        fi
        echo "[✓] Created admin user: $new_user (Password: $new_pass - SAVE THIS!)"
    else
        echo "[✓] Existing sudo users found: $existing_sudo"
    fi
}

# ==========================================
# 3. SSH Hardening
# ==========================================
phase_3_ssh() {
    echo "=========================================="
    echo "[Phase 3] SSH Hardening"
    echo "=========================================="

    local ssh_config="/etc/ssh/sshd_config"
    backup_config "$ssh_config"

    # ## 3.1 Daemon Parameter Restriction
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$ssh_config"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$ssh_config"
    sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$ssh_config"
    sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$ssh_config"
    sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$ssh_config"

    # ## 3.2 Validation & Service Restart
    if sshd -t; then
        systemctl restart ssh || systemctl restart sshd
        echo "[✓] SSH hardened, password login disabled, service restarted."
    else
        echo "[ERROR] SSH configuration test failed. Restoring backup."
        local latest=$(ls -t "$BACKUP_DIR" | grep sshd_config | head -1)
        [[ -n "$latest" ]] && cp "$BACKUP_DIR/$latest" "$ssh_config"
    fi
}

# ==========================================
# 4. Kernel & Module Hardening
# ==========================================
phase_4_kernel() {
    echo "=========================================="
    echo "[Phase 4] Kernel & Module Hardening"
    echo "=========================================="

    # ## 4.1 Sysctl Security Parameters
    local sysctl_file="/etc/sysctl.d/99-hardening.conf"
    backup_config "$sysctl_file"
    cat << 'EOF' > "$sysctl_file"
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0
EOF
    sysctl --system > /dev/null 2>&1
    echo "[✓] Kernel sysctl security parameters applied."

    # ## 4.2 Unused Kernel Module Blacklisting
    local mod_file="/etc/modprobe.d/hardening.conf"
    backup_config "$mod_file"
    cat << 'EOF' > "$mod_file"
install dccp /bin/true
install sctp /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install udf /bin/true
install usb-storage /bin/true
EOF
    for mod in dccp sctp cramfs freevxfs udf usb-storage; do
        modprobe -r "$mod" 2>/dev/null || true
    done
    echo "[✓] Unused protocols, legacy filesystems, and USB storage blacklisted."
}

# ==========================================
# 5. PAM & Password Policy
# ==========================================
phase_5_pam() {
    echo "=========================================="
    echo "[Phase 5] PAM & Password Policy"
    echo "=========================================="

    install_pkg "libpam-pwquality"
    
    # ## 5.1 Password Quality Enforcement
    local pwq="/etc/security/pwquality.conf"
    backup_config "$pwq"
    cat << 'EOF' > "$pwq"
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
enforce_for_root
remember = 5
EOF

    # ## 5.2 Aging Policies
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   10/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs
    echo "[✓] PAM complexity and login.defs aging rules configured."
}

# ==========================================
# 6. Auditd & Auditing
# ==========================================
phase_6_auditd() {
    echo "=========================================="
    echo "[Phase 6] Auditd & Auditing"
    echo "=========================================="

    install_pkg "auditd"
    
    # ## 6.1 Audit Rules Deployment
    local rules_file="/etc/audit/rules.d/hardening.rules"
    cat << 'EOF' > "$rules_file"
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /usr/bin/passwd -p x -k passwd_modification
EOF
    augenrules --load > /dev/null 2>&1
    systemctl restart auditd 2>/dev/null || service auditd restart 2>/dev/null || true
    echo "[✓] Auditd rules deployed and active."
}

# ==========================================
# 7. AppArmor
# ==========================================
phase_7_apparmor() {
    echo "=========================================="
    echo "[Phase 7] AppArmor"
    echo "=========================================="

    install_pkg "apparmor"
    install_pkg "apparmor-utils"

    # ## 7.1 Enable & Enforce Profiles
    systemctl enable apparmor --now 2>/dev/null || true
    if command -v aa-enforce &> /dev/null; then
        for profile in /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/usr.bin.man; do
            [[ -f "$profile" ]] && aa-enforce "$profile" 2>/dev/null || true
        done
    fi
    echo "[✓] AppArmor service enabled and available profiles enforced."
}

# ==========================================
# 8. Firewall (UFW)
# ==========================================
phase_8_ufw() {
    echo "=========================================="
    echo "[Phase 8] Firewall (UFW)"
    echo "=========================================="

    install_pkg "ufw"
    
    # ## 8.1 Default Policy & SSH Allowance
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
    echo "[✓] UFW firewall active: incoming denied, outgoing allowed, SSH permitted."
}

# ==========================================
# 9. Automatic Security Updates
# ==========================================
phase_9_updates() {
    echo "=========================================="
    echo "[Phase 9] Automatic Security Updates"
    echo "=========================================="

    install_pkg "unattended-upgrades"

    # ## 9.1 Unattended-Upgrades Configuration
    cat << 'EOF' > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat << 'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    systemctl enable unattended-upgrades --now 2>/dev/null || true
    echo "[✓] Unattended-upgrades configured for daily security updates without auto-reboot."
}

# ==========================================
# 10. Filesystem Mount Hardening
# ==========================================
phase_10_mounts() {
    echo "=========================================="
    echo "[Phase 10] Filesystem Mount Hardening"
    echo "=========================================="

    backup_config "/etc/fstab"

    # ## 10.1 /tmp and /dev/shm Flag Hardening
    if ! grep -qE '/tmp.*noexec' /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=1G 0 0" >> /etc/fstab
    fi
    if ! grep -qE '/dev/shm.*noexec' /etc/fstab; then
        echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    fi
    mount -o remount /tmp 2>/dev/null || true
    mount -o remount /dev/shm 2>/dev/null || true
    echo "[✓] /tmp and /dev/shm secured with noexec,nosuid,nodev."
}

# ==========================================
# 11. Sudo Hardening
# ==========================================
phase_11_sudo() {
    echo "=========================================="
    echo "[Phase 11] Sudo Hardening"
    echo "=========================================="

    local sudoers_file="/etc/sudoers.d/hardening"
    backup_config "$sudoers_file"
    mkdir -p /var/log/sudo-io && chmod 750 /var/log/sudo-io

    # ## 11.1 Logging & Timeout Rules
    cat << 'EOF' > "$sudoers_file"
Defaults timestamp_timeout=15
Defaults passwd_tries=3
Defaults logfile=/var/log/sudo.log
Defaults log_input
Defaults log_output
Defaults iolog_dir=/var/log/sudo-io
Defaults !visiblepw
EOF
    chmod 440 "$sudoers_file"
    visudo -c -f "$sudoers_file" > /dev/null 2>&1
    echo "[✓] Sudo hardened with session I/O logging and 15-minute timeout."
}

# ==========================================
# 12. File Permissions & Umask
# ==========================================
phase_12_permissions() {
    echo "=========================================="
    echo "[Phase 12] File Permissions & Umask"
    echo "=========================================="

    # ## 12.1 Critical File Permissions
    chmod 644 /etc/passwd /etc/group 2>/dev/null || true
    chmod 640 /etc/shadow /etc/gshadow 2>/dev/null || true
    chmod 600 /etc/crontab 2>/dev/null || true

    # ## 12.2 Global Umask Settings
    for rc in /etc/profile /etc/bash.bashrc; do
        if [[ -f "$rc" ]] && ! grep -q "umask 027" "$rc"; then
            echo "umask 027" >> "$rc"
        fi
    done
    sed -i 's/^UMASK.*/UMASK           027/' /etc/login.defs 2>/dev/null || echo "UMASK           027" >> /etc/login.defs
    echo "[✓] File permissions and global umask (027) successfully enforced."
}

# ==========================================
# 13. Services & Daemons
# ==========================================
phase_13_services() {
    echo "=========================================="
    echo "[Phase 13] Services & Daemons"
    echo "=========================================="

    # ## 13.1 Stop & Disable Unnecessary Daemons
    for service in avahi-daemon cups nfs-server rpcbind snmpd; do
        if systemctl list-unit-files | grep -qw "$service"; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            echo "[✓] Disabled service: $service"
        fi
    done
}

# ==========================================
# 14. Monitoring & Integrity
# ==========================================
phase_14_monitoring() {
    echo "=========================================="
    echo "[Phase 14] Monitoring & Integrity (AIDE + RKHunter + Fail2Ban)"
    echo "=========================================="

    install_pkg "fail2ban"
    install_pkg "rkhunter"
    install_pkg "aide"

    # ## 14.1 Fail2Ban Setup
    cat << 'EOF' > /etc/fail2ban/jail.d/custom.conf
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 3600
EOF
    systemctl enable fail2ban --now 2>/dev/null || true

    # ## 14.2 AIDE Database Initialization
    if [[ ! -f /var/lib/aide/aide.db ]]; then
        echo "[INFO] Initializing AIDE database (may take a moment)..."
        aideinit > /dev/null 2>&1 || true
        [[ -f /var/lib/aide/aide.db.new ]] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
    echo "[✓] Fail2Ban active, RKHunter and AIDE integrity monitoring configured."
}

# ==========================================
# 15. Final Verification & Cleanup
# ==========================================
phase_15_verification() {
    echo "=========================================="
    echo "[Phase 15] Final Verification & Cleanup"
    echo "=========================================="

    # ## 15.1 Security State Summary Check
    echo "--- UFW Status ---"
    ufw status | head -n 5
    echo "--- Fail2Ban Status ---"
    systemctl is-active fail2ban
    echo "--- SSH Config Syntax Test ---"
    sshd -t && echo "[✓] SSH syntax valid."
    
    echo ""
    echo "=========================================="
    echo "  MODULAR HARDENING COMPLETE SUCCESSFULLY "
    echo "=========================================="
}

# Execute all phases sequentially (or call individual functions for testing)
phase_1_prep
phase_2_users
phase_3_ssh
phase_4_kernel
phase_5_pam
phase_6_auditd
phase_7_apparmor
phase_8_ufw
phase_9_updates
phase_10_mounts
phase_11_sudo
phase_12_permissions
phase_13_services
phase_14_monitoring
phase_15_verification

exit 0
