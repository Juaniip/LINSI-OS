#!/usr/bin/env bash
# ==============================================================================
# LINSI-OS · Fase 6 — "Interfaz Moderna" (parte 2: Mesa + LLVM, drivers gráficos)
# ------------------------------------------------------------------------------
# Igual que fases anteriores: no se chrootea, todo se instala con --prefix=/usr
# + DESTDIR="${LFS_SYSROOT}". Requiere Fase 6 Parte 1 completa
# (scripts/build-desktop.sh all) -- en particular necesita el wayland-scanner
# NATIVO que ya dejó compilado step_wayland() ahí (no se reconstruye acá, se
# reusa vía el volumen persistente /lfs/build).
#
# Alcance elegido (2026-08-29, a pedido explícito: máquinas del lab con
# GPUs de cualquier tipo -- Nvidia RTX 3060, AMD RX 7700, Intel integrada):
#   - Gallium (OpenGL):  iris (Intel), radeonsi (AMD), nouveau (Nvidia libre),
#                        llvmpipe (software con JIT de LLVM, fallback
#                        universal -- "swrast" era el nombre viejo de esta
#                        opción en versiones antiguas de Mesa; en 26.2.1 el
#                        choice válido es "llvmpipe" -- ver corrección más
#                        abajo. El .so instalado sigue llamándose
#                        swrast_dri.so igual, eso no cambió.)
#   - Vulkan:            amd (RADV), intel (ANV)
#   - LLVM sólo con los targets X86 (lo necesita llvmpipe para JIT) y
#     AMDGPU (lo necesita radeonsi para compilar shaders) -- nada de ARM,
#     RISC-V, etc. que no vamos a usar nunca acá.
#
# Lo que se dejó AFUERA a propósito (ver docs/PENDIENTES.md, no es un olvido):
#   - Vulkan por software (lavapipe, "vulkan-drivers=swrast" -- ese option sí
#     se sigue llamando "swrast", es un namespace de opciones separado de
#     "gallium-drivers"): sigue sin estar en el plan.
#   - NVK (driver Vulkan nativo para Nvidia): a la fecha de este script ni
#     siquiera figura como choice válido en el meson_options.txt real de
#     Mesa -- nouveau (Gallium/OpenGL) es lo que hay disponible.
#   - VA-API/VDPAU (aceleración de decodificación de video): -Dgallium-va
#     queda en disabled -- necesita libva, que este proyecto todavía no
#     compiló. VDPAU es más simple todavía: CORRECCIÓN (post-build real,
#     2026-08-30) -- "gallium-vdpau" ni siquiera es un option válido en
#     Mesa 26.2.1 ("ERROR: Unknown option: gallium-vdpau"), Mesa upstream
#     lo sacó del todo (no es un rename a otro nombre, es soporte VDPAU
#     nativo eliminado de Gallium). Sacado del comando de meson -- no había
#     nada que "dejar en disabled", la opción no existe.
#   - glvnd (dispatcher multi-vendor de OpenGL): sólo hace falta si algún día
#     convive Mesa con un driver propietario de Nvidia -- no es el caso hoy.
#
# ------------------------------------------------------------------------------
# AGREGADO 2026-09-02 -- Clang + SPIRV-Tools + SPIRV-LLVM-Translator
# (Opción B de CONTEXTO_PENDIENTE_MESA.md, decidido en la PC de escritorio con
# 48GB de RAM, para tener Intel real -- iris/anv -- en esta misma pasada).
#
# El motivo: con iris (gallium) e intel_vk/anv (vulkan) habilitados, el
# meson.build REAL de Mesa ${MESA_VERSION} (leído directo del propio
# mesa-${MESA_VERSION}.tar.gz ya descargado, no de un mirror desactualizado)
# activa "with_driver_using_cl" -- Mesa necesita compilar mesa-clc/intel_clc,
# su compilador interno de OpenCL C a SPIR-V para shaders/kernels internos de
# esos dos drivers. El error real ya visto en la sesión anterior
# ("Dependency 'LLVMSPIRVLib' not found") era sólo el PRIMERO de varios
# huecos -- research completo (leyendo el meson.build real, no la docs
# genérica) encontró lo siguiente:
#
#   - dep_clang (Clang): la Mesa ${MESA_VERSION} real YA NO usa
#     dependency('clang', method:'cmake') como versiones viejas -- usa
#     cpp.find_library('clang-cpp', dirs: llvm_libdir) primero, y sólo si
#     eso falla cae a linkear ~15 librerías estáticas de clang una por una.
#     Como ya compilamos LLVM con -Dshared-llvm=enabled, alcanza con que
#     exista libclang-cpp.so en el sysroot. Confirmado contra
#     clang/tools/CMakeLists.txt real de la tag llvmorg-${LLVM_VERSION}:
#     ese .so se arma solo en Linux con LLVM_ENABLE_PROJECTS=clang, sin
#     flags extra (la condición ahí es sólo "UNIX AND NOT CYGWIN").
#   - dep_spirv_tools: SPIRV-Tools (>= 2024.1) es OBLIGATORIO apenas
#     with_clc=true -- componente nuevo, NO estaba anotado en
#     CONTEXTO_PENDIENTE_MESA.md (esa nota se escribió sin poder leer el
#     meson.build real todavía).
#   - dep_clc (libclc EXTERNO): CONFIRMADO que NO hace falta para nuestra
#     selección de drivers. Sólo se resuelve
#     "if with_gallium_rusticl or with_microsoft_clc" en el meson.build real
#     -- ninguno de los dos está en nuestro -Dgallium-drivers=
#     iris,radeonsi,nouveau,llvmpipe / -Dvulkan-drivers=amd,intel. with_clc
#     queda en true igual (por iris/intel_vk), pero eso sólo obliga a
#     LLVM+clang+SPIRV-Tools+LLVMSPIRVLib -- el código que de verdad usa
#     libclc (nir_load_libclc.c, en src/compiler/clc/meson.build real) sólo
#     se agrega "if dep_clc.found()", y dep_clc nunca se resuelve en nuestro
#     caso. Esto SIMPLIFICA la Opción B tal como se había descrito
#     originalmente: no hace falta cross-compilar libclc (bitcode LLVM
#     por-target, la parte más pesada y delicada que se había anticipado) --
#     un componente entero menos que compilar.
#
# Orden real de compilación de estos tres componentes nuevos:
#   spirv-headers -> spirv-tools -> spirv-llvm-translator (necesita LLVM
#   cruzado + opcionalmente detecta SPIRV-Tools ya instalado) -> mesa.
# Van DESPUÉS de llvm/glslang-native y ANTES de mesa en la secuencia "all".
# ------------------------------------------------------------------------------
#
# La parte MÁS delicada de todo esto es cómo LLVM resuelve su propio
# "llvm-config" durante el build de Mesa -- ver el comentario largo en
# step_llvm() antes de tocar nada ahí. Es voluntad expresa de este proyecto
# (y de quien pidió esto) no dar por sentado que esto va a salir a la
# primera: el propio docs/PENDIENTES.md, desde antes de escribir este script, ya
# decía "cross-compilar LLVM es delicado y merece su propia pasada de
# research" -- research que se hizo (LLVM.org, Buildroot real, docs oficiales
# de Mesa sobre detección de LLVM, un issue real de Meson sobre esto mismo),
# pero sin poder correr nada en vivo hasta que tiren el build real.
#
# Orden (cada paso depende del anterior):
#   1. libdrm                    -> bindings de espacio de usuario al DRM/GEM
#   2. llvm-native                -> build NATIVO (llvm-tblgen + llvm-config +
#                                  clang-tblgen + libLLVM.so + libclang-cpp.so
#                                  NATIVAS, éstas últimas para mesa_clc --
#                                  ver Décimo noveno/Vigésimo error real), no
#                                  se instala nada del sistema final con esto
#   3. llvm                       -> build CRUZADO real (libLLVM + libclang-cpp
#                                  + headers), el que efectivamente queda en
#                                  el sysroot
#   4. glslang-native              -> glslangValidator NATIVO (Mesa >= 12.2)
#   5. spirv-headers               -> sólo headers/gramática, dos checkouts
#                                  (uno por consumidor, ver env.sh)
#   6. spirv-tools                 -> cruzado, provee SPIRV-Tools.pc
#   6b. spirv-tools-native          -> NATIVO, lo necesita mesa_clc NATIVO
#                                  del paso 7c (ver Vigésimo error real)
#   7. spirv-llvm-translator       -> cruzado, provee LLVMSPIRVLib.pc
#   7b. spirv-llvm-translator-native -> NATIVO, idem 6b
#   7c. mesa-clc-native             -> mesa_clc + vtn_bindgen2 100% NATIVOS,
#                                  build de Mesa aparte con drivers vacíos
#                                  (Vigésimo error real -- reemplaza el
#                                  intento de forzar native:true a mano
#                                  adentro del build cruzado, Décimo noveno
#                                  parte 2, revertido)
#   8. mesa                        -> los drivers en sí, usa libdrm + LLVM +
#                                  clang + SPIRV-Tools + LLVMSPIRVLib + el
#                                  wayland-scanner nativo de la Parte 1 +
#                                  mesa_clc/vtn_bindgen2 NATIVOS (-Dmesa-clc=
#                                  system) del paso 7c
#
# Uso:
#   scripts/build-mesa.sh libdrm
#   scripts/build-mesa.sh all        # corre todos los pasos
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/lfs/scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

log()  { printf '\n\033[1;35m[fase6-2]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[fase6-2][error]\033[0m %s\n' "$*" >&2; exit 1; }

require_toolchain() {
    if ! command -v "${LFS_TGT}-gcc" >/dev/null 2>&1; then
        die "no se encontró ${LFS_TGT}-gcc en el PATH. Corré primero: scripts/build-cross-toolchain.sh all"
    fi
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

extract_once() {
    local tarball="$1" marker="$2"
    if [[ -f "${marker}" ]]; then
        log "ya extraído: ${tarball}"
        return 0
    fi
    log "extrayendo ${tarball}"
    tar -xf "${tarball}" -C "${LFS_BUILD}"
    touch "${marker}"
}

# build_triplet() -- agregado junto con step_elfutils() (Décimo quinto error
# real): hasta ahora este archivo sólo tenía pasos Meson/CMake (libdrm, LLVM,
# SPIRV-*, Mesa), ninguno usa "--build=" -- elfutils es el primer ./configure
# de Autotools de build-mesa.sh, así que hace falta este helper, ya usado en
# build-security.sh/build-desktop.sh/build-userspace.sh/build-comms.sh con
# esta misma definición exacta (config.guess real de Binutils, no "uname -m"
# a mano).
build_triplet() {
    "${LFS_BUILD}/binutils-${BINUTILS_VERSION}/config.guess"
}

# Cross file de Meson -- copia exacta del de build-desktop.sh (Fase 6 Parte 1),
# ya con los dos fixes reales que costaron una ronda entera de debug ahí:
# pkg_config_libdir como LISTA (share/pkgconfig además de lib/pkgconfig, lo
# necesitan paquetes sin código compilado) y el parámetro extra_binaries para
# poder pisar find_program()s puntuales sin --native-file (find_program() sin
# native:true resuelve contra ACÁ, no contra el native file -- lección real de
# wireplumber/spa-json-dump, ver docs/PENDIENTES.md).
write_meson_crossfile() {
    local crossfile="$1"
    local extra_binaries="${2:-}"
    cat > "${crossfile}" <<EOF
[binaries]
c = '${LFS_TOOLS}/bin/${LFS_TGT}-gcc'
cpp = '${LFS_TOOLS}/bin/${LFS_TGT}-g++'
ar = '${LFS_TOOLS}/bin/${LFS_TGT}-ar'
strip = '${LFS_TOOLS}/bin/${LFS_TGT}-strip'
ranlib = '${LFS_TOOLS}/bin/${LFS_TGT}-ranlib'
pkg-config = 'pkg-config'
${extra_binaries}

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
sys_root = '${LFS_SYSROOT}'
pkg_config_libdir = ['${LFS_SYSROOT}/usr/lib/pkgconfig', '${LFS_SYSROOT}/usr/share/pkgconfig']
growing_stack = false
have_strlcpy = false
have_c99_vsnprintf = true
have_c99_snprintf = true
va_val_copy = true
EOF
}

# Prefix del wayland-scanner NATIVO -- NO se reconstruye acá. Ya lo dejó
# compilado step_wayland() en build-desktop.sh (Fase 6 Parte 1), y como
# /lfs/build es un volumen persistente (linsios-build en docker-compose.yml),
# este script -- aunque es un proceso bash completamente aparte -- lo
# encuentra en el mismo lugar. Sólo se chequea que exista.
WAYLAND_SCANNER_NATIVE_PREFIX="${LFS_BUILD}/wayland-scanner-native"

write_meson_nativefile() {
    local nativefile="$1"
    local extra_binaries="${2:-}"
    cat > "${nativefile}" <<EOF
[properties]
pkg_config_libdir = '${WAYLAND_SCANNER_NATIVE_PREFIX}/lib/pkgconfig'
EOF
    if [[ -n "${extra_binaries}" ]]; then
        {
            echo ""
            echo "[binaries]"
            echo "${extra_binaries}"
        } >> "${nativefile}"
    fi
}

# Toolchain file de CMake -- el equivalente del cross-file de Meson, pero
# para LLVM (CMake, no Meson). Patrón estándar de CMake para cross-compiling
# (CMAKE_SYSTEM_NAME distinto activa CMAKE_CROSSCOMPILING automáticamente):
# CMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER porque los programas de build
# (bison, python3, etc.) tienen que ser los del HOST, no buscarse adentro
# del sysroot; LIBRARY/INCLUDE/PACKAGE=ONLY porque esos sí tienen que salir
# del sysroot (ahí vive el resto de lo que ya compilamos: libdrm, etc.).
write_cmake_toolchain() {
    local toolchain="$1"
    cat > "${toolchain}" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER ${LFS_TOOLS}/bin/${LFS_TGT}-gcc)
set(CMAKE_CXX_COMPILER ${LFS_TOOLS}/bin/${LFS_TGT}-g++)
set(CMAKE_SYSROOT ${LFS_SYSROOT})
set(CMAKE_FIND_ROOT_PATH ${LFS_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
}

# ------------------------------------------------------------------------------
# 1) libdrm — Meson. Bindings de espacio de usuario al DRM/GEM del kernel;
# necesario para que Mesa hable con /dev/dri/*. Receta mínima (udev+valgrind
# nada más) confirmada contra una receta real de LFS/BLFS para esta misma
# versión -- las cabeceras por-vendor de radeon/amdgpu/nouveau se instalan
# solas sin flags extra.
#
# CORRECCIÓN (post-build real, 2026-08-29): libdrm_intel NO se instala solo.
# Su detección depende de pciaccess (libpciaccess), que no está en el
# sysroot -- meson lo marca "NO" y desactiva silenciosamente el subdirectorio
# intel/ sin frenar el resto del build. Esto en un principio parecía un bug
# a arreglar, pero en realidad NO hace falta: libdrm_intel sólo lo usan el
# driver clásico i965/crocus (legado, pre-Gen8) y la DDX de X11
# (xf86-video-intel) -- ninguno de los dos está en el plan (elegimos el
# driver moderno `iris` para Mesa y este proyecto es Wayland puro, sin DDX de
# X11). Confirmado contra el meson.build real de iris en Mesa: sólo depende
# de `dep_libdrm` genérico, nunca de `libdrm_intel`/`intel_bufmgr`. Por eso
# step_verify_libdrm() de abajo lo trata como informativo, no como falla.
# ------------------------------------------------------------------------------
step_libdrm() {
    require_toolchain
    log "libdrm ${LIBDRM_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${LIBDRM_MIRROR}/libdrm-libdrm-${LIBDRM_VERSION}.tar.gz" \
          "libdrm-${LIBDRM_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libdrm-${LIBDRM_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libdrm-${LIBDRM_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libdrm"

    # Igual que con pipewire/wireplumber: gitlab.fd.o arma el tarball como
    # "<repo>-<tag>" -- acá el tag es "libdrm-${LIBDRM_VERSION}", así que el
    # directorio queda con el nombre duplicado.
    local src="${LFS_BUILD}/libdrm-libdrm-${LIBDRM_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        -Dudev=true \
        -Dvalgrind=disabled

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libdrm instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libdrm() {
    log "Verificación: libdrm y bindings por-vendor en el sysroot"
    local ok=1
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libdrm.so*' 2>/dev/null | grep -q .; then
        echo "  [FALTA] libdrm.so en ${LFS_SYSROOT}/usr/lib"; ok=0
    else
        echo "  [OK] libdrm.so presente"
    fi
    local p
    for p in libdrm_amdgpu libdrm_nouveau; do
        if find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name "${p}.so*" 2>/dev/null | grep -q .; then
            echo "  [OK] ${p}.so presente"
        else
            echo "  [FALTA] ${p}.so en ${LFS_SYSROOT}/usr/lib"; ok=0
        fi
    done
    # libdrm_intel: NO se cuenta como falla. Sólo la usan el driver clásico
    # i965/crocus y la DDX de X11 xf86-video-intel -- ninguno está en este
    # proyecto (usamos `iris`, que sólo depende de libdrm genérico). Se
    # desactiva solo porque falta pciaccess en el sysroot, y eso está bien.
    if find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libdrm_intel.so*' 2>/dev/null | grep -q .; then
        echo "  [OK] libdrm_intel.so presente (no hacía falta, pero está)"
    else
        echo "  [info] libdrm_intel.so no está -- esperado, sólo lo necesitan i965/crocus (legado) y xf86-video-intel, no iris"
    fi
    [[ "${ok}" -eq 1 ]] || die "falta algo de libdrm en el sysroot"
    log "OK: libdrm completo en el sysroot (para lo que este proyecto necesita)."
}

# ------------------------------------------------------------------------------
# 2) y 3) LLVM — CMake, build en DOS ETAPAS. Esto es lo más delicado de todo
# el proyecto hasta ahora, así que va el razonamiento completo acá.
#
# LLVM_TARGETS_TO_BUILD="X86;AMDGPU" nada más -- lo necesita llvmpipe
# (JIT en X86) y radeonsi (compila shaders para AMDGPU). Nada de ARM/RISC-V/
# etc: no vamos a generar código para esas arquitecturas nunca en este
# proyecto.
#
# LLVM_ENABLE_PROJECTS="clang" (agregado 2026-09-02, ver bloque grande al
# principio del archivo): mesa-clc/intel_clc (que necesitan iris/anv, ya
# elegidos para el Intel del lab) exigen las LIBRERÍAS de Clang -- no hace
# falta lld/mlir/clang-tools-extra, sólo "clang" a secas. Esto agrega un
# tool nativo nuevo a resolver en la Etapa 1: clang-tblgen (ver más abajo,
# mismo mecanismo que llvm-tblgen -- confirmado contra clang/CMakeLists.txt
# real de la tag llvmorg-${LLVM_VERSION}, que documenta exactamente este
# patrón para sus propios builds "bootstrap": "-DCLANG_TABLEGEN=.../clang-tblgen"
# junto con "-DLLVM_TABLEGEN=.../llvm-tblgen").
#
# ETAPA 1 (step_llvm_native, NATIVA, sin --cross-file): build de CMake
# mínimo (sólo los targets "llvm-tblgen", "llvm-config" y "clang-tblgen", no
# "ninja install" de todo LLVM+Clang) usando el compilador nativo del
# contenedor. Confirmado contra la documentación real de LLVM
# (llvm.org/docs/CMake.html, variable LLVM_TABLEGEN: "Full path to a native
# TableGen executable... intended for cross-compiling") y una receta real de
# cross-compiling de LLVM en Buildroot
# (linuxembedded.fr/2018/07/llvmclang-integration-into-buildroot): un build
# cruzado de LLVM (y de Clang, por la misma razón) NECESITA un llvm-tblgen /
# clang-tblgen que corran YA, durante el build, para generar código a partir
# de los ".td" -- exactamente el mismo patrón de "herramienta de build-time
# que tiene que ser nativa" que ya vimos tres veces con wayland-scanner en
# la Parte 1, sólo que acá LLVM/Clang mismos ya lo tienen resuelto de
# fábrica con estas variables, no hace falta --native-file.
#
# El problema nuevo, específico de LLVM, es "llvm-config": Mesa lo necesita
# para preguntarle "¿dónde están tus headers, tus libs, tenés RTTI?" durante
# SU PROPIO configure -- y esa consulta tiene que poder EJECUTARSE (no sirve
# de nada un llvm-config cross-compilado tirado en el sysroot, va a fallar
# con el mismo problema de glibc que ya vimos con glib-compile-resources y
# spa-json-dump en wireplumber). Documentado en los docs oficiales de Mesa
# (docs.mesa3d.org/meson.html, sección de detección de LLVM) que el método
# estándar es un llvm-config real en el PATH (o pisado vía cross/native
# file) -- y un issue real de Meson (mesonbuild/meson#2921, "Cross-file
# binaries not being used for ConfigTool") confirma que Meson SÍ soporta
# pisarlo desde ahí (el bug que describía ese issue ya está resuelto en la
# versión de Meson que usamos, >=1.3).
#
# La solución (mismo patrón que Buildroot, adaptado a que acá build==target
# en arquitectura): compilar llvm-config NATIVO -- corre bien, misma
# arquitectura -- pero configurado con el MISMO --prefix que va a tener el
# LLVM cruzado de verdad (${LFS_SYSROOT}/usr, no un prefix nativo aparte),
# para que lo que imprime ("--includedir", "--libdir", etc) apunte a donde
# EFECTIVAMENTE van a estar los headers/libs cruzados de verdad (instalados
# por la ETAPA 2). Se copia ese binario nativo directo a
# ${LFS_SYSROOT}/usr/bin/llvm-config, pisando el cruzado (roto) que deja el
# "ninja install" de la Etapa 2.
#
# CORRECCIÓN #2 (post-build real, 2026-09-01): la parte de "Mesa lo
# encuentra solo por PATH" de más arriba era la suposición equivocada.
# Error real: "llvm-config found: NO need ['>= 18.0.0']" seguido de un
# intento fallido de Meson de bajar LLVM como subproyecto fallback (algo
# que ni siquiera queremos -- ya tenemos LLVM 23.1.0 compilado y andando).
# El formato exacto de ese mensaje ("X found: NO", sin una línea previa de
# "Program 'llvm-config' found: YES <versión>") es el que imprime Meson
# cuando NINGÚN candidato de llvm-config fue siquiera encontrado -- no un
# mismatch de versión (23.1.0 es sobrada para el >=18.0.0 que pide Mesa).
# La dependencia `dependency('llvm', method: 'config-tool', ...)` de Mesa
# es una dependencia de la MÁQUINA HOST en terminología de Meson (o sea,
# el TARGET real en un build cruzado -- Mesa la linkea al binario final),
# y para ese tipo de dependencias el mecanismo config-tool de Meson NO cae
# de vuelta a buscar en el PATH del contenedor si el binario no está
# declarado explícitamente en la sección [binaries] del CROSS FILE --
# confirmado contra la documentación real de Meson (mesonbuild.com,
# Machine-files.html: "An incomplete list of internally used programs
# that can be overridden here is: ... llvm-config ...") y contra el
# historial del issue real mesonbuild/meson#2921 ("Cross-file binaries
# not being used for ConfigTool"), que trata justamente de esta ambigüedad
# entre PATH y cross-file para llvm-config. Mismo mecanismo que ya usamos
# para glslangValidator más abajo en step_mesa(): se pisa `llvm-config`
# directo en el [binaries] del cross-file con `write_meson_crossfile()`.
#
# CORRECCIÓN (post-build real, 2026-08-30): el prefix SÍ queda bien grabado
# en el binario (confirmado: llvm-config.cpp de LLVM compara su ubicación de
# ejecución contra una constante LLVM_OBJ_ROOT grabada en tiempo de
# compilación -- si NO coinciden, que es justo lo que pasa acá porque lo
# movimos fuera de ${LLVM_NATIVE_BUILD}, usa el CMAKE_INSTALL_PREFIX que le
# dimos, o sea ${LFS_SYSROOT}/usr -- exactamente lo que queríamos). El
# problema real fue otro, más básico: LLVM compila su tooling (llvm-config
# incluido) con un RPATH relativo a propósito ("$ORIGIN/../lib", para que
# las herramientas de LLVM sean relocalizables -- confirmado contra el
# historial real de cambios de AddLLVM.cmake en el repo de LLVM). Al copiar
# el binario nativo a ${LFS_SYSROOT}/usr/bin/llvm-config, ese RPATH relativo
# pasa a resolver a ${LFS_SYSROOT}/usr/lib -- que es la carpeta de
# librerías del SYSROOT (la glibc cross-compilada de Fase 2), no la del
# contenedor. Error real visto: "symbol lookup error:
# .../lib/libc.so.6: undefined symbol: __pointer_chk_guard, version
# GLIBC_PRIVATE" -- otra vuelta más del mismo problema de fondo que ya
# apareció 3 veces en la Parte 1 (mezclar binario y glibc de mundos
# distintos aunque sea "la misma arquitectura"), sólo que acá el binario SÍ
# es nativo -- lo que estaba mal era a qué librerías apuntaba por culpa de
# dónde lo copiamos, no el binario en sí.
#
# La solución: dejar que el binario reporte las rutas del sysroot (eso ya
# funciona, es independiente del RPATH -- son dos mecanismos separados: uno
# son strings grabados en tiempo de compilación, el otro es una entrada del
# header ELF que se puede reescribir después sin recompilar nada), pero
# usar `patchelf --set-rpath` para apuntar su RPATH al directorio de build
# NATIVO de LLVM (${LLVM_NATIVE_BUILD}/lib), que tiene una libLLVM.so
# compatible con el contenedor. step_verify_llvm() de abajo corre el
# llvm-config ya parcheado y CHEQUEA tanto que corra sin error como que
# --includedir devuelva algo adentro de ${LFS_SYSROOT}.
# ------------------------------------------------------------------------------
LLVM_NATIVE_BUILD="${LFS_BUILD}/llvm-native-build"
LLVM_TABLEGEN_NATIVE="${LLVM_NATIVE_BUILD}/bin/llvm-tblgen"
CLANG_TABLEGEN_NATIVE="${LLVM_NATIVE_BUILD}/bin/clang-tblgen"

LLVM_CMAKE_COMMON_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_ENABLE_PROJECTS=clang
    "-DLLVM_TARGETS_TO_BUILD=X86;AMDGPU"
    -DLLVM_TARGET_ARCH=X86
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_ENABLE_TERMINFO=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_BUILD_LLVM_DYLIB=ON
    -DLLVM_LINK_LLVM_DYLIB=ON
)

_llvm_fetch_extract() {
    cd "${LFS_SOURCES}"
    fetch "${LLVM_MIRROR}/llvm-project-${LLVM_VERSION}.src.tar.xz" \
          "llvm-project-${LLVM_VERSION}.src.tar.xz"
    log_sha256 "${LFS_SOURCES}/llvm-project-${LLVM_VERSION}.src.tar.xz"
    extract_once "${LFS_SOURCES}/llvm-project-${LLVM_VERSION}.src.tar.xz" \
                 "${LFS_BUILD}/.extracted-llvm-project"
}

step_llvm_native() {
    log "LLVM+Clang ${LLVM_VERSION} — build NATIVO (llvm-tblgen + llvm-config + clang-tblgen + libLLVM.so + libclang-cpp.so nativas, para el build cruzado y para mesa_clc)"
    _llvm_fetch_extract

    local src="${LFS_BUILD}/llvm-project-${LLVM_VERSION}.src"
    rm -rf "${LLVM_NATIVE_BUILD}"

    # Décimo noveno error real (2026-09-03): agregado libLLVM.so + libclang-cpp.so
    # NATIVAS a este build (targets CMake "LLVM" y "clang-cpp") -- hasta acá este
    # build nativo sólo pedía tres binarios puntuales (llvm-tblgen/llvm-config/
    # clang-tblgen), ninguno de los cuales termina necesitando el .so completo de
    # LLVM/Clang en tiempo de ejecución (son herramientas chicas, linkeadas contra
    # los .a estáticos que quedan en este mismo directorio). mesa_clc, en cambio,
    # SÍ necesita libLLVM.so/libclang-cpp.so NATIVAS de verdad -- ver el
    # comentario largo en step_mesa() sobre por qué (parchear su native:true no
    # alcanza sin esto). -DCLANG_LINK_CLANG_DYLIB=ON es el mismo flag que ya usa
    # step_llvm() (build CRUZADO) para producir libclang-cpp.so ahí; acá se repite
    # para el lado NATIVO. -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF por la misma razón
    # documentada en step_llvm(): evita que ese subdirectorio (la única fuente en
    # C puro de todo clang/llvm/tools, rompe el link con `gcc` en vez de `g++`)
    # se configure siquiera -- acá no debería hacer falta porque pedimos targets
    # puntuales, no "ninja" a secas, pero se deja por las dudas, no cuesta nada.
    cmake -S "${src}/llvm" -B "${LLVM_NATIVE_BUILD}" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${LFS_SYSROOT}/usr" \
        -DCLANG_LINK_CLANG_DYLIB=ON \
        -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF \
        "${LLVM_CMAKE_COMMON_FLAGS[@]}"

    # Vigésimo tercer error real (2026-09-04): además de llvm-tblgen/
    # llvm-config/clang-tblgen/LLVM/clang-cpp, hace falta el target de CMake
    # "clang-resource-headers" -- confirmado contra
    # clang/lib/Headers/CMakeLists.txt real (llvm-project, rama main):
    # `add_library(clang-resource-headers INTERFACE ${out_files})`, con
    # `opencl_files` (opencl-c.h, opencl-c-base.h) entre los headers que
    # copia, en `lib/clang/<version>/include/` relativo al directorio de
    # build (vía `get_clang_resource_dir()`). Sin este target ese
    # directorio no existe -- ninguno de los otros 5 targets lo genera como
    # efecto secundario. Esto lo destapó `-Dmesa-clc-bundle-headers=enabled`
    # (Vigésimo segundo error real) al fallar en tiempo de CONFIGURE de
    # Meson, no de compilación:
    #   src/compiler/clc/meson.build:25:20: ERROR: File
    #   .../llvm-native-build/lib/clang/23/include/opencl-c-base.h does not
    #   exist.
    # -- pero el gap era el mismo de fondo con el modo "runtime" (Vigésimo
    # segundo, antes de forzar el bundling): ese directorio tampoco existía
    # ahí, sólo que el error salía más tarde (al ejecutar mesa_clc) en vez
    # de en el configure. Bundling sigue siendo la estrategia correcta
    # (Vigésimo segundo error real) -- lo que faltaba era generar el
    # directorio de origen que ambos modos necesitan.
    ninja -C "${LLVM_NATIVE_BUILD}" ${MAKEFLAGS} llvm-tblgen llvm-config clang-tblgen LLVM clang-cpp clang-resource-headers

    [[ -x "${LLVM_TABLEGEN_NATIVE}" ]] || die "no se compiló llvm-tblgen nativo"
    [[ -x "${LLVM_NATIVE_BUILD}/bin/llvm-config" ]] || die "no se compiló llvm-config nativo"
    [[ -x "${CLANG_TABLEGEN_NATIVE}" ]] || die "no se compiló clang-tblgen nativo -- ¿LLVM_ENABLE_PROJECTS incluye 'clang'?"
    find "${LLVM_NATIVE_BUILD}/lib" -maxdepth 1 -name 'libLLVM.so*' 2>/dev/null | grep -q . \
        || die "no se compiló libLLVM.so nativa en ${LLVM_NATIVE_BUILD}/lib -- ¿el target 'LLVM' de CMake cambió de nombre?"
    find "${LLVM_NATIVE_BUILD}/lib" -maxdepth 1 -name 'libclang-cpp.so*' 2>/dev/null | grep -q . \
        || die "no se compiló libclang-cpp.so nativa en ${LLVM_NATIVE_BUILD}/lib -- ¿el target 'clang-cpp' de CMake cambió de nombre?"
    find "${LLVM_NATIVE_BUILD}/lib/clang" -mindepth 3 -maxdepth 3 -name 'opencl-c-base.h' 2>/dev/null | grep -q . \
        || die "no se generó opencl-c-base.h en ${LLVM_NATIVE_BUILD}/lib/clang/*/include -- ¿el target 'clang-resource-headers' de CMake cambió de nombre o de ruta de salida?"
    log "LLVM+Clang nativos listos: llvm-tblgen en ${LLVM_TABLEGEN_NATIVE}, clang-tblgen en ${CLANG_TABLEGEN_NATIVE}, libLLVM.so + libclang-cpp.so + resource headers (opencl-c*.h) en ${LLVM_NATIVE_BUILD}/lib"
}

step_llvm() {
    require_toolchain
    [[ -x "${LLVM_TABLEGEN_NATIVE}" && -x "${CLANG_TABLEGEN_NATIVE}" ]] \
        || die "no están llvm-tblgen/clang-tblgen NATIVOS en ${LLVM_NATIVE_BUILD}/bin -- corré primero: scripts/build-mesa.sh llvm-native"

    log "LLVM+Clang ${LLVM_VERSION} para ${LFS_TGT} — build CRUZADO (usa llvm-tblgen/clang-tblgen nativos)"
    _llvm_fetch_extract

    local src="${LFS_BUILD}/llvm-project-${LLVM_VERSION}.src"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/llvm-cross-build"
    rm -rf "${bdir}"

    cmake -S "${src}/llvm" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_TABLEGEN="${LLVM_TABLEGEN_NATIVE}" \
        -DCLANG_TABLEGEN="${CLANG_TABLEGEN_NATIVE}" \
        -DLLVM_DEFAULT_TARGET_TRIPLE="${LFS_TGT}" \
        -DLLVM_HOST_TRIPLE="${LFS_TGT}" \
        -DCLANG_LINK_CLANG_DYLIB=ON \
        -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF \
        "${LLVM_CMAKE_COMMON_FLAGS[@]}"

    # HISTORIA de este bloque (se deja completa a propósito -- las dos
    # rondas anteriores llevaron a un diagnóstico incompleto, vale la pena
    # que quede el resultado final Y el motivo del cambio de rumbo):
    #
    # Ronda 1 -- error real: pedir "ninja" sin target (= "all") intenta
    # construir TODOS los binarios de LLVM+Clang -- unos 4600 targets,
    # incluidos ~130 herramientas standalone que no usamos para nada
    # (llvm-mca, llvm-objdump, clang-fuzzer-dictionary, etc.). Uno de esos,
    # clang-fuzzer-dictionary (clang/tools/clang-fuzzer/dictionary/), rompía
    # el link real (dictionary.c es la única fuente puramente en C de todo
    # clang/llvm/tools -- CMake usa `gcc`, no `g++`, como driver de link
    # para ese target puntual, y `gcc` no agrega `-lstdc++` aunque el
    # binario dependa de libLLVM.so).
    #
    # Ronda 2 -- la respuesta que le dimos entonces fue acotar el build a
    # sólo 4 targets con nombre bien definido (LLVM, clang-cpp,
    # llvm-headers, clang-headers) más sus install-<nombre> -- evitando así
    # tocar clang-fuzzer-dictionary. Eso destapó DOS problemas nuevos, uno
    # atrás del otro, al llegar a SPIRV-LLVM-Translator (que resuelve LLVM
    # vía find_package(LLVM), CMake modo CONFIG):
    #   1. Faltaba LLVMConfig.cmake (componente aparte, "cmake-exports",
    #      que install-LLVM no trae) -- se agregó install-cmake-exports.
    #   2. Con LLVMConfig.cmake ya instalado, CMake tiraba:
    #        "The imported target LLVMDemangle references the file
    #         /lfs/usr/lib/libLLVMDemangle.a but this file does not exist"
    #      Causa raíz real (confirmada contra AddLLVM.cmake): CADA librería
    #      creada con add_llvm_library/add_llvm_component_library
    #      (LLVMDemangle, LLVMSupport, LLVMCore, ... son ~80) se agrega
    #      SIEMPRE a la propiedad global LLVM_EXPORTS, sin importar si
    #      pedimos construirla o instalarla -- no hay forma de "acotar" el
    #      build sin que LLVMExports.cmake termine listando componentes que
    #      nunca se instalaron. El único mecanismo real para exportar un
    #      subconjunto (LLVM_DISTRIBUTIONS, en LLVMDistributionSupport.cmake)
    #      es harina de otro costal -- exige coordinar Clang por separado y
    #      no vale la pena para lo que necesitamos acá.
    #
    # Ronda 3 (la actual, correcta) -- en vez de tratar de reconstruir a
    # mano el grafo de dependencias de instalación de un proyecto de este
    # tamaño, la solución real es la que LLVM ya provee para este caso
    # exacto: cada subcarpeta de clang/tools/ tiene su propio flag
    # "CLANG_TOOL_<NOMBRE>_BUILD" (autogenerado por
    # create_subdirectory_options() en clang/tools/CMakeLists.txt real,
    # consumido por add_llvm_subdirectory() en AddLLVM.cmake) -- la
    # investigación de la Ronda 1 decía que "no hay ningún guard", pero no
    # había mirado ese mecanismo genérico, sólo el CMakeLists.txt puntual
    # de clang-fuzzer/dictionary. Con -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF
    # (ver flags de cmake más arriba) directamente no se configura NADA de
    # clang-fuzzer/ (dictionary incluido) -- así que volvemos al build e
    # install COMPLETOS de siempre, que instalan todas las librerías reales
    # (dejando LLVMExports.cmake consistente) sin tocar el único target
    # roto.
    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    # Pisar el llvm-config cruzado (instalado recién por el "ninja install"
    # de arriba, pero NO ejecutable acá sin chroot) con el nativo -- ver el
    # comentario largo más arriba.
    install -Dm755 "${LLVM_NATIVE_BUILD}/bin/llvm-config" "${LFS_SYSROOT}/usr/bin/llvm-config"

    # El binario recién copiado trae un RPATH relativo ("$ORIGIN/../lib")
    # que, en su nueva ubicación, resuelve a ${LFS_SYSROOT}/usr/lib -- la
    # glibc CRUZADA, no la del contenedor (ver el comentario largo arriba de
    # este bloque). Se reescribe con patchelf para que apunte al build
    # nativo de LLVM, que tiene su propia libLLVM.so compatible. Esto NO
    # toca las rutas que imprime llvm-config (--includedir, etc.) -- esas
    # están grabadas aparte, en tiempo de compilación.
    command -v patchelf >/dev/null 2>&1 \
        || die "falta patchelf en el contenedor -- agregalo al Dockerfile (apt-get install patchelf) y correé 'podman-compose build' de nuevo"
    patchelf --set-rpath "${LLVM_NATIVE_BUILD}/lib" "${LFS_SYSROOT}/usr/bin/llvm-config"

    log "LLVM+Clang instalados en ${LFS_SYSROOT}/usr (libLLVM + libclang-cpp compartidas, llvm-config nativo pisado encima, RPATH corregido con patchelf)"
}

step_verify_llvm() {
    log "Verificación: LLVM+Clang en el sysroot + llvm-config nativo funcional"
    local ok=1
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libLLVM*.so*' 2>/dev/null | grep -q .; then
        echo "  [FALTA] libLLVM*.so en ${LFS_SYSROOT}/usr/lib"; ok=0
    else
        echo "  [OK] libLLVM*.so presente"
    fi
    # libclang-cpp.so: agregado 2026-09-02 -- lo necesita Mesa (dep_clang vía
    # cpp.find_library('clang-cpp', ...), ver bloque grande al principio del
    # archivo) para compilar mesa-clc/intel_clc (iris/anv).
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libclang-cpp.so*' 2>/dev/null | grep -q .; then
        echo "  [FALTA] libclang-cpp.so en ${LFS_SYSROOT}/usr/lib"; ok=0
    else
        echo "  [OK] libclang-cpp.so presente"
    fi
    local lc="${LFS_SYSROOT}/usr/bin/llvm-config"
    if [[ ! -x "${lc}" ]]; then
        echo "  [FALTA] ${lc}"; ok=0
    else
        local includedir
        if ! includedir="$("${lc}" --includedir 2>&1)"; then
            echo "  [FALTA] ${lc} no corrió bien: ${includedir}"; ok=0
        elif [[ "${includedir}" != "${LFS_SYSROOT}"* ]]; then
            echo "  [ADVERTENCIA] ${lc} --includedir devolvió '${includedir}' -- no arranca con ${LFS_SYSROOT}, Mesa probablemente NO va a encontrar los headers/libs correctos. Avisame si ves esto, es el punto más incierto de todo el script (ver comentario largo arriba de step_llvm)."
            ok=0
        else
            echo "  [OK] ${lc} --includedir = ${includedir}"
        fi
    fi
    # LLVMConfig.cmake: agregado 2026-09-02 -- lo necesita SPIRV-LLVM-Translator
    # (find_package(LLVM) en su CMakeLists.txt real) para encontrar a LLVM. Lo
    # instala el target install-cmake-exports, agregado en step_llvm() junto con
    # este chequeo tras el error real documentado en docs/PENDIENTES.md.
    if [[ ! -f "${LFS_SYSROOT}/usr/lib/cmake/llvm/LLVMConfig.cmake" ]]; then
        echo "  [FALTA] LLVMConfig.cmake en ${LFS_SYSROOT}/usr/lib/cmake/llvm"; ok=0
    else
        echo "  [OK] LLVMConfig.cmake presente"
    fi
    [[ "${ok}" -eq 1 ]] || die "falta algo de LLVM/Clang en el sysroot (ver arriba)"
    log "OK: LLVM+Clang completos y llvm-config funcional."
}

# ------------------------------------------------------------------------------
# 4) glslang — CMake, build 100% NATIVO (sin cross-file, sin sysroot).
#
# CORRECCIÓN (post-build real, 2026-08-31, en dos pasos): Mesa necesita
# glslangValidator en tiempo de build para compilar shaders internos
# (GLSL -> SPIR-V). Primer error real: no estaba instalado -- se agregó
# glslang-tools al Dockerfile (apt). Segundo error real, con el paquete de
# apt ya instalado: "ERROR: glslang >= 12.2 is required" -- el glslang de
# Debian bookworm queda por debajo de ese piso (mismo motivo que ya llevó a
# instalar meson por pip y rust por rustup en vez de apt, Fase 2). Acá no
# hay pip/rustup equivalente para glslang, así que se compila de fuente,
# igual que LLVM más arriba -- pero mucho más simple: glslangValidator
# SÓLO genera código en tiempo de build, nunca corre en el sysroot final,
# así que no hace falta NADA de lo que hizo delicado a LLVM (ni dos etapas,
# ni RPATH, ni CMAKE_INSTALL_PREFIX apuntando al sysroot) -- un build
# nativo derecho, con un prefix nativo cualquiera, alcanza.
# -DENABLE_OPT=OFF evita necesitar SPIRV-Tools como dependencia externa
# (confirmado contra el CMakeLists.txt real de glslang: con ENABLE_OPT=OFF
# no hace falta ningún submódulo/dependencia externa) -- Mesa sólo necesita
# el compilador de shaders, no el optimizador de SPIR-V.
# ------------------------------------------------------------------------------
GLSLANG_NATIVE_BUILD="${LFS_BUILD}/glslang-native-build"
GLSLANG_NATIVE_INSTALL="${LFS_BUILD}/glslang-native-install"
GLSLANG_NATIVE_BIN="${GLSLANG_NATIVE_INSTALL}/bin/glslangValidator"

step_glslang_native() {
    if [[ -x "${GLSLANG_NATIVE_BIN}" ]]; then
        log "glslangValidator nativo ya compilado en ${GLSLANG_NATIVE_BIN}"
        return 0
    fi
    log "glslang ${GLSLANG_VERSION} — build NATIVO (glslangValidator, Mesa exige >=12.2)"

    cd "${LFS_SOURCES}"
    fetch "${GLSLANG_MIRROR}/${GLSLANG_VERSION}.tar.gz" "glslang-${GLSLANG_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/glslang-${GLSLANG_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/glslang-${GLSLANG_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-glslang"

    local src="${LFS_BUILD}/glslang-${GLSLANG_VERSION}"
    rm -rf "${GLSLANG_NATIVE_BUILD}"

    cmake -S "${src}" -B "${GLSLANG_NATIVE_BUILD}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${GLSLANG_NATIVE_INSTALL}" \
        -DENABLE_OPT=OFF \
        -DENABLE_GLSLANG_BINARIES=ON \
        -DBUILD_TESTING=OFF

    ninja -C "${GLSLANG_NATIVE_BUILD}" ${MAKEFLAGS}
    ninja -C "${GLSLANG_NATIVE_BUILD}" install

    [[ -x "${GLSLANG_NATIVE_BIN}" ]] || die "no se compiló glslangValidator nativo"
    log "glslangValidator nativo listo en ${GLSLANG_NATIVE_BIN}"
}

# ------------------------------------------------------------------------------
# 5) SPIRV-Headers — sin build propio, sólo dos checkouts de fuente (headers +
# gramática JSON de Khronos). Dos copias SEPARADAS a propósito: SPIRV-Tools y
# SPIRV-LLVM-Translator piden cada uno un commit distinto (confirmado leyendo
# el DEPS real de SPIRV-Tools y el spirv-headers-tag.conf real de
# SPIRV-LLVM-Translator -- no son el mismo commit, así que no se asume que
# son intercambiables). Ver env.sh para el porqué de cada commit puntual.
# ------------------------------------------------------------------------------
SPIRV_HEADERS_FOR_TOOLS_DIR="${LFS_BUILD}/SPIRV-Headers-${SPIRV_HEADERS_FOR_TOOLS_COMMIT}"
SPIRV_HEADERS_FOR_TRANSLATOR_DIR="${LFS_BUILD}/SPIRV-Headers-${SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT}"

step_spirv_headers() {
    log "SPIRV-Headers — dos checkouts de fuente (uno para SPIRV-Tools, otro para SPIRV-LLVM-Translator)"

    cd "${LFS_SOURCES}"
    fetch "${SPIRV_HEADERS_MIRROR}/${SPIRV_HEADERS_FOR_TOOLS_COMMIT}.tar.gz" \
          "spirv-headers-${SPIRV_HEADERS_FOR_TOOLS_COMMIT}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-headers-${SPIRV_HEADERS_FOR_TOOLS_COMMIT}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-headers-${SPIRV_HEADERS_FOR_TOOLS_COMMIT}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-headers-for-tools"

    fetch "${SPIRV_HEADERS_MIRROR}/${SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT}.tar.gz" \
          "spirv-headers-${SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-headers-${SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-headers-${SPIRV_HEADERS_FOR_TRANSLATOR_COMMIT}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-headers-for-translator"

    [[ -d "${SPIRV_HEADERS_FOR_TOOLS_DIR}" ]] \
        || die "no se extrajo SPIRV-Headers para SPIRV-Tools en ${SPIRV_HEADERS_FOR_TOOLS_DIR} -- si el archive de GitHub arma el directorio con otro nombre (ver comentario de SPIRV_HEADERS_MIRROR en env.sh), avisame con el nombre real y lo ajusto"
    [[ -d "${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}" ]] \
        || die "no se extrajo SPIRV-Headers para SPIRV-LLVM-Translator en ${SPIRV_HEADERS_FOR_TRANSLATOR_DIR} (mismo comentario que arriba)"
    log "SPIRV-Headers listos: ${SPIRV_HEADERS_FOR_TOOLS_DIR} y ${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}"
}

# ------------------------------------------------------------------------------
# 6) SPIRV-Tools — CMake, build CRUZADO. Provee libSPIRV-Tools + el
# SPIRV-Tools.pc que tanto Mesa como SPIRV-LLVM-Translator buscan por
# pkg-config. SPIRV_SKIP_EXECUTABLES=ON fuerza SPIRV_SKIP_TESTS=ON
# (confirmado en el CMakeLists.txt real: "if (SPIRV_SKIP_EXECUTABLES) set
# (SPIRV_SKIP_TESTS ON)") -- evita todo el bloque de external/CMakeLists.txt
# que si no intentaría configurar googletest/effcee/re2/protobuf/abseil (sólo
# hacen falta para los tests, que no vamos a correr; ninguno de esos
# proyectos está en nuestras fuentes y sin este flag el build fallaría
# pidiéndolos). -DSPIRV-Headers_SOURCE_DIR apunta al checkout ya bajado por
# step_spirv_headers() -- evita el FetchContent+git clone que el propio
# CMakeLists.txt de SPIRV-Tools intentaría si no se lo pisamos (ver
# comentario de fetch() en este mismo archivo sobre por qué este proyecto no
# depende de git en tiempo de build).
# ------------------------------------------------------------------------------
step_spirv_tools() {
    require_toolchain
    [[ -d "${SPIRV_HEADERS_FOR_TOOLS_DIR}" ]] \
        || die "no está SPIRV-Headers para SPIRV-Tools -- corré primero: scripts/build-mesa.sh spirv-headers"

    log "SPIRV-Tools ${SPIRV_TOOLS_VERSION} para ${LFS_TGT} — CMake+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${SPIRV_TOOLS_MIRROR}/v${SPIRV_TOOLS_VERSION}.tar.gz" "spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-tools"

    # GitHub arma el directorio del archive de un tag como "<repo>-<tag sin
    # la 'v' inicial>" -- mismo patrón que systemd/uutils en este proyecto.
    local src="${LFS_BUILD}/SPIRV-Tools-${SPIRV_TOOLS_VERSION}"
    [[ -d "${src}" ]] || die "no se extrajo SPIRV-Tools en ${src} -- si el directorio real tiene otro nombre avisame con \`tar -tzf sources/spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz | head\` y lo ajusto"
    cd "${src}"

    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/spirv-tools-cross-build"
    rm -rf "${bdir}"

    # -DSPIRV_WERROR=OFF: SPIRV-Tools compila con -Werror por default (pensado
    # para su propio CI, con compiladores puntuales ya probados) -- con
    # nuestro cross-gcc puede saltar algún warning benigno no contemplado
    # ahí; no vale la pena que tire abajo el build entero por eso.
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DSPIRV-Headers_SOURCE_DIR="${SPIRV_HEADERS_FOR_TOOLS_DIR}" \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_WERROR=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "SPIRV-Tools instalado en ${LFS_SYSROOT}/usr"
}

step_verify_spirv_tools() {
    log "Verificación: SPIRV-Tools.pc en el sysroot"
    local ok=1
    if find "${LFS_SYSROOT}/usr/lib/pkgconfig" -maxdepth 1 -name 'SPIRV-Tools.pc' 2>/dev/null | grep -q .; then
        echo "  [OK] SPIRV-Tools.pc presente"
    else
        echo "  [FALTA] SPIRV-Tools.pc en ${LFS_SYSROOT}/usr/lib/pkgconfig"; ok=0
    fi
    [[ "${ok}" -eq 1 ]] || die "falta SPIRV-Tools en el sysroot"
    log "OK: SPIRV-Tools completo en el sysroot."
}

# ------------------------------------------------------------------------------
# 6b) SPIRV-Tools NATIVO — CMake, build NATIVO (sin --cross-file, sin
# sysroot). Vigésimo error real (2026-09-04): hace falta para el mesa_clc
# NATIVO de la sección "7c" más abajo — ver el comentario grande ahí sobre
# por qué mesa_clc no puede seguir compilándose con native:true a mano
# adentro del build CRUZADO de Mesa (Décimo noveno parte 2, revertido en
# este mismo commit). Mismos flags de CMake que la versión cruzada
# (step_spirv_tools()) salvo que acá no hay --cross-file/toolchain
# (compilador nativo del propio contenedor) y el --prefix es un directorio
# de build-tools cualquiera bajo ${LFS_BUILD}, NUNCA ${LFS_SYSROOT} — esto
# no se instala en el sysroot final, es sólo una herramienta de build-time
# (mismo patrón que glslang-native).
# ------------------------------------------------------------------------------
SPIRV_TOOLS_NATIVE_INSTALL="${LFS_BUILD}/spirv-tools-native-install"

step_spirv_tools_native() {
    if [[ -f "${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig/SPIRV-Tools.pc" ]]; then
        log "SPIRV-Tools NATIVO ya compilado en ${SPIRV_TOOLS_NATIVE_INSTALL}"
        return 0
    fi
    [[ -d "${SPIRV_HEADERS_FOR_TOOLS_DIR}" ]] \
        || die "no está SPIRV-Headers para SPIRV-Tools -- corré primero: scripts/build-mesa.sh spirv-headers"

    log "SPIRV-Tools ${SPIRV_TOOLS_VERSION} NATIVO — CMake+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${SPIRV_TOOLS_MIRROR}/v${SPIRV_TOOLS_VERSION}.tar.gz" "spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-tools-${SPIRV_TOOLS_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-tools"

    local src="${LFS_BUILD}/SPIRV-Tools-${SPIRV_TOOLS_VERSION}"
    [[ -d "${src}" ]] || die "no se extrajo SPIRV-Tools en ${src}"

    local bdir="${LFS_BUILD}/spirv-tools-native-build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${SPIRV_TOOLS_NATIVE_INSTALL}" \
        -DSPIRV-Headers_SOURCE_DIR="${SPIRV_HEADERS_FOR_TOOLS_DIR}" \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_WERROR=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    [[ -f "${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig/SPIRV-Tools.pc" ]] \
        || die "no se instaló SPIRV-Tools.pc NATIVO en ${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig"
    log "SPIRV-Tools NATIVO listo en ${SPIRV_TOOLS_NATIVE_INSTALL}"
}

# ------------------------------------------------------------------------------
# 7) SPIRV-LLVM-Translator — CMake, build CRUZADO, standalone (fuera del
# árbol de llvm-project, apuntando al LLVM ya cruzado e instalado en el
# sysroot vía -DLLVM_DIR). Provee libLLVMSPIRVLib + el LLVMSPIRVLib.pc que
# pide directo el meson.build real de Mesa.
#
# -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR apunta al checkout de
# step_spirv_headers() (el commit que pide ESTE proyecto puntual, distinto
# al de SPIRV-Tools) -- confirmado contra el CMakeLists.txt real de la rama
# llvm_release_230 que si no se lo pisamos intenta un FetchContent+git clone
# de SPIRV-Headers.git en tiempo de configure, algo que este proyecto evita
# en todos lados por la conexión inestable (ver fetch() más arriba).
#
# BASE_LLVM_VERSION=23.1.0 está fijado adentro del propio CMakeLists.txt de
# esta rama (llvm_release_230) -- coincide exacto con nuestro LLVM_VERSION,
# confirmando que es la rama correcta (no una suposición por continuidad
# numérica de nombre de rama).
#
# PKG_CONFIG_PATH: SPIRV-LLVM-Translator intenta encontrar SPIRV-Tools por
# pkg-config primero (pkg_search_module, opcional -- sólo habilita el flag
# --spirv-tools-dis de su CLI, que no usamos) -- se lo damos igual porque ya
# lo tenemos armado (step_spirv_tools) y no cuesta nada extra.
# ------------------------------------------------------------------------------
SPIRV_LLVM_TRANSLATOR_SRC="${LFS_BUILD}/SPIRV-LLVM-Translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}"

step_spirv_llvm_translator() {
    require_toolchain
    [[ -x "${LFS_SYSROOT}/usr/bin/llvm-config" ]] \
        || die "no está LLVM en el sysroot -- corré primero: scripts/build-mesa.sh llvm"
    [[ -d "${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}" ]] \
        || die "no está SPIRV-Headers para SPIRV-LLVM-Translator -- corré primero: scripts/build-mesa.sh spirv-headers"

    log "SPIRV-LLVM-Translator (llvm_release_230, commit ${SPIRV_LLVM_TRANSLATOR_COMMIT:0:12}) para ${LFS_TGT} — CMake+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${SPIRV_LLVM_TRANSLATOR_MIRROR}/${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz" \
          "spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-llvm-translator"

    [[ -d "${SPIRV_LLVM_TRANSLATOR_SRC}" ]] \
        || die "no se extrajo SPIRV-LLVM-Translator en ${SPIRV_LLVM_TRANSLATOR_SRC} -- si el directorio real tiene otro nombre avisame con \`tar -tzf sources/spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz | head\` y lo ajusto"
    cd "${SPIRV_LLVM_TRANSLATOR_SRC}"

    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/spirv-llvm-translator-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_PATH="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    cmake -S "${SPIRV_LLVM_TRANSLATOR_SRC}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_DIR="${LFS_SYSROOT}/usr/lib/cmake/llvm" \
        -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}" \
        -DLLVM_SPIRV_INCLUDE_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "SPIRV-LLVM-Translator instalado en ${LFS_SYSROOT}/usr"
}

step_verify_spirv_llvm_translator() {
    log "Verificación: LLVMSPIRVLib.pc en el sysroot"
    local ok=1
    if find "${LFS_SYSROOT}/usr/lib/pkgconfig" -maxdepth 1 -name 'LLVMSPIRVLib.pc' 2>/dev/null | grep -q .; then
        echo "  [OK] LLVMSPIRVLib.pc presente"
    else
        echo "  [FALTA] LLVMSPIRVLib.pc en ${LFS_SYSROOT}/usr/lib/pkgconfig"; ok=0
    fi
    [[ "${ok}" -eq 1 ]] || die "falta SPIRV-LLVM-Translator en el sysroot"
    log "OK: SPIRV-LLVM-Translator completo en el sysroot."
}

# ------------------------------------------------------------------------------
# 7b) SPIRV-LLVM-Translator NATIVO — CMake, build NATIVO, standalone, apunta
# al LLVM NATIVO (${LLVM_NATIVE_BUILD}) SIN instalarlo -- LLVM genera su
# LLVMConfig.cmake de "build tree" apenas corre el cmake configure, sin
# hacer falta ningún "ninja install" (mecanismo estándar y documentado de
# LLVM/CMake para poder usar un LLVM recién compilado antes de instalarlo --
# confirmado contra el comportamiento real de AddLLVM.cmake/
# LLVMConfig.cmake.in del propio LLVM, 2026-09-04: el archivo de build-tree
# se escribe en tiempo de CONFIGURE, aparte del de install-tree que sí
# necesita el target install-cmake-exports que ya usa step_llvm() más
# arriba). Hace falta para mesa_clc NATIVO -- ver comentario grande en la
# sección "7c" más abajo (Vigésimo error real).
# ------------------------------------------------------------------------------
SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL="${LFS_BUILD}/spirv-llvm-translator-native-install"

step_spirv_llvm_translator_native() {
    if [[ -f "${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}/lib/pkgconfig/LLVMSPIRVLib.pc" ]]; then
        log "SPIRV-LLVM-Translator NATIVO ya compilado en ${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}"
        return 0
    fi
    [[ -f "${LLVM_NATIVE_BUILD}/lib/cmake/llvm/LLVMConfig.cmake" ]] \
        || die "no está LLVMConfig.cmake NATIVO en ${LLVM_NATIVE_BUILD}/lib/cmake/llvm -- corré primero: scripts/build-mesa.sh llvm-native"
    [[ -f "${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig/SPIRV-Tools.pc" ]] \
        || die "no está SPIRV-Tools NATIVO -- corré primero: scripts/build-mesa.sh spirv-tools-native"
    [[ -d "${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}" ]] \
        || die "no está SPIRV-Headers para SPIRV-LLVM-Translator -- corré primero: scripts/build-mesa.sh spirv-headers"

    log "SPIRV-LLVM-Translator (llvm_release_230, commit ${SPIRV_LLVM_TRANSLATOR_COMMIT:0:12}) NATIVO — CMake+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${SPIRV_LLVM_TRANSLATOR_MIRROR}/${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz" \
          "spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz"
    log_sha256 "${LFS_SOURCES}/spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz"
    extract_once "${LFS_SOURCES}/spirv-llvm-translator-${SPIRV_LLVM_TRANSLATOR_COMMIT}.tar.gz" \
                 "${LFS_BUILD}/.extracted-spirv-llvm-translator"

    [[ -d "${SPIRV_LLVM_TRANSLATOR_SRC}" ]] \
        || die "no se extrajo SPIRV-LLVM-Translator en ${SPIRV_LLVM_TRANSLATOR_SRC}"

    local bdir="${LFS_BUILD}/spirv-llvm-translator-native-build"
    rm -rf "${bdir}"

    PKG_CONFIG_PATH="${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig" \
    cmake -S "${SPIRV_LLVM_TRANSLATOR_SRC}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}" \
        -DLLVM_DIR="${LLVM_NATIVE_BUILD}/lib/cmake/llvm" \
        -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="${SPIRV_HEADERS_FOR_TRANSLATOR_DIR}" \
        -DLLVM_SPIRV_INCLUDE_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    [[ -f "${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}/lib/pkgconfig/LLVMSPIRVLib.pc" ]] \
        || die "no se instaló LLVMSPIRVLib.pc NATIVO en ${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}/lib/pkgconfig"
    log "SPIRV-LLVM-Translator NATIVO listo en ${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}"
}

# ------------------------------------------------------------------------------
# 7bis) elfutils (en la práctica, sólo libelf) — Autotools. Décimo quinto error
# real (2026-09-02): con LLVM+Clang y SPIRV-LLVM-Translator ya completos en el
# sysroot, el "meson setup" de Mesa avanzó y recién ahí frenó:
#   Run-time dependency libelf found: NO (tried pkg-config and cmake)
#   Library elf found: NO
#   meson.build:2149:2: ERROR: Problem encountered: Gallium driver radeonsi requires libelf
#
# Causa raíz: el driver Gallium radeonsi (AMD, elegido para la RX 7700 real
# del lab -- ver aviso al principio del archivo) usa libelf en su runtime
# linker de ELF (src/amd/common/ac_rtld.c, para relocar en tiempo de
# ejecución los binarios que el propio backend AMDGPU de LLVM produce al
# compilar shaders) -- no es opcional para esa selección de drivers. Ningún
# paso anterior de este proyecto compiló libelf para ${LFS_TGT}: el
# "libelf-dev" que ya está en el Dockerfile es del compilador NATIVO del
# contenedor (build machine), y esto es un build cruzado -- Mesa resuelve
# dependencias contra ${LFS_SYSROOT}, no contra el sysroot del host.
#
# Se compila el paquete elfutils COMPLETO, no sólo el subdirectorio libelf/ a
# mano: confirmado contra el Makefile.am real (rama principal del repo,
# 2026-09-02) que SUBDIRS ahí es una lista fija sin ningún equivalente al
# create_subdirectory_options() de LLVM/Clang (ver la lección grande del
# Décimo quinto error de arriba, la de LLVM) -- no hay mecanismo oficial para
# levantar sólo una parte, así que recortarlo a mano acá repetiría el mismo
# error de fondo que ya costó dos rondas con LLVM. No hace falta preocuparse
# por el costo: elfutils es chico, construir debuginfod/libdw/libasm/eu-* de
# más son segundos, no las horas de LLVM.
#
# Tampoco se busca instalar/verificar un libelf.pc: confirmado contra
# libelf/Makefile.am real que esta librería nunca generó uno (no hay
# libelf.pc.in en el árbol) -- por eso el log de Mesa arriba prueba las DOS
# rutas ("Run-time dependency" vía pkg-config/cmake, y por separado "Library
# elf" vía cc.find_library) antes de rendirse; a nosotros nos alcanza con
# que exista libelf.so instalado, que es lo que la segunda ruta encuentra.
#
# Flags de configure: --disable-nls (no hace falta i18n acá, evita depender
# de que gettext/msgfmt generen catálogos .mo bien en cruzado);
# --disable-libdebuginfod / --disable-debuginfod (el configure.ac real ya
# los deja en "no" solo si no encuentra libcurl/json-c/libmicrohttpd/
# libarchive/sqlite3 -- ninguno está en el sysroot -- pero se pasan
# explícitos para no depender de ese autodescubrimiento). zlib (el único
# requisito "mandatory" real de elfutils, confirmado contra configure.ac:
# "zlib is mandatory") ya está en el sysroot desde build-comms.sh; bzip2/xz/
# zstd quedan en su default "auto" y se autodesactivan solos -- no hacen
# falta para libelf.
# ------------------------------------------------------------------------------
step_elfutils() {
    require_toolchain
    log "elfutils ${ELFUTILS_VERSION} para ${LFS_TGT} (libelf, lo necesita radeonsi de Mesa)"

    cd "${LFS_SOURCES}"
    fetch "${ELFUTILS_MIRROR}/${ELFUTILS_VERSION}/elfutils-${ELFUTILS_VERSION}.tar.bz2" \
          "elfutils-${ELFUTILS_VERSION}.tar.bz2"
    log_sha256 "${LFS_SOURCES}/elfutils-${ELFUTILS_VERSION}.tar.bz2"
    extract_once "${LFS_SOURCES}/elfutils-${ELFUTILS_VERSION}.tar.bz2" \
                 "${LFS_BUILD}/.extracted-elfutils"

    local src="${LFS_BUILD}/elfutils-${ELFUTILS_VERSION}"

    local bdir="${src}/build"
    # rm -rf, no sólo mkdir -p: a diferencia de libnftnl/libmnl (que nunca
    # tuvieron una corrida previa fallida acá), esta vez sí puede quedar un
    # ${bdir} de una corrida anterior que falló a mitad de camino.
    rm -rf "${bdir}"
    mkdir -p "${bdir}"
    cd "${bdir}"

    # CFLAGS=-Wno-error=discarded-qualifiers (Décimo séptimo error real, ver
    # docs/PENDIENTES.md): bug SISTÉMICO de elfutils 0.191, no de un archivo
    # puntual -- la primera corrida real rompió en libcpu/riscv_disasm.c
    # (bsearch sobre una tabla const, variable destino sin const) y, apenas
    # parcheado ESE archivo a mano, la corrida siguiente rompió en
    # libdw/dwarf_getsrclines.c con el mismo patrón pero con memchr (3 veces
    # en ese único archivo). El glibc cross-compilado de este proyecto
    # (Fase 2) le da a varias funciones de <string.h>/<search.h> (bsearch,
    # memchr, etc.) overloads const-correctos bajo _FORTIFY_SOURCE=3 (activo
    # acá, confirmado en el log de configure) que elfutils 0.191 -- escrito
    # antes de que esos overloads existieran en glibc -- no anticipa, y
    # `-Werror` (que elfutils trae de fábrica, ver AM_CFLAGS en su
    # config/eu.am real: "$(if $($(*F)_no_Werror),,-Werror)", sin ningún
    # --disable-werror que lo apague entero) convierte cada uno en build
    # roto. Parchear archivo por archivo cada vez que aparece uno nuevo no
    # escala -- no hay forma de saber cuántos más hay sin correr el build
    # completo.
    #
    # En vez de eso, se apaga sólo ESA clase de warning (no todo -Werror,
    # que elfutils sigue usando para todo lo demás) agregándola a CFLAGS acá:
    # confirmado contra config/eu.am real que la regla de compilación de
    # Automake pone $(AM_CFLAGS) (donde vive el -Werror de elfutils) ANTES
    # que $(CFLAGS) en la línea real de gcc -- un -Wno-error=<clase> que
    # aparezca DESPUÉS en la misma línea gana para esa clase puntual,
    # dejando el resto de los warnings de elfutils como error igual. Se pasa
    # "-g -O2" también porque autoconf sólo pone esos por default si CFLAGS
    # viene sin setear -- si nosotros lo seteamos, hay que repetirlos a mano
    # o se pierden (confirmado contra el configure.ac real: el bloque de
    # _FORTIFY_SOURCE hace "CFLAGS=\"$fortified_cflags $save_CFLAGS\"", así
    # que lo que pongamos acá sobrevive completo, con -D_FORTIFY_SOURCE=3
    # antepuesto).
    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    CFLAGS="-g -O2 -Wno-error=discarded-qualifiers" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --program-prefix="eu-" \
        --disable-nls \
        --disable-libdebuginfod \
        --disable-debuginfod

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install

    log "elfutils (libelf) instalado en ${LFS_SYSROOT}/usr"
}

step_verify_elfutils() {
    log "Verificación: libelf.so + libelf.h en el sysroot"
    local ok=1
    if [[ -e "${LFS_SYSROOT}/usr/include/libelf.h" ]]; then
        echo "  [OK] ${LFS_SYSROOT}/usr/include/libelf.h"
    else
        echo "  [FALTA] ${LFS_SYSROOT}/usr/include/libelf.h"; ok=0
    fi
    if find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libelf.so*' 2>/dev/null | grep -q .; then
        echo "  [OK] libelf.so presente"
    else
        echo "  [FALTA] libelf.so en ${LFS_SYSROOT}/usr/lib"; ok=0
    fi
    [[ "${ok}" -eq 1 ]] || die "falta elfutils/libelf en el sysroot"
    log "OK: elfutils (libelf) completo en el sysroot."
}

# ------------------------------------------------------------------------------
# 7c) mesa_clc + vtn_bindgen2 NATIVOS — build de Mesa APARTE, 100% nativo
# (sin --cross-file), siguiendo al pie de la letra la receta OFICIAL de
# Mesa para este escenario exacto (confirmado contra docs.mesa3d.org/
# android.html, sección "cross-compiling the nvk driver", 2026-09-04 -- ese
# doc es sobre Android/nvk pero la receta en sí es genérica de Meson/Mesa,
# no específica de esa plataforma):
#
#   meson setup build-compiler -Dprefix=... -Dbuildtype=release -Dstrip=true
#       -Dplatforms= -Dgallium-drivers= -Dvulkan-drivers=
#       -Dmesa-clc=enabled -Dinstall-mesa-clc=true
#   meson install -C build-compiler
#   export PATH=.../bin:$PATH   # acá se resuelve con --native-file en vez
#                                  de PATH (ver más abajo)
#
# Vigésimo error real (2026-09-04) -- por qué esto reemplaza por completo el
# intento anterior (Décimo noveno, parte 2, revertido en este mismo commit):
# forzar native:true a mano en el executable('mesa_clc', ...) de
# src/compiler/clc/meson.build (adentro del build CRUZADO de Mesa) hacía que
# mesa_clc pasara a compilarse con el compilador nativo, pero
# idep_mesaclc/_libmesaclc (la libmesaclc estática de la que depende) sigue
# declarada SIN native: en ese mismo archivo (confirmado leyendo el archivo
# real completo, mirror/mesa, src/compiler/clc/meson.build) -- por default
# eso la deja en contexto HOST (cruzado), y con mesa_clc ya native:true,
# Meson rechaza mezclar los dos contextos en el mismo link. Error real
# visto:
#   src/compiler/clc/meson.build:129:18: ERROR: Tried to mix a host machine
#   library ("libmesaclc") with a build machine target "mesa_clc" This is
#   not possible in a cross build.
# Parchear TAMBIÉN _libmesaclc a native:true no alcanzaba tampoco: esa
# librería a su vez depende de dep_llvm/dep_clang/dep_spirv_tools/
# dep_llvmspirvlib, TODAS declaradas sin native: en el meson.build raíz real
# de Mesa (confirmado leyéndolo completo) -- forzar sólo _libmesaclc native
# hubiera reproducido el MISMO error de mezcla de contextos un nivel más
# abajo, ahora entre _libmesaclc (native) y dep_llvm (host). La única forma
# de arreglar eso de raíz sería declarar TODA una segunda copia native de
# LLVM/Clang/SPIRV-Tools/LLVMSPIRVLib adentro del propio meson.build de
# Mesa -- reescribir a mano el build system entero de Mesa, inviable.
#
# La receta real de Mesa para este problema (confirmada en el meson.build
# raíz real: `if get_option('mesa-clc') == 'system' prog_mesa_clc =
# find_program('mesa_clc', native : true) ... else with_clc = ... or
# with_driver_using_cl endif`, y en meson.options: option 'mesa-clc' con
# choice 'system', descripción de 'install-mesa-clc': "Install the mesa-clc
# compiler (if needed for cross builds)") es mucho más simple: no tratar de
# que el build CRUZADO compile mesa_clc en absoluto. En cambio, acá se
# compila un mesa_clc + vtn_bindgen2 100% NATIVOS en un build de Mesa
# COMPLETAMENTE APARTE (sin --cross-file, sólo -Dmesa-clc=enabled
# -Dinstall-mesa-clc=true y todos los drivers vacíos -- no hace falta
# compilar ningún driver para esto, sólo src/compiler/{nir,spirv,clc} +
# src/util), y se le pasan a Mesa esos dos binarios ya construidos vía
# --native-file (mesa_clc/vtn_bindgen2 en [binaries]) + -Dmesa-clc=system en
# el build CRUZADO real (ver step_mesa()) -- ahí `with_clc` queda en false
# (este proyecto no usa rusticl), así que src/compiler/clc/meson.build ni
# siquiera se procesa en el build cruzado: cero mezcla de contextos posible,
# porque _libmesaclc/idep_mesaclc/dep_llvm-en-contexto-host nunca entran en
# juego ahí.
#
# Confirmado que esto no deja nada a medias revisando quién más usa
# prog_mesa_clc/prog_vtn_bindgen2 en el árbol real de Mesa (mirror/mesa,
# src/intel/blorp/meson.build): sólo como comando de un custom_target()
# (blorp_shaders_spv, compila blorp_shaders.cl a SPIR-V) -- se invoca como
# programa ya compilado, no se linkea contra nada, así que basta con que el
# binario NATIVO exista y corra.
#
# Dependencias NATIVAS que hacen falta para este build aparte (mismo patrón
# que este script ya venía usando para LLVM/glslang, ahora también para
# SPIRV-Tools/SPIRV-LLVM-Translator -- ver las dos secciones NATIVO justo
# arriba de ésta): LLVM+Clang nativos (llvm-native, ya existía desde el
# Décimo noveno), SPIRV-Tools nativo y SPIRV-LLVM-Translator nativo (los dos
# nuevos de este fix).
#
# --native-file: llvm-config apunta directo a
# ${LLVM_NATIVE_BUILD}/bin/llvm-config (sin instalar, mismo mecanismo de
# "build tree" que SPIRV-LLVM-Translator-native de arriba) -- se declara
# explícito para no depender de qué llvm-config haya en el PATH del
# contenedor (podría ser uno viejo de apt, mismo motivo que la
# "CORRECCIÓN #2" de step_llvm() más arriba). pkg_config_libdir con las dos
# instalaciones NATIVAS de SPIRV-Tools/SPIRV-LLVM-Translator.
#
# patchelf al final: mismo motivo que la "red de seguridad" que este script
# ya usaba para el mesa_clc CRUZADO (Décimo octavo/noveno, ahora removida de
# step_mesa() porque ya no aplica) -- mesa_clc NATIVO linkea contra
# libLLVM.so/libclang-cpp.so NATIVAS que están en ${LLVM_NATIVE_BUILD}/lib,
# un directorio que no es una ruta de librerías del sistema. vtn_bindgen2 NO
# lo necesita: sus dependencias (idep_vtn, idep_mesautil, idep_nir) son
# todas internas de Mesa, sin LLVM de por medio (confirmado leyendo el
# executable() real de vtn_bindgen2 en src/compiler/spirv/meson.build).
# ------------------------------------------------------------------------------
MESA_CLC_NATIVE_INSTALL="${LFS_BUILD}/mesa-clc-native-install"
MESA_CLC_NATIVE_BIN="${MESA_CLC_NATIVE_INSTALL}/bin/mesa_clc"
VTN_BINDGEN2_NATIVE_BIN="${MESA_CLC_NATIVE_INSTALL}/bin/vtn_bindgen2"

step_mesa_clc_native() {
    [[ -x "${LLVM_TABLEGEN_NATIVE}" ]] \
        || die "no están LLVM/Clang NATIVOS -- corré primero: scripts/build-mesa.sh llvm-native"
    find "${LLVM_NATIVE_BUILD}/lib" -maxdepth 1 -name 'libLLVM.so*' 2>/dev/null | grep -q . \
        || die "no está libLLVM.so NATIVA en ${LLVM_NATIVE_BUILD}/lib -- corré primero: scripts/build-mesa.sh llvm-native"
    find "${LLVM_NATIVE_BUILD}/lib" -maxdepth 1 -name 'libclang-cpp.so*' 2>/dev/null | grep -q . \
        || die "no está libclang-cpp.so NATIVA en ${LLVM_NATIVE_BUILD}/lib -- corré primero: scripts/build-mesa.sh llvm-native"
    [[ -f "${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig/SPIRV-Tools.pc" ]] \
        || die "no está SPIRV-Tools NATIVO -- corré primero: scripts/build-mesa.sh spirv-tools-native"
    [[ -f "${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}/lib/pkgconfig/LLVMSPIRVLib.pc" ]] \
        || die "no está SPIRV-LLVM-Translator NATIVO -- corré primero: scripts/build-mesa.sh spirv-llvm-translator-native"

    log "Mesa ${MESA_VERSION} -- build aparte 100% NATIVO SÓLO para mesa_clc + vtn_bindgen2 (Vigésimo error real, ver comentario grande arriba)"

    cd "${LFS_SOURCES}"
    fetch "${MESA_MIRROR}/mesa-mesa-${MESA_VERSION}.tar.gz" "mesa-${MESA_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/mesa-${MESA_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/mesa-${MESA_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-mesa"

    local src="${LFS_BUILD}/mesa-mesa-${MESA_VERSION}"
    [[ -d "${src}" ]] || die "no se extrajo Mesa en ${src}"
    cd "${src}"

    # Vigésimo primer error real (2026-09-04): con lo anterior ya andando,
    # `_libmesaclc` (src/compiler/clc/clc_helpers.cpp) rompe en compilación
    # (no en configure) con:
    #   clc_helpers.cpp:45:10: fatal error: clang/Config/config.h: No such
    #   file or directory
    # Causa raíz: `dep_clang` en Mesa se resuelve con
    # `cpp.find_library('clang-cpp', dirs: llvm_libdir, ...)` -- un
    # find_library() puro, que sólo aporta el flag de LINKEO contra
    # libclang-cpp.so, NUNCA include dirs (a diferencia de `dep_llvm`, que sí
    # es un `dependency('llvm', method: 'config-tool', ...)` completo y por
    # eso aporta sus propios `-isystem` -- confirmado en el log real:
    # `-isystem.../llvm-project-23.1.0.src/llvm/include -isystem.../llvm-
    # native-build/include`, dos rutas, ambas de LLVM, CERO de Clang). En el
    # build CRUZADO esto no se nota porque LLVM+Clang quedan instalados
    # completos en ${LFS_SYSROOT}/usr -- los headers de clang caen en una
    # ruta de include ESTÁNDAR del sysroot, sin hacer falta ningún -I
    # explícito. Acá, en cambio, LLVM+Clang nativos nunca se instalan (se
    # usan directo desde su árbol de build, sin "ninja install") -- sus
    # headers no están en ningún include path por default.
    # Fix: agregar a mano las mismas DOS rutas que Meson ya arma solo para
    # LLVM, pero del lado de Clang -- fuente (headers públicos normales,
    # `clang/include`) y árbol de build NATIVO (headers generados por CMake
    # en tiempo de configure, como este mismo `clang/Config/config.h`, bajo
    # `tools/clang/include` -- mismo layout estándar del monorepo LLVM que
    # ya usa ${LLVM_NATIVE_BUILD}/include para los generados de LLVM).
    # CFLAGS/CXXFLAGS en el propio `meson setup` (no en el native-file):
    # mismo mecanismo que ya usa step_elfutils() más arriba -- Meson graba
    # esto como flags base del proyecto en tiempo de configure.
    local llvm_native_src="${LFS_BUILD}/llvm-project-${LLVM_VERSION}.src"
    local clang_src_include="${llvm_native_src}/clang/include"
    local clang_build_include="${LLVM_NATIVE_BUILD}/tools/clang/include"
    [[ -d "${clang_src_include}" ]] \
        || die "no está ${clang_src_include} -- ¿cambió la estructura de directorios de LLVM ${LLVM_VERSION}?"
    [[ -f "${clang_build_include}/clang/Config/config.h" ]] \
        || die "no está ${clang_build_include}/clang/Config/config.h -- ¿el target 'clang-cpp' de step_llvm_native() no generó los headers de Clang, o cambió su ruta de build?"

    local nativefile="${LFS_BUILD}/meson-native-mesaclc-linsi.ini"
    cat > "${nativefile}" <<EOF
[binaries]
llvm-config = '${LLVM_NATIVE_BUILD}/bin/llvm-config'

[properties]
pkg_config_libdir = ['${SPIRV_TOOLS_NATIVE_INSTALL}/lib/pkgconfig', '${SPIRV_LLVM_TRANSLATOR_NATIVE_INSTALL}/lib/pkgconfig']
EOF

    local bdir="${LFS_BUILD}/mesa-clc-native-build"
    rm -rf "${bdir}"
    rm -rf "${MESA_CLC_NATIVE_INSTALL}"

    # Vigésimo segundo error real (2026-09-04): con lo anterior ya andando,
    # mesa_clc NATIVO compiló, se instaló, y el build CRUZADO real de Mesa lo
    # invocó de verdad (1366/2872 targets, compilando
    # src/intel/blorp/blorp_shaders.cl a SPIR-V) -- pero ahí rompió en
    # tiempo de EJECUCIÓN de mesa_clc, no de compilación:
    #   <built-in>:439:10: fatal error: 'opencl-c-base.h' file not found
    # Causa raíz (confirmada leyendo src/compiler/clc/meson.build real
    # completo, ya citado más arriba en este archivo): Mesa tiene DOS
    # estrategias para que mesa_clc encuentre sus headers de OpenCL-C
    # (opencl-c-base.h/opencl-c.h, que clang necesita para compilar
    # `-cl-std=cl2.0`): (a) "bundled" -- los empaqueta ADENTRO del binario
    # en tiempo de compilación (vía xxd, activado con
    # `-DUSE_STATIC_OPENCL_C_H=1`) cuando `not _shared_llvm` o
    # `-Dmesa-clc-bundle-headers=enabled`; o (b) "runtime" (default si LLVM
    # es compartida, que es nuestro caso) -- los busca en disco en
    # `<LLVM_LIB_DIR>/clang/<version>/include/`, una ruta armada en base al
    # `llvm_libdir` que reporta `llvm-config` en tiempo de compilación de
    # mesa_clc. Ese directorio (`${LLVM_NATIVE_BUILD}/lib/clang/23/
    # include/`) nunca lo generamos -- `step_llvm_native()` sólo pide
    # targets puntuales de CMake (`llvm-tblgen llvm-config clang-tblgen LLVM
    # clang-cpp`), ninguno de los cuales copia/genera el "resource
    # directory" de headers builtin de Clang.
    # Fix: en vez de perseguir qué target de CMake genera ese directorio
    # (frágil, ligado a la estructura interna de Clang), se fuerza el modo
    # (a) -- `-Dmesa-clc-bundle-headers=enabled` -- que empaqueta los
    # headers DENTRO del binario mesa_clc en tiempo de compilación: cero
    # dependencia de rutas en disco en tiempo de ejecución, exactamente lo
    # que hace falta para un binario NATIVO pre-compilado que se usa desde
    # OTRO build (el cruzado) donde ni siquiera existe ${LLVM_NATIVE_BUILD}
    # en el mismo contexto de resolución de rutas relativas.
    CFLAGS="-isystem ${clang_src_include} -isystem ${clang_build_include}" \
    CXXFLAGS="-isystem ${clang_src_include} -isystem ${clang_build_include}" \
    meson setup "${bdir}" \
        --native-file="${nativefile}" \
        --prefix="${MESA_CLC_NATIVE_INSTALL}" \
        --buildtype=release \
        -Dstrip=true \
        -Dplatforms= \
        -Dgallium-drivers= \
        -Dvulkan-drivers= \
        -Dmesa-clc=enabled \
        -Dmesa-clc-bundle-headers=enabled \
        -Dinstall-mesa-clc=true

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    [[ -x "${MESA_CLC_NATIVE_BIN}" ]] || die "no se compiló mesa_clc NATIVO en ${MESA_CLC_NATIVE_BIN}"
    [[ -x "${VTN_BINDGEN2_NATIVE_BIN}" ]] || die "no se compiló vtn_bindgen2 NATIVO en ${VTN_BINDGEN2_NATIVE_BIN}"

    command -v patchelf >/dev/null 2>&1 \
        || die "falta patchelf en el contenedor -- agregalo al Dockerfile (apt-get install patchelf) y correé 'podman-compose build' de nuevo"
    patchelf --set-rpath "${LLVM_NATIVE_BUILD}/lib" "${MESA_CLC_NATIVE_BIN}"

    # Chequeo real, no sólo "compiló sin error" -- Lección del Décimo octavo
    # error real (ver docs/PENDIENTES.md): un ldd limpio prueba que el
    # binario RESUELVE todas sus librerías dinámicas, no lo mismo que "ninja
    # terminó sin fallar".
    if ldd "${MESA_CLC_NATIVE_BIN}" 2>&1 | grep -q 'not found'; then
        ldd "${MESA_CLC_NATIVE_BIN}" >&2
        die "mesa_clc NATIVO no resuelve todas sus librerías dinámicas (ver ldd arriba) -- el patchelf de RPATH no alcanzó"
    fi

    log "mesa_clc + vtn_bindgen2 NATIVOS listos en ${MESA_CLC_NATIVE_INSTALL}/bin"
}

# ------------------------------------------------------------------------------
# 8) Mesa — Meson. Drivers elegidos para cubrir Intel/AMD/Nvidia reales del
# lab (ver el aviso al principio del archivo). --native-file hace falta
# porque Mesa también invoca wayland-scanner en tiempo de build (protocolo
# linux-dmabuf/wayland-drm para la plataforma EGL wayland) -- mismo problema
# que ya resolvimos tres veces en la Parte 1, acá se reusa el mismo scanner
# nativo en vez de reconstruirlo. Mismo mecanismo para glslangValidator, con
# una vuelta más: CORRECCIÓN (post-build real, 2026-09-01) -- pisarlo sólo
# en el cross-file (el patrón que funcionó con spa-json-dump en
# build-desktop.sh) NO alcanzó acá; Meson lo siguió resolviendo contra el
# de apt (/usr/bin/glslangValidator, muy viejo). A diferencia de
# spa-json-dump (que confirmamos leyendo el meson.build real de wireplumber
# que NO usa native:true), no pude confirmar en vivo si el find_program()
# de glslangValidator en el meson.build real de Mesa 26.2.1 usa
# native:true o no -- las dos fuentes que miré (mirror de GitHub) no
# coinciden entre sí ni con el comportamiento real observado. En vez de
# seguir adivinando, se pisa en LOS DOS archivos (--cross-file y
# --native-file) -- no cuesta nada extra y cubre cualquiera de los dos
# mecanismos que Mesa termine usando.
# ------------------------------------------------------------------------------
step_mesa() {
    require_toolchain
    [[ -x "${LFS_SYSROOT}/usr/bin/llvm-config" ]] \
        || die "no está LLVM en el sysroot -- corré primero: scripts/build-mesa.sh llvm"
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libdrm.so*' 2>/dev/null | grep -q .; then
        die "no está libdrm en el sysroot -- corré primero: scripts/build-mesa.sh libdrm"
    fi
    [[ -x "${WAYLAND_SCANNER_NATIVE_PREFIX}/bin/wayland-scanner" ]] \
        || die "no está el wayland-scanner NATIVO en ${WAYLAND_SCANNER_NATIVE_PREFIX}/bin -- corré primero: scripts/build-desktop.sh wayland (Fase 6 Parte 1)"
    [[ -x "${GLSLANG_NATIVE_BIN}" ]] \
        || die "no está glslangValidator NATIVO en ${GLSLANG_NATIVE_BIN} -- corré primero: scripts/build-mesa.sh glslang-native"
    # Con iris/intel_vk habilitados, Mesa activa with_driver_using_cl -- pero
    # desde el Vigésimo error real (2026-09-04) mesa_clc/intel_clc YA NO se
    # compilan acá adentro: se usa -Dmesa-clc=system con un mesa_clc +
    # vtn_bindgen2 NATIVOS pre-compilados aparte (ver step_mesa_clc_native()
    # y su comentario grande, sección "7c"). libclang-cpp.so CRUZADA sigue
    # haciendo falta igual -- Mesa la resuelve al margen de with_clc (la usan
    # otros consumidores, confirmado que no cuesta nada dejar el chequeo).
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libclang-cpp.so*' 2>/dev/null | grep -q .; then
        die "no está libclang-cpp.so en el sysroot -- corré primero: scripts/build-mesa.sh llvm (ya con LLVM_ENABLE_PROJECTS=clang)"
    fi
    [[ -x "${MESA_CLC_NATIVE_BIN}" ]] \
        || die "no está mesa_clc NATIVO en ${MESA_CLC_NATIVE_BIN} -- corré primero: scripts/build-mesa.sh mesa-clc-native"
    [[ -x "${VTN_BINDGEN2_NATIVE_BIN}" ]] \
        || die "no está vtn_bindgen2 NATIVO en ${VTN_BINDGEN2_NATIVE_BIN} -- corré primero: scripts/build-mesa.sh mesa-clc-native"
    if ! find "${LFS_SYSROOT}/usr/lib/pkgconfig" -maxdepth 1 -name 'SPIRV-Tools.pc' 2>/dev/null | grep -q .; then
        die "no está SPIRV-Tools.pc en el sysroot -- corré primero: scripts/build-mesa.sh spirv-headers && scripts/build-mesa.sh spirv-tools"
    fi
    if ! find "${LFS_SYSROOT}/usr/lib/pkgconfig" -maxdepth 1 -name 'LLVMSPIRVLib.pc' 2>/dev/null | grep -q .; then
        die "no está LLVMSPIRVLib.pc en el sysroot -- corré primero: scripts/build-mesa.sh spirv-llvm-translator"
    fi
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libelf.so*' 2>/dev/null | grep -q .; then
        die "no está libelf en el sysroot (lo necesita radeonsi) -- corré primero: scripts/build-mesa.sh elfutils"
    fi

    log "Mesa ${MESA_VERSION} para ${LFS_TGT} — Meson+Ninja (gallium: iris/radeonsi/nouveau/llvmpipe, vulkan: amd/intel, + mesa-clc/intel_clc vía Clang/SPIRV-Tools/LLVMSPIRVLib)"

    cd "${LFS_SOURCES}"
    fetch "${MESA_MIRROR}/mesa-mesa-${MESA_VERSION}.tar.gz" "mesa-${MESA_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/mesa-${MESA_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/mesa-${MESA_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-mesa"

    # Mismo patrón "<repo>-<tag>" duplicado de gitlab.fd.o que libdrm/pipewire.
    local src="${LFS_BUILD}/mesa-mesa-${MESA_VERSION}"
    cd "${src}"

    # Décimo noveno error real, parte 2 -- REVERTIDO (2026-09-04, Vigésimo
    # error real): este script llegó a parchear src/compiler/clc/meson.build
    # a mano (sed forzando `native : true` en el executable('mesa_clc', ...)
    # ) para que mesa_clc se compilara con el compilador NATIVO. Eso
    # destapó un error NUEVO en el siguiente `meson setup` ("Tried to mix a
    # host machine library ("libmesaclc") with a build machine target
    # "mesa_clc" This is not possible in a cross build.") porque
    # idep_mesaclc/_libmesaclc (y sus propias dependencias: dep_llvm,
    # dep_clang, dep_spirv_tools, dep_llvmspirvlib) siguen sin native: en
    # ESE MISMO archivo -- forzar sólo el executable() no alcanza, y forzar
    # también la librería reproduciría el mismo choque un nivel más abajo
    # contra dep_llvm. El fix real -- no tocar el meson.build de Mesa en
    # absoluto, usar mesa_clc/vtn_bindgen2 NATIVOS pre-compilados aparte
    # con -Dmesa-clc=system -- está en step_mesa_clc_native() (sección "7c"
    # más arriba); ese comentario tiene el diagnóstico completo.

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    # llvm-config: ver el comentario largo de "CORRECCIÓN #2" más arriba --
    # el mecanismo config-tool de Meson no cae al PATH para dependencias de
    # host machine en build cruzado, hace falta declararlo acá explícito.
    write_meson_crossfile "${crossfile}" "glslangValidator = '${GLSLANG_NATIVE_BIN}'
llvm-config = '${LFS_SYSROOT}/usr/bin/llvm-config'"

    # mesa_clc/vtn_bindgen2 NATIVOS (Vigésimo error real, ver step_mesa_clc_native()
    # más arriba): con -Dmesa-clc=system, Mesa busca estos dos programas con
    # find_program(..., native : true) -- se los pisamos acá en vez de
    # depender de que estén en el PATH del contenedor.
    local nativefile="${LFS_BUILD}/meson-native-linsi.ini"
    write_meson_nativefile "${nativefile}" "glslangValidator = '${GLSLANG_NATIVE_BIN}'
mesa_clc = '${MESA_CLC_NATIVE_BIN}'
vtn_bindgen2 = '${VTN_BINDGEN2_NATIVE_BIN}'"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    # No hay "-Dosmesa=..." acá: CORRECCIÓN (post-build real, 2026-08-30) --
    # "osmesa" (renderizado off-screen sin GPU/display) fue eliminado de
    # Mesa upstream (mismo patrón que gallium-vdpau más abajo: no es un
    # rename, la opción no existe más). Como igual la queríamos en "false"
    # (no la necesitamos, este proyecto siempre tiene GPU real o llvmpipe),
    # sacarla del comando no cambia nada funcionalmente.
    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --native-file="${nativefile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -Dplatforms=wayland \
        -Dgallium-drivers=iris,radeonsi,nouveau,llvmpipe \
        -Dvulkan-drivers=amd,intel \
        -Dllvm=enabled \
        -Dshared-llvm=enabled \
        -Dmesa-clc=system \
        -Dvalgrind=disabled \
        -Dgbm=enabled \
        -Degl=enabled \
        -Dglx=disabled \
        -Dopengl=true \
        -Dgles2=enabled \
        -Dglvnd=disabled \
        -Dgallium-va=disabled

    # Décimo octavo/Décimo noveno error real -- YA NO APLICA (2026-09-04,
    # Vigésimo error real): con -Dmesa-clc=system + -Dgallium-drivers=rusticl
    # ausente, `with_clc` queda en false para ESTE build cruzado -- Mesa ni
    # siquiera procesa src/compiler/clc/meson.build acá, así que no existe
    # ningún ejecutable *_clc en este grafo de ninja para parchear. mesa_clc/
    # vtn_bindgen2 ya vienen NATIVOS y con su RPATH corregido desde
    # step_mesa_clc_native() (sección "7c"); Mesa sólo los INVOCA como
    # comandos ya compilados (custom_target() en src/intel/blorp/meson.build,
    # confirmado leyendo el archivo real) -- no hay nada más que patchear acá.
    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "Mesa instalado en ${LFS_SYSROOT}/usr"
}

step_verify_mesa() {
    log "Verificación: drivers de Mesa (Gallium + Vulkan) en el sysroot"
    local ok=1
    local p
    # swrast_dri.so es el nombre correcto del .so instalado por la opción de
    # meson "llvmpipe" (confirmado contra el meson.build real de Mesa,
    # target dri) -- el nombre del archivo no cambió aunque el nombre de la
    # opción sí, no es una inconsistencia.
    for p in \
        "${LFS_SYSROOT}/usr/lib/dri/iris_dri.so" \
        "${LFS_SYSROOT}/usr/lib/dri/radeonsi_dri.so" \
        "${LFS_SYSROOT}/usr/lib/dri/nouveau_dri.so" \
        "${LFS_SYSROOT}/usr/lib/dri/swrast_dri.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    for p in \
        "${LFS_SYSROOT}/usr/lib/libvulkan_radeon.so" \
        "${LFS_SYSROOT}/usr/lib/libvulkan_intel.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    if ! find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libEGL.so*' 2>/dev/null | grep -q .; then
        echo "  [FALTA] libEGL.so en ${LFS_SYSROOT}/usr/lib"; ok=0
    else
        echo "  [OK] libEGL.so presente"
    fi
    [[ "${ok}" -eq 1 ]] || die "falta algo de Mesa en el sysroot"
    log "OK: Mesa completo en el sysroot."
}

main() {
    local target="${1:-all}"
    case "${target}" in
        libdrm)                   step_libdrm ;;
        verify-libdrm)            step_verify_libdrm ;;
        llvm-native)              step_llvm_native ;;
        llvm)                     step_llvm ;;
        verify-llvm)              step_verify_llvm ;;
        glslang-native)           step_glslang_native ;;
        spirv-headers)            step_spirv_headers ;;
        spirv-tools)              step_spirv_tools ;;
        verify-spirv-tools)       step_verify_spirv_tools ;;
        spirv-tools-native)       step_spirv_tools_native ;;
        spirv-llvm-translator)    step_spirv_llvm_translator ;;
        verify-spirv-llvm-translator) step_verify_spirv_llvm_translator ;;
        spirv-llvm-translator-native) step_spirv_llvm_translator_native ;;
        elfutils)                 step_elfutils ;;
        verify-elfutils)          step_verify_elfutils ;;
        mesa-clc-native)          step_mesa_clc_native ;;
        mesa)                     step_mesa ;;
        verify-mesa)              step_verify_mesa ;;
        all)
            step_libdrm;      step_verify_libdrm
            step_llvm_native
            step_llvm;        step_verify_llvm
            step_glslang_native
            step_spirv_headers
            step_spirv_tools;             step_verify_spirv_tools
            step_spirv_tools_native
            step_spirv_llvm_translator;   step_verify_spirv_llvm_translator
            step_spirv_llvm_translator_native
            step_elfutils;    step_verify_elfutils
            step_mesa_clc_native
            step_mesa;        step_verify_mesa
            log "Fase 6 parte 2 ('Mesa + LLVM') completa: libdrm, LLVM+Clang (X86+AMDGPU), SPIRV-Tools, SPIRV-LLVM-Translator, elfutils (libelf), mesa_clc/vtn_bindgen2 NATIVOS y Mesa (iris/radeonsi/nouveau/llvmpipe + Vulkan amd/intel, con mesa-clc/intel_clc para Intel real) listos en el sysroot. Falta Qt6/KDE Frameworks -- va en su propio script."
            ;;
        *)
            die "target desconocido: ${target} (usar: libdrm|llvm-native|llvm|glslang-native|spirv-headers|spirv-tools|spirv-tools-native|spirv-llvm-translator|spirv-llvm-translator-native|elfutils|mesa-clc-native|mesa|all, cada uno con su verify-<paso> salvo llvm-native/glslang-native/spirv-headers/spirv-tools-native/spirv-llvm-translator-native/mesa-clc-native)"
            ;;
    esac
}

main "$@"
