#!/usr/bin/env bash
# ==============================================================================
# LINSI-OS · Fase 8 — "La Instalación": primera imagen booteable
# ------------------------------------------------------------------------------
# Arma, a partir del sysroot compilado en las fases 0-6, una imagen de disco
# GPT lista para grabar en un pendrive (Rufus en modo DD, Balena Etcher o
# `dd`) y arrancar por UEFI. No es todavía el instalador (Calamares queda para
# más adelante): es el sistema completo, escribible, corriendo desde el USB.
#
#   Partición 1  LINSI-ESP   FAT32  512 MiB  GRUB (EFI/BOOT/BOOTX64.EFI) + kernel
#   Partición 2  linsi-root  btrfs  8 GiB    el sistema (el resto del pendrive
#                                            queda sin usar: agrandarlo solo
#                                            necesita initramfs, ver fstab).
#
# Sin initramfs: todo lo necesario para llegar al disco raíz está compilado
# adentro del kernel (ver scripts/kernel-hardware.config) y el raíz se busca
# por PARTLABEL, que el kernel resuelve solo. Lo que pide firmware (amdgpu,
# iwlwifi) va como módulo y lo carga udev con el raíz ya montado.
#
# Secure Boot tiene que estar APAGADO: GRUB y el kernel no están firmados
# todavía (el enrolado de claves propio es trabajo pendiente de esta fase).
#
# Requiere haber corrido antes las fases 0-6 (sysroot completo) y:
#   scripts/build-kernel.sh all       (kernel + módulos en /usr/lib/modules)
#   scripts/build-comms.sh  all       (PAM, shadow, util-linux con login, kmod, systemd)
#   scripts/build-kde.sh    all       (escritorio, shared-mime-info, fuentes)
#
# Uso:
#   scripts/build-image.sh kbd        # teclado/fuentes de consola
#   scripts/build-image.sh tzdata     # zonas horarias
#   scripts/build-image.sh cacert     # certificados raíz (Mozilla)
#   scripts/build-image.sh firmware   # firmware de GPU/WiFi/red
#   scripts/build-image.sh rootfs     # arma el árbol del sistema (como root)
#   scripts/build-image.sh image      # genera out/linsi-os-AAAAMMDD.img
#   scripts/build-image.sh test       # lo arranca en QEMU y saca capturas
#   scripts/build-image.sh all        # todo lo anterior, en orden
# cada uno con su verify-<paso>.
#
# Contraseña de prueba: usuario "linsi" y root, contraseña "linsi" (se puede
# pisar con LINSI_IMAGE_PASSWORD=...). Es una imagen de PRUEBA: cambiarla con
# `passwd` apenas se entra.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/lfs/scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

log()  { printf '\n\033[1;36m[fase8]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[fase8][error]\033[0m %s\n' "$*" >&2; exit 1; }

IMAGE_DIR="${LFS_BUILD}/image"
STAGE="${IMAGE_DIR}/rootfs"
WORK="${IMAGE_DIR}/work"
OUT_DIR="${LFS}/out"

ESP_SIZE_MIB=512
ROOT_SIZE_MIB="${LINSI_ROOT_SIZE_MIB:-8192}"
ESP_LABEL="LINSI-ESP"
ROOT_PARTLABEL="linsi-root"
LIVE_USER="linsi"
LIVE_PASSWORD="${LINSI_IMAGE_PASSWORD:-linsi}"
IMAGE_DATE="$(date +%Y%m%d)"
IMAGE_NAME="linsi-os-${IMAGE_DATE}.img"

# Línea de comandos del kernel común a todas las entradas de GRUB. Sin
# "quiet" a propósito en esta primera imagen: si algo falla en hardware real,
# los mensajes de arranque son la única pista.
# systemd.gpt_auto=0: el generador de particiones GPT no puede identificar el
# disco raíz sin initramfs (mismo problema de /dev/root que growfs/repart,
# ver fstab en step_rootfs_etc) y fallaba en cada arranque; las particiones
# se montan por fstab.
KERNEL_CMDLINE="root=PARTLABEL=${ROOT_PARTLABEL} rootfstype=btrfs rw rootwait loglevel=4 systemd.gpt_auto=0"

require_toolchain() {
    command -v "${LFS_TGT}-gcc" >/dev/null 2>&1 \
        || die "no se encontró ${LFS_TGT}-gcc en el PATH. Corré primero: scripts/build-cross-toolchain.sh all"
}

fetch() {
    local url="$1" out="$2"
    if [[ -f "${out}" ]]; then
        log "ya descargado: ${out}"
        return 0
    fi
    log "descargando ${out}"
    wget -c -O "${out}.part" "${url}"
    mv "${out}.part" "${out}"
}

build_triplet() {
    "${LFS_BUILD}/binutils-${BINUTILS_VERSION}/config.guess"
}

# El rootfs final tiene que ser de root (setuid, /etc/shadow, /root...), y el
# sysroot se compiló entero como el usuario "linsi" del contenedor. El
# contenedor tiene sudo sin contraseña para ese usuario (Dockerfile); en
# podman rootless el root del contenedor es el usuario de Windows mapeado,
# así que esto no toca nada fuera de los volúmenes.
as_root() { sudo -n "$@"; }

# Corre un binario DEL PROPIO SISTEMA adentro del árbol armado (misma
# arquitectura que el contenedor): systemd-sysusers, useradd, systemctl,
# depmod, localedef, fc-cache... Así cada herramienta escribe exactamente lo
# que escribiría en el sistema real, sin reimplementarla acá.
in_root() { as_root /usr/sbin/chroot "${STAGE}" "$@"; }

# Escribe stdin en un archivo del árbol armado, con permisos.
put() {
    local f="$1" mode="$2"
    as_root mkdir -p "$(dirname "${STAGE}/${f}")"
    as_root tee "${STAGE}/${f}" >/dev/null
    as_root chmod "${mode}" "${STAGE}/${f}"
}

# ==============================================================================
# Paquetes del sistema base que sólo hacen falta para arrancar de verdad
# ==============================================================================

# kbd -- loadkeys/setfont + mapas de teclado y fuentes de consola. Sin esto
# systemd-vconsole-setup falla y la consola queda en teclado US; además
# systemd-firstboot frena el primer arranque preguntando el keymap si
# /etc/vconsole.conf no existe. vlock (pide PAM propio) queda afuera.
step_kbd() {
    require_toolchain
    log "kbd ${KBD_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${KBD_MIRROR}/kbd-${KBD_VERSION}.tar.xz" "kbd-${KBD_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/kbd-${KBD_VERSION}.tar.xz"

    local src="${LFS_BUILD}/kbd-${KBD_VERSION}"
    rm -rf "${src}"
    tar -xf "${LFS_SOURCES}/kbd-${KBD_VERSION}.tar.xz" -C "${LFS_BUILD}"
    cd "${src}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ./configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --datadir=/usr/share \
        --disable-vlock \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install

    log "kbd instalado en ${LFS_SYSROOT}/usr"
}
step_verify_kbd() {
    local p
    for p in usr/bin/loadkeys usr/bin/setfont; do
        [[ -x "${LFS_SYSROOT}/${p}" ]] || die "falta ${LFS_SYSROOT}/${p}"
        echo "  [OK] ${LFS_SYSROOT}/${p}"
    done
    p="$(find "${LFS_SYSROOT}/usr/share/keymaps" -name 'la-latin1.map*' -print -quit 2>/dev/null)"
    [[ -n "${p}" ]] || die "no está el mapa la-latin1 en ${LFS_SYSROOT}/usr/share/keymaps"
    echo "  [OK] ${p}"
    p="$(find "${LFS_SYSROOT}/usr/share/consolefonts" -name 'eurlatgr*' -print -quit 2>/dev/null)"
    [[ -n "${p}" ]] || die "no está la fuente de consola eurlatgr"
    echo "  [OK] ${p}"
}

# tzdata -- datos de IANA compilados con el zic del contenedor (Debian). El
# formato TZif no depende de la arquitectura ni de la versión de glibc. Se
# instalan también los .tab, que leen timedatectl y el KCM de fecha/hora
# para listar zonas.
step_tzdata() {
    log "tzdata ${TZDATA_VERSION}"
    cd "${LFS_SOURCES}"
    fetch "${TZDATA_MIRROR}/tzdata${TZDATA_VERSION}.tar.gz" "tzdata${TZDATA_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/tzdata${TZDATA_VERSION}.tar.gz"

    local tmp="${LFS_BUILD}/tzdata-${TZDATA_VERSION}"
    rm -rf "${tmp}"
    mkdir -p "${tmp}"
    tar -xf "${LFS_SOURCES}/tzdata${TZDATA_VERSION}.tar.gz" -C "${tmp}"

    local dst="${LFS_SYSROOT}/usr/share/zoneinfo"
    rm -rf "${dst}"
    mkdir -p "${dst}"
    (cd "${tmp}" && /usr/sbin/zic -d "${dst}" -b fat \
        africa antarctica asia australasia europe northamerica southamerica etcetera backward factory)
    # tzdata.zi no viene en el tarball de datos (lo genera el Makefile de
    # tzcode; error real "cannot stat tzdata.zi"): systemd lista las zonas
    # desde zone1970.tab cuando no está.
    install -m 0644 "${tmp}"/{zone.tab,zone1970.tab,iso3166.tab,leapseconds} "${dst}/"
    rm -rf "${tmp}"
    log "tzdata instalado en ${dst}"
}
step_verify_tzdata() {
    local z="${LFS_SYSROOT}/usr/share/zoneinfo/America/Argentina/Buenos_Aires"
    [[ -f "${z}" ]] || die "falta ${z}"
    head -c 4 "${z}" | grep -q TZif || die "${z} no es un archivo TZif"
    echo "  [OK] ${z} (TZif)"
}

# Certificados raíz de Mozilla (el bundle que publica curl.se). No había
# NINGUNO: systemd-resolved tiene DNS-over-TLS estricto (Fase 4) y valida el
# certificado del servidor DNS contra el almacén de OpenSSL, así que sin CA
# no resolvía ningún nombre -- sin internet. OPENSSLDIR es /etc/ssl
# (compilado en libcrypto): cert.pem es el archivo por defecto.
step_cacert() {
    log "certificados raíz de Mozilla (curl.se, ${CACERT_DATE})"
    cd "${LFS_SOURCES}"
    fetch "${CACERT_MIRROR}/cacert-${CACERT_DATE}.pem" "cacert-${CACERT_DATE}.pem"
    log_sha256 "${LFS_SOURCES}/cacert-${CACERT_DATE}.pem"

    install -D -m 0644 "${LFS_SOURCES}/cacert-${CACERT_DATE}.pem" \
        "${LFS_SYSROOT}/etc/ssl/certs/ca-certificates.crt"
    ln -sfn certs/ca-certificates.crt "${LFS_SYSROOT}/etc/ssl/cert.pem"
    log "bundle instalado en ${LFS_SYSROOT}/etc/ssl/certs/ca-certificates.crt"
}
step_verify_cacert() {
    local f="${LFS_SYSROOT}/etc/ssl/certs/ca-certificates.crt"
    [[ -f "${f}" ]] || die "falta ${f}"
    local n
    n="$(grep -c 'BEGIN CERTIFICATE' "${f}")"
    [[ "${n}" -gt 100 ]] || die "${f} tiene sólo ${n} certificados"
    [[ -L "${LFS_SYSROOT}/etc/ssl/cert.pem" ]] || die "falta el symlink /etc/ssl/cert.pem"
    echo "  [OK] ${f} (${n} certificados) + /etc/ssl/cert.pem"
}

# linux-firmware -- sólo lo que usan los drivers compilados. Se instala con el
# copy-firmware.sh oficial a un directorio aparte (crea los symlinks de
# compatibilidad listados en WHENCE: p. ej. los iwlwifi-*.ucode de la raíz
# apuntan a intel/iwlwifi/) y de ahí se copian las rutas elegidas:
#   amdgpu/            DRM_AMDGPU (sin firmware no arranca)
#   i915/              DRM_I915 (DMC/GuC: ahorro de energía y video)
#   intel/iwlwifi/ + iwlwifi-*  IWLWIFI
#   rtl_nic/           R8169 (varias revisiones lo piden)
# más regulatory.db de wireless-regdb (cfg80211: canales WiFi por país).
step_firmware() {
    log "linux-firmware ${LINUX_FIRMWARE_VERSION} (subconjunto)"
    cd "${LFS_SOURCES}"
    fetch "${LINUX_FIRMWARE_MIRROR}/linux-firmware-${LINUX_FIRMWARE_VERSION}.tar.xz" \
          "linux-firmware-${LINUX_FIRMWARE_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/linux-firmware-${LINUX_FIRMWARE_VERSION}.tar.xz"

    local src="${LFS_BUILD}/linux-firmware-${LINUX_FIRMWARE_VERSION}"
    local full="${LFS_BUILD}/linux-firmware-full"
    rm -rf "${src}" "${full}"
    tar -xf "${LFS_SOURCES}/linux-firmware-${LINUX_FIRMWARE_VERSION}.tar.xz" -C "${LFS_BUILD}"
    (cd "${src}" && ./copy-firmware.sh "${full}" >/dev/null)

    local dst="${LFS_SYSROOT}/usr/lib/firmware"
    rm -rf "${dst}"
    mkdir -p "${dst}"
    (
        cd "${full}"
        # cp -a conserva los symlinks relativos; las rutas elegidas incluyen
        # sus destinos, así que no quedan colgados (lo controla el verify).
        cp -a --parents amdgpu i915 rtl_nic intel/iwlwifi "${dst}/"
        cp -a iwlwifi-* "${dst}/"
    )
    # regulatory.db ya no viene en linux-firmware (error real: "cannot stat
    # 'regulatory.db'"): se publica aparte, en wireless-regdb. cfg80211 lo
    # pide por el cargador de firmware y verifica la firma .p7s con las
    # claves que trae compiladas el kernel.
    fetch "${WIRELESS_REGDB_MIRROR}/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz" \
          "${LFS_SOURCES}/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz"
    tar -xf "${LFS_SOURCES}/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz" -C "${LFS_BUILD}"
    install -m 0644 "${LFS_BUILD}/wireless-regdb-${WIRELESS_REGDB_VERSION}"/regulatory.db{,.p7s} "${dst}/"
    rm -rf "${LFS_BUILD}/wireless-regdb-${WIRELESS_REGDB_VERSION}"
    install -D -m 0644 "${src}/WHENCE" "${LFS_SYSROOT}/usr/share/licenses/linux-firmware/WHENCE"
    cp -a "${src}"/LICENCE.* "${src}"/LICENSE.* "${LFS_SYSROOT}/usr/share/licenses/linux-firmware/" 2>/dev/null || true
    rm -rf "${src}" "${full}"
    log "firmware instalado en ${dst} ($(du -sh "${dst}" | cut -f1))"
}
step_verify_firmware() {
    local dst="${LFS_SYSROOT}/usr/lib/firmware"
    local d
    for d in amdgpu i915 rtl_nic intel/iwlwifi regulatory.db; do
        [[ -e "${dst}/${d}" ]] || die "falta ${dst}/${d}"
        echo "  [OK] ${dst}/${d}"
    done
    local broken
    broken="$(find "${dst}" -xtype l | head -5)"
    [[ -z "${broken}" ]] || die "symlinks de firmware colgados:\n${broken}"
    echo "  [OK] sin symlinks colgados ($(find "${dst}" -type f | wc -l) archivos, $(du -sh "${dst}" | cut -f1))"
}

# ==============================================================================
# rootfs -- el árbol completo del sistema, listo para meter en el btrfs
# ==============================================================================
step_rootfs() {
    sudo -n true 2>/dev/null || die "hace falta sudo sin contraseña en el contenedor (ver Dockerfile)"
    local kver
    kver="$(ls "${LFS_SYSROOT}/usr/lib/modules" 2>/dev/null | head -1)"
    [[ -n "${kver}" ]] || die "no hay módulos en ${LFS_SYSROOT}/usr/lib/modules -- corré scripts/build-kernel.sh all"
    [[ -x "${LFS_SYSROOT}/usr/bin/login" ]] || die "falta login -- corré scripts/build-comms.sh util-linux-pam"
    [[ -e "${LFS_SYSROOT}/usr/lib/libkmod.so.2" ]] || die "falta kmod -- corré scripts/build-comms.sh kmod && scripts/build-comms.sh systemd-rebuild"

    log "copiando el sysroot a ${STAGE}"
    as_root rm -rf "${STAGE}"
    as_root mkdir -p "${STAGE}"
    as_root cp -a "${LFS_SYSROOT}/usr" "${STAGE}/usr"
    as_root cp -a "${LFS_SYSROOT}/etc" "${STAGE}/etc"
    # modules_install deja build/source apuntando al árbol del kernel en
    # /lfs/build: en el sistema final quedarían colgados.
    as_root rm -f "${STAGE}/usr/lib/modules/${kver}/build" "${STAGE}/usr/lib/modules/${kver}/source"
    as_root chown -R 0:0 "${STAGE}"

    log "estructura de directorios (usrmerge)"
    # Todo vive en /usr; los directorios clásicos son symlinks. /lib64 es el
    # crítico: el intérprete de TODOS los binarios es
    # /lib64/ld-linux-x86-64.so.2 y el loader está en /usr/lib.
    as_root ln -s usr/bin  "${STAGE}/bin"
    as_root ln -s usr/sbin "${STAGE}/sbin"
    as_root ln -s usr/lib  "${STAGE}/lib"
    as_root ln -s usr/lib  "${STAGE}/lib64"
    as_root mkdir -p "${STAGE}"/{boot,dev,efi,home,mnt,opt,proc,run,srv,sys,tmp} \
                     "${STAGE}"/var/{cache,lib,log/journal,mail,spool/mail,tmp}
    as_root install -d -m 0700 "${STAGE}/root"
    as_root chmod 1777 "${STAGE}/tmp" "${STAGE}/var/tmp"
    # /bin/sh: no hay bash -- zsh es el shell del sistema (Pilar de Estética,
    # Fase 2). Invocado como "sh", zsh emula sh POSIX.
    [[ -e "${STAGE}/usr/bin/sh" ]] || as_root ln -s zsh "${STAGE}/usr/bin/sh"

    step_rootfs_etc "${kver}"
    step_rootfs_users
    step_rootfs_services
    step_rootfs_caches "${kver}"
    step_rootfs_permissions

    log "rootfs listo en ${STAGE} ($(as_root du -sh "${STAGE}" | cut -f1))"
}

step_rootfs_etc() {
    local kver="$1"
    log "/etc del sistema"

    put usr/lib/os-release 0644 <<EOF
NAME="LINSI-OS"
PRETTY_NAME="LINSI-OS (imagen de prueba ${IMAGE_DATE})"
ID=linsi
VERSION="0 (Fase 8 -- primera imagen booteable)"
VERSION_ID=0
BUILD_ID=${IMAGE_DATE}
ANSI_COLOR="0;36"
HOME_URL="https://github.com/Juaniip/LINSI-OS"
EOF
    as_root ln -sfn ../usr/lib/os-release "${STAGE}/etc/os-release"

    echo "linsi" | put etc/hostname 0644
    put etc/hosts 0644 <<'EOF'
127.0.0.1   localhost
::1         localhost
EOF

    # PARTLABEL, igual que la línea de comandos del kernel.
    # SIN x-systemd.growfs ni systemd-repart (probado 2026-10-27 en QEMU: los
    # dos fallan en cada arranque): sin initramfs el kernel monta el raíz
    # como el pseudo-dispositivo /dev/root y systemd no puede saber qué disco
    # hay detrás ("backed by pseudo-device /dev/root, which is not a valid
    # userspace accessible device node"). Agrandar la raíz para ocupar todo
    # el pendrive queda para cuando haya initramfs o instalador.
    put etc/fstab 0644 <<EOF
# LINSI-OS -- ver scripts/build-image.sh
PARTLABEL=${ROOT_PARTLABEL}  /     btrfs  defaults,noatime  0 0
PARTLABEL=${ESP_LABEL}   /efi  vfat   umask=0077,noauto,x-systemd.automount,x-systemd.idle-timeout=60  0 2
EOF

    put etc/locale.conf 0644 <<'EOF'
LANG=es_AR.UTF-8
EOF
    # Los archivos PAM de plasma-login-manager (configuración "debian") leen
    # el idioma de acá con pam_env.
    put etc/default/locale 0644 <<'EOF'
LANG=es_AR.UTF-8
EOF
    put etc/vconsole.conf 0644 <<'EOF'
KEYMAP=la-latin1
FONT=eurlatgr
EOF
    as_root ln -sfn ../usr/share/zoneinfo/America/Argentina/Buenos_Aires "${STAGE}/etc/localtime"
    # "uninitialized": systemd lo trata como primer arranque y genera el
    # machine-id ahí (cada pendrive grabado tiene el suyo).
    echo "uninitialized" | put etc/machine-id 0444

    put etc/nsswitch.conf 0644 <<'EOF'
# LINSI-OS -- módulos NSS de glibc y de systemd (nss-systemd/resolve/myhostname/mymachines)
passwd:     files systemd
group:      files [SUCCESS=merge] systemd
shadow:     files systemd
gshadow:    files systemd
hosts:      mymachines resolve [!UNAVAIL=return] files myhostname dns
networks:   files
protocols:  files
services:   files
ethers:     files
rpc:        files
netgroup:   files
EOF
    # services/protocols: glibc no los instala (en las distros vienen de
    # netbase/iana-etc) y el contenedor tampoco los tiene (error real:
    # "cannot stat '/etc/services'"). iana-etc, igual que LFS: las tablas
    # oficiales de IANA ya en formato /etc.
    fetch "${IANA_ETC_MIRROR}/iana-etc-${IANA_ETC_VERSION}.tar.gz" \
          "${LFS_SOURCES}/iana-etc-${IANA_ETC_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/iana-etc-${IANA_ETC_VERSION}.tar.gz"
    local iana
    iana="$(mktemp -d)"
    tar -xf "${LFS_SOURCES}/iana-etc-${IANA_ETC_VERSION}.tar.gz" -C "${iana}" --strip-components=1
    as_root install -m 0644 "${iana}/services"  "${STAGE}/etc/services"
    as_root install -m 0644 "${iana}/protocols" "${STAGE}/etc/protocols"
    rm -rf "${iana}"

    # systemd-resolved (DNS-over-TLS de Fase 4). NetworkManager lo detecta
    # solo por este symlink y le pasa los DNS de cada conexión.
    as_root ln -sfn ../run/systemd/resolve/stub-resolv.conf "${STAGE}/etc/resolv.conf"

    put etc/shells 0644 <<'EOF'
/usr/bin/zsh
/bin/zsh
/usr/bin/sh
/bin/sh
EOF

    # Administradores = grupo wheel (run0, acciones de administrador de KDE).
    # Reemplaza a sudo: run0 viene con systemd y pasa por polkit.
    put etc/polkit-1/rules.d/49-linsi-wheel.rules 0644 <<'EOF'
// LINSI-OS: los miembros de wheel son administradores (run0, KDE).
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
EOF

    # zsh: configuración global + .zshrc vacío en skel (sin él, zsh abre el
    # asistente zsh-newuser-install la primera vez en cada terminal).
    put etc/zsh/zshrc 0644 <<'EOF'
# LINSI-OS -- configuración global de zsh (la personal va en ~/.zshrc)
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt hist_ignore_dups share_history autocd interactive_comments
bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
autoload -Uz colors && colors
PROMPT='%F{cyan}%n@%m%f %F{blue}%~%f %(?.%F{green}.%F{red})%#%f '
alias ls='ls --color=auto'
alias ll='ls -lh --color=auto'
alias la='ls -lah --color=auto'
EOF
    echo "# Configuración personal de zsh (la global está en /etc/zsh/zshrc)." \
        | put etc/skel/.zshrc 0644
    as_root cp "${STAGE}/etc/skel/.zshrc" "${STAGE}/root/.zshrc"

    # Reglas base de audit (error real en QEMU: "augenrules: No rules
    # directory - /etc/audit/rules.d" y audit-rules.service fallaba en cada
    # arranque). audit instala auditd.conf pero ningún rules.d; augenrules
    # compila de acá /etc/audit/audit.rules al arrancar. Sólo la base: buffer,
    # espera ante picos y "printk" si se pierde algo; las reglas de vigilancia
    # concretas son trabajo de la política de seguridad (Fase 3).
    put etc/audit/rules.d/10-linsi-base.rules 0640 <<'EOF'
# LINSI-OS -- base de audit (ver scripts/build-image.sh)
-D
-b 8192
--backlog_wait_time 60000
-f 1
EOF

    # Usuario de CUPS: el sistema se configuró con --with-cups-user=lp
    # --with-system-groups=lpadmin y ningún sysusers.d los creaba.
    put usr/lib/sysusers.d/linsi.conf 0644 <<'EOF'
# LINSI-OS -- cuentas de sistema que ningún paquete declara
u lp      -  "Servicio de impresión (CUPS)"  /var/spool/cups
g lpadmin -
EOF

    put usr/lib/systemd/system-preset/80-linsi.preset 0644 <<'EOF'
# LINSI-OS -- servicios del sistema (gana sobre 90-systemd.preset)
enable NetworkManager.service
enable systemd-resolved.service
enable systemd-timesyncd.service
enable plasmalogin.service
enable cups.socket
enable cups.path
# La red la maneja NetworkManager; networkd sin configuración sólo haría
# esperar al arranque (wait-online).
disable systemd-networkd.service
disable systemd-networkd.socket
disable systemd-networkd-wait-online.service
EOF
    put usr/lib/systemd/user-preset/80-linsi.preset 0644 <<'EOF'
# LINSI-OS -- servicios de la sesión de cada usuario
enable pipewire.socket
enable pipewire-pulse.socket
enable wireplumber.service
# filter-chain sin configuración propia sólo falla en cada inicio de sesión.
disable filter-chain.service
EOF
}

step_rootfs_users() {
    log "usuarios y grupos"
    # Cuentas de sistema declaradas por cada paquete en /usr/lib/sysusers.d
    # (root, nobody, messagebus, polkitd, plasmalogin, systemd-*...).
    in_root /usr/bin/systemd-sysusers

    # Rangos de UID/GID subordinados (Podman rootless, Fase 7): useradd los
    # asigna solo si los archivos existen.
    as_root touch "${STAGE}/etc/subuid" "${STAGE}/etc/subgid"
    in_root /usr/sbin/useradd -m -U \
        -G wheel,audio,video,input,render,lp,lpadmin \
        -s /usr/bin/zsh -c "Usuario LINSI" "${LIVE_USER}"

    # El hash se genera en el contenedor (SHA-512 crypt, el mismo que usa
    # pam_unix en common-password) y chpasswd -e lo escribe tal cual.
    local hash
    hash="$(openssl passwd -6 "${LIVE_PASSWORD}")"
    printf 'root:%s\n%s:%s\n' "${hash}" "${LIVE_USER}" "${hash}" | in_root /usr/sbin/chpasswd -e
}

step_rootfs_services() {
    log "servicios (presets) y target gráfico"
    in_root /usr/bin/systemctl preset-all
    in_root /usr/bin/systemctl --global preset-all
    in_root /usr/bin/systemctl set-default graphical.target
    # glibc se compiló sin instalar ldconfig y no hace falta (el loader busca
    # en /usr/lib); sin esto ldconfig.service falla en cada arranque.
    in_root /usr/bin/systemctl mask ldconfig.service
}

step_rootfs_caches() {
    local kver="$1"
    log "cachés que normalmente generan los paquetes al instalarse"
    in_root /usr/sbin/depmod -a "${kver}"
    # hwdb.bin NO se genera acá (error real: "Failed to write database
    # /usr/lib/udev/hwdb.bin: Function not implemented" -- systemd escribe
    # vía /proc/self/fd y en el chroot no hay /proc, que en podman rootless
    # no se puede montar). Lo genera systemd-hwdb-update.service en el
    # primer arranque (ConditionNeedsUpdate=/etc), antes de udev.
    in_root /usr/bin/update-mime-database /usr/share/mime
    [[ -d "${STAGE}/usr/share/glib-2.0/schemas" ]] \
        && in_root /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas
    in_root /usr/bin/fc-cache -f

    # Locales: es_AR (el del sistema) y en_US. El charmap viene comprimido y
    # localedef necesitaría gzip adentro del sistema, que no hay: se
    # descomprime en un temporal del propio árbol.
    as_root mkdir -p "${STAGE}/usr/lib/locale" "${STAGE}/tmp/charmaps"
    as_root sh -c "gzip -dc '${STAGE}/usr/share/i18n/charmaps/UTF-8.gz' > '${STAGE}/tmp/charmaps/UTF-8'"
    in_root /usr/bin/localedef -i es_AR -f /tmp/charmaps/UTF-8 es_AR.UTF-8
    in_root /usr/bin/localedef -i en_US -f /tmp/charmaps/UTF-8 en_US.UTF-8
    as_root rm -rf "${STAGE}/tmp/charmaps"
}

step_rootfs_permissions() {
    log "dueños y bits setuid"
    # Los paquetes se instalaron como usuario sin privilegios (con chown/chgrp
    # de mentira en util-linux): acá van los permisos que en una distro pone
    # cada paquete al instalarse. Todo chown con NOMBRE de grupo va por
    # in_root: desde afuera, chown resuelve los nombres con el /etc/group del
    # contenedor (error real: "chown: invalid group: 'root:messagebus'").
    local f
    for f in usr/bin/passwd usr/bin/chage usr/bin/gpasswd usr/bin/newgrp usr/bin/expiry \
             usr/bin/chsh usr/bin/chfn usr/bin/su usr/bin/mount usr/bin/umount \
             usr/bin/newuidmap usr/bin/newgidmap usr/bin/fusermount3 usr/bin/pkexec \
             usr/sbin/unix_chkpwd usr/lib/polkit-1/polkit-agent-helper-1; do
        [[ -e "${STAGE}/${f}" ]] || continue
        as_root chown root:root "${STAGE}/${f}"
        as_root chmod 4755 "${STAGE}/${f}"
        echo "  setuid root: /${f}"
    done
    if [[ -e "${STAGE}/usr/libexec/dbus-daemon-launch-helper" ]]; then
        in_root /usr/bin/chown root:messagebus /usr/libexec/dbus-daemon-launch-helper
        as_root chmod 4750 "${STAGE}/usr/libexec/dbus-daemon-launch-helper"
        echo "  setuid root (grupo messagebus): /usr/libexec/dbus-daemon-launch-helper"
    fi
    for f in usr/bin/wall usr/bin/write; do
        [[ -e "${STAGE}/${f}" ]] || continue
        in_root /usr/bin/chown root:tty "/${f}"
        as_root chmod 2755 "${STAGE}/${f}"
        echo "  setgid tty: /${f}"
    done
    local d
    for d in etc/polkit-1/rules.d usr/share/polkit-1/rules.d; do
        [[ -d "${STAGE}/${d}" ]] || continue
        in_root /usr/bin/chown root:polkitd "/${d}"
        as_root chmod 0750 "${STAGE}/${d}"
    done
    if [[ -d "${STAGE}/etc/cups" ]]; then
        in_root /usr/bin/chgrp -R lp /etc/cups
    fi
}

step_verify_rootfs() {
    log "Verificación: rootfs armado"
    local p
    for p in lib64/ld-linux-x86-64.so.2 usr/lib/systemd/systemd usr/bin/login usr/bin/zsh bin/sh \
             etc/os-release etc/fstab etc/passwd etc/shadow etc/locale.conf etc/vconsole.conf \
             usr/lib/locale/locale-archive usr/share/mime/mime.cache \
             etc/systemd/system/display-manager.service \
             etc/systemd/system/multi-user.target.wants/NetworkManager.service; do
        # -L también: los symlinks de systemd son absolutos (/usr/lib/...) y
        # desde afuera del árbol "test -e" los sigue contra el contenedor.
        as_root test -e "${STAGE}/${p}" -o -L "${STAGE}/${p}" || die "falta /${p} en el rootfs"
        echo "  [OK] /${p}"
    done
    as_root grep -q "^${LIVE_USER}:" "${STAGE}/etc/passwd" || die "no está el usuario ${LIVE_USER}"
    # -F: en un regex el "$" final de "$6$" es ancla de fin de línea.
    as_root grep -qF "${LIVE_USER}:\$6\$" "${STAGE}/etc/shadow" || die "${LIVE_USER} no tiene contraseña SHA-512"
    echo "  [OK] usuario ${LIVE_USER} con contraseña"
    [[ "$(as_root stat -c '%U %a' "${STAGE}/usr/sbin/unix_chkpwd")" == "root 4755" ]] \
        || die "unix_chkpwd no es setuid root (el bloqueo de pantalla no podría validar la contraseña)"
    echo "  [OK] unix_chkpwd setuid root"
    [[ "$(readlink "${STAGE}/etc/systemd/system/default.target")" == *graphical.target ]] \
        || die "default.target no es graphical.target"
    echo "  [OK] default.target -> graphical.target"
    local kver
    kver="$(ls "${STAGE}/usr/lib/modules")"
    as_root test -s "${STAGE}/usr/lib/modules/${kver}/modules.dep" || die "depmod no generó modules.dep"
    echo "  [OK] modules.dep (${kver})"
}

# ==============================================================================
# image -- disco GPT: ESP (GRUB + kernel) + btrfs con el rootfs
# ==============================================================================
step_image() {
    local kernel="${LFS}/boot/vmlinuz-linsi-${LINUX_VERSION}"
    [[ -f "${kernel}" ]] || die "falta ${kernel} -- corré scripts/build-kernel.sh all"
    as_root test -x "${STAGE}/usr/lib/systemd/systemd" || die "no hay rootfs armado -- corré: scripts/build-image.sh rootfs"

    as_root rm -rf "${WORK}"
    as_root mkdir -p "${WORK}"
    as_root chown "$(id -u):$(id -g)" "${WORK}"

    log "GRUB (EFI, autónomo con su grub.cfg adentro)"
    # Entradas: normal; modo texto (sin sesión gráfica, para diagnosticar);
    # gráficos básicos (nomodeset: sólo el framebuffer del firmware, si el
    # driver de la GPU cuelga la pantalla); consola serie (VMs/depuración).
    cat > "${WORK}/grub.cfg" <<EOF
set timeout=5
set default=0
search --no-floppy --label ${ESP_LABEL} --set=root
insmod all_video

menuentry "LINSI-OS" {
    linux /linsi/vmlinuz ${KERNEL_CMDLINE}
}
menuentry "LINSI-OS (modo texto)" {
    linux /linsi/vmlinuz ${KERNEL_CMDLINE} systemd.unit=multi-user.target
}
menuentry "LINSI-OS (gráficos básicos: nomodeset)" {
    linux /linsi/vmlinuz ${KERNEL_CMDLINE} nomodeset
}
menuentry "LINSI-OS (diagnóstico: consola serie + logs)" {
    linux /linsi/vmlinuz ${KERNEL_CMDLINE} console=tty0 console=ttyS0,115200 systemd.log_level=info systemd.show_status=1
}
menuentry "Configuración del firmware UEFI" {
    fwsetup
}
EOF
    grub-mkstandalone -O x86_64-efi -o "${WORK}/BOOTX64.EFI" \
        --modules="part_gpt fat search search_label normal linux echo all_video efi_gop test configfile reboot halt" \
        --locales="" --themes="" --fonts="" \
        "boot/grub/grub.cfg=${WORK}/grub.cfg"

    log "partición EFI (${ESP_SIZE_MIB} MiB, FAT32, etiqueta ${ESP_LABEL})"
    truncate -s "${ESP_SIZE_MIB}M" "${WORK}/esp.img"
    /usr/sbin/mkfs.fat -F 32 -n "${ESP_LABEL}" "${WORK}/esp.img" >/dev/null
    mmd   -i "${WORK}/esp.img" ::/EFI ::/EFI/BOOT ::/linsi
    mcopy -i "${WORK}/esp.img" "${WORK}/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
    mcopy -i "${WORK}/esp.img" "${kernel}" ::/linsi/vmlinuz

    log "partición raíz (btrfs de ~${ROOT_SIZE_MIB} MiB, mkfs.btrfs --rootdir)"
    # Como root: el árbol tiene archivos legibles sólo por root (/etc/shadow).
    # Tamaño (errores reales 2026-10-27): el mkfs.btrfs 6.2 del contenedor,
    # con --rootdir, NO respeta ni el tamaño del archivo ni -b: le suma su
    # propio margen (pedido 8192 MiB -> filesystem de 8685 MiB, confirmado
    # con dump-super: total_bytes 9106882560). Con --shrink sale del tamaño
    # mínimo, pero sin initramfs no se puede agrandar después (ver fstab) y
    # quedaban ~2 GB libres. Entonces se invierte el orden: primero el
    # filesystem y DESPUÉS la partición, del tamaño real que haya salido.
    truncate -s "${ROOT_SIZE_MIB}M" "${WORK}/root.img"
    as_root /usr/sbin/mkfs.btrfs -q -L "${ROOT_PARTLABEL}" -b "${ROOT_SIZE_MIB}M" --rootdir "${STAGE}" "${WORK}/root.img"
    local root_bytes root_mib
    root_bytes="$(as_root stat -c %s "${WORK}/root.img")"
    root_mib=$(( (root_bytes + 1048575) / 1048576 ))
    log "btrfs: ${root_mib} MiB -> partición raíz de ${root_mib} MiB"

    log "disco GPT"
    local disk="${WORK}/${IMAGE_NAME}"
    local total_mib=$((1 + ESP_SIZE_MIB + root_mib + 1))
    truncate -s "${total_mib}M" "${disk}"
    # Tipos: ESP y "Linux root (x86-64)" de la Discoverable Partitions Spec
    # (lo que usa systemd-repart para reconocer la raíz).
    /usr/sbin/sfdisk -q "${disk}" <<EOF
label: gpt
start=2048, size=$((ESP_SIZE_MIB * 2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="${ESP_LABEL}"
start=$((2048 + ESP_SIZE_MIB * 2048)), size=$((root_mib * 2048)), type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name="${ROOT_PARTLABEL}"
EOF
    dd if="${WORK}/esp.img"  of="${disk}" bs=1M seek=1 conv=notrunc,sparse status=none
    as_root dd if="${WORK}/root.img" of="${disk}" bs=1M seek=$((1 + ESP_SIZE_MIB)) conv=notrunc,sparse status=none
    as_root rm -f "${WORK}/root.img" "${WORK}/esp.img"

    log "copiando a ${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
    rm -f "${OUT_DIR}/${IMAGE_NAME}" "${OUT_DIR}/${IMAGE_NAME}.sha256"
    cp --sparse=always "${disk}" "${OUT_DIR}/${IMAGE_NAME}"
    (cd "${OUT_DIR}" && sha256sum "${IMAGE_NAME}" > "${IMAGE_NAME}.sha256")
    log "imagen lista: ${OUT_DIR}/${IMAGE_NAME} ($((total_mib)) MiB)"
}
step_verify_image() {
    local img="${OUT_DIR}/${IMAGE_NAME}"
    [[ -f "${img}" ]] || die "falta ${img}"
    /usr/sbin/sfdisk -l "${img}"
    local gpt
    gpt="$(/usr/sbin/sfdisk -J "${img}")"
    grep -qE "\"name\": ?\"${ROOT_PARTLABEL}\"" <<<"${gpt}" || die "la tabla GPT no tiene ${ROOT_PARTLABEL}"
    # Tamaño exacto: la partición raíz termina 1 MiB antes del final del
    # archivo (lugar de la GPT de respaldo). Si algo agrandó el archivo, la
    # GPT de respaldo no queda al final y el firmware puede rechazar el disco.
    local end_sector want
    end_sector="$(python3 -I -c 'import json,sys; p=json.load(sys.stdin)["partitiontable"]["partitions"][-1]; print(p["start"]+p["size"])' <<<"${gpt}")"
    want=$(( end_sector * 512 + 1024 * 1024 ))
    [[ "$(stat -c %s "${img}")" -eq "${want}" ]] || die "la imagen no mide ${want} bytes (¿algo agrandó el archivo?)"
    echo "  [OK] GPT con ${ROOT_PARTLABEL}, tamaño exacto ($((want / 1024 / 1024)) MiB)"
    # El btrfs no puede ser más grande que su partición (el kernel no lo
    # montaría): se lee total_bytes del superbloque (offset 64 KiB + 0x70).
    local root_start root_size fs_bytes
    root_start="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][-1]["start"])' <<<"${gpt}")"
    root_size="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][-1]["size"])' <<<"${gpt}")"
    fs_bytes="$(python3 -I - "${img}" "${root_start}" <<'PYEOF'
import struct, sys
with open(sys.argv[1], "rb") as f:
    f.seek(int(sys.argv[2]) * 512 + 65536 + 0x70)
    print(struct.unpack("<Q", f.read(8))[0])
PYEOF
)"
    (( fs_bytes <= root_size * 512 )) || die "el btrfs (${fs_bytes} bytes) es más grande que su partición ($((root_size * 512)) bytes)"
    echo "  [OK] btrfs de $((fs_bytes / 1048576)) MiB en partición de $((root_size * 512 / 1048576)) MiB"
    mdir -i "${img}@@1M" ::/EFI/BOOT | grep -qi "BOOTX64" || die "la ESP no tiene EFI/BOOT/BOOTX64.EFI"
    mdir -i "${img}@@1M" ::/linsi | grep -qi "vmlinuz" || die "la ESP no tiene el kernel"
    echo "  [OK] ESP con BOOTX64.EFI y vmlinuz"
    (cd "${OUT_DIR}" && sha256sum -c "${IMAGE_NAME}.sha256")
}

# ==============================================================================
# test -- arrancar la imagen en QEMU (sin KVM: emulación pura, lento)
# ==============================================================================
# Dos arranques sobre una capa qcow2 descartable (la imagen entregable no se
# toca):
#   1. directo al kernel con consola serie: se lee el arranque completo de
#      systemd en el log y se ve si llega al login gráfico.
#   2. por UEFI (OVMF) desde el disco: valida GRUB + ESP como en una PC real.
# En los dos se sacan capturas de pantalla (PNG) en out/.
_qemu_screendump() {
    local sock="$1" png="$2"
    python3 -I - "${sock}" "${png}" <<'PYEOF'
import socket, sys, time, zlib, struct, os
sock, png = sys.argv[1], sys.argv[2]
ppm = png[:-4] + ".ppm"
s = socket.socket(socket.AF_UNIX); s.connect(sock)
s.recv(4096)
s.sendall(f"screendump {ppm}\n".encode()); time.sleep(2); s.close()
data = open(ppm, "rb").read()
parts = data.split(b"\n", 3)
w, h = map(int, parts[1].split()); raw = parts[3]
rows = b"".join(b"\x00" + raw[y*w*3:(y+1)*w*3] for y in range(h))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(png, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                      + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))
os.remove(ppm)
print(f"captura: {png} ({w}x{h})")
PYEOF
}

step_test() {
    local img="${OUT_DIR}/${IMAGE_NAME}"
    [[ -f "${img}" ]] || die "falta ${img} -- corré: scripts/build-image.sh image"
    local t="${IMAGE_DIR}/test"
    # IMAGE_DIR es de root (lo crea step_rootfs); error real "Permission
    # denied". Mismo criterio que WORK en step_image.
    as_root rm -rf "${t}"
    as_root mkdir -p "${t}"
    as_root chown "$(id -u):$(id -g)" "${t}"
    local kvm=()
    # Sin KVM, "-cpu Nehalem" y no "-cpu max" (probado 2026-10-27): con max,
    # la emulación por software de QEMU expone instrucciones vectoriales que
    # el código JIT de llvmpipe usa y QEMU no emula bien -- kwin_wayland moría
    # con SEGV dentro de llvmpipe y la pantalla quedaba negra; con Nehalem
    # (SSE4.2, sin AVX) el mismo disco llega al login. Es un problema de la
    # emulación, no del sistema: en hardware real no se usa llvmpipe (hay
    # driver de GPU) y en una VM con KVM/Hyper-V la CPU es la real.
    [[ -w /dev/kvm ]] && kvm=(-enable-kvm -cpu host) || kvm=(-cpu Nehalem)
    log "QEMU: ${kvm[*]} (sin /dev/kvm la emulación es lenta: varios minutos hasta el login)"

    # --- 1: kernel directo + consola serie ---
    qemu-img create -q -f qcow2 -b "${img}" -F raw "${t}/disk1.qcow2"
    qemu-system-x86_64 -machine q35 "${kvm[@]}" -smp 4 -m 4096 \
        -kernel "${LFS}/boot/vmlinuz-linsi-${LINUX_VERSION}" \
        -append "${KERNEL_CMDLINE} console=tty0 console=ttyS0,115200 systemd.show_status=1" \
        -drive file="${t}/disk1.qcow2",format=qcow2,if=virtio \
        -vga std -display none -serial file:"${t}/serial1.log" \
        -monitor unix:"${t}/mon1.sock",server,nowait \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        -daemonize -pidfile "${t}/qemu1.pid"

    local waited=0 limit="${LINSI_TEST_TIMEOUT:-1500}"
    while (( waited < limit )); do
        if grep -qE "Started plasmalogin|Reached target graphical|login:" "${t}/serial1.log" 2>/dev/null \
           && (( waited > 60 )); then
            break
        fi
        sleep 15; waited=$((waited + 15))
    done
    # Darle tiempo al greeter a dibujarse (llvmpipe sobre TCG es lento).
    sleep 90
    _qemu_screendump "${t}/mon1.sock" "${OUT_DIR}/test-1-kernel-directo.png" || true
    kill "$(cat "${t}/qemu1.pid")" 2>/dev/null || true
    cp "${t}/serial1.log" "${OUT_DIR}/test-1-serial.log"

    # --- 2: UEFI (OVMF) desde el disco, como una PC real ---
    qemu-img create -q -f qcow2 -b "${img}" -F raw "${t}/disk2.qcow2"
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "${t}/vars.fd"
    qemu-system-x86_64 -machine q35 "${kvm[@]}" -smp 4 -m 4096 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
        -drive if=pflash,format=raw,file="${t}/vars.fd" \
        -drive file="${t}/disk2.qcow2",format=qcow2,if=virtio \
        -vga std -display none -serial file:"${t}/serial2.log" \
        -monitor unix:"${t}/mon2.sock",server,nowait \
        -daemonize -pidfile "${t}/qemu2.pid"
    sleep 20
    _qemu_screendump "${t}/mon2.sock" "${OUT_DIR}/test-2-uefi-grub.png" || true
    sleep "${LINSI_TEST_UEFI_WAIT:-600}"
    _qemu_screendump "${t}/mon2.sock" "${OUT_DIR}/test-2-uefi-sesion.png" || true
    kill "$(cat "${t}/qemu2.pid")" 2>/dev/null || true

    log "prueba terminada: capturas y log serie en ${OUT_DIR}"
}
step_verify_test() {
    local s="${OUT_DIR}/test-1-serial.log"
    [[ -f "${s}" ]] || die "falta ${s} -- corré: scripts/build-image.sh test"
    grep -E "Failed to start|FAILED|Kernel panic|emergency" "${s}" | head -20 || true
    grep -qE "Reached target.*[Gg]raphical|Started plasmalogin" "${s}" \
        || die "el arranque no llegó al target gráfico (ver ${s})"
    echo "  [OK] llegó al target gráfico"
}

main() {
    local target="${1:-all}"
    case "${target}" in
        kbd)             step_kbd ;;
        verify-kbd)      step_verify_kbd ;;
        tzdata)          step_tzdata ;;
        verify-tzdata)   step_verify_tzdata ;;
        cacert)          step_cacert ;;
        verify-cacert)   step_verify_cacert ;;
        firmware)        step_firmware ;;
        verify-firmware) step_verify_firmware ;;
        rootfs)          step_rootfs ;;
        verify-rootfs)   step_verify_rootfs ;;
        image)           step_image ;;
        verify-image)    step_verify_image ;;
        test)            step_test ;;
        verify-test)     step_verify_test ;;
        all)
            step_kbd;      step_verify_kbd
            step_tzdata;   step_verify_tzdata
            step_cacert;   step_verify_cacert
            step_firmware; step_verify_firmware
            step_rootfs;   step_verify_rootfs
            step_image;    step_verify_image
            log "Fase 8: imagen booteable en ${OUT_DIR}/${IMAGE_NAME}"
            ;;
        *)
            die "target desconocido: ${target} (usar: kbd|tzdata|cacert|firmware|rootfs|image|test|all, cada uno con su verify-<paso>)"
            ;;
    esac
}

main "$@"
