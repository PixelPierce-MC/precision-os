# PrecisionOS helpers

# Install/repair the baked-in Flatpaks (idempotent; use after a `bootc switch` or if one failed to install)
precision-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo /usr/libexec/precision-os/install-flatpaks
    echo "Done. Next: ujust precision-theme-apply"

# Copy libadwaita, OBS and Ptyxis theming into an EXISTING user profile (/etc/skel only covers new users)
precision-theme-apply:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.config/gtk-4.0
    [ -f ~/.config/gtk-4.0/gtk.css ] && cp ~/.config/gtk-4.0/gtk.css ~/.config/gtk-4.0/gtk.css.bak
    cp /etc/skel/.config/gtk-4.0/gtk.css ~/.config/gtk-4.0/gtk.css
    OBS=~/.var/app/com.obsproject.Studio/config/obs-studio/themes
    mkdir -p "$OBS" ~/.local/share/org.gnome.Ptyxis/palettes
    cp /etc/skel/.var/app/com.obsproject.Studio/config/obs-studio/themes/PrecisionOS.obt "$OBS"/
    cp /usr/share/precision-os/ptyxis/precision-os.palette ~/.local/share/org.gnome.Ptyxis/palettes/
    echo "Applied. Log out/in. OBS: Settings > Appearance > Theme > PrecisionOS."
