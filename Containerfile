ARG FEDORA_VERSION=44
ARG KERNEL_FLAVOR=ogc
ARG KERNEL_VERSION=7.0.9-ogc3.2.fc${FEDORA_VERSION}.x86_64
ARG NVIDIA_FLAVOR=nvidia-open

# ─── STAGES: uBlue's pre-built kernel + drivers ───
FROM ghcr.io/ublue-os/akmods:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods
FROM ghcr.io/ublue-os/akmods-extra:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods-extra
FROM ghcr.io/ublue-os/akmods-${NVIDIA_FLAVOR}:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods-nvidia
FROM ghcr.io/ublue-os/brew:latest AS brew

# ─── FINAL BASE ───
FROM ghcr.io/ublue-os/kinoite-main:${FEDORA_VERSION}

ARG FEDORA_VERSION=44
ARG NVIDIA_FLAVOR=nvidia-open

# ─── 1. OGC KERNEL ───
COPY --from=akmods /kernel-rpms /tmp/akmods/kernel-rpms
COPY --from=akmods /rpms/common /tmp/akmods/rpms/common
COPY --from=akmods /rpms/kmods /tmp/akmods/rpms/kmods
COPY --from=akmods-extra /rpms/extra /tmp/akmods-extra/rpms/extra
COPY --from=akmods-extra /rpms/kmods /tmp/akmods-extra/rpms/kmods

RUN dnf5 -y install --allowerasing \
    /tmp/akmods/kernel-rpms/*.rpm \
    /tmp/akmods/rpms/common/*.rpm \
    /tmp/akmods/rpms/kmods/*.rpm \
    /tmp/akmods-extra/rpms/extra/*.rpm \
    /tmp/akmods-extra/rpms/kmods/*.rpm \
    && dnf5 clean all

# ─── 2. NVIDIA DRIVERS ───
COPY --from=akmods-nvidia /rpms /tmp/rpms/nvidia

RUN dnf5 -y install \
    egl-wayland.x86_64 egl-wayland.i686 \
    egl-wayland2.x86_64 egl-wayland2.i686 \
    && dnf5 clean all

RUN IMAGE_NAME="SKIP_PACKAGE_INSTALL" \
    AKMODNV_PATH="/tmp/rpms/nvidia" \
    MULTILIB=1 \
    /tmp/rpms/nvidia/ublue-os/nvidia-install.sh \
    && dnf5 clean all

RUN dnf5 -y copr enable ublue-os/bazzite && \
    dnf5 -y copr enable ublue-os/bazzite-multilib && \
    dnf5 -y install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release && \
    dnf5 -y config-manager setopt "terra-mesa".enabled=false && \
    # Swap to Valve's patched versions
    dnf5 -y swap --from-repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite \
    wireplumber wireplumber && \
    dnf5 -y swap --from-repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib \
    bluez bluez && \
    dnf5 -y swap --from-repo=copr:copr.fedorainfracloud.org:ublue-os:bazzite-multilib \
    xorg-x11-server-Xwayland xorg-x11-server-Xwayland && \
    dnf5 -y swap --from-repo=terra-mesa \
    mesa-filesystem mesa-filesystem && \
    # Lock them so Fedora updates don't overwrite Valve's patches
    dnf5 versionlock add \
    wireplumber wireplumber-libs \
    bluez bluez-cups bluez-libs bluez-obexd \
    xorg-x11-server-Xwayland \
    mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm mesa-vulkan-drivers && \
    # Better Bluetooth audio codec (free aptX implementation)
    dnf5 -y install libfreeaptx && \
    # H.264 codec for browsers/video calls (Fedora can't ship it directly)
    dnf5 -y install --enable-repo="*fedora-multimedia*" --allowerasing \
    openh264.x86_64 openh264.i686 && \
    # Clean up: disable repos so they don't pollute the final image
    dnf5 -y copr disable ublue-os/bazzite && \
    dnf5 -y copr disable ublue-os/bazzite-multilib && \
    dnf5 -y config-manager setopt terra.enabled=0 && \
    dnf5 clean all

# ─── 4. SCX SCHEDULERS (CachyOS COPR) ───
RUN dnf5 -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf5 -y install scx-scheds scx-tools && \
    dnf5 -y copr disable bieszczaders/kernel-cachyos-addons && \
    dnf5 clean all

# ─── 5. BETTER STEAM GAMING PERFORMANCES ───
RUN dnf5 -y install \
    gamemode \
    && dnf5 clean all

# ─── 6. SYSTEM TWEAKS ───
COPY system_files/ /

# Disable irqbalance (conflicts with scx_lavd per winterofhell guide)
RUN (systemctl disable irqbalance.service 2>/dev/null || true) && \
    systemctl enable scx_loader.service

# ─── 7. BOOTC LINT ───
RUN bootc container lint