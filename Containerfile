FROM ghcr.io/ublue-os/bazzite-gnome-nvidia:stable

# Copy custom system files and build scripts
COPY system_files/ /
RUN /ctx/build.sh
