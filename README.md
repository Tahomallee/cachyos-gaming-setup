# CachyOS Gaming Setup

[<p align="center">
  <img src="what-it-does.png" alt="CachyOS Gaming Setup - Feature Matrix" width="800">
</p>](https://github.com/Tahomallee/cachyos-gaming-setup/tree/main)

**One script that turns a fresh CachyOS KDE install into a system that is updated, tidied up and set up the way most people want it, without doing it all by hand.**

After every fresh install I found myself doing the same things again: removing tools nobody uses, fixing the same small annoyances, setting up drivers, hiding menu entries I never open. This script does all of that in one go. It is long on purpose, because you should be able to see exactly what it does.

---

## Before you start

- A fresh **CachyOS KDE** install with **BTRFS** on `/`.
- **Make a backup.** The script removes packages and changes system settings.
- **Read the script first.** It is meant to be read, not run blindly.
- It has been tested on my own machines only. Your hardware may behave differently. If something breaks, open an issue and include the log.

---

## Install

```bash
git clone https://github.com/Tahomallee/cachyos-gaming-setup
cd cachyos-gaming-setup
less CachyOS-Setup-Public.sh        # read it first
./CachyOS-Setup-Public.sh
```

The script asks for your `sudo` password once. It writes two logs to `~/cachyos-logs/`:

- `install_<date>.log`: everything that happened
- `errors_<date>.log`: only the errors

Plan for a while. The first run takes a good while, depending on your internet and the packages. When it is done, reboot.

---

## What it does

The script runs in phases. Each phase is logged and explains itself on screen.

1. **System check.** Checks the BTRFS root, internet, keyring and mirrors. It stops early if something essential is missing.
2. **Update.** A full `pacman` update, with a clean abort on errors.
3. **Cleanup.** Removes unneeded packages with `pacman -Rns` only. Nothing is forced with `-Rdd`. It asks before removing anything that is not clearly unused.
4. **Base.** Flatpak with Flathub, the basic tools, and a few small helper commands.
5. **Apps.** A curated set of applications: browser, office, media, a few gaming launchers and tools. Brave is set up with a fixed set of extensions and with its own policies.
6. **Tweaks.** Sensible system settings for gaming and everyday use.
7. **Verify.** A check at the end that the important parts are in place.
8. **Bootloader and reboot.** Rebuilds the boot setup and tells you when a reboot is needed.
9. **Final update.** One more update pass at the end, including Flatpak.

### Highlights

- **Drivers by hardware.** The script checks your GPU, CPU and other hardware and installs only what matches. NVIDIA drivers are built with DKMS for every installed CachyOS kernel.
- **Firmware is shown, not forced.** Firmware updates are listed. Installing them requires your confirmation.
- **BIOS is never flashed automatically.** The script only checks the BIOS version and explains how to update it manually.
- **No blanket Flatpak permissions.** Apps get access to their folders (Downloads, Documents, Pictures, Music, Videos), the GPU, the network and the portals. Game launchers also get your home folder, because they store games there.
- **Menu cleanup.** A few tools that most people never open are hidden from the application menu. They still work from the terminal.
- **Welcome screen off.** The CachyOS welcome screen does not start automatically.
- **Tray icon for updates.** `alles-updaten` is installed as a command. A small tray icon shows whether updates are waiting, in white when your system is up to date and red when something needs updating. Clicking it starts the update.
- **Logs everywhere.** Each step writes to a log, so you can see afterwards what changed.

---

## Helper commands after installation

Installed to `~/.local/bin`, so they work right away in a new terminal:

- `alles-updaten`: updates everything (system, AUR, Flatpak, firmware, AppImages)
- `task-kill`: kills a program. Type a name, or run it without one and click the window you want to close (works on Wayland and X11)
- `alles-updaten-tray`: the tray icon, started automatically after login

---

## Uninstall and rollback

There is no one-click uninstall. If you want to go back:

- Reinstall CachyOS, or restore your BTRFS snapshot made before the run.
- Remove the tray icon with `pkill -f alles-updaten-tray` and delete `~/.config/autostart/alles-updaten-tray.desktop`.

---

## Contributing

Bug reports and suggestions are welcome. Please include your hardware, the relevant log file and what you expected to happen. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License and disclaimer

Released under the MIT license, see [LICENSE](LICENSE).

This project is not affiliated with CachyOS or Arch Linux. It is provided as is, without warranty. You run it at your own risk.
