#!/usr/bin/bash
# Titanoboa hook-post-rootfs: runs inside the LIVE rootfs before it is squashed.
# Nothing here ends up on the installed system (the installer deploys the container image itself).
# Pattern follows Bluefin's configure_iso_anaconda.sh: install anaconda-live, put the installer in the
# dock, and ship an interactive kickstart that installs the OCI image (ostreecontainer) + bootc switch.
set -euxo pipefail

# Replaced by the workflow before the build (sed). Must look like ghcr.io/<owner>/precision-os:latest
IMAGE_REF="@IMAGE_REF@"
[[ $IMAGE_REF == ghcr.io/*/*:* ]] || { echo "IMAGE_REF was not rendered: '$IMAGE_REF'"; exit 1; }

# ---- 1. Installer packages ---------------------------------------------------------------
dnf install -y anaconda-live libblockdev-btrfs
dnf install -y libblockdev-lvm libblockdev-dm || true      # extra storage backends, non-fatal
dnf install -y anaconda-webui || true                       # only present on newer Fedora, non-fatal

# Fail the ISO build (not the end user) if no installer entry point exists.
command -v liveinst >/dev/null || command -v anaconda >/dev/null \
  || { echo "ERROR: anaconda-live installed no liveinst/anaconda binary"; exit 1; }

# ---- 2. 'Install PrecisionOS' launcher ---------------------------------------------------
install -Dm755 /dev/stdin /usr/libexec/precision-os/launch-installer <<'LAUNCH'
#!/usr/bin/bash
if command -v liveinst >/dev/null 2>&1; then exec liveinst "$@"; fi
if command -v anaconda >/dev/null 2>&1; then exec pkexec "$(command -v anaconda)" --liveinst "$@"; fi
notify-send "PrecisionOS" "No installer found in this live image." 2>/dev/null || true
exit 1
LAUNCH

install -Dm644 /dev/stdin /usr/share/applications/precision-install.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install PrecisionOS
Comment=Install PrecisionOS to this computer
Exec=/usr/libexec/precision-os/launch-installer
Icon=system-software-install
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP

# Live-session-only dconf layer (sorts after 00-precision-os so it wins): installer first in the dock.
install -Dm644 /dev/stdin /etc/dconf/db/local.d/10-precision-live <<'DCONF'
[org/gnome/shell]
favorite-apps=['precision-install.desktop','org.gnome.Nautilus.desktop','org.gnome.Ptyxis.desktop','org.mozilla.firefox.desktop']
DCONF
dconf update

# ---- 3. Interactive kickstart (Anaconda reads interactive-defaults.ks in the live environment) ----
install -d /usr/share/anaconda
cat > /usr/share/anaconda/interactive-defaults.ks <<'KS'
# PrecisionOS live installer: deploy the container image from the registry (network required).
ostreecontainer --url=@IMAGE@ --transport=registry

# Point the installed system's origin at the registry so `bootc upgrade` tracks it (same step Bazzite's hook uses).
%post --erroronfail --log=/var/roothome/precision-bootc-switch.log
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry @IMAGE@
%end

# Secure Boot: queue the ublue akmods key for enrollment (password: ublue-os). Non-fatal; the fallback is
# running `ujust enroll-secure-boot-key` after first boot.
%post --log=/var/roothome/precision-mok.log
for c in /etc/pki/akmods/certs/akmods-ublue.der /etc/pki/akmods/certs/public_key.der; do
  if [ -f "$c" ] && [ -d /sys/firmware/efi ]; then
    printf '%s\n%s\n' ublue-os ublue-os | mokutil --import "$c" || true
    break
  fi
done
%end
KS
sed -i "s|@IMAGE@|${IMAGE_REF}|g" /usr/share/anaconda/interactive-defaults.ks

# ---- 4. Make the live session quiet and safe ---------------------------------------------
# Don't let first-boot Flatpak install, auto-updates or fetch timers run inside the RAM-backed live session.
for u in precision-os-flatpaks.service ublue-update.timer rpm-ostreed-automatic.timer \
         bootc-fetch-apply-updates.timer flatpak-system-update.timer; do
  systemctl mask "$u" 2>/dev/null || true
done
