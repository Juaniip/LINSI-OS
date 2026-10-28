#!/usr/bin/env bash
# ==============================================================================
# LINSI-OS · Fase 0 — Variables de entorno compartidas
# Se sourcea desde entrypoint.sh y desde cada script de build.
#
# IMPORTANTE: revisá las versiones antes de una build "real" — acá se fija un
# set conocido-bueno al momento de escribir esto, pero Binutils/GCC/kernel
# sacan releases seguido. https://ftp.gnu.org/gnu/binutils/  /gcc/  /kernel.org
# ==============================================================================
set -euo pipefail

# --- Versiones del cross-toolchain (Fase 0) ----------------------------------
export BINUTILS_VERSION="2.43.1"
export GCC_VERSION="14.2.0"
export LINUX_VERSION="7.2"             # kernel a usar tanto para las cabeceras (Fase 0) como el build completo (Fase 1)
export GMP_VERSION="6.3.0"
export MPFR_VERSION="4.2.1"
export MPC_VERSION="1.3.1"

# sha256 oficial de linux-7.2.tar.xz publicado en kernel.org/pub/linux/kernel/v7.x/sha256sums.asc
# (chequeado el 2026-08-22 — antes de una build "real" volvé a confirmarlo ahí mismo)
export LINUX_SHA256="f9fef3d14c0df53819026f4be74459835c2a0b0dcbf5b5bbd9ea19f0829402b3"

# --- Versiones del espacio de usuario (Fase 2) --------------------------------
# Chequeadas por búsqueda web el 2026-08-24 (últimas estables a esa fecha):
#   glibc   2.44  — sourceware.org/glibc, release 2026-07-25
#   systemd 261   — github.com/systemd/systemd/releases/tag/v261, release 2026-06-19
#   zsh     5.9   — zsh.sourceforge.io/News, sin release más nuevo desde 2022
# A diferencia del kernel, ninguno de estos tres publica un sha256sums.txt
# plano y fácil de verificar de forma automática (se firman por GPG). No se
# fija acá un hash inventado — verify_userspace_tarball() calcula el sha256
# real después de bajar cada uno y lo deja en el log para cotejar a mano
# contra la fuente oficial si querés esa garantía extra.
export GLIBC_VERSION="2.44"
export SYSTEMD_VERSION="261"
export ZSH_VERSION="5.9"

# Dependencias de systemd que hay que compilar antes (systemd las busca vía
# pkg-config contra el sysroot: sin esto, meson las auto-deshabilita en vez
# de fallar, así que si querés que systemd las use de verdad tienen que
# estar instaladas ANTES del paso systemd).
# Chequeadas por búsqueda web el 2026-08-25 (últimas estables a esa fecha):
#   util-linux 2.42.2 — kernel.org/pub/linux/utils/util-linux, release 2026-06-16
#   libcap     2.78   — kernel.org/pub/linux/libs/security/linux-privs/libcap2, release 2026-04-06
#   attr       2.6.0  — download-mirror.savannah.gnu.org/releases/attr, release 2026-06-29
#   acl        2.4.0  — confirmado por versión de paquete en Arch/Artix (2.4.0-1);
#                        no se pudo confirmar el nombre exacto del tarball en
#                        savannah por bloqueo de robots.txt en la búsqueda — si
#                        el .tar.xz de acl-2.4.0 no existe en el mirror, avisame
#                        con el error de wget y lo ajusto a .tar.gz.
export UTIL_LINUX_VERSION="2.42.2"
export LIBCAP_VERSION="2.78"
export ATTR_VERSION="2.6.0"
export ACL_VERSION="2.4.0"

# ncurses: lo necesita Zsh (edición de línea, colores, terminfo) — no estaba
# en la lista original de dependencias de systemd, se agrega acá porque Zsh
# sin ninguna librería de terminal no tiene mucho sentido como shell real.
# Chequeada por búsqueda web el 2026-08-25: última estable, ftp.gnu.org/gnu/ncurses.
export NCURSES_VERSION="6.6"

# uutils (coreutils en Rust) — se compila desde el tag de GitHub, no desde
# crates.io, porque el repo es un workspace con muchos crates (uu_ls, uu_cp,
# etc.) más el crate "coreutils" que arma el binario multicall tipo BusyBox;
# publicar eso reproducible vía crates.io individual sería mucho más frágil
# que bajar el tarball del tag directo. Chequeada el 2026-08-25: último
# release "0.9.0" (30/05/2026), 625 tests de la testsuite de GNU pasando.
export UUTILS_VERSION="0.9.0"

# --- Fase 3 ("El Escudo") -------------------------------------------------------
# nftables + sus dos librerías netlink de base. Chequeadas por búsqueda web el
# 2026-08-26 (últimas estables a esa fecha, netfilter.org/projects/*/downloads.html):
#   libmnl    1.0.5  — sin release nuevo desde 2022 (paquete chico y estable)
#   libnftnl  1.3.1  — 03/12/2025
#   nftables  1.1.6  — 05/12/2025
export LIBMNL_VERSION="1.0.5"
export LIBNFTNL_VERSION="1.3.1"
export NFTABLES_VERSION="1.1.6"

# libcap-ng: dependencia OPCIONAL de auditd/audisp para que sus plugins
# corran con el mínimo de capabilities posible en vez de con todo el root
# (coherente con el resto del hardening de esta fase, aunque no es
# estrictamente necesaria para que auditd funcione). Chequeada por búsqueda
# web el 2026-08-26: el release taggeado más nuevo en GitHub es 0.9.5
# (21/08/2024). El configure.ac de la rama master ya dice "0.9.6", pero eso
# es sólo el número que el propio proyecto sube ni bien taggea un release,
# para el PRÓXIMO (todavía sin tag ni tarball publicado) — mismo patrón que
# se repite con audit-userspace más abajo. Nos quedamos con el último tag
# REAL: 0.9.5.
export LIBCAP_NG_VERSION="0.9.5"

# audit-userspace (auditd + auparse + auditctl + reglas). Chequeada por
# búsqueda web el 2026-08-26 contra el ChangeLog real del repo (no contra la
# página de releases, que a veces no lista el más nuevo): el último release
# taggeado es 4.2.1 (29/07/2026). Igual que con libcap-ng, el audit.spec de
# master ya dice "4.2.2" (versión en preparación, sin tag todavía). Si para
# cuando corras esto ya existe un 4.2.2 (u otro más nuevo) publicado de
# verdad en https://github.com/linux-audit/audit-userspace/releases, avisame
# y lo actualizo — este es, de todo el proyecto, el número de versión que
# menos pude confirmar con certeza total.
export AUDIT_VERSION="4.2.1"

# --- Fase 3 (cont.) — cryptsetup/LUKS2 con Argon2id -----------------------------
# Versiones confirmadas contra las páginas de BLFS (Beyond Linux From Scratch,
# el mismo linaje de proyecto que esta guía) el 2026-08-26 — son la fuente
# más confiable para versiones/flags de un build LFS-style, mejor que
# adivinar desde cero como con libcap-ng/audit-userspace:
#   json-c      0.19        — linuxfromscratch.org/blfs/.../json-c.html
#   popt        1.19        — linuxfromscratch.org/blfs/.../popt.html
#   LVM2        2.03.42     — linuxfromscratch.org/blfs/.../lvm2.html
#   cryptsetup  2.8.7       — linuxfromscratch.org/blfs/.../cryptsetup.html
# libargon2 no está en BLFS (cryptsetup lo trata como opcional, BLFS no lo
# usa) — se confirmó aparte contra el repo de PHC: no tiene un release
# nuevo desde 2019 (20190702), lo cual es normal: es la implementación de
# referencia del algoritmo ganador del Password Hashing Competition, ya
# congelada/estable.
export LIBARGON2_VERSION="20190702"
export POPT_VERSION="1.19"
export JSON_C_VERSION="0.19"
export LVM2_VERSION="2.03.42"
export CRYPTSETUP_VERSION="2.8.7"

# libaio: agregado 2026-08-26 tras un intento real de LVM2 — hace falta
# incluso para el subconjunto mínimo "device-mapper" (lib/bcache.c del
# propio LVM2 lo necesita, no sólo el daemon opcional dmeventd). Versión
# confirmada contra el índice real de releases.pagure.org/libaio/: la
# 0.3.113 (14/04/2022) es la más nueva publicada ahí, sin release más
# reciente desde entonces — normal para una librería tan chica y estable.
export LIBAIO_VERSION="0.3.113"

# --- Fase 3 (cont.) — SELinux (paso 12, último de la fase) -----------------------
# libsepol/libselinux/libsemanage/checkpolicy/policycoreutils vienen del MISMO
# repo (github.com/SELinuxProject/selinux), taggeados y publicados todos juntos
# bajo el mismo número de versión — no son proyectos independientes con
# versiones propias. Chequeado contra la página de releases real el 2026-08-26:
# último tag "3.11" (01/07/2026). Cada componente sí publica su propio tarball
# de release "de verdad" (con Makefile listo, no un archive de git crudo).
export SELINUX_VERSION="3.11"

# bzip2: NUEVA dependencia agregada acá — libsemanage linkea contra -lbz2
# (comprime/descomprime el store de políticas). El "bzip2" que ya estaba en
# el Dockerfile es sólo el binario del HOST para descomprimir tarballs .bz2
# de las fuentes (libmnl, por ejemplo) — no sirve para linkear, hace falta
# esta copia cross-compilada aparte, con libbz2.so instalado en el sysroot.
# Última versión estable: 1.0.8, sin release nuevo desde 2019 (proyecto
# congelado/estable, es normal). URL confirmada: es el mismo tarball que usa
# LFS/BLFS desde hace años.
export BZIP2_VERSION="1.0.8"

# PCRE2: NUEVA dependencia agregada acá — libselinux usa PCRE2 (no la regex
# POSIX de glibc) para matchear los patrones de file_contexts (USE_PCRE2=y
# es el default del proyecto, y la alternativa USE_PCRE2=n cae a la libpcre1
# vieja/discontinuada en vez de a algo sin dependencias — mejor compilar
# PCRE2 de una vez). Confirmada por búsqueda web el 2026-08-26 contra los
# releases reales de github.com/PCRE2Project/pcre2: la 10.47 (21/10/2025) es
# la última — un research anterior había asumido "10.48" sin verificar
# contra la página real de releases, que no existe; quedó corregido acá
# antes de escribir el script, no después de un 404 real.
export PCRE2_VERSION="10.47"

# --- Fase 4 ("Comunicaciones") ---------------------------------------------------
# zlib -> OpenSSL -> libcbor -> libfido2 -> Linux-PAM -> pam_u2f -> recompilar
# systemd con soporte de PAM/SELinux/LUKS/DNS-over-TLS/FIDO2 -> config estática
# de red. Todas las versiones verificadas por búsqueda web + fetch directo de
# la página de releases real (no de memoria) el 2026-08-27.
#
# zlib: BLFS y el propio proyecto coinciden en 1.3.2 como última estable. Su
# propio dominio (zlib.net) resultó bloqueado desde el research sandbox, pero
# el mismo tarball está republicado como asset de GitHub Release (verificado
# 200, mismo tamaño) — se usa esa URL para no depender de si zlib.net responde
# desde la red del usuario.
export ZLIB_VERSION="1.3.2"

# OpenSSL: CORREGIDO tras verificar contra la página real de releases de
# github.com/openssl/openssl — la 3.5.7 (que se había asumido antes de
# verificar) ya fue superada por la 3.5.8 (25/08/2026, dos días antes de
# escribir esto). El bug de "make install en paralelo corrompe los .so" no
# aparece documentado en el INSTALL.md de esta versión (puede ser folklore de
# la comunidad, no un bug confirmado por upstream) — se instala en serie
# igual (-j1) por las dudas, ya que el costo extra es insignificante.
export OPENSSL_VERSION="3.5.8"

# libcbor: 0.14.0 (18/07/2026). Sin tarball de "make dist" propio — sólo
# existe el archive/refs/tags crudo de GitHub, pero a diferencia de
# libcap-ng/audit-userspace esto SÍ alcanza sin autoreconf: es CMake puro
# (CMakeLists.txt ya está en el repo, no hay nada que generar).
export LIBCBOR_VERSION="0.14.0"

# libfido2: 1.17.0 (15/04/2026). Yubico publica un tarball de release real
# (no el archive crudo de GitHub) en developers.yubico.com — mismo dominio
# que ya usábamos para pam_u2f más abajo.
export LIBFIDO2_VERSION="1.17.0"

# Linux-PAM: 1.7.2. Desde ~1.6 el proyecto migró de autotools a Meson (mismo
# sistema que systemd) — el tarball de GitHub Release es el dist real
# (Linux-PAM-X.Y.Z.tar.xz, con nota explícita en el release de ignorar el
# "Source code" automático de GitHub).
export LINUX_PAM_VERSION="1.7.2"

# pam_u2f: 1.4.0 (25/03/2025, sigue siendo la última — confirmado porque el
# tab de Releases del repo de GitHub está vacío: Yubico sólo publica tarballs
# en su propio dominio, igual que libfido2).
export PAM_U2F_VERSION="1.4.0"

# libxcrypt: NUEVA dependencia agregada 2026-08-27 tras un error real de build
# (no anticipado en la investigación original de policycoreutils): glibc
# ${GLIBC_VERSION} ya no instala libcrypt.so/crypt.h (glibc lo removió a
# partir de la 2.38, delegando crypt(3) a una librería aparte) — el build
# real falló con "ld: cannot find -lcrypt" al linkear newrole/ (que cae a
# -lcrypt porque policycoreutils se compila con PAMH=n). libxcrypt es el
# reemplazo estándar. Verificado contra el release real de
# github.com/besser82/libxcrypt: el tag v4.5.2 (10/11/2025) es el último, con
# tarball de "make dist" de verdad (./configure ya generado, no un archive de
# git crudo) — confirmado bajando el tarball y corriendo
# ./configure+make+install nativo en este mismo contenedor antes de escribir
# el step, no a ciegas.
export LIBXCRYPT_VERSION="4.5.2"

# --- Fase 5 ("Infraestructura Autónoma") -----------------------------------------
# apk-tools: NUEVO hallazgo por research 2026-08-27 que cambia el plan original:
# desde la serie 3.0 apk-tools usa Meson, no el Makefile plano (el propio
# README del proyecto dice que el Makefile legacy "sólo sirve para targets
# musl-linux y se va a eliminar en el release 3.0"). Versión confirmada por
# fetch directo contra el archivo VERSION real del repo (no de memoria):
# "3.0.7" tanto en pkgs.alpinelinux.org (edge/main, build 28/07/2026) como en
# raw.githubusercontent.com/alpinelinux/apk-tools/master/VERSION.
export APK_TOOLS_VERSION="3.0.7"

# --- Fase 6 ("Interfaz Moderna"), parte 1: fundación no gráfica ------------------
# Wayland+Qt6+KDE es ENORME -- se parte en varios scripts. Esta primera parte
# cubre todo lo que hace falta ANTES de tocar Mesa/LLVM (los drivers gráficos,
# que van en su propio script por lo delicado que es cross-compilar LLVM) y
# antes de Qt6/KDE Frameworks (que van después de Mesa). Versiones
# confirmadas por fetch directo contra fuentes reales el 2026-08-27 (dos
# research pases: build systems verificados contra meson_options.txt/
# configure.ac reales vía mirrors de GitHub, no de memoria -- varios
# supuestos iniciales resultaron directamente incorrectos, ver comentarios
# puntuales en build-desktop.sh, ej. PipeWire NO tiene una opción
# "pipewire-pulseaudio", Wayland NO tiene "build-libwayland-server" separado).
#
# gitlab.freedesktop.org (donde vive el código real de dbus/polkit/wayland/
# wayland-protocols/libinput/pipewire/wireplumber/fontconfig) devolvió 403 en
# TODOS los intentos de verificación directa desde este sandbox -- mismo
# patrón que zlib.net/gitlab.alpinelinux.org en fases anteriores, no
# necesariamente algo de tu red real. Los ítems marcados "VERIFICAR" abajo
# usan la URL documentada por BLFS (el mismo linaje de proyecto que esta
# guía) o un mirror de GitHub cuando existe, pero no se pudieron confirmar
# con un 200 real -- si alguno da 404 en la build de verdad, avisame.
export LIBFFI_VERSION="3.6.0"
export EXPAT_VERSION="2.8.2"
export GLIB_VERSION="2.88.3"
export DBUS_VERSION="1.16.2"                # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export DUKTAPE_VERSION="2.7.0"               # VERIFICAR: duktape.org bloqueado en el sandbox; única dependencia dura de polkit para el motor de reglas JS
export LIBPNG_VERSION="1.6.58"
export POLKIT_VERSION="127"                  # VERIFICAR: tag-archive de GitHub, no un tarball de "make dist"
export FREETYPE_VERSION="2.14.3"
export HARFBUZZ_VERSION="14.4.0"
export FONTCONFIG_VERSION="2.18.3"           # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export PIXMAN_VERSION="0.46.4"
export CAIRO_VERSION="1.18.4"
export WAYLAND_VERSION="1.26.0"              # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export WAYLAND_PROTOCOLS_VERSION="1.49"      # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export MTDEV_VERSION="1.1.7"
export LIBEVDEV_VERSION="1.13.6"
export XKEYBOARD_CONFIG_VERSION="2.48"
export LIBINPUT_VERSION="1.31.3"             # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export LIBXKBCOMMON_VERSION="1.13.2"         # VERIFICAR: tag-archive de GitHub, no un tarball de "make dist"
# libxml2: prerequisito de xkbregistry (Fase 6 Parte 3), agregado 2026-09-04.
# Confirmado en vivo (tag real "v2.15.3" en GNOME/libxml2, sha256 real
# 5c6060277173270356c3f1c321a640ab629bdabc5e5ba9095b99e00759ba0c39, archivo
# de GitHub SÍ pisa el "v" -- extrae a "libxml2-2.15.3/").
export LIBXML2_VERSION="2.15.3"
export ALSA_LIB_VERSION="1.2.16.1"
export LUA_VERSION="5.4.8"
export PIPEWIRE_VERSION="1.6.8"              # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
export WIREPLUMBER_VERSION="0.5.15"          # VERIFICAR: gitlab.fd.o bloqueado en el sandbox

# --- Fase 6 Parte 2 (Mesa + LLVM) ----------------------------------------------
export LIBDRM_VERSION="2.4.134"              # VERIFICAR: gitlab.fd.o bloqueado en el sandbox
# LLVM: único caso de este proyecto que NO es gitlab.fd.o -- release real de
# GitHub, confirmado contra la página de assets de la versión (LLVM dejó de
# publicar tarballs por-componente hace unas versiones; hoy sólo hay
# "llvm-project-X.Y.Z.src.tar.xz", el monorepo completo -- de ahí adentro se
# compila sólo "llvm/", ver build-mesa.sh).
export LLVM_VERSION="23.1.0"
export MESA_VERSION="26.2.1"                 # VERIFICAR: gitlab.fd.o bloqueado en el sandbox, tag "mesa-X.Y.Z" no confirmado en vivo
# glslang (agregado 2026-08-31 tras un error real de build): Mesa 26.2.1
# exige "glslang >= 12.2" para compilar shaders internos con
# glslangValidator, y el glslang-tools de Debian bookworm queda por debajo
# de ese piso -- mismo motivo que ya llevó a instalar meson/rust por fuera
# de apt (Fase 2). Acá en vez de pip se compila glslang de fuente, NATIVO
# (nunca corre en el sysroot final, sólo genera código en tiempo de build),
# igual que LLVM. Release real de GitHub (KhronosGroup/glslang no está en
# gitlab.fd.o), confirmado contra la página de releases en vivo.
export GLSLANG_VERSION="16.3.0"

# --- Fase 6 Parte 2 (cont.) — Clang + SPIRV-Tools + SPIRV-LLVM-Translator ------
# Agregado 2026-09-02, decisión explícita (Opción B de docs/CONTEXTO_PENDIENTE_MESA.md,
# tomada en la PC de escritorio con 48GB de RAM): el build real de Mesa
# ${MESA_VERSION} con iris+intel_vk habilitados (RTX3060/RX7700/Intel del lab)
# activa "with_driver_using_cl" en el meson.build real de Mesa -- necesita
# compilar mesa-clc/intel_clc (compilador interno de OpenCL C -> SPIR-V que
# iris/anv usan para shaders internos). El error real ya visto en la sesión
# anterior ("Dependency 'LLVMSPIRVLib' not found") es sólo la PRIMERA de varias
# dependencias nuevas que hace falta agregar -- lo siguiente está confirmado
# leyendo el meson.build REAL de mesa-${MESA_VERSION} (extraído del propio
# mesa-${MESA_VERSION}.tar.gz ya descargado en sources/, no de un mirror
# desactualizado) en vez de asumir contra la documentación genérica de Mesa:
#
#   - dep_clang (línea ~2095 del meson.build real): NO usa
#     dependency('clang', method:'cmake') como en versiones viejas de Mesa --
#     usa cpp.find_library('clang-cpp', dirs: llvm_libdir) primero, y sólo si
#     eso falla (o si LLVM no es shared) cae a linkear ~15 librerías estáticas
#     de clang una por una. Como ya compilamos LLVM con -Dshared-llvm=enabled
#     (shared-llvm=ON en Mesa), alcanza con que exista libclang-cpp.so en el
#     sysroot -- no hace falta el binario `clang` ni sus herramientas, sólo
#     las librerías (LLVM_ENABLE_PROJECTS=clang alcanza, libclang-cpp.so se
#     construye solo en Linux, confirmado contra clang/tools/CMakeLists.txt
#     real de la tag llvmorg-${LLVM_VERSION}: la condición es sólo "UNIX AND
#     NOT CYGWIN", no depende de ningún flag extra).
#   - dep_spirv_tools (línea ~2084): SPIRV-Tools (>= 2024.1) es OBLIGATORIO
#     apenas with_clc=true -- esto NO estaba mencionado en
#     docs/CONTEXTO_PENDIENTE_MESA.md (esa nota se escribió antes de poder leer el
#     meson.build real). Es un componente nuevo, no sólo Clang+libclc+SPIRV-LLVM-
#     Translator como se había anotado ahí.
#   - dep_clc (libclc externo, línea ~985): CONFIRMADO que NO hace falta para
#     nuestra selección de drivers. Sólo se resuelve
#     "if with_gallium_rusticl or with_microsoft_clc" -- ninguno de los dos
#     está en nuestro -Dgallium-drivers=iris,radeonsi,nouveau,llvmpipe /
#     -Dvulkan-drivers=amd,intel. with_clc=true igual (por iris/intel_vk vía
#     with_driver_using_cl), pero eso sólo obliga a LLVM+clang+SPIRV-Tools+
#     LLVMSPIRVLib -- nir_load_libclc.c (el código que de verdad usa libclc)
#     sólo se agrega al build "if dep_clc.found()", y dep_clc nunca se resuelve
#     en nuestro caso. Confirmado además en
#     src/compiler/clc/meson.build real (mismo tarball). Esto SIMPLIFICA la
#     Opción B tal como se había descrito: no hace falta cross-compilar libclc
#     (la parte más pesada y delicada de compilar bitcode LLVM por-target que
#     se había anticipado) -- un componente entero menos.
#
# SPIRV-Headers: no tiene versión propia (es sólo headers + gramática JSON de
# Khronos) -- cada proyecto que lo usa fija su propio commit exacto vía su
# DEPS/config. SPIRV-Tools y SPIRV-LLVM-Translator piden commits DISTINTOS
# (confirmado leyendo el DEPS real de SPIRV-Tools y el spirv-headers-tag.conf
# real de SPIRV-LLVM-Translator, no asumiendo que son intercambiables) -- por
# eso hay dos variables separadas, una por consumidor, en vez de una sola.
export SPIRV_HEADERS_FOR_TOOLS_COMMIT="29981f65241605e08b0ede4cfeb999fe3b723c6a"      # = tag vulkan-sdk-1.4.357.0, pin real del DEPS de SPIRV-Tools v2026.3
export SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT="575b6512579ebde466ed3dfc04e413439d14d95d" # pin real de spirv-headers-tag.conf en la rama llvm_release_230

# SPIRV-Tools: el propio README dice "GitHub releases are deprecated" -- no hay
# tarball de "make dist", se usa el archive/refs/tags crudo (mismo patrón que
# libcap-ng/audit-userspace/libcbor/polkit/libxkbcommon en este proyecto).
# Versión confirmada por `git ls-remote --tags` en vivo contra el repo real
# (no de memoria): último tag real "v2026.3" (2026-09), sobra para el piso
# ">= 2024.1" que pide Mesa. CMake real de esta tag confirmado además:
# SPIRV_SKIP_EXECUTABLES=ON implica SPIRV_SKIP_TESTS=ON y evita necesitar
# googletest/effcee/re2/protobuf/abseil (sólo hacen falta para los tests) --
# sólo se compila la librería, que es todo lo que Mesa necesita.
export SPIRV_TOOLS_VERSION="2026.3"

# SPIRV-LLVM-Translator: NO usa un esquema de tags con fecha como SPIRV-Tools
# -- usa branches "llvm_release_XXX" (uno por versión mayor de LLVM), y el
# wiki de releases del repo está desactualizado (se dejó de mantener después
# de la v11). Confirmado por `git ls-remote --heads` en vivo: existe
# "llvm_release_230" (LLVM 23.x), y su CMakeLists.txt real fija
# BASE_LLVM_VERSION=23.1.0 -- coincide EXACTO con nuestro LLVM_VERSION, así
# que es la rama correcta, no una suposición por continuidad numérica. Se fija
# el commit exacto que esa rama tenía en el momento de este research (en vez
# de "la punta de la rama", que se puede mover) -- mismo criterio de
# reproducibilidad que el resto de este proyecto.
export SPIRV_LLVM_TRANSLATOR_COMMIT="c808623558686b7b285cabfa71542a93a5390f55" # HEAD de llvm_release_230 al momento de este research (2026-09-02)

# --- Fase 6 Parte 2 (cont.) — elfutils (libelf) --------------------------------
# Agregado 2026-09-02, Décimo quinto error real: con LLVM+Clang y
# SPIRV-LLVM-Translator ya completos en el sysroot, el "meson setup" de Mesa
# frenó en "Gallium driver radeonsi requires libelf" -- el driver Gallium de
# AMD (elegido para la RX 7700 del lab) usa libelf en su runtime linker de ELF
# (src/amd/common, para relocar los binarios que produce el propio backend
# AMDGPU de LLVM al compilar shaders). Ningún paso anterior del proyecto
# compiló libelf para el target -- el "libelf-dev" del Dockerfile es del
# compilador NATIVO del contenedor, no sirve para un build cruzado.
#
# VERIFICAR: sourceware.org devolvió 403 desde el sandbox de research (mismo
# problema que ya tuvieron zlib.net/gitlab.fd.o con este proyecto -- ver
# comentarios de ZLIB/LIBDRM/MESA más arriba), así que la versión se confirmó
# indirecto, contra la portada real de sourceware.org/elfutils (que linkea
# "0.191" como último release) en vez de por fetch directo del tarball -- pero
# LVM2_MIRROR y BZIP2_MIRROR de este mismo archivo ya usan sourceware.org con
# éxito en corridas reales de este proyecto, así que el dominio en sí no es
# problema para el contenedor del usuario, sólo para este sandbox puntual.
export ELFUTILS_VERSION="0.191"

# --- Fase 6 Parte 3 (Qt6 + KDE Frameworks/Plasma) — decisiones tomadas
# 2026-09-04, research completo contra fuentes reales antes de escribir nada
# (invent.kde.org y github.com/qt SÍ accesibles desde este sandbox, a
# diferencia de gitlab.freedesktop.org/gitlab.gnome.org de research anteriores
# -- confirmado en vivo, no asumido). Ver docs/PENDIENTES.md para el mapa
# completo de dependencias por tier.
#
# Qt6 6.11.2: último release estable real (confirmado contra los tags de
# github.com/qt/qtbase) -- supera cómodo el mínimo real que pide kwin/
# plasma-workspace (QT_MIN_VERSION 6.10.0, leído directo de sus
# CMakeLists.txt reales). Mismo criterio de "vanguardia" ya usado en el
# resto del proyecto: última versión real, no el piso mínimo de un
# consumidor. Placeholder acá -- step_qtbase()/etc. todavía no están
# escritos, es el próximo bloque de trabajo real después de ECM.
export QT6_VERSION="6.11.2"
#
# KDE Frameworks 6 (KF6) + "tren de Plasma": KF6_MIN_VERSION real de kwin es
# 6.27.0, el de plasma-workspace 6.26.0 -- se fija el tren completo en
# 6.29.0, el último REALMENTE PUBLICADO en download.kde.org/stable/frameworks/
# (confirmado en vivo listando ese directorio: hasta 6.29/, la rama "master"
# de los repos individuales ya apunta a 6.30.0 sin publicar todavía, no sirve
# como fuente de versión real). extra-cmake-modules (ECM) es parte de este
# mismo tren de versiones.
export KDE_VERSION="6.29.0"
#
# ECM (extra-cmake-modules): el módulo de CMake base que necesita CUALQUIER
# paquete de KDE Frameworks/Plasma para configurarse -- confirmado en vivo
# bajando su tarball real de la 6.29.0 (extra-cmake-modules-6.29.0.tar.xz).
# BLOQUEANTE real encontrado: su propio CMakeLists.txt pide
# "cmake_minimum_required(VERSION 3.29)" -- el cmake de apt de este proyecto
# (Debian bookworm) es 3.25.1, no alcanza (confirmado con "cmake --version"
# real adentro del contenedor). Mismo criterio que meson/Rust: cmake más
# nuevo por pip en el Dockerfile (ver comentario ahí), no depender de la
# versión de apt.
export ECM_VERSION="${KDE_VERSION}"
#
# iso-codes: prerequisito real de ki18n (Tier 2 KF6) -- paquete de datos de
# códigos ISO de idiomas/países/monedas. Upstream real es salsa.debian.org
# (Debian iso-codes-team), no un mirror -- confirmado bajando el tag real
# v4.20.1 en vivo (extrae a "iso-codes-v4.20.1/", el archive de GitLab SÍ
# mantiene el prefijo "v" en el nombre, a diferencia de GitHub).
export ISOCODES_VERSION="4.20.1"
#
# PlasmaWaylandProtocols: prerequisito real de kguiaddons/kidletime/
# kwindowsystem (Tier 2 KF6) para su soporte Wayland -- NO es parte del
# tren de KDE Frameworks (versionado aparte) y no tiene tarball en
# download.kde.org/stable/plasma/ pese a aparecer listado ahí (confirmado
# 404 real). Fuente real: mirror de GitHub KDE/plasma-wayland-protocols
# -- mismo patrón archive/refs/tags que ya usa este proyecto para paquetes
# sin tarball de "make dist" (libxkbcommon, glslang).
# Bump real 2026-09-16: KWayland (Tier 3) pide >= 1.22.0 -- más nuevo que
# el 1.21.0 fijado originalmente para kwin. Confirmado tag real v1.22.0
# (10-sep-2026) en github.com/KDE/plasma-wayland-protocols/tags -- se
# sube el pin entero del proyecto a 1.22.0 (satisface también a kwin, que
# sólo pide >= 1.21.0) y se recompila el paso una vez.
export PLASMA_WAYLAND_PROTOCOLS_VERSION="1.22.0"
#
# zstd: prerequisito real de karchive (Tier 2 KF6), encontrado en la
# corrida real -- confirmado tag/release real v1.5.7 de facebook/zstd.
export ZSTD_VERSION="1.5.7"
#
# liblzma (xz): SEGUNDO prerequisito real de karchive, encontrado en la
# corrida real inmediatamente después de zstd -- confirmado release real
# v5.8.3 de tukaani-project/xz (el upstream real del proyecto).
export LIBLZMA_VERSION="5.8.3"
#
# libtool (libltdl): prerequisito real de libcanberra, encontrado en la
# corrida real -- sólo se compila el subdirectorio libltdl/, no el
# libtool completo (el script libtool/ltmain.sh que ya usa cada
# ./configure de este proyecto es otra cosa, generado por autoreconf en
# cada paquete). Última release real de GNU (ftp.gnu.org/gnu/libtool).
export LIBTOOL_VERSION="2.6.2"
#
# libcanberra: prerequisito REQUIRED real de knotifications (Tier 2b KF6),
# no opcional como se había anotado originalmente para plasma-workspace.
# El proyecto está congelado en 0.30 desde hace años (mismo release que
# usa Debian hoy, confirmado contra sources.debian.org) -- no hay ningún
# fork "oficial" más nuevo.
export LIBCANBERRA_VERSION="0.30"
#
# libogg + libvorbis: prerequisitos reales de libcanberra ("Vorbis
# (mandatory)" en su configure.ac), encontrados en la corrida real.
# Últimas releases reales de Xiph.Org.
export LIBOGG_VERSION="1.3.6"
export LIBVORBIS_VERSION="1.3.7"
#
# Decisión XWayland/X11 (2026-09-04): SACADO por completo, Wayland puro.
# No es una preferencia técnica improvisada -- el propio documento
# fundacional del proyecto (docs/LINSI-OS.pdf, Pilar 5 "Vanguardia",
# sección 2.5) lo dice explícito: "en lugar de mantener compatibilidad con
# X11 ... LINSI-OS se construye exclusivamente sobre Wayland", y la sección
# 6 ("Originalidad") lo repite: "sin arrastrar compatibilidad con X11 ni
# PulseAudio". kwin trae XWayland/X11 prendido por defecto
# (KWIN_BUILD_X11=ON en su CMakeLists.txt real) -- cuando se llegue a
# step_kwin(), va con KWIN_BUILD_X11=OFF a propósito, sin libxcb/Xwayland en
# el sysroot.

# Plasma (el "tren de Plasma", Tier 3): versionado APARTE de KDE Frameworks
# -- confirmado listando en vivo download.kde.org/stable/plasma/, la última
# versión REALMENTE publicada ahí es 6.7.4 (2026-08-04), release posterior a
# 6.7.0-6.7.3 y a toda la serie 6.6.x. Sus CMakeLists.txt reales (libplasma,
# plasma-activities) piden KF6_MIN_VERSION 6.26.0 -- el 6.29.0 ya compilado
# en este proyecto lo supera cómodo. Mismo tarball-naming que KF6:
# "<paquete>-6.7.4.tar.xz" bajo download.kde.org/stable/plasma/6.7.4/.
export PLASMA_VERSION="6.7.4"

# KirigamiAddons (Tier 3): versionado APARTE del tren de Plasma Y de KDE
# Frameworks -- su propio ciclo de release independiente, confirmado
# listando en vivo download.kde.org/stable/kirigami-addons/ (última
# versión real: 1.13.1, 2026-07-20). Repo real bajo "libraries/" en
# invent.kde.org, no "frameworks/" (donde 404 primero).
export KIRIGAMI_ADDONS_VERSION="1.13.1"

# libnl (Tier 3): prerequisito real REQUIRED de libksysguard ("Used for
# gathering socket info via the sock_diag netlink subsystem", confirmado
# contra su CMakeLists.txt real). Última release real:
# github.com/thom311/libnl/releases, tag "libnl3_12_0" (04-dic-2025).
export LIBNL_VERSION="3.12.0"

# lm-sensors / libsensors (Tier 3): prerequisito real REQUIRED de
# libksysguard ("Used for reading hardware sensors"). Build system NO
# estándar (ni autotools ni CMake ni Meson) -- Makefile plano propio,
# cross-compilable pisando CC/AR por línea de comandos (confirmado
# leyendo el Makefile real: "CC := gcc", sin ningún --host= de por
# medio). Última tag real: github.com/lm-sensors/lm-sensors/tags,
# "V3-6-2" (13-ene-2024) -- el proyecto no tuvo release nueva desde
# entonces, no es que se haya fijado una vieja a propósito.
export LMSENSORS_VERSION="3.6.2"

# libepoxy (Tier 3): prerequisito real REQUIRED de kwin (dispatch de
# funciones GL/GLES/EGL en tiempo de ejecución) -- confirmado contra el
# CMakeLists.txt real de kwin. Meson, sin dependencias obligatorias
# (EGL/GL/X11 opcionales, confirmado contra su meson.build real). Última
# release real: github.com/anholt/libepoxy/releases, "1.5.10"
# (18-mar-2024). Sin tarball de "make dist" real (no hace falta, es
# Meson, el meson.build ya está en el repo) -- se usa el archive crudo
# del tag, que NO pisa nada porque el tag no tiene prefijo "v" (extrae a
# "libepoxy-1.5.10/" tal cual, confirmado en vivo).
export LIBEPOXY_VERSION="1.5.10"

# lcms2 / Little CMS (Tier 3): prerequisito real REQUIRED de kwin
# (gestión de color). Autotools, tarball real de "make dist" (no un
# archive crudo de tag). Última release real:
# github.com/mm2/Little-CMS/releases, tag "lcms2.19.1" (06-may-2025) --
# nombre de tag inusual (con punto en vez de guion), confirmado en vivo
# vía el enlace de descarga real del asset:
# ".../releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz".
export LCMS2_VERSION="2.19.1"
export LCMS2_TAG="lcms2.19.1"

# libdisplay-info (Tier 3): prerequisito real REQUIRED de kwin (parseo de
# EDID/DisplayID de monitores, >= 0.2.0 según kwin). Meson, sin
# dependencias (confirmado). Última release real: 0.4.0 (jul-2026),
# fuente real gitlab.freedesktop.org/emersion/libdisplay-info (bloqueado
# por robots.txt en el sandbox de research vía navegador, pero la URL de
# descarga directa puede funcionar igual desde el contenedor -- si falla,
# hay un mirror de GitHub de terceros: github.com/sepnic/libdisplay-info).
export LIBDISPLAYINFO_VERSION="0.4.0"

# hwdata (Tier 3): prerequisito real REQUIRED de libdisplay-info --
# descubierto recién al intentar el build real ("File
# /usr/share/hwdata/pnp.ids does not exist"), no estaba en ningún mapa
# anterior. Pura data (pci.ids/usb.ids/pnp.ids, sin código que compilar),
# Makefile propio con un ./configure real (no autoconf, un script shell
# custom, "prefix=/usr" ya es el default). Última release real:
# github.com/vcrhonek/hwdata/releases, tag "v0.411" (04-sep-2026).
export HWDATA_VERSION="0.411"

# Vulkan-Headers + Vulkan-Loader (Tier 4, kwin): "find_package(Vulkan
# REQUIRED)" real de kwin, descubierto recién al intentar el build real
# de kwin ("Could NOT find Vulkan"). Se creía cubierto por Mesa (Fase 6
# Parte 2) pero Mesa sólo instala los DRIVERS ICD (libvulkan_radeon.so/
# libvulkan_intel.so + los manifests /usr/share/vulkan/icd.d/*.json) --
# el LOADER real (libvulkan.so, lo que las apps linkean, que dlopen-ea
# el ICD correcto en runtime) y los headers (vulkan/vulkan.h) son DOS
# proyectos aparte de KhronosGroup, nunca compilados. Sin CMakeLists.txt
# real leído (invent.kde.org no aplica acá, son repos de Khronos, no de
# KDE) -- confirmado contra github.com/KhronosGroup/Vulkan-Headers y
# Vulkan-Loader directamente. Ambos taggean en lockstep con el mismo
# número de versión (confirmado: la tag más reciente de los dos es
# idéntica, "v1.4.362" al momento de fijar este pin) -- se usa la más
# reciente de ambos ya que no están atados a ningún tren de KDE/Plasma.
export VULKAN_HEADERS_VERSION="1.4.362"
export VULKAN_LOADER_VERSION="1.4.362"

# libxcvt (Tier 4, kwin): "pkg_check_modules(Libxcvt IMPORTED_TARGET
# libxcvt>=0.1.1 REQUIRED)" real de kwin (CMakeLists.txt:334) --
# descubierto igual que Vulkan, recién al CORRER el build real de kwin
# (no estaba en el mapa de find_package() original porque es
# pkg_check_modules, no find_package). Pese al nombre (viene del mundo
# Xorg/DRM), es sólo la librería del algoritmo VESA CVT para generar
# modelines de video -- matemática pura, sin ningún vínculo con X11/XCB
# real (confirmado leyendo su meson.build real: única dep es libm).
# gitlab.freedesktop.org bloquea la navegación (Anubis) pero la
# descarga directa del tarball SÍ funciona (mismo caso ya documentado
# para libdisplay-info) -- confirmado con un wget real. Última versión
# real: Arch Linux empaqueta 0.1.3 (gitlab.freedesktop.org/xorg/lib/
# libxcvt no lista releases navegables por el bloqueo de Anubis).
export LIBXCVT_VERSION="0.1.3"

# QCoro6 (Tier 5, plasma-workspace): "find_package(QCoro6 REQUIRED
# COMPONENTS Core)" real (CMakeLists.txt de plasma-workspace 6.7.4) --
# wrapper de corutinas de C++20 sobre Qt6 (github.com/danvratil/qcoro),
# proyecto independiente sin ningún tren de KDE/Qt. Última tag real:
# v0.13.0.
export QCORO_VERSION="0.13.0"

# ICU4C (Tier 5, plasma-workspace): "find_package(ICU COMPONENTS i18n
# uc)" con TYPE REQUIRED real. Build autotools de dos pasadas para
# cross-compilar (documentado oficialmente en unicode-org.github.io/
# icu/userguide/icu4c/build.html): primero un build NATIVO completo
# (con "runConfigureICU Linux"), después el build cruzado real pasando
# "--with-cross-build=<dir del build nativo>" -- ICU necesita las
# herramientas nativas compiladas (genrb, gennorm2, etc.) para generar
# datos durante SU PROPIO build cruzado, no sólo para correr. Última
# release real: 78.3 (unicode-org/icu, tag "release-78.3"; el asset de
# fuentes completas es "icu4c-78.3-sources.tgz", confirmado con el
# Browser tool ya que la lista de assets de GitHub no carga vía
# WebFetch -- mismo caso ya visto con libepoxy/lcms2).
export ICU_VERSION="78.3"

# libqrencode (Tier 5, Prison -- dependencia real de plasma-workspace):
# "find_package(QRencode)" SIEMPRE REQUIRED en Prison (sin ninguna
# opción para sacarlo), confirmado contra su CMakeLists.txt real
# (invent.kde.org/frameworks/prison). Proyecto independiente
# (github.com/fukuchi/libqrencode), última tag real: v4.1.1.
export LIBQRENCODE_VERSION="4.1.1"

# libgpg-error + libgcrypt (Tier 5, KWallet -- dependencia real de
# plasma-workspace): "find_package(LibGcrypt 1.5.0 REQUIRED)" real en
# src/runtime/kwalletbackend/CMakeLists.txt ("kwalletd needs libgcrypt
# to perform PBKDF2-SHA512 hashing") -- confirmado que NO es opcional
# (a diferencia de Gpgmepp/GPGME, que sí lo es -- "if (Gpgmepp_FOUND)",
# sin REQUIRED -- se deja sin construir, wallet vía GPG queda
# deshabilitado, sólo el backend gcrypt clásico). Ambos son releases
# clásicas de GnuPG (gnupg.org/ftp/gcrypt/), Autotools puro.
export LIBGPGERROR_VERSION="1.61"
export LIBGCRYPT_VERSION="1.12.4"

# libsecret (Tier 5, KWallet -- dependencia real de plasma-workspace):
# "pkg_check_modules(LIBSECRET REQUIRED libsecret-1)" real en
# src/runtime/kwalletd/CMakeLists.txt, sin ninguna opción para
# sacarlo. Proyecto GNOME (download.gnome.org/sources/libsecret/) --
# convención de versionado GNOME clásica: minor PAR = estable ("0.20"),
# minor IMPAR = desarrollo ("0.21", visto en el listado real pero
# descartado a propósito). Última estable real: 0.20.5 (confirmado con
# el archivo "LATEST-IS-0.20.5" real del servidor). Meson, deps reales
# (glib-2.0/gio-2.0/gio-unix-2.0, ya en el sysroot desde fases
# anteriores; libgcrypt, recién construido) -- soporte TPM2 (tss2-*) es
# opcional y no se pide.
export LIBSECRET_VERSION="0.20.5"

# libndp (Tier 5, NetworkManager -- dependencia real de
# KF6NetworkManagerQt): "dependency('libndp')" SIEMPRE REQUIRED (sin
# "required: false") en el meson.build real de NetworkManager --
# implementa IPv6 Neighbor Discovery Protocol. Proyecto chico e
# independiente (github.com/jpirko/libndp), Autotools con
# "autogen.sh" (el tarball de GitHub no trae "configure" pre-generado,
# hace falta "autoreconf"). Última tag real: v1.9.
export LIBNDP_VERSION="1.9"

# NetworkManager (Tier 5): "pkg_search_module(NetworkManager REQUIRED
# IMPORTED_TARGET libnm>=1.4.0)" real en KF6NetworkManagerQt -- sin
# ninguna opción para evitarlo en Linux. Meson. Se compila con el
# máximo de subsistemas opcionales apagados (wifi se deja, no agrega
# dependencia dura real; ppp/modem_manager/ovs/nmtui/nm_cloud_setup/
# introspection/vapi/qt/tests/docs apagados -- ninguno tiene consumidor
# real todavía) para minimizar superficie, ya que sólo hace falta la
# librería cliente "libnm" para que KF6NetworkManagerQt compile, no
# NetworkManager funcionando de verdad como daemon de red del sistema
# (eso queda pendiente de decisión aparte, fuera del alcance de
# "hacer compilar Fase 6 Parte 3"). Real última estable (par, según
# convención de versionado de NetworkManager -- impar = desarrollo):
# 1.50.0 (download.gnome.org/sources/NetworkManager/1.50/, confirmado
# con el archivo "LATEST-IS-1.50.0" real).
export NETWORKMANAGER_VERSION="1.50.0"

# polkit-qt-1 (Tier 5, plasma-workspace): "find_package(PolkitQt6-1)"
# con TYPE REQUIRED real ("Communicate with localegen helper in region
# & lang kcm"). Proyecto independiente (download.kde.org/stable/
# polkit-qt-1/, sin carpeta de versión que siga KDE_VERSION) -- Qt6
# Core/DBus/Widgets nada más, todo ya en el sysroot.
export POLKITQT1_VERSION="0.201.1"

# Escritorio usable (2026-10-22) -- dependencias de terceros de plasma-pa y
# plasma-nm (ver docs/PENDIENTES.md, "Escritorio usable"):
# - libsndfile: dependency('sndfile') SIN condición en el meson.build real
#   de pulseaudio (línea 615), aunque sólo se compile el cliente. Último
#   release real con tarball en github.com/libsndfile/libsndfile/releases.
# - pulseaudio: SÓLO la librería cliente (-Ddaemon=false) -- plasma-pa pide
#   libpulse + libpulse-mainloop-glib; habla con pipewire-pulse, no hay
#   servidor PulseAudio. 17.0 es el último de
#   freedesktop.org/software/pulseaudio/releases/ (listado en vivo).
# - pulseaudio-qt: plasma-pa pide KF6PulseAudioQt >= 1.6.0.
# - qtkeychain: plasma-nm pide Qt6Keychain >= 0.16.0 (tag real en GitHub).
# - ModemManager: plasma-nm pide ModemManagerQt sin condición. 1.24.2 es el
#   último estable (las 1.25.x son "-dev", preliminares de la 1.26) --
#   confirmado con la API de tags de gitlab.freedesktop.org; desde 1.20 ya
#   no publican tarballs en freedesktop.org/software/ModemManager/ (ahí se
#   corta en 1.18.12), así que se usa el archive del tag.
export LIBSNDFILE_VERSION="1.2.2"
export PULSEAUDIO_VERSION="17.0"
export PULSEAUDIO_QT_VERSION="1.9.0"
export QTKEYCHAIN_VERSION="0.17.0"
export MODEMMANAGER_VERSION="1.24.2"
# - Boost: kactivitymanagerd pide "find_package(Boost 1.58 REQUIRED)" y sólo
#   usa boost/range (header-only, confirmado con grep de sus #include), así
#   que alcanza con los headers. 1.92.0 = último release real de
#   github.com/boostorg/boost/releases (API en vivo).
export BOOST_VERSION="1.92.0"
# Impresión (2026-10-22, decisión de Juani: "CUPS + filtros, sin
# ghostscript"): CUPS 2.4.20 (libcups + cupsd) y la pila de filtros de
# OpenPrinting. libcupsfilters 2.2 pide PDFio sin condición (reemplazó a
# qpdf). Últimos releases reales en github.com/OpenPrinting/* y
# github.com/michaelrsweet/pdfio (API en vivo). libcupsfilters 2.1.2 es más
# NUEVO por fecha (2026-10-05) pero es mantenimiento de la rama 2.1; se usa
# la 2.2.1, que es la que pide PDFio.
export PDFIO_VERSION="1.6.5"
export CUPS_VERSION="2.4.20"
export LIBCUPSFILTERS_VERSION="2.2.1"
export LIBPPD_VERSION="2.1.1"
export CUPS_FILTERS_VERSION="2.0.1"
# Multimedia (2026-10-27): kpipewire pide FFmpeg (libavcodec/avformat/
# avfilter/avutil/swscale) y libva/libva-drm sin condición (pkg_check_modules
# REQUIRED en su CMakeLists.txt real). kpipewire es dependencia de runtime
# (import QML org.kde.pipewire) del selector de pantalla de
# xdg-desktop-portal-kde, de las miniaturas de la barra de tareas y del
# indicador de cámara. Últimos releases reales: ffmpeg.org/releases/ y
# github.com/intel/libva (API en vivo).
export LIBVA_VERSION="2.24.1"
export FFMPEG_VERSION="9.0.2"
# KDE Gear (release-service) -- Konsole y Dolphin. 26.08.2 = último listado
# en download.kde.org/stable/release-service/.
export KDE_GEAR_VERSION="26.08.2"

# libxcb (Tier 3, retrofit real 2026-09-04): libplasma v6.7.4 tiene un bug
# real de upstream -- src/plasma/private/blureffectwatcher_p.h hace
# "#include <xcb/xcb.h>" SIN ningún guard de preprocesador, aunque el uso
# real de X11 en ese archivo sí está guardeado con "#if HAVE_X11"
# (confirmado leyendo el archivo real de la tag v6.7.4 en invent.kde.org).
# Como este proyecto no define HAVE_X11 en ningún lado (decisión Wayland
# puro, ver más arriba), ese código queda deshabilitado en runtime -- pero
# el header igual hace falta para que compile. Se decidió (con el usuario)
# compilar un libxcb real y mínimo (sin XWayland, sin Xlib, sin servidor
# X) sólo para satisfacer este include -- nunca se linkea en runtime real.
# Cadena de dependencias real (xorg.freedesktop.org, accesible en vivo a
# diferencia de gitlab.freedesktop.org): xorgproto (headers puros) ->
# libXau + libXdmcp (bases de autenticación X, paquetes chicos) ->
# xcb-proto (specs XML + módulo python "xcbgen", sin código compilado) ->
# libxcb en sí. Versiones: últimas reales publicadas en
# xorg.freedesktop.org/archive/individual/ (confirmado en vivo listando
# ese directorio).
export XORGPROTO_VERSION="2025.1"
export LIBXAU_VERSION="1.0.12"
export LIBXDMCP_VERSION="1.1.5"
export XCBPROTO_VERSION="1.17.0"
export LIBXCB_VERSION="1.17.0"

# xcb-util + xcb-util-image (2026-10-22): plasma-desktop 6.7.4 pide "XCB
# REQUIRED COMPONENTS XCB SHM IMAGE"; IMAGE sale de xcb-util-image, que
# depende de xcb-util. Últimas versiones reales en
# xorg.freedesktop.org/archive/individual/xcb/ (listado en vivo). libX11 y
# libxkbfile se llegaron a compilar y se descartaron -- ver
# docs/PENDIENTES.md, "Escritorio usable".
export XCB_UTIL_VERSION="0.4.1"
export XCB_UTIL_IMAGE_VERSION="0.4.1"

# --- Rutas --------------------------------------------------------------------
export LFS="${LFS:-/lfs}"
export LFS_SOURCES="${LFS}/sources"
export LFS_TOOLS="${LFS}/tools"
export LFS_BUILD="${LFS}/build"
# Logs: agregado 2026-08-27 a pedido — bind mount nuevo (./logs:/lfs/logs en
# docker-compose.yml, a diferencia de /lfs/tools, /lfs/build, /lfs/usr, que
# son volúmenes con nombre de Podman, sin ruta directa en Windows) para que
# cada corrida quede guardada como archivo normal dentro de
# C:\Users\...\LINSIOS\linsi-os\logs\ — entrypoint.sh es quien arma el nombre
# del archivo y hace el tee, no cada script individual, así queda una sola
# vez para las cuatro fases (Fase 0 a 3) y para cualquier fase futura.
export LFS_LOGS="${LFS}/logs"

# --- Triplet del cross-compiler propio de LINSI-OS -----------------------------
export LFS_TGT="${LFS_TGT:-x86_64-linsi-linux-gnu}"

# --- PATH: el cross-toolchain recién compilado tiene prioridad -----------------
export PATH="${LFS_TOOLS}/bin:${PATH}"

# --- PATH (agregado Fase 6, 2026-08-27): binarios ya instalados en el sysroot --
# A partir de Fase 6 empiezan a aparecer herramientas que son A LA VEZ parte
# del sistema final Y necesarias en tiempo de BUILD para paquetes posteriores
# (wayland-scanner genera código a partir de los XML de wayland-protocols,
# glib-compile-resources/gdbus-codegen los va a pedir Qt6/KDE más adelante,
# etc.) -- el patrón "GLib necesita glib-genmarshal del BUILD machine" que
# describe la propia documentación de cross-compiling de Meson.
#
# CORREGIDO (2026-08-29) -- la idea original de este comentario era: "en un
# cross-compile real (arquitecturas distintas) esas herramientas del build
# machine se compilan aparte, nativas; acá no hace falta ese lío porque
# LFS_TGT es la MISMA arquitectura que el host (x86_64), así que el propio
# binario recién cross-compilado corre perfecto en este mismo contenedor".
# Un build real de wireplumber demostró que eso es FALSO en general: un
# binario cross-compilado (glib-compile-resources) SÍ se pudo ejecutar
# (misma arquitectura, el exec no falla), pero reventó al cargar sus
# librerías ("libgio-2.0.so.0: cannot open shared object file") porque
# están linkeadas contra el glibc CROSS-compilado de Fase 2, que vive en
# ${LFS_SYSROOT}, no contra el glibc real del contenedor -- y como nunca se
# chrootea a /lfs, el linker dinámico real del contenedor no las encuentra.
# Misma arquitectura no implica mismo glibc ni mismo entorno de carga; sólo
# funciona sin dramas para binarios que no dependen de librerías del propio
# sysroot (por eso wayland-scanner sí se resuelve, pero como build NATIVO
# aparte -- ver step_wayland() -- no ejecutando el cross-compilado).
#
# Esta entrada de PATH se deja igual (no molesta, y hace falta para que
# Meson encuentre herramientas del sysroot que si son seguras de ejecutar
# así), pero la lección es: si una herramienta de build falla con "error
# while loading shared libraries" al correr desde ${LFS_SYSROOT}/usr/bin, la
# solución NO es tocar LD_LIBRARY_PATH -- es conseguir una versión
# genuinamente nativa (paquete de apt, como libglib2.0-dev-bin, o un build
# nativo aparte, como wayland-scanner) que el PATH encuentre primero (por
# eso este PATH se agrega DESPUÉS de todo lo demás, ${LFS_TOOLS}/bin
# incluido: para que una alternativa nativa siempre gane si existe).
export PATH="${PATH}:${LFS_SYSROOT:-${LFS:-/lfs}}/usr/bin"

# --- Paralelismo de compilación ------------------------------------------------
# GCC pass1 (Fase 0) compila unidades pesadas —genautomata, c-family/c-common.cc,
# gimple-match-N.cc, generic-match-N.cc— que solas pueden pisar 1.5-2.5 GB de RAM
# cada una. Si se lanzan tantos jobs como cores (-j$(nproc)) pero la VM de
# Podman/Docker Desktop tiene poca RAM, el kernel mata esos procesos (OOM,
# "Killed signal terminated program cc1plus", exit 137) a mitad de compilación.
#
# Por eso el techo de jobs sale del mínimo entre nproc y (RAM disponible / 2GB),
# nunca menos de 1. Se puede pisar a mano si hace falta más o menos margen:
#   docker compose run --rm -e MAKEFLAGS=-j2 builder scripts/build-cross-toolchain.sh all
if [[ -z "${MAKEFLAGS:-}" ]]; then
    NPROC="$(nproc)"
    MEM_KB="$(awk '/MemAvailable/{print $2; exit} /MemTotal/{t=$2} END{if (!$0 && t) print t}' /proc/meminfo 2>/dev/null || echo 0)"
    [[ -z "${MEM_KB}" || "${MEM_KB}" -le 0 ]] && MEM_KB=2097152   # fallback: asumí 2GB si no se puede leer
    MEM_GB=$(( MEM_KB / 1024 / 1024 ))
    JOBS_BY_MEM=$(( MEM_GB / 2 ))
    if [[ "${JOBS_BY_MEM}" -lt 1 ]]; then
        JOBS_BY_MEM=1
    fi
    JOBS="${NPROC}"
    if [[ "${JOBS_BY_MEM}" -lt "${JOBS}" ]]; then
        JOBS="${JOBS_BY_MEM}"
    fi
    export MAKEFLAGS="-j${JOBS}"
    echo "[env] RAM disponible ~${MEM_GB}GB, ${NPROC} cores -> MAKEFLAGS=${MAKEFLAGS} (pisalo con -e MAKEFLAGS=-jN si hace falta)" >&2
else
    export MAKEFLAGS="${MAKEFLAGS}"
fi

# Mirrors de descarga (con fallback a GNU si el mirror falla)
export GNU_MIRROR="https://ftpmirror.gnu.org"
export KERNEL_MIRROR="https://cdn.kernel.org/pub/linux/kernel/v7.x"
export SYSTEMD_MIRROR="https://github.com/systemd/systemd/archive/refs/tags"
export ZSH_MIRROR="https://downloads.sourceforge.net/project/zsh/zsh"
export UTIL_LINUX_MIRROR="https://www.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION%.*}"
export LIBCAP_MIRROR="https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2"
export SAVANNAH_MIRROR="https://download-mirror.savannah.gnu.org/releases"
export UUTILS_MIRROR="https://github.com/uutils/coreutils/archive/refs/tags"
export LIBMNL_MIRROR="https://www.netfilter.org/projects/libmnl/files"
export LIBNFTNL_MIRROR="https://www.netfilter.org/projects/libnftnl/files"
export NFTABLES_MIRROR="https://www.netfilter.org/projects/nftables/files"
# CORREGIDO 2026-08-26: probé primero releases/download/vX.Y/<nombre>-X.Y.tar.gz
# asumiendo un tarball "de verdad" (con ./configure ya generado vía "make
# dist", como systemd/uutils NO hacen falta pero GNU/netfilter sí publican) —
# dio 404 en la build real del usuario. Confirmé después contra la propia
# página de assets de cada release (releases/expanded_assets/vX.Y) que NI
# libcap-ng NI audit-userspace suben un tarball propio: sólo existen los dos
# "Source code (zip/tar.gz)" que GitHub genera automático del propio tag, es
# decir, el archive/refs/tags crudo — mismo mecanismo que ya usamos para
# systemd y uutils. La diferencia importante es que ESE tarball NO trae un
# ./configure generado (a diferencia de libmnl/libnftnl/nftables, que sí
# publican un dist real): por eso step_libcap_ng()/step_audit() corren
# autoreconf antes de ./configure (ambos proyectos confirman en su propio
# README que así se construye desde fuente de git: libcap-ng con
# "./autogen.sh", audit-userspace con "autoreconf -f --install" — y el
# Dockerfile de Fase 0 ya tiene autoconf/automake/libtool instalados).
export LIBCAP_NG_MIRROR="https://github.com/stevegrubb/libcap-ng/archive/refs/tags"
export AUDIT_MIRROR="https://github.com/linux-audit/audit-userspace/archive/refs/tags"

# libargon2: igual que libcap-ng/audit-userspace, sólo existe el archive
# crudo de GitHub (no publica un tarball de "make dist") — pero a diferencia
# de esos dos, NO hace falta autoreconf: es un Makefile plano (CC=/PREFIX=/
# DESTDIR=), no autotools.
export LIBARGON2_MIRROR="https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags"
# popt, LVM2 y cryptsetup sí publican tarballs de release "de verdad" (con
# ./configure ya generado) — mirrors confirmados contra BLFS.
export POPT_MIRROR="https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x"
export LVM2_MIRROR="https://sourceware.org/ftp/lvm2"
export CRYPTSETUP_MIRROR="https://www.kernel.org/pub/linux/utils/cryptsetup/v${CRYPTSETUP_VERSION%.*}"
# json-c: CMake, no autotools — confirmado contra BLFS.
export JSON_C_MIRROR="https://s3.amazonaws.com/json-c_releases/releases"
# libaio: tarball de release real (con Makefile listo, no un archive de
# git) — confirmado contra el índice de releases.pagure.org/libaio/. A
# diferencia de casi todo el resto de este proyecto, su Makefile NO
# respeta DESTDIR (ver step_libaio en build-security.sh): prefix/
# includedir/libdir se pisan directo apuntando adentro del sysroot.
export LIBAIO_MIRROR="https://releases.pagure.org/libaio"

# SELinux: un solo mirror para los cinco componentes (mismo repo, mismo tag),
# assets reales de GitHub Release, no un archive/refs/tags crudo.
export SELINUX_MIRROR="https://github.com/SELinuxProject/selinux/releases/download/${SELINUX_VERSION}"

# bzip2: el mismo tarball "de toda la vida" que usa LFS/BLFS.
export BZIP2_MIRROR="https://sourceware.org/pub/bzip2"

# PCRE2: asset real de GitHub Release (tag "pcre2-X.Y", no sólo "X.Y").
export PCRE2_MIRROR="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}"

# libxcrypt: asset real de GitHub Release (tag "vX.Y.Z").
export LIBXCRYPT_MIRROR="https://github.com/besser82/libxcrypt/releases/download/v${LIBXCRYPT_VERSION}"

# --- Fase 4 ("Comunicaciones") --------------------------------------------------
# zlib: mismo tarball, republicado como asset de GitHub Release (ver comentario
# de versión más arriba sobre por qué no se usa zlib.net directo).
export ZLIB_MIRROR="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}"
# OpenSSL: asset real de GitHub Release (tag "openssl-X.Y.Z", no sólo "X.Y.Z").
export OPENSSL_MIRROR="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}"
# libcbor: sin dist propio — archive/refs/tags crudo (alcanza: es CMake puro,
# ver comentario de versión más arriba).
export LIBCBOR_MIRROR="https://github.com/PJK/libcbor/archive/refs/tags"
# libfido2: tarball de release real de Yubico (no el archive crudo de GitHub).
export LIBFIDO2_MIRROR="https://developers.yubico.com/libfido2/Releases"
# Linux-PAM: asset real de GitHub Release (tag "vX.Y.Z").
export LINUX_PAM_MIRROR="https://github.com/linux-pam/linux-pam/releases/download/v${LINUX_PAM_VERSION}"
# pam_u2f: tarball de release real de Yubico (el tab de Releases de GitHub
# está vacío para este proyecto).
export PAM_U2F_MIRROR="https://developers.yubico.com/pam-u2f/Releases"

# --- Fase 5 ("Infraestructura Autónoma") ----------------------------------------
# apk-tools: el repo canónico se mudó a gitlab.alpinelinux.org, pero ese host
# devolvió 403 al verificarlo en vivo desde este sandbox (bloqueo de red del
# propio sandbox de research, no necesariamente algo del build real -- mismo
# patrón que ya vimos con zlib.net). Se usa el mirror de sólo lectura de
# GitHub, mismo formato archive/refs/tags que systemd/uutils/libcbor en este
# mismo proyecto -- si "v${APK_TOOLS_VERSION}.tar.gz" da 404 en la build real,
# avisame y lo cambio a la URL de GitLab.
export APK_TOOLS_MIRROR="https://github.com/alpinelinux/apk-tools/archive/refs/tags"

# --- Fase 6, parte 1 -------------------------------------------------------------
export LIBFFI_MIRROR="https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}"
export EXPAT_MIRROR="https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}"
# GNOME: convención "MAJOR.MINOR/nombre-VERSION.tar.xz", rama estable = minor par.
export GLIB_MIRROR="https://download.gnome.org/sources/glib/${GLIB_VERSION%.*}"
export DBUS_MIRROR="https://dbus.freedesktop.org/releases/dbus"
# Duktape: distribución "amalgamada" (un solo .c/.h) -- no se instala con
# make/autotools de terceros, build-desktop.sh lo compila directo con el
# cross-gcc (ver comentario largo en step_duktape).
export DUKTAPE_MIRROR="https://duktape.org"
export LIBPNG_MIRROR="https://downloads.sourceforge.net/libpng"
# polkit: sin tarball de "make dist" -- archive/refs/tags crudo de GitHub,
# mismo patrón que libcap-ng/audit-userspace/libcbor en fases anteriores.
export POLKIT_MIRROR="https://github.com/polkit-org/polkit/archive/refs/tags"
export FREETYPE_MIRROR="https://downloads.sourceforge.net/freetype"
export HARFBUZZ_MIRROR="https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}"
# fontconfig: publica en el registro de paquetes genéricos de GitLab, no en
# una carpeta releases/ tradicional (confirmado contra BLFS).
export FONTCONFIG_MIRROR="https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/${FONTCONFIG_VERSION}"
export PIXMAN_MIRROR="https://www.cairographics.org/releases"
export CAIRO_MIRROR="https://www.cairographics.org/releases"
export WAYLAND_MIRROR="https://gitlab.freedesktop.org/wayland/wayland/-/releases/${WAYLAND_VERSION}/downloads"
export WAYLAND_PROTOCOLS_MIRROR="https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${WAYLAND_PROTOCOLS_VERSION}/downloads"
export MTDEV_MIRROR="https://bitmath.org/code/mtdev"
export LIBEVDEV_MIRROR="https://www.freedesktop.org/software/libevdev"
export XKEYBOARD_CONFIG_MIRROR="https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config"
export LIBINPUT_MIRROR="https://gitlab.freedesktop.org/libinput/libinput/-/archive/${LIBINPUT_VERSION}"
# libxkbcommon: sin tarball de "make dist" -- archive/refs/tags crudo de GitHub.
export LIBXKBCOMMON_MIRROR="https://github.com/xkbcommon/libxkbcommon/archive/refs/tags"
# libxml2: el repo canónico es gitlab.gnome.org/GNOME/libxml2 (SÍ accesible
# desde este sandbox de research, a diferencia de gitlab.freedesktop.org --
# confirmado en vivo, no asumido); se usa igual el mirror de GitHub
# (GNOME/libxml2) por consistencia con el resto del proyecto, que ya pulls
# archive/refs/tags crudo de GitHub para varios paquetes (libxkbcommon,
# glslang) -- tarball real bajado y confirmado (sha256 en LIBXML2_VERSION
# de más arriba, extrae a "libxml2-2.15.3/").
export LIBXML2_MIRROR="https://github.com/GNOME/libxml2/archive/refs/tags"
export ALSA_LIB_MIRROR="https://www.alsa-project.org/files/pub/lib"
export LUA_MIRROR="https://www.lua.org/ftp"
export PIPEWIRE_MIRROR="https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/${PIPEWIRE_VERSION}"
export WIREPLUMBER_MIRROR="https://gitlab.freedesktop.org/pipewire/wireplumber/-/archive/${WIREPLUMBER_VERSION}"
export LIBDRM_MIRROR="https://gitlab.freedesktop.org/mesa/libdrm/-/archive/libdrm-${LIBDRM_VERSION}"
# LLVM: release real de GitHub (no gitlab.fd.o) -- confirmado el nombre exacto
# del asset contra la página de la release llvmorg-${LLVM_VERSION}.
export LLVM_MIRROR="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}"
export MESA_MIRROR="https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-${MESA_VERSION}"
# glslang: release real de GitHub (KhronosGroup/glslang no está en
# gitlab.fd.o), mismo patrón de URL que LIBXKBCOMMON_MIRROR de más arriba.
export GLSLANG_MIRROR="https://github.com/KhronosGroup/glslang/archive/refs/tags"

# SPIRV-Headers: archive crudo por commit exacto (no hay tags propios que
# nos sirvan -- ver comentario largo de versión más arriba). GitHub arma el
# directorio del tarball como "SPIRV-Headers-<sha-completo>" -- confirmado
# por convención real de codeload.github.com para archives por commit (no
# por tag), igual que ya se documentó para otros archives crudos de este
# proyecto (libcbor, polkit, etc.) con tags en vez de shas.
export SPIRV_HEADERS_MIRROR="https://github.com/KhronosGroup/SPIRV-Headers/archive"
# SPIRV-Tools: archive/refs/tags crudo -- ver comentario de versión más
# arriba (README real: "GitHub releases are deprecated").
export SPIRV_TOOLS_MIRROR="https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags"
# SPIRV-LLVM-Translator: archive crudo por commit exacto, mismo motivo que
# SPIRV-Headers -- fijamos un commit puntual de la rama llvm_release_230, no
# la rama en sí (que se mueve).
export SPIRV_LLVM_TRANSLATOR_MIRROR="https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive"

# elfutils: mismo tarball oficial que usan LFS/BLFS, "<version>/elfutils-<version>.tar.bz2"
# dentro de esta base (ver VERIFICAR en el comentario de versión más arriba).
export ELFUTILS_MIRROR="https://sourceware.org/elfutils/ftp"

# KDE Frameworks/Plasma: tarballs oficiales reales de KDE (download.kde.org,
# accesible en vivo desde este sandbox), NO un mirror de GitHub como el resto
# de Fase 6 -- confirmado bajando extra-cmake-modules-6.29.0.tar.xz real desde
# acá. Estructura real: <base>/<tren>/<paquete>-<versión>.tar.xz.
export KDE_FRAMEWORKS_MIRROR="https://download.kde.org/stable/frameworks/6.29"
# Plasma (Tier 3): mismo dominio real que KDE Frameworks, tren de versión
# aparte -- ver comentario de PLASMA_VERSION más arriba. Estructura real
# confirmada en vivo: <base>/<paquete>-<versión>.tar.xz.
export PLASMA_MIRROR="https://download.kde.org/stable/plasma/${PLASMA_VERSION}"
# Sin subcarpeta de versión (a diferencia de Plasma) -- confirmado
# listando en vivo: los tarballs están planos bajo este mismo directorio.
export KIRIGAMI_ADDONS_MIRROR="https://download.kde.org/stable/kirigami-addons"
export LIBNL_MIRROR="https://github.com/thom311/libnl/releases/download/libnl3_12_0"
export LMSENSORS_MIRROR="https://github.com/lm-sensors/lm-sensors/archive/refs/tags"
export LIBEPOXY_MIRROR="https://github.com/anholt/libepoxy/archive/refs/tags"
export LCMS2_MIRROR="https://github.com/mm2/Little-CMS/releases/download/${LCMS2_TAG}"
export LIBDISPLAYINFO_MIRROR="https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/${LIBDISPLAYINFO_VERSION}/downloads"
export HWDATA_MIRROR="https://github.com/vcrhonek/hwdata/archive/refs/tags"
export VULKAN_HEADERS_MIRROR="https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags"
export VULKAN_LOADER_MIRROR="https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags"
export LIBXCVT_MIRROR="https://gitlab.freedesktop.org/xorg/lib/libxcvt/-/archive/libxcvt-${LIBXCVT_VERSION}"
export QCORO_MIRROR="https://github.com/danvratil/qcoro/archive/refs/tags"
export ICU_MIRROR="https://github.com/unicode-org/icu/releases/download/release-${ICU_VERSION}"
export LIBQRENCODE_MIRROR="https://github.com/fukuchi/libqrencode/archive/refs/tags"
export LIBGPGERROR_MIRROR="https://www.gnupg.org/ftp/gcrypt/libgpg-error"
export LIBGCRYPT_MIRROR="https://www.gnupg.org/ftp/gcrypt/libgcrypt"
export LIBSECRET_MIRROR="https://download.gnome.org/sources/libsecret/0.20"
export LIBNDP_MIRROR="https://github.com/jpirko/libndp/archive/refs/tags"
export NETWORKMANAGER_MIRROR="https://download.gnome.org/sources/NetworkManager/1.50"
export POLKITQT1_MIRROR="https://download.kde.org/stable/polkit-qt-1"
export LIBSNDFILE_MIRROR="https://github.com/libsndfile/libsndfile/releases/download/${LIBSNDFILE_VERSION}"
export PULSEAUDIO_MIRROR="https://www.freedesktop.org/software/pulseaudio/releases"
export PULSEAUDIO_QT_MIRROR="https://download.kde.org/stable/pulseaudio-qt"
export QTKEYCHAIN_MIRROR="https://github.com/frankosterfeld/qtkeychain/archive/refs/tags"
export PDFIO_MIRROR="https://github.com/michaelrsweet/pdfio/releases/download/v${PDFIO_VERSION}"
export CUPS_MIRROR="https://github.com/OpenPrinting/cups/releases/download/v${CUPS_VERSION}"
export LIBCUPSFILTERS_MIRROR="https://github.com/OpenPrinting/libcupsfilters/releases/download/${LIBCUPSFILTERS_VERSION}"
export LIBPPD_MIRROR="https://github.com/OpenPrinting/libppd/releases/download/${LIBPPD_VERSION}"
export CUPS_FILTERS_MIRROR="https://github.com/OpenPrinting/cups-filters/releases/download/${CUPS_FILTERS_VERSION}"
export BOOST_MIRROR="https://github.com/boostorg/boost/releases/download/boost-${BOOST_VERSION}"
export MODEMMANAGER_MIRROR="https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/archive/${MODEMMANAGER_VERSION}"
export LIBVA_MIRROR="https://github.com/intel/libva/releases/download/${LIBVA_VERSION}"
export FFMPEG_MIRROR="https://ffmpeg.org/releases"
export KDE_GEAR_MIRROR="https://download.kde.org/stable/release-service/${KDE_GEAR_VERSION}/src"
# Mirror directo para todo lo de download.kde.org (ver _fetch_kde en
# build-kde.sh): el redirector manda a un mirror caído. GWDG (Göttingen)
# replica el árbol completo bajo /pub/linux/kde/ con la misma ruta.
export KDE_FALLBACK_MIRROR="https://ftp.gwdg.de/pub/linux/kde"
# Fuentes tipográficas (2026-10-27): el sysroot no tenía ninguna. Noto Sans
# es la fuente de interfaz por defecto de plasma-integration; Hack Nerd Font
# reemplaza a Hack (la monoespaciada por defecto) con los glifos de íconos.
# Últimos releases reales en github.com/notofonts/latin-greek-cyrillic y
# github.com/ryanoasis/nerd-fonts (API en vivo).
export NOTO_SANS_VERSION="2.015"
export NERD_FONTS_VERSION="3.5.1"
export NOTO_SANS_MIRROR="https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v${NOTO_SANS_VERSION}"
export NERD_FONTS_MIRROR="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}"
# Layout de teclado por defecto del sistema (/etc/xdg/kxkbrc). latam =
# "Spanish (Latin American)" de xkeyboard-config, el estándar en Argentina.
export LINSI_KEYBOARD_LAYOUT="latam"

# Fase 8 -- primera imagen booteable (2026-10-27). Últimos releases reales:
# kernel.org/pub/linux/utils/kernel/kmod/, github.com/shadow-maint/shadow,
# gitlab.freedesktop.org/xdg/shared-mime-info (API de releases),
# data.iana.org/time-zones/releases/ y kernel.org/pub/linux/kernel/firmware/.
# - kmod: systemd se había compilado SIN kmod (libkmod no existía), así que
#   udev no podía cargar ningún módulo (amdgpu, iwlwifi...).
# - shadow: passwd/useradd/chpasswd/newuidmap. login/su/nologin/chsh/chfn
#   salen de util-linux (recompilado con PAM), como en Arch.
# - shared-mime-info: sin la base MIME, KIO/Dolphin no reconocen ningún tipo
#   de archivo.
# - tzdata: no había /usr/share/zoneinfo; se compila con el zic del
#   contenedor (formato TZif, no depende de la arquitectura).
# - linux-firmware: sólo lo que piden los drivers que van como módulo o que
#   lo necesitan para andar bien (amdgpu, i915, iwlwifi, rtl_nic,
#   regulatory.db), no el árbol entero.
export KMOD_VERSION="34.2"
export SHADOW_VERSION="4.20.3"
export SHARED_MIME_INFO_VERSION="2.5.1"
export TZDATA_VERSION="2026e"
export LINUX_FIRMWARE_VERSION="20261019"
export KMOD_MIRROR="https://www.kernel.org/pub/linux/utils/kernel/kmod"
export SHADOW_MIRROR="https://github.com/shadow-maint/shadow/releases/download/${SHADOW_VERSION}"
export SHARED_MIME_INFO_MIRROR="https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SHARED_MIME_INFO_VERSION}"
export TZDATA_MIRROR="https://data.iana.org/time-zones/releases"
export LINUX_FIRMWARE_MIRROR="https://www.kernel.org/pub/linux/kernel/firmware"
# - kbd: loadkeys/setfont + mapas (la-latin1) para la consola; sin él
#   systemd-vconsole-setup falla y systemd-firstboot frena el primer arranque
#   preguntando el keymap.
# - Certificados raíz: el bundle de Mozilla que publica curl.se (fechado, el
#   último listado en curl.se/docs/caextract.html). No había ninguno, y
#   systemd-resolved (DNS-over-TLS estricto) los necesita para resolver.
export KBD_VERSION="2.10.0"
export CACERT_DATE="2026-10-20"
export KBD_MIRROR="https://www.kernel.org/pub/linux/utils/kbd"
# wireless-regdb: regulatory.db (canales WiFi legales por país). Ya no viene
# dentro de linux-firmware.
export WIRELESS_REGDB_VERSION="2026.09.03"
export WIRELESS_REGDB_MIRROR="https://www.kernel.org/pub/software/network/wireless-regdb"
# iana-etc: /etc/services y /etc/protocols (glibc no los trae). Último
# release real de github.com/Mic92/iana-etc.
export IANA_ETC_VERSION="20261022"
export IANA_ETC_MIRROR="https://github.com/Mic92/iana-etc/releases/download/${IANA_ETC_VERSION}"
export CACERT_MIRROR="https://curl.se/ca"
# libxcb y su cadena de dependencias: xorg.freedesktop.org, accesible en
# vivo (a diferencia de gitlab.freedesktop.org) -- ver comentario real de
# versión más arriba. Tres subdirectorios reales distintos del mismo
# archivo ("proto", "lib", "xcb"), confirmado listando cada uno en vivo.
export XORGPROTO_MIRROR="https://xorg.freedesktop.org/archive/individual/proto"
export XORG_LIB_MIRROR="https://xorg.freedesktop.org/archive/individual/lib"
export XCB_MIRROR="https://xorg.freedesktop.org/archive/individual/xcb"
# iso-codes: upstream real (salsa.debian.org), no un mirror -- ver
# comentario de versión más arriba. Base para "/v<version>/iso-codes-v<version>.tar.gz".
export ISOCODES_MIRROR="https://salsa.debian.org/iso-codes-team/iso-codes/-/archive"
# PlasmaWaylandProtocols: mirror de GitHub, ver comentario de versión más
# arriba. Archive crudo por tag, GitHub SÍ pisa el "v" al armar el
# directorio (confirmado: extrae a "plasma-wayland-protocols-1.21.0/").
export PLASMA_WAYLAND_PROTOCOLS_MIRROR="https://github.com/KDE/plasma-wayland-protocols/archive/refs/tags"
# zstd: release real de GitHub (tarball "make dist", no un archive crudo).
export ZSTD_MIRROR="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}"
# liblzma (xz): release real de GitHub (tukaani-project/xz), tarball
# "make dist" real, no un archive crudo.
export LIBLZMA_MIRROR="https://github.com/tukaani-project/xz/releases/download/v${LIBLZMA_VERSION}"
# libcanberra: upstream real (0pointer.de, la web personal de Lennart
# Poettering) -- confirmado en vivo, tarball real "make dist" con
# configure ya generado. gitlab.freedesktop.org NO tiene este proyecto
# bajo el namespace "0pointer" pese a que muchas referencias antiguas lo
# dan por hecho (probado 404 real) -- éste es el mirror correcto.
export LIBCANBERRA_MIRROR="https://0pointer.de/lennart/projects/libcanberra"
# libtool: release oficial real de ftp.gnu.org.
export LIBTOOL_MIRROR="https://ftp.gnu.org/gnu/libtool"
# libogg/libvorbis: releases oficiales reales de Xiph.Org.
export LIBOGG_MIRROR="https://downloads.xiph.org/releases/ogg"
export LIBVORBIS_MIRROR="https://downloads.xiph.org/releases/vorbis"

# Qt6: tarballs oficiales reales de Qt (download.qt.io, confirmado en vivo
# con la URL real de qtbase-everywhere-src-6.11.2.tar.xz -- HTTP 200,
# redirige a un mirror real vía MirrorBrain, mismo mecanismo que ya usa
# download.kde.org). Estructura real:
# <base>/<X.Y>/<X.Y.Z>/submodules/<módulo>-everywhere-src-<X.Y.Z>.tar.xz
export QT6_MIRROR="https://download.qt.io/official_releases/qt/6.11/${QT6_VERSION}/submodules"

# --- Cargo (Fase 2, uutils) ----------------------------------------------------
# CARGO_HOME por default es ~/.cargo (home del usuario "linsi" dentro del
# contenedor), y ese directorio NO está en ningún volumen del compose — cada
# `podman compose run` es un contenedor efímero, así que sin esto cada intento
# de compilar uutils re-descargaría TODOS los crates de crates.io de cero
# (con la conexión que se corta seguido, un dolor de cabeza evitable). Se
# redirige sólo el caché de registry/config de Cargo a /lfs/build, que sí es
# un volumen persistente (linsios-build) — esto no toca dónde vive el propio
# toolchain de rustup (~/.rustup, ~/.cargo/bin), que ya quedó instalado
# adentro de la imagen en el Dockerfile y no necesita persistir por volumen.
export CARGO_HOME="${LFS_BUILD}/.cargo-home"

# --- Sysroot del sistema final (Fase 2 en adelante) ---------------------------
# Todo lo de espacio de usuario (glibc, systemd, zsh, uutils) se instala acá
# con --prefix=/usr + DESTDIR="${LFS}" — igual que las cabeceras del kernel en
# Fase 0 — para no chrootear: como el target es x86_64 igual que el host, los
# binarios se pueden probar corriéndolos directo contra su propio ld.so del
# sysroot (ver step_verify en build-userspace.sh), sin necesidad de chroot.
export LFS_SYSROOT="${LFS}"

# ------------------------------------------------------------------------------
# Verificación de integridad del tarball del kernel (sha256 contra LINUX_SHA256).
# La llaman tanto build-cross-toolchain.sh (Fase 0, cabeceras) como
# build-kernel.sh (Fase 1, build completo) sobre el mismo archivo.
# ------------------------------------------------------------------------------
verify_linux_tarball() {
    local tarball="${LFS_SOURCES}/linux-${LINUX_VERSION}.tar.xz"
    [[ -f "${tarball}" ]] || { echo "[env] no existe ${tarball}" >&2; return 1; }

    local got
    got="$(sha256sum "${tarball}" | awk '{print $1}')"
    if [[ "${got}" != "${LINUX_SHA256}" ]]; then
        echo "[env][error] sha256 de ${tarball} no coincide." >&2
        echo "  esperado: ${LINUX_SHA256}" >&2
        echo "  obtenido: ${got}" >&2
        echo "  Verificá el hash oficial en https://www.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc" >&2
        echo "  antes de seguir — puede ser una descarga corrupta o el archivo equivocado." >&2
        return 1
    fi
    echo "[env] sha256 de linux-${LINUX_VERSION}.tar.xz verificado OK"
}

# ------------------------------------------------------------------------------
# glibc/systemd/zsh no publican un sha256sums.txt plano (se firman por GPG, no
# por hash). En vez de fijar un hash que no puedo respaldar, esto calcula el
# sha256 real del tarball ya descargado y lo deja bien visible en el log para
# que lo compares a mano contra la fuente oficial si querés esa garantía.
# ------------------------------------------------------------------------------
log_sha256() {
    local tarball="$1"
    [[ -f "${tarball}" ]] || { echo "[env] no existe ${tarball}" >&2; return 1; }
    local got
    got="$(sha256sum "${tarball}" | awk '{print $1}')"
    echo "[env] sha256 de $(basename "${tarball}"): ${got}"
}
