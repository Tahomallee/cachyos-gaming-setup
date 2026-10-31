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
