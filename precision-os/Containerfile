# PrecisionOS (precision-os): custom Bazzite, GNOME + NVIDIA proprietary drivers.
# "bazzite-nvidia" is the KDE image; the GNOME one is "bazzite-gnome-nvidia".
# RTX 30-series also works with "bazzite-gnome-nvidia-open" (change BASE_IMAGE).
ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-gnome-nvidia"
ARG BASE_TAG="latest"

FROM scratch AS ctx
COPY build_files /

FROM ${BASE_IMAGE}:${BASE_TAG}

# dconf defaults, skel theming, palettes, wallpaper, ujust recipes, Flatpak list
COPY system_files/ /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
