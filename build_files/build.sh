#!/usr/bin/bash
set -euo pipefail

DCONF_FILE=/etc/dconf/db/local.d/00-precision-os

install_missing() {   # only layer what the base image lacks
  local missing=()
  for p in "$@"; do rpm -q "$p" &>/dev/null || missing+=("$p"); done
  if ((${#missing[@]})); then dnf5 -y install "${missing[@]}"; fi
}

# Build-time validation: every key in our dconf file must exist in the installed schemas.
# This is what keeps extension key names honest across Blur my Shell / Dash to Dock releases.
validate_dconf() {
  local rc=0 section id xml dir tmp key
  while IFS= read -r section; do
    [[ $section == *Profiles* ]] && continue          # Ptyxis relocatable profile schema
    id=${section//\//.}
    xml=$(grep -rlE "id=['\"]${id}['\"]" /usr/share/glib-2.0/schemas /usr/share/gnome-shell/extensions \
          --include='*.gschema.xml' 2>/dev/null | head -1 || true)
    if [[ -z $xml ]]; then echo "WARN: no schema found for $id (skipped)"; continue; fi
    tmp=""
    if [[ $xml == /usr/share/glib-2.0/schemas/* ]]; then
      dir=/usr/share/glib-2.0/schemas
    else
      tmp=$(mktemp -d); cp "$xml" "$tmp"/
      glib-compile-schemas "$tmp" 2>/dev/null || { echo "WARN: cannot compile $xml (skipped)"; rm -rf "$tmp"; continue; }
      dir=$tmp
    fi
    mapfile -t valid < <(GSETTINGS_SCHEMA_DIR=$dir gsettings list-keys "$id")
    while IFS= read -r key; do
      printf '%s\n' "${valid[@]}" | grep -qx -- "$key" || { echo "ERROR: schema $id has no key '$key'"; rc=1; }
    done < <(awk -v s="[$section]" '$0==s{f=1;next} /^\[/{f=0} f && /=/{sub(/=.*/,""); print}' "$DCONF_FILE")
    [[ -n $tmp ]] && rm -rf "$tmp"
  done < <(grep -oP '^\[\K[^\]]+' "$DCONF_FILE")
  return $rc
}

# ---- 1. RPM layer ----------------------------------------------------------
install_missing \
  git sassc glib2-devel \
  gnome-shell-extension-dash-to-dock \
  gnome-shell-extension-blur-my-shell \
  gnome-shell-extension-user-theme \
  gnome-shell-extension-appindicator \
  rsms-inter-fonts jetbrains-mono-fonts-all \
  clinfo vulkan-tools
# DaVinci Resolve is intentionally NOT layered (davincibox, see POST-BOOT.md).

# ---- 2. macOS-style themes (pin tags/commits for reproducible builds) -------
WORK=$(mktemp -d); cd "$WORK"
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git
( cd WhiteSur-gtk-theme && ./install.sh -d /usr/share/themes -c Dark -t red -N glassy )
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git
( cd WhiteSur-icon-theme && ./install.sh -d /usr/share/icons -t red )
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git
( cd WhiteSur-cursors && ./install.sh )
cd /; rm -rf "$WORK"
for d in /usr/share/themes/WhiteSur-Dark-red /usr/share/icons/WhiteSur-red-dark; do
  [[ -d $d ]] || { echo "MISSING $d"; ls /usr/share/themes /usr/share/icons | grep -i whitesur; exit 1; }
done

# ---- 3. Ptyxis palette: install next to Ptyxis' own stock palettes ----------
PAL_DIR=$(rpm -ql ptyxis 2>/dev/null | grep '\.palette$' | head -1 | xargs -r dirname || true)
PAL_DIR=${PAL_DIR:-/usr/share/org.gnome.Ptyxis/palettes}
echo "Installing Ptyxis palette into $PAL_DIR"
install -Dm644 /usr/share/precision-os/ptyxis/precision-os.palette "$PAL_DIR/precision-os.palette"

# ---- 3b. First-boot Flatpak installer (works for ISO installs and plain `bootc switch`) ----
chmod +x /usr/libexec/precision-os/install-flatpaks
systemctl enable precision-os-flatpaks.service

# ---- 4. ujust recipes --------------------------------------------------------
echo 'import "/usr/share/ublue-os/just/60-precision.just"' >> /usr/share/ublue-os/justfile

# ---- 5. dconf: validate keys against installed schemas, then compile ---------
validate_dconf
dconf update
