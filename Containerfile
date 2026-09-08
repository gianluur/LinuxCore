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


# ─── 4. SCX SCHEDULERS (CachyOS COPR) ───
RUN dnf5 -y copr enable bieszczaders/kernel-cachyos-addons && \
    dnf5 -y install scx-scheds scx-tools && \
    dnf5 -y copr disable bieszczaders/kernel-cachyos-addons && \
    dnf5 clean all

# ─── 5. PERFORMANCE PACKAGES ───
RUN dnf5 -y install \
    cachyos-settings \
    gamemode \
    mangohud \
    vkBasalt \
    btop \
    bees \
    input-remapper \
    distrobox \
    && dnf5 clean all

# ─── 6. SYSTEM TWEAKS ───
COPY system_files/ /

# Disable irqbalance (conflicts with scx_lavd per winterofhell guide)
RUN systemctl disable irqbalance.service && \
    systemctl enable scx_loader.service

# ─── 7. BOOTC LINT ───
RUN bootc container lint