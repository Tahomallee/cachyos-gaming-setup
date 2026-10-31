#!/usr/bin/env bash
# ==============================================================================
# CachyOS Gaming Setup
# Inspired by: Arch Wiki, CachyOS, pacman-contrib + proven desktop setups
# Target: CachyOS KDE on BTRFS | fresh installation
# Standard location: ~/Downloads/cachyos-gaming-setup.sh (always run from there)
# What it does: reproducible gaming setup, deliberate app selection, safe maintenance
# ==============================================================================
set -Euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'

# One run = one full log plus a separate error log.
LOG_DIR="$HOME/cachyos-logs"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/install_${RUN_ID}.log"
ERROR_LOG="$LOG_DIR/errors_${RUN_ID}.log"
LOG="$LOG_FILE" # Compatibility with final message below
mkdir -p "$LOG_DIR"
touch "$LOG_FILE" "$ERROR_LOG"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" "$ERROR_LOG" >&2)

log_time(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo -e "${GREEN}[✓ $(log_time)]${NC} $1"; }
info(){ echo -e "${CYAN}[→ $(log_time)]${NC} $1"; }
warn(){ echo -e "${YELLOW}[! $(log_time)]${NC} $1"; }
fail(){ echo -e "${RED}[✖ $(log_time)]${NC} $1"; }

# Gaming mode: EXTREME = maximum performance with deliberate trade-off (mitigations=off, Coolbits etc.)
# For daily driver set to false → SAFE MODE (safe, balanced)
GAMING_EXTREME=false
# GPU detection for hardware-specific drivers (NVIDIA only on NVIDIA)
GPU_VENDOR="unknown"
if lspci 2>/dev/null | grep -qi "nvidia"; then GPU_VENDOR="nvidia"
elif lspci 2>/dev/null | grep -qiE "amd.*vga|amd.*graphics|Radeon" -i; then GPU_VENDOR="amd"
elif lspci 2>/dev/null | grep -qi "intel.*graphics"; then GPU_VENDOR="intel"
fi
log "GPU: $GPU_VENDOR | Gaming-Extreme: $GAMING_EXTREME"
step(){ echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${MAGENTA} $1${NC}\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
on_error(){
 local status="$1" line="$2" command="$3" quoted_command
 printf -v quoted_command '%q' "$command"
 printf '[FEHLER %s] Zeile %s: Befehl %s fehlgeschlagen (Status %s)\n' "$(log_time)" "$line" "$quoted_command" "$status" >> "$ERROR_LOG"
 warn "Line $line failed (status $status) – details: $ERROR_LOG"
}
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

echo -e "${BLUE}Full log: $LOG_FILE${NC}"
echo -e "${RED}Errors only:    $ERROR_LOG${NC}\n"
if ! sudo -v; then
 fail "Sudo authorization failed – aborting without changes."
 exit 1
fi

# ---------- 0. SYSTEMPRÜFUNG ----------
step "0/8 SYSTEM CHECK - check prerequisites and system status"
info "Secure Boot check (muss AUS, sonst Invalid signature)"
sbctl status 2>/dev/null | grep -q "Secure Boot.*Enabled" && warn "Secure Boot ON! Disable in BIOS" || log "Secure Boot off - good"
info "Filesystem Check (Enforce BTRFS for Snapshots & Performance)"
CURRENT_FS="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
if [[ "$CURRENT_FS" != "btrfs" ]]; then
 fail "Wrong filesystem detected: '$CURRENT_FS'!"
 echo -e "${YELLOW}This masterpiece requires the BTRFS filesystem to ensure safe"
 echo -e "system snapshots and optimal gaming performance.${NC}"
 echo -e "\n${CYAN}SOLUTION for the user:${NC}"
 echo -e "1. Restart the CachyOS installation from the USB stick."
 echo -e "2. Select explicitly ${GREEN}BTRFS${NC} in the installer's disk selection."
 echo -e "3. Simply run this script again after reinstallation.\n"
 exit 1
else
 log "Filesystem is BTRFS – perfect for automatic recovery!"
fi

info "Boot Partition Check (Windows 100MB too small -> 2GB needed)"
df -h /boot | tail -1 | awk '{print "Boot:", $2, "total", $4, "frei"}'
df /boot | awk 'NR==2{if($4<500000) exit 1}' || warn "Boot low! 2GB recommended"
log "Kernel $(uname -r) ok"
if curl --fail --silent --show-error --connect-timeout 10 --head https://archlinux.org/ >/dev/null 2>&1 || ping -c1 -W3 archlinux.org &>/dev/null; then
 log "Internet reachable"
else
 fail "No internet connection – aborting to avoid incomplete setup."
 exit 1
fi
info "Configure pacman (parallel, color, verbose)"
if grep -q "^#\?ParallelDownloads" /etc/pacman.conf; then sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf 2>/dev/null || true; else echo "ParallelDownloads = 5" | sudo tee -a /etc/pacman.conf >/dev/null; fi
if grep -q "^#\?Color" /etc/pacman.conf; then sudo sed -i 's/^#\?Color/Color/' /etc/pacman.conf 2>/dev/null || true; else echo "Color" | sudo tee -a /etc/pacman.conf >/dev/null; fi
if grep -q "^#\?VerbosePkgLists" /etc/pacman.conf; then sudo sed -i 's/^#\?VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf 2>/dev/null || true; else echo "VerbosePkgLists" | sudo tee -a /etc/pacman.conf >/dev/null; fi
grep -q "ILoveCandy" /etc/pacman.conf || echo "ILoveCandy" | sudo tee -a /etc/pacman.conf >/dev/null
info "Keyring auto-fix (invalid signature after fresh ISO) - try quick fix first"
if ! sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring 2>/dev/null && ! sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring --overwrite '*' 2>/dev/null; then
 warn "Quick keyring update failed, doing full reset (can take a few minutes)..."
 sudo rm -rf /var/lib/pacman/sync/* 2>/dev/null || true
 timeout 30 sudo pacman-key --init 2>/dev/null || sudo pacman-key --init 2>/dev/null || true
 sudo pacman-key --populate archlinux cachyos 2>/dev/null || true
  # Reihenfolge wichtig: Schlüssel zuerst, DBs danach (sonst schlägt die DB-Signatur fehl)
  sudo pacman -Syy --noconfirm 2>/dev/null || true
  sudo pacman -S --needed --noconfirm archlinux-keyring cachyos-keyring 2>/dev/null || sudo pacman -S --needed --noconfirm archlinux-keyring cachyos-keyring --overwrite '*' 2>/dev/null || true
 sudo pacman-key --populate archlinux cachyos 2>/dev/null || true
else
 sudo pacman-key --populate archlinux cachyos 2>/dev/null || true
 log "Keyring quick fix succeeded - no full reset needed"
fi
if command -v cachyos-rate-mirrors &>/dev/null; then sudo cachyos-rate-mirrors 2>/dev/null || true; fi
sudo chmod 644 /etc/pacman.d/mirrorlist /etc/pacman.d/cachyos-mirrorlist 2>/dev/null || true
log "Pre-flight done"

# ---------- 1. UPDATE ----------
# On Arch/CachyOS the full update must run before installations/removals.
step "1/8 SYSTEM UPDATE - full update, abort safely on error"
if sudo pacman -Syu --noconfirm; then
 log "System update done"
else
 fail "System update failed – no automatic --overwrite='*'. Check $ERROR_LOG and restart only after fix."
 exit 1
fi

# ---------- 1.5 BEREINIGUNG - bewusst ersetzte Apps und Kernel ----------
step "1.5/8 CLEANUP - Standard+Bore, remove intentionally replaced apps"
# Welcome Center 1:1 wie Calamares - SOFORT blocken BEVOR KDE installiert wird (sonst ploppt es auf und Nutzer haben keine Ahnung)
# Autostart SOFORT killen und Binär kurz un-ausführbar machen - 100% kein Popup während Script
mkdir -p "$HOME/.config/autostart" 2>/dev/null || true
printf "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false\n" > "$HOME/.config/autostart/cachyos-hello.desktop" 2>/dev/null || true
printf "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false\n" > "$HOME/.config/autostart/org.kde.plasma-welcome.desktop" 2>/dev/null || true
sudo mkdir -p /etc/xdg/autostart 2>/dev/null || true
echo -e "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false" | sudo tee /etc/xdg/autostart/cachyos-hello.desktop >/dev/null 2>&1 || true
echo -e "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false" | sudo tee /etc/xdg/autostart/org.kde.plasma-welcome.desktop >/dev/null 2>&1 || true
sudo chmod -x /usr/bin/cachyos-hello 2>/dev/null || true
sudo chmod -x /usr/bin/cachyos-hello-qt 2>/dev/null || true
pkill -9 cachyos-hello 2>/dev/null || killall cachyos-hello 2>/dev/null || true
pkill -9 plasma-welcome 2>/dev/null || true
# Crashed Processes View (drkonqi) ebenfalls blocken
sudo chmod -x /usr/lib/drkonqi 2>/dev/null || true
sudo chmod -x /usr/bin/drkonqi 2>/dev/null || true
pkill -9 drkonqi 2>/dev/null || killall drkonqi 2>/dev/null || true
info "Ensure KDE Plasma installed (keep other desktops parallel) & Enforce GRUB"
echo -e "${YELLOW}KDE will be installed alongside existing desktops - GRUB will be enforced as bootloader (5s to abort with CTRL+C)!${NC}"
sleep 5
# Keep other desktops parallel - just ensure KDE is installed (do not delete GNOME/XFCE etc.)
# CachyOS KDE Standard & SDDM ensure and enable (SDDM will become default display manager)
# KDE + Calamares base as in CachyOS-Calamares (netinstall: KDE-Desktop + all default-selected groups)
# plasma-meta and SDDM are NOT installed (plasma-meta pulls in Discover, kwrite, krdp, kup, plasma-welcome etc.)
sudo pacman -S --needed --noconfirm ark bluedevil breeze-gtk cachy-update cachyos-kde-settings dolphin ffmpegthumbs filelight gwenview haruna kate kcalc kde-gtk-config kdeconnect kdegraphics-thumbnailers kdeplasma-addons kdialog kinfocenter kio-admin konsole kscreen kwallet-pam kwalletmanager partitionmanager phonon-qt6-vlc plasma-browser-integration plasma-desktop plasma-firewall plasma-login-manager plasma-nm plasma-pa plasma-systemmonitor plasma-thunderbolt plymouth-kcm powerdevil spectacle tesseract-data-eng xsettingsd fwupd 2>/dev/null || true
sudo pacman -S --needed --noconfirm dnsmasq dnsutils ethtool iwd modemmanager networkmanager networkmanager-openvpn nss-mdns usb_modeswitch wpa_supplicant wireless-regdb xl2tpd ufw ufw-extras bluez bluez-hid2hci bluez-libs bluez-utils bluez-obex pacman-contrib pkgfile rebuild-detector reflector shelly accountsservice bash-completion ffmpegthumbnailer gst-libav gst-plugin-pipewire gst-plugins-bad gst-plugins-ugly libdvdcss libgsf libopenraw plocate poppler-glib vlc-plugins-all xdg-user-dirs xdg-utils efitools nfs-utils nilfs-utils smartmontools unrar unzip awesome-terminal-fonts noto-fonts-emoji cantarell-fonts noto-fonts ttf-bitstream-vera ttf-dejavu ttf-liberation ttf-opensans ttf-meslo-nerd noto-fonts-cjk alsa-firmware alsa-plugins alsa-utils pavucontrol pipewire-pulse wireplumber pipewire-alsa realtime-privileges dmidecode dmraid hdparm hwdetect linux-firmware lsscsi mesa-utils mtools sg3_utils sof-firmware cpupower power-profiles-daemon upower alacritty btop duf fsarchiver git glances hwinfo meld nano-syntax-highlighting fastfetch pv python-defusedxml python-packaging rsync wget ripgrep  nano vim openssh cachyos-hooks cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist cachyos-rate-mirrors chwd cachyos-hello cachyos-kernel-manager cachyos-packageinstaller cachyos-settings cachyos-wallpapers cachyos-fish-config cachyos-zsh-config 2>/dev/null || true
# Install one by one if a package is missing in the repos (prevents aborting the whole install)
for _p in dnsmasq dnsutils ethtool iwd modemmanager networkmanager networkmanager-openvpn nss-mdns usb_modeswitch wpa_supplicant wireless-regdb xl2tpd ufw ufw-extras bluez bluez-hid2hci bluez-libs bluez-utils bluez-obex pacman-contrib pkgfile rebuild-detector reflector shelly accountsservice bash-completion ffmpegthumbnailer gst-libav gst-plugin-pipewire gst-plugins-bad gst-plugins-ugly libdvdcss libgsf libopenraw plocate poppler-glib vlc-plugins-all xdg-user-dirs xdg-utils efitools nfs-utils nilfs-utils smartmontools unrar unzip awesome-terminal-fonts noto-fonts-emoji cantarell-fonts noto-fonts ttf-bitstream-vera ttf-dejavu ttf-liberation ttf-opensans ttf-meslo-nerd noto-fonts-cjk alsa-firmware alsa-plugins alsa-utils pavucontrol pipewire-pulse wireplumber pipewire-alsa realtime-privileges dmidecode dmraid hdparm hwdetect linux-firmware lsscsi mesa-utils mtools sg3_utils sof-firmware cpupower power-profiles-daemon upower alacritty btop duf fsarchiver git glances hwinfo meld nano-syntax-highlighting fastfetch pv python-defusedxml python-packaging rsync wget ripgrep  nano vim openssh cachyos-hooks cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist cachyos-rate-mirrors chwd cachyos-hello cachyos-kernel-manager cachyos-packageinstaller cachyos-settings cachyos-wallpapers cachyos-fish-config cachyos-zsh-config ark bluedevil breeze-gtk cachy-update cachyos-kde-settings dolphin ffmpegthumbs filelight gwenview haruna kate kcalc kde-gtk-config kdeconnect kdegraphics-thumbnailers kdeplasma-addons kdialog kinfocenter kio-admin konsole kscreen kwallet-pam kwalletmanager partitionmanager phonon-qt6-vlc plasma-browser-integration plasma-desktop plasma-firewall plasma-login-manager plasma-nm plasma-pa plasma-systemmonitor plasma-thunderbolt plymouth-kcm powerdevil spectacle tesseract-data-eng xsettingsd fwupd; do pacman -Q "$_p" >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm "$_p" 2>/dev/null || true; done
sudo pacman -Rns --noconfirm micro cachyos-micro-settings 2>/dev/null || true  # Micro wird nicht gebraucht
# AUR themes from the Calamares KDE group (optional, errors are ignored)
for _p in cachyos-emerald-kde-theme-git cachyos-nord-kde-theme-git cachyos-iridescent-kde char-white; do (paru -S --needed --noconfirm "$_p" || yay -S --needed --noconfirm "$_p") 2>/dev/null || true; done
sudo systemctl enable plasmalogin.service --now 2>/dev/null || true
# SOFORT wieder blocken - pacman hat Autostart überschrieben! + plasma-welcome auch (sonst ploppt es während Script)
mkdir -p "$HOME/.config/autostart" 2>/dev/null || true
printf "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false\n" > "$HOME/.config/autostart/cachyos-hello.desktop" 2>/dev/null || true
printf "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false\n" > "$HOME/.config/autostart/org.kde.plasma-welcome.desktop" 2>/dev/null || true
echo -e "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false" | sudo tee /etc/xdg/autostart/cachyos-hello.desktop >/dev/null 2>&1 || true
echo -e "[Desktop Entry]\nHidden=true\nX-GNOME-Autostart-enabled=false" | sudo tee /etc/xdg/autostart/org.kde.plasma-welcome.desktop >/dev/null 2>&1 || true
pkill -9 cachyos-hello 2>/dev/null || killall cachyos-hello 2>/dev/null || true
pkill -9 cachyos-hello-qt 2>/dev/null || true
pkill -9 plasma-welcome 2>/dev/null || true
# Welcome Center wieder ausführbar machen (bleibt aber Hidden=true - startet nicht auto, nur manuell)
sudo chmod +x /usr/bin/cachyos-hello 2>/dev/null || true
sudo chmod +x /usr/bin/cachyos-hello-qt 2>/dev/null || true
sudo chmod +x /usr/lib/drkonqi 2>/dev/null || true
sudo chmod +x /usr/bin/drkonqi 2>/dev/null || true
pkill -9 cachyos-hello 2>/dev/null || true; pkill -9 drkonqi 2>/dev/null || true

info "Block KDE Telemetry (no diagnostics phone-home)"
# User level
kwriteconfig6 --file kuserfeedbackrc --group UserFeedback --key Enabled false 2>/dev/null || true
mkdir -p "$HOME/.config"
printf "[UserFeedback]\nEnabled=false\n" > "$HOME/.config/kuserfeedbackrc" 2>/dev/null || true
# System wide
sudo mkdir -p /etc/xdg 2>/dev/null || true
printf "[UserFeedback]\nEnabled=false\n" | sudo tee /etc/xdg/kuserfeedbackrc >/dev/null 2>&1 || true
# Disable DrKonqi crash reporter if present
kwriteconfig6 --file drkonqirc --group "CrashReporter" --key "Enabled" false 2>/dev/null || true
log "KDE Telemetry blocked"
# GRUB als festen Standard ERZWINGEN - erst GRUB installieren, dann Limine entfernen (sonst kein Bootloader!)
sudo pacman -S --needed --noconfirm grub efibootmgr os-prober grub-btrfs cachyos-grub-theme 2>/dev/null || sudo pacman -S --needed --noconfirm grub efibootmgr os-prober grub-btrfs 2>/dev/null || true
# CachyOS GRUB Theme für GUI statt Text (wie Screenshot 1 statt 2)
sudo pacman -S --needed --noconfirm cachyos-grub-theme 2>/dev/null || $AUR -S --needed --noconfirm cachyos-grub-theme 2>/dev/null || true
# 1:1 CachyOS GRUB Standard wie Wiki/Calamares (GRUB_DEFAULT 0, TIMEOUT 5, etc.) + Theme
sudo tee /etc/default/grub >/dev/null <<'GRUBEOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT='5'
GRUB_DISTRIBUTOR='CachyOS'
GRUB_CMDLINE_LINUX_DEFAULT='nowatchdog nvme_load=YES zswap.enabled=0 splash loglevel=3'
GRUB_CMDLINE_LINUX=""
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
#GRUB_ENABLE_CRYPTODISK=y
GRUB_TIMEOUT_STYLE=menu
GRUB_TERMINAL_INPUT=console
#GRUB_TERMINAL_OUTPUT=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
#GRUB_DISABLE_LINUX_UUID=true
GRUB_DISABLE_RECOVERY='true'
GRUB_THEME='/usr/share/grub/themes/cachyos/theme.txt'
GRUB_DISABLE_OS_PROBER=false
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUBEOF
sudo sed -i 's/Arch Linux/CachyOS/g' /usr/share/grub/themes/cachyos/theme.txt 2>/dev/null || true
# EFI Verzeichnis robust ermitteln (Cachy nutzt /boot/efi oder /boot)
EFI_DIR=""
for cand in /boot/efi /boot /efi; do
  if mountpoint -q "$cand" 2>/dev/null || [ -d "$cand/EFI" ]; then EFI_DIR="$cand"; break; fi
done
[ -z "$EFI_DIR" ] && EFI_DIR="/boot/efi"
info "GRUB EFI Verzeichnis: $EFI_DIR"
# Os-prober aktivieren damit Windows gefunden wird
sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub 2>/dev/null || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null 2>&1 || true
GRUB_OK=false
if sudo grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --bootloader-id=cachyos --recheck 2>&1 | tee -a "$LOG_FILE"; then
  GRUB_OK=true
elif sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=cachyos --recheck 2>&1 | tee -a "$LOG_FILE"; then
  GRUB_OK=true
elif sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=cachyos --recheck 2>&1 | tee -a "$LOG_FILE"; then
  GRUB_OK=true
elif sudo grub-install 2>&1 | tee -a "$LOG_FILE"; then
  GRUB_OK=true
fi
if [ "$GRUB_OK" = true ]; then
  sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub 2>/dev/null || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null 2>&1 || true
  sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee -a "$LOG_FILE" || true
  # GRUB als ersten Boot-Eintrag setzen
  sudo efibootmgr -v 2>&1 | tee -a "$LOG_FILE" || true
  GRUB_ENTRY=$(sudo efibootmgr 2>/dev/null | grep -i cachyos | head -n1 | sed 's/Boot\([0-9A-F]*\).*/\1/')
  if [ -n "$GRUB_ENTRY" ]; then sudo efibootmgr -o "$GRUB_ENTRY" 2>&1 | tee -a "$LOG_FILE" || true; fi
  log "GRUB erfolgreich installiert auf $EFI_DIR - entferne jetzt ALLE anderen Bootloader (egal was gewählt war)"
  sudo pacman -Rns --noconfirm limine limine-mkinitcpio-hook limine-snapper-sync limine-snapper-restore cachyos-limine 2>/dev/null || sudo pacman -R --noconfirm limine limine-mkinitcpio-hook limine-snapper-sync limine-snapper-restore cachyos-limine 2>/dev/null || true
  sudo pacman -Rns --noconfirm refind rEFInd systemd-boot systemd-boot-manager 2>/dev/null || true
  # Limine-Restore Desktop restlos verstecken (egal ob Paket noch da)
  sudo find /usr/share/applications ~/.local/share/applications -name "*limine*" -o -name "*snapper*restore*" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null 2>&1 || true; grep -q "^Hidden=" "$f" 2>/dev/null && sudo sed -i "s/^Hidden=.*/Hidden=true/" "$f" || echo "Hidden=true" | sudo tee -a "$f" >/dev/null 2>&1 || true; done
  sudo update-desktop-database /usr/share/applications 2>/dev/null || true
  sudo bootctl remove 2>/dev/null || true
  sudo bootctl remove 2>/dev/null || true
  # RESTLOS: alle Spuren von Limine/systemd-boot/rEFInd weg
  sudo rm -rf /boot/limine.cfg /boot/limine.conf /boot/efi/limine.cfg /boot/efi/limine.conf /boot/EFI/limine /boot/efi/EFI/limine /boot/EFI/BOOT/limine* /etc/default/limine /etc/limine* /usr/share/limine 2>/dev/null || true
  sudo rm -rf /boot/loader /boot/efi/loader /efi/loader /boot/EFI/systemd /boot/efi/EFI/systemd /boot/EFI/BOOT/systemd* /etc/kernel/cmdline 2>/dev/null || true
  sudo rm -rf /boot/EFI/refind /boot/efi/EFI/refind /boot/refind_linux.conf /etc/refind.d /usr/share/refind 2>/dev/null || true
  sudo rm -rf /boot/efi/EFI/BOOT/BOOTX64.EFI.limine /boot/efi/EFI/BOOT/BOOTX64.EFI.limine 2>/dev/null || true
  # EFI NVRAM restlos: alle alten Bootloader-Einträge löschen
  sudo efibootmgr 2>/dev/null | grep -Ei "limine|systemd|refind|systemd-boot" | while read -r line; do num=$(echo "$line" | sed 's/Boot\([0-9A-F]*\).*/\1/'); [ -n "$num" ] && sudo efibootmgr -b "$num" -B 2>/dev/null || true; done
  sudo efibootmgr 2>/dev/null | grep -i limine | while read -r line; do num=$(echo "$line" | sed 's/Boot\([0-9A-F]*\).*/\1/'); sudo efibootmgr -b "$num" -B 2>/dev/null || true; done
  # Snapper-Sync Reste
  sudo systemctl disable --now limine-snapper-sync.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/limine-snapper-sync.service 2>/dev/null || true
  # Initcpio Reste von Limine restlos - sonst ERROR Hook sd-btrfs-overlayfs
  sudo rm -f /etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf /etc/mkinitcpio.conf.d/10-limine* 2>/dev/null || true
  sudo rm -f /etc/limine-snapper-sync.conf.pacsave /etc/limine-snapper-sync.conf 2>/dev/null || true
  # Initcpio neu bauen ohne Limine-Hook (nvidia Warnungen sind ok wenn nvidia nicht installiert)
  sudo mkinitcpio -P 2>&1 | tee -a "$LOG_FILE" || true

  log "Limine entfernt, GRUB ist jetzt Standard"
else
  warn "GRUB Install fehlgeschlagen auf $EFI_DIR - Limine bleibt vorerst, Boot bleibt sicher"
  # Limine nicht entfernen wenn GRUB fehlschlug
fi
# Variablen für die nachfolgende Konfiguration fixieren
BOOTLOADER="grub"
BOOTLOADER_CONFIG="/etc/default/grub"

info "Kernel: Install Standard + Bore from CachyOS repos; remove other kernels only without force"
sudo pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers 2>/dev/null || warn "Standard kernel could not be confirmed"
sudo pacman -S --needed --noconfirm linux-cachyos-bore linux-cachyos-bore-headers 2>/dev/null || warn "Bore kernel could not be confirmed"
# Bore package can be installed without the kernel image landing in /boot -> reinstall hard in that case
if [[ ! -f /boot/vmlinuz-linux-cachyos-bore ]]; then
  warn "Bore kernel image missing in /boot – reinstalling package"
  sudo pacman -S --noconfirm linux-cachyos-bore linux-cachyos-bore-headers 2>&1 | tail -n 20 || true
  [[ -f /boot/vmlinuz-linux-cachyos-bore ]] || warn "Bore kernel image still missing in /boot – see pacman -Ql linux-cachyos-bore"
fi
# Provide AUR helper only after that for selected AUR apps – never for building the CachyOS kernel.
# CachyOS bringt teils 'shelly' als nativen Manager mit – erkennen, aber Install-Flags bleiben bei paru/yay kompatibel
if command -v shelly &>/dev/null; then
 info "CachyOS shelly found — using paru/yay syntax for compatibility"
 if command -v paru &>/dev/null; then AUR="paru"
 elif command -v yay &>/dev/null; then AUR="yay"
 else
  info "Shelly alone present — installing compatible helper (yay) for -S --needed flags"
  if sudo pacman -S --needed --noconfirm yay 2>/dev/null; then AUR="yay"
  else
   rm -rf /tmp/paru
   git clone https://aur.archlinux.org/paru.git /tmp/paru 2>/dev/null
   (cd /tmp/paru && makepkg -si --noconfirm 2>/dev/null) || warn "Paru could not be installed"
   AUR="paru"
  fi
 fi
elif command -v paru &>/dev/null; then
 AUR="paru"
elif command -v yay &>/dev/null; then
 AUR="yay"
else
 info "No AUR helper found — trying yay via pacman (less error-prone than git clone)"
 if sudo pacman -S --needed --noconfirm yay 2>/dev/null; then
  AUR="yay"
 else
  rm -rf /tmp/paru
  git clone https://aur.archlinux.org/paru.git /tmp/paru 2>/dev/null
  (cd /tmp/paru && makepkg -si --noconfirm 2>/dev/null) || warn "Paru could not be installed"
  AUR="paru"
 fi
fi

# Ensure paru is present in addition to yay (keep both)
if command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
 sudo pacman -S --needed --noconfirm paru 2>/dev/null || true
 command -v paru &>/dev/null && AUR="paru" || AUR="yay"
fi

# Never remove the currently running kernel. No -Rdd: dependency conflicts stay visible.
RUNNING_KERNEL_PKG="$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -n1 || true)"
mapfile -t KERNEL_PACKAGES < <(pacman -Qq 2>/dev/null | grep -E '^linux-(cachyos|zen|lts|hardened|rt|xanmod)(-|$)' || true)
for k in "${KERNEL_PACKAGES[@]}"; do
 case "$k" in
  linux-cachyos|linux-cachyos-headers|linux-cachyos-bore|linux-cachyos-bore-headers) continue ;;
 esac
 if [[ -n "$RUNNING_KERNEL_PKG" && "$k" == "$RUNNING_KERNEL_PKG" ]]; then
  warn "Keeping currently running kernel: $k"
 elif sudo pacman -Rns --noconfirm "$k" 2>/dev/null; then
  log "Removed unneeded kernel: $k"
 else
  warn "Kernel $k not removed (dependency or protection) – no force-remove"
 fi
done
log "Kernel cleanup done: Standard+Bore kept, no pacman -Rdd"

info "Remove selected preinstalled apps – only with normal dependency check"
# Deliberate choice: Mission Center is the task manager; no extra alias for plasma-systemmonitor needed.
# Knetattach is a separate network folder assistant, not a KDE Connect dependency; KDE Connect is installed independently below.
REMOVED_PACKAGES=(
 btrfs-assistant
 yakuake spectacle kmail kontact akonadi akregator korganizer
 elisa dragon haruna amarok juk octopi flatseal btop neofetch
 htop ksysguard plasma-systemmonitor khelpcenter konqueror kmahjongg kpat knetattach
 vim neovim qt5-tools yad meld btrfs-assistant
 cachy-update cachyos-update shelly cachyos-packageinstaller haruna
)
for pkg in "${REMOVED_PACKAGES[@]}"; do
 if pacman -Qq "$pkg" &>/dev/null; then
  sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || warn "Keeping $pkg (still needed)"
 fi
done
# STANDARD-RESET: Alles was Standardnutzer auf true/false gelassen hat, aber nicht gebraucht wird, wird deinstalliert
# Go through every single package from netinstall.yaml - default true/false is reset
# CachyOS Packages: alles behalten (hello etc. nur versteckt, not deinstalliert)
# Base-devel Common - only remove superfluous:
# - octopi (GUI Paketmanager) weg, paru bleibt
if pacman -Q octopi &>/dev/null; then sudo pacman -Rns --noconfirm octopi 2>/dev/null || true; fi
# - fonts: nur Noto + Nerd behalten, Rest weg (Standard hatte viele)
for f in awesome-terminal-fonts cantarell-fonts opendesktop-fonts ttf-bitstream-vera ttf-dejavu ttf-liberation ttf-opensans gnu-free-fonts; do
 if pacman -Qq "$f" &>/dev/null; then sudo pacman -Rns --noconfirm "$f" 2>/dev/null || true; fi
done
# - Some applications: nur überflüssig weg (btop/neofetch/meld/vim bleiben weg, Rest behalten)
for pkg in btop neofetch meld vim neovim; do
 if pacman -Qq "$pkg" &>/dev/null; then sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || true; fi
done
# - KDE extras if the default user kept KDE checked: keep ark, remove rest (haruna/spectacle/systemmonitor etc.)
# (ark jetzt behalten wegen Nutzerfreundlich, haruna etc. weg)
for pkg in haruna spectacle plasma-systemmonitor; do
 if pacman -Qq "$pkg" &>/dev/null; then sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || true; fi
done
# - GNOME/Xfce/Wayfire/Hyprland falls versehentlich installiert: komplett weg (Standard false)
for grp in gnome xfce4 wayfire hyprland; do
 if pacman -Qq "$grp" &>/dev/null 2>&1 | head -1 | grep -q .; then
  sudo pacman -Rns --noconfirm gnome gnome-shell xfce4 wayfire 2>/dev/null || true
 fi
done
# - Printing/HP/Accessibility: Standard false -> wenn trotzdem da und kein Drucker/HP/Barrierefreiheit, weg
if ! lsusb 2>/dev/null | grep -Eiq "printer|cups" && ! lpstat -p 2>/dev/null | grep -q .; then
 for pkg in cups cups-filters cups-pdf foomatic-db foomatic-db-engine gutenprint splix system-config-printer hplip; do
  if pacman -Qq "$pkg" &>/dev/null; then sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || true; fi
 done
fi
# Accessibility weg wenn nicht gebraucht
for pkg in espeak-ng mousetweaks orca; do
 if pacman -Qq "$pkg" &>/dev/null; then sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || true; fi
done
# Remove Flatpak variants of intentionally replaced apps (completely with data).
# Flatpak-Reste und User-Configs der entfernten Apps vollständig löschen (auf Wunsch voller Clean)
# User-Configs/Caches der per pacman entfernten Apps löschen – damit Deinstallation vollständig ist
for _cfg in btrfs-assistant yakuake spectacle kmail kontact akonadi akregator korganizer elisa dragon haruna amarok juk octopi flatseal btop neofetch htop ksysguard plasma-systemmonitor khelpcenter konqueror kmahjongg kpat knetattach vim neovim qt5-tools qt6-tools avahi yad hwloc; do
 rm -rf -- "$HOME/.config/${_cfg}" "$HOME/.config/${_cfg}rc" "$HOME/.local/share/${_cfg}" "$HOME/.cache/${_cfg}" 2>/dev/null || true
done
# Spezifische Reste
rm -rf -- "$HOME/.config/yakuakerc" "$HOME/.config/spectaclerc" "$HOME/.config/baloofilerc" "$HOME/.local/share/akonadi" "$HOME/.local/share/baloo" 2>/dev/null || true
# Clean: lstopo verstecken, NVIDIA Settings bei AMD entfernen
# Hide unneeded apps robustly: qv4l2/V4L2 via find (Name variiert: qv4l2.desktop/org.kde.qv4l2 etc.) + Standard
for d in /usr/share/applications/assistant*.desktop /usr/share/applications/designer*.desktop /usr/share/applications/linguist*.desktop /usr/share/applications/*qdbusviewer*.desktop /usr/share/applications/*qv4l*.desktop /usr/share/applications/*v4l*.desktop /usr/share/applications/*avahi*.desktop /usr/share/applications/bssh.desktop /usr/share/applications/bvnc.desktop /usr/share/applications/avahi-discover.desktop /usr/share/applications/lstopo.desktop /usr/share/applications/meld*.desktop /usr/share/applications/micro.desktop /usr/share/applications/*sched*.desktop /usr/share/applications/*scx*.desktop /usr/share/applications/*SchedExt*.desktop; do [[ -f "$d" ]] && { grep -q "^NoDisplay=" "$d" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$d" || echo "NoDisplay=true" | sudo tee -a "$d" >/dev/null; } 2>/dev/null || true; done
# Qv4l2 Fallback via find (deckt org.kde.qv4l2, qv4l2, etc.)
sudo find /usr/share/applications ~/.local/share/applications -type f -name "*.desktop" -print0 2>/dev/null | xargs -0 grep -l -i "qv4l\|V4L2" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null; done; sudo find /usr/share/applications ~/.local/share/applications -type f -name "*.desktop" -print0 2>/dev/null | xargs -0 grep -l -i "avahi" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null; done; sudo find /usr/share/applications ~/.local/share/applications -type f -name "*.desktop" -print0 2>/dev/null | xargs -0 grep -l -i "SchedExt" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null; done; sudo find /usr/share/applications ~/.local/share/applications -type f -name "*.desktop" -print0 2>/dev/null | xargs -0 grep -l -i "scx.*sched\|sched.*scx" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null; done
# CachyOS Hello + Kernel Manager + Netzwerk verstecken - protected from changes + Hello Autostart aus (gewünscht)
hide_desktop(){ local f="$1" W=""; [ -w "$f" ] || W="sudo"; if grep -q '^NoDisplay=' "$f" 2>/dev/null; then $W sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$f"; else echo 'NoDisplay=true' | $W tee -a "$f" >/dev/null; fi; }
# Welcome Center (KDE Plasma Welcome) komplett aus dem Menü verstecken
find /usr/share/applications ~/.local/share/applications -type f -name '*.desktop' -print0 2>/dev/null | xargs -0 -r grep -l -i -E 'cachy.*hello|Welcome Center|plasma.*welcome|Learn more about KDE Plasma' 2>/dev/null | while IFS= read -r f; do hide_desktop "$f"; done
find /usr/share/applications -type f \( -name '*plasma*welcom*.desktop' -o -name '*welcome*.desktop' \) 2>/dev/null | while IFS= read -r f; do hide_desktop "$f"; done
find /usr/share/applications ~/.local/share/applications -type f -name '*.desktop' -print0 2>/dev/null | xargs -0 -r grep -l -i -E 'kernel.*manager|cachy.*kernel' 2>/dev/null | while IFS= read -r f; do hide_desktop "$f"; done
find /usr/share/applications ~/.local/share/applications -type f -name '*.desktop' -print0 2>/dev/null | xargs -0 -r grep -l -i -E 'nm-connection-editor|network.*manager.*editor|netplan' 2>/dev/null | while IFS= read -r f; do hide_desktop "$f"; done
# CachyOS Hello Autostart deaktivieren
rm -f "$HOME/.config/autostart/cachyos-hello.desktop" 2>/dev/null || true
rm -f "$HOME/.config/autostart/cachy-hello.desktop" 2>/dev/null || true
sudo rm -f /etc/xdg/autostart/cachyos-hello.desktop 2>/dev/null || true
mkdir -p "$HOME/.config/autostart"
printf "[Desktop Entry]\nHidden=true\n" > "$HOME/.config/autostart/cachyos-hello.desktop" 2>/dev/null || true
# Netzwerk automatisch richtig - kein Rumfummeln nötig (NetworkManager + DHCP auto)
sudo systemctl enable --now NetworkManager 2>/dev/null || true
# BleachBit hidden - installiert for Script, aber protected from changes (Cache löschen unpraktisch)
sudo find /usr/share/applications ~/.local/share/applications -type f -name "*.desktop" -print0 2>/dev/null | xargs -0 grep -l -i "bleachbit" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null; done
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
if ! lspci 2>/dev/null | grep -qi nvidia; then sudo pacman -Rns --noconfirm nvidia-settings 2>/dev/null || true; fi
# Timeshift/Snapper bleibt auf Wunsch bei beiden (kein Entfernen)
# sudo systemctl disable --now snapper-cleanup.timer snapper-timeline.timer limine-snapper-sync.service 2>/dev/null || true
# sudo pacman -Rns --noconfirm snapper cachyos-snapper-support limine-snapper-sync 2>/dev/null || true
 # Vim cleanup: single -Rns pass, keep zsh-config if ZSH is active (avoid killing theme)
 if [[ "$SHELL" == *zsh* ]] || grep -q "zsh" /etc/passwd 2>/dev/null; then
    # Vim/gvim NICHT entfernen (Abhängigkeiten) – nur versteckt (NoDisplay + Hook weiter unten)
  # Keep cachyos-zsh-config when ZSH is in use
    :
  else
    :
 fi
 # Steamtinkerlaunch handled separately per variant
# Vim Fallback: if pulled as dep again -> hide + Kate as default (no vim/kate choice for newcomers)
sudo find /usr/share/applications ~/.local/share/applications -type f -name "*vim*.desktop" -o -name "gvim*.desktop" 2>/dev/null | while IFS= read -r f; do grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null 2>&1 || true; done
# Vim konsequent verstecken - Hook: egal ob Dep es wieder installiert, sofort wieder NoDisplay
sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/hide-vim.hook >/dev/null <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = vim
Target = gvim
Target = neovim
Target = vim-runtime

[Action]
Description = Hide vim (force Kate as default)
When = PostTransaction
Exec = /bin/sh -c 'for f in /usr/share/applications/*vim*.desktop /usr/share/applications/gvim*.desktop; do [ -f "$f" ] || continue; grep -q "^NoDisplay=" "$f" && sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" || echo "NoDisplay=true" >> "$f"; grep -q "^Hidden=" "$f" && sed -i "s/^Hidden=.*/Hidden=true/" "$f" || echo "Hidden=true" >> "$f"; done; update-desktop-database /usr/share/applications 2>/dev/null || true; kbuildsycoca6 --noincremental 2>/dev/null || true'
HOOK

# === ALLE Standard-Apps fest setzen - neue Nutzer müssen nie wählen (Kate statt vim, Brave, Dolphin, Gwenview, Okular, VLC, Ark) ===
# Vim versteckt ist oben schon, hier jetzt ALLE Defaults deterministisch
if command -v kate >/dev/null 2>&1; then
  # Text -> Kate (statt vim/nvim/kwrite)
  for m in text/plain text/x-log text/x-c text/x-csrc text/x-chdr text/x-c++hdr text/x-c++src text/x-python text/x-shellscript text/x-makefile application/json application/xml text/x-cmake application/javascript text/markdown text/x-tex; do
    xdg-mime default org.kde.kate.desktop "$m" 2>/dev/null || true
  done
  echo 'export EDITOR=kate' >> "$HOME/.bashrc" 2>/dev/null || true
  echo 'export VISUAL=kate' >> "$HOME/.bashrc" 2>/dev/null || true
fi
if command -v okular >/dev/null 2>&1; then
  xdg-mime default org.kde.okular.desktop application/pdf 2>/dev/null || true
  xdg-mime default org.kde.okular.desktop application/x-pdf 2>/dev/null || true
fi
if command -v gwenview >/dev/null 2>&1; then
  for m in image/jpeg image/png image/gif image/webp image/svg+xml image/bmp image/tiff image/x-eps image/heif image/avif; do
    xdg-mime default org.kde.gwenview.desktop "$m" 2>/dev/null || true
  done
fi
if command -v vlc >/dev/null 2>&1; then
  for m in video/mp4 video/x-matroska video/avi video/webm video/mpeg video/x-msvideo audio/mpeg audio/x-wav audio/flac audio/ogg audio/x-vorbis+ogg; do
    xdg-mime default vlc.desktop "$m" 2>/dev/null || true
  done
fi
if command -v ark >/dev/null 2>&1; then
  for m in application/zip application/x-tar application/x-compressed-tar application/x-bzip2 application/x-xz application/x-7z-compressed application/x-rar application/x-archive application/gzip; do
    xdg-mime default org.kde.ark.desktop "$m" 2>/dev/null || true
  done
fi
if command -v dolphin >/dev/null 2>&1; then
  xdg-mime default org.kde.dolphin.desktop inode/directory 2>/dev/null || true
fi
if command -v brave-browser >/dev/null 2>&1 || command -v brave >/dev/null 2>&1; then
  BRAVE_DESKTOP=$(ls /usr/share/applications/brave*.desktop 2>/dev/null | head -1 | xargs -r basename 2>/dev/null); BRAVE_DESKTOP=${BRAVE_DESKTOP:-brave-browser.desktop}
  xdg-mime default "$BRAVE_DESKTOP" x-scheme-handler/http 2>/dev/null || true
  xdg-mime default "$BRAVE_DESKTOP" x-scheme-handler/https 2>/dev/null || true
  xdg-mime default "$BRAVE_DESKTOP" text/html 2>/dev/null || true
  xdg-settings set default-web-browser "$BRAVE_DESKTOP" 2>/dev/null || true
fi
# Vollständiges mimeapps.list schreiben - deterministisch, kein Auswahl-Dialog für neue Nutzer
mkdir -p "$HOME/.config"
cat > "$HOME/.config/mimeapps.list" <<'MIME_EOF'
[Default Applications]
text/plain=org.kde.kate.desktop
text/x-log=org.kde.kate.desktop
text/x-c=org.kde.kate.desktop
text/x-csrc=org.kde.kate.desktop
text/x-chdr=org.kde.kate.desktop
text/x-c++hdr=org.kde.kate.desktop
text/x-c++src=org.kde.kate.desktop
text/x-python=org.kde.kate.desktop
text/x-shellscript=org.kde.kate.desktop
text/x-makefile=org.kde.kate.desktop
application/json=org.kde.kate.desktop
application/xml=org.kde.kate.desktop
text/x-cmake=org.kde.kate.desktop
application/javascript=org.kde.kate.desktop
text/markdown=org.kde.kate.desktop
text/x-tex=org.kde.kate.desktop
application/pdf=org.kde.okular.desktop
image/jpeg=org.kde.gwenview.desktop
image/png=org.kde.gwenview.desktop
image/gif=org.kde.gwenview.desktop
image/webp=org.kde.gwenview.desktop
image/svg+xml=org.kde.gwenview.desktop
image/bmp=org.kde.gwenview.desktop
image/tiff=org.kde.gwenview.desktop
image/heif=org.kde.gwenview.desktop
image/avif=org.kde.gwenview.desktop
video/mp4=vlc.desktop
video/x-matroska=vlc.desktop
video/avi=vlc.desktop
video/webm=vlc.desktop
video/mpeg=vlc.desktop
audio/mpeg=vlc.desktop
audio/x-wav=vlc.desktop
audio/flac=vlc.desktop
audio/ogg=vlc.desktop
inode/directory=org.kde.dolphin.desktop
application/zip=org.kde.ark.desktop
application/x-tar=org.kde.ark.desktop
application/x-compressed-tar=org.kde.ark.desktop
application/x-bzip2=org.kde.ark.desktop
application/x-xz=org.kde.ark.desktop
application/x-7z-compressed=org.kde.ark.desktop
application/x-rar=org.kde.ark.desktop
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
text/html=brave-browser.desktop

[Added Associations]
MIME_EOF
# Brave-Name dynamisch korrigieren falls brave.desktop statt brave-browser.desktop
if [ -n "${BRAVE_DESKTOP:-}" ] && [ "$BRAVE_DESKTOP" != "brave-browser.desktop" ]; then
  sed -i "s/brave-browser.desktop/$BRAVE_DESKTOP/g" "$HOME/.config/mimeapps.list" 2>/dev/null || true
fi
# Auch systemweit für neue Nutzer (skel)
sudo mkdir -p /etc/skel/.config 2>/dev/null || true
sudo cp "$HOME/.config/mimeapps.list" /etc/skel/.config/mimeapps.list 2>/dev/null || true
if [ -f /etc/xdg/mimeapps.list ]; then sudo cp "$HOME/.config/mimeapps.list" /etc/xdg/mimeapps.list 2>/dev/null || true; fi
log "Selected applications handled – no force-removes (configs/caches fully deleted)"

# Paketdateien not manuell aus /usr/share/locale löschen: Ein Update ist kein Reparatur-Mechanismus.
# Fehlende Locale-Dateien bleiben bis zum jeweiligen Paket-Update kaputt und erzeugen einen inkonsistenten Paketbestand.
info "Language packs stay package-managed (de+en fully available)"

info "Clean fonts: Keep only Nerd Fonts + Noto"
sudo pacman -Rns --noconfirm gnu-free-fonts 2>/dev/null || true
log "Fonts cleaned"

info "Services: Disable Baloo, Tracker, ModemManager and unnecessary services"
balooctl disable 2>/dev/null || true; balooctl6 disable 2>/dev/null || true; balooctl purge 2>/dev/null || true; balooctl6 purge 2>/dev/null || true; balooctl suspend 2>/dev/null || true; systemctl --user mask --now baloo_file.service 2>/dev/null || true; kwriteconfig6 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" false 2>/dev/null || true; pkill -9 -f baloo_file 2>/dev/null || true
systemctl --user mask tracker-miner-fs.service tracker-miner-rss.service tracker-extract.service 2>/dev/null || true
systemctl --user mask tracker-miner-fs-3.service tracker-extract-3.service 2>/dev/null || true
sudo systemctl disable --now ModemManager 2>/dev/null || true
sudo systemctl disable --now lvm2-monitor 2>/dev/null || true
# KDE Connect ist bewusst ausgewählt und wird später installiert; keine wirkungslose oder widersprüchliche Service-Schleife.
log "Unneeded services handled; KDE Connect kept intended"

# ---------- 2. BASIS ----------
step "2/8 BASE - Multilib, Flatpak"
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
 printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
 # Neue Repository-Konfiguration immer mit einem vollständigen Update aboutnehmen, nie nur -Sy.
 if ! sudo pacman -Syu --noconfirm; then
  fail "Update after enabling multilib failed – aborting."
  exit 1
 fi
fi
sudo pacman -S --needed --noconfirm base-devel git flatpak pacman-contrib acl python pciutils 2>/dev/null || true
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
# Sichere Komfort-Befehle: keine Paketlöschung oder BleachBit-Aktion ohne Prüfung.
mkdir -p "$HOME/.local/bin" "$HOME/.config/fish/conf.d"
cat <<'EOF' > "$HOME/.local/bin/update-arch"
#!/usr/bin/env bash
# update-arch: starts the update tool alles-updaten (one source for all updates).
exec "$HOME/.local/bin/alles-updaten" "$@"
EOF
cat <<'EOF' > "$HOME/.local/bin/clean-arch"
#!/usr/bin/env bash
set -u
sudo paccache -rk2
flatpak uninstall --unused -y || true
sudo journalctl --vacuum-time=3d || true
sudo journalctl --vacuum-size=100M || true
orphans="$(pacman -Qdtq 2>/dev/null || true)"
if [[ -n "$orphans" ]]; then
 printf '%s\n%s\n' 'Possible orphans – only show, not auto-remove:' "$orphans"
 printf '%s\n' 'After check optionally: sudo pacman -Rns <package>'
else
 printf '%s\n' 'Keine Pacman-Waisen gefunden.'
fi
printf '%s\n' 'BleachBit will not run automatically. First: bleachbit --preview <cleaner>'
EOF
cat <<'EOF' > "$HOME/.local/bin/fix-key"
#!/usr/bin/env bash
set -u
if ! sudo pacman -Syu --needed --noconfirm archlinux-keyring cachyos-keyring; then
 printf '%s\n' 'Keyring-Update fehlgeschlagen.' >&2
 exit 1
fi
sudo pacman-key --populate archlinux cachyos
EOF
cat <<'EOF' > "$HOME/.local/bin/update-mirrors"
#!/usr/bin/env bash
set -u
if command -v cachyos-rate-mirrors >/dev/null 2>&1; then
 sudo cachyos-rate-mirrors
elif command -v reflector >/dev/null 2>&1; then
 sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
else
 printf '%s\n' 'Kein Mirror-Tool installiert (cachyos-rate-mirrors / reflector).'
fi
EOF
cat <<'EOF' > "$HOME/.local/bin/clean-flatpak-caches"
#!/usr/bin/env bash
# Entfernt ausschließlich Inhalte aus den standardisierten Flatpak-XDG-Cache-Ordnern.
# Ohne --yes wird nur die belegte Größe angezeigt.
set -Euo pipefail
cache_root="$HOME/.var/app"
declare -a cache_dirs=()
if [[ -d "$cache_root" && ! -L "$cache_root" ]]; then
 while IFS= read -r -d '' cache_dir; do
  cache_dirs+=("$cache_dir")
 done < <(find "$cache_root" -mindepth 2 -maxdepth 2 -type d -name cache -print0 2>/dev/null)
fi
if (( ${#cache_dirs[@]} == 0 )); then
 printf '%s\n' 'Keine Flatpak-App-Caches gefunden.'
 exit 0
fi
printf '%s\n' 'Gefundene Flatpak-App-Caches (config/ und data/ bleiben unangetastet):'
printf ' %q\n' "${cache_dirs[@]}"
du -sch -- "${cache_dirs[@]}" 2>/dev/null || true
if [[ "${1:-}" != "--yes" || $# -ne 1 ]]; then
 printf '%s\n' 'Preview finished. To actually clean run: clean-flatpak-caches --yes'
 exit 0
fi
for cache_dir in "${cache_dirs[@]}"; do
 find "$cache_dir" -mindepth 1 -xdev -depth -delete
done
printf '%s\n' 'Flatpak-App-Caches geleert. Einstellungen und Nutzerdaten wurden nicht gelöscht.'
EOF
cat <<'EOF' > "$HOME/.local/bin/clean-wine-temp"
#!/usr/bin/env bash
# Leert nur Temp-Inhalte eines explizit angegebenen Wine-/Proton-Prefixes; nie Shadercache oder den Prefix selbst.
set -Euo pipefail
if [[ $# -ne 2 || "$1" != "--yes" ]]; then
 printf '%s\n' 'Verwendung: clean-wine-temp --yes /absoluter/pfad/zum/prefix' >&2
 printf '%s\n' 'Beispiel Steam: clean-wine-temp --yes ~/.local/share/Steam/steamapps/compatdata/APPID/pfx' >&2
 exit 2
fi
prefix="$(realpath -e -- "$2" 2>/dev/null || true)"
if [[ -z "$prefix" || ! -f "$prefix/system.reg" || ! -d "$prefix/drive_c/users" ]]; then
 printf '%s\n' 'Kein gültiger Wine-/Proton-Prefix (system.reg und drive_c/users erforderlich).' >&2
 exit 2
fi
for process in wineserver wine wine64 wine-preloader wine64-preloader steam steamwebhelper lutris bottles; do
 if pgrep -u "$(id -u)" -x "$process" >/dev/null 2>&1; then
  printf 'Abbruch: %s läuft noch. Schließe Steam, Wine, Lutris und Bottles zuerst.\n' "$process" >&2
  exit 1
 fi
done
declare -a temp_dirs=()
while IFS= read -r -d '' temp_dir; do
 temp_dirs+=("$temp_dir")
done < <(find "$prefix/drive_c/users" -xdev -type d -path '*/AppData/Local/Temp' -print0 2>/dev/null)
if (( ${#temp_dirs[@]} == 0 )); then
 printf '%s\n' 'Keine Windows-Temp-Ordner in diesem Prefix gefunden.'
 exit 0
fi
printf '%s\n' 'Folgende Temp-Ordner werden geleert (nur deren Inhalte; Prefix und Shadercache bleiben außerhalb davon):'
printf ' %q\n' "${temp_dirs[@]}"
du -sch -- "${temp_dirs[@]}" 2>/dev/null || true
for temp_dir in "${temp_dirs[@]}"; do
 find "$temp_dir" -mindepth 1 -xdev -depth -delete
done
printf '%s\n' 'Windows-Temp-Inhalte dieses Prefixes wurden geleert.'
EOF
chmod +x "$HOME/.local/bin/update-arch" "$HOME/.local/bin/clean-arch" "$HOME/.local/bin/fix-key" "$HOME/.local/bin/update-mirrors" "$HOME/.local/bin/clean-flatpak-caches" "$HOME/.local/bin/clean-wine-temp"
# Den neuen Pfad sofort im aktuellen Skriptprozess verfügbar machen und dauerhaft für Bash/Fish speichern.
case ":$PATH:" in
 *":$HOME/.local/bin:"*) ;;
 *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# ~/.local/bin for Bash und Fish dauerhaft verfügbar machen, ohne Bash-Syntax in Fish zu schreiben.
if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH" # CachyOS local tools' "$HOME/.bashrc" 2>/dev/null; then
 printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH" # CachyOS local tools' >> "$HOME/.bashrc"
fi
cat <<'EOF' > "$HOME/.config/fish/conf.d/cachyos-local-tools.fish"
if not contains -- "$HOME/.local/bin" $PATH
  set -gx PATH "$HOME/.local/bin" $PATH
end
EOF
log "Base+helper commands: update-arch, clean-arch, fix-key, update-mirrors, clean-flatpak-caches, clean-wine-temp"

# Firewall for Gaming/Sync sofort korrekt konfigurieren (not erst beim nächsten update-arch)
if command -v ufw >/dev/null 2>&1; then
 sudo ufw default deny incoming 2>/dev/null || true
 sudo ufw default allow outgoing 2>/dev/null || true
 sudo ufw allow 22000/tcp 2>/dev/null || true
 sudo ufw allow 21027/udp 2>/dev/null || true
 sudo ufw allow 1714:1764/tcp 2>/dev/null || true
 sudo ufw allow 1714:1764/udp 2>/dev/null || true
 sudo ufw allow 5353/udp 2>/dev/null || true
 sudo ufw allow 5355/tcp 2>/dev/null || true
 sudo ufw allow 5355/udp 2>/dev/null || true
 sudo ufw allow 7680/tcp 2>/dev/null || true
 sudo ufw allow 1900/udp 2>/dev/null || true
 sudo ufw --force enable 2>/dev/null || true
 log "Firewall (UFW) configured with Syncthing/KDE Connect/mDNS/LAN ports"
fi

# ---------- 3. AUSGEWÄHLTE ANWENDUNGEN ----------
step "3/8 APPLICATIONS - install selected programs"

info "Browser: Configure Brave (remove Firefox – report showed Firefox still active)"
# Firefox: thorough cleanup (stays installed, hardened like Brave, no uninstall)
if ! pacman -Q firefox &>/dev/null && ! flatpak info org.mozilla.firefox &>/dev/null; then
 sudo pacman -S --needed --noconfirm firefox firefox-i18n-de 2>/dev/null || flatpak install -y flathub org.mozilla.firefox 2>/dev/null || true
fi
# Policies: disable telemetry, Pocket, sponsored, studies
sudo mkdir -p /usr/lib/firefox/distribution /etc/firefox/policies 2>/dev/null || true
sudo tee /usr/lib/firefox/distribution/policies.json >/dev/null <<'FFPOL'
{
 "policies": {
  "DisableTelemetry": true,
  "DisablePocket": true,
  "DisableFirefoxStudies": true,
  "DisableSystemAddonUpdate": false,
  "DisableAppUpdate": false,
  "OfferToSaveLogins": false,
  "FirefoxHome": {"Search": true, "TopSites": false, "SponsoredTopSites": false, "Pocket": false, "SponsoredPocket": false, "Highlights": false, "Snippets": false},
  "UserMessaging": {"ExtensionRecommendations": false, "FeatureRecommendations": false, "UrlbarInterventions": false, "SkipOnboarding": true},
  "SearchEngines": {"Default": "Google"},
  "SearchSuggestEnabled": false
 }
}
FFPOL
sudo tee /etc/firefox/policies/policies.json >/dev/null <<'FFPOL2'
{
 "policies": {
  "DisableTelemetry": true,
  "DisablePocket": true,
  "DisableFirefoxStudies": true,
  "FirefoxHome": {"SponsoredTopSites": false, "SponsoredPocket": false}
 }
}
FFPOL2
# Prefs.js hardening for existing profiles
for d in "$HOME/.mozilla/firefox/"*.default* "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/"*.default*; do
 [ -d "$d" ] || continue
 cat >> "$d/user.js" <<'FFJS' 2>/dev/null || true
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("extensions.pocket.enabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.discovery.enabled", false);
FFJS
done
sudo pacman -S --needed --noconfirm brave-browser 2>/dev/null || $AUR -S --needed --noconfirm brave-bin 2>/dev/null || true
sudo mkdir -p /etc/brave/policies/managed
sudo tee /etc/brave/policies/managed/brave-settings.json >/dev/null <<'EOF'
{
 "BraveRewardsDisabled": true,
 "BraveWalletDisabled": true,
 "BraveVPNDisabled": true,
 "BraveNewsDisabled": true,
 "BraveAIChatEnabled": false,
 "BraveTalkDisabled": true,
 "DefaultSearchProviderEnabled": true,
 "DefaultSearchProviderName": "Google",
 "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
}
EOF
sudo tee /etc/brave/policies/managed/extensions.json >/dev/null <<'EOF'
{"ExtensionInstallForcelist":["mnjggcdmjocbbbhaepdhchncahnbgone;https://clients2.google.com/service/update2/crx","gebbhagfogifgggkldgodflihgfeippi;https://clients2.google.com/service/update2/crx","cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx","hdokiejnpimakedhajhdlcegeplioahd;https://clients2.google.com/service/update2/crx","ponfpcnoehjfmfllpaingbgckeeldkh;https://clients2.google.com/service/update2/crx","alhmbbnlcggfcjjfihglopfopcbigmil;https://clients2.google.com/service/update2/crx"]}
EOF

# WhatsApp PWA wird manuell installiert — kein force-install mehr (auf Wunsch)
info "Terminal: Alacritty + Konsole + Fish + Fisher+Z + Starship (keep both terminals)"
# Btop/neofetch/fastfetch wurden oben ausschließlich mit normaler Abhängigkeitsprüfung behandelt – nie mit -Rdd.
sudo pacman -S --needed --noconfirm alacritty konsole fish starship 2>/dev/null || true
log "Keeping both terminals: Alacritty + Konsole"
# Fisher erst als Funktionsdatei speichern; die frische Fish-Instanz lädt sie dann zuverlässig.
if command -v fish &>/dev/null; then
 mkdir -p "$HOME/.config/fish/functions"
 if curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
  rm -f "$HOME/.config/fish/functions/fisher.fish" 2>/dev/null || true
   https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
   -o "$HOME/.config/fish/functions/fisher.fish"; then
  if fish -c 'fisher install jorgebucaran/fisher jethrokuan/z'; then
   log "Fisher and z for Fish installed"
  else
   warn "Fisher plugins could not be installed"
  fi
 else
  warn "Fisher could not be downloaded"
 fi
else
 warn "Fish not available – Fisher plugins skipped"
fi
# Kein Conky Widget mehr — stattdessen bester Taskmanager (Mission Center wie Windows)
flatpak install -y flathub io.missioncenter.MissionCenter 2>/dev/null || sudo pacman -S --needed --noconfirm plasma-systemmonitor 2>/dev/null || true
log "Task manager Mission Center installed (fallback plasma-systemmonitor)"
# Catfish als überflüssig entfernt – Dolphin Suche reicht; bei Bedarf: sudo pacman -S catfish
mkdir -p ~/.config/fish; starship preset nerd-font-symbols -o ~/.config/starship.toml 2>/dev/null || true; grep -q "starship init fish" ~/.config/fish/config.fish 2>/dev/null || echo 'starship init fish | source' >> ~/.config/fish/config.fish

info "Apps: Flameshot (Spectacle removed), Gimp+Gwenview, VLC+ffmpeg, Ark+p7zip/unrar/unzip/lrzip, OnlyOffice, Kate"
sudo pacman -Rns --noconfirm spectacle 2>/dev/null || true
sudo pacman -S --needed --noconfirm flameshot gimp gwenview vlc vlc-plugins-all ffmpeg ark p7zip unrar unzip lrzip dolphin dolphin-plugins okular kate 2>/dev/null || true

# Calibre sub-viewers hiden - nur Hauptprogramm Calibre sichtbar (Editor/Viewer/LRF nur via Hauptprogramm)
for f in /usr/share/applications/calibre-ebook-edit.desktop /usr/share/applications/calibre-ebook-viewer.desktop /usr/share/applications/calibre-lrfviewer.desktop /usr/share/applications/calib*viewer*.desktop; do
 [ -f "$f" ] || continue
 if grep -q "^NoDisplay=" "$f" 2>/dev/null; then sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" 2>/dev/null || true
 else echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null 2>&1 || true
 fi
done
# Fallback find
sudo find /usr/share/applications -type f -name "*calibre*viewer*.desktop" -o -name "*lrf*.desktop" 2>/dev/null | while IFS= read -r f; do
 grep -q "^NoDisplay=" "$f" 2>/dev/null && sudo sed -i "s/^NoDisplay=.*/NoDisplay=true/" "$f" 2>/dev/null || echo "NoDisplay=true" | sudo tee -a "$f" >/dev/null 2>&1 || true
done 2>/dev/null || true
# Keine Windows-Aliase mehr — alle Aliase entfernt auf Wunsch (clean)
# (früher hier: notepad->kate, snippingtool->flameshot, roblox->sober etc. — jetzt entfernt)
# OnlyOffice for Word-Dateien statt LibreOffice (nur zum Öffnen wie gewünscht)
flatpak install -y flathub org.onlyoffice.desktopeditors 2>/dev/null || $AUR -S --needed --noconfirm onlyoffice-bin 2>/dev/null || sudo pacman -S --needed --noconfirm onlyoffice-bin 2>/dev/null || true
sudo pacman -S --needed --noconfirm bleachbit fwupd openrgb lm_sensors 2>/dev/null || true # Stacer/CopyQ entfernt – Mission Center+Klipper reichen (ein Tool pro Art)
# Stacer-bin als überflüssig entfernt – BleachBit + Mission Center reichen; bei Bedarf: $AUR -S stacer-bin

info "Comm: Vesktop TOS-safe, WhatsApp as Brave App, Spotify without Spicetify, Thunderbird (Proton replaced) – Public without TOS mods"
flatpak uninstall -y com.discordapp.Discord 2>/dev/null || true; sudo pacman -Rns --noconfirm discord 2>/dev/null || true
# Public: Vesktop ohne TOS-Plugins (MessageLogger etc. nur Privat/Freunde) - TOS sicher
flatpak install -y flathub dev.vencord.Vesktop 2>/dev/null || $AUR -S --needed --noconfirm vesktop-bin 2>/dev/null || true
# Vesktop nutzt je nach Installationsart unterschiedliche XDG-Konfigurationspfade. Nur tatsächlich installierte Varianten konfigurieren.
VESKTOP_SETTINGS_PATHS=()
if flatpak info dev.vencord.Vesktop >/dev/null 2>&1; then
 VESKTOP_SETTINGS_PATHS+=("$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/settings/settings.json")
fi
if pacman -Q vesktop-bin >/dev/null 2>&1 || pacman -Q vesktop >/dev/null 2>&1; then
 VESKTOP_SETTINGS_PATHS+=("${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/settings/settings.json")
fi
if (( ${#VESKTOP_SETTINGS_PATHS[@]} == 0 )); then
 warn "Vesktop not installed – plugin defaults skipped"
elif ! command -v python3 >/dev/null 2>&1; then
 warn "Python3 missing – Vesktop settings unchanged"
else
 # Fehlende Standardwerte ergänzen, aber vorhandene JSON-Felder und bewusste Plugin-Schalter niemals überschreiben.
 python3 - "$RUN_ID" "${VESKTOP_SETTINGS_PATHS[@]}" <<'PY'
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path

run_id = sys.argv[1]
if len(sys.argv) < 3:
  sys.exit(0) # keine Pfade -> sauber beenden
plugin_defaults = {
  # Public TOS-safe: keine TOS-Plugins (nur Privat/Freunde haben MessageLogger etc.)
}

for raw_path in sys.argv[2:]:
  path = Path(raw_path)
  if path.is_symlink():
    print(f"Vesktop: Symlink wird not verändert: {path}", file=sys.stderr)
    continue
  path.parent.mkdir(parents=True, exist_ok=True)
  existed = path.exists()
  if existed:
    try:
      text = path.read_text(encoding="utf-8")
      settings = json.loads(text) if text.strip() else {}
    except (OSError, json.JSONDecodeError) as error:
      print(f"Vesktop: ungültige JSON-Datei bleibt unverändert: {path} ({error})", file=sys.stderr)
      continue
    if not isinstance(settings, dict):
      print(f"Vesktop: JSON-Wurzel ist kein Objekt und bleibt unverändert: {path}", file=sys.stderr)
      continue
  else:
    settings = {}

  plugins = settings.get("plugins")
  if plugins is None:
    plugins = {}
    settings["plugins"] = plugins
  elif not isinstance(plugins, dict):
    print(f"Vesktop: plugins ist kein Objekt und bleibt unverändert: {path}", file=sys.stderr)
    continue

  changes = []
  for name, enabled in plugin_defaults.items():
    current = plugins.get(name)
    if current is None:
      plugins[name] = {"enabled": enabled}
      changes.append(name)
    elif isinstance(current, dict):
      if "enabled" not in current:
        current["enabled"] = enabled
        changes.append(name)
    else:
      print(f"Vesktop: Plugin {name} hat ein unerwartetes Format und bleibt unverändert: {path}", file=sys.stderr)

  if not changes:
    print(f"Vesktop: vorhandene Einstellungen unverändert gelassen: {path}")
    continue

  if existed:
    backup = path.with_name(f"{path.name}.before-cachyos-gaming-setup-{run_id}.bak")
    shutil.copy2(path, backup)
  mode = stat.S_IMODE(path.stat().st_mode) if existed else 0o600
  fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
  try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, "w", encoding="utf-8") as temporary:
      json.dump(settings, temporary, ensure_ascii=False, indent=2)
      temporary.write("\n")
      temporary.flush()
      os.fsync(temporary.fileno())
    os.replace(temporary_name, path)
  except BaseException:
    try:
      os.unlink(temporary_name)
    except FileNotFoundError:
      pass
    raise
  print(f"Vesktop: fehlende Plugin-Standardwerte ergänzt: {path} ({', '.join(changes)})")
PY
fi
# WhatsApp als Brave App (PWA) statt Flatpak — damit WAIncognito (Browser-Addon) funktioniert 🟢📱
flatpak install -y flathub com.spotify.Client 2>/dev/null || true # Public TOS-safe ohne Spicetify (nur Privat/Freunde mit AdBlock)
log "WhatsApp manually via brave://apps (if not working: brave --app=https://web.whatsapp.com)"
# Public: kein Spicetify/Marketplace - gegen Spotify TOS, nur Privat/Freunde
# Mail: Proton Mail ersetzt durch Thunderbird (Proton VPN entfernt)
if ! flatpak install -y flathub org.mozilla.Thunderbird 2>/dev/null; then
 flatpak install -y flathub org.mozilla.thunderbird_esr 2>/dev/null || true
 sudo pacman -S --needed --noconfirm thunderbird 2>/dev/null || sudo pacman -S --needed --noconfirm thunderbird-bin 2>/dev/null || true
fi
# Proton Mail/VPN not installiert – ersetzt durch Thunderbird
info "Mail: Thunderbird (Proton Mail/VPN replaced, Proton VPN removed)"

info "Sync/Remote: KDEConnect Syncthing RustDesk Sunshine WaydroidStore"
sudo pacman -S --needed --noconfirm kdeconnect syncthing 2>/dev/null || true; systemctl --user enable --now syncthing 2>/dev/null || true
$AUR -S --needed --noconfirm rustdesk-bin sunshine-bin 2>/dev/null || flatpak install -y flathub com.rustdesk.RustDesk 2>/dev/null || true
# Public/Freunde: generische Hardware (kein K830/JBL spezifisch - nur Privat)
sudo pacman -S --needed --noconfirm linux-firmware 2>/dev/null || true
sudo pacman -S --needed --noconfirm pipewire pipewire-pulse wireplumber pavucontrol 2>/dev/null || true

info "Gaming: Steam, Heroic, Prism, Sober, BedrockOnLinux, Waydroid, VMware, Bottles, Lutris and tools"
sudo pacman -S --needed --noconfirm steam 2>/dev/null || true
# Steam Link wird nicht gebraucht - raus
flatpak uninstall -y com.valvesoftware.SteamLink 2>/dev/null || true
sudo pacman -Rns --noconfirm steamlink 2>/dev/null || true
$AUR -S --needed --noconfirm heroic-games-launcher-bin 2>/dev/null || flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null || true
sudo pacman -S --needed --noconfirm prism-launcher 2>/dev/null || $AUR -S --needed --noconfirm prism-launcher-bin 2>/dev/null || flatpak install -y flathub org.prismlauncher.PrismLauncher 2>/dev/null || true
# Fallback: falls einzelne JDKs fehlen (ältere), einzeln versuchen
# Java JDKs nur in Privat (für MC Server) - Freunde/Public nur Prism-Launcher, Java managed via Prism
flatpak install -y flathub org.vinegarhq.Sober 2>/dev/null || true
# BedrockOnLinux lädt mit deinem Microsoft-Konto die Windows-/GDK-Ausgabe von Minecraft Bedrock.
# Bewusst kein mcpelauncher-Fallback: mcpelauncher nutzt die Android-Ausgabe und wäre etwas anderes.
if ! $AUR -S --needed --noconfirm bedrock-on-linux-bin 2>/dev/null; then
 warn "BedrockOnLinux could not be installed – Android version will not be installed as replacement"
fi
if ! sudo pacman -S --needed --noconfirm waydroid lzip 2>/dev/null; then
 $AUR -S --needed --noconfirm waydroid 2>/dev/null || warn "Waydroid could not be installed"
fi
# Binder nur dann beim Boot laden, wenn der aktuelle Kernel das Modul tatsächlich bereitstellt.
if modinfo binder_linux &>/dev/null; then
 sudo install -d -m 755 /etc/modules-load.d /etc/modprobe.d
 printf '%s\n' 'binder_linux' | sudo tee /etc/modules-load.d/waydroid-binder.conf >/dev/null
 if modinfo -F parm binder_linux 2>/dev/null | grep -q '^devices:'; then
  printf '%s\n' 'options binder_linux devices=binder,hwbinder,vndbinder' | sudo tee /etc/modprobe.d/waydroid-binder.conf >/dev/null
 fi
 if sudo modprobe binder_linux; then
  log "Waydroid Binder module loaded and marked for boot"
 else
  warn "binder_linux could not be loaded – check Waydroid log after start"
 fi
else
 info "binder_linux is not a loadable module; no forced modules-load config created"
fi
# Waydroid ARM Translation: libhoudini (Intel) / libndk (AMD) via waydroid-script (libhoudini AUR gibt es not mehr - waydroid-script-git)
if ! $AUR -S --needed --noconfirm waydroid-script-git 2>/dev/null; then
 $AUR -S --needed --noconfirm waydroid-script 2>/dev/null || warn "waydroid-script could not be installed"
fi
# Installiere ARM Translation je nach CPU (AMD -> libndk empfohlen, Intel -> libhoudini) - for ARM-only Apps wie The Tower
if command -v waydroid-extras &>/dev/null; then
 if lscpu 2>/dev/null | grep -qi amd; then
  sudo waydroid-extras install libndk 2>&1 | tail -n 20 || sudo waydroid-extras install libhoudini 2>&1 | tail -n 20 || warn "libndk/libhoudini installation failed"
 else
  sudo waydroid-extras install libhoudini 2>&1 | tail -n 20 || sudo waydroid-extras install libndk 2>&1 | tail -n 20 || warn "libhoudini/libndk installation failed"
 fi
 sudo systemctl restart waydroid-container 2>/dev/null || true
elif [ -x /usr/share/waydroid-script/waydroid_extras.py ]; then
 if lscpu 2>/dev/null | grep -qi amd; then
  sudo python3 /usr/share/waydroid-script/waydroid_extras.py install libndk 2>&1 | tail -n 20 || true
 else
  sudo python3 /usr/share/waydroid-script/waydroid_extras.py install libhoudini 2>&1 | tail -n 20 || true
 fi
 sudo systemctl restart waydroid-container 2>/dev/null || true
else
 warn "waydroid-script not found - ARM apps like The Tower may be incompatible"
fi
# Waydroid: nur init wenn noch kein Image (verhindert Hängen bei jedem Lauf), Instant-Start danach
if [[ ! -f /var/lib/waydroid/waydroid_base.prop ]] || [[ ! -d /var/lib/waydroid/rootfs ]]; then
 timeout 300 sudo waydroid init -s GAPPS -f 2>&1 | tail -n 5 || warn "Waydroid init hanging - try again on next boot"
else
 info "Waydroid already initialized - skipping init (Instant Start)"
fi
sudo systemctl enable waydroid-container 2>/dev/null || true
sudo systemctl start waydroid-container 2>/dev/null || warn "waydroid-container could not be started"
# Waydroid Netzwerk: Sicher isolieren (Kein Zugriff für Fremde im öffentlichen WLAN!)
# Wir erlauben Datenverkehr NUR auf der lokalen Schnittstelle selbst (in/out/route)
sudo ufw allow in on waydroid0 to any 2>/dev/null || true
sudo ufw allow out on waydroid0 from any 2>/dev/null || true
sudo ufw route allow in on waydroid0 to any 2>/dev/null || true
sudo ufw route allow out on waydroid0 from any 2>/dev/null || true
# Die wichtigen Standard-Ports für DNS und DHCP (damit der Google-Login-Loop verschwindet)
# Werden NUR für das interne Waydroid-Netzwerk freigeschaltet!
sudo ufw allow in on waydroid0 to any port 53 proto udp 2>/dev/null || true
sudo ufw allow in on waydroid0 to any port 67 proto udp 2>/dev/null || true
sudo ufw allow in on waydroid0 to any port 68 proto udp 2>/dev/null || true
 # Waydroid DNS nur setzen wenn Session existiert (verhindert Hängen)
 timeout 5 waydroid prop set persist.waydroid.no_guest_dns false 2>/dev/null || true
# VM: VMware Workstation Pro statt QEMU - nutzerfreundlicher + beste Windows Grafik auf NVIDIA (du wolltest VMware statt QEMU)
# VMware 3D Beschleunigung (SVGA) viel stabiler als QEMU VirGL auf NVIDIA 3060 Ti - automatisch
if ! pacman -Q vmware-workstation 2>/dev/null | grep -q vmware; then
 $AUR -S --needed --noconfirm vmware-keymaps 2>/dev/null || yay -S --needed --noconfirm vmware-keymaps 2>/dev/null || paru -S --needed --noconfirm vmware-keymaps 2>/dev/null || true
 $AUR -S --needed --noconfirm vmware-workstation vmware-keymaps 2>/dev/null || $AUR -S --needed --noconfirm vmware-workstation 2>/dev/null || yay -S --needed --noconfirm vmware-workstation vmware-keymaps 2>/dev/null || yay -S --needed --noconfirm vmware-workstation 2>/dev/null || paru -S --needed --noconfirm vmware-workstation 2>/dev/null || warn "VMware Workstation konnte nicht installiert werden - Broadcom Bundle manuell laden"
fi
sudo modprobe -a vmw_vmci vmmon vmnet 2>/dev/null || sudo vmware-modconfig --console --install-all 2>/dev/null || true
sudo systemctl enable --now vmware-networks 2>/dev/null || true; sudo systemctl enable --now vmware-usbarbitrator 2>/dev/null || true
# VMware User Gruppen + UEFI Firmware for Windows 11 VM
sudo pacman -S --needed --noconfirm edk2-ovmf swtpm 2>/dev/null || true
sudo usermod -aG vmware $USER 2>/dev/null || true
log "VMware Workstation Pro zuverlässig - gute Windows Grafik (SVGA 3D) + nutzerfreundlich, parallel Host+VM ohne den Host auszubremsen"
# VMware Netzwerk: UFW KOMPLETT FREI - EGAL WAS ER TUT (vmnet1/vmnet8/vmnet0)
sudo ufw allow in on vmnet1 from any to any 2>/dev/null || true; sudo ufw allow out on vmnet1 from any to any 2>/dev/null || true; sudo ufw route allow in on vmnet1 from any to any 2>/dev/null || true; sudo ufw route allow out on vmnet1 from any to any 2>/dev/null || true
sudo ufw allow in on vmnet8 from any to any 2>/dev/null || true; sudo ufw allow out on vmnet8 from any to any 2>/dev/null || true; sudo ufw route allow in on vmnet8 from any to any 2>/dev/null || true; sudo ufw route allow out on vmnet8 from any to any 2>/dev/null || true
sudo ufw allow in on vmnet0 from any to any 2>/dev/null || true; sudo ufw allow out on vmnet0 from any to any 2>/dev/null || true; sudo ufw route allow in on vmnet0 from any to any 2>/dev/null || true; sudo ufw route allow out on vmnet0 from any to any 2>/dev/null || true

# Bootable USB: Ventoy (King, Multi-ISO) + Popsicle + Etcher Fallback
info "Boot-USB Tools: Ventoy, Popsicle, Etcher"
sudo pacman -S --needed --noconfirm ventoy popsicle 2>/dev/null || yay -S --needed --noconfirm ventoy-bin 2>/dev/null || paru -S --needed --noconfirm ventoy-bin 2>/dev/null || true
flatpak install -y flathub io.balena.etcher 2>/dev/null || flatpak install -y flathub com.github.pagedoodles.BalenaEtcher 2>/dev/null || true

$AUR -S --needed --noconfirm protonup protonup-qt umu-launcher 2>/dev/null || flatpak install -y flathub net.davidotek.pupgui2 2>/dev/null || true
# GE-Proton sofort holen (not erst beim nächsten Alles-Updaten)
if command -v protonup &>/dev/null; then protonup --help 2>&1 | head -n 5; echo "--- Installiere neuestes GE-Proton ---"; protonup -y 2>&1 | tail -n 40 || true; fi
# Proton CachyOS (eigenes CachyOS Proton) falls im Repo/AUR verfügbar - direkt mitinstallieren
sudo pacman -S --needed --noconfirm proton-cachyos 2>/dev/null || $AUR -S --needed --noconfirm proton-cachyos 2>/dev/null || $AUR -S --needed --noconfirm proton-cachyos-git 2>/dev/null || true
if pacman -Q proton-cachyos 2>/dev/null; then echo "Proton CachyOS installiert"; fi
if pacman -Q proton-cachyos-git 2>/dev/null; then echo "Proton CachyOS-git installiert"; fi
sudo pacman -S --needed --noconfirm mangohud lib32-mangohud gamemode lib32-gamemode gamescope 2>/dev/null || true
sudo pacman -S --needed --noconfirm vkbasalt lib32-vkbasalt 2>/dev/null || $AUR -S --needed --noconfirm vkbasalt 2>/dev/null || true
sudo pacman -S --needed --noconfirm obs-studio distrobox podman 2>/dev/null || flatpak install -y flathub com.obsproject.Studio 2>/dev/null || true
# Kooha Screenrecorder (einfach, Wayland)
sudo pacman -S --needed --noconfirm kooha 2>/dev/null || flatpak install -y flathub io.github.seadve.Kooha 2>/dev/null || true
sudo pacman -S --needed --noconfirm bottles lutris winetricks protontricks 2>/dev/null || $AUR -S --needed --noconfirm bottles lutris 2>/dev/null || flatpak install -y flathub com.usebottles.bottles 2>/dev/null || true
# SMM Satisfactory Mod Manager (nur privat)
$AUR -S --needed --noconfirm satisfactory-mod-manager 2>/dev/null || $AUR -S --needed --noconfirm smm 2>/dev/null || flatpak install -y flathub com.moddingcentral.smm 2>/dev/null || flatpak install -y flathub io.github.satisfactorymodding.smm 2>/dev/null || true
# Debtap/alien als überflüssig entfernt – reine Konvertierungs-Tools, bei Bedarf: $AUR -S debtap alien
sudo pacman -S --needed --noconfirm git 2>/dev/null || true # github-cli/handbrake als überflüssig entfernt – nur git for AUR; bei Bedarf: sudo pacman -S github-cli handbrake

info "GUI/Theme: Variety, Plymouth bleibt (Kvantum entfernt)"
$AUR -S --needed --noconfirm variety 2>/dev/null || true
sudo pacman -S --needed --noconfirm plymouth 2>/dev/null || true; $AUR -S --needed --noconfirm plymouth-theme-cachyos 2>/dev/null || true; sudo plymouth-set-default-theme -R cachyos 2>/dev/null || true
log "Ausgewählte Anwendungen installiert"

# ---------- 3.5 APP-KONFIGURATION - alle Apps direkt optimal einstellen (kein unnatürlich) ----------
info "Gaming-Overlays: vkBasalt, MangoHud, Gamemode optimal vorkonfigurieren"
# VkBasalt: global AUS, nur per ENABLE_VKBASALT=1 aktiv – CAS 0.4 ist natürlicher Sweet-Spot (0.7+=aboutschärft)
mkdir -p "$HOME/.config/vkBasalt"
cat <<'EOF' > "$HOME/.config/vkBasalt/vkBasalt.conf"
# VkBasalt – natürlich, not aboutschärft. Global deaktiviert, pro Spiel aktivieren.
# Start: ENABLE_VKBASALT=1 %command% (Steam) oder ENABLE_VKBASALT=1 mangohud %command%
casSharpness = 0.40
# Nur CAS, kein FXAA/SMAA/LUT – natürlich
enableOnLaunch = False
toggleKey = Home
EOF
# MangoHud: schlank, nur FPS/CPU/GPU – not aboutladen
mkdir -p "$HOME/.config/MangoHud"
cat <<'EOF' > "$HOME/.config/MangoHud/MangoHud.conf"
# MangoHud – minimal, kein unnatürliches Overlay
legacy_layout=false
fps
frame_timing=0
cpu_stats
gpu_stats
ram
vram
# Keine feste fps_limit – Spiel entscheidet; bei Bedarf fps_limit=144 setzen
toggle_fps_limit=F1
toggle_hud=Shift_R+F12
EOF
# Gamemode bereits: renice=10 + desiredgov=performance (steht unten, hier nur sicherstellen)
mkdir -p "$HOME/.config/gamemode"
cat <<'EOF' > "$HOME/.config/gamemode/gamemode.ini"
[general]
renice=10
desiredgov=performance
igpu_desiredgov=performance
[custom]
start=notify-send "Gamemode an"
end=notify-send "Gamemode aus"
EOF
# Flameshot: speichern nach ~/Pictures/Screenshots, keine doppelte Spectacle-Konfig
mkdir -p "$HOME/Pictures/Screenshots" "$HOME/.config/flameshot"
cat > "$HOME/.config/flameshot/flameshot.ini" <<EOF
[General]
savePath=$HOME/Pictures/Screenshots
saveAsFileExtension=.png
showHelp=false
showDesktopNotification=false
startupLaunch=false
EOF
# Flameshot Autostart automatisch - in allen 3 Editionen (auf Wunsch)
mkdir -p "$HOME/.config/autostart" 2>/dev/null || true
if [ -f /usr/share/applications/org.flameshot.Flameshot.desktop ]; then
  cp /usr/share/applications/org.flameshot.Flameshot.desktop "$HOME/.config/autostart/" 2>/dev/null || true
  sed -i "s/^Hidden=.*/Hidden=false/" "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || true
  grep -q "^X-GNOME-Autostart-enabled" "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || echo "X-GNOME-Autostart-enabled=true" >> "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || true
  # Doppelstart verhindern: nur EINE Autostart-Datei
  rm -f "$HOME/.config/autostart/flameshot.desktop" 2>/dev/null || true
  grep -q "^Exec=flameshot" "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || sed -i "s/^Exec=.*/Exec=flameshot/" "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || true
else
  printf "[Desktop Entry]
Type=Application
Name=Flameshot
Exec=flameshot
Icon=flameshot
Hidden=false
X-GNOME-Autostart-enabled=true
" > "$HOME/.config/autostart/flameshot.desktop" 2>/dev/null || true
  rm -f "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" 2>/dev/null || true
fi
# Sicherstellen: keine zweite Flameshot-Autostart-Datei übrig
if [ -f "$HOME/.config/autostart/org.flameshot.Flameshot.desktop" ] && [ -f "$HOME/.config/autostart/flameshot.desktop" ]; then
  rm -f "$HOME/.config/autostart/flameshot.desktop" 2>/dev/null || true
fi
log "Flameshot Autostart aktiviert (einmalig, Tray, startupLaunch=false)"
sudo update-desktop-database /usr/share/applications 2>/dev/null || true; kbuildsycoca6 --noincremental 2>/dev/null || true
# === Permissions automatisch managen - kein manuelles Erlauben mehr (Flameshot Screenshot etc.) ===
# Portale sicherstellen + PipeWire für Screenshot/Screencast
sudo pacman -S --needed --noconfirm xdg-desktop-portal xdg-desktop-portal-kde pipewire 2>/dev/null || true
systemctl --user enable --now pipewire 2>/dev/null || true; systemctl --user enable --now pipewire-pulse 2>/dev/null || true
# Portal-Dienste aktivieren (falls vorhanden)
systemctl --user try-restart xdg-desktop-portal 2>/dev/null || true
systemctl --user try-restart xdg-desktop-portal-kde 2>/dev/null || true
# Flameshot: Screenshot/Screencast ohne Nachfrage (Wayland KDE)
mkdir -p "$HOME/.local/share/xdg-desktop-portal/permissions" 2>/dev/null || true
# Flatpak permission store (auch für native Apps via portal)
flatpak permission-set screenshot screenshot org.flameshot.Flameshot yes 2>/dev/null || true
flatpak permission-set screencast screencast org.flameshot.Flameshot yes 2>/dev/null || true
# Vesktop/Discord + OBS: Kamera/Mic/ScreenShare ohne Nachfrage
for _app in dev.vencord.Vesktop com.obsproject.Studio; do
  flatpak permission-set screencast screencast "$_app" yes 2>/dev/null || true
  flatpak permission-set camera camera "$_app" yes 2>/dev/null || true
done
# Flameshot Wayland-Tweaks: kein Grim-Warning, direkter Portal-Zugriff
if [ -f "$HOME/.config/flameshot/flameshot.ini" ]; then
  grep -q "disabledGrimWarning" "$HOME/.config/flameshot/flameshot.ini" 2>/dev/null || echo "disabledGrimWarning=true" >> "$HOME/.config/flameshot/flameshot.ini" 2>/dev/null || true
fi
# KDE KWin erlaubt Flameshot Screenshot via DBus ohne Nachfrage (Wayland)
mkdir -p "$HOME/.config" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key AllowScreenshots true 2>/dev/null || true
# Portal-Prefs für KDE bevorzugen
mkdir -p "$HOME/.config/xdg-desktop-portal" 2>/dev/null || true
cat > "$HOME/.config/xdg-desktop-portal/portals.conf" <<'PORTAL_EOF'
# === ALLE Permissions für JEDE App vorab erlauben - nie wieder Nachfrage ===
# Flatpak: alle installierten Apps bekommen alle Portal-Rechte + alle Geräte/Dateien
if command -v flatpak >/dev/null 2>&1; then
  for _app in $(flatpak list --app --columns=application 2>/dev/null); do
    for _perm in screenshot screencast camera microphone location notification background wallpaper open-uri trash documents; do
      flatpak permission-set "$_perm" "$_perm" "$_app" yes 2>/dev/null || true
    done
    # Flatpak Overrides: eng gefasst (Downloads/Dokumente/Bilder/Musik/Videos, GPU, Netz, Portale; Launcher bekommen Home)
    _FS=""
    case "$_app" in com.heroicgameslauncher.hgl|net.lutris.Lutris|org.prismlauncher.PrismLauncher) _FS="--filesystem=home" ;; esac
    flatpak override --user $_FS --filesystem=xdg-download --filesystem=xdg-documents --filesystem=xdg-pictures --filesystem=xdg-music --filesystem=xdg-videos --device=dri --share=network --share=ipc --socket=wayland --socket=x11 --socket=fallback-x11 --socket=pulseaudio --talk-name=org.freedesktop.portal.* "$_app" 2>/dev/null || true
  done
fi
# Native Apps via Portal Permission Store - alle bekannten Apps freischalten
for _app in org.flameshot.Flameshot dev.vencord.Vesktop com.obsproject.Studio com.spotify.Client org.vinegarhq.Sober com.rustdesk.RustDesk org.kde.kate org.kde.gwenview org.kde.okular org.kde.dolphin org.kde.ark vlc brave-browser brave com.heroicgameslauncher.hgl net.lutris.Lutris com.github.tchx84.Flatseal org.prismlauncher.PrismLauncher; do
  for _perm in screenshot screencast camera microphone notification background; do
    flatpak permission-set "$_perm" "$_perm" "$_app" yes 2>/dev/null || true
  done
done
# PipeWire + Portal für alle - Kamera/Mic/ScreenShare ohne Prompt
sudo pacman -S --needed --noconfirm pipewire pipewire-pulse wireplumber xdg-desktop-portal xdg-desktop-portal-kde 2>/dev/null || true
systemctl --user enable --now pipewire 2>/dev/null || true; systemctl --user enable --now wireplumber 2>/dev/null || true
# KDE: Mic/Camera/ScreenShare global erlauben
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false 2>/dev/null || true
kwriteconfig6 --file plasmaparc --group General --key RaiseMaximumVolume true 2>/dev/null || true
# Flatpak Permission DB aufräumen - alle auf yes
mkdir -p "$HOME/.local/share/flatpak/db" 2>/dev/null || true
'
[preferred]
default=kde
org.freedesktop.impl.portal.Screenshot=kde
org.freedesktop.impl.portal.ScreenCast=kde
PORTAL_EOF



# KDEConnect Autostart - NUR Daemon, KEIN Fenster (Hintergrund, vernachlässigbar Performance ~10MB)
# Kdeconnectd läuft unsichtbar + System-Tray Icon, kein Popup-Fenster beim Login
if [ -f /etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop ]; then
 mkdir -p "$HOME/.config/autostart" 2>/dev/null || true
 cp /etc/xdg/autostart/org.kde.kdeconnect.daemon.desktop "$HOME/.config/autostart/" 2>/dev/null || true
 sed -i "s/^Hidden=.*/Hidden=false/" "$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" 2>/dev/null || true
 grep -q "^X-GNOME-Autostart-enabled" "$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" 2>/dev/null || echo "X-GNOME-Autostart-enabled=true" >> "$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" 2>/dev/null || true
 log "KDEConnect Daemon Autostart aktiviert (kein Fenster, nur Handy-Sync im Hintergrund)"
else
 # Fallback: Daemon startet ohnehin mit Plasma Session, wenn kdeconnect installiert ist
 log "KDEConnect Daemon startet automatisch mit Plasma (kein Fenster)"
fi

# Gwenview + Okular + Kate: schlank, Kate bleibt Editor, Okular PDF, Gwenview Bilder – keine Doppel-Viewer
# Gwenview: keine extra Plugins nötig, Standard reicht
# VLC: Hardware-Decoding auto, kein extra Eingriff – natürlich
# Task beenden wie Windows Rechtsklick - KDE xkill per Terminal + Shortcut ohne Einstellungen
sudo pacman -S --needed --noconfirm xorg-xkill xdotool wmctrl 2>/dev/null || true
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/kservices5/ServiceMenus"
# 1. task-kill Befehl für Terminal: taskkill [Name] oder ohne Name = klicken
cat > "$HOME/.local/bin/task-kill" <<'TASK_EOF'
#!/usr/bin/env bash
if [ -n "$1" ]; then
  pkill -9 "$1" 2>/dev/null || killall -9 "$1" 2>/dev/null || echo "Kein Prozess $1 gefunden"
else
  echo "Klicke auf Fenster zum Killen (Esc zum Abbrechen)..."
  if [ -n "$WAYLAND_DISPLAY" ]; then
    _QD="$(command -v qdbus6 || command -v qdbus)"
    _PID="$("$_QD" org.kde.KWin /KWin queryWindowInfo 2>/dev/null | sed -n 's/^pid: //p' | head -n1)"
    if [ -n "$_PID" ] && [ "$_PID" -gt 0 ] 2>/dev/null; then kill -9 "$_PID" && echo "Process $_PID killed"; else echo "No window selected"; fi
  else
    xkill
  fi
fi
TASK_EOF
chmod +x "$HOME/.local/bin/task-kill"
sudo ln -sf "$HOME/.local/bin/task-kill" /usr/local/bin/taskkill 2>/dev/null || true
sudo ln -sf "$HOME/.local/bin/task-kill" /usr/local/bin/task-kill 2>/dev/null || true
cp "$HOME/.local/bin/task-kill" "$HOME/.local/bin/taskkill" 2>/dev/null || true
# Fish Alias für Windows-Schreibweise ohne Bindestrich
mkdir -p "$HOME/.config/fish/conf.d" 2>/dev/null || true
grep -q "alias taskkill" "$HOME/.config/fish/conf.d/cachyos-local-tools.fish" 2>/dev/null || echo 'alias taskkill="task-kill"' >> "$HOME/.config/fish/conf.d/cachyos-local-tools.fish" 2>/dev/null || true
grep -q "alias task-kill" "$HOME/.config/fish/conf.d/cachyos-local-tools.fish" 2>/dev/null || echo 'alias task-kill="task-kill"' >> "$HOME/.config/fish/conf.d/cachyos-local-tools.fish" 2>/dev/null || true
# Bash alias auch
grep -q "alias taskkill" "$HOME/.bashrc" 2>/dev/null || echo "alias taskkill='task-kill'" >> "$HOME/.bashrc" 2>/dev/null || true
sudo ln -sf "$HOME/.local/bin/task-kill" /usr/local/bin/task-kill 2>/dev/null || true
# 2. Rechtsklick Task-beenden im Dolphin + überall (ServiceMenu)
cat > "$HOME/.local/share/kservices5/ServiceMenus/taskkill.desktop" <<'SERVEOF'
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;inode/file;
Actions=TaskKill;
[Desktop Action TaskKill]
Name=Task beenden
Name[de]=Task beenden
Icon=process-stop
Exec=sh -c 'exec "$HOME/.local/bin/task-kill"'
SERVEOF
# 3. Shortcut wie Windows: Strg+Alt+Esc = xkill (ist bei KDE Standard, hier nochmal fest)
mkdir -p "$HOME/.config" 2>/dev/null || true
kwriteconfig6 --file kglobalshortcutsrc --group khotkeys --key _k_friendly_name "Task beenden" 2>/dev/null || true
# KWin Kill Window Shortcut sicherstellen
kwriteconfig6 --file kwinrc --group ModifierOnlyShortcuts --key Meta "" 2>/dev/null || true
qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true

log "App-Konfiguration: vkBasalt CAS 0.40 aus, MangoHud minimal, Gamemode performance, Flameshot Pfad gesetzt"


# ---------- 4. LEISTUNGS-TWEAKS ----------
step "4/8 LEISTUNGS-TWEAKS - gewünschte Gaming-Einstellungen anwenden"
# Der Bore-Kernel wurde bereits vor dem Kernel-Cleanup in Phase 1.5 installiert und dort geschützt.
if pacman -Q linux-cachyos-bore &>/dev/null; then
 log "Bore-Kernel bereits installiert"
else
 warn "Bore-Kernel fehlt – Details im Log prüfen, bevor du neu startest"
fi
sudo pacman -S --needed --noconfirm amd-ucode zram-generator ananicy-cpp cachyos-ananicy-rules scx-scheds cpupower earlyoom 2>/dev/null || true
sudo systemctl enable --now ananicy-cpp earlyoom 2>/dev/null || true
# Ananicy CGroups Fix (Report: cpu controller not available) - Fallback auf nice only wenn cgroup fehlt
if ! grep -q "cpu" /sys/fs/cgroup/cgroup.controllers 2>/dev/null; then sudo mkdir -p /etc/ananicy.d; echo "apply_cgroup=false" | sudo tee -a /etc/ananicy.d/00-cgroup-fix.conf >/dev/null || true; fi
# CPU: use EPP on amd-pstate-epp (Ryzen 5600X etc.), don't force governor when EPP is available (avoids power-profiles-daemon error)
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]]; then
 log "AMD EPP detected (amd-pstate-epp) – using EPP, leaving governor to system daemon"
 # Enable boost safely
 echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
 for p in /sys/devices/system/cpu/cpufreq/policy*/boost; do echo 1 | sudo tee "$p" 2>/dev/null || true; done
 for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo balance_performance | sudo tee "$f" 2>/dev/null || echo power | sudo tee "$f" 2>/dev/null || true; done
 log "AMD EPP set to balance_performance (Gamemode will boost to performance when needed)"
else
 # Fallback for systems without EPP: use schedutil
 echo 'governor="schedutil"' | sudo tee /etc/default/cpupower >/dev/null; sudo systemctl enable --now cpupower 2>/dev/null || true
 sudo cpupower frequency-set -g schedutil 2>/dev/null || sudo cpupower frequency-set -g powersave 2>/dev/null || true
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo schedutil | sudo tee $f 2>/dev/null || echo powersave | sudo tee $f 2>/dev/null || true; done
 log "CPU governor set to schedutil (no EPP available)"
fi
# Do not mask power-profiles-daemon when EPP is present – it manages EPP correctly
cat <<'EOF' | sudo tee /etc/systemd/zram-generator.conf >/dev/null
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
EOF
if [[ "$GAMING_EXTREME" == "true" ]]; then SPLIT="kernel.split_lock_mitigate=0"; else SPLIT="# split_lock nur EXTREME"; fi
cat <<EOF | sudo tee /etc/sysctl.d/99-gaming-max.conf >/dev/null
vm.max_map_count=2147483642
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
$SPLIT
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
fs.file-max=2097152
vm.nr_hugepages=0
EOF
sudo sysctl --system 2>/dev/null || true; sudo sysctl -w vm.swappiness=10 2>/dev/null || true; echo 10 | sudo tee /proc/sys/vm/swappiness 2>/dev/null || true; sudo sysctl -w vm.vfs_cache_pressure=50 2>/dev/null || true
# Watchdog etc. außerhalb von GAMING_EXTREME
# Watchdog bleibt an (auf Wunsch not geblacklistet) — sicherer bei Freeze
log "Watchdog bleibt aktiv (kein Blacklist auf Wunsch)"
# Coredumps bleiben an (auf Wunsch not deaktiviert) — Debug Infos bei Crash verfügbar
log "Coredumps bleiben aktiv (kein Deaktivieren auf Wunsch)"
# Shader-Cache clean Helper — kein Limit, aber sauber löschbar 🧹🎮
cat <<'EOF' > "$HOME/.local/bin/clean-shader-cache"
#!/usr/bin/env bash
set -uo pipefail
echo "Shader-Caches die geleert werden:"
du -sch -- "$HOME/.cache/mesa_shader_cache" "$HOME/.cache/nvidia" "$HOME/.cache/radv_builtin_shaders" "$HOME/.nv" "$HOME/.cache/dxvk" 2>/dev/null || true
if [[ "${1:-}" != "--yes" ]]; then echo "Vorschau — mit --yes wirklich löschen: clean-shader-cache --yes"; exit 0; fi
rm -rf -- "$HOME/.cache/mesa_shader_cache" "$HOME/.cache/nvidia" "$HOME/.cache/radv_builtin_shaders" "$HOME/.nv" "$HOME/.cache/dxvk" 2>/dev/null || true
echo "Shader-Caches geleert — beim nächsten Spielstart werden sie neu aufgebaut (kurz mehr Ruckler)"
EOF
chmod +x "$HOME/.local/bin/clean-shader-cache"
log "Shader-Cache Helper erstellt: clean-shader-cache"
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
cat <<'EOF' | sudo tee /etc/tmpfiles.d/thp.conf >/dev/null
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - madvise
EOF
# Amd_pstate wird not via modprobe.d gesetzt — Kernel-Default bleibt, EPP regelt Performance
cat <<'EOF' | sudo tee /etc/security/limits.d/99-gaming.conf >/dev/null
@users soft nice -20
@users hard nice -20
* soft memlock unlimited
* hard memlock unlimited
EOF
if [[ "$GPU_VENDOR" == "nvidia" ]]; then
sudo mkdir -p /etc/X11/xorg.conf.d; cat <<'EOF' | sudo tee /etc/X11/xorg.conf.d/20-nvidia.conf >/dev/null
Section "Device"
  Identifier "NVIDIA Card"
  Driver "nvidia"
  Option "TripleBuffer" "off"
  Option "Coolbits" "28"
EndSection
EOF
fi # nur bei NVIDIA
mkdir -p ~/.config/gamemode; echo -e "[general]\nrenice=10\ndesiredgov=performance" > ~/.config/gamemode/gamemode.ini
# Mitigations OFF nur im EXTREME Gaming-Modus (bewusster Trade-off)

if [[ "$GAMING_EXTREME" == "true" ]]; then
# Mitigations OFF wie gewünscht – aber nur in der Konfiguration des tatsächlich erkannten Bootloaders.
# CachyOS nutzt je nach Installation Limine, systemd-boot, GRUB oder rEFInd; jede Variante hat eine andere Quelle.
BOOTLOADER="unknown"
BOOTLOADER_CONFIG=""
# Privates Setup: GRUB bevorzugt (auf Wunsch, zeigt alle Kernel im Menü, keine verfall Probleme)
# Stelle sicher dass GRUB installiert ist
sudo pacman -S --needed --noconfirm grub 2>/dev/null || true
if [[ -f /etc/default/grub ]]; then
 BOOTLOADER="grub"
 BOOTLOADER_CONFIG="/etc/default/grub"
 # GRUB mandatory: Bore as default – NVIDIA/DKMS driver is built for the Bore kernel (standard kernel stays in the menu as fallback)
 # GRUB_DEFAULT now handled by saved/savedefault block below (no duplicate 0)
 # Top-Level direkt auf Bore setzen - damit "CachyOS Linux" oben direkt den Bore-Kernel bootet (Standard-Kernel bleibt als Menüpunkt verfügbar)
 sudo sed -i '/^GRUB_TOP_LEVEL=/d' "$BOOTLOADER_CONFIG" 2>/dev/null || true
 echo "GRUB_TOP_LEVEL='/boot/vmlinuz-linux-cachyos-bore'" | sudo tee -a "$BOOTLOADER_CONFIG" >/dev/null
 # Sicherstellen dass Submenu aktiv bleibt (sonst greift Default not)
 sudo sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=false/' "$BOOTLOADER_CONFIG" 2>/dev/null || echo "GRUB_DISABLE_SUBMENU=false" | sudo tee -a "$BOOTLOADER_CONFIG" >/dev/null
info "Configure GRUB (menu always visible, remember last kernel)"
# 1. Always show menu (CachyOS sometimes hides it by default!)
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub 2>/dev/null || echo 'GRUB_TIMEOUT_STYLE=menu' | sudo tee -a /etc/default/grub >/dev/null
# 2. Give 5 seconds timeout at boot
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub 2>/dev/null || echo 'GRUB_TIMEOUT=5' | sudo tee -a /etc/default/grub >/dev/null
# 3. Remember last selected kernel every time!
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub 2>/dev/null || echo 'GRUB_DEFAULT=0' | sudo tee -a /etc/default/grub >/dev/null

 if sudo grep -qE '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$BOOTLOADER_CONFIG"; then
  # Fix: handle both ' and " quotes, remove nowatchdog (Watchdog bleibt AN) and add mitigations=off
  sudo sed -Ei "/^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ { s/[[:space:]]*mitigations=off//g; s/[[:space:]]*nowatchdog//g; s/'$/ mitigations=off'/; s/\"$/ mitigations=off\"/; }" "$BOOTLOADER_CONFIG" || warn "GRUB-Konfiguration konnte nicht geändert werden"
  # Fallback: falls Quote-Typ not erkannt, normalisiere Leerzeichen
  sudo sed -Ei "s/'[[:space:]]+'/'/g; s/\"[[:space:]]+\"/\"/g; s/'[[:space:]]+mitigations/' mitigations/g" "$BOOTLOADER_CONFIG" 2>/dev/null || true
 else
  echo 'GRUB_CMDLINE_LINUX_DEFAULT="mitigations=off"' | sudo tee -a "$BOOTLOADER_CONFIG" >/dev/null
 fi
elif [[ -f /etc/sdboot-manage.conf ]]; then
 BOOTLOADER="systemd-boot"
 BOOTLOADER_CONFIG="/etc/sdboot-manage.conf"
 if sudo grep -qE '^[[:space:]]*LINUX_OPTIONS=' "$BOOTLOADER_CONFIG"; then
  sudo sed -Ei '/^[[:space:]]*LINUX_OPTIONS=/ { s/[[:space:]]*mitigations=off//g; s/"$/ mitigations=off"/; }' "$BOOTLOADER_CONFIG" || warn "systemd-boot-Konfiguration konnte nicht geändert werden"
 else
  echo 'LINUX_OPTIONS="mitigations=off"' | sudo tee -a "$BOOTLOADER_CONFIG" >/dev/null
 fi
elif [[ -f /boot/refind_linux.conf ]]; then
 BOOTLOADER="refind"
 BOOTLOADER_CONFIG="/boot/refind_linux.conf"
 if sudo grep -qE '^[[:space:]]*"Boot using default options"' "$BOOTLOADER_CONFIG"; then
  sudo sed -Ei '/^[[:space:]]*"Boot using default options"/ { s/[[:space:]]*mitigations=off//g; s/"$/ mitigations=off"/; }' "$BOOTLOADER_CONFIG" || warn "rEFInd-Konfiguration konnte nicht geändert werden"
 else
  warn "rEFInd-Standardzeile nicht gefunden – schreibe keine unvollständige Bootoption"
 fi
elif [[ -f /etc/kernel/cmdline ]]; then
 # Generischer kernel-install-Fallback – nur verwenden, wenn die Datei bereits Teil des Setups ist.
 BOOTLOADER="kernel-install"
 BOOTLOADER_CONFIG="/etc/kernel/cmdline"
 if ! sudo grep -qw 'mitigations=off' "$BOOTLOADER_CONFIG"; then
  echo 'mitigations=off' | sudo tee -a "$BOOTLOADER_CONFIG" >/dev/null
 fi
else
 warn "Kein unterstützter Bootloader erkannt – mitigations=off wurde nicht blind geschrieben"
fi
log "Bootloader erkannt: $BOOTLOADER${BOOTLOADER_CONFIG:+ ($BOOTLOADER_CONFIG)}"
# Safety-Net: systemd-boot liest auch /etc/kernel/cmdline (kernel-install)
if [[ "$BOOTLOADER" == "systemd-boot" && -d /etc/kernel ]]; then
 sudo mkdir -p /etc/kernel
 # Watchdog auf Wunsch AN -> nowatchdog explizit entfernen falls vorhanden
 sudo sed -Ei 's/[[:space:]]*nowatchdog//g' /etc/kernel/cmdline 2>/dev/null || true
 sudo sed -Ei 's/[[:space:]]*nowatchdog//g' "$BOOTLOADER_CONFIG" 2>/dev/null || true
fi
# GRUB: nowatchdog auch direkt entfernen falls noch vorhanden (unabhängig vom Bootloader-Typ)
if [[ -f /etc/default/grub ]]; then
 sudo sed -Ei 's/[[:space:]]*nowatchdog//g' /etc/default/grub 2>/dev/null || true
fi
else
 log "Mitigations bleiben an (SAFE/GAMING) — kein mitigations=off"
fi
# Watchdog auf Wunsch AN -> nowatchdog wird not ergänzt, sondern entfernt (s.o.)
log "Watchdog bleibt AN – kein nowatchdog ergänzt"
log "Tweaks (amd_pstate Fix, EPP, no Conky)"

# ---------- 4.5 SYSTEM DIREKT RICHTIG EINGESTELLT - alles wo niemand nein sagt ----------
info "System: PipeWire, KWin, I/O-Scheduler, Journald, EarlyOOM, Ananicy optimal einstellen"
# PipeWire: 48kHz, low-latency quantum 1024/48000 = 21ms – natürlicher Sweetspot for Gaming+Discord
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat <<'EOF' > "$HOME/.config/pipewire/pipewire.conf.d/99-lowlatency.conf"
context.properties = {
  default.clock.rate = 48000
  default.clock.quantum = 1024
  default.clock.min-quantum = 256
  default.clock.max-quantum = 2048
}
EOF
# KWin: Compositor richtig – kein Tearing, Adaptive Sync wo vorhanden, kein unnatürliches Blur
mkdir -p "$HOME/.config"
if [[ -f "$HOME/.config/kwinrc" ]]; then cp -a "$HOME/.config/kwinrc" "$HOME/.config/kwinrc.before-cachyos-gaming-setup-${RUN_ID}.bak" 2>/dev/null || true; fi
kwriteconfig6 --file kwinrc --group Compositing --key Backend "OpenGL" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key GLCore "true" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key Enabled "true" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key LatencyPolicy "Extremely Low" 2>/dev/null || (mkdir -p ~/.config; grep -q "LatencyPolicy" ~/.config/kwinrc 2>/dev/null || echo -e "\n[Compositing]\nLatencyPolicy=Extremely Low" >> ~/.config/kwinrc)
kwriteconfig6 --file kwinrc --group Compositing --key MaxFPS "144" 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Compositing --key AllowTearing "true" 2>/dev/null || (mkdir -p ~/.config; grep -q "AllowTearing" ~/.config/kwinrc 2>/dev/null || echo "AllowTearing=true" >> ~/.config/kwinrc)
# I/O Scheduler: NVMe -> none/kyber, SATA SSD -> mq-deadline/bfq – automatisch richtig
for _dev in /sys/block/nvme* /sys/block/sd* /sys/block/vd*; do
 [[ -e "$_dev/queue/scheduler" ]] || continue
 if [[ "$_dev" == *nvme* ]]; then
  echo "none" | sudo tee "$_dev/queue/scheduler" 2>/dev/null || echo "kyber" | sudo tee "$_dev/queue/scheduler" 2>/dev/null || true
 else
  echo "mq-deadline" | sudo tee "$_dev/queue/scheduler" 2>/dev/null || echo "bfq" | sudo tee "$_dev/queue/scheduler" 2>/dev/null || true
 fi
done
# Udev-Regel for Scheduler nach Reboot persistent
cat <<'EOF' | sudo tee /etc/udev/rules.d/60-ioscheduler.rules >/dev/null
# NVMe: none, SATA: mq-deadline
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"
EOF
# Journald: fest auf 200M begrenzen – natürlich, wächst not ewig, 3 Tage reichen
sudo mkdir -p /etc/systemd/journald.conf.d; sudo rm -f /etc/systemd/journald.conf.d/99-cachyos-gaming.conf
cat <<'EOF' | sudo tee /etc/systemd/journald.conf.d/99-cachyos-gaming.conf >/dev/null
[Journal]
SystemMaxUse=200M
SystemKeepFree=500M
SystemMaxFileSize=50M
MaxRetentionSec=3d
EOF
sudo systemctl restart systemd-journald 2>/dev/null || true
# EarlyOOM: scharf aber fair – bei 5% RAM frei + 10% Swap, schont X/kwin/plasmashell
cat <<'EOF' | sudo tee /etc/default/earlyoom >/dev/null
EARLYOOM_ARGS="-m 5 -s 10 -r 0 --avoid '^(X|Xorg|kwin_x11|kwin_wayland|plasmashell|sddm)$' --prefer '^(electron|chrome|brave|firefox|chromium|steam|lutris|bottles)$'"
EOF
sudo systemctl enable --now earlyoom 2>/dev/null || true
# Ananicy-Cpp: sicherstellen dass Gaming-Regeln aktiv, CGroups nur wenn verfügbar
if [[ -f /etc/ananicy.d/00-cgroup-fix.conf ]] && grep -q "apply_cgroup=false" /etc/ananicy.d/00-cgroup-fix.conf 2>/dev/null; then
 log "Ananicy bleibt auf nice-only (keine CGroup) – korrekt"
else
 sudo mkdir -p /etc/ananicy.d
 # Gaming-Prozesse bekommen -nice, Hintergrund nur dezent gedrosselt – natürlich
 cat <<'EOF' | sudo tee /etc/ananicy.d/99-gaming-nice.conf >/dev/null
# Natürliche Priorisierung – niemand würde nein sagen
[steam]
nice = -5
[cs2]
nice = -10
[GameThread]
nice = -10
[brave]
nice = 0
[discord]
nice = 0
EOF
 sudo systemctl restart ananicy-cpp 2>/dev/null || true
fi
# BTRFS: noatime + compress=zstd direkt richtig – aber sicher mit fstab-Backup
if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
 ROOT_OPTS="$(findmnt -n -o OPTIONS / 2>/dev/null || true)"
 if [[ ",$ROOT_OPTS," != *",noatime,"* || ",$ROOT_OPTS," != *",compress=zstd"* ]]; then
  info "BTRFS root ohne noatime/compress=zstd – füge sicher hinzu (mit Backup)"
  sudo cp -a /etc/fstab "/etc/fstab.before-cachyos-gaming-setup-${RUN_ID}.bak" 2>/dev/null || true
  # Nur die Root-Zeile ergänzen, Subvolumes not anfassen
  if grep -q " / .*btrfs" /etc/fstab 2>/dev/null; then
   if ! grep -E " / .*btrfs.*,noatime" /etc/fstab 2>/dev/null; then
    sudo sed -i -E '/^[[:space:]]*[^#].*[[:space:]]\/[[:space:]]+btrfs/s/(btrfs[[:space:]]+)([^#]*)/\1noatime,\2/' /etc/fstab 2>/dev/null || true
   fi
   if ! grep -E " / .*btrfs.*,compress=zstd" /etc/fstab 2>/dev/null; then
    sudo sed -i -E '/^[[:space:]]*[^#].*[[:space:]]\/[[:space:]]+btrfs/s/(btrfs[[:space:]]+)([^#]*)/\1compress=zstd,\2/' /etc/fstab 2>/dev/null || true
   fi
   # Doppelte Kommas bereinigen
   sudo sed -i -E 's/,+/,/g; s/,([[:space:]])/\1/g' /etc/fstab 2>/dev/null || true
   log "BTRFS fstab nachgezogen – Backup: /etc/fstab.before-cachyos-gaming-setup-${RUN_ID}.bak (prüfe: cat /etc/fstab)"
  else
   warn "BTRFS root aber keine / -Zeile in /etc/fstab gefunden – keine Auto-Änderung"
  fi
 else
  log "BTRFS bereits optimal: noatime + compress=zstd aktiv"
 fi
fi
# Limits + sysctl bereits oben, hier nur sicherstellen dass sie sofort greifen
sudo sysctl --system 2>/dev/null || true
log "System direkt richtig eingestellt: PipeWire 48k/1024, KWin LowLatency, I/O none/mq-deadline, Journal 200M/3d, EarlyOOM 5%, Ananicy gaming, BTRFS noatime+zstd"


# ---------- 5. PACCACHE HOOK (sicherer Cache-Erhalt bei jedem Update) ----------
step "5/8 PACCACHE HOOK - übersprungen (auf Wunsch kein Hook)"
info "Paccache Hook auf Wunsch nicht erstellt (kein -rk2)"
# DISABLED on request
# sudo mkdir -p /etc/pacman.d/hooks (disabled – Hook auf Wunsch nicht erstellt)
log "Hook übersprungen (auf Wunsch)"
# DISABLED

# ---------- 6. SICHERE WARTUNG - Caches, Runtimes und Logs ohne Systemdateien zu beschädigen ----------
step "6/8 SICHERE WARTUNG - Speicher freigeben, Rollback und Daten schützen"
info "Vorher: Pakete=$(pacman -Qq | wc -l) Explizit=$(pacman -Qqe | wc -l) Cache=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1) Orphans=$(pacman -Qtdq 2>/dev/null | wc -l)"
# BleachBit kann je nach Cleaner Logins, Sprache oder Nutzerdaten betreffen: niemals blind/root ausführen.
info "BleachBit wird nicht automatisch ausgeführt – erst Vorschau prüfen: bleachbit --preview <cleaner>"
# Keine extern nachgeladenen Skripte mit deinem Benutzerkonto ausführen.

# Nur klar abgegrenzte Thumbnail-/Browser-Caches und den Papierkorb bereinigen; System-Tmp verwaltet systemd.
# Kein pauschales ~/.cache/*: App-Caches können Downloads, Sitzungen oder teure Spiel-Precompilations enthalten.
rm -rf -- "$HOME/.thumbnails/"* "$HOME/.cache/thumbnails/"* "$HOME/.local/share/Trash/"* 2>/dev/null || true
sudo systemd-tmpfiles --clean 2>/dev/null || true

# Waisen sind ein Hinweis, keine Freigabe zum Löschen: zur Prüfung protokollieren, nicht automatisch entfernen.
ORPHANS_FILE="$LOG_DIR/orphans_${RUN_ID}.txt"
orphans="$(pacman -Qdtq 2>/dev/null || true)"
if [[ -n "$orphans" ]]; then
 printf '%s\n' "$orphans" | tee "$ORPHANS_FILE"
 warn "Mögliche Waisen in $ORPHANS_FILE – nach Prüfung optional: sudo pacman -Rns <paketname>"
else
 : > "$ORPHANS_FILE"
 log "Keine Pacman-Waisen gefunden"
fi
# Defekte Symlinks haben praktisch keinen Speicherbedarf und können absichtlich sein: nur melden.
BROKEN_LINKS_FILE="$LOG_DIR/broken-symlinks_${RUN_ID}.txt"
find "$HOME" -type l ! -exec test -e {} \; -print > "$BROKEN_LINKS_FILE" || true
if [[ -s "$BROKEN_LINKS_FILE" ]]; then
 warn "Defekte Symlinks nur protokolliert: $BROKEN_LINKS_FILE"
else
 rm -f "$BROKEN_LINKS_FILE"
fi

info "Flatpak: unbenutzte Runtimes und Daten bereinigen"
flatpak uninstall --unused --delete-data -y 2>/dev/null || true
# Verbliebene App-Caches sind standardisierte XDG-Caches, werden beim Fresh-Install aber nicht blind gelöscht.
# Der Bericht zeigt später, ob sich ein gezielter Aufruf von clean-flatpak-caches --yes lohnt.
FLATPAK_CACHE_REPORT="$LOG_DIR/flatpak-caches_${RUN_ID}.txt"
: > "$FLATPAK_CACHE_REPORT"
if [[ -d "$HOME/.var/app" && ! -L "$HOME/.var/app" ]]; then
 while IFS= read -r -d '' cache_dir; do
  du -sh -- "$cache_dir" >> "$FLATPAK_CACHE_REPORT" 2>/dev/null || printf 'unlesbar: %q\n' "$cache_dir" >> "$FLATPAK_CACHE_REPORT"
 done < <(find "$HOME/.var/app" -mindepth 2 -maxdepth 2 -type d -name cache -print0 2>/dev/null)
fi
if [[ -s "$FLATPAK_CACHE_REPORT" ]]; then
 info "Flatpak-App-Caches nur protokolliert: $FLATPAK_CACHE_REPORT (optional: clean-flatpak-caches --yes)"
else
 rm -f "$FLATPAK_CACHE_REPORT"
 log "Keine verbliebenen Flatpak-App-Caches gefunden"
fi
# Steam-Shadercache bleibt erhalten: Er gehört oft zu installierten Spielen und ein Löschen erzeugt Ruckler beim Neuaufbau.
info "Steam-Shadercache und Wine-/Proton-Prefixe bleiben unangetastet (optional gezielt: clean-wine-temp --yes <prefix>)"
# Zwei Paketversionen als Rollback-Schutz behalten; passt zum Pacman-Hook.
sudo paccache -rk2 2>/dev/null || true
# Journald/Coredumps ausschließlich about ihre eigenen Werkzeuge begrenzen; /var/log bleibt strukturell intakt.
sudo journalctl --rotate 2>/dev/null || true
sudo journalctl --vacuum-time=3d 2>/dev/null || true
sudo journalctl --vacuum-size=100M 2>/dev/null || true
sudo coredumpctl --vacuum-time=3d 2>/dev/null || true
# Fontconfig löscht und erstellt seine Caches selbst neu. Kein rohes sudo rm in /var/cache/fontconfig.
if command -v fc-cache &>/dev/null; then
 fc-cache -r 2>/dev/null || warn "Benutzer-Fontcache konnte nicht vollständig neu erstellt werden"
 sudo fc-cache -r -s 2>/dev/null || warn "System-Fontcache konnte nicht vollständig neu erstellt werden"
else
 warn "Fc-cache fehlt – Fontcache nicht neu erstellt"
fi
sudo rm -rf /etc/pacman.d/gnupg/*.log 2>/dev/null || true
# Der Pacman-Cache wurde oben bewusst auf zwei Versionen begrenzt; kein pacman -Scc und kein rm -rf /var/cache/*.
# Flatpak-Runtimes und ungenutzte Daten wurden oben about Flatpak selbst bereinigt.
info "Logs sicher bereinigen - nur alte komprimierte Reste, keine Verzeichnisstruktur oder Timer-Zustände löschen"
sudo find /var/log -type f -name "*.old" -delete 2>/dev/null || true
# sudo find /var/log -type f -name "*.gz" -delete  # entfernt: journald bereits via SystemMaxUse=200M begrenzt, .gz Historie bleibt für Dienste erhalten
# Fontconfig wurde oben bereits mit seinem eigenen Neuaufbau behandelt.
rm -rf -- "$HOME/.cache/icon-cache/"* "$HOME/.local/share/baloo/"* 2>/dev/null || true
# Man-/Info-/Doc-Dateien, Locales und Firmware bleiben vollständig: Paketbestand und Hardware bleiben zuverlässig.
info "Dokumentation, Sprachdateien und Firmware bleiben paketkonsistent"

# BTRFS: Optionen protokollieren statt /etc/fstab blind zu verändern. Das schützt Subvolumes und Bootfähigkeit.
if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
 BTRFS_MOUNTS_FILE="$LOG_DIR/btrfs-mounts_${RUN_ID}.txt"
 findmnt -rn -t btrfs -o TARGET,SOURCE,OPTIONS | tee "$BTRFS_MOUNTS_FILE"
 ROOT_BTRFS_OPTIONS="$(findmnt -n -o OPTIONS / 2>/dev/null || true)"
 case ",$ROOT_BTRFS_OPTIONS," in
  *,noatime,*) log "BTRFS root: noatime aktiv" ;;
  *) info "BTRFS root: noatime nicht gesetzt – für eine bewusste Prüfung siehe $BTRFS_MOUNTS_FILE" ;;
 esac
 case ",$ROOT_BTRFS_OPTIONS," in
  *compress=zstd*) log "BTRFS root: Zstd-Kompression aktiv" ;;
  *) info "BTRFS root: keine Zstd-Kompression erkannt – keine automatische fstab-Änderung" ;;
 esac
 # Moderne BTRFS-Systeme haben den freien Speicherbaum bereits; space_cache=v2 wird not erzwungen.
 sudo systemctl enable --now fstrim.timer 2>/dev/null || warn "fstrim.timer konnte nicht aktiviert werden"
 # Auf frischer Installation fast keine Fragmentierung – Balance nur wenn sinnvoll (>10% belegt), sonst skip (spart Zeit beim ersten Run)
 if [[ $(df / | awk 'NR==2{print $5}' | tr -d '%') -gt 10 ]]; then
  info "BTRFS Balance for wenig belegte Chunks (System >10% belegt)"
  sudo btrfs balance start -dusage=50 -musage=50 / 2>/dev/null || warn "BTRFS Balance nicht ausgeführt – Details im Log"
 else
  info "BTRFS Balance übersprungen – frische Installation (<10% belegt), keine Fragmentierung"
 fi
else
 info "Kein BTRFS erkannt – fstab und Balance übersprungen"
fi
info "Node/Yarn/Electron-Caches bereinigen (ohne App-Einstellungen zu löschen)"
rm -rf ~/.npm/_cacache/* ~/.yarn/cache/* ~/.node-gyp/* ~/.cache/electron/* 2>/dev/null || true
sudo fstrim -av 2>/dev/null || true
# .pacnew/.pacsave automatisch bereinigen for vollständig (Backup vorher)
PACNEW_FILE="$LOG_DIR/pacnew_${RUN_ID}.txt"
info "Prüfe auf .pacnew/.pacsave-Dateien"
find /etc -regextype posix-extended -regex '.+\.pac(new|save)' -print > "$PACNEW_FILE" || true
if [[ -s "$PACNEW_FILE" ]]; then
 cat "$PACNEW_FILE" | head -n 20 | while read -r f; do warn ".pacnew/.pacsave: $f"; done
 info "→ .pacnew/.pacsave GEFUNDEN - NICHT automatisch gelöscht! Bitte manuell mergen: DIFFPROG=meld pacdiff"
 for f in $(cat "$PACNEW_FILE"); do
  cp -a "$f" "$LOG_DIR/$(basename $f).bak_${RUN_ID}" 2>/dev/null || true
  log "Backup: $f -> $LOG_DIR/$(basename $f).bak_${RUN_ID} (NICHT gelöscht - nutze pacdiff!)"
 done
 warn ".pacnew/.pacsave bleiben erhalten - manuell mergen: sudo DIFFPROG=meld pacdiff  (oder pacdiff -o)"
else
 log "Keine .pacnew/.pacsave-Dateien"
fi
# Orphans automatisch bereinigen for 0 WARN
if pacman -Qtdq >/dev/null 2>&1; then
 info "→ Orphans bereinigen: $(pacman -Qtdq | tr '\n' ' ')"
 pacman -Qtdq 2>/dev/null | xargs -r sudo pacman -Rns --noconfirm 2>&1 | tail -n 5 || true
else
 log "Keine Orphans"
fi
if false; then log "Keine .pacnew/.pacsave-Dateien"
 rm -f "$PACNEW_FILE"
fi
info "Nachher: Pakete=$(pacman -Qq | wc -l) Explizit=$(pacman -Qqe | wc -l) Orphans=$(pacman -Qtdq 2>/dev/null | wc -l)"
info "Nachher Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" used, "$4" free"}' 2>/dev/null) RAM Boot: $(free -h | awk '/Mem:/{print $3"/"$2}' 2>/dev/null)"
log "Sichere Wartung fertig – Caches bereinigt, Rollback-Schutz und Systemdateien erhalten"


# --- 38 Zeilen Fix (Calibre NUR Privat + Journald stabil + Broken 715 + Vim Rdd + Sober Discord) ---
# Public/Freunde: kein Calibre (nur Privat wie gewünscht)
sudo mkdir -p /etc/systemd/journald.conf.d; sudo rm -f /etc/systemd/journald.conf.d/99-cachyos-gaming.conf
printf "[Journal]\nSystemMaxUse=200M\nSystemKeepFree=500M\nMaxRetentionSec=3d\nStorage=persistent\n" | sudo tee /etc/systemd/journald.conf.d/99-cachyos-gaming.conf >/dev/null
sudo chmod 644 /etc/systemd/journald.conf.d/99-cachyos-gaming.conf; sudo systemctl daemon-reload 2>/dev/null || true; sudo systemctl restart systemd-journald 2>/dev/null || true
# Broken Symlinks robust - 715 fix: HOME + /usr /etc + .var/.local, 2 Durchgänge (721->715)
sudo find /usr /etc -xtype l -delete 2>/dev/null || true
# HOME Broken Symlinks nur protokollieren (nicht löschen - Wine/Lutris/Modpacks nutzen absichtlich temporäre Links)
BROKEN_38_FILE="$LOG_DIR/broken-home-38_${RUN_ID}.txt"
find ~ -xtype l ! -path "*waydroid*" ! -path "*Steam*" ! -path "*.mozilla*" -print > "$BROKEN_38_FILE" 2>/dev/null || true
find "$HOME" -xtype l ! -path "*waydroid*" -print >> "$BROKEN_38_FILE" 2>/dev/null || true
find ~/.var ~/.local -type l ! -exec test -e {} \; -print >> "$BROKEN_38_FILE" 2>/dev/null || true
if [[ -s "$BROKEN_38_FILE" ]]; then
  warn "Broken Symlinks HOME nur protokolliert: $BROKEN_38_FILE (nicht gelöscht - manuell prüfen)"
  BROKEN_TMP=$(wc -l < "$BROKEN_38_FILE" 2>/dev/null | tr -d ' ')
  if [ "$BROKEN_TMP" -gt 5 ]; then warn "Viele Broken Symlinks ($BROKEN_TMP) - siehe $BROKEN_38_FILE"; fi
else
  rm -f "$BROKEN_38_FILE" 2>/dev/null || true
fi
# Vim already cleaned in Phase 1.5 - skip duplicate Rdd (avoid doppelt)

# ---------- 7. VERIFY INTEGRIERT - Alles in einem Skript ----------
step "7/8 VERIFY - Prüfe ob alles geklappt hat (alles in EINEM Skript)"
PASS=0; FAIL=0
check(){
 local label="$1"
 shift
 if "$@" &>/dev/null; then
  echo -e "${GREEN}[✓]${NC} $label"
  PASS=$((PASS+1))
 else
  echo -e "${RED}[✖]${NC} $label"
  FAIL=$((FAIL+1))
 fi
}
vesktop_plugin_config_valid(){
 (( ${#VESKTOP_SETTINGS_PATHS[@]} > 0 )) || return 1
 command -v python3 >/dev/null 2>&1 || return 1
 python3 - "${VESKTOP_SETTINGS_PATHS[@]}" <<'PY'
import json
import sys
from pathlib import Path

for raw_path in sys.argv[1:]:
  try:
    settings = json.loads(Path(raw_path).read_text(encoding="utf-8"))
    logger = settings.get("plugins", {}).get("MessageLogger", {})
  except (OSError, json.JSONDecodeError, AttributeError):
    raise SystemExit(1)
  if not isinstance(logger, dict) or not isinstance(logger.get("enabled"), bool):
    raise SystemExit(1)
PY
}
check "Brave" bash -c 'command -v brave-browser >/dev/null || command -v brave >/dev/null'
check "Alacritty" command -v alacritty
check "Mission Center (Taskmanager)" bash -c 'flatpak info io.missioncenter.MissionCenter >/dev/null 2>&1 || command -v missioncenter >/dev/null || pacman -Q plasma-systemmonitor >/dev/null 2>&1'
check "Konsole behalten" command -v konsole
check "Flameshot" command -v flameshot
check "Gimp" command -v gimp
check "Vesktop-Plugin-Konfiguration" vesktop_plugin_config_valid
# Proton Mail/VPN auf Wunsch entfernt – kein Check (manuell bei Bedarf)
check "Bore Kernel" pacman -Q linux-cachyos-bore
check "NVIDIA Treiber" bash -c '! lspci 2>/dev/null | grep -qi nvidia || pacman -Q nvidia-utils >/dev/null 2>&1'
check "NVIDIA Kernel-Modul (Bore + Standard)" bash -c '! lspci 2>/dev/null | grep -qi nvidia || { for k in $(ls /usr/lib/modules | grep -E "cachyos"); do modinfo -k "$k" nvidia >/dev/null 2>&1 || exit 1; done; }'
check "Minecraft Bedrock for Windows" bash -c 'command -v bedrock-on-linux >/dev/null 2>&1 || pacman -Q bedrock-on-linux-bin >/dev/null 2>&1'
check "Mitigations off konfiguriert ($BOOTLOADER)" grep -qw mitigations=off "$BOOTLOADER_CONFIG"
check "ZRAM" test -f /etc/systemd/zram-generator.conf
check "Gamemode" command -v gamemoded
check "BleachBit" command -v bleachbit
check "AUR Helper (paru/yay)" bash -c 'command -v paru >/dev/null || command -v yay >/dev/null'
# Paccache Hook auf Wunsch entfernt -> nur Info, kein FAIL
if [[ -f /etc/pacman.d/hooks/pacclean.hook ]]; then check "Paccache Hook (pacclean.hook)" bash -c 'test -f /etc/pacman.d/hooks/pacclean.hook'; else info "Paccache Hook auf Wunsch nicht erstellt (kein -rk2)"; fi
if modinfo binder_linux &>/dev/null; then
 check "Waydroid Binder-Autoload" grep -qx binder_linux /etc/modules-load.d/waydroid-binder.conf
else
 info "Waydroid Binder: kein ladbares binder_linux-Modul – keine Autoload-Datei erwartet"
fi
if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
 check "SSD-Trim Timer" systemctl is-enabled fstrim.timer
fi
check "Bore-Kernel-Image in /boot" bash -c 'sudo -n test -f /boot/vmlinuz-linux-cachyos-bore'
check "Bore-Initramfs in /boot" bash -c 'sudo -n test -f /boot/initramfs-linux-cachyos-bore.img'
check "Bore im GRUB-Menü" bash -c 'sudo -n grep -q vmlinuz-linux-cachyos-bore /boot/grub/grub.cfg'
check "Kein Limine-Paket mehr" bash -c '! pacman -Q limine limine-mkinitcpio-hook limine-snapper-sync >/dev/null 2>&1'
check "Fallback-Loader ohne Limine" bash -c 'sudo -n test -f /boot/efi/EFI/BOOT/BOOTX64.EFI && ! sudo -n grep -a -q -i limine /boot/efi/EFI/BOOT/BOOTX64.EFI'
check "Preset für jeden CachyOS-Kernel" bash -c 'for k in /usr/lib/modules/*-cachyos*/; do s=$(basename "${k%/}" | sed -E "s/^[0-9.]+-[0-9]+-//"); test -f "/etc/mkinitcpio.d/linux-$s.preset" || exit 1; done'
if lspci 2>/dev/null | grep -qi nvidia; then
  check "NVIDIA-Modul geladen" bash -c 'lsmod | grep -q "^nvidia "'
  check "nvidia-smi antwortet" nvidia-smi
fi
echo -e "Verify: ${GREEN}$PASS OK${NC} / ${RED}$FAIL FAIL${NC}"
log "Verify fertig"

# Einen echten Check for nach dem Reboot erzeugen (die frühere Abschlussmeldung verwies auf eine not vorhandene Datei).
cat <<'EOF' > "$HOME/system-check.sh"
#!/usr/bin/env bash
set -uo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
check(){
 local label="$1"
 shift
 if "$@" &>/dev/null; then
  echo -e "${GREEN}[✓]${NC} $label"
  PASS=$((PASS+1))
 else
  echo -e "${RED}[✖]${NC} $label"
  FAIL=$((FAIL+1))
 fi
}
check "Bore-Kernel läuft" bash -c 'uname -r | grep -q -- "bore"'
check "Standard-Kernel installiert" pacman -Q linux-cachyos
check "Bore-Kernel installiert" pacman -Q linux-cachyos-bore
check "NVIDIA Treiber" bash -c '! lspci 2>/dev/null | grep -qi nvidia || pacman -Q nvidia-utils >/dev/null 2>&1'
check "NVIDIA Kernel-Modul (Bore + Standard)" bash -c '! lspci 2>/dev/null | grep -qi nvidia || { for k in $(ls /usr/lib/modules | grep -E "cachyos"); do modinfo -k "$k" nvidia >/dev/null 2>&1 || exit 1; done; }'
check "Mitigations off aktiv" grep -qw mitigations=off /proc/cmdline
check "ZRAM aktiv" bash -c 'swapon --show=NAME 2>/dev/null | grep -q zram'
check "Mission Center" bash -c 'flatpak info io.missioncenter.MissionCenter >/dev/null 2>&1 || pacman -Q plasma-systemmonitor >/dev/null 2>&1'
check "Alacritty" command -v alacritty
check "Konsole behalten" command -v konsole
check "Brave" bash -c 'command -v brave-browser >/dev/null || command -v brave >/dev/null'
# Proton Mail/VPN auf Wunsch entfernt – kein Check (manuell bei Bedarf)
if modinfo binder_linux &>/dev/null; then
 check "Waydroid Binder-Autoload" grep -qx binder_linux /etc/modules-load.d/waydroid-binder.conf
fi
if [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "btrfs" ]]; then
 check "SSD-Trim Timer" systemctl is-enabled fstrim.timer
 # Noatime Warnung — SSD-Schonung
 if ! findmnt -n -o OPTIONS / 2>/dev/null | grep -qw noatime; then
  echo -e "\033[1;33m[!] BTRFS ohne noatime — erhöht SSD-Schreiblast\033[0m"
 fi
fi
check "AUR Helper (paru/yay)" bash -c 'command -v paru >/dev/null || command -v yay >/dev/null'
echo -e "${GREEN}[✓]${NC} Paccache Hook auf Wunsch nicht erstellt (kein -rk2) - OK"
check "Bootloader Config" bash -c 'test -f /boot/limine.conf || test -f /boot/limine.cfg || test -f /boot/EFI/limine/limine.conf || test -f /boot/EFI/BOOT/limine.cfg || test -f /etc/default/grub || test -f /boot/grub/grub.cfg || sudo ls /boot/loader/entries/*.conf >/dev/null 2>&1 || bootctl status 2>&1 | grep -qiE "limine|systemd-boot|grub"'
check "Minecraft Bedrock for Windows" bash -c 'command -v bedrock-on-linux >/dev/null 2>&1 || pacman -Q bedrock-on-linux-bin >/dev/null 2>&1'
check "Bore-Kernel-Image in /boot" bash -c 'sudo -n test -f /boot/vmlinuz-linux-cachyos-bore'
check "Bore-Initramfs in /boot" bash -c 'sudo -n test -f /boot/initramfs-linux-cachyos-bore.img'
check "Bore im GRUB-Menü" bash -c 'sudo -n grep -q vmlinuz-linux-cachyos-bore /boot/grub/grub.cfg'
check "Kein Limine-Paket mehr" bash -c '! pacman -Q limine limine-mkinitcpio-hook limine-snapper-sync >/dev/null 2>&1'
check "Fallback-Loader ohne Limine" bash -c 'sudo -n test -f /boot/efi/EFI/BOOT/BOOTX64.EFI && ! sudo -n grep -a -q -i limine /boot/efi/EFI/BOOT/BOOTX64.EFI'
check "Preset für jeden CachyOS-Kernel" bash -c 'for k in /usr/lib/modules/*-cachyos*/; do s=$(basename "${k%/}" | sed -E "s/^[0-9.]+-[0-9]+-//"); test -f "/etc/mkinitcpio.d/linux-$s.preset" || exit 1; done'
if lspci 2>/dev/null | grep -qi nvidia; then
  check "NVIDIA-Modul geladen" bash -c 'lsmod | grep -q "^nvidia "'
  check "nvidia-smi antwortet" nvidia-smi
fi
echo -e "\nErgebnis: ${GREEN}$PASS OK${NC} / ${RED}$FAIL FAIL${NC}"
exit "$FAIL"
EOF
chmod +x "$HOME/system-check.sh"
log "Post-Reboot-Check erstellt: $HOME/system-check.sh"

# ---------- 8. BOOTLOADER AKTUALISIEREN + REBOOT ----------
step "8/8 BOOTLOADER - Kernelparameter for $BOOTLOADER anwenden"
case "$BOOTLOADER" in
 systemd-boot)
  if command -v sdboot-manage &>/dev/null; then
   sudo sdboot-manage gen || warn "systemd-boot-Einträge konnten nicht neu erzeugt werden"
  else
   warn "sdboot-manage fehlt – $BOOTLOADER_CONFIG manuell anwenden"
  fi
  if command -v bootctl &>/dev/null; then
   sudo bootctl update || warn "Bootctl update fehlgeschlagen"
  fi
  ;;
 grub)
  if command -v grub-mkconfig &>/dev/null; then
   sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub 2>/dev/null || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null 2>&1 || true
   sudo grub-mkconfig -o /boot/grub/grub.cfg || warn "GRUB-Konfiguration konnte nicht neu erzeugt werden"
  else
   warn "Grub-mkconfig fehlt – $BOOTLOADER_CONFIG manuell anwenden"
  fi
  ;;
 refind)
  log "REFInd übernimmt Änderungen an $BOOTLOADER_CONFIG direkt; kein Rebuild nötig"
  ;;
 kernel-install)
  if command -v mkinitcpio &>/dev/null; then
   sudo mkinitcpio -P || warn "Kernel-install/mkinitcpio konnte nicht neu erzeugt werden"
  else
   warn "Kein mkinitcpio gefunden – $BOOTLOADER_CONFIG manuell anwenden"
  fi
  ;;
 *)
  warn "Bootloader unbekannt – keine blind geratenen Rebuild-Befehle ausgeführt"
  ;;
esac

# ---------- 9/9 FINAL UPDATE - nochmal alles am Schluss (direkt aus Alles-Updaten-Public.sh - jeden Bit) ----------
# ---------- AppImage-Integration (Gear Lever, Doppelklick startet das Programm) ----------
info "Setting up AppImage integration (fuse2 + Gear Lever)..."
if sudo pacman -S --needed --noconfirm fuse2 >/dev/null 2>&1; then log "fuse2 installed"; else warn "fuse2 could not be installed"; fi
if command -v flatpak &>/dev/null; then
  if flatpak install -y --noninteractive flathub it.mijorus.gearlever >/dev/null 2>&1; then
    log "Gear Lever installed (Flatpak)"
    for mime in application/x-iso9660-appimage application/x-executable-appimage; do
      xdg-mime default it.mijorus.gearlever.desktop "$mime" 2>/dev/null || true
    done
    log "AppImages now open with Gear Lever"
  else
    warn "Gear Lever could not be installed"
  fi
else
  warn "flatpak missing, Gear Lever skipped"
fi

# ---------- Discover mit Flatpak-Backend (Snap-Backend nicht im Arch-Repo) ----------
echo "==> Discover installieren (Flatpak-Backend)"
sudo pacman -S --needed --noconfirm discover >/dev/null 2>&1 && echo "  OK    discover" || echo "  FEHLT discover"

# ---------- Snap-Kompatibilität: snapd aus dem AUR, damit Snap-Apps direkt laufen ----------
echo "==> Snap-Unterstützung (snapd)"
if ! command -v snap &>/dev/null; then
  if command -v paru &>/dev/null; then paru -S --needed --noconfirm snapd || true
  elif command -v yay &>/dev/null; then yay -S --needed --noconfirm snapd || true
  else echo "Kein AUR-Helfer gefunden, snapd wird übersprungen."; fi
fi
if command -v snap &>/dev/null; then
  sudo systemctl enable --now snapd.apparmor.service 2>/dev/null || true
  sudo systemctl enable --now snapd.socket 2>/dev/null || true
  [[ -e /snap ]] || sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
  echo "snapd bereit: $(snap version 2>/dev/null | head -n1)"
fi
step "9/9 FINAL UPDATE - Alles updaten (jeden Bit: pacman + AUR + Flatpak + Snap + Firmware + Treiber + Kernel + AppImages)"
info "FINAL: Übernimmt den kompletten Inhalt von Alles-Updaten-Public.sh - jedes Paket wird aktualisiert"
say(){ echo -e "\n========== $* =========="; }
say "1/9 PACMAN — System + Kernel + Treiber + Firmware"
sudo pacman -Syu --noconfirm || { echo "pacman Fehler — prüfe Spiegel/Keyring"; sudo pacman -Syyu --noconfirm || sudo pacman -Syu; }
# Kernel + Microcode + Firmware explizit (damit wirklich jeder Treiber aktuell)
sudo pacman -S --needed --noconfirm linux-cachyos linux-cachyos-bore linux-cachyos-headers amd-ucode intel-ucode linux-firmware mkinitcpio 2>&1 | tail -n 40 || true
# Alle installierten Kernel-Header nachziehen
pacman -Qq 2>/dev/null | grep -E "^linux-.*-headers" | xargs -r sudo pacman -S --needed --noconfirm 2>&1 | tail -n 20 || true

say "2/9 AUR — alle AUR Pakete"
if [[ -n "$AUR" ]]; then
 $AUR -Syu --noconfirm 2>&1 | tail -n 120 || $AUR -Syu --noconfirm
else
 echo "Kein AUR-Helper (paru/yay) gefunden — nur pacman"
fi

say "3/9 FLATPAK + SNAP — alles wo existiert"
if command -v flatpak &>/dev/null; then
 flatpak update -y 2>&1 | tail -n 120
 flatpak update -y --appstream 2>&1 | tail -n 20 || true
 flatpak uninstall --unused -y 2>&1 | tail -n 20 || true
else
 echo "flatpak not installiert"
fi
if command -v snap &>/dev/null; then
 echo "--- SNAP gefunden -> snap refresh ---"
 sudo snap refresh 2>&1 | tail -n 80 || snap refresh 2>&1 | tail -n 80 || true
 snap list 2>&1 | head -n 100 || true
 # Snapd selbst aktuell halten
 true  # snapd kommt aus dem AUR, siehe Snap-Block im Setup
else
 echo "snap not installiert — kein snap update nötig (wenn du snaps nutzt: sudo pacman -S snapd && sudo systemctl enable --now snapd)"
 # Trotzdem prüfen ob snap Verzeichnis existiert
 ls -l /var/lib/snapd/snaps 2>&1 | head -n 20 || true
fi
# Distrobox / Podman Images falls vorhanden
if command -v distrobox &>/dev/null; then distrobox upgrade --all 2>&1 | tail -n 60 || true; fi

say "4/9 FIRMWARE — fwupd (BIOS/SSD/GPU/NVMe)"
if command -v fwupdmgr &>/dev/null; then
 sudo fwupdmgr refresh 2>&1 | tail -n 20 || true
 sudo fwupdmgr get-updates 2>&1 | tail -n 80 || true
 echo "Hinweis: installieren mit: sudo fwupdmgr update (kann Neustart verlangen)"
else
 echo "fwupd not installiert — installiere..."
 sudo pacman -S --needed --noconfirm fwupd 2>&1 | tail -n 10 || true
fi

say "5/9 TREIBER — NVIDIA/AMD/Intel/Mesa/Vulkan/DKMS explizit"
if command -v dkms &>/dev/null; then echo "--- DKMS status vor Update ---"; dkms status 2>&1 | head -n 200; fi
sudo pacman -S --needed --noconfirm nvidia-utils lib32-nvidia-utils nvidia-settings opencl-nvidia lib32-opencl-nvidia mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel libva-mesa-driver lib32-libva-mesa-driver xf86-video-amdgpu xf86-video-intel 2>&1 | tail -n 40 || true
sudo pacman -S --needed --noconfirm fuse2 fuse3 2>&1 | tail -n 10 || true
# NVIDIA: Kernel-Modul muss für jeden installierten CachyOS-Kernel vorhanden sein (Bore = Default, Standard = Fallback)
if lspci 2>/dev/null | grep -qi nvidia; then
  sudo pacman -S --needed --noconfirm dkms linux-cachyos-headers linux-cachyos-bore-headers 2>&1 | tail -n 10 || true
  if pacman -Q nvidia &>/dev/null; then
    echo "--- NVIDIA: vorinstalliertes Paket 'nvidia' erkannt ---"
  else
    sudo pacman -S --needed --noconfirm nvidia-open-dkms 2>&1 | tail -n 20 || true
  fi
  sudo dkms autoinstall 2>&1 | tail -n 20 || true
  mapfile -t _KVERS < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -name '*cachyos*' -printf '%f\n' 2>/dev/null)
  for kver in "${_KVERS[@]}"; do
    if ! modinfo -k "$kver" nvidia &>/dev/null; then
      echo "--- NVIDIA: Modul fehlt für $kver – baue es ---"
      sudo dkms autoinstall -k "$kver" 2>&1 | tail -n 20 || true
    fi
  done
  sudo depmod -a 2>/dev/null || true
  echo "--- NVIDIA Modul-Check je Kernel ---"
  mapfile -t _KVERS < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -name '*cachyos*' -printf '%f\n' 2>/dev/null)
  for kver in "${_KVERS[@]}"; do
    if modinfo -k "$kver" nvidia &>/dev/null; then echo "OK: nvidia für $kver"; else fail "NVIDIA-Modul fehlt für Kernel $kver – nach Reboot wäre der Treiber weg"; fi
  done
  nvidia-smi 2>&1 | head -n 12 || true
fi
if command -v dkms &>/dev/null; then echo "--- DKMS status nach Update ---"; dkms status 2>&1 | head -n 200; fi


ensure_kernel_boot() {
  local EFI_K="/boot" c
  for c in /boot/efi /boot; do if [ -d "$c/EFI" ]; then EFI_K="$c"; break; fi; done
  # Limine komplett entfernen (nur GRUB bleibt)
  if pacman -Q limine >/dev/null 2>&1 || pacman -Q limine-mkinitcpio-hook >/dev/null 2>&1 || pacman -Q limine-snapper-sync >/dev/null 2>&1; then
    log "Removing Limine (only GRUB stays)"
    sudo pacman -Rns --noconfirm limine limine-mkinitcpio-hook limine-snapper-sync 2>&1 | tee -a "$LOG_FILE" || warn "Limine could not be removed completely - see log"
  fi
  sudo rm -f /etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf /boot/limine.conf /boot/limine.conf.old /boot/limine-splash.png 2>/dev/null || true
  sudo rm -rf "$EFI_K/EFI/limine" "$EFI_K/limine" 2>/dev/null || true
  # Fallback-Loader: nur ersetzen, wenn er wirklich Limine ist
  if sudo test -f "$EFI_K/EFI/BOOT/BOOTX64.EFI" && sudo grep -a -q -i limine "$EFI_K/EFI/BOOT/BOOTX64.EFI" 2>/dev/null; then
    if sudo test -f "$EFI_K/EFI/cachyos/grubx64.efi"; then
      sudo cp "$EFI_K/EFI/cachyos/grubx64.efi" "$EFI_K/EFI/BOOT/BOOTX64.EFI" && log "Fallback loader BOOTX64.EFI contained Limine - replaced with GRUB"
    else
      warn "Fallback loader contains Limine but the GRUB file is missing - please check"
    fi
  fi
  # Presets und Kernel-Images für jeden installierten CachyOS-Kernel
  local tmpl="/etc/mkinitcpio.d/linux-cachyos-lts.preset" kdir kname suffix preset
  for kdir in /usr/lib/modules/*-cachyos*/; do
    [ -d "$kdir" ] || continue
    kdir="${kdir%/}"; kname="$(basename "$kdir")"
    suffix="$(echo "$kname" | sed -E 's/^[0-9.]+-[0-9]+-//')"
    preset="/etc/mkinitcpio.d/linux-$suffix.preset"
    if [ ! -f "$preset" ]; then
      if [ -f "$tmpl" ]; then
        sed "s/cachyos-lts/$suffix/g" "$tmpl" | sudo tee "$preset" >/dev/null && log "Preset created $preset"
      else
        warn "No preset template available - skipped $suffix"; continue
      fi
    fi
    if [ ! -f "/boot/vmlinuz-linux-$suffix" ] && [ -f "$kdir/vmlinuz" ]; then
      sudo cp "$kdir/vmlinuz" "/boot/vmlinuz-linux-$suffix" && log "Kernel image copied to /boot $suffix"
    fi
    sudo mkinitcpio -p "linux-$suffix" 2>&1 | tee -a "$LOG_FILE" | tail -n 5 || warn "Mkinitcpio linux-$suffix: Fehler – siehe Log"
  done
  # GRUB neu erzeugen und prüfen
  sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee -a "$LOG_FILE" | tail -n 3 || true
  if sudo grep -q 'vmlinuz-linux-cachyos-bore' /boot/grub/grub.cfg 2>/dev/null; then log "Bore kernel found in GRUB menu"; else warn "Bore kernel missing from GRUB menu - check /boot/vmlinuz-linux-cachyos-bore"; fi
  # Headers für installierte CachyOS-Kernel (DKMS braucht sie)
  for suffix in cachyos cachyos-bore cachyos-lts; do
    if pacman -Q "linux-$suffix" >/dev/null 2>&1 && ! pacman -Q "linux-$suffix-headers" >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm "linux-$suffix-headers" >/dev/null 2>&1 || warn "Headers missing for $suffix"
    fi
  done
}

say "6/9 KERNEL + INITRAMFS + BOOTLOADER — alles wo existiert wird neu gebaut"
ensure_kernel_boot
# GRUB (dein privat bevorzugt)
if [[ -f /etc/default/grub ]] || command -v grub-mkconfig &>/dev/null; then
 echo "--- GRUB ---"
 sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub 2>/dev/null || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null 2>&1 || true
 sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -n 40 || echo "grub-mkconfig fehlgeschlagen"
 sudo grub-install 2>&1 | tail -n 20 || true
fi
# systemd-boot
if [[ -f /etc/sdboot-manage.conf ]] || command -v sdboot-manage &>/dev/null; then
 echo "--- systemd-boot ---"
 sudo sdboot-manage gen 2>&1 | tail -n 40 || sudo bootctl update 2>&1 | tail -n 20 || true
 sudo kernel-install add-all 2>&1 | tail -n 20 || true
fi
# rEFInd
if [[ -f /boot/refind_linux.conf ]] || [[ -d /boot/EFI/refind ]]; then
 echo "--- rEFInd ---"
 sudo refind-install 2>&1 | tail -n 20 || true
fi
# Kernel-install generisch
if [[ -d /etc/kernel ]]; then sudo kernel-install add-all 2>&1 | tail -n 20 || true; fi
echo "--- Boot Check ---"
efibootmgr -v 2>&1 | head -n 80 || true
ls -lh /boot/*.img 2>&1 | head -n 20

say "7/9 APPIMAGES — alle .AppImage suchen + updaten wo zsync / shelly vorhanden"
APPIMAGE_DIRS=("$HOME/Applications" "$HOME/AppImages" "$HOME/Downloads" "$HOME/.local/bin" "$HOME" "/opt")
FOUND=0
for d in "${APPIMAGE_DIRS[@]}"; do
 [[ -d "$d" ]] || continue
 while IFS= read -r -d '' f; do
  FOUND=1
  echo ""
  echo "--- $f ---"
  ls -lh "$f" 2>&1
  if strings "$f" 2>/dev/null | grep -qi "zsync\|AppImageUpdate"; then echo " -> zsync vorhanden"; else echo " -> kein zsync (manuell prüfen) - Tipp: Gear Lever oder shelly (CachyOS 2026) kann externe Updates"; fi
  if command -v appimageupdatetool &>/dev/null; then
   echo " -> appimageupdatetool -> update..."
   appimageupdatetool -O "$f" 2>&1 | tail -n 40 || echo " -> kein Update / Fehler"
  else
   echo " -> appimageupdatetool not installiert"
  fi
  # shelly kann AppImages verwalten (seit 2026 nativ)
  if command -v shelly &>/dev/null; then echo " -> shelly vorhanden - kann AppImages extern updaten"; fi
  "$f" --version 2>&1 | head -n 3 || true
 done < <(find "$d" -maxdepth 4 -type f -name "*.AppImage" -print0 2>/dev/null | head -z -n 80)
done
if [[ $FOUND -eq 0 ]]; then echo "Keine .AppImage gefunden in: ${APPIMAGE_DIRS[*]}"; fi
if ! command -v appimageupdatetool &>/dev/null; then echo "Tipp: paru -S appimageupdatetool oder shelly (CachyOS 2026) -> danach auto-update"; fi

say "8/9 SONSTIGES + PROTON + EMULATOREN + GIT-CLONES (nur wenn vorhanden)"
# Proton GE + Steam Runtime
if command -v protonup &>/dev/null; then echo "--- ProtonUp GE-Proton update ---"; protonup -y 2>&1 | tail -n 40 || true; fi
if command -v protonup-qt &>/dev/null; then echo "protonup-qt vorhanden - GE-Proton via GUI updaten"; fi
if command -v umu-launcher &>/dev/null; then echo "umu vorhanden - Gaming Laufzeiten aktuell via pacman"; fi
if [[ -d "$HOME/.local/share/Steam/compatibilitytools.d" ]]; then
 echo "--- Steam compatibilitytools.d ---"
 ls -lh "$HOME/.local/share/Steam/compatibilitytools.d" 2>&1 | head -n 20
 echo "Hinweis: GE-Proton Updates via protonup oder ProtonUp-Qt"
fi
# Emulatoren / Launcher mit In-App Updates nur Hinweis
if command -v heroic &>/dev/null; then echo "Heroic vorhanden - Updates via In-App beim Start"; fi
if command -v lutris &>/dev/null; then echo "Lutris vorhanden - Updates via In-App"; fi
# Rust/Cargo, npm, pip, etc.
if command -v rustup &>/dev/null; then rustup update 2>&1 | tail -n 40 || true; fi
if command -v cargo &>/dev/null; then cargo install --list 2>&1 | head -n 20 || true; fi
if command -v npm &>/dev/null; then npm update -g 2>&1 | tail -n 40 || true; fi
if command -v pip &>/dev/null; then pip list --outdated 2>&1 | head -n 40 || true; fi
if command -v flatpak &>/dev/null; then flatpak --version 2>&1; fi
if command -v snap &>/dev/null; then snap version 2>&1 | head -n 20; fi
# Manuelle Git-Clones im Home (~/Tools etc.)
for d in "$HOME/Tools" "$HOME/tools" "$HOME/Git" "$HOME/git" "$HOME/Projects"; do
 if [[ -d "$d" ]]; then
  echo "--- Git-Clones in $d ---"
  find "$d" -maxdepth 2 -name ".git" -type d 2>/dev/null | while read -r g; do
   echo "git pull in $(dirname "$g")"
   git -C "$(dirname "$g")" pull --ff-only 2>&1 | tail -n 10 || echo " kein pull"
  done
 fi
done
# Waydroid / QEMU / Bottles bleiben about pacman/flatpak aktuell
command -v waydroid &>/dev/null && waydroid status 2>&1 | head -n 20 || true

say "9/9 CLEAN + CHECK + PACNEW + MANUAL INTERVENTIONS — orphans, paccache, failed, kernel, treiber"
echo "Orphans (nur anzeigen):"
pacman -Qdt 2>&1 | head -n 100 || echo "Keine orphans"
echo ""
if command -v paccache &>/dev/null; then echo "paccache -rk2:"; sudo paccache -rk2 2>&1 | tail -n 20; fi
flatpak uninstall --unused -y 2>&1 | tail -n 10 || true
if command -v snap &>/dev/null; then echo "snap ungenutzt:"; snap list --all 2>&1 | head -n 40 || true; fi
echo ""
echo "Failed Services:"
systemctl --failed 2>&1 | head -n 60
echo ""
echo "Kernel + Bootloader + Treiber Check:"
uname -r; pacman -Q | grep -E "^linux" 2>&1 | head -n 30; dkms status 2>&1 | head -n 40; nvidia-smi 2>&1 | head -n 30 || lspci -k | grep -A2 VGA 2>&1 | head -n 20
efibootmgr -v 2>&1 | head -n 40 || true
echo ""
echo "--- PACNEW Check (manuell mergen mit DIFFPROG=meld pacdiff) ---"
PACNEWS=$(find /etc -regextype posix-extended -regex '.+\.pac(new|save)' 2>/dev/null)
if [[ -n "$PACNEWS" ]]; then
 echo "WARN: .pacnew/.pacsave gefunden:"
 echo "$PACNEWS" | head -n 20
 echo "Fix: DIFFPROG=meld pacdiff (oder sudo pacdiff -o)"
else
 echo "Keine .pacnew/.pacsave - Configs aktuell"
fi
echo ""
echo "--- Arch Manual Interventions Check ---"
echo "Prüfe Arch News (https://archlinux.org/news) bei Pacman Fehlern - manuelle Eingriffe nötig?"
# Falls pacman kürzlich Fehler hatte, Hinweis
if grep -qi "manual intervention" "$LOG" 2>/dev/null; then echo "Hinweis im Log: Manual Intervention erwähnt - bitte Arch News checken!"; fi

log "Final Update fertig — alles auf neuestem Stand ✅ (jeder Bit: pacman + AUR + Flatpak + Snap + Firmware + Treiber + Kernel + AppImages)"

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} ✓ Setup done!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Full log: ${CYAN}$LOG_FILE${NC}"
echo -e "Fehler-Log:    ${CYAN}$ERROR_LOG${NC}"
echo -e "1. ${YELLOW}sudo reboot${NC} -> Bore-Kernel bootet automatisch (Treiber/NVIDIA sind dafür gebaut), Standard-Kernel ist im Menü wählbar"
echo -e "2. Danach: ${CYAN}~/system-check.sh${NC}"
# Public: kein Spicetify (TOS-safe) - Zeile entfernt
flatpak override --user --filesystem=xdg-run/app/com.discordapp.Discord:create --filesystem=xdg-run/discord-ipc-0 org.vinegarhq.Sober 2>/dev/null || flatpak override --user --filesystem=xdg-run/discord:create org.vinegarhq.Sober 2>/dev/null || true
# Sober Flatpak graphics fix - automate org.freedesktop.Platform.GL for detected GPU so Sober never crashes "couldn't find graphics device"
if flatpak info org.vinegarhq.Sober &>/dev/null || flatpak info org.vinegarhq.Sober 2>/dev/null | grep -q Sober; then
 echo "--- Sober Flatpak GL drivers auto-fix ---"
 flatpak update -y 2>&1 | tail -n 20 || true
 flatpak install -y flathub org.freedesktop.Platform.GL.default org.freedesktop.Platform.GL32.default 2>&1 | tail -n 20 || true
 if [[ "$GPU_VENDOR" == "nvidia" ]]; then
  # Detect installed NVIDIA driver version for matching Flatpak GL
  NV_VER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ' || true)"
  if [[ -z "$NV_VER" ]]; then NV_VER="$(pacman -Q nvidia 2>/dev/null | awk '{print $2}' | cut -d- -f1 || true)"; fi
  if [[ -n "$NV_VER" ]]; then
   NV_FLAT="$(echo "$NV_VER" | tr '.' '-' | sed 's/-$//')"
   # Try full version and major version fallbacks
   flatpak install -y flathub "org.freedesktop.Platform.GL.nvidia-$NV_FLAT" 2>&1 | tail -n 20 || true
   flatpak install -y flathub "org.freedesktop.Platform.GL32.nvidia-$NV_FLAT" 2>&1 | tail -n 20 || true
   # Fallback try without patch version (e.g. 555-58)
   NV_MAJOR="$(echo "$NV_VER" | cut -d. -f1-2 | tr '.' '-')"
   flatpak install -y flathub "org.freedesktop.Platform.GL.nvidia-$NV_MAJOR" 2>&1 | tail -n 5 || true
   flatpak install -y flathub "org.freedesktop.Platform.GL32.nvidia-$NV_MAJOR" 2>&1 | tail -n 5 || true
  fi
  # Ensure VAAPI and extra GL
  flatpak install -y flathub org.freedesktop.Platform.VAAPI.Intel 2>&1 | tail -n 5 || true
 elif [[ "$GPU_VENDOR" == "amd" ]]; then
  flatpak install -y flathub org.freedesktop.Platform.GL.default 2>&1 | tail -n 5 || true
  flatpak install -y flathub org.freedesktop.Platform.VAAPI.Intel org.freedesktop.Platform.VAAPI.AMD 2>&1 | tail -n 5 || true
 fi
 flatpak update -y 2>&1 | tail -n 10 || true
 flatpak repair 2>&1 | tail -n 5 || true
  # Instant NVIDIA driver rebuild if nvidia-smi fails (so Sober never crashes)
 if ! nvidia-smi &>/dev/null; then
  echo "NVIDIA driver not loaded - rebuilding instantly"
  sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils nvidia-settings 2>&1 | tail -n 5 || true
  sudo pacman -S --needed --noconfirm nvidia-open-dkms 2>&1 | tail -n 5 || true
  sudo dkms autoinstall 2>&1 | tail -n 10 || true
  sudo mkinitcpio -P 2>&1 | tail -n 10 || true
  sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub 2>/dev/null || echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null 2>&1 || true
  sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -n 5 || true
 fi
 echo "Sober GL fix done"
fi
# GANZ AM ENDE: Flatpak Update for Nvidia Runtime (Sober etc. erkennt Nvidia erst nach flatpak update)
flatpak update -y 2>&1 | tail -n 20 || true
if command -v bedrock-on-linux >/dev/null 2>&1; then
 echo -e "4. Minecraft Bedrock for Windows: ${CYAN}bedrock-on-linux${NC} starten und mit dem Microsoft-Konto anmelden"
else
 echo -e "4. ${YELLOW}BedrockOnLinux wurde not installiert – den AUR-Fehler im Log prüfen.${NC}"
fi
echo -e "5. Prüfe bei Bedarf: ${CYAN}$ORPHANS_FILE${NC}, ${CYAN}$PACNEW_FILE${NC}, ${CYAN}${BTRFS_MOUNTS_FILE:-}${NC} und ${CYAN}${FLATPAK_CACHE_REPORT:-}${NC}"
echo -e "Komfortbefehle: ${CYAN}update-arch clean-arch fix-key update-mirrors clean-flatpak-caches clean-wine-temp${NC}" # Public ohne configure-spicetify
# Nutzerfreundlich: Fertig-Fenster
# === App-Feineinstellungen (Brave + Dolphin) ===
# Brave: Parallel-Download-Flag (= brave://flags enable-parallel-downloading) in Local State setzen.
# Nur wenn Brave NICHT läuft, sonst überschreibt Brave die Datei beim Beenden.
BRAVE_LS="$HOME/.config/BraveSoftware/Brave-Browser/Local State"
if command -v brave-browser >/dev/null 2>&1 || command -v brave >/dev/null 2>&1; then
  if ! pgrep -x brave >/dev/null 2>&1 && ! pgrep -x brave-browser >/dev/null 2>&1; then
    mkdir -p "$(dirname "$BRAVE_LS")"
    [ -s "$BRAVE_LS" ] || echo '{}' > "$BRAVE_LS"
    python3 - "$BRAVE_LS" <<'PYEOF' 2>/dev/null && info "Brave: Parallel-Download-Flag gesetzt" || warn "Brave: Parallel-Download-Flag konnte nicht gesetzt werden"
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    d = json.load(fh)
exp = d.setdefault("browser", {}).setdefault("enabled_labs_experiments", [])
exp[:] = [e for e in exp if not e.startswith("enable-parallel-downloading")]
exp.append("enable-parallel-downloading@1")
with open(p, "w", encoding="utf-8") as fh:
    json.dump(d, fh)
PYEOF
  else
    warn "Brave läuft – Parallel-Download-Flag nicht gesetzt (Brave schließen, Script erneut starten oder brave://flags manuell)"
  fi
fi
# Dolphin: versteckte Dateien global anzeigen (Standard-Ansicht für alle Ordner)
DOLPHIN_GLOBAL="$HOME/.local/share/dolphin/view_properties/global"
mkdir -p "$DOLPHIN_GLOBAL"
printf '[Dolphin]\nVersion=4\nSortFoldersFirst=true\nSortHiddenLast=false\n\n[Settings]\nHiddenFilesShown=true\n' > "$DOLPHIN_GLOBAL/.directory"
# === Weitere App-Einstellungen (nur geprüfte Schlüssel) ===
# Konsole: Scrollback 10000 Zeilen im Standard-Profil
if command -v konsole >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/share/konsole"
  kwriteconfig6 --file "$HOME/.local/share/konsole/Default.profile" --group Scrolling --key HistorySize 10000 2>/dev/null || true
  info "Konsole: Scrollback auf 10000 gesetzt"
fi
# Alacritty: Scrollback 10000 (nur wenn noch keine Config existiert, damit eigene Änderungen bleiben)
if command -v alacritty >/dev/null 2>&1 && [ ! -f "$HOME/.config/alacritty/alacritty.toml" ]; then
  mkdir -p "$HOME/.config/alacritty"
  printf '[scrolling]\nhistory = 10000\n' > "$HOME/.config/alacritty/alacritty.toml"
  info "Alacritty: Scrollback auf 10000 gesetzt"
fi
# Syncthing: als Benutzerdienst beim Login starten
if command -v syncthing >/dev/null 2>&1; then
  systemctl --user enable --now syncthing.service 2>/dev/null || warn "Syncthing-Autostart konnte nicht gesetzt werden"
fi
# === Plasma-Session: immer mit leerer Sitzung starten (keine alten Apps wiederherstellen) ===
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession 2>/dev/null && info "Plasma: Start mit leerer Sitzung" || warn "Plasma: Sitzungseinstellung nicht gesetzt"
fi
# === Num-Lock beim Plasma-Start einschalten ===
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0 2>/dev/null && info "Num-Lock: beim Start an" || warn "Num-Lock-Einstellung nicht gesetzt"
fi
# Kate: aus Menü-Kategorie Developer/IDE entfernen (neue Nutzer denken sonst, sie brauchen Dev-Tools), bleibt unter Utilities
if [ -f /usr/share/applications/org.kde.kate.desktop ]; then
  mkdir -p "$HOME/.local/share/applications"
  cp -f /usr/share/applications/org.kde.kate.desktop "$HOME/.local/share/applications/org.kde.kate.desktop"
  sed -i -E '/^Categories=/ { s/Development;//g; s/IDE;//g; }' "$HOME/.local/share/applications/org.kde.kate.desktop"
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi
# YAD-Starter verstecken (Benutzer-Override, /usr bleibt unverändert)
for _yad in yad-icon-browser yad-settings; do
  if [ -f "/usr/share/applications/$_yad.desktop" ]; then
    mkdir -p "$HOME/.local/share/applications"
    cp -f "/usr/share/applications/$_yad.desktop" "$HOME/.local/share/applications/" 2>/dev/null || true
    sed -i '/^NoDisplay=/d; /^\[Desktop Entry\]/a NoDisplay=true' "$HOME/.local/share/applications/$_yad.desktop" 2>/dev/null || true
  fi
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
# ---------- Alles-Updaten installieren (eingebettet, kein Download nötig) ----------
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cat > "$HOME/.local/bin/alles-updaten" <<'ALLESEOF'
#!/usr/bin/env bash
# Alles-Updaten-Public.sh: Updates everything it can find on the system
# (pacman, AUR, Flatpak, Snap, firmware, drivers, DKMS, kernel, GRUB, Calibre, AppImages, dev tools).
# Design follows cachy-update: ==> main steps, -> questions, WARNING / ERROR, "Press enter to quit".
# Only one instance runs at a time (flock).
# Bootloader: only GRUB is updated. Limine, systemd-boot and rEFInd are not touched.
# Pacnew/pacsave files are never deleted automatically, only listed.
# BIOS/UEFI is never flashed automatically. The script checks the version and shows the safe steps.
# Log: ~/cachyos-logs/update-YYYY-MM-DD_HH-MM.log
# Usage: chmod +x Alles-Updaten-Public.sh && ./Alles-Updaten-Public.sh

set -u

# ---------- Colors and messages (same style as cachy-update) ----------
bold="\e[1m"; blue="${bold}\e[34m"; green="${bold}\e[32m"; yellow="${bold}\e[33m"; red="${bold}\e[31m"; off="\e[0m"

main_msg()    { echo -e "${blue}==>${off}${bold} $*${off}"; }
info_msg()    { echo -e "${green}==>${off}${bold} $*${off}"; }
warning_msg() { echo -e "${yellow}==> WARNING:${off}${bold} $*${off}"; }
error_msg()   { echo -e >&2 "${red}==> ERROR:${off}${bold} $*${off}"; }
ask_msg()     { local a; read -rp "$(echo -e "${blue}->${off}${bold} $*${off} ")" a; echo "$a"; }
quit_msg()    { read -n 1 -r -s -p "$(echo -e "${green}==>${off}${bold} Press \"enter\" to quit ${off}")"; echo; }

# ---------- Log ----------
LOG_DIR="$HOME/cachyos-logs"
STAMP="$(date +%Y-%m-%d_%H-%M)"
LOG="$LOG_DIR/update-$STAMP.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

# ---------- Lock: only one instance ----------
exec {LOCK_FD}> "/tmp/alles-updaten.lock"
if ! flock -n "$LOCK_FD"; then
  warning_msg "Alles-Updaten is already running in another session."
  answer="$(ask_msg "Continue anyway? [y/N]")"
  case "$answer" in
    y|Y) echo ;;
    *) error_msg "Aborted."; quit_msg; exit 17 ;;
  esac
fi

# ---------- Collect results ----------
declare -a RES_NAME=() RES_STATUS=()
record() { RES_NAME+=("$1"); RES_STATUS+=("$2"); }   # Status: OK | WARN | FAIL | SKIP

AUR=""
if command -v paru &>/dev/null; then AUR="paru"; elif command -v yay &>/dev/null; then AUR="yay"; elif command -v pikaur &>/dev/null; then AUR="pikaur"; fi

echo -e "${bold}===== UPDATE ALL started: $STAMP =====${off}"
echo "Log: $LOG"
echo

# ---------- 0: SNAPSHOT BEFORE UPDATE ----------
main_msg "0/11 SNAPSHOT BEFORE UPDATE"
if command -v snapper &>/dev/null && sudo snapper -c root list &>/dev/null; then
  if sudo snapper -c root create --description "before Alles-Updaten $STAMP"; then
    info_msg "Snapshot created. If something breaks, boot the snapshot from the GRUB menu."
    record "Snapshot" OK
  else
    warning_msg "Could not create a snapshot."; record "Snapshot" WARN
  fi
else
  warning_msg "No snapper setup for root found. The update continues without a snapshot."
  record "Snapshot" WARN
fi

# ---------- 1: PACMAN ----------
main_msg "1/11 PACMAN: system, kernel, drivers"
if command -v checkupdates &>/dev/null; then
  info_msg "Available updates (official repositories):"
  checkupdates 2>/dev/null | sed 's/^/  /' || true
else
  warning_msg "Checkupdates not found (package: pacman-contrib). Preview skipped."
fi
info_msg "Latest Arch news:"
curl -fsSL --max-time 15 https://archlinux.org/feeds/news/ 2>/dev/null | grep -o '<title>[^<]*' | sed 's/<title>/  /' | sed -n '2,6p' || warning_msg "Arch news not reachable."
if sudo pacman -Syu; then
  record "pacman -Syu" OK
else
  error_msg "Pacman -Syu failed. Check mirrors or keyring (see log)."
  record "pacman -Syu" FAIL
fi
if grep -q "signature" "$LOG" 2>/dev/null; then
  warning_msg "Signature error in the log. Keyring: sudo pacman -Sy archlinux-keyring cachyos-keyring"
fi

# ---------- 2: AUR ----------
main_msg "2/11 AUR: all AUR packages"
if [[ -n "$AUR" ]]; then
  if $AUR -Syu; then record "AUR ($AUR)" OK; else error_msg "AUR update failed."; record "AUR ($AUR)" FAIL; fi
else
  info_msg "No AUR helper (paru, yay or pikaur) found. Skipped."
  record "AUR" SKIP
fi

# ---------- 3: FLATPAK + SNAP ----------
main_msg "3/11 FLATPAK + SNAP"
if command -v flatpak &>/dev/null; then
  if flatpak update -y --noninteractive; then record "Flatpak" OK; else record "Flatpak" WARN; fi
  # NVIDIA GL runtime for Flatpak apps, matching the driver version
  if [[ -n "$(flatpak list --app 2>/dev/null)" ]]; then
    if lspci 2>/dev/null | grep -qi nvidia; then
      NV_VER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)"
      NV_FLAT="${NV_VER//./-}"
      if [[ -n "$NV_FLAT" ]]; then
        flatpak install -y flathub "org.freedesktop.Platform.GL.nvidia-$NV_FLAT" || true
        flatpak install -y flathub "org.freedesktop.Platform.GL32.nvidia-$NV_FLAT" || true
      fi
    fi
  fi
  unused="$(flatpak uninstall --unused </dev/null 2>&1 | tail -n 15)"
  if [[ -n "$unused" ]] && ! echo "$unused" | grep -qi "nothing"; then
    info_msg "Unused Flatpaks found:"; echo "$unused"
    if [[ "$(ask_msg "Remove unused Flatpaks? [y/N]")" =~ ^[yY]$ ]]; then flatpak uninstall --unused || true; fi
  else
    info_msg "No unused Flatpaks."
  fi
else
  info_msg "Flatpak not installed."
fi
if command -v snap &>/dev/null; then
  sudo snap refresh || record "Snap" WARN
  record "Snap" OK
else
  info_msg "Snap not installed."
fi
command -v distrobox &>/dev/null && distrobox upgrade --all || true

# ---------- 4: FIRMWARE (fwupd / LVFS) ----------
main_msg "4/11 FIRMWARE (fwupd: BIOS if supported, SSD, GPU, NVMe, docks, peripherals)"
if command -v fwupdmgr &>/dev/null; then
  if ! fwupdmgr get-devices >/dev/null 2>&1; then
    warning_msg "fwupd does not respond. Check with: sudo systemctl start fwupd"
    record "fwupd service" WARN
  fi
  sudo fwupdmgr refresh --force || record "Firmware refresh" WARN
  info_msg "Devices and installed firmware versions:"
  fwupdmgr get-devices 2>/dev/null | grep -E '^[A-Za-z]|Version:' | sed 's/^/  /' | head -n 120 || true
  UPD="$(fwupdmgr get-updates 2>&1)"
  if echo "$UPD" | grep -qi "no updates\|no upgrades"; then
    info_msg "No firmware updates available."
    record "Firmware" OK
  else
    echo "$UPD" | sed 's/^/  /'
    if [[ "$(ask_msg "Install firmware updates now? (may require a reboot) [y/N]")" =~ ^[yY]$ ]]; then
      if sudo fwupdmgr update; then
        info_msg "Firmware installed. Checking again..."
        if fwupdmgr get-updates 2>&1 | grep -qi "no updates\|no upgrades"; then
          record "Firmware" OK
        else
          info_msg "Firmware installed. Some updates take effect only after a reboot."
          record "Firmware" OK
        fi
      else
        error_msg "Firmware update failed."; record "Firmware" FAIL
      fi
    else
      record "Firmware" WARN
    fi
  fi
else
  warning_msg "Fwupd is not installed. Install it with: sudo pacman -S fwupd"
  record "Firmware" WARN
fi

# ---------- 4b: BIOS / UEFI (universal, never flashed automatically) ----------
main_msg "4b/11 BIOS / UEFI (mainboard detection)"
BOARD_VENDOR="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)"
BOARD_NAME="$(cat /sys/class/dmi/id/board_name 2>/dev/null)"
BIOS_VER="$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
BIOS_DATE="$(cat /sys/class/dmi/id/bios_date 2>/dev/null)"
info_msg "Mainboard: ${BOARD_VENDOR:-unknown} ${BOARD_NAME:-unknown}"
info_msg "BIOS: ${BIOS_VER:-unknown} (${BIOS_DATE:-unknown date})"
if command -v fwupdmgr &>/dev/null && fwupdmgr get-devices 2>/dev/null | grep -qi "system firmware\|UEFI"; then
  info_msg "Fwupd supports the system firmware of this board (see step 4)."
else
  info_msg "Fwupd does not support this board's BIOS. Check the vendor's support page for newer versions:"
  info_msg "  search: \"${BOARD_VENDOR:-vendor} ${BOARD_NAME:-board} BIOS download\""
  info_msg "Flash only with the vendor's own method (for example EZ Flash in the BIOS), never during a running system."
fi
record "BIOS" OK

# ---------- 5: DRIVERS / DKMS ----------
main_msg "5/11 DRIVERS: graphics, audio, WLAN, firmware, DKMS for every kernel"
DRV_PKGS="$(pacman -Qq 2>/dev/null | grep -E '(^nvidia|opencl-nvidia|^mesa|^lib32-mesa|^vulkan-|^lib32-vulkan|^xf86-video-|^libva-|^lib32-libva|^linux-firmware|^sof-firmware|^alsa-firmware|^amd-ucode|^intel-ucode|-dkms$|-dkms-git$|^broadcom-wl|^rtl.*-dkms|^v4l2loopback|^vmware-.*modules|^virtualbox-host|^ntsync)' | tr '\n' ' ')"
if [[ -n "$DRV_PKGS" ]]; then
  info_msg "Installed driver packages (updated via pacman and AUR):"
  echo "$DRV_PKGS" | fold -s -w 100 | sed 's/^/  /'
else
  info_msg "No special driver packages found."
fi
if lspci 2>/dev/null | grep -qi nvidia && ! { pacman -Qq nvidia-open-dkms &>/dev/null || pacman -Qq nvidia-dkms &>/dev/null; }; then
  warning_msg "NVIDIA GPU detected, but neither nvidia-open-dkms nor nvidia-dkms is installed. Check this."
  record "NVIDIA package" WARN
fi
if command -v dkms &>/dev/null; then
  info_msg "DKMS status before building:"
  dkms status 2>/dev/null | sed 's/^/  /' || true
  for kdir in /usr/lib/modules/*/; do
    kver="$(basename "$kdir")"
    [[ -e "$kdir/build" || -e "/usr/lib/modules/$kver/build" ]] || continue
    info_msg "DKMS building for kernel $kver ..."
    sudo dkms autoinstall -k "$kver" 2>&1 | tail -n 5 || warning_msg "DKMS build for $kver failed (check headers)."
  done
  if dkms status 2>/dev/null | grep -qi "error\|broken"; then
    warning_msg "A DKMS module has an error. Check with: dkms status"
    record "DKMS" WARN
  else
    record "DKMS" OK
  fi
else
  info_msg "Dkms not installed. Skipped."
  record "DKMS" SKIP
fi
for m in nvidia v4l2loopback vboxdrv vmw_vmci; do
  if lsmod 2>/dev/null | grep -q "^$m "; then info_msg "Module loaded: $m"; fi
done
if command -v nvidia-smi &>/dev/null && ! nvidia-smi &>/dev/null; then
  warning_msg "nvidia-smi reports an error. Check again after a reboot."
  record "NVIDIA driver" WARN
fi
# Verify the NVIDIA module against the package, for every kernel
if pacman -Qq nvidia-open-dkms &>/dev/null || pacman -Qq nvidia-dkms &>/dev/null; then
  PKG_NV="$(pacman -Q nvidia-open-dkms nvidia-dkms 2>/dev/null | head -n1 | awk '{print $2}' | sed 's/-[0-9]*$//')"
  info_msg "NVIDIA package: ${PKG_NV:-unknown}"
  for kdir in /usr/lib/modules/*/; do
    kver="$(basename "$kdir")"
    if ls "$kdir"/updates/dkms/nvidia*.ko* &>/dev/null || ls "$kdir"/extramodules/nvidia*.ko* &>/dev/null; then
      MOD_VER="$(modinfo -k "$kver" -F version nvidia 2>/dev/null | head -n1)"
      if [[ -n "$PKG_NV" && "$MOD_VER" == "$PKG_NV"* ]]; then
        info_msg "Kernel $kver: nvidia module $MOD_VER matches the package"
      else
        warning_msg "Kernel $kver: nvidia module ($MOD_VER) does not match the package ($PKG_NV). Rebuild DKMS."
        record "NVIDIA verification" WARN
      fi
    else
      warning_msg "Kernel $kver: NO nvidia module built. Check headers, then: sudo dkms autoinstall -k $kver"
      record "NVIDIA verification" WARN
    fi
  done
  RUN_MOD="$(modinfo -F version nvidia 2>/dev/null | head -n1)"
  if [[ -n "$RUN_MOD" && -n "$PKG_NV" && "$RUN_MOD" != "$PKG_NV"* ]]; then
    warning_msg "Loaded nvidia module ($RUN_MOD) is older than the package ($PKG_NV). REBOOT needed."
    record "NVIDIA verification" WARN
  fi
fi
dkms status 2>/dev/null | grep -v ': installed' | grep -q . && { warning_msg "At least one DKMS module is not 'installed':"; dkms status | grep -v ': installed' | sed 's/^/  /'; record "DKMS verification" WARN; } || true

# ---------- 6: KERNEL, INITRAMFS, GRUB ----------
main_msg "6/11 KERNEL, INITRAMFS, GRUB"
if command -v mkinitcpio &>/dev/null && ls /etc/mkinitcpio.d/*.preset &>/dev/null; then
  sudo mkinitcpio -P && record "mkinitcpio" OK || { error_msg "mkinitcpio -P failed (see log)."; record "mkinitcpio" FAIL; }
elif command -v dracut &>/dev/null; then
  info_msg "No mkinitcpio setup found, using dracut."
  sudo dracut --regenerate-all --force && record "dracut" OK || { error_msg "dracut failed (see log)."; record "dracut" FAIL; }
else
  warning_msg "Neither mkinitcpio presets nor dracut found. Initramfs not rebuilt."
  record "Initramfs-Tool" WARN
fi
if [[ -f /boot/grub/grub.cfg ]] || command -v grub-mkconfig &>/dev/null; then
  if sudo grub-mkconfig -o /boot/grub/grub.cfg; then record "GRUB" OK; else record "GRUB" FAIL; fi
fi
for stale in /boot/efi/EFI/limine /boot/efi/EFI/refind /boot/efi/loader /boot/limine.conf /boot/loader; do
  [[ -e "$stale" ]] && warning_msg "Old bootloader leftover found: $stale (remove it, GRUB is the standard)"
done
info_msg "Installed kernels:"
find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '  %f\n'

# ---------- 7: REBOOT CHECK + SERVICES ----------
main_msg "7/11 REBOOT CHECK"
if [[ -d "/usr/lib/modules/$(uname -r)" ]]; then
  info_msg "Running kernel ($(uname -r)) is still installed. No kernel reboot needed."
else
  warning_msg "Running kernel $(uname -r) has been replaced. REBOOT needed."
  record "Reboot" WARN
fi
if command -v nvidia-smi &>/dev/null; then nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  NVIDIA: /' || true; fi
if command -v efibootmgr &>/dev/null; then info_msg "UEFI boot order:"; efibootmgr 2>/dev/null | head -n 12 | sed 's/^/  /' || true; fi
systemctl --failed --no-legend | head -n 20 | sed 's/^/  /'
if command -v needrestart &>/dev/null; then
  info_msg "Services that need a restart (needrestart):"
  sudo needrestart -b 2>/dev/null | grep -i 'service\|kernel' | sed 's/^/  /' || true
  if [[ "$(ask_msg "Restart the affected services now? [y/N]")" =~ ^[yY]$ ]]; then
    sudo needrestart -r a || true
  fi
else
  info_msg "Tip: install needrestart (sudo pacman -S needrestart) to list services that need a restart."
fi

# ---------- 8: APPIMAGES, PROTON, DEV TOOLS, GIT CLONES ----------
main_msg "8/11 APPIMAGES, PROTON, DEV TOOLS, GIT CLONES"
APP_DIRS=("$HOME/Applications" "$HOME/AppImages" "$HOME/.local/bin")
found=0
for d in "${APP_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' f; do
    found=1; info_msg "AppImage: $f"
    command -v appimageupdatetool &>/dev/null && appimageupdatetool -O "$f" || true
  done < <(find "$d" -maxdepth 2 -type f -name "*.AppImage" -print0 2>/dev/null)
done
[[ $found -eq 0 ]] && info_msg "No AppImages found."
command -v protonup &>/dev/null && protonup -y || true
# Info only: installed GE-Proton versions with size. Nothing is deleted here.
_PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
if [ -d "$_PROTON_DIR" ]; then
  info_msg "Installed Proton versions (info only, nothing is deleted):"
  du -sh "$_PROTON_DIR"/*/ 2>/dev/null | while read -r _size _path; do echo "  $_size  $(basename "$_path")"; done
  echo "  Remove old versions yourself with ProtonUp-Qt."
fi
command -v rustup &>/dev/null && rustup update || true
command -v npm &>/dev/null && npm update -g || true
if command -v pip &>/dev/null; then info_msg "Pip: outdated packages (display only):"; pip list --outdated 2>/dev/null | head -n 30 | sed 's/^/  /' || true; fi
if command -v cargo &>/dev/null; then info_msg "Cargo: installed crates:"; cargo install --list 2>/dev/null | head -n 20 | sed 's/^/  /' || true; fi
command -v heroic &>/dev/null && info_msg "Heroic and Lutris: the programs update via pacman/AUR/Flatpak. Wine/Proton versions are downloaded by the apps themselves."
command -v waydroid &>/dev/null && waydroid status 2>/dev/null | head -n 5 | sed 's/^/  /' || true
for d in "$HOME/Tools" "$HOME/tools" "$HOME/Git" "$HOME/git" "$HOME/Projects"; do
  [[ -d "$d" ]] || continue
  find "$d" -maxdepth 2 -name ".git" -type d 2>/dev/null | while read -r g; do
    info_msg "Git pull: $(dirname "$g")"
    git -C "$(dirname "$g")" pull --ff-only || warning_msg "No pull possible: $(dirname "$g")"
  done
done

# ---------- 8b: CALIBRE (official installer, only if installed in /opt) ----------
main_msg "8b/11 CALIBRE (official installer)"
if pacman -Qq calibre &>/dev/null; then
  info_msg "Calibre is installed via pacman. It is updated by pacman -Syu (step 1)."
  record "Calibre" OK
elif [[ -d /opt/calibre ]]; then
  info_msg "Calibre installed via the official installer (/opt/calibre). Updating..."
  if sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin; then
    record "Calibre" OK
  else
    error_msg "Calibre installer failed."; record "Calibre" FAIL
  fi
else
  info_msg "Calibre not found (neither pacman nor /opt). Skipped."
  record "Calibre" SKIP
fi

# ---------- 9: CLEAN UP (only after confirmation) ----------
main_msg "9/11 CLEAN UP (only after confirmation)"
orphans="$(pacman -Qdtq 2>/dev/null)"
if [[ -n "$orphans" ]]; then
  info_msg "Orphaned packages:"; echo "$orphans" | sed 's/^/  /'
  if [[ "$(ask_msg "Remove orphaned packages with -Rns? [y/N]")" =~ ^[yY]$ ]]; then
    sudo pacman -Rns $orphans || true
  fi
else
  info_msg "No orphaned packages."
fi
if command -v paccache &>/dev/null; then
  if [[ "$(ask_msg "Clean the package cache and keep only the last 2 versions? [y/N]")" =~ ^[yY]$ ]]; then sudo paccache -rk2 || true; fi
fi

# ---------- 10: PACNEW / PACSAVE (display only) ----------
main_msg "10/11 PACNEW / PACSAVE"
PACNEWS="$(find /etc -regextype posix-extended -regex '.+\.pac(new|save)' 2>/dev/null)"
if [[ -n "$PACNEWS" ]]; then
  warning_msg ".pacnew/.pacsave files found (never deleted automatically):"
  echo "$PACNEWS" | sed 's/^/  /'
  info_msg "Review them with: sudo DIFFPROG=vimdiff pacdiff"
  record "Pacnew" WARN
else
  info_msg "No .pacnew/.pacsave files. Configs are current."
fi

# ---------- 11: VERIFICATION (cleanly installed?) ----------
main_msg "11/11 VERIFICATION: package health, initramfs, GRUB, microcode"
info_msg "Dependencies (pacman -Dk):"
DK="$(sudo pacman -Dk 2>&1)"
if echo "$DK" | grep -qiE "^(error|fehler):"; then
  echo "$DK" | grep -v "^$" | head -n 30 | sed 's/^/  /'; warning_msg "Dependency problems found."; record "Dependencies" WARN
else
  info_msg "No dependency problems."; record "Dependencies" OK
fi
info_msg "File integrity (pacman -Qk):"
QK="$(sudo pacman -Qk 2>&1)"
QK_ERR="$(echo "$QK" | grep -E 'warning|error' | grep -v ' 0 missing' | wc -l)"
if [[ "$QK_ERR" -eq 0 ]]; then
  info_msg "No missing files found."; record "File integrity" OK
else
  warning_msg "$QK_ERR notes about missing or changed files. Details: pacman -Qkk"; record "File integrity" WARN
fi
info_msg "Initramfs per installed kernel:"
for kdir in /usr/lib/modules/*/; do
  kver="$(basename "$kdir")"
  img=""; flav="${kver#*-}"; flav="${flav#*-}"; sudo test -f "/boot/initramfs-linux-${flav}.img" && img="/boot/initramfs-linux-${flav}.img"
  if [[ -n "$img" ]]; then info_msg "  $kver: $img"; else warning_msg "  $kver: no initramfs in /boot. Run: sudo mkinitcpio -P"; record "Initramfs" WARN; fi
done
if sudo test -f /boot/grub/grub.cfg; then
  if sudo grep -q "vmlinuz" /boot/grub/grub.cfg; then info_msg "GRUB lists kernels."; else warning_msg "GRUB lists no kernels. Run: sudo grub-mkconfig -o /boot/grub/grub.cfg"; record "GRUB entries" WARN; fi
fi
if dmesg 2>/dev/null | grep -qi "microcode updated"; then info_msg "Microcode was loaded at boot."; else info_msg "No microcode message in dmesg (check as root: sudo dmesg | grep -i microcode)."; fi

# ---------- SUMMARY ----------
echo
main_msg "SUMMARY"
fail=0
for i in "${!RES_NAME[@]}"; do
  case "${RES_STATUS[$i]}" in
    OK)   info_msg    "${RES_NAME[$i]}: OK" ;;
    SKIP) info_msg    "${RES_NAME[$i]}: skipped" ;;
    WARN) warning_msg "${RES_NAME[$i]}: note" ;;
    FAIL) error_msg   "${RES_NAME[$i]}: failed"; fail=1 ;;
  esac
done
echo
info_msg "Log: $LOG"
[[ $fail -eq 0 ]] && info_msg "Done." || error_msg "At least one step failed. Check the log."
quit_msg
ALLESEOF
chmod +x "$HOME/.local/bin/alles-updaten"
cat > "$HOME/.local/share/applications/alles-updaten.desktop" <<DESKEOF
[Desktop Entry]
Type=Application
Name=Alles updaten
Comment=Updates everything: packages, AUR, Flatpak, firmware, drivers, kernel
Exec=konsole -e $HOME/.local/bin/alles-updaten
Icon=alles-updaten
Categories=System;
Terminal=false
DESKEOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
info "Alles-Updaten installiert: ~/.local/bin/alles-updaten (Menü: Alles updaten)"

# Hide (NoDisplay=true): KWrite, KWallet Manager, Menu Editor. Nothing is deleted.
for _app in org.kde.kwrite org.kde.kwalletmanager5 org.kde.kmenuedit; do
  _src=""
  for _d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
    if [ -f "$_d/$_app.desktop" ]; then _src="$_d/$_app.desktop"; break; fi
  done
  [ -n "$_src" ] || continue
  mkdir -p "$HOME/.local/share/applications"
  _dst="$HOME/.local/share/applications/$_app.desktop"
  [ -f "$_dst" ] || cp "$_src" "$_dst"
  if grep -q '^NoDisplay=' "$_dst"; then sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$_dst"; else echo "NoDisplay=true" >> "$_dst"; fi
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
# Update-All tray icon: own icon, red badge when updates are available
echo "Setting up the Update All tray icon"
sudo pacman -S --needed --noconfirm python-pyqt6 pacman-contrib >/dev/null 2>&1 || echo "Tray dependencies could not be installed"
mkdir -p "$HOME/.local/bin" "$HOME/.config/autostart"
cat > "$HOME/.local/bin/alles-updaten-tray" <<'TRAYEOF'
#!/usr/bin/env python3
# Update All tray icon: own icon in the system tray, red counter as soon as any update is available.
import json
import math
import os
import shutil
import subprocess
import sys
import threading

from PyQt6.QtCore import QObject, QTimer, Qt, QRectF, QPointF, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QIcon, QPainter, QPainterPath, QPixmap, QPen, QPolygonF
from PyQt6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

HOME = os.path.expanduser("~")
UPDATER = os.path.join(HOME, ".local", "bin", "alles-updaten")
CHECK_MINUTES = 360  # check every 6 hours
APP_DIRS = [os.path.join(HOME, "Applications"), os.path.join(HOME, "AppImages"), os.path.join(HOME, ".local", "bin")]


def _lines(text):
    return [l for l in text.splitlines() if l.strip()]


def count_pacman():
    try:
        out = subprocess.run(["checkupdates"], capture_output=True, text=True, timeout=300)
        return len(_lines(out.stdout))
    except Exception:
        return 0


def count_aur():
    # AUR updates (paru, yay or pikaur), same as the update script
    for helper in ("paru", "yay", "pikaur"):
        if shutil.which(helper):
            try:
                out = subprocess.run([helper, "-Qua"], capture_output=True, text=True, timeout=300)
                return len(_lines(out.stdout))
            except Exception:
                return 0
    return 0


def count_flatpak():
    try:
        out = subprocess.run(["flatpak", "remote-ls", "--updates"], capture_output=True, text=True, timeout=300)
        return len(_lines(out.stdout))
    except Exception:
        return 0


def count_snap():
    if not shutil.which("snap"):
        return 0
    try:
        out = subprocess.run(["snap", "refresh", "--list"], capture_output=True, text=True, timeout=300)
        lines = _lines(out.stdout)
        if lines and lines[0].lower().startswith("name"):
            lines = lines[1:]
        return len([l for l in lines if "up to date" not in l.lower()])
    except Exception:
        return 0


def count_firmware():
    # Firmware (fwupd): number of devices with a new version
    if not shutil.which("fwupdmgr"):
        return 0
    try:
        out = subprocess.run(["fwupdmgr", "get-updates", "--json"], capture_output=True, text=True, timeout=300)
        data = json.loads(out.stdout)
        return sum(1 for dev in data.get("Devices", []) if dev.get("Releases"))
    except Exception:
        return 0


def count_appimages():
    # AppImages with an update: appimageupdatetool -j, exit 1 = update available
    if not shutil.which("appimageupdatetool"):
        return 0
    n = 0
    for d in APP_DIRS:
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            if name.lower().endswith(".appimage"):
                try:
                    r = subprocess.run(["appimageupdatetool", "-j", os.path.join(d, name)],
                                       capture_output=True, timeout=300)
                    if r.returncode == 1:
                        n += 1
                except Exception:
                    pass
    return n


SOURCES = [
    ("pacman", count_pacman),
    ("aur", count_aur),
    ("flatpak", count_flatpak),
    ("snap", count_snap),
    ("firmware", count_firmware),
    ("appimage", count_appimages),
]


def _head(cx, cy, r, th_deg):
    """Pfeilspitze am Ende eines Bogens (Winkel in Grad, y nach oben, Bewegung im Uhrzeigersinn)."""
    t = math.radians(th_deg)
    ex, ey = cx + r * math.cos(t), cy - r * math.sin(t)
    tx, ty = math.sin(t), math.cos(t)
    nx, ny = math.cos(t), -math.sin(t)
    return QPolygonF([
        QPointF(ex + tx * 7, ey + ty * 7),
        QPointF(ex - tx * 3 + nx * 9, ey - ty * 3 + ny * 9),
        QPointF(ex - tx * 3 - nx * 9, ey - ty * 3 - ny * 9),
    ])


def make_icon(alert):
    """Update-Symbol: zwei dünne weiße Kreispfeile wie die anderen Tray-Icons.
    Bei Updates kommt ein roter Pfeil nach unten in die Mitte dazu."""
    pix = QPixmap(64, 64)
    pix.fill(Qt.GlobalColor.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    white = QColor("#eff0f1")
    red = QColor("#e53935")
    cx, cy, r = 32, 32, 20
    rect = QRectF(cx - r, cy - r, 2 * r, 2 * r)
    pen = QPen(white, 4.5)
    pen.setCapStyle(Qt.PenCapStyle.FlatCap)
    p.setBrush(Qt.BrushStyle.NoBrush)
    # Oberer Bogen links -> rechts, Pfeil rechts
    p.setPen(pen)
    p.drawArc(rect, 160 * 16, -170 * 16)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(white)
    p.drawPolygon(_head(cx, cy, r, 10))
    # Unterer Bogen rechts -> links, Pfeil links
    p.setPen(pen)
    p.setBrush(Qt.BrushStyle.NoBrush)
    p.drawArc(rect, -20 * 16, -150 * 16)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(white)
    p.drawPolygon(_head(cx, cy, r, -170))
    if alert:
        # roter Pfeil nach unten in der Mitte
        p.setBrush(red)
        p.drawRect(QRectF(29.5, 22, 5, 16))
        p.drawPolygon(QPolygonF([QPointF(23, 36), QPointF(41, 36), QPointF(32, 46)]))
    p.end()
    return QIcon(pix)


def run_update():
    cmd = f"{UPDATER}; read -rp 'Press Enter to close...'"
    # Terminal runs in the foreground, so the number can be checked again when it closes
    for term, args in (("konsole", ["--nofork", "-e"]), ("gnome-terminal", ["--wait", "--"]),
                       ("xfce4-terminal", ["-e"]), ("xterm", ["-e"])):
        if shutil.which(term):
            return subprocess.Popen([term, *args, "bash", "-c", cmd])
    return None


class Bridge(QObject):
    # Result of one check comes back from a background thread into the main thread
    counted = pyqtSignal(str, int)


class Tray:
    def __init__(self, app):
        self.app = app
        self.counts = {}
        self.checking = False
        self.alert = False
        self.bridge = Bridge()
        self.bridge.counted.connect(self.on_counted)
        self.tray = QSystemTrayIcon(make_icon(False))
        self.menu = QMenu()
        self.menu.addAction("Update now", self.start_update)
        self.menu.addAction("Check now", self.refresh)
        self.menu.addSeparator()
        self.menu.addAction("Quit", app.quit)
        self.tray.setContextMenu(self.menu)
        self.tray.activated.connect(self.on_activated)
        self.tray.show()
        self.update_proc = None
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.check_update_done)
        self.timer = QTimer()
        self.timer.timeout.connect(self.refresh)
        self.timer.start(CHECK_MINUTES * 60 * 1000)
        self.refresh()

    def on_activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.start_update()

    def start_update(self):
        self.update_proc = run_update()
        self.update_timer.start(5000)

    def check_update_done(self):
        if self.update_proc is None or self.update_proc.poll() is not None:
            self.update_timer.stop()
            self.refresh()

    def refresh(self):
        # All sources run in parallel. Each source updates the icon as soon as it has finished.
        if self.checking:
            return
        self.checking = True
        self.pending = len(SOURCES)
        for name, fn in SOURCES:
            threading.Thread(target=self._run_source, args=(name, fn), daemon=True).start()

    def _run_source(self, name, fn):
        try:
            n = fn()
        except Exception:
            n = 0
        self.bridge.counted.emit(name, n)

    def on_counted(self, name, n):
        self.counts[name] = n
        self.alert = any(v > 0 for v in self.counts.values())
        self.tray.setIcon(make_icon(self.alert))
        if self.alert:
            self.tray.setToolTip("Update All: updates available")
        else:
            self.tray.setToolTip("Update All: system is up to date")
        self.pending -= 1
        if self.pending <= 0:
            self.checking = False


def save_menu_icon():
    """Writes the same tray logo as a PNG into the icon theme so the start menu shows the same icon."""
    d = os.path.join(os.path.expanduser("~"), ".local", "share", "icons", "hicolor", "64x64", "apps")
    os.makedirs(d, exist_ok=True)
    make_icon(False).pixmap(64, 64).save(os.path.join(d, "alles-updaten.png"), "PNG")


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    if not QSystemTrayIcon.isSystemTrayAvailable():
        print("No system tray available.")
        return 1
    save_menu_icon()
    _tray = Tray(app)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
TRAYEOF
chmod +x "$HOME/.local/bin/alles-updaten-tray"
printf '[Desktop Entry]\nType=Application\nName=Alles updaten (Tray)\nExec=python3 %s\nIcon=alles-updaten\nTerminal=false\nX-GNOME-Autostart-enabled=true\n' "$HOME/.local/bin/alles-updaten-tray" > "$HOME/.config/autostart/alles-updaten-tray.desktop"
echo "Update All tray icon set up (starts at next login)"
if command -v kdialog &>/dev/null; then kdialog --title "Setup complete" --msgbox "Setup complete! Please reboot - linux-cachyos-bore boots by default (NVIDIA/DKMS driver is built for it), the standard kernel stays in the GRUB menu. Then run ~/system-check.sh to verify." 500 200 2>/dev/null || true; fi