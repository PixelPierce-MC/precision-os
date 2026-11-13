#!/usr/bin/bash
set -euo pipefail

DCONF_FILE=/etc/dconf/db/local.d/00-precision-os

install_missing() {
    local missing=()
    for p in "$@"; do rpm -q "$p" &>/dev/null || missing+=("$p"); done
    if (( ${#missing[@]} )); then dnf -y install "${missing[@]}"; fi
}

validate_dconf() {
    local rc=0 section id xml dir tmp key
    while IFS= read -r section; do
        [[ $section == *Profiles* ]] && continue
        id=${section//\\//}
        xml=$(grep -rle "id=['\"]${id}['\"]" /usr/share/glib-2.0/schemas /usr/share/gnome-shell/extensions \
            --include='*.gschema.xml' 2>/dev/null | head -1 || true)
        [[ -z $xml ]] && echo "WARN: no schema found for $id (skipped)" && continue
        tmp=""
        if [[ $xml == /usr/share/glib-2.0/schemas/* ]]; then
            dir=/usr/share/glib-2.0/schemas
        else
            tmp=$(mktemp -d); cp "$xml" "$tmp"/
            glib-compile-schemas "$tmp" 2>/dev/null || { echo "WARN: cannot compile $xml (skipped)"; rm -rf "$tmp"; continue; }
        fi
    done
}
