# PrecisionOS: Post-Boot Guide

## 0. Live ISO and the "Install PrecisionOS" launcher
Two ISO kinds, both built by `build-iso.yml`:

| | Installer ISO (`build-installer-iso`) | Live ISO (`build-live-iso`) |
|---|---|---|
| Boots to | Anaconda installer | PrecisionOS desktop (Mint-style), installer launcher first in the dock |
| Flatpaks | Baked in, installed onto the target disk | Downloaded on first boot of the installed system (`precision-os-flatpaks.service`) |
| Install source | Embedded payload | **Network**: the kickstart pulls `ghcr.io/<you>/precision-os:latest` |
| Status | Reliable | **Experimental**, test in a VM first |

**How the live installer hook works** (`iso_files/configure_iso_anaconda.sh`, run by Titanoboa's `hook-post-rootfs`):
1. Installs `anaconda-live` and `libblockdev-btrfs` (the same packages Bluefin's hook installs), and fails the ISO build if no `liveinst`/`anaconda` binary results.
2. Adds `Install PrecisionOS` (`precision-install.desktop`) and puts it first in the live session's dock via a live-only dconf layer (`10-precision-live`, not present on the installed system).
3. Writes `/usr/share/anaconda/interactive-defaults.ks`: `ostreecontainer` to deploy your image, then `bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry` in `%post` (mirrors Bazzite's hook), plus a non-fatal Secure Boot key import.
4. Masks the first-boot Flatpak service and update timers inside the live session only.

**Not verified (GitHub blocked me from reading Bluefin's actual script):** the hook is modeled on the confirmed structure of
Bluefin/Bazzite's pipelines. These details come from my knowledge of Anaconda and need a VM test: the
`interactive-defaults.ks` location, whether your Fedora release's `anaconda-live` ships `liveinst`, the akmods cert path used for MOK import, and
partitioning options (Bazzite documents automatic partitioning only for its live ISO; expect the same).
Branding inside Anaconda will still say Bazzite/Fedora.

**Test it before you flash it (QEMU, no NVIDIA in the VM, that's expected):**
```bash
qemu-img create -f qcow2 test.qcow2 60G
qemu-system-x86_64 -enable-kvm -cpu host -m 8G -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
  -cdrom precision-os-live.iso -drive file=test.qcow2,if=virtio
```
Check, in order: live desktop appears; dock shows *Install PrecisionOS*; installer launches; install completes; reboot into the installed disk; `rpm-ostree status` shows `ghcr.io/<you>/precision-os`.
If the installer won't start, run `/usr/libexec/precision-os/launch-installer` from a terminal in the live session and read the error.
After the first boot with internet, Flatpaks install automatically (watch with `systemctl status precision-os-flatpaks`).
Windows dual-boot: prefer the installer ISO, or install PrecisionOS onto a separate drive.

## 1. Install / dual-boot checklist
1. Windows: disable **Fast Startup**; suspend BitLocker or keep the recovery key.
2. Best: Windows and PrecisionOS on **separate physical drives**. Install Windows first; if Windows goes on second, unplug the Linux drive.
3. Secure Boot ON: on first boot choose **Enroll MOK**, password `ublue-os` (NVIDIA modules are signed with the ublue-os akmods key, inherited from the base image).
4. Fedora's GRUB stays intact. If Windows is missing from the menu: `ujust regenerate-grub`.
5. After install: `rpm-ostree status` (confirm it tracks your image). Flatpaks should already be present; if any are missing run `ujust precision-setup`, then `ujust precision-theme-apply` for existing users.
6. Spotify's Flatpak uses Flathub "extra-data" (the app binary downloads from Spotify), so it may not survive offline baking. `ujust precision-setup` fixes it online.

## 2. Verified settings reference (GNOME 46+)
**Ptyxis palette.** Palette files are INI files named `*.palette`; user location `~/.local/share/org.gnome.Ptyxis/palettes/`.
Selection is stored per profile as the palette's *display name*:
```
[org/gnome/Ptyxis]
profile-uuids=['<uuid>']
default-profile-uuid='<uuid>'
[org/gnome/Ptyxis/Profiles/<uuid>]
palette='PrecisionOS'
```
Profiles must be listed in `profile-uuids` or they don't appear. The image ships a fixed UUID. If a system-wide profile
ever fails to take on your build, pick *PrecisionOS* once under Preferences > Profile > Palette.
**Dash to Dock** keys used (confirmed against its published gschema): `dock-position`, `dock-fixed`, `intellihide`,
`extend-height`, `multi-monitor`, `transparency-mode` (`DEFAULT|FIXED|DYNAMIC`), `custom-background-color`, `background-color`,
`background-opacity`, `running-indicator-style`, `click-action`, `dash-max-icon-size`.
**Blur my Shell**: schemas are `.../blur-my-shell/{panel,dash-to-dock,overview,...}`. Recent versions are *pipeline-based*:
blur strength (sigma/brightness) is configured inside pipelines (default id `pipeline_default`), so the old per-component
`sigma`/`brightness` keys from my previous version were removed.
**Build-time guard:** `build.sh` checks every key in `00-precision-os` against the schemas actually installed in the image
and fails the build with the offending key name if an extension renames something. That is the authoritative check.
To capture a tuned look: tweak in prefs, then `dconf dump /org/gnome/shell/extensions/blur-my-shell/`.

## 3. DaVinci Resolve (davincibox, host CUDA/OpenCL)
Resolve is not layered into the image (not redistributable; RHEL-family libs). Host driver libs reach the container through CDI.
```bash
./DaVinci_Resolve_*_Linux.run --appimage-extract            # on the HOST, creates squashfs-root/
distrobox create -n davincibox -i ghcr.io/zelikos/davincibox:latest \
    --additional-flags "--device nvidia.com/gpu=all"
distrobox enter davincibox -- setup-davinci squashfs-root/AppRun distrobox
distrobox enter davincibox -- sudo dnf update
```
(`ujust install-resolve` wraps the same workflow.) Verify: `nvidia-ctk cdi list` (host), then inside the box `nvidia-smi` and
`clinfo | grep -i "device name"`. In Resolve: Preferences > Memory and GPU > **CUDA**. If the GPU isn't visible:
`sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`, recreate the container, reboot after driver updates.
VRAM: 12 GB (3060) / 8 GB (3060 Ti). Resolve Free on Linux has restricted codecs (e.g. AAC audio, some H.264/H.265);
transcode to DNxHR/ProRes/PCM or use Studio.

## 4. OBS Studio with NVENC (RTX 3060 / 3060 Ti = Ampere)
- Install: baked in (Flatpak). NVENC works through the Flatpak NVIDIA GL runtime that Bazzite keeps matched to the host driver.
- *Settings > Output > Output Mode: **Advanced***.
- Encoder: **NVIDIA NVENC H.264** (or HEVC). Prefer the non-"(FFmpeg)/(legacy)" entry; names differ slightly across OBS versions.
- **No AV1 hardware encode on 30-series** (needs RTX 40+). Use H.264 for streaming, HEVC for local recording.
- Streaming: CBR 6000 to 8000 kbps, keyframe interval 2 s, Preset **P5** (Slow/Good Quality), Tuning **High Quality**,
  Multipass **Two Passes (Quarter Resolution)**, Look-ahead **on**, Psycho Visual Tuning **on**, B-frames 2.
- Recording: rate control **CQP 18 to 22** (or CQ), same preset/tuning. Record to MKV, then *File > Remux Recordings* to MOV/MP4 for Resolve.
- Dual monitors: add one *Screen Capture (PipeWire)* source per monitor (the portal asks once).
- Check it's really NVENC: `nvidia-smi dmon -s u` while recording (the `enc` column should move).

### OBS theme ("CSS palette") injection
OBS 30+ themes are `.obt` files (QSS plus a `@OBSThemeVars` palette block). PrecisionOS ships `PrecisionOS.obt` in
`/etc/skel` (new users) and `ujust precision-theme-apply` copies it for existing users:
`~/.var/app/com.obsproject.Studio/config/obs-studio/themes/`. Select it in *Settings > Appearance > Theme*.
It `extends` Yami and overrides only palette variables (`--primary` = #D30000, backgrounds #0D0D0D/#1E1E1E).
If a color doesn't change, your OBS release uses different variable names: open the bundled Yami theme
(`flatpak run --command=sh com.obsproject.Studio -c 'ls /app/share/obs/themes'`) and rename the variables to match.

## 5. Dual-monitor layout (GNOME on Wayland)
- *Settings > Displays*: arrange to match your desk, set the **gaming monitor as Primary**. `workspaces-only-on-primary` keeps monitor 2 static across workspaces.
- Enable VRR only on the monitor that supports it (the experimental feature flag is on by default).
- Make the layout apply at the login screen:
  ```bash
  sudo cp ~/.config/monitors.xml /var/lib/gdm/.config/monitors.xml
  sudo chown gdm:gdm /var/lib/gdm/.config/monitors.xml
  ```
- Dock on both screens: `dconf write /org/gnome/shell/extensions/dash-to-dock/multi-monitor true` (default is primary only).
- Resolve: Workspace > Dual Screen > On, viewer/inspector on monitor 2. Games: borderless on the primary only.

## 6. Gaming notes
- Steam launch option: `gamemoderun mangohud %command%`. Flatpak games use the MangoHud Vulkan layer installed by the setup step.
- Proton-GE: ProtonUp-Qt (baked in), then select it per game in Steam > Properties > Compatibility.
- CS2 and Borderlands 2 run well. **Call of Duty online does not work on Linux** (Ricochet anti-cheat); check ProtonDB.
- 7900X3D (dual CCD): check game threads land on the V-Cache CCD. 5700X3D (single CCD): nothing to do.
