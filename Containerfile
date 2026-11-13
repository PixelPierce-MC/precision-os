FROM ghcr.io/ublue-os/bazzite-gnome-nvidia:stable

# Copy build files and system configurations into the image root
COPY build_files/ /tmp/build_files/
COPY system_files/ /

# Run the build script
RUN /tmp/build_files/build.sh
