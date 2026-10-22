#!/usr/bin/env bash
# ==============================================================================
# LINSI-OS · Fase 6 — "Interfaz Moderna" (parte 3: Qt6 + KDE Frameworks/Plasma)
# ------------------------------------------------------------------------------
# Igual que fases anteriores: no se chrootea, todo se instala con --prefix=/usr
# + DESTDIR="${LFS_SYSROOT}". Requiere Fase 6 Parte 1 (build-desktop.sh all,
# en particular libxml2/libxkbcommon con xkbregistry) y Fase 6 Parte 2
# (build-mesa.sh all) completas -- kwin necesita Mesa (EGL/Vulkan/gbm) y
# libxkbcommon con xkbregistry para el selector de layout de teclado.
#
# ------------------------------------------------------------------------------
# MAPA DE DEPENDENCIAS (research 2026-09-04, contra fuente real -- CMakeLists.txt
# reales de kwin y plasma-workspace bajados de invent.kde.org, NO inventado ni
# recordado de memoria; invent.kde.org y github.com/qt SÍ están accesibles
# desde este sandbox, a diferencia de gitlab.freedesktop.org/gitlab.gnome.org
# de research anteriores de este proyecto -- confirmado en vivo).
#
# Decisiones ya tomadas (ver también env.sh):
#   - Qt6 6.11.2 (último estable real, supera el mínimo real de kwin/
#     plasma-workspace: QT_MIN_VERSION 6.10.0).
#   - KDE Frameworks 6 + tren de Plasma en 6.29.0 (el último REALMENTE
#     publicado en download.kde.org/stable/frameworks/ -- supera el
#     KF6_MIN_VERSION real de kwin, 6.27.0, y de plasma-workspace, 6.26.0).
#   - XWayland/X11: SACADO por completo. Confirmado contra el documento
#     fundacional real del proyecto (docs/LINSI-OS.pdf, Pilar 5 "Vanguardia"):
#     "LINSI-OS se construye exclusivamente sobre Wayland" / "sin arrastrar
#     compatibilidad con X11 ni PulseAudio". kwin trae XWayland prendido por
#     defecto (KWIN_BUILD_X11=ON en su CMakeLists.txt real) -- cuando se
#     llegue a step_kwin(), va con KWIN_BUILD_X11=OFF a propósito.
#   - Alcance: TODO desde el principio, incluidas las piezas opcionales que
#     el CMakeLists.txt real de plasma-workspace no marca REQUIRED (Baloo,
#     NetworkManagerQt, PackageKitQt6, AppStreamQt, KIOExtras/KIOFuse) -- a
#     diferencia del criterio "mínimo primero" que se usó en Mesa (VA-API/
#     glvnd/NVK afuera a propósito), acá se pidió explícitamente el desktop
#     completo desde el principio, no un subconjunto recortado.
#
# Tiers (cada uno depende del anterior; dentro de un tier, sin orden estricto
# salvo que se indique):
#
#   Tier 0 — herramientas de build, sin dependencia de Qt/KF6:
#     - cmake >= 3.29 vía pip (Dockerfile, ya agregado 2026-09-04 -- ECM lo
#       exige, el cmake de apt de Debian bookworm es 3.25.1).
#     - extra-cmake-modules (ECM): sólo módulos .cmake, LANGUAGES NONE, sin
#       dependencias externas ni compilador involucrado -- primer paso real
#       de este script, implementado más abajo (step_ecm).
#
#   Tier 1 — Qt6 (CMake, necesita un Qt NATIVO aparte para cross-compilar:
#     moc/rcc/qmlcachegen/etc. tienen que correr en el contenedor de build,
#     mismo patrón "native tool" ya resuelto 4 veces en Fase 6 Parte 2 --
#     mesa_clc/llvm-config/wayland-scanner/glslangValidator -- pero acá es
#     la pieza completa más delicada, con research propio pendiente antes de
#     escribir el primer step_qtbase*()):
#     qtbase, qtshadertools, qtdeclarative, qtsvg, qt5compat, qttools,
#     qtwayland. Confirmado contra los find_package(Qt6 ... COMPONENTS)
#     reales de kwin (Concurrent, Core, Core5Compat, DBus, Quick, UiTools,
#     WaylandClient, Widgets, Svg) y plasma-workspace (agrega Test/QuickTest
#     -- sólo si BUILD_TESTING, y WaylandCompositor).
#     ✅ COMPLETO (2026-09-04) -- ver docs/PENDIENTES.md, sección "Tier 1
#     (Qt6) — primeros pasos reales".
#
#   Tier 2 — KDE Frameworks 6 (KF6 >= 6.27.0), lista de componentes CONFIRMADA
#     contra los find_package(KF6 ... COMPONENTS) reales de kwin y
#     plasma-workspace (no es una lista completa de los ~90 frameworks que
#     existen, sólo los que estos dos paquetes piden directo -- sus propias
#     dependencias transitivas se van a descubrir building, mismo método que
#     ya funcionó en Mesa):
#     Auth, ColorScheme, Config, CoreAddons, Crash, DBusAddons, GlobalAccel,
#     GuiAddons, I18n, IdleTime, Package, Service, Svg, WidgetsAddons,
#     WindowSystem, Declarative, KCMUtils, NewStuff, XmlGui, Runner,
#     DocTools, NetworkManagerQt, QuickCharts, UserFeedback, Baloo.
#     ✅ COMPLETO (2026-09-04) -- ver docs/PENDIENTES.md para el detalle real
#     tier por tier (2a/2b/2c/2d) y las dependencias transitivas que salieron
#     building (bastantes más que la lista de arriba: KWindowSystem, KArchive,
#     KConfigWidgets, KService, KIconThemes, Kirigami, KBookmarks, KJobWidgets,
#     Solid, KIO, Attica, NewStuff, más zstd/liblzma/libltdl/libogg/libvorbis/
#     libcanberra/iso-codes como dependencias de sistema no-KF6).
#
#   Tier 3 — librerías del "tren de Plasma" (versionadas junto a Plasma, NO
#     parte de KDE Frameworks propiamente -- por eso en los CMakeLists.txt
#     reales usan PROJECT_DEP_VERSION en vez de KF6_MIN_VERSION):
#     Plasma (libplasma), PlasmaQuick, KWayland (la de KDE -- distinta de
#     Qt6WaylandClient de Tier 1), PlasmaActivities(+Stats), KSysGuard,
#     KF6Screen, LayerShellQt, KF6Kirigami+KF6KirigamiAddons, KNightTime,
#     KDecoration3, Breeze/Aurorae (temas de decoración), Union, KWinDBusInterface,
#     ScreenSaverDBusInterface, PlasmaWaylandProtocols (protocolos XML propios
#     de KDE, mismo patrón wayland-scanner que wayland-protocols en Fase 6
#     Parte 1).
#     NO SE EMPEZÓ TODAVÍA.
#
#   Tier 4 — terceros, nada de esto está compilado en el proyecto todavía:
#     QCoro6 (corrutinas de C++ para Qt, proyecto separado de Qt/KDE), ICU
#     (i18n/uc), libcanberra (sonidos de eventos), libei (Emulated Input,
#     input remoto para el portal RemoteDesktop), lcms2 (gestión de color),
#     hwdata (base de datos PCI/monitores, sin compilar -- son datos),
#     AccountsService, AppStreamQt, PolkitQt6-1 (bindings Qt6 del polkit ya
#     compilado en Fase 6 Parte 1), QAccessibilityClient6, PackageKitQt6,
#     KExiv2Qt6, KIOExtras, KIOFuse.
#     NO SE EMPEZÓ TODAVÍA.
#
#   Tier 5 — kwin y plasma-workspace en sí (KWIN_BUILD_X11=OFF, ver arriba).
#     NO SE EMPEZÓ TODAVÍA.
#
# Uso:
#   scripts/build-kde.sh ecm
#   scripts/build-kde.sh all        # corre todos los pasos escritos hasta ahora
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/lfs/scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

log()  { printf '\n\033[1;36m[fase6-3]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[fase6-3][error]\033[0m %s\n' "$*" >&2; exit 1; }

# Prefix del build NATIVO de Qt6 (sección "Tier 1" del header) -- mismo
# patrón que LLVM_NATIVE_BUILD/GLSLANG_NATIVE_BUILD en build-mesa.sh: se
# define acá (no en env.sh) porque depende de LFS_BUILD, recién disponible
# después de sourcear env.sh. Un solo prefix compartido para TODOS los
# módulos de Qt6 que se compilen nativos (qtbase primero, más adelante
# qtshadertools/qtdeclarative/qtwayland nativos van al mismo lugar) -- así
# el build CRUZADO de cada módulo encuentra el paquete "*Tools" de todos los
# anteriores con un solo "-DQT_HOST_PATH=${QT6_NATIVE_INSTALL}" (mecanismo
# real, confirmado en qtbase/cmake/README.md).
QT6_NATIVE_BUILD="${LFS_BUILD}/qt6-native-build"
QT6_NATIVE_INSTALL="${LFS_BUILD}/qt6-native-install"

# Prefix del build NATIVO de herramientas propias de KDE Frameworks (Tier
# 2c) -- mismo patrón que QT6_NATIVE_*, pero para el mecanismo
# "KF6_HOST_TOOLING" (equivalente de KF6 al QT_HOST_PATH de Qt6). Se
# descubrió con BreezeIcons: algunos frameworks compilan herramientas
# propias (generate-symbolic-dark, qrcAlias) que se INVOCAN en tiempo de
# build del propio framework -- mismo problema de fondo de siempre
# (binario cruzado que no corre en el contenedor), pero acá KF6 ya tiene
# su convención propia para resolverlo (confirmado leyendo
# tools/CMakeLists.txt real de breeze-icons: "if (CMAKE_CROSSCOMPILING AND
# KF6_HOST_TOOLING): find_program(... PATHS ${KF6_HOST_TOOLING} ...)").
KF6_NATIVE_BUILD="${LFS_BUILD}/kf6-native-build"
KF6_NATIVE_INSTALL="${LFS_BUILD}/kf6-native-install"

# Prefix NATIVO de hwdata -- mismo patrón que QT6_NATIVE_INSTALL/
# KF6_NATIVE_INSTALL, pero para datos puros (pnp.ids), no binarios. Ver
# el comentario real en step_hwdata() (Tier 3): libdisplay-info pide
# hwdata como dependencia NATIVA de tiempo de build.
HWDATA_NATIVE_INSTALL="${LFS_BUILD}/hwdata-native-install"

# Build NATIVO de ICU4C -- distinto a los de arriba: acá lo que hace
# falta no es un binario puntual ni datos, es el DIRECTORIO DE BUILD
# nativo completo (no un install), porque "--with-cross-build" de ICU
# pide exactamente eso (ver step_icu()/step_icu_native()).
ICU_NATIVE_BUILD="${LFS_BUILD}/icu-native-build"

require_toolchain() {
    if ! command -v "${LFS_TGT}-gcc" >/dev/null 2>&1; then
        die "no se encontró ${LFS_TGT}-gcc en el PATH. Corré primero: scripts/build-cross-toolchain.sh all"
    fi
}

require_qtbase_native() {
    [[ -x "${QT6_NATIVE_INSTALL}/libexec/moc" ]] \
        || die "no está qtbase NATIVO en ${QT6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh qtbase-native"
}

require_qtshadertools_native() {
    [[ -x "${QT6_NATIVE_INSTALL}/bin/qsb" ]] \
        || die "no está qtshadertools NATIVO en ${QT6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh qtshadertools-native"
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

build_triplet() {
    "${LFS_BUILD}/binutils-${BINUTILS_VERSION}/config.guess"
}

# Toolchain file de CMake -- copia exacta del de build-mesa.sh (mismo patrón
# ya probado ahí para LLVM/SPIRV-*). Todo lo de este script (Qt6/KF6/kwin/
# plasma-workspace) es CMake, no Meson -- a diferencia de Fase 6 Parte 1/2,
# acá no hace falta write_meson_crossfile()/write_meson_nativefile() para
# nada, sólo esto.
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
# Tier 0) extra-cmake-modules (ECM) — sólo módulos .cmake (find-modules,
# kde-modules, toolchain files), "project(ECM LANGUAGES NONE)" en su propio
# CMakeLists.txt real -- no compila nada, así que no hace falta el toolchain
# file de cross-compiling de más arriba (no hay ningún compilador que
# detectar): "cross" vs "target" no aplica acá, el contenido instalado es
# idéntico sin importar la arquitectura de destino. Es el primer requisito
# de CUALQUIER paquete de KDE Frameworks/Plasma de acá en adelante.
# ------------------------------------------------------------------------------
step_ecm() {
    log "extra-cmake-modules ${ECM_VERSION} — CMake (sin compilar, sólo módulos)"

    cd "${LFS_SOURCES}"
    fetch "${KDE_FRAMEWORKS_MIRROR}/extra-cmake-modules-${ECM_VERSION}.tar.xz" \
          "extra-cmake-modules-${ECM_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/extra-cmake-modules-${ECM_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/extra-cmake-modules-${ECM_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-ecm"

    local src="${LFS_BUILD}/extra-cmake-modules-${ECM_VERSION}"
    local bdir="${src}/build"
    rm -rf "${bdir}"

    # -DBUILD_DOC=OFF / -DBUILD_TESTING=OFF: mismo criterio que el resto del
    # proyecto (Mesa -Ddocs=disabled, libxml2 -Ddocs=disabled, libxkbcommon
    # -Denable-docs=false) -- BUILD_DOC real de ECM arrastra Sphinx (no
    # instalado en el Dockerfile) y BUILD_TESTING corre su propia suite de
    # tests de CMake (pensada para validación interactiva del propio ECM,
    # no para este pipeline de cross-build). Ninguna de las dos hace falta
    # para que el resto de KDE Frameworks encuentre sus módulos.
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_DOC=OFF \
        -DBUILD_TESTING=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "extra-cmake-modules instalado en ${LFS_SYSROOT}/usr"
}

step_verify_ecm() {
    log "Verificación: ECMConfig.cmake + módulos base en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/share/ECM/cmake/ECMConfig.cmake" \
        "${LFS_SYSROOT}/usr/share/ECM/kde-modules/KDEInstallDirs.cmake" \
        "${LFS_SYSROOT}/usr/share/ECM/modules/ECMSetupVersion.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de ECM en el sysroot"
    log "OK: extra-cmake-modules completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qtbase NATIVO — build "regular" de Qt para el propio contenedor de
# build, SIN toolchain file (gcc/g++ nativos del contenedor, no el cross
# toolchain de Fase 0). Necesario porque compilar Qt genera código con sus
# propias herramientas (moc, rcc, uic, ...) que después se INVOCAN durante el
# mismo build para producir el resto del código fuente -- esas herramientas
# tienen que poder correr en el contenedor, mismo motivo de fondo que ya
# resolvimos 4+ veces en Fase 6 Parte 2 (mesa_clc/llvm-config/wayland-scanner/
# glslangValidator), documentado en la receta OFICIAL de Qt
# (qtbase/cmake/README.md real, sección "Cross Compiling": "This 'host build'
# is needed because the process of building Qt involves the compilation of
# intermediate code generator tools ... they need to run on the machine
# you're building on, regardless of the architecture you are targeting").
#
# Este build NATIVO no se instala en el sysroot -- va a un prefix aparte,
# ${QT6_NATIVE_INSTALL}, que el build CRUZADO (todavía sin escribir) va a
# apuntar vía "-DQT_HOST_PATH=${QT6_NATIVE_INSTALL}" (mecanismo real,
# confirmado en el mismo cmake/README.md).
#
# -DFEATURE_xcb=OFF a propósito: no hace falta X11 para nada en este
# contenedor (el Dockerfile no tiene libxcb-dev ni relacionados, y el
# proyecto entero es Wayland puro -- ver decisión XWayland/X11 en env.sh),
# y este build nativo sólo importa por sus binarios de herramientas
# (moc/rcc/uic/...), nunca corre como GUI de verdad.
# -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF: exactos de la receta oficial
# de más arriba -- no hace falta compilar ejemplos ni tests para un build
# que sólo se usa por sus herramientas de código.
# ------------------------------------------------------------------------------
step_qtbase_native() {
    log "Qt6 (qtbase) ${QT6_VERSION} NATIVO — CMake, para el contenedor de build"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtbase-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtbase-native"

    local src="${LFS_BUILD}/qtbase-everywhere-src-${QT6_VERSION}"
    local bdir="${QT6_NATIVE_BUILD}/qtbase"
    mkdir -p "${QT6_NATIVE_INSTALL}"
    rm -rf "${bdir}"

    # Primer error real (2026-09-04): "The OpenGL functionality tests
    # failed!" -- CMake Error duro, no un auto-disable silencioso. El
    # contenedor no tiene libGL/EGL de desarrollo instalados a nivel host
    # (a propósito -- este proyecto nunca quiso GL del lado del contenedor,
    # sólo cross-compilado en el sysroot vía Mesa). Confirmado contra
    # src/gui/configure.cmake real de qtbase: "opengl" depende de
    # opengl_desktop/opengl_dynamic/opengles2, y el switch documentado de
    # Qt para desactivarlo entero es INPUT_opengl=no (equivalente CMake de
    # "./configure -opengl no" de qmake). Esta build nativa sólo importa
    # por sus binarios de herramientas (moc/rcc/uic/...) -- nunca renderiza
    # nada -- así que no hace falta ningún backend de OpenGL acá.
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${QT6_NATIVE_INSTALL}" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF \
        -DFEATURE_xcb=OFF \
        -DINPUT_opengl=no

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "qtbase NATIVO instalado en ${QT6_NATIVE_INSTALL}"
}

step_verify_qtbase_native() {
    log "Verificación: herramientas NATIVAS de qtbase (moc/rcc/uic) + Qt6CoreTools"
    local ok=1
    local p
    # moc/rcc/uic quedan en libexec/, NO en bin/ -- confirmado en la corrida
    # real (Qt6 instala las herramientas de desarrollo "privadas" en
    # INSTALL_LIBEXECDIR, reservando bin/ para binarios de cara al usuario
    # final; acá no hay ninguno de esos últimos porque no compilamos
    # aplicaciones, sólo la librería + sus herramientas).
    for p in \
        "${QT6_NATIVE_INSTALL}/libexec/moc" \
        "${QT6_NATIVE_INSTALL}/libexec/rcc" \
        "${QT6_NATIVE_INSTALL}/libexec/uic" \
        "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6CoreTools/Qt6CoreToolsConfig.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qtbase nativo"
    log "OK: qtbase NATIVO completo."
}

# ------------------------------------------------------------------------------
# Tier 1) qtshadertools NATIVO — provee "qsb" (Qt Shader Baker), que
# QtDeclarative/QtQuick invoca en tiempo de build (tanto el suyo propio como,
# más adelante, el de kwin/plasma-workspace) para precompilar shaders del
# scenegraph RHI a SPIR-V/GLSL/HLSL/MSL según la plataforma. Mismo prefix
# compartido que qtbase-native (QT6_NATIVE_INSTALL) -- se le pasa
# CMAKE_PREFIX_PATH apuntando ahí para que encuentre el Qt6 nativo recién
# compilado (no hay ningún Qt de sistema instalado en el contenedor).
# ------------------------------------------------------------------------------
step_qtshadertools_native() {
    require_qtbase_native
    log "Qt6 (qtshadertools) ${QT6_VERSION} NATIVO — CMake"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtshadertools-native"

    local src="${LFS_BUILD}/qtshadertools-everywhere-src-${QT6_VERSION}"
    local bdir="${QT6_NATIVE_BUILD}/qtshadertools"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "qtshadertools NATIVO instalado en ${QT6_NATIVE_INSTALL}"
}

step_verify_qtshadertools_native() {
    log "Verificación: qsb NATIVO + Qt6ShaderToolsTools"
    local ok=1
    local p
    # qsb SÍ queda en bin/ (a diferencia de moc/rcc/uic en libexec/, ver
    # step_verify_qtbase_native) -- confirmado en la corrida real: qsb es
    # una herramienta que un desarrollador podría querer invocar a mano
    # (compilar shaders .qsb sueltos), no sólo build-time interno.
    for p in \
        "${QT6_NATIVE_INSTALL}/bin/qsb" \
        "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6ShaderToolsTools/Qt6ShaderToolsToolsConfig.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qtshadertools nativo"
    log "OK: qtshadertools NATIVO completo."
}

# ------------------------------------------------------------------------------
# Tier 1) qtsvg NATIVO -- agregado 2026-09-04, retrofit real encontrado
# recompilando qtdeclarative CRUZADO en Tier 3 (libplasma): el tool
# "svgtoqml" (nuevo en Qt 6.11, QuickVectorImage) sólo se agrega
# (add_subdirectory) si "TARGET Qt::Quick AND QT_FEATURE_quick_vectorimage"
# -- confirmado contra tools/CMakeLists.txt real de qtdeclarative -- y esa
# feature depende de Qt::SvgPrivate (confirmado contra
# src/quickvectorimage/CMakeLists.txt real). Sin Qt6Svg NATIVO, la feature
# queda apagada en silencio (ni error ni warning) y el paquete cmake
# "Qt6QuickTools" completo NUNCA se genera -- rompe recién más adelante,
# cuando el build CRUZADO de qtdeclarative busca a "svgtoqml" como host
# tool vía QT_HOST_PATH y no lo encuentra. Mismo prefix compartido
# QT6_NATIVE_INSTALL que el resto de los nativos.
# ------------------------------------------------------------------------------
step_qtsvg_native() {
    require_qtbase_native
    log "Qt6 (qtsvg) ${QT6_VERSION} NATIVO — CMake"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtsvg-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtsvg-native"

    local src="${LFS_BUILD}/qtsvg-everywhere-src-${QT6_VERSION}"
    local bdir="${QT6_NATIVE_BUILD}/qtsvg"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "qtsvg NATIVO instalado en ${QT6_NATIVE_INSTALL}"
}

step_verify_qtsvg_native() {
    log "Verificación: Qt6Svg NATIVO"
    local p="${QT6_NATIVE_INSTALL}/lib/cmake/Qt6Svg/Qt6SvgConfig.cmake"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qtsvg NATIVO completo."
}

require_qtsvg_native() {
    [[ -e "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6Svg/Qt6SvgConfig.cmake" ]] \
        || die "no está qtsvg NATIVO en ${QT6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh qtsvg-native"
}

# ------------------------------------------------------------------------------
# Tier 1) qtdeclarative NATIVO — provee "qmlcachegen" (precompila .qml a
# bytecode) y "qmltyperegistrar" (genera metadatos de tipos QML), que TODO
# módulo que use QML invoca en su propio build vía qt_add_qml_module() --
# no sólo el qtdeclarative cruzado en sí, sino más adelante kwin y
# plasma-workspace también (ambos con Quick/QML pesado: Kirigami, plasma
# shell, kcm's). Mismo prefix compartido QT6_NATIVE_INSTALL. Depende
# también de qtsvg NATIVO (ver comentario arriba) para que
# QT_FEATURE_quick_vectorimage se prenda y genere el paquete
# "Qt6QuickTools" completo (svgtoqml).
# ------------------------------------------------------------------------------
step_qtdeclarative_native() {
    require_qtbase_native
    require_qtshadertools_native
    require_qtsvg_native
    log "Qt6 (qtdeclarative) ${QT6_VERSION} NATIVO — CMake"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtdeclarative-native"

    local src="${LFS_BUILD}/qtdeclarative-everywhere-src-${QT6_VERSION}"
    local bdir="${QT6_NATIVE_BUILD}/qtdeclarative"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "qtdeclarative NATIVO instalado en ${QT6_NATIVE_INSTALL}"
}

step_verify_qtdeclarative_native() {
    log "Verificación: qmlcachegen/qmltyperegistrar/svgtoqml NATIVOS + Qt6QmlTools/Qt6QuickTools"
    local ok=1
    local p
    for p in \
        "${QT6_NATIVE_INSTALL}/libexec/qmlcachegen" \
        "${QT6_NATIVE_INSTALL}/libexec/qmltyperegistrar" \
        "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6QmlTools/Qt6QmlToolsConfig.cmake" \
        "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6QuickTools/Qt6QuickToolsConfig.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qtdeclarative nativo"
    log "OK: qtdeclarative NATIVO completo."
}

require_qtdeclarative_native() {
    [[ -x "${QT6_NATIVE_INSTALL}/libexec/qmlcachegen" ]] \
        || die "no está qtdeclarative NATIVO en ${QT6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh qtdeclarative-native"
}

# ------------------------------------------------------------------------------
# Tier 1) qttools NATIVO -- agregado tras un error real (2026-09-04): el
# build CRUZADO de qttools falló en el configure con "Failed to find the
# host tool 'Qt6::lconvert'. It is part of the Qt6LinguistTools package".
# A diferencia de lo que decía el mapa de dependencias original (qttools NO
# necesitaba build nativo porque no aporta herramientas que OTRO módulo
# consuma), acá lo que hace falta es una herramienta de qttools que SU
# PROPIO build cruzado invoca internamente (lconvert, usado por el propio
# módulo linguist al compilarse) -- mismo patrón de fondo que moc/rcc/qsb/
# qmlcachegen, sólo que el consumidor es el mismo módulo, no otro. Mismo
# prefix compartido QT6_NATIVE_INSTALL de siempre.
# ------------------------------------------------------------------------------
step_qttools_native() {
    require_qtbase_native
    log "Qt6 (qttools) ${QT6_VERSION} NATIVO — CMake"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qttools-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qttools-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qttools-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qttools-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qttools-native"

    local src="${LFS_BUILD}/qttools-everywhere-src-${QT6_VERSION}"
    local bdir="${QT6_NATIVE_BUILD}/qttools"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "qttools NATIVO instalado en ${QT6_NATIVE_INSTALL}"
}

step_verify_qttools_native() {
    log "Verificación: lconvert NATIVO + Qt6LinguistTools"
    local ok=1
    local p
    for p in \
        "${QT6_NATIVE_INSTALL}/bin/lconvert" \
        "${QT6_NATIVE_INSTALL}/lib/cmake/Qt6LinguistTools/Qt6LinguistToolsConfig.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qttools nativo"
    log "OK: qttools NATIVO completo."
}

require_qttools_native() {
    [[ -x "${QT6_NATIVE_INSTALL}/bin/lconvert" ]] \
        || die "no está qttools NATIVO en ${QT6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh qttools-native"
}

# ------------------------------------------------------------------------------
# Tier 1) qtbase CRUZADO — el build real que termina en el sysroot.
# -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" es el mecanismo real (confirmado en
# qtbase/cmake/README.md, sección "Cross Compiling") para que encuentre
# moc/rcc/uic/qsb/qmlcachegen/qmltyperegistrar/qtwaylandscanner de los 3
# pasos nativos de más arriba, en vez de intentar compilarlos de nuevo (cosa
# que fallaría -- esos binarios cruzados no podrían correr en el
# contenedor, mismo problema de fondo de siempre en este proyecto).
#
# -DINPUT_opengl=es2 -- CORREGIDO (primer error real de este paso, ver más
# abajo): el primer intento usó "desktop", asumiendo que como Mesa da
# Gallium/OpenGL completo, correspondía el GL de escritorio clásico. Error:
# "desktop" depende de que exista libGL.so real (el WrapOpenGL de CMake lo
# busca por find_library), y confirmado con un find real sobre el sysroot
# que Mesa NUNCA lo generó acá -- sólo libGLESv2.so/libGLESv1_CM.so (Fase 6
# Parte 2 se compiló con -Dplatforms=wayland, sin -Dglx ni glvnd, así que
# Mesa nunca arma el libGL.so clásico atado a GLX/dispatch multi-vendor,
# aunque el header GL/gl.h sí se instala igual). "es2" es la opción
# correcta para este sysroot: usa libGLESv2.so (sí existe) vía contexto EGL
# -- el camino estándar y documentado por el propio Qt para setups
# Wayland-only sin GLX (ver doc.qt.io/qt-6/embedded-linux.html, que insiste
# en EGLFS/GLESv2 para targets sin X11).
# -DFEATURE_xcb=OFF: sin X11 (decisión ya tomada, ver env.sh).
# PKG_CONFIG_LIBDIR/PKG_CONFIG_SYSROOT_DIR: mismo prefijo que usa TODO el
# resto del proyecto (Meson, Autotools y CMake por igual -- ver
# step_dbus()/step_polkit() en este mismo repo) para que cualquier
# pkg_check_modules() interno de Qt6 (dbus, fontconfig, etc.) resuelva
# contra el sysroot, no contra el contenedor.
# -DINSTALL_QMLDIR=lib/qml: agregado 2026-09-04, retrofit real encontrado
# recién en Tier 3 (libplasma) mucho después de que este paso ya estaba
# "✅ COMPLETO" -- el default real de Qt6 (sin este flag) es
# QT6_INSTALL_QML="qml" (confirmado leyendo
# ${LFS_SYSROOT}/usr/lib/cmake/Qt6/QtInstallPaths.cmake real), es decir
# TODO módulo QML que instala el árbol de Qt (qtdeclarative, qt5compat,
# qtwayland) cae en /usr/qml -- pero ecm_find_qmlmodule() de KDE (usado
# por libplasma para pedir Qt5Compat.GraphicalEffects como REQUIRED) busca
# en KDE_INSTALL_QMLDIR, que en este proyecto resuelve a /usr/lib/qml (el
# fallback real de KDEInstallDirs6.cmake, ver el mismo archivo real:
# "_define_relative(QMLDIR LIBDIR "qml" ...)" -- el intento previo de esa
# macro de preguntarle a Qt vía ecm_query_qt() no sirve en un build
# CRUZADO, termina consultando el qtpaths NATIVO). Mismo criterio que usan
# distros reales (Fedora/Arch fijan INSTALL_QMLDIR para que coincida con
# el qml dir de KDE) -- se alinea Qt a la convención de KDE acá, no al
# revés. Retrofit real: qtbase, qtdeclarative, qtsvg, qt5compat y
# qtwayland (todo lo que instala contenido QML del árbol de Qt) se
# tuvieron que RECOMPILAR después de este cambio -- ver docs/PENDIENTES.md.
# ------------------------------------------------------------------------------
step_qtbase() {
    require_toolchain
    require_qtbase_native
    require_qtshadertools_native
    require_qtdeclarative_native
    log "Qt6 (qtbase) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO (usa QT_HOST_PATH)"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtbase-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtbase-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtbase"

    local src="${LFS_BUILD}/qtbase-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtbase-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF \
        -DFEATURE_xcb=OFF \
        -DINPUT_opengl=es2 \
        -DINSTALL_QMLDIR=lib/qml

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtbase instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qtbase() {
    log "Verificación: Qt6Core/Qt6Gui/Qt6Widgets + moc/rcc/uic en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libQt6Core.so" \
        "${LFS_SYSROOT}/usr/lib/libQt6Gui.so" \
        "${LFS_SYSROOT}/usr/lib/libQt6Widgets.so" \
        "${LFS_SYSROOT}/usr/lib/libQt6DBus.so" \
        "${LFS_SYSROOT}/usr/lib/cmake/Qt6/Qt6Config.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qtbase en el sysroot"
    log "OK: qtbase completo en el sysroot."
}

require_qtbase() {
    [[ -e "${LFS_SYSROOT}/usr/lib/cmake/Qt6/Qt6Config.cmake" ]] \
        || die "no está qtbase en el sysroot -- corré primero: scripts/build-kde.sh qtbase"
}

# ------------------------------------------------------------------------------
# Tier 1) qtshadertools CRUZADO — la librería QtShaderTools en sí (Qt Quick
# la linkea en runtime para el shader baker de RHI). No hace falta pisar
# ningún binario acá: encuentra el qtbase CRUZADO ya instalado en el
# sysroot vía CMAKE_FIND_ROOT_PATH del toolchain file (no CMAKE_PREFIX_PATH,
# eso era sólo para el build NATIVO, que no tenía sysroot); QT_HOST_PATH
# sigue haciendo falta para que su propio build encuentre "qsb" NATIVO
# (se usa en tiempo de build para las pruebas/generadores internos).
# ------------------------------------------------------------------------------
step_qtshadertools() {
    require_toolchain
    require_qtbase
    require_qtshadertools_native
    log "Qt6 (qtshadertools) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtshadertools-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtshadertools"

    local src="${LFS_BUILD}/qtshadertools-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtshadertools-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtshadertools instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qtshadertools() {
    log "Verificación: libQt6ShaderTools.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQt6ShaderTools.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qtshadertools completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qtdeclarative CRUZADO — motor QML/Quick real (Qt6::Qml, Qt6::Quick,
# QuickControls2, etc.), lo que kwin y plasma-workspace usan pesado.
# ------------------------------------------------------------------------------
step_qtdeclarative() {
    require_toolchain
    require_qtbase
    require_qtdeclarative_native
    log "Qt6 (qtdeclarative) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtdeclarative-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtdeclarative"

    local src="${LFS_BUILD}/qtdeclarative-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtdeclarative-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtdeclarative instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qtdeclarative() {
    log "Verificación: libQt6Qml.so + libQt6Quick.so en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libQt6Qml.so" \
        "${LFS_SYSROOT}/usr/lib/libQt6Quick.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de qtdeclarative en el sysroot"
    log "OK: qtdeclarative completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qtsvg CRUZADO — plugin de formato de imagen SVG (QIcon/QImage con
# .svg) + el módulo Qt6::Svg que usan los íconos de KDE (breeze-icons son
# SVG). Ninguno de los módulos restantes de Tier 1 depende de un build
# NATIVO propio (sin herramientas de build-time), así que de acá en más es
# el patrón más simple: sólo CROSS, sin require_*_native.
# ------------------------------------------------------------------------------
step_qtsvg() {
    require_toolchain
    require_qtbase
    log "Qt6 (qtsvg) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtsvg-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtsvg-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtsvg"

    local src="${LFS_BUILD}/qtsvg-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtsvg-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtsvg instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qtsvg() {
    log "Verificación: libQt6Svg.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQt6Svg.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qtsvg completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qt5compat CRUZADO — Core5Compat (kwin lo pide explícito, ver
# find_package(Qt6 ... COMPONENTS Core5Compat) real) + módulos QML de
# compatibilidad (Qt5.15 Compat). Depende de qtbase Y qtdeclarative (según
# .gitmodules real: "depends = qtbase qtdeclarative").
# ------------------------------------------------------------------------------
step_qt5compat() {
    require_toolchain
    require_qtbase
    log "Qt6 (qt5compat) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qt5compat-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qt5compat-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qt5compat-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qt5compat-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qt5compat"

    local src="${LFS_BUILD}/qt5compat-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qt5compat-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qt5compat instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qt5compat() {
    log "Verificación: libQt6Core5Compat.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQt6Core5Compat.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qt5compat completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qttools CRUZADO — kwin pide el componente "UiTools" (Qt6::UiTools,
# QUiLoader) explícito en su find_package(Qt6 ...). El resto de qttools
# (Linguist/Designer/Assistant) se compila igual -- no hace falta acotar,
# no arrastra dependencias nuevas más allá de lo que ya está en el sysroot.
# ------------------------------------------------------------------------------
step_qttools() {
    require_toolchain
    require_qtbase
    require_qttools_native
    log "Qt6 (qttools) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qttools-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qttools-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qttools-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qttools-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qttools"

    local src="${LFS_BUILD}/qttools-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qttools-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qttools instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qttools() {
    log "Verificación: libQt6UiTools.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQt6UiTools.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qttools completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 1) qtwayland CRUZADO — último módulo Qt6 de Tier 1. kwin pide
# Qt6::WaylandClient (que, según lo confirmado en step_qtbase(), YA viene
# integrado en qtbase mismo en esta versión de Qt) -- lo que este módulo
# aporta de verdad y que ningún otro trae es Qt6::WaylandCompositor, la
# librería del LADO SERVIDOR del protocolo Wayland, que un compositor como
# kwin necesita para implementar su propio servidor. Sin flags especiales
# a priori -- primera corrida real, se ajusta si hace falta.
# ------------------------------------------------------------------------------
step_qtwayland() {
    require_toolchain
    require_qtbase
    log "Qt6 (qtwayland) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtwayland-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtwayland-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtwayland-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtwayland-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtwayland"

    local src="${LFS_BUILD}/qtwayland-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtwayland-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtwayland instalado en ${LFS_SYSROOT}/usr"
}

step_verify_qtwayland() {
    log "Verificación: libQt6WaylandCompositor.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQt6WaylandCompositor.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: qtwayland completo en el sysroot."
}

# Cross file de Meson -- sólo hace falta para iso-codes (Meson, el resto de
# Tier 2 es CMake). Copia mínima del patrón real ya usado en
# build-desktop.sh/build-mesa.sh -- acá no hace falta pisar binarios
# (extra_binaries), iso-codes sólo corre scripts Python en tiempo de build,
# nunca invoca una herramienta cross-compilada.
write_meson_crossfile() {
    local crossfile="$1"
    cat > "${crossfile}" <<EOF
[binaries]
c = '${LFS_TOOLS}/bin/${LFS_TGT}-gcc'
cpp = '${LFS_TOOLS}/bin/${LFS_TGT}-g++'
ar = '${LFS_TOOLS}/bin/${LFS_TGT}-ar'
strip = '${LFS_TOOLS}/bin/${LFS_TGT}-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
pkg_config_libdir = ['${LFS_SYSROOT}/usr/lib/pkgconfig', '${LFS_SYSROOT}/usr/share/pkgconfig']
sys_root = '${LFS_SYSROOT}'
EOF
}

# ------------------------------------------------------------------------------
# Tier 2) IsoCodes -- prerequisito de ki18n. Paquete de datos puro (JSON/XML
# de códigos ISO de idiomas/países/monedas), Meson, sin código C/C++ que
# compilar de verdad -- los "custom_target" de su meson.build sólo corren
# scripts Python (xml_from_json.py) para generar los XML deprecados a
# partir del JSON real, más msgfmt para las traducciones .mo. Fuente real:
# salsa.debian.org (el upstream real del proyecto, no un mirror).
# ------------------------------------------------------------------------------
step_isocodes() {
    require_toolchain
    log "iso-codes ${ISOCODES_VERSION} para ${LFS_TGT} — Meson+Ninja (datos)"

    # El archive real de salsa.debian.org (GitLab) SÍ mantiene el prefijo
    # "v" en el nombre de archivo/directorio (a diferencia de GitHub, que
    # lo pisa) -- confirmado bajando el tarball real:
    # ".../-/archive/v4.20.1/iso-codes-v4.20.1.tar.gz" extrae a
    # "iso-codes-v4.20.1/".
    cd "${LFS_SOURCES}"
    fetch "${ISOCODES_MIRROR}/v${ISOCODES_VERSION}/iso-codes-v${ISOCODES_VERSION}.tar.gz" \
          "iso-codes-${ISOCODES_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/iso-codes-${ISOCODES_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/iso-codes-${ISOCODES_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-isocodes"

    local src="${LFS_BUILD}/iso-codes-v${ISOCODES_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "iso-codes instalado en ${LFS_SYSROOT}/usr"
}

step_verify_isocodes() {
    log "Verificación: iso-codes.pc + datos JSON en el sysroot"
    local ok=1
    local p
    # iso-codes.pc queda en share/pkgconfig, no lib/pkgconfig -- mismo
    # patrón ya documentado en Fase 6 Parte 1 para paquetes sin código
    # compilado (confirmado con un find real, no asumido).
    for p in \
        "${LFS_SYSROOT}/usr/share/pkgconfig/iso-codes.pc" \
        "${LFS_SYSROOT}/usr/share/iso-codes/json/iso_639-2.json"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de iso-codes en el sysroot"
    log "OK: iso-codes completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 2) PlasmaWaylandProtocols -- prerequisito real de kguiaddons/
# kidletime/kwindowsystem para su soporte Wayland (confirmado leyendo el
# if(WITH_WAYLAND) real de cada uno). NO es parte del tren de KDE
# Frameworks (versionado aparte, 1.21.0 -- no 6.x) ni tiene tarball en
# download.kde.org/stable/plasma/ pese a aparecer listado ahí (confirmado
# 404 real) -- fuente real: mirror de GitHub KDE/plasma-wayland-protocols,
# tag v1.21.0 (coincide exacto con lo que pide kwin). Sólo protocolos XML +
# CMake/ECM, sin código para compilar (confirmado leyendo su
# CMakeLists.txt real completo) -- mismo espíritu que wayland-protocols de
# Fase 6 Parte 1.
# ------------------------------------------------------------------------------
step_plasma_wayland_protocols() {
    require_toolchain
    log "PlasmaWaylandProtocols ${PLASMA_WAYLAND_PROTOCOLS_VERSION} para ${LFS_TGT} — CMake (sólo protocolos XML)"

    cd "${LFS_SOURCES}"
    fetch "${PLASMA_WAYLAND_PROTOCOLS_MIRROR}/v${PLASMA_WAYLAND_PROTOCOLS_VERSION}.tar.gz" \
          "plasma-wayland-protocols-${PLASMA_WAYLAND_PROTOCOLS_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/plasma-wayland-protocols-${PLASMA_WAYLAND_PROTOCOLS_VERSION}.tar.gz"
    # Marcador CON versión -- bug real encontrado 2026-09-16 al subir el pin
    # de 1.21.0 a 1.22.0: el marcador viejo ".extracted-plasma-wayland-protocols"
    # (sin versión) seguía existiendo de la corrida original con 1.21.0, así
    # que extract_once() daba "ya extraído" para 1.22.0 sin haber extraído
    # nada -- el cmake de más abajo fallaba con "source directory ... does
    # not exist". Cualquier paso que algún día suba de versión un paquete ya
    # compilado antes tiene el mismo riesgo si el marcador no incluye la
    # versión.
    extract_once "${LFS_SOURCES}/plasma-wayland-protocols-${PLASMA_WAYLAND_PROTOCOLS_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-plasma-wayland-protocols-${PLASMA_WAYLAND_PROTOCOLS_VERSION}"

    local src="${LFS_BUILD}/plasma-wayland-protocols-${PLASMA_WAYLAND_PROTOCOLS_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "PlasmaWaylandProtocols instalado en ${LFS_SYSROOT}/usr"
}

step_verify_plasma_wayland_protocols() {
    log "Verificación: PlasmaWaylandProtocolsConfig.cmake en el sysroot"
    local p="${LFS_SYSROOT}/usr/share/cmake/PlasmaWaylandProtocols/PlasmaWaylandProtocolsConfig.cmake"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: PlasmaWaylandProtocols completo en el sysroot."
}

require_ecm() {
    [[ -e "${LFS_SYSROOT}/usr/share/ECM/cmake/ECMConfig.cmake" ]] \
        || die "no está ECM en el sysroot -- corré primero: scripts/build-kde.sh ecm"
}

# ------------------------------------------------------------------------------
# Tier 2a) Helper genérico para los KF6 "simples" -- todos CMake+ECM, mismo
# patrón exacto (fetch, extract, cross toolchain, cmake/ninja/install),
# sólo cambia el nombre del paquete y flags puntuales. En vez de repetir el
# mismo bloque 13 veces (11 frameworks + variantes), un solo helper interno
# que cada step_kf6_<nombre>() llama con sus propios argumentos -- reduce
# el riesgo de un typo en una de las 13 copias casi idénticas. Cada
# step_kf6_<nombre>() sigue existiendo como función nombrada (no se
# colapsa todo en una sola, para mantener el mismo estilo de log/dispatch
# que el resto del proyecto).
#
# -DBUILD_PYTHON_BINDINGS=OFF (primer error real de Tier 2a, encontrado en
# kcoreaddons): varios frameworks de KF6 traen bindings de Python opcionales
# (Shiboken6/PySide6) prendidos por defecto en Linux
# ("if (ANDROID OR APPLE OR WIN32 OR HAIKU OR NOT BUILD_SHARED_LIBS):
# BUILD_PYTHON_BINDINGS OFF" -- ninguna de esas excepciones aplica acá), y
# el CMakeLists.txt real exige find_package(Python3 ... COMPONENTS
# Development) cuando está ON -- el Python3.11 del Dockerfile no tiene los
# headers de desarrollo (python3-dev) instalados, algo que este proyecto
# nunca necesitó hasta ahora. Nadie en el proyecto necesita bindings de
# Python de KDE Frameworks, así que se apaga acá una sola vez para los 13
# módulos de Tier 2a en vez de instalar python3-dev sólo para esto.
#
# -DWITH_X11=OFF (segundo error real de Tier 2a, encontrado en
# kdbusaddons): mismo patrón que BUILD_PYTHON_BINDINGS -- pensado al
# principio como algo puntual de kguiaddons/kidletime/kwindowsystem (los
# que además necesitan WITH_WAYLAND=ON + PlasmaWaylandProtocols), pero
# resultó ser una opción MÁS GENERAL de KF6 ("option(WITH_X11 "Build X11
# support" ON)", default ON en Linux, confirmado en el CMakeLists.txt real
# de kdbusaddons -- que ni siquiera usa Wayland, sólo evita X11). Sin este
# flag, kdbusaddons rompía compilando kdbusservice.cpp: "fatal error:
# private/qtx11extras_p.h: No such file or directory" -- ese header privado
# de Qt6Gui sólo existe si Qt6 se compiló CON soporte X11
# (-DFEATURE_xcb=ON), y este proyecto lo compiló apagado a propósito (ver
# step_qtbase(), decisión Wayland puro). Se apaga acá para los 13 módulos
# de Tier 2a de una vez -- si algún módulo no define esta opción, CMake
# como mucho tira un warning de "variable no usada" al final, no falla.
# ------------------------------------------------------------------------------
_kf6_cmake_build() {
    local pkg="$1" tarname="$2"; shift 2
    local extra_cmake_flags=("$@")

    require_toolchain
    require_ecm
    log "KDE Frameworks: ${pkg} ${KDE_VERSION} para ${LFS_TGT} — CMake+ECM"

    cd "${LFS_SOURCES}"
    fetch "${KDE_FRAMEWORKS_MIRROR}/${tarname}-${KDE_VERSION}.tar.xz" \
          "${tarname}-${KDE_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/${tarname}-${KDE_VERSION}.tar.xz"
    # Marcador CON versión -- ver el comentario real en
    # step_plasma_wayland_protocols() (bug real 2026-09-16: un bump de
    # versión de un paquete ya compilado antes hacía que extract_once()
    # diera "ya extraído" contra el directorio VIEJO, sin haber extraído
    # el nuevo tarball).
    extract_once "${LFS_SOURCES}/${tarname}-${KDE_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-${tarname}-${KDE_VERSION}"

    local src="${LFS_BUILD}/${tarname}-${KDE_VERSION}"

    # Mismo hook genérico de patch local que _plasma_cmake_build() --
    # agregado recién (2026-09-16) para el primer bug real de Tier 2/3
    # que exige tocar la fuente (KWallet/blowfish.h, ver _patch_kwallet()).
    local patch_fn="_patch_${tarname//-/_}"
    local patch_marker="${LFS_BUILD}/.patched-${tarname}"
    if declare -F "${patch_fn}" >/dev/null && [[ ! -f "${patch_marker}" ]]; then
        log "Aplicando patch local: ${patch_fn}()"
        "${patch_fn}" "${src}"
        touch "${patch_marker}"
    fi

    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_QCH=OFF \
        -DBUILD_PYTHON_BINDINGS=OFF \
        -DWITH_X11=OFF \
        "${extra_cmake_flags[@]}"

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "${pkg} instalado en ${LFS_SYSROOT}/usr"
}

_kf6_verify_lib() {
    local pkg="$1" libfile="$2"
    log "Verificación: ${libfile} en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/${libfile}"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: ${pkg} completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Tier 3 -- "tren de Plasma". Mismo mecanismo CMake+ECM que _kf6_cmake_build(),
# pero con PLASMA_MIRROR/PLASMA_VERSION en vez de KDE_FRAMEWORKS_MIRROR/
# KDE_VERSION (versionado aparte de KF6, ver comentario real en env.sh).
# _kf6_verify_lib() se reutiliza tal cual para verificar -- no depende del
# esquema de versión, sólo busca el archivo en el sysroot.
# ------------------------------------------------------------------------------
_plasma_cmake_build() {
    local pkg="$1" tarname="$2"; shift 2
    local extra_cmake_flags=("$@")

    require_toolchain
    require_ecm
    log "Plasma: ${pkg} ${PLASMA_VERSION} para ${LFS_TGT} — CMake+ECM"

    cd "${LFS_SOURCES}"
    fetch "${PLASMA_MIRROR}/${tarname}-${PLASMA_VERSION}.tar.xz" \
          "${tarname}-${PLASMA_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/${tarname}-${PLASMA_VERSION}.tar.xz"
    # Marcador CON versión -- ver el comentario real en
    # step_plasma_wayland_protocols() (bug real 2026-09-16).
    extract_once "${LFS_SOURCES}/${tarname}-${PLASMA_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-${tarname}-${PLASMA_VERSION}"

    local src="${LFS_BUILD}/${tarname}-${PLASMA_VERSION}"

    # Hook de parche local opcional -- 2026-09-04, agregado recién para el
    # primer (y hasta ahora único) bug real de upstream que EXIGE tocar la
    # fuente (ver _patch_libplasma() y el comentario largo en
    # step_libplasma()). Si existe una función bash "_patch_<tarname>", se
    # corre una sola vez contra el source recién extraído (marcador
    # .patched-<tarname>, mismo criterio que extract_once). No agregar
    # patches "por las dudas" -- sólo cuando aparece un bug real.
    local patch_fn="_patch_${tarname//-/_}"
    local patch_marker="${LFS_BUILD}/.patched-${tarname}"
    if declare -F "${patch_fn}" >/dev/null && [[ ! -f "${patch_marker}" ]]; then
        log "Aplicando patch local: ${patch_fn}()"
        "${patch_fn}" "${src}"
        touch "${patch_marker}"
    fi

    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_QCH=OFF \
        -DBUILD_PYTHON_BINDINGS=OFF \
        -DWITH_X11=OFF \
        "${extra_cmake_flags[@]}"

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "${pkg} instalado en ${LFS_SYSROOT}/usr"
}

step_kcodecs()          { _kf6_cmake_build KCodecs kcodecs; }
step_verify_kcodecs()   { _kf6_verify_lib KCodecs libKF6Codecs.so; }

step_kitemviews()        { _kf6_cmake_build KItemViews kitemviews; }
step_verify_kitemviews() { _kf6_verify_lib KItemViews libKF6ItemViews.so; }

step_kitemmodels()        { _kf6_cmake_build KItemModels kitemmodels; }
step_verify_kitemmodels() { _kf6_verify_lib KItemModels libKF6ItemModels.so; }

# kcoreaddons -- LibMount REQUIRED (util-linux, ya compilado Fase 2), Inotify
# opcional (headers del kernel). Sin flags extra, se auto-detecta contra el
# sysroot vía el toolchain file de siempre.
step_kcoreaddons()        { _kf6_cmake_build KCoreAddons kcoreaddons; }
step_verify_kcoreaddons() { _kf6_verify_lib KCoreAddons libKF6CoreAddons.so; }

# Bug real encontrado MUCHO más tarde (2026-09-16, recién al compilar
# Breeze en Tier 3) pero que corresponde acá: KConfig instala
# "kconfig_compiler_kf6" (compila archivos .kcfg a C++) en
# ${LFS_SYSROOT}/usr/lib/libexec/kf6/ -- un binario CRUZADO. Mismo
# problema de fondo de siempre, pero recién ahora se manifestó porque
# Breeze es el PRIMER paquete de todo el proyecto que realmente usa
# "kconfig_add_kcfg_files()" en su build (ningún consumidor de KF6 hasta
# ahora había procesado un .kcfg de verdad) -- confirmado con un ldd real:
# ni libQt6Xml.so.6 ni libQt6Core.so.6 resuelven al ejecutarlo directo en
# el contenedor, y además choca versión de GLIBCXX contra el libstdc++
# del contenedor. KConfig no tiene ningún mecanismo TOOLS_ONLY ni
# KF6_HOST_TOOLING propio (confirmado contra su CMakeLists.txt real) --
# se compila un KConfig NATIVO mínimo (`-DKCONFIG_USE_GUI=OFF
# -DKCONFIG_USE_QML=OFF -DUSE_DBUS=OFF`, sólo pide Qt6 Core+Xml, ambos ya
# nativos) y se pisa el binario roto del sysroot con el nativo -- mismo
# patrón que kcmdesktopfilegenerator un poco más arriba.
step_kconfig_native() {
    require_qtbase_native
    log "KConfig ${KDE_VERSION} NATIVO (sólo kconfig_compiler_kf6) — CMake"

    cd "${LFS_SOURCES}"
    fetch "${KDE_FRAMEWORKS_MIRROR}/kconfig-${KDE_VERSION}.tar.xz" \
          "kconfig-${KDE_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/kconfig-${KDE_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/kconfig-${KDE_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-kconfig-native-${KDE_VERSION}"

    local src="${LFS_BUILD}/kconfig-${KDE_VERSION}"
    local bdir="${KF6_NATIVE_BUILD}/kconfig"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX="${KF6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DKCONFIG_USE_GUI=OFF \
        -DKCONFIG_USE_QML=OFF \
        -DUSE_DBUS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "KConfig NATIVO (kconfig_compiler_kf6) instalado en ${KF6_NATIVE_INSTALL}"
}

# -DCMAKE_INSTALL_LIBDIR=lib (agregado 2026-09-16, retrofit real): sin
# este flag, GNUInstallDirs detecta multiarch en el build NATIVO
# (contenedor Debian) e inserta "x86_64-linux-gnu" en el libdir --
# rompía kwin más adelante (ver comentario largo en step_kwin(): un
# KF6_HOST_TOOLING real necesita que las herramientas nativas de KF6 y
# de Qt6 (QT6_NATIVE_INSTALL, sin multiarch) vivan a la MISMA
# profundidad de directorio, porque los "*Targets.cmake" generados por
# CMake calculan su _IMPORT_PREFIX navegando ".." un número FIJO de
# niveles -- una profundidad distinta rompe ese cálculo con un path sin
# sentido). Forzar "lib" a secas alinea a KF6_NATIVE_INSTALL con el
# layout de QT6_NATIVE_INSTALL.
KCONFIG_NATIVE_TOOL="${KF6_NATIVE_INSTALL}/lib/libexec/kf6/kconfig_compiler_kf6"

step_verify_kconfig_native() {
    log "Verificación: kconfig_compiler_kf6 NATIVO"
    [[ -x "${KCONFIG_NATIVE_TOOL}" ]] || die "no está ${KCONFIG_NATIVE_TOOL}"
    echo "  [OK] ${KCONFIG_NATIVE_TOOL}"
    log "OK: kconfig NATIVO completo."
}

require_kconfig_native() {
    [[ -x "${KCONFIG_NATIVE_TOOL}" ]] \
        || die "no está kconfig_compiler_kf6 NATIVO -- corré primero: scripts/build-kde.sh kconfig-native"
}

step_kconfig() {
    require_kconfig_native
    _kf6_cmake_build KConfig kconfig
    cp -f "${KCONFIG_NATIVE_TOOL}" \
          "${LFS_SYSROOT}/usr/lib/libexec/kf6/kconfig_compiler_kf6"
    log "kconfig_compiler_kf6 del sysroot pisado con la versión NATIVA"
}
step_verify_kconfig() { _kf6_verify_lib KConfig libKF6ConfigCore.so; }

step_kwidgetsaddons()        { _kf6_cmake_build KWidgetsAddons kwidgetsaddons; }
step_verify_kwidgetsaddons() { _kf6_verify_lib KWidgetsAddons libKF6WidgetsAddons.so; }

# ki18n -- LibIntl (parte de glibc, siempre disponible) + IsoCodes (paso
# nuevo de más arriba, tiene que correr antes).
require_isocodes() {
    [[ -e "${LFS_SYSROOT}/usr/share/pkgconfig/iso-codes.pc" ]] \
        || die "no está iso-codes en el sysroot -- corré primero: scripts/build-kde.sh isocodes"
}
step_ki18n() { require_isocodes; _kf6_cmake_build KI18n ki18n; }
step_verify_ki18n() { _kf6_verify_lib KI18n libKF6I18n.so; }

step_kdbusaddons()        { _kf6_cmake_build KDBusAddons kdbusaddons; }
step_verify_kdbusaddons() { _kf6_verify_lib KDBusAddons libKF6DBusAddons.so; }

# liblzma (xz) -- SEGUNDO prerequisito real de karchive encontrado en la
# corrida real, después de zstd. La primera corrida real con zstd ya
# resuelto mostró "REQUIRED packages... not found: LibLZMA" -- el
# `find_package(LibLZMA)` (sin REQUIRED) del CMakeLists.txt de karchive no
# frena el configure por sí solo, pero `WITH_LIBLZMA` también está en ON
# por default (mismo patrón exacto que WITH_LIBZSTD, arriba) y el
# `ecm_feature_summary()` final SÍ frena si falta algo marcado
# REQUIRED-por-opción. Corrección a un comentario anterior de este archivo
# ("ZLIB/BZip2/LibLZMA/OpenSSL, los 4 ya compilados") -- estaba mal:
# `xz-utils` sólo existía como herramienta de HOST (Dockerfile, para
# extraer tarballs .tar.xz durante el build), nunca se había cross-
# compilado la librería para el sysroot. Última release real
# (tukaani-project/xz v5.8.3), build vía su CMakeLists.txt propio (soporta
# CMake nativo desde hace varias versiones, no hace falta autotools).
step_liblzma() {
    require_toolchain
    log "liblzma (xz) ${LIBLZMA_VERSION} para ${LFS_TGT} — CMake"

    cd "${LFS_SOURCES}"
    fetch "${LIBLZMA_MIRROR}/xz-${LIBLZMA_VERSION}.tar.gz" \
          "xz-${LIBLZMA_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/xz-${LIBLZMA_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/xz-${LIBLZMA_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-liblzma"

    local src="${LFS_BUILD}/xz-${LIBLZMA_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DXZ_TOOL_XZ=OFF \
        -DXZ_TOOL_XZDEC=OFF \
        -DXZ_TOOL_LZMADEC=OFF \
        -DXZ_TOOL_LZMAINFO=OFF \
        -DXZ_DOC=OFF \
        -DXZ_NLS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "liblzma instalado en ${LFS_SYSROOT}/usr"
}

step_verify_liblzma() {
    log "Verificación: liblzma.so + liblzma.pc en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/liblzma.so" \
        "${LFS_SYSROOT}/usr/lib/pkgconfig/liblzma.pc"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de liblzma en el sysroot"
    log "OK: liblzma completo en el sysroot."
}

require_liblzma() {
    [[ -e "${LFS_SYSROOT}/usr/lib/pkgconfig/liblzma.pc" ]] \
        || die "no está liblzma en el sysroot -- corré primero: scripts/build-kde.sh liblzma"
}

# zstd -- prerequisito real de karchive, encontrado en la corrida real (no
# estaba en el mapa de dependencias original: el grep inicial de
# find_package() de karchive no lo detectó porque karchive lo busca con
# pkg_check_modules(LibZstd ..., "libzstd"), un macro distinto de
# find_package() que el research original no había cubierto). Confirmado
# leyendo el CMakeLists.txt real de karchive: "option(WITH_LIBZSTD "Make
# libzstd required" ON)" -- con esa opción prendida (default), libzstd es
# obligatorio de verdad, no un "Could NOT find" tolerado como LibLZMA. En
# vez de apagar la opción (perder soporte de compresión zstd sin necesidad
# real), se compila zstd de una vez -- es chico y sin dependencias
# externas más allá de un compilador. Última release real
# (facebook/zstd v1.5.7), build vía el CMakeLists.txt propio del proyecto
# en build/cmake/ (el root del repo no es un proyecto CMake en sí).
step_zstd() {
    require_toolchain
    log "zstd ${ZSTD_VERSION} para ${LFS_TGT} — CMake"

    cd "${LFS_SOURCES}"
    fetch "${ZSTD_MIRROR}/zstd-${ZSTD_VERSION}.tar.gz" \
          "zstd-${ZSTD_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/zstd-${ZSTD_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/zstd-${ZSTD_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-zstd"

    local src="${LFS_BUILD}/zstd-${ZSTD_VERSION}/build/cmake"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/zstd-${ZSTD_VERSION}/build/cmake-build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "zstd instalado en ${LFS_SYSROOT}/usr"
}

step_verify_zstd() {
    log "Verificación: libzstd.so + libzstd.pc en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libzstd.so" \
        "${LFS_SYSROOT}/usr/lib/pkgconfig/libzstd.pc"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de zstd en el sysroot"
    log "OK: zstd completo en el sysroot."
}

require_zstd() {
    [[ -e "${LFS_SYSROOT}/usr/lib/pkgconfig/libzstd.pc" ]] \
        || die "no está zstd en el sysroot -- corré primero: scripts/build-kde.sh zstd"
}

# karchive -- ZLIB/BZip2/OpenSSL ya compilados en este proyecto (Fase 2/
# Fase 4); zstd y liblzma (arriba) son los dos nuevos, encontrados en las
# corridas reales de este mismo paso.
step_karchive() {
    require_zstd
    require_liblzma
    _kf6_cmake_build KArchive karchive
}
step_verify_karchive() { _kf6_verify_lib KArchive libKF6Archive.so; }

step_kglobalaccel()        { _kf6_cmake_build KGlobalAccel kglobalaccel; }
step_verify_kglobalaccel() { _kf6_verify_lib KGlobalAccel libKF6GlobalAccel.so; }

require_plasma_wayland_protocols() {
    [[ -e "${LFS_SYSROOT}/usr/share/cmake/PlasmaWaylandProtocols/PlasmaWaylandProtocolsConfig.cmake" ]] \
        || die "no está PlasmaWaylandProtocols en el sysroot -- corré primero: scripts/build-kde.sh plasma-wayland-protocols"
}

# kguiaddons/kidletime/kwindowsystem -- los 3 necesitan PlasmaWaylandProtocols
# (paso nuevo de más arriba) y comparten la misma decisión real: Wayland
# puro, WITH_X11=OFF/WITH_WAYLAND=ON (confirmado que estos son los nombres
# reales de la opción leyendo el if() de cada CMakeLists.txt -- no
# asumido). No todos los 3 CMakeLists.txt usan literalmente esos dos
# nombres de opción con el mismo casing en los 3 -- si alguno da
# "Unknown option" en la corrida real, ese es el primer lugar a revisar.
step_kguiaddons() {
    require_plasma_wayland_protocols
    _kf6_cmake_build KGuiAddons kguiaddons -DWITH_WAYLAND=ON
}
step_verify_kguiaddons() { _kf6_verify_lib KGuiAddons libKF6GuiAddons.so; }

step_kidletime() {
    require_plasma_wayland_protocols
    _kf6_cmake_build KIdleTime kidletime -DWITH_WAYLAND=ON
}
step_verify_kidletime() { _kf6_verify_lib KIdleTime libKF6IdleTime.so; }

step_kwindowsystem() {
    require_plasma_wayland_protocols
    # Confirmado el error anticipado en el comentario de arriba: kwindowsystem
    # NO usa WITH_X11/WITH_WAYLAND como kguiaddons/kidletime -- tiene sus
    # propias opciones con prefijo propio ("option(KWINDOWSYSTEM_X11 "Build
    # X11 support" ON)" / "option(KWINDOWSYSTEM_WAYLAND ...)", confirmado
    # leyendo su CMakeLists.txt real). El WITH_X11=OFF del helper compartido
    # no le hace nada (CMake lo ignora con un warning de "variable no usada"
    # al final, no falla) -- hay que pisar el nombre real acá.
    _kf6_cmake_build KWindowSystem kwindowsystem \
        -DKWINDOWSYSTEM_X11=OFF -DKWINDOWSYSTEM_WAYLAND=ON
}
step_verify_kwindowsystem() { _kf6_verify_lib KWindowSystem libKF6WindowSystem.so; }

# ------------------------------------------------------------------------------
# Tier 2b) -- dependen de frameworks de Tier 2a, todos ya en el sysroot.
# Mismo helper _kf6_cmake_build(), mismo criterio de flags (WITH_X11=OFF y
# BUILD_PYTHON_BINDINGS=OFF ya salen del helper por default).
# ------------------------------------------------------------------------------

require_kf6() {
    local name="$1"
    [[ -e "${LFS_SYSROOT}/usr/lib/cmake/KF6${name}/KF6${name}Config.cmake" ]] \
        || die "no está KF6${name} en el sysroot -- corré primero: scripts/build-kde.sh <paso correspondiente>"
}

# kcolorscheme -- KF6Config, KF6GuiAddons, KF6I18n (los 3 ya en el sysroot).
step_kcolorscheme() { _kf6_cmake_build KColorScheme kcolorscheme; }
step_verify_kcolorscheme() { _kf6_verify_lib KColorScheme libKF6ColorScheme.so; }

# kauth -- KF6CoreAddons.
step_kauth() { _kf6_cmake_build KAuth kauth; }
step_verify_kauth() { _kf6_verify_lib KAuth libKF6AuthCore.so; }

# kcrash -- KF6CoreAddons, WITH_X11 estándar (ya lo apaga el helper).
step_kcrash() { _kf6_cmake_build KCrash kcrash; }
step_verify_kcrash() { _kf6_verify_lib KCrash libKF6Crash.so; }

# kcompletion -- KF6Codecs, KF6Config, KF6WidgetsAddons.
step_kcompletion() { _kf6_cmake_build KCompletion kcompletion; }
step_verify_kcompletion() { _kf6_verify_lib KCompletion libKF6Completion.so; }

# kconfigwidgets -- necesita KColorScheme (arriba), además de CoreAddons/
# Codecs/Config/GuiAddons/I18n/WidgetsAddons, todos ya en el sysroot.
step_kconfigwidgets() {
    require_kf6 ColorScheme
    _kf6_cmake_build KConfigWidgets kconfigwidgets
}
step_verify_kconfigwidgets() { _kf6_verify_lib KConfigWidgets libKF6ConfigWidgets.so; }

# kservice -- KF6Config, KF6CoreAddons, KF6I18n. KF6DocTools es opcional
# (find_package sin REQUIRED) -- se deja afuera por ahora, ver kdoctools
# más abajo (diferido, no bloquea nada de lo que sigue).
step_kservice() { _kf6_cmake_build KService kservice; }
step_verify_kservice() { _kf6_verify_lib KService libKF6Service.so; }

# kpackage -- KF6Archive, KF6I18n, KF6CoreAddons. KF6DocTools opcional,
# mismo criterio que kservice.
step_kpackage() { _kf6_cmake_build KPackage kpackage; }
step_verify_kpackage() { _kf6_verify_lib KPackage libKF6Package.so; }

# libltdl -- prerequisito real de libcanberra, encontrado en la corrida
# real (primer error real de este script en Autotools): "configure: error:
# Unable to find libltdl." -- confirmado leyendo el configure.ac real de
# libcanberra ("LT_INIT(...)" + un chequeo explícito de ltdl.h/lt_dladvise_init
# con AC_MSG_ERROR si falta, sin ningún flag para saltearlo) que es un
# requisito duro: libcanberra carga sus backends (alsa/null/...) como
# módulos dinámicos vía libltdl, no directo. libltdl NO es la
# infraestructura de libtool que ya usa cada ./configure de este proyecto
# (esa es sólo el script `libtool`/`ltmain.sh`, generado en cada paquete)
# -- es una librería runtime aparte, "libltdl.so", que vive en el
# subdirectorio libltdl/ del propio tarball de GNU Libtool y tiene su
# PROPIO configure standalone (confirmado bajando el tarball real:
# "libtool-2.6.2/libltdl/configure" existe) -- no hace falta compilar
# libtool completo, sólo esa subcarpeta.
step_libltdl() {
    require_toolchain
    log "libltdl (de GNU libtool ${LIBTOOL_VERSION}) para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBTOOL_MIRROR}/libtool-${LIBTOOL_VERSION}.tar.xz" \
          "libtool-${LIBTOOL_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libtool-${LIBTOOL_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libtool-${LIBTOOL_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libltdl"

    local src="${LFS_BUILD}/libtool-${LIBTOOL_VERSION}/libltdl"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    # --enable-ltdl-install: primer intento sin este flag compiló sólo
    # libltdlc.la (la "convenience library" interna, noinst_LTLIBRARIES) y
    # "make install" no instaló nada -- confirmado leyendo el Makefile.am
    # real: "lib_LTLIBRARIES += libltdl.la" está adentro de
    # "if INSTALL_LTDL ... endif", un Automake conditional que sólo se
    # activa con este flag (confirmado con el "./configure --help" real
    # del propio script: "--enable-ltdl-install install libltdl", OFF por
    # default). Nosotros SÍ queremos la librería instalada de verdad
    # (libcanberra la busca como dependencia externa del sistema, no como
    # libltdl "convenience" empaquetada adentro de otro proyecto).
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static \
        --enable-ltdl-install

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libltdl*.la' -delete 2>/dev/null || true

    log "libltdl instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libltdl() {
    log "Verificación: libltdl.so + ltdl.h en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libltdl.so" \
        "${LFS_SYSROOT}/usr/include/ltdl.h"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libltdl en el sysroot"
    log "OK: libltdl completo en el sysroot."
}

require_libltdl() {
    [[ -e "${LFS_SYSROOT}/usr/include/ltdl.h" ]] \
        || die "no está libltdl en el sysroot -- corré primero: scripts/build-kde.sh libltdl"
}

# libogg + libvorbis -- prerequisitos reales de libcanberra, encontrados en
# la corrida real DESPUÉS de resolver libltdl: "### Vorbis (mandatory) ###"
# en el configure.ac real -- libcanberra reproduce los sonidos de tema
# (freedesktop sound theme) codificados en Ogg Vorbis, y no hay flag para
# saltear esto. Xiph.Org (el upstream real de los dos) los publica como
# paquetes separados -- libvorbis depende de libogg. Últimas releases
# reales de downloads.xiph.org.
step_libogg() {
    require_toolchain
    log "libogg ${LIBOGG_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBOGG_MIRROR}/libogg-${LIBOGG_VERSION}.tar.xz" \
          "libogg-${LIBOGG_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libogg-${LIBOGG_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libogg-${LIBOGG_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libogg"

    local src="${LFS_BUILD}/libogg-${LIBOGG_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libogg*.la' -delete 2>/dev/null || true

    log "libogg instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libogg() {
    log "Verificación: libogg.so + ogg.pc en el sysroot"
    local ok=1
    local p
    for p in "${LFS_SYSROOT}/usr/lib/libogg.so" "${LFS_SYSROOT}/usr/lib/pkgconfig/ogg.pc"; do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libogg en el sysroot"
    log "OK: libogg completo en el sysroot."
}

require_libogg() {
    [[ -e "${LFS_SYSROOT}/usr/lib/pkgconfig/ogg.pc" ]] \
        || die "no está libogg en el sysroot -- corré primero: scripts/build-kde.sh libogg"
}

step_libvorbis() {
    require_toolchain
    require_libogg
    log "libvorbis ${LIBVORBIS_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBVORBIS_MIRROR}/libvorbis-${LIBVORBIS_VERSION}.tar.xz" \
          "libvorbis-${LIBVORBIS_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libvorbis-${LIBVORBIS_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libvorbis-${LIBVORBIS_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libvorbis"

    local src="${LFS_BUILD}/libvorbis-${LIBVORBIS_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libvorbis*.la' -delete 2>/dev/null || true

    log "libvorbis instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libvorbis() {
    log "Verificación: libvorbisfile.so + vorbisfile.pc en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libvorbisfile.so" \
        "${LFS_SYSROOT}/usr/lib/pkgconfig/vorbisfile.pc"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libvorbis en el sysroot"
    log "OK: libvorbis completo en el sysroot."
}

require_libvorbis() {
    [[ -e "${LFS_SYSROOT}/usr/lib/pkgconfig/vorbisfile.pc" ]] \
        || die "no está libvorbis en el sysroot -- corré primero: scripts/build-kde.sh libvorbis"
}

# libcanberra -- CORRECCIÓN a un comentario anterior de este archivo:
# Canberra NO es opcional acá. El mapa original (Fase 6 Parte 2, research
# de plasma-workspace) lo había anotado como Tier 4 / "find_package(Canberra)"
# sin REQUIRED -- cierto para plasma-workspace, pero knotifications (Tier
# 2b, mucho antes) lo pide REQUIRED de verdad en Linux normal: confirmado
# leyendo el if() real de su CMakeLists.txt --
# "if (NOT APPLE AND NOT ANDROID AND NOT WIN32 AND NOT HAIKU OR ...):
# find_package(Canberra REQUIRED)". Primer paquete Autotools de este
# script (Tier 0-2 fue CMake/Meson puro hasta ahora) -- mismo patrón
# "--host/--build, sin CC= explícito" ya usado en el resto del proyecto
# (el PATH ya prioriza ${LFS_TOOLS}/bin, autotools deriva el compilador
# del --host solo). Upstream real: la propia web de Lennart Poettering
# (0pointer.de) -- el proyecto está congelado en 0.30 desde hace años
# (confirmado contra el tracker de fuente de Debian, que también sigue en
# 0.30), no hay ningún fork "oficial" más nuevo. --enable-alsa (ya
# compilado en Fase 6 Parte 1) en vez de pulse/gstreamer (ninguno de los
# dos existe en este proyecto, Wayland+PipeWire no los necesita) --
# --disable-gtk/-gtk3 porque no compilamos GTK para nada.
step_libcanberra() {
    require_toolchain
    require_libltdl
    require_libvorbis
    log "libcanberra ${LIBCANBERRA_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBCANBERRA_MIRROR}/libcanberra-${LIBCANBERRA_VERSION}.tar.xz" \
          "libcanberra-${LIBCANBERRA_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libcanberra-${LIBCANBERRA_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libcanberra-${LIBCANBERRA_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libcanberra"

    local src="${LFS_BUILD}/libcanberra-${LIBCANBERRA_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static \
        --enable-alsa \
        --disable-oss \
        --disable-pulse \
        --disable-gstreamer \
        --disable-gtk \
        --disable-gtk3 \
        --disable-lynx \
        --disable-tdb

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libcanberra*.la' -delete 2>/dev/null || true

    log "libcanberra instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libcanberra() {
    log "Verificación: libcanberra.so + libcanberra.pc en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libcanberra.so" \
        "${LFS_SYSROOT}/usr/lib/pkgconfig/libcanberra.pc"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libcanberra en el sysroot"
    log "OK: libcanberra completo en el sysroot."
}

require_libcanberra() {
    [[ -e "${LFS_SYSROOT}/usr/lib/pkgconfig/libcanberra.pc" ]] \
        || die "no está libcanberra en el sysroot -- corré primero: scripts/build-kde.sh libcanberra"
}

# knotifications -- KF6Config REQUIRED + Canberra REQUIRED (arriba, nuevo).
step_knotifications() {
    require_libcanberra
    _kf6_cmake_build KNotifications knotifications
}
step_verify_knotifications() { _kf6_verify_lib KNotifications libKF6Notifications.so; }

# ------------------------------------------------------------------------------
# Tier 2c) -- dependen de Tier 2b. Mismo helper de siempre.
# ------------------------------------------------------------------------------

# BreezeIcons NATIVO -- agregado tras un error real (2026-09-04): el build
# CRUZADO rompió invocando su propio "generate-symbolic-dark"
# ("error while loading shared libraries: libQt6Core.so.6") -- ese binario
# se compila con el cross-toolchain y se INVOCA en el mismo build para
# generar los íconos oscuros/symbolic, mismo problema de fondo de siempre
# (Fase 6 Parte 2, mesa_clc y compañía). A diferencia de Qt6, acá no hace
# falta levantar un build nativo COMPLETO del framework con todo su
# contenido -- sólo -DINSTALL_HOST_TOOLS=ON (la variable real que gatea el
# install de generate-symbolic-dark/qrcAlias en su tools/CMakeLists.txt,
# ver comentario de KF6_NATIVE_BUILD/INSTALL más arriba). Necesita
# encontrar ECM (ya en el sysroot -- ECM es sólo módulos .cmake sin código
# compilado, sirve igual para un build nativo) y Qt6 nativo
# (QT6_NATIVE_INSTALL, Tier 1) vía CMAKE_PREFIX_PATH, sin ningún toolchain
# file (es un build normal para el propio contenedor).
step_breezeicons_native() {
    require_qtbase_native
    log "BreezeIcons ${KDE_VERSION} NATIVO (sólo generate-symbolic-dark/qrcAlias) — CMake"

    cd "${LFS_SOURCES}"
    fetch "${KDE_FRAMEWORKS_MIRROR}/breeze-icons-${KDE_VERSION}.tar.xz" \
          "breeze-icons-${KDE_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/breeze-icons-${KDE_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/breeze-icons-${KDE_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-breeze-icons-native"

    local src="${LFS_BUILD}/breeze-icons-${KDE_VERSION}"
    local bdir="${KF6_NATIVE_BUILD}/breeze-icons"
    rm -rf "${bdir}"

    # Build normal, completo (sin acotar targets a mano): a diferencia del
    # cruzado, ACÁ generate-symbolic-dark SÍ corre bien solo (es nativo de
    # verdad, mismo Qt6Core nativo, sin cross toolchain de por medio) --
    # generar el set de íconos completo es trabajo de sobra que después se
    # descarta (SKIP_INSTALL_ICONS=ON evita instalarlo), pero no rompe nada,
    # así que no hace falta la complejidad de acotar targets a mano como sí
    # hizo falta con mesa_clc en Fase 6 Parte 2.
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL};${LFS_SYSROOT}/usr" \
        -DCMAKE_INSTALL_PREFIX="${KF6_NATIVE_INSTALL}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DINSTALL_HOST_TOOLS=ON \
        -DSKIP_INSTALL_ICONS=ON

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "BreezeIcons NATIVO (host tools) instalado en ${KF6_NATIVE_INSTALL}"
}

step_verify_breezeicons_native() {
    log "Verificación: generate-symbolic-dark + qrcAlias NATIVOS"
    local ok=1
    local p
    for p in \
        "${KF6_NATIVE_INSTALL}/bin/generate-symbolic-dark" \
        "${KF6_NATIVE_INSTALL}/bin/qrcAlias"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de BreezeIcons nativo"
    log "OK: BreezeIcons NATIVO (host tools) completo."
}

require_breezeicons_native() {
    [[ -x "${KF6_NATIVE_INSTALL}/bin/generate-symbolic-dark" ]] \
        || die "no está BreezeIcons NATIVO en ${KF6_NATIVE_INSTALL} -- corré primero: scripts/build-kde.sh breezeicons-native"
}

# BreezeIcons CRUZADO -- prerequisito real de kiconthemes (KF6BreezeIcons
# REQUIRED en su CMakeLists.txt real), parte del mismo tren de KDE
# Frameworks 6.29.0 (no un paquete aparte). Sólo Qt Core/Gui + Python3
# (Interpreter, no Development -- no repite el problema de
# BUILD_PYTHON_BINDINGS) para la generación de íconos 24x24.
# -DKF6_HOST_TOOLING apunta al build nativo de arriba para
# generate-symbolic-dark/qrcAlias.
step_breezeicons() {
    require_breezeicons_native
    _kf6_cmake_build BreezeIcons breeze-icons \
        -DKF6_HOST_TOOLING="${KF6_NATIVE_INSTALL}/bin"
}
step_verify_breezeicons() {
    log "Verificación: BreezeIconsConfig.cmake + set de íconos en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/cmake/KF6BreezeIcons/KF6BreezeIconsConfig.cmake" \
        "${LFS_SYSROOT}/usr/share/icons/breeze/index.theme"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de BreezeIcons en el sysroot"
    log "OK: BreezeIcons completo en el sysroot."
}

# kiconthemes -- KF6Archive, KF6I18n, KF6WidgetsAddons, KF6ColorScheme
# (todos ya en el sysroot) + KF6BreezeIcons (arriba, nuevo).
step_kiconthemes() {
    require_kf6 BreezeIcons
    _kf6_cmake_build KIconThemes kiconthemes
}
step_verify_kiconthemes() { _kf6_verify_lib KIconThemes libKF6IconThemes.so; }

# kdeclarative -- KF6I18n, KF6Config, KF6GuiAddons, KF6WidgetsAddons.
step_kdeclarative() { _kf6_cmake_build KDeclarative kdeclarative; }
# kdeclarative NO produce una librería principal propia (confirmado con un
# find real sobre el sysroot) -- es básicamente un conjunto de plugins QML
# (draganddrop, kquickcontrolsaddons, kquickcontrols, graphicaleffects) +
# la librería aparte KF6CalendarEvents. Se verifica el paquete cmake real
# en vez de adivinar una lib que no existe.
step_verify_kdeclarative() {
    log "Verificación: KF6DeclarativeConfig.cmake + libKF6CalendarEvents.so en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/cmake/KF6Declarative/KF6DeclarativeConfig.cmake" \
        "${LFS_SYSROOT}/usr/lib/libKF6CalendarEvents.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de KDeclarative en el sysroot"
    log "OK: KDeclarative completo en el sysroot."
}

# krunner -- KF6Config, KF6CoreAddons, KF6I18n, KF6WindowSystem.
step_krunner() { _kf6_cmake_build KRunner krunner; }
step_verify_krunner() { _kf6_verify_lib KRunner libKF6Runner.so; }

# kxmlgui -- necesita KIconThemes (arriba) además de CoreAddons/ItemViews/
# Config/ConfigWidgets/GuiAddons/I18n/WidgetsAddons, todos ya en el
# sysroot.
step_kxmlgui() {
    require_kf6 IconThemes
    _kf6_cmake_build KXmlGui kxmlgui
}
step_verify_kxmlgui() { _kf6_verify_lib KXmlGui libKF6XmlGui.so; }

# kirigami -- prerequisito real de ksvg (pide KF6KirigamiPlatform,
# encontrado en la corrida real de ksvg -- no estaba en el mapa original).
# Kirigami en sí sólo depende de Qt6 (Core/Quick/Gui/Svg/QuickControls2/
# Concurrent/ShaderTools, todos ya en el sysroot) + OpenMP opcional -- CERO
# frameworks KF6 como dependencia, confirmado leyendo su CMakeLists.txt
# real. Parte del mismo tren 6.29.0.
step_kirigami() { _kf6_cmake_build Kirigami kirigami; }
step_verify_kirigami() {
    log "Verificación: KF6KirigamiPlatformConfig.cmake en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/cmake/KF6KirigamiPlatform/KF6KirigamiPlatformConfig.cmake"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: Kirigami completo en el sysroot."
}

# ksvg -- Qt Quick/Gui/Qml/Svg/QuickControls2 + KF6KirigamiPlatform (arriba,
# nuevo).
step_ksvg() {
    require_kf6 KirigamiPlatform
    _kf6_cmake_build KSvg ksvg
}
step_verify_ksvg() { _kf6_verify_lib KSvg libKF6Svg.so; }

# ------------------------------------------------------------------------------
# Tier 2d) -- las piezas pesadas. KF6KIO (el framework más grande de todo
# KF6) necesita 3 frameworks nuevos: KF6Solid, KF6Bookmarks, KF6JobWidgets
# (research 2026-09-04, contra los CMakeLists.txt reales de invent.kde.org
# -- ninguno estaba en el mapa original). Nombres de repo reales
# confirmados (no siempre coinciden con el nombre del framework): "solid"
# (sin prefijo "k"), "kbookmarks", "kjobwidgets".
# ------------------------------------------------------------------------------

# kbookmarks -- KF6Config, KF6CoreAddons, KF6WidgetsAddons (los 3 ya en el
# sysroot).
step_kbookmarks() { _kf6_cmake_build KBookmarks kbookmarks; }
step_verify_kbookmarks() { _kf6_verify_lib KBookmarks libKF6Bookmarks.so; }

# kjobwidgets -- KF6CoreAddons, KF6WidgetsAddons, KF6Notifications (los 3
# ya en el sysroot).
step_kjobwidgets() { _kf6_cmake_build KJobWidgets kjobwidgets; }
step_verify_kjobwidgets() { _kf6_verify_lib KJobWidgets libKF6JobWidgets.so; }

# solid -- FLEX/BISON (ya en el Dockerfile desde Fase 0, herramientas de
# host puras -- generan el parser de Predicate en tiempo de build, no hace
# falta nada cruzado) + LibMount/UDev en el bloque real de Linux (ambos ya
# compilados: LibMount de Fase 2/util-linux, UDev de Fase 2/systemd --
# confirmado con un find real de .so + headers antes de correr esto).
step_solid() { _kf6_cmake_build Solid solid; }
step_verify_solid() { _kf6_verify_lib Solid libKF6Solid.so; }

# ------------------------------------------------------------------------------
# KF6KIO -- el framework más grande de KF6. Dependencias reales confirmadas
# contra su CMakeLists.txt (invent.kde.org/frameworks/kio): KF6Config,
# KF6CoreAddons, KF6I18n, KF6Service, KF6Crash, KF6Solid, KF6WindowSystem,
# KF6Bookmarks, KF6ColorScheme, KF6Completion, KF6GuiAddons, KF6IconThemes,
# KF6ItemViews, KF6JobWidgets, KF6WidgetsAddons, KF6DBusAddons -- todas ya
# en el sysroot. WITH_X11=OFF y BUILD_PYTHON_BINDINGS=OFF ya salen del
# helper compartido. ACL es sólo RECOMMENDED (no REQUIRED) -- se omite sin
# agregar la librería. LibMount 2.26 REQUIRED en Linux -- ya confirmado
# presente (Fase 2/util-linux).
# ------------------------------------------------------------------------------
step_kio() { _kf6_cmake_build KIO kio; }
step_verify_kio() { _kf6_verify_lib KIO libKF6KIOCore.so; }

# ------------------------------------------------------------------------------
# knewstuff -- necesita un framework nuevo, KF6Attica ("Open Collaboration
# Services" -- protocolo real detrás de "Obtener Cosas Nuevas"). Attica en
# sí es el framework más liviano visto hasta ahora: sólo ECM + Qt6
# Core/Network (confirmado contra su CMakeLists.txt real en
# invent.kde.org/frameworks/attica), sin dependencias KF6 propias.
# ------------------------------------------------------------------------------

# attica -- sólo Qt6 Core/Network (ya en el sysroot). Nombre de librería
# real: KF6Attica (no "Attica" a secas).
step_attica() { _kf6_cmake_build Attica attica; }
step_verify_attica() { _kf6_verify_lib Attica libKF6Attica.so; }

# knewstuff -- KF6Archive, KF6Config, KF6CoreAddons, KF6I18n, KF6Package,
# KF6WidgetsAddons, KF6Attica (los 7 REQUIRED, todos ya en el sysroot tras
# el paso anterior). KF6Syndication (OPTIONAL, sólo para soporte OPDS) NO
# está compilado y se omite a propósito -- no hay nada en el mapa de este
# proyecto que lo necesite todavía. KF6Kirigami (OPTIONAL, para los
# componentes QML) sí está disponible y se detecta solo. Librería
# principal real: KF6NewStuffCore (confirmado contra
# src/core/CMakeLists.txt real -- "KNewStuff" el nombre del framework,
# "NewStuffCore" el nombre del target).
step_knewstuff() { _kf6_cmake_build KNewStuff knewstuff; }
step_verify_knewstuff() { _kf6_verify_lib KNewStuff libKF6NewStuffCore.so; }

# ==============================================================================
# Tier 3 -- librerías del "tren de Plasma" (versionado en PLASMA_VERSION,
# NO en KDE_VERSION -- ver env.sh). Se usa _plasma_cmake_build() en vez de
# _kf6_cmake_build(). Research 2026-09-04 contra los CMakeLists.txt reales
# de invent.kde.org/plasma/*, empezando por libplasma (el consumidor real
# que define el resto del mapa de este tier).
# ==============================================================================

# plasma-activities -- sólo ECM + Qt6 Core/DBus (confirmado contra su
# CMakeLists.txt real -- el framework más liviano de todo Tier 3). Target
# real: "PlasmaActivities" (namespace Plasma::Activities), sin prefijo KF6
# porque no es parte del tren de KDE Frameworks.
step_plasma_activities() { _plasma_cmake_build PlasmaActivities plasma-activities; }
step_verify_plasma_activities() { _kf6_verify_lib PlasmaActivities libPlasmaActivities.so; }

# plasma-activities-stats -- depende de PlasmaActivities (recién compilado)
# + KF6Config + Qt6 Core/DBus/Sql + Threads (todos ya en el sysroot; Qt6Sql
# ya viene con el driver QSQLite embebido desde qtbase, confirmado con un
# find real -- no hace falta libsqlite3 del sistema). Target real:
# "PlasmaActivitiesStats" (namespace Plasma::ActivitiesStats).
step_plasma_activities_stats() { _plasma_cmake_build PlasmaActivitiesStats plasma-activities-stats; }
step_verify_plasma_activities_stats() { _kf6_verify_lib PlasmaActivitiesStats libPlasmaActivitiesStats.so; }

# ------------------------------------------------------------------------------
# libxcb y su cadena de dependencias -- retrofit real 2026-09-04, agregado
# recién al toparse con un bug real de libplasma (ver comentario de versión
# en env.sh: blureffectwatcher_p.h incluye <xcb/xcb.h> sin guard, aunque el
# proyecto entero es Wayland puro y HAVE_X11 nunca se define). Se decidió
# junto con el usuario compilar un libxcb real y mínimo -- sólo para
# satisfacer el #include en tiempo de compilación, nunca se linkea de
# verdad en runtime (todo el código que lo usaría queda apagado por
# "#if HAVE_X11", indefinido acá) -- en vez de parchear código fuente de
# KDE. Orden real de compilación: xorgproto (headers puros) -> libXau +
# libXdmcp (autenticación X, paquetes chicos e independientes entre sí) ->
# xcb-proto (specs XML + módulo python "xcbgen", sin código compilado) ->
# libxcb. Mismo patrón Autotools (./configure --host=... --build=...) que
# el resto del proyecto (ver libogg/libvorbis más arriba).
# ------------------------------------------------------------------------------

# xorgproto -- sólo headers + archivos .pc, sin librería compilada.
step_xorgproto() {
    require_toolchain
    log "xorgproto ${XORGPROTO_VERSION} para ${LFS_TGT} — Autotools (headers)"

    cd "${LFS_SOURCES}"
    fetch "${XORGPROTO_MIRROR}/xorgproto-${XORGPROTO_VERSION}.tar.gz" \
          "xorgproto-${XORGPROTO_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/xorgproto-${XORGPROTO_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/xorgproto-${XORGPROTO_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-xorgproto"

    local src="${LFS_BUILD}/xorgproto-${XORGPROTO_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install

    log "xorgproto instalado en ${LFS_SYSROOT}/usr"
}

step_verify_xorgproto() {
    log "Verificación: xproto.pc en el sysroot"
    # xorgproto es el "merge" de ~40 protocolos legacy de X11 (bigreqsproto,
    # xextproto, etc.) -- NO genera un único "xorgproto.pc" combinado, cada
    # sub-protocolo mantiene su propio .pc real (confirmado con un find real
    # tras el install: "xproto.pc", "dmxproto.pc", etc. en /usr/share/pkgconfig).
    # Se verifica "xproto.pc" -- el más básico, el que en definitiva
    # necesitan libXau/libXdmcp/libxcb más adelante.
    local p="${LFS_SYSROOT}/usr/share/pkgconfig/xproto.pc"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: xorgproto completo en el sysroot."
}

# libXau -- necesita xorgproto (X11/Xmd.h vía x11proto, confirmado contra
# el Build-Depends real de Debian: "x11proto-dev").
step_libxau() {
    require_toolchain
    log "libXau ${LIBXAU_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${XORG_LIB_MIRROR}/libXau-${LIBXAU_VERSION}.tar.gz" \
          "libXau-${LIBXAU_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libXau-${LIBXAU_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libXau-${LIBXAU_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libxau"

    local src="${LFS_BUILD}/libXau-${LIBXAU_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libXau*.la' -delete 2>/dev/null || true

    log "libXau instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libxau() {
    log "Verificación: libXau.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libXau.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libXau completo en el sysroot."
}

# libXdmcp -- mismo prerequisito real que libXau (x11proto-dev).
step_libxdmcp() {
    require_toolchain
    log "libXdmcp ${LIBXDMCP_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${XORG_LIB_MIRROR}/libXdmcp-${LIBXDMCP_VERSION}.tar.xz" \
          "libXdmcp-${LIBXDMCP_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libXdmcp-${LIBXDMCP_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libXdmcp-${LIBXDMCP_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libxdmcp"

    local src="${LFS_BUILD}/libXdmcp-${LIBXDMCP_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libXdmcp*.la' -delete 2>/dev/null || true

    log "libXdmcp instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libxdmcp() {
    log "Verificación: libXdmcp.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libXdmcp.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libXdmcp completo en el sysroot."
}

# xcb-proto -- sólo specs XML + módulo python "xcbgen" (sin código
# compilado propio), necesario para que el ./configure de libxcb genere
# su código C real vía ese generador python.
step_xcbproto() {
    require_toolchain
    log "xcb-proto ${XCBPROTO_VERSION} para ${LFS_TGT} — Autotools (specs + python)"

    cd "${LFS_SOURCES}"
    fetch "${XCB_MIRROR}/xcb-proto-${XCBPROTO_VERSION}.tar.gz" \
          "xcb-proto-${XCBPROTO_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/xcb-proto-${XCBPROTO_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/xcb-proto-${XCBPROTO_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-xcbproto"

    local src="${LFS_BUILD}/xcb-proto-${XCBPROTO_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install

    log "xcb-proto instalado en ${LFS_SYSROOT}/usr"
}

step_verify_xcbproto() {
    log "Verificación: xcb-proto.pc en el sysroot"
    # Va a /usr/share/pkgconfig, no /usr/lib/pkgconfig (confirmado con un
    # find real tras el install) -- mismo patrón que xorgproto.
    local p="${LFS_SYSROOT}/usr/share/pkgconfig/xcb-proto.pc"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: xcb-proto completo en el sysroot."
}

# libxcb -- la pieza real que hace falta: libXau + libXdmcp + xcb-proto
# (los 3 recién compilados). Nunca se linkea de verdad en runtime en este
# proyecto (HAVE_X11 indefinido en todo lo que compile más adelante) --
# sólo satisface el #include sin guard de libplasma.
step_libxcb() {
    require_toolchain
    log "libxcb ${LIBXCB_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${XCB_MIRROR}/libxcb-${LIBXCB_VERSION}.tar.gz" \
          "libxcb-${LIBXCB_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libxcb-${LIBXCB_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libxcb-${LIBXCB_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libxcb"

    local src="${LFS_BUILD}/libxcb-${LIBXCB_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static \
        --without-doxygen

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libxcb*.la' -delete 2>/dev/null || true

    log "libxcb instalado en ${LFS_SYSROOT}/usr"
}

step_verify_libxcb() {
    log "Verificación: libxcb.so + xcb/xcb.h en el sysroot"
    local ok=1
    local p
    for p in "${LFS_SYSROOT}/usr/lib/libxcb.so" "${LFS_SYSROOT}/usr/include/xcb/xcb.h"; do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libxcb"
    log "OK: libxcb completo en el sysroot."
}

# libplasma -- la pieza central de Tier 3. Dependencias reales confirmadas
# contra su CMakeLists.txt (invent.kde.org/plasma/libplasma): ECM;
# Qt6 Quick/Gui/Qml/Svg/QuickControls2/DBus + Qt6GuiPrivate (todos ya en
# el sysroot -- QuickControls2 confirmado presente pese a no tener step
# propio, viene incluido en el build de qtdeclarative); KF6 Config,
# CoreAddons, GlobalAccel, GuiAddons, I18n, IconThemes, KIO, WindowSystem,
# Notifications, Package, KirigamiPlatform (parte del build de kirigami,
# confirmado con un find real -- no es un framework aparte), Svg (KSvg),
# ColorScheme -- las 13 ya en el sysroot; PlasmaWaylandProtocols >= 1.10.0
# (tenemos 1.21.0) + Qt6WaylandClient + wayland-client + wayland-protocols
# >= 1.46 (tenemos 1.49, confirmado con el .pc real) -- todas de fases
# anteriores; PlasmaActivities (recién compilado, ENABLE_ACTIVITIES=ON por
# default). Tarball real: "libplasma". Target real: "Plasma" (namespace
# Plasma::Plasma), NO "libplasma" ni "KF6Plasma".
#
# PRIMER PARCHE REAL DE TODO EL PROYECTO (2026-09-04, decidido junto con
# el usuario tras comparar alcance -- ver docs/PENDIENTES.md). Dos bugs
# reales de upstream en esta tag exacta (v6.7.4), mismo patrón los dos:
# un #include sin ningún guard de preprocesador, aunque el USO real del
# símbolo sí está guardeado (con "#if HAVE_X11" o un chequeo de runtime
# "KWindowSystem::isPlatformX11()"):
#   1. src/plasma/private/blureffectwatcher_p.h: "#include <xcb/xcb.h>"
#      sin guard -- resuelto agregando libxcb real y mínimo al sysroot
#      (ver step_libxcb() y la cadena xorgproto->libXau/libXdmcp->
#      xcb-proto->libxcb más arriba), nunca se linkea de verdad en runtime.
#   2. src/plasma/private/theme_p.cpp: "#include <KX11Extras>" sin guard.
#      A diferencia del caso anterior, la solución "agregar la librería
#      real" acá es DESPROPORCIONADA: KX11Extras sólo existe si KWindowSystem
#      se compila con KWINDOWSYSTEM_X11=ON, lo que exige Xlib real
#      (find_package(X11 REQUIRED)) + xcb-util + xcb-util-keysyms + icccm
#      (confirmado contra el CMakeLists.txt real de kwindowsystem) -- meter
#      Xlib de verdad en el sysroot choca de frente con el Pilar 5
#      ("Wayland puro", ver env.sh). Se decidió parchear la fuente en vez
#      de eso -- ver _patch_libplasma() más abajo: envuelve el #include y
#      los otros 2 usos de KX11Extras que NO estaban guardeados (uno ya
#      lo estaba en el propio upstream, con el mismo "#if HAVE_X11" que
#      usamos acá) con "#if HAVE_X11". HAVE_X11 se genera real y
#      correctamente como "#define HAVE_X11 0" en config-plasma.h
#      (confirmado leyendo el archivo generado real tras un intento de
#      build) -- no hace falta -Wno-undef ni nada especial, el macro
#      existe de verdad, sólo vale 0.
step_libplasma() { _plasma_cmake_build Plasma libplasma; }

# Parche real de theme_p.cpp -- ver el comentario largo arriba. Reemplazos
# exactos por texto (no un .patch con números de línea, para no depender
# de que el offset coincida byte a byte con la tag real) -- falla fuerte
# y explícito si algún ancla no aparece o no es única, en vez de aplicar
# a ciegas.
# Bug sistemático confirmado en 5 archivos de esta tag exacta (v6.7.4):
# includes de <KX11Extras>/<KWindowInfo> sin ningún guard de preprocesador,
# aunque el uso real siempre está detrás de un chequeo de RUNTIME
# ("KWindowSystem::isPlatformX11()") que en este proyecto (Wayland puro,
# HAVE_X11=0) siempre da falso -- el chequeo de runtime no alcanza para
# que el código compile sin la librería real. Decisión tomada con el
# usuario: parchear caso por caso (no headers stub, no agregar Xlib real)
# -- cada bloque se envuelve en "#if HAVE_X11 ... #endif" (mismo criterio
# que ya usa el propio upstream en otras partes de estos mismos archivos),
# preservando el comportamiento real de runtime para HAVE_X11=0 (que ya
# era, en la práctica, siempre el mismo que el "else" o directamente
# código muerto, confirmado leyendo cada call site real antes de tocarlo).
_patch_libplasma() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]

def patch_file(relpath, replacements):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            sys.exit(f"ERROR: ancla de patch no encontrada en {path}:\n{old!r}")
        if count > 1:
            sys.exit(f"ERROR: ancla de patch no es única en {path} ({count} veces):\n{old!r}")
        content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado ({len(replacements)} reemplazos)")

# src/plasma/private/theme_p.cpp -- 4 reemplazos (el #include + 3 usos:
# compositingActive, el connect() de compositingChanged, y el bloque
# entero de BlurEffectWatcher -- éste último descubierto en un segundo
# intento de build real: BlurEffectWatcher sólo implementa su método
# virtual puro heredado, QAbstractNativeEventFilter::nativeEventFilter,
# adentro de un "#if HAVE_X11" en su propio header -- con HAVE_X11=0 queda
# una clase abstracta, y el "new BlurEffectWatcher()" de este archivo NO
# estaba guardeado: "invalid new-expression of abstract class type" real).
patch_file("src/plasma/private/theme_p.cpp", [
    (
        "#include <KX11Extras>\n",
        "#if HAVE_X11\n#include <KX11Extras>\n#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        compositingActive = KX11Extras::self()->compositingActive();\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        compositingActive = KX11Extras::self()->compositingActive();\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        connect(KX11Extras::self(), &KX11Extras::compositingChanged, selectorsUpdateTimer, qOverload<>(&QTimer::start));\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        connect(KX11Extras::self(), &KX11Extras::compositingChanged, selectorsUpdateTimer, qOverload<>(&QTimer::start));\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (QPixmap::defaultDepth() > 8) {\n"
        "        // watch for background contrast effect property changes as well\n"
        "        if (!s_blurEffectWatcher) {\n"
        "            s_blurEffectWatcher = new BlurEffectWatcher();\n"
        "        }\n"
        "\n"
        "        QObject::connect(s_blurEffectWatcher, &BlurEffectWatcher::effectChanged, selectorsUpdateTimer, qOverload<>(&QTimer::start));\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (QPixmap::defaultDepth() > 8) {\n"
        "        // watch for background contrast effect property changes as well\n"
        "        if (!s_blurEffectWatcher) {\n"
        "            s_blurEffectWatcher = new BlurEffectWatcher();\n"
        "        }\n"
        "\n"
        "        QObject::connect(s_blurEffectWatcher, &BlurEffectWatcher::effectChanged, selectorsUpdateTimer, qOverload<>(&QTimer::start));\n"
        "    }\n"
        "#endif\n",
    ),
])

# src/plasmaquick/plasmawindow.cpp -- el #include + 2 usos. El segundo
# (compositingActive en handleFrameChanged) equivale, en runtime real, a
# "siempre setMask(QRegion())" cuando HAVE_X11=0 (el "!isPlatformX11()"
# ya da true solo por estar en Wayland, el OR corta ahí) -- se preserva
# ese comportamiento real con un #else explícito en vez de borrar la rama.
# A diferencia de dialog.cpp (mismo directorio, mismo target), este
# archivo NO incluye "config-plasma.h" todavía -- sin él, HAVE_X11 no
# está definido y "-Werror=undef" (real, en los flags de compilación)
# rompe el build. Se agrega el include real que dialog.cpp ya usa con
# éxito (mismo target PlasmaQuick, mismo include path).
patch_file("src/plasmaquick/plasmawindow.cpp", [
    (
        "#include <KWindowEffects>\n#include <KWindowSystem>\n#include <KX11Extras>\n",
        "#include <KWindowEffects>\n#include <KWindowSystem>\n\n#include \"config-plasma.h\"\n#if HAVE_X11\n#include <KX11Extras>\n#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (!KWindowSystem::isPlatformX11() || KX11Extras::compositingActive()) {\n"
        "        q->setMask(QRegion());\n"
        "    } else {\n"
        "        q->setMask(mask);\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (!KWindowSystem::isPlatformX11() || KX11Extras::compositingActive()) {\n"
        "        q->setMask(QRegion());\n"
        "    } else {\n"
        "        q->setMask(mask);\n"
        "    }\n"
        "#else\n"
        "    q->setMask(QRegion());\n"
        "#endif\n",
    ),
])

# src/plasmaquick/appletpopup.cpp -- el #include + 1 uso. El "else" YA es
# el camino Wayland real (PlasmaShellWaylandIntegration) -- con HAVE_X11=0
# ese "else" es lo único que puede ejecutarse, se preserva tal cual.
# Mismo problema real que plasmawindow.cpp: no incluye "config-plasma.h"
# todavía, hace falta agregarlo para que HAVE_X11 exista de verdad
# (-Werror=undef real en los flags de compilación).
patch_file("src/plasmaquick/appletpopup.cpp", [
    (
        "#include <KConfigGroup>\n#include <KWindowSystem>\n#include <KX11Extras>\n",
        "#include <KConfigGroup>\n#include <KWindowSystem>\n\n#include \"config-plasma.h\"\n#if HAVE_X11\n#include <KX11Extras>\n#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setType(winId(), NET::AppletPopup);\n"
        "    } else {\n"
        "        PlasmaShellWaylandIntegration::get(this)->setRole(QtWayland::org_kde_plasma_surface::role::role_appletpopup);\n"
        "        PlasmaShellWaylandIntegration::get(this)->setTakesFocus(true);\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setType(winId(), NET::AppletPopup);\n"
        "    } else {\n"
        "        PlasmaShellWaylandIntegration::get(this)->setRole(QtWayland::org_kde_plasma_surface::role::role_appletpopup);\n"
        "        PlasmaShellWaylandIntegration::get(this)->setTakesFocus(true);\n"
        "    }\n"
        "#else\n"
        "    PlasmaShellWaylandIntegration::get(this)->setRole(QtWayland::org_kde_plasma_surface::role::role_appletpopup);\n"
        "    PlasmaShellWaylandIntegration::get(this)->setTakesFocus(true);\n"
        "#endif\n",
    ),
])

# src/plasmaquick/dialog.cpp -- el más grande: 2 includes + 5 usos. Todos
# los "if (KWindowSystem::isPlatformX11())" puros (sin "!" ni "||") son
# código muerto entero con HAVE_X11=0 -- se envuelven tal cual, sin else.
# El de "compositingActive" (mismo patrón que plasmawindow.cpp) sí
# necesita el #else explícito para preservar el comportamiento real.
patch_file("src/plasmaquick/dialog.cpp", [
    (
        "#include <KWindowInfo>\n",
        "#if HAVE_X11\n#include <KWindowInfo>\n#endif\n",
    ),
    (
        "#include <KX11Extras>\n",
        "#if HAVE_X11\n#include <KX11Extras>\n#endif\n",
    ),
    (
        "        if (!KWindowSystem::isPlatformX11() || KX11Extras::compositingActive()) {\n"
        "            if (hasMask) {\n"
        "                hasMask = false;\n"
        "                q->setMask(QRegion());\n"
        "            }\n"
        "        } else {\n"
        "            hasMask = true;\n"
        "            q->setMask(dialogBackground->mask());\n"
        "        }\n",
        "#if HAVE_X11\n"
        "        if (!KWindowSystem::isPlatformX11() || KX11Extras::compositingActive()) {\n"
        "            if (hasMask) {\n"
        "                hasMask = false;\n"
        "                q->setMask(QRegion());\n"
        "            }\n"
        "        } else {\n"
        "            hasMask = true;\n"
        "            q->setMask(dialogBackground->mask());\n"
        "        }\n"
        "#else\n"
        "        if (hasMask) {\n"
        "            hasMask = false;\n"
        "            q->setMask(QRegion());\n"
        "        }\n"
        "#endif\n",
    ),
    (
        "    if (!wmType && type != Dialog::Normal && KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setType(q->winId(), static_cast<NET::WindowType>(type));\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (!wmType && type != Dialog::Normal && KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setType(q->winId(), static_cast<NET::WindowType>(type));\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        if (type == Dialog::Dock || type == Dialog::Notification || type == Dialog::OnScreenDisplay || type == Dialog::CriticalNotification) {\n"
        "            KX11Extras::setOnAllDesktops(q->winId(), true);\n"
        "        } else {\n"
        "            KX11Extras::setOnAllDesktops(q->winId(), false);\n"
        "        }\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        if (type == Dialog::Dock || type == Dialog::Notification || type == Dialog::OnScreenDisplay || type == Dialog::CriticalNotification) {\n"
        "            KX11Extras::setOnAllDesktops(q->winId(), true);\n"
        "        } else {\n"
        "            KX11Extras::setOnAllDesktops(q->winId(), false);\n"
        "        }\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        // on X11 we also consider windows with the type Dock\n"
        "        const KWindowInfo winInfo(item->window()->winId(), NET::WMWindowType);\n"
        "        outsideParentWindow = outsideParentWindow || (winInfo.windowType(NET::AllTypesMask) == NET::Dock && item->window()->mask().isNull());\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        // on X11 we also consider windows with the type Dock\n"
        "        const KWindowInfo winInfo(item->window()->winId(), NET::WMWindowType);\n"
        "        outsideParentWindow = outsideParentWindow || (winInfo.windowType(NET::AllTypesMask) == NET::Dock && item->window()->mask().isNull());\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "    }\n"
        "    QQuickWindow::showEvent(event);\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "    }\n"
        "#endif\n"
        "    QQuickWindow::showEvent(event);\n",
    ),
])

# src/declarativeimports/core/windowthumbnail.cpp -- el #include + 2 usos.
# El primero es código muerto entero (AND con isPlatformX11()). El
# segundo YA tiene un "else" real (icono de fallback "plasma") que es el
# único camino posible con HAVE_X11=0 -- se preserva ese fallback.
# Este archivo tampoco define HAVE_X11 todavía -- a diferencia de
# plasmawindow.cpp/appletpopup.cpp (mismo target que dialog.cpp), éste
# vive en declarativeimports/core, el mismo directorio real donde CMake
# genera "config-x11.h" (confirmado con un find real tras un intento de
# build) -- se agrega ese include, no "config-plasma.h".
patch_file("src/declarativeimports/core/windowthumbnail.cpp", [
    (
        "#include \"windowthumbnail.h\"\n// KF5\n#include <KWindowSystem>\n#include <KX11Extras>\n",
        "#include \"windowthumbnail.h\"\n\n#include \"config-x11.h\"\n// KF5\n#include <KWindowSystem>\n#if HAVE_X11\n#include <KX11Extras>\n#endif\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11() && !KX11Extras::self()->hasWId(winId)) {\n"
        "        // invalid Id, don't updated\n"
        "        return;\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11() && !KX11Extras::self()->hasWId(winId)) {\n"
        "        // invalid Id, don't updated\n"
        "        return;\n"
        "    }\n"
        "#endif\n",
    ),
    (
        "    QIcon icon;\n"
        "    if (KWindowSystem::isPlatformX11() && KX11Extras::self()->hasWId(m_winId)) {\n"
        "        icon = KX11Extras::self()->icon(m_winId, boundingRect().width(), boundingRect().height());\n"
        "    } else {\n"
        "        // fallback to plasma icon\n"
        "        icon = QIcon::fromTheme(QStringLiteral(\"plasma\"));\n"
        "    }\n",
        "    QIcon icon;\n"
        "#if HAVE_X11\n"
        "    if (KWindowSystem::isPlatformX11() && KX11Extras::self()->hasWId(m_winId)) {\n"
        "        icon = KX11Extras::self()->icon(m_winId, boundingRect().width(), boundingRect().height());\n"
        "    } else {\n"
        "        // fallback to plasma icon\n"
        "        icon = QIcon::fromTheme(QStringLiteral(\"plasma\"));\n"
        "    }\n"
        "#else\n"
        "    icon = QIcon::fromTheme(QStringLiteral(\"plasma\"));\n"
        "#endif\n",
    ),
])

print("OK: los 5 archivos de libplasma parcheados (KX11Extras/KWindowInfo guardeados con HAVE_X11)")
PYEOF
}
step_verify_libplasma() { _kf6_verify_lib Plasma libPlasma.so; }

# kwayland -- la KWayland de PLASMA (namespace Plasma::), distinta de
# Qt6WaylandClient (Tier 1) y de KF6's KWindowSystem. Dependencias reales
# confirmadas contra su CMakeLists.txt (invent.kde.org/plasma/kwayland):
# ECM; Qt6Gui/Qt6Concurrent/Qt6WaylandClient + sus variantes *Private
# (todas ya en el sysroot); Wayland Client >= 1.26 (tenemos 1.26.0 justo
# al límite, confirmado con el .pc real) + WaylandScanner (nativo, Fase 6
# Parte 1) + WaylandProtocols >= 1.15 (tenemos 1.49); EGL (Mesa); y
# PlasmaWaylandProtocols >= 1.22.0 -- ESTE dato hizo falta subir el pin
# del proyecto (ver env.sh, era 1.21.0, sólo alcanzaba para kwin). Target
# real: "KWaylandClient" (namespace Plasma::), confirmado contra
# src/client/CMakeLists.txt real -- NO "KWayland" a secas.
step_kwayland() { _plasma_cmake_build KWayland kwayland; }
step_verify_kwayland() { _kf6_verify_lib KWayland libKWaylandClient.so; }

# layer-shell-qt -- integra el protocolo Wayland wlr-layer-shell (paneles,
# barras, overlays por fuera del modelo de ventanas normal) con Qt6.
# Dependencias reales confirmadas contra su CMakeLists.txt
# (invent.kde.org/plasma/layer-shell-qt): ECM; Qt6 WaylandClient/Qml +
# Qt6WaylandClientPrivate; WaylandScanner (nativo); Wayland Client Y
# Server >= 1.3 (tenemos 1.26.0 de los dos, confirmado -- Server no se
# había usado hasta ahora en Tier 3, pero ya estaba compilado desde Fase
# 6 Parte 1); WaylandProtocols; xkbcommon (vía pkg-config, ya en el
# sysroot). Target real: "LayerShellQtInterface" (confirmado contra
# src/CMakeLists.txt real -- "layer-shell" a secas es sólo el plugin QPA
# interno, no la librería pública).
step_layer_shell_qt() { _plasma_cmake_build LayerShellQtInterface layer-shell-qt; }
step_verify_layer_shell_qt() { _kf6_verify_lib LayerShellQtInterface libLayerShellQtInterface.so; }

# kirigami-addons -- versionado APARTE tanto del tren de Plasma como de
# KDE Frameworks (su propio release cycle, ver env.sh) -- no encaja en
# ninguno de los dos helpers compartidos, función propia. Dependencias
# reales confirmadas contra su CMakeLists.txt
# (invent.kde.org/libraries/kirigami-addons, repo real bajo "libraries/",
# NO "frameworks/" donde 404 primero): ECM; Qt6 Core/Quick/QuickControls2/
# QuickEffects; KF6 Kirigami/I18n/Config/CoreAddons/GuiAddons/ColorScheme/
# Crash/IconThemes/GlobalAccel (todas ya en el sysroot). Es
# mayormente QML puro (formcard, delegates, statefulapp, etc.) -- no hay
# un único "libKirigamiAddons.so" real, se verifica contra el paquete
# cmake en vez de una lib inexistente.
step_kirigami_addons() {
    require_toolchain
    require_ecm
    log "KirigamiAddons ${KIRIGAMI_ADDONS_VERSION} para ${LFS_TGT} — CMake+ECM"

    cd "${LFS_SOURCES}"
    fetch "${KIRIGAMI_ADDONS_MIRROR}/kirigami-addons-${KIRIGAMI_ADDONS_VERSION}.tar.xz" \
          "kirigami-addons-${KIRIGAMI_ADDONS_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/kirigami-addons-${KIRIGAMI_ADDONS_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/kirigami-addons-${KIRIGAMI_ADDONS_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-kirigami-addons-${KIRIGAMI_ADDONS_VERSION}"

    local src="${LFS_BUILD}/kirigami-addons-${KIRIGAMI_ADDONS_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_PYTHON_BINDINGS=OFF \
        -DWITH_X11=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "KirigamiAddons instalado en ${LFS_SYSROOT}/usr"
}

# libkscreen -- tarball real "libkscreen", target real "KF6Screen"
# (namespace Plasma::Screen, EXPORT_NAME "Screen" -- confirmado contra
# src/CMakeLists.txt real). 100% Wayland, sin ninguna opción de X11/XRandR
# (confirmado contra el CMakeLists.txt real -- ni siquiera existe un
# WITH_X11 acá). Dependencias reales: ECM; Qt6 Core/DBus/Gui/Test/
# WaylandClient + Qt6GuiPrivate; WaylandScanner (nativo); Wayland Client
# >= 1.24 (tenemos 1.26.0); PlasmaWaylandProtocols >= 1.21 (tenemos
# 1.22.0, después del bump real de KWayland) -- todas ya en el sysroot.
step_libkscreen() { _plasma_cmake_build KF6Screen libkscreen; }
step_verify_libkscreen() { _kf6_verify_lib KF6Screen libKF6Screen.so; }

# Mismo patrón otra vez (tercera vez en el proyecto, después de libplasma),
# pero esta vez NO es KDE -- es Qt: "src/libdpms/dpms.cpp" incluye sin
# guard "QtGui/private/qtx11extras_p.h", un header PRIVADO de Qt6Gui que
# sólo existe si Qt se compiló con el plugin de plataforma xcb
# (-DFEATURE_xcb=ON) -- este proyecto lo compiló con -DFEATURE_xcb=OFF a
# propósito (Wayland puro). El uso real está detrás de un runtime-check
# real ("QX11Info::isPlatformX11()"), pero el include no. Además,
# "xcbdpmshelper.cpp" (implementación DPMS vía XCB, hermano de
# "waylanddpmshelper.cpp") es 100% código X11 -- ni siquiera tiene sentido
# guardearlo con un #if, hay que sacarlo directo del target_sources() del
# CMakeLists.txt real de ese subdirectorio (confirmado: linkea
# XCB::XCB/XCB::DPMS/XCB::RANDR sin ningún guard tampoco). A diferencia
# del caso de KX11Extras, acá NO hace falta agregar ninguna librería real
# nueva -- ya tenemos libxcb-dpms/libxcb-randr compilados (parte del
# libxcb mínimo que ya se agregó para libplasma), el problema es
# puramente el header privado de Qt, que no existe sin el plugin xcb real
# (que sí necesitaría bastante más: libxcb-cursor, xkbcommon-x11, etc. --
# mismo tipo de escalada que se evitó con KWindowSystem). Se saca el
# archivo X11 entero del build y se deja sólo el camino Wayland real.
_patch_libkscreen() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]

def patch_file(relpath, replacements):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            sys.exit(f"ERROR: ancla de patch no encontrada en {path}:\n{old!r}")
        if count > 1:
            sys.exit(f"ERROR: ancla de patch no es única en {path} ({count} veces):\n{old!r}")
        content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado ({len(replacements)} reemplazos)")

patch_file("src/libdpms/CMakeLists.txt", [
    (
        "target_sources(KF6ScreenDpms PRIVATE dpms.cpp dpms.h abstractdpmshelper.cpp waylanddpmshelper.cpp xcbdpmshelper.cpp waylanddpmshelper.cpp)\n",
        "target_sources(KF6ScreenDpms PRIVATE dpms.cpp dpms.h abstractdpmshelper.cpp waylanddpmshelper.cpp waylanddpmshelper.cpp)\n",
    ),
    (
        "target_link_libraries(KF6ScreenDpms PUBLIC Qt::Gui\n"
        "                                    PRIVATE XCB::XCB XCB::DPMS XCB::RANDR\n"
        "                                            Qt::GuiPrivate Qt::WaylandClient Wayland::Client\n"
        ")\n",
        "target_link_libraries(KF6ScreenDpms PUBLIC Qt::Gui\n"
        "                                    PRIVATE Qt::GuiPrivate Qt::WaylandClient Wayland::Client\n"
        ")\n",
    ),
])

patch_file("src/libdpms/dpms.cpp", [
    (
        "#include \"xcbdpmshelper_p.h\"\n"
        "\n"
        "#include <QGuiApplication>\n"
        "#include <QtGui/private/qtx11extras_p.h>\n",
        "#include <QGuiApplication>\n",
    ),
    (
        "    if (QX11Info::isPlatformX11()) {\n"
        "        m_helper.reset(new XcbDpmsHelper);\n"
        "    } else if (QGuiApplication::platformName().startsWith(QLatin1String(\"wayland\"), Qt::CaseInsensitive)) {\n"
        "        m_helper.reset(new WaylandDpmsHelper);\n"
        "    } else {\n",
        "    if (QGuiApplication::platformName().startsWith(QLatin1String(\"wayland\"), Qt::CaseInsensitive)) {\n"
        "        m_helper.reset(new WaylandDpmsHelper);\n"
        "    } else {\n",
    ),
])

# Segundo archivo con el mismo bug, encontrado en el intento SIGUIENTE
# tras arreglar libdpms: "src/backendmanager.cpp" -- elige qué backend de
# verdad usar (XRandR vs KWayland) según la plataforma. Mismo patrón:
# include sin guard, uso real detrás de un runtime-check real. Acá el
# branch X11 completo se saca (no sólo el include) porque nunca puede
# ganar en este proyecto -- "XRandR" como backend ni siquiera está
# compilado (era el propósito de xcbdpmshelper.cpp que ya sacamos).
patch_file("src/backendmanager.cpp", [
    (
        "#include <QThread>\n"
        "#include <QtGui/private/qtx11extras_p.h>\n",
        "#include <QThread>\n",
    ),
    (
        "    } else {\n"
        "        if (QX11Info::isPlatformX11()) {\n"
        "            backendFilter = QStringLiteral(\"XRandR\");\n"
        "        } else if (QGuiApplication::platformName().startsWith(QLatin1String(\"wayland\"))) {\n"
        "            backendFilter = QStringLiteral(\"KWayland\");\n"
        "        }\n"
        "    }\n",
        "    } else {\n"
        "        if (QGuiApplication::platformName().startsWith(QLatin1String(\"wayland\"))) {\n"
        "            backendFilter = QStringLiteral(\"KWayland\");\n"
        "        }\n"
        "    }\n",
    ),
])

# Tercer hallazgo, distinto a los dos anteriores: "backends/xrandr/" es un
# TARGET CMake entero (KSC_XRandR), 100% implementación X11/XCB real --
# no un archivo con include-sin-guard, sino un backend completo que
# upstream SÍ gatea correctamente con "if(${XCB_RANDR_FOUND})" (real,
# confirmado contra backends/CMakeLists.txt). El problema es indirecto:
# este proyecto SÍ tiene libxcb-randr compilado (parte del libxcb mínimo
# agregado para libplasma), así que XCB_RANDR_FOUND da verdadero y CMake
# entra a compilar un backend que después falla por el mismo header
# privado de Qt de siempre. Nunca se va a poder seleccionar en runtime de
# todos modos (ya sacamos "XRandR" de backendFilter en backendmanager.cpp)
# así que no tiene sentido ni intentar compilarlo -- se saca el
# add_subdirectory(xrandr) entero, sin importar XCB_RANDR_FOUND.
patch_file("backends/CMakeLists.txt", [
    (
        "if(${XCB_RANDR_FOUND})\n"
        "    message(STATUS \"Will build xrandr backend.\")\n"
        "    add_subdirectory(xrandr)\n"
        "else()\n"
        "    message(STATUS \"Not building xrandr backend, no XCB_RANDR_FOUND set.\")\n"
        "endif()\n",
        "message(STATUS \"xrandr backend deshabilitado a proposito (LINSI-OS es Wayland puro)\")\n",
    ),
])

print("OK: libkscreen parcheado (libdpms sin X11, backendmanager.cpp sin X11, backend xrandr deshabilitado)")
PYEOF
}

# kdecoration -- REQUIRED real por kwin (find_package(KDecoration3 ...
# REQUIRED), confirmado contra el CMakeLists.txt real de kwin). API que
# implementan los temas de decoración de ventanas (Breeze, Aurorae). Muy
# liviano: sólo ECM + Qt6 Core/Gui/Test + KF6I18n (todas ya en el
# sysroot). Target real: "kdecorations3" (namespace KDecoration3::,
# EXPORT_NAME "KDecoration") -- confirmado contra src/CMakeLists.txt
# real. Tarball real: "kdecoration" (sin el "3", confirmado en el listado
# de download.kde.org/stable/plasma/6.7.4/).
step_kdecoration() { _plasma_cmake_build KDecoration3 kdecoration; }
step_verify_kdecoration() { _kf6_verify_lib KDecoration3 libkdecorations3.so; }

# KScreenLocker -- mismo bug sistémico de X11 sin guard de siempre, pero
# repartido en 3 archivos reales (ksldapp.cpp, globalaccel.cpp,
# greeter/greeterapp.cpp) en vez de 1-2 como en libkscreen -- confirmado
# leyendo el CMakeLists.txt REAL del tarball 6.7.4 (no el de master en
# invent.kde.org, que ya no tiene ningún check de X11 -- upstream lo
# sacó recién después de esta versión). Criterio ya aprobado por Juani
# para este mismo tipo de caso (KX11Extras, libkscreen): sacar el código
# X11 muerto en vez de compilar Xlib/xcb-util real, ya que TODO uso real
# está detrás de un runtime-check (m_isX11/KWindowSystem::isPlatformX11())
# que siempre da false en un release Wayland puro. Confirmado por escrito
# con Juani antes de tocar esto por ser el componente de bloqueo de
# pantalla (área de seguridad) y por ser bastante más grande que los
# parches anteriores.
_patch_kscreenlocker() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]

def patch_file(relpath, replacements):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            sys.exit(f"ERROR: ancla de patch no encontrada en {path}:\n{old!r}")
        if count > 1:
            sys.exit(f"ERROR: ancla de patch no es única en {path} ({count} veces):\n{old!r}")
        content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado ({len(replacements)} reemplazos)")

# CMakeLists.txt (raíz): find_package(X11)/find_package(XCB ... REQUIRED
# COMPONENTS XCB KEYSYMS UTIL XTEST) exigían xcb-util/xcb-util-keysyms/X11
# reales que no tenemos (y no vamos a construir). x11locker.cpp/.h se
# sacan de ksld_SRCS -- implementan el backend X11 completo del locker,
# reemplazado en runtime por WaylandLocker cuando no hay X11 (siempre).
patch_file("CMakeLists.txt", [
    (
        "find_package(X11)\n"
        "set_package_properties(X11 PROPERTIES DESCRIPTION \"X11 libraries\"\n"
        "                        URL \"https://www.x.org\"\n"
        "                        TYPE REQUIRED\n"
        "                        PURPOSE \"Required for building the X11 based workspace\")\n"
        "\n"
        "find_package(XCB MODULE REQUIRED COMPONENTS XCB KEYSYMS UTIL XTEST)\n"
        "set_package_properties(XCB PROPERTIES TYPE REQUIRED)\n"
        "add_feature_info(\"XInput\" X11_Xinput_FOUND \"Required for grabbing XInput2 devices in the screen locker\")\n"
        "\n",
        "# X11 real removido a proposito -- LINSI-OS es Wayland puro (ver\n"
        "# _patch_kscreenlocker() en build-kde.sh). x11locker.cpp/.h sacados\n"
        "# de ksld_SRCS mas abajo. Se mantiene sólo el componente XCB (núcleo\n"
        "# de libxcb, ya en el sysroot) porque el target CMake XCB::XCB se usa\n"
        "# de verdad en el ksld_SRCS de doUnlock() -- KEYSYMS/UTIL/XTEST\n"
        "# (paquetes xcb-util/xcb-util-keysyms aparte, no construidos) se\n"
        "# sacan de los componentes requeridos.\n"
        "find_package(XCB MODULE REQUIRED COMPONENTS XCB)\n"
        "\n",
    ),
    (
        "   x11locker.cpp\n",
        "",
    ),
    (
        "   x11locker.h\n",
        "",
    ),
    (
        "   KF6::WindowSystem\n"
        "   X11::X11\n"
        "   XCB::XCB\n"
        "   XCB::KEYSYMS\n"
        "   Wayland::Server\n",
        "   KF6::WindowSystem\n"
        "   XCB::XCB\n"
        "   Wayland::Server\n",
    ),
])

# ksldapp.cpp: constructor fuerza m_isX11=false (nunca se detecta X11
# real); initializeX11() (XGetScreenSaver/XSetScreenSaver) se elimina
# entera junto con su único call site; cleanUp() tenía una llamada a
# XSetScreenSaver SIN ningún guard de m_isX11 (bug real aparte); todo el
# grab real (XSync/XGrabKeyboard/XGrabPointer/XIGrabDevice) en
# establishGrab()+grabKeyboard()+grabMouse()+XServerGrabber se elimina
# (doUnlock() usa xcb core puro -- xcb_ungrab_keyboard/pointer -- y ESE
# sí compila fino con nuestro libxcb mínimo, no se toca); showLockWindow()
# pierde el X11Locker (clase eliminada) y un XSync final.
patch_file("ksldapp.cpp", [
    (
        "#include \"waylandlocker.h\"\n"
        "#include \"x11locker.h\"\n",
        "#include \"waylandlocker.h\"\n",
    ),
    (
        "// X11\n"
        "#include \"x11info.h\"\n"
        "#include <X11/Xlib.h>\n"
        "#include <xcb/xcb.h>\n",
        "// X11 (Xlib real removido a proposito -- Wayland puro, ver\n"
        "// _patch_kscreenlocker()). xcb.h se mantiene: doUnlock() usa xcb\n"
        "// core (xcb_ungrab_keyboard/xcb_ungrab_pointer), no Xlib.\n"
        "#include <xcb/xcb.h>\n",
    ),
    (
        "    m_isX11 = X11Info::isPlatformX11();\n",
        "    m_isX11 = false; // Xlib real removido -- Wayland puro (_patch_kscreenlocker())\n",
    ),
    (
        "    delete m_lockWindow;\n"
        "\n"
        "    // Restore X screensaver parameters\n"
        "    XSetScreenSaver(X11Info::display(), s_XTimeout, s_XInterval, s_XBlanking, s_XExposures);\n"
        "}\n",
        "    delete m_lockWindow;\n"
        "}\n",
    ),
    (
        "void KSldApp::initializeX11()\n"
        "{\n"
        "    qCDebug(KSCREENLOCKER) << \"Initializing X11\";\n"
        "\n"
        "    m_hasXInput2 = hasXInput();\n"
        "    // Save X screensaver parameters\n"
        "    XGetScreenSaver(X11Info::display(), &s_XTimeout, &s_XInterval, &s_XBlanking, &s_XExposures);\n"
        "    // And disable it. The internal X screensaver is not used at all, but we use its\n"
        "    // internal idle timer (and it is also used by DPMS support in X). This timer must not\n"
        "    // be altered by this code, since e.g. resetting the counter after activating our\n"
        "    // screensaver would prevent DPMS from activating. We use the timer merely to detect\n"
        "    // user activity.\n"
        "    XSetScreenSaver(X11Info::display(), 0, s_XInterval, s_XBlanking, s_XExposures);\n"
        "}\n"
        "\n"
        "void KSldApp::initialize()\n"
        "{\n"
        "    qCDebug(KSCREENLOCKER) << \"Initializing\";\n"
        "\n"
        "    m_requirePassword = KScreenSaverSettings::requirePassword();\n"
        "\n"
        "    if (m_isX11) {\n"
        "        initializeX11();\n"
        "    }\n",
        "void KSldApp::initialize()\n"
        "{\n"
        "    qCDebug(KSCREENLOCKER) << \"Initializing\";\n"
        "\n"
        "    m_requirePassword = KScreenSaverSettings::requirePassword();\n",
    ),
    (
        "/*\n"
        " * Forward declarations:\n"
        " * Only called from KSldApp::establishGrab(). Using from somewhere else is incorrect usage!\n"
        " **/\n"
        "static bool grabKeyboard();\n"
        "static bool grabMouse();\n"
        "\n"
        "class XServerGrabber\n"
        "{\n"
        "public:\n"
        "    XServerGrabber()\n"
        "    {\n"
        "        xcb_grab_server(X11Info::connection());\n"
        "    }\n"
        "    ~XServerGrabber()\n"
        "    {\n"
        "        xcb_ungrab_server(X11Info::connection());\n"
        "        xcb_flush(X11Info::connection());\n"
        "    }\n"
        "};\n"
        "\n",
        "",
    ),
    (
        "    XSync(X11Info::display(), False);\n"
        "    XServerGrabber serverGrabber;\n"
        "    if (!grabKeyboard()) {\n"
        "        return false;\n"
        "    }\n"
        "\n"
        "    if (!grabMouse()) {\n"
        "        XUngrabKeyboard(X11Info::display(), CurrentTime);\n"
        "        XFlush(X11Info::display());\n"
        "        return false;\n"
        "    }\n"
        "\n"
        "#if X11_Xinput_FOUND\n"
        "    if (m_hasXInput2) {\n"
        "        // get all devices\n"
        "        Display *dpy = X11Info::display();\n"
        "        int numMasters;\n"
        "        XIDeviceInfo *masters = XIQueryDevice(dpy, XIAllMasterDevices, &numMasters);\n"
        "        bool success = true;\n"
        "        for (int i = 0; i < numMasters; ++i) {\n"
        "            // ignoring core pointer and core keyboard as we already grabbed them\n"
        "            if (qstrcmp(masters[i].name, \"Virtual core pointer\") == 0) {\n"
        "                continue;\n"
        "            }\n"
        "            if (qstrcmp(masters[i].name, \"Virtual core keyboard\") == 0) {\n"
        "                continue;\n"
        "            }\n"
        "            XIEventMask mask;\n"
        "            uchar bitmask[] = {0, 0};\n"
        "            mask.deviceid = masters[i].deviceid;\n"
        "            mask.mask = bitmask;\n"
        "            mask.mask_len = sizeof(bitmask);\n"
        "            XISetMask(bitmask, XI_ButtonPress);\n"
        "            XISetMask(bitmask, XI_ButtonRelease);\n"
        "            XISetMask(bitmask, XI_Motion);\n"
        "            XISetMask(bitmask, XI_Enter);\n"
        "            XISetMask(bitmask, XI_Leave);\n"
        "            const int result = XIGrabDevice(dpy,\n"
        "                                            masters[i].deviceid,\n"
        "                                            X11Info::appRootWindow(),\n"
        "                                            XCB_TIME_CURRENT_TIME,\n"
        "                                            XCB_CURSOR_NONE,\n"
        "                                            XIGrabModeAsync,\n"
        "                                            XIGrabModeAsync,\n"
        "                                            True,\n"
        "                                            &mask);\n"
        "            if (result != XIGrabSuccess) {\n"
        "                success = false;\n"
        "                break;\n"
        "            }\n"
        "        }\n"
        "        if (!success) {\n"
        "            // ungrab all devices again\n"
        "            for (int i = 0; i < numMasters; ++i) {\n"
        "                XIUngrabDevice(dpy, masters[i].deviceid, XCB_TIME_CURRENT_TIME);\n"
        "            }\n"
        "            xcb_connection_t *c = X11Info::connection();\n"
        "            xcb_ungrab_keyboard(c, XCB_CURRENT_TIME);\n"
        "            xcb_ungrab_pointer(c, XCB_CURRENT_TIME);\n"
        "        }\n"
        "        XIFreeDeviceInfo(masters);\n"
        "        XFlush(dpy);\n"
        "        return success;\n"
        "    }\n"
        "#endif\n"
        "\n"
        "    return true;\n"
        "}\n"
        "\n"
        "static bool grabKeyboard()\n"
        "{\n"
        "    qCDebug(KSCREENLOCKER) << \"Grabbing keyboard\";\n"
        "\n"
        "    int rv = XGrabKeyboard(X11Info::display(), X11Info::appRootWindow(), True, GrabModeAsync, GrabModeAsync, CurrentTime);\n"
        "\n"
        "    return (rv == GrabSuccess);\n"
        "}\n"
        "\n"
        "static bool grabMouse()\n"
        "{\n"
        "    qCDebug(KSCREENLOCKER) << \"Grabbing mouse\";\n"
        "\n"
        "#define GRABEVENTS ButtonPressMask | ButtonReleaseMask | PointerMotionMask | EnterWindowMask | LeaveWindowMask\n"
        "    int rv = XGrabPointer(X11Info::display(), X11Info::appRootWindow(), True, GRABEVENTS, GrabModeAsync, GrabModeAsync, None, None, CurrentTime);\n"
        "#undef GRABEVENTS\n"
        "\n"
        "    return (rv == GrabSuccess);\n"
        "}\n",
        "    return true;\n"
        "}\n",
    ),
    (
        "        if (m_isX11) {\n"
        "            m_lockWindow = new X11Locker(this);\n"
        "\n"
        "            connect(\n"
        "                m_lockWindow,\n"
        "                &AbstractLocker::userActivity,\n"
        "                m_lockWindow,\n"
        "                [this]() {\n"
        "                    if (isGraceTime() || !m_requirePassword) {\n"
        "                        unlock();\n"
        "                    }\n"
        "                },\n"
        "                Qt::QueuedConnection);\n"
        "        }\n"
        "\n"
        "        if (m_isWayland) {\n",
        "        if (m_isWayland) {\n",
    ),
    (
        "    m_lockWindow->showLockWindow();\n"
        "    if (m_isX11) {\n"
        "        XSync(X11Info::display(), False);\n"
        "    }\n"
        "}\n",
        "    m_lockWindow->showLockWindow();\n"
        "}\n",
    ),
    (
        # doUnlock() -- se creía "compila fino, sólo usa xcb core" porque
        # xcb_ungrab_keyboard/xcb_ungrab_pointer/xcb_flush son del núcleo
        # de libxcb -- cierto, pero X11Info::connection() (la fuente del
        # xcb_connection_t*) vive en x11info.h, que ya sacamos del todo.
        # Error real visto en el segundo intento de build:
        # "ksldapp.cpp:459:31: error: 'X11Info' has not been declared".
        # Mismo criterio: bloque muerto (m_isX11 siempre false), se saca.
        "    if (m_isX11) {\n"
        "        xcb_connection_t *c = X11Info::connection();\n"
        "        xcb_ungrab_keyboard(c, XCB_CURRENT_TIME);\n"
        "        xcb_ungrab_pointer(c, XCB_CURRENT_TIME);\n"
        "        xcb_flush(c);\n"
        "#if X11_Xinput_FOUND\n"
        "        if (m_hasXInput2) {\n"
        "            // get all devices\n"
        "            Display *dpy = X11Info::display();\n"
        "            int numMasters;\n"
        "            XIDeviceInfo *masters = XIQueryDevice(dpy, XIAllMasterDevices, &numMasters);\n"
        "            // ungrab all devices again\n"
        "            for (int i = 0; i < numMasters; ++i) {\n"
        "                XIUngrabDevice(dpy, masters[i].deviceid, XCB_TIME_CURRENT_TIME);\n"
        "            }\n"
        "            XIFreeDeviceInfo(masters);\n"
        "            XFlush(dpy);\n"
        "        }\n"
        "#endif\n"
        "    }\n",
        "",
    ),
])

patch_file("ksldapp.h", [
    (
        "    void initializeX11();\n",
        "",
    ),
])

# globalaccel.cpp: m_keySymbols (xcb_key_symbols_t*) sólo se llenaba
# detrás de X11Info::isPlatformX11() (siempre false acá) -- se saca la
# asignación/liberación real y checkKeyPress() se reduce a su propio
# "if (!m_keySymbols) return false;" que YA era el comportamiento real.
#
# "#include <KKeyServer>" es un problema real APARTE (no es sólo un
# include sin guard como los demás): KWindowSystem (Tier 2, ya compilado
# hace semanas) sólo INSTALA kkeyserver.h cuando se compila con soporte
# X11 real -- confirmado leyendo su src/CMakeLists.txt ("we install
# kkeyserver_x11.h which needs the X11 headers available"). Como
# construimos KWindowSystem sin X11 (mismo criterio de siempre), el
# header directamente no existe en el sysroot -- error real visto:
# "globalaccel.cpp:8:10: fatal error: KKeyServer: No such file or
# directory". De las funciones de KKeyServer que este archivo usaba,
# sólo UNA sigue viva tras sacar el código X11 muerto (checkKeyPress()
# ya no la necesita): isShiftAsModifierAllowed(), que además es un
# camino REAL en runtime (keyEvent(), la ruta de shortcuts en Wayland,
# no detrás de ningún m_isX11) -- lógica pura de Qt::Key, sin ningún uso
# de Xlib/xcb pese a vivir en un archivo con install gateado a X11. En
# vez de re-parchear KWindowSystem (Tier 2 ya cerrado, mucho más blast
# radius), se copia esa función tal cual (verbatim, confirmado contra
# kwindowsystem-6.29.0/src/kkeyserver.cpp líneas 106-297) como estática
# local de este archivo.
patch_file("globalaccel.cpp", [
    (
        "#include <KKeyServer>\n"
        "#include <netwm.h>\n"
        "\n"
        "#include <QDBusConnection>\n"
        "#include <QDBusMessage>\n"
        "#include <QDBusMetaType>\n"
        "#include <QDBusPendingReply>\n"
        "#include <QKeyEvent>\n"
        "#include <QRegularExpression>\n"
        "\n"
        "#include \"x11info.h\"\n"
        "#include <X11/keysym.h>\n"
        "#include <xcb/xcb.h>\n"
        "#include <xcb/xcb_keysyms.h>\n",
        "\n"
        "#include <QDBusConnection>\n"
        "#include <QDBusMessage>\n"
        "#include <QDBusMetaType>\n"
        "#include <QDBusPendingReply>\n"
        "#include <QKeyEvent>\n"
        "#include <QRegularExpression>\n"
        "\n"
        "// KKeyServer, X11/xcb-util-keysyms y netwm.h removidos a proposito.\n"
        "// netwm.h es el \"netwm.h\" completo de KWindowSystem\n"
        "// (src/platforms/xcb/netwm.h), sólo instalado con soporte X11 real\n"
        "// (igual que kkeyserver.h) -- pero acá ni un solo símbolo NET::/\n"
        "// NETWinInfo del header se usaba en este archivo, así que se saca\n"
        "// directo (include muerto, no una dependencia real). Ver comentario\n"
        "// largo en _patch_kscreenlocker() (build-kde.sh) para el resto.\n"
        "// isShiftAsModifierAllowed() se reimplementa mas abajo, copiada\n"
        "// verbatim de KWindowSystem (unico simbolo de KKeyServer que sigue\n"
        "// vivo en runtime tras sacar checkKeyPress()).\n"
        "\n"
        "static bool isShiftAsModifierAllowed(int keyQt)\n"
        "{\n"
        "    // remove any modifiers\n"
        "    keyQt &= ~Qt::KeyboardModifierMask;\n"
        "\n"
        "    // Shift only works as a modifier with certain keys. It's not possible\n"
        "    // to enter the SHIFT+5 key sequence for me because this is handled as\n"
        "    // '%' by qt on my keyboard.\n"
        "    // The working keys are all hardcoded here :-(\n"
        "    if (keyQt >= Qt::Key_F1 && keyQt <= Qt::Key_F35) {\n"
        "        return true;\n"
        "    }\n"
        "\n"
        "    // Returns false if not a unicode code point\n"
        "    if (QChar::isLetter(keyQt)) {\n"
        "        return true;\n"
        "    }\n"
        "\n"
        "    switch (keyQt) {\n"
        "    case Qt::Key_Return:\n"
        "    case Qt::Key_Space:\n"
        "    case Qt::Key_Backspace:\n"
        "    case Qt::Key_Tab:\n"
        "    case Qt::Key_Backtab:\n"
        "    case Qt::Key_Escape:\n"
        "    case Qt::Key_Print:\n"
        "    case Qt::Key_ScrollLock:\n"
        "    case Qt::Key_Pause:\n"
        "    case Qt::Key_PageUp:\n"
        "    case Qt::Key_PageDown:\n"
        "    case Qt::Key_Insert:\n"
        "    case Qt::Key_Delete:\n"
        "    case Qt::Key_Home:\n"
        "    case Qt::Key_End:\n"
        "    case Qt::Key_Up:\n"
        "    case Qt::Key_Down:\n"
        "    case Qt::Key_Left:\n"
        "    case Qt::Key_Right:\n"
        "    case Qt::Key_Enter:\n"
        "    case Qt::Key_SysReq:\n"
        "    case Qt::Key_CapsLock:\n"
        "    case Qt::Key_NumLock:\n"
        "    case Qt::Key_Help:\n"
        "    case Qt::Key_Back:\n"
        "    case Qt::Key_Forward:\n"
        "    case Qt::Key_Stop:\n"
        "    case Qt::Key_Refresh:\n"
        "    case Qt::Key_Favorites:\n"
        "    case Qt::Key_LaunchMedia:\n"
        "    case Qt::Key_OpenUrl:\n"
        "    case Qt::Key_HomePage:\n"
        "    case Qt::Key_Search:\n"
        "    case Qt::Key_VolumeDown:\n"
        "    case Qt::Key_VolumeMute:\n"
        "    case Qt::Key_VolumeUp:\n"
        "    case Qt::Key_BassBoost:\n"
        "    case Qt::Key_BassUp:\n"
        "    case Qt::Key_BassDown:\n"
        "    case Qt::Key_TrebleUp:\n"
        "    case Qt::Key_TrebleDown:\n"
        "    case Qt::Key_MediaPlay:\n"
        "    case Qt::Key_MediaStop:\n"
        "    case Qt::Key_MediaPrevious:\n"
        "    case Qt::Key_MediaNext:\n"
        "    case Qt::Key_MediaRecord:\n"
        "    case Qt::Key_MediaPause:\n"
        "    case Qt::Key_MediaTogglePlayPause:\n"
        "    case Qt::Key_LaunchMail:\n"
        "    case Qt::Key_Calculator:\n"
        "    case Qt::Key_Memo:\n"
        "    case Qt::Key_ToDoList:\n"
        "    case Qt::Key_Calendar:\n"
        "    case Qt::Key_PowerDown:\n"
        "    case Qt::Key_ContrastAdjust:\n"
        "    case Qt::Key_Standby:\n"
        "    case Qt::Key_MonBrightnessUp:\n"
        "    case Qt::Key_MonBrightnessDown:\n"
        "    case Qt::Key_KeyboardLightOnOff:\n"
        "    case Qt::Key_KeyboardBrightnessUp:\n"
        "    case Qt::Key_KeyboardBrightnessDown:\n"
        "    case Qt::Key_PowerOff:\n"
        "    case Qt::Key_WakeUp:\n"
        "    case Qt::Key_Eject:\n"
        "    case Qt::Key_ScreenSaver:\n"
        "    case Qt::Key_WWW:\n"
        "    case Qt::Key_Sleep:\n"
        "    case Qt::Key_LightBulb:\n"
        "    case Qt::Key_Shop:\n"
        "    case Qt::Key_History:\n"
        "    case Qt::Key_AddFavorite:\n"
        "    case Qt::Key_HotLinks:\n"
        "    case Qt::Key_BrightnessAdjust:\n"
        "    case Qt::Key_Finance:\n"
        "    case Qt::Key_Community:\n"
        "    case Qt::Key_AudioRewind:\n"
        "    case Qt::Key_BackForward:\n"
        "    case Qt::Key_ApplicationLeft:\n"
        "    case Qt::Key_ApplicationRight:\n"
        "    case Qt::Key_Book:\n"
        "    case Qt::Key_CD:\n"
        "    case Qt::Key_Clear:\n"
        "    case Qt::Key_ClearGrab:\n"
        "    case Qt::Key_Close:\n"
        "    case Qt::Key_Copy:\n"
        "    case Qt::Key_Cut:\n"
        "    case Qt::Key_Display:\n"
        "    case Qt::Key_DOS:\n"
        "    case Qt::Key_Documents:\n"
        "    case Qt::Key_Excel:\n"
        "    case Qt::Key_Explorer:\n"
        "    case Qt::Key_Game:\n"
        "    case Qt::Key_Go:\n"
        "    case Qt::Key_iTouch:\n"
        "    case Qt::Key_LogOff:\n"
        "    case Qt::Key_Market:\n"
        "    case Qt::Key_Meeting:\n"
        "    case Qt::Key_MenuKB:\n"
        "    case Qt::Key_MenuPB:\n"
        "    case Qt::Key_MySites:\n"
        "    case Qt::Key_News:\n"
        "    case Qt::Key_OfficeHome:\n"
        "    case Qt::Key_Option:\n"
        "    case Qt::Key_Paste:\n"
        "    case Qt::Key_Phone:\n"
        "    case Qt::Key_Reply:\n"
        "    case Qt::Key_Reload:\n"
        "    case Qt::Key_RotateWindows:\n"
        "    case Qt::Key_RotationPB:\n"
        "    case Qt::Key_RotationKB:\n"
        "    case Qt::Key_Save:\n"
        "    case Qt::Key_Send:\n"
        "    case Qt::Key_Spell:\n"
        "    case Qt::Key_SplitScreen:\n"
        "    case Qt::Key_Support:\n"
        "    case Qt::Key_TaskPane:\n"
        "    case Qt::Key_Terminal:\n"
        "    case Qt::Key_Tools:\n"
        "    case Qt::Key_Travel:\n"
        "    case Qt::Key_Video:\n"
        "    case Qt::Key_Word:\n"
        "    case Qt::Key_Xfer:\n"
        "    case Qt::Key_ZoomIn:\n"
        "    case Qt::Key_ZoomOut:\n"
        "    case Qt::Key_Away:\n"
        "    case Qt::Key_Messenger:\n"
        "    case Qt::Key_WebCam:\n"
        "    case Qt::Key_MailForward:\n"
        "    case Qt::Key_Pictures:\n"
        "    case Qt::Key_Music:\n"
        "    case Qt::Key_Battery:\n"
        "    case Qt::Key_Bluetooth:\n"
        "    case Qt::Key_WLAN:\n"
        "    case Qt::Key_UWB:\n"
        "    case Qt::Key_AudioForward:\n"
        "    case Qt::Key_AudioRepeat:\n"
        "    case Qt::Key_AudioRandomPlay:\n"
        "    case Qt::Key_Subtitle:\n"
        "    case Qt::Key_AudioCycleTrack:\n"
        "    case Qt::Key_Time:\n"
        "    case Qt::Key_Select:\n"
        "    case Qt::Key_View:\n"
        "    case Qt::Key_TopMenu:\n"
        "    case Qt::Key_Suspend:\n"
        "    case Qt::Key_Hibernate:\n"
        "    case Qt::Key_Launch0:\n"
        "    case Qt::Key_Launch1:\n"
        "    case Qt::Key_Launch2:\n"
        "    case Qt::Key_Launch3:\n"
        "    case Qt::Key_Launch4:\n"
        "    case Qt::Key_Launch5:\n"
        "    case Qt::Key_Launch6:\n"
        "    case Qt::Key_Launch7:\n"
        "    case Qt::Key_Launch8:\n"
        "    case Qt::Key_Launch9:\n"
        "    case Qt::Key_LaunchA:\n"
        "    case Qt::Key_LaunchB:\n"
        "    case Qt::Key_LaunchC:\n"
        "    case Qt::Key_LaunchD:\n"
        "    case Qt::Key_LaunchE:\n"
        "    case Qt::Key_LaunchF:\n"
        "    case Qt::Key_Shift:\n"
        "    case Qt::Key_Control:\n"
        "    case Qt::Key_Meta:\n"
        "    case Qt::Key_Alt:\n"
        "    case Qt::Key_Super_L:\n"
        "    case Qt::Key_Super_R:\n"
        "        return true;\n"
        "\n"
        "    default:\n"
        "        return false;\n"
        "    }\n"
        "}\n",
    ),
    (
        # calculateGrabMasks()/g_keyModMaskX* quedan totalmente muertos:
        # su único caller era el bloque de abajo, y su cuerpo usa símbolos
        # de KKeyServer (accelModMaskX/modXLock/etc) que ya no existen tras
        # sacar el include -- si se dejaba la función definida (sólo sin
        # llamarla) igual fallaba la compilación por símbolos indefinidos.
        "static uint g_keyModMaskXAccel = 0;\n"
        "static uint g_keyModMaskXOnOrOff = 0;\n"
        "\n"
        "static void calculateGrabMasks()\n"
        "{\n"
        "    g_keyModMaskXAccel = KKeyServer::accelModMaskX();\n"
        "    g_keyModMaskXOnOrOff = KKeyServer::modXLock() | KKeyServer::modXNumLock() | KKeyServer::modXScrollLock() | KKeyServer::modXModeSwitch();\n"
        "}\n"
        "\n",
        "",
    ),
    (
        "    if (X11Info::isPlatformX11()) {\n"
        "        m_keySymbols = xcb_key_symbols_alloc(X11Info::connection());\n"
        "        calculateGrabMasks();\n"
        "    }\n"
        "\n",
        "",
    ),
    (
        "    if (keyModQt & Qt::SHIFT && !KKeyServer::isShiftAsModifierAllowed(keyCodeQt)) {\n"
        "        keyModQt &= ~Qt::SHIFT;\n"
        "    }\n"
        "\n"
        "    if ((keyModQt == 0 || keyModQt == Qt::SHIFT) && (keyCodeQt >= Qt::Key_Space && keyCodeQt <= Qt::Key_AsciiTilde)) {\n"
        "        // security check: we don't allow shortcuts without modifier for \"normal\" keys\n"
        "        // this is to prevent a malicious application to grab shortcuts for all keys\n"
        "        // and by that being able to read out the keyboard\n"
        "        return false;\n"
        "    }\n"
        "\n"
        "    const QKeySequence seq(keyCodeQt | keyModQt);\n"
        "    // let's check whether we have a mapping shortcut\n"
        "    for (const auto &[key, value] : std::as_const(m_shortcuts).asKeyValueRange()) {\n"
        "        for (const auto &info : value) {\n"
        "            if (info.keys().contains(seq)) {\n"
        "                auto signal = QDBusMessage::createMethodCall(s_kglobalAccelService, key, s_componentInterface, QStringLiteral(\"invokeShortcut\"));\n"
        "                signal.setArguments(QList<QVariant>{QVariant(info.uniqueName())});\n"
        "                QDBusConnection::sessionBus().asyncCall(signal);\n"
        "                event->setAccepted(true);\n"
        "                return true;\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    return false;\n"
        "}\n"
        "\n"
        "bool GlobalAccel::checkKeyPress(xcb_key_press_event_t *event)\n",
        "    if (keyModQt & Qt::SHIFT && !isShiftAsModifierAllowed(keyCodeQt)) {\n"
        "        keyModQt &= ~Qt::SHIFT;\n"
        "    }\n"
        "\n"
        "    if ((keyModQt == 0 || keyModQt == Qt::SHIFT) && (keyCodeQt >= Qt::Key_Space && keyCodeQt <= Qt::Key_AsciiTilde)) {\n"
        "        // security check: we don't allow shortcuts without modifier for \"normal\" keys\n"
        "        // this is to prevent a malicious application to grab shortcuts for all keys\n"
        "        // and by that being able to read out the keyboard\n"
        "        return false;\n"
        "    }\n"
        "\n"
        "    const QKeySequence seq(keyCodeQt | keyModQt);\n"
        "    // let's check whether we have a mapping shortcut\n"
        "    for (const auto &[key, value] : std::as_const(m_shortcuts).asKeyValueRange()) {\n"
        "        for (const auto &info : value) {\n"
        "            if (info.keys().contains(seq)) {\n"
        "                auto signal = QDBusMessage::createMethodCall(s_kglobalAccelService, key, s_componentInterface, QStringLiteral(\"invokeShortcut\"));\n"
        "                signal.setArguments(QList<QVariant>{QVariant(info.uniqueName())});\n"
        "                QDBusConnection::sessionBus().asyncCall(signal);\n"
        "                event->setAccepted(true);\n"
        "                return true;\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    return false;\n"
        "}\n"
        "\n"
        "bool GlobalAccel::checkKeyPress(xcb_key_press_event_t *event)\n",
    ),
    (
        "    m_shortcuts.clear();\n"
        "    if (m_keySymbols) {\n"
        "        xcb_key_symbols_free(m_keySymbols);\n"
        "        m_keySymbols = nullptr;\n"
        "    }\n"
        "}\n",
        "    m_shortcuts.clear();\n"
        "}\n",
    ),
    (
        "bool GlobalAccel::checkKeyPress(xcb_key_press_event_t *event)\n"
        "{\n"
        "    if (!m_keySymbols) {\n"
        "        return false;\n"
        "    }\n"
        "    // based and inspired from code in kglobalaccel_x11.cpp\n"
        "    xcb_keycode_t keyCodeX = event->detail;\n"
        "    uint16_t keyModX = event->state & (g_keyModMaskXAccel | KKeyServer::MODE_SWITCH);\n"
        "\n"
        "    xcb_keysym_t keySymX = xcb_key_press_lookup_keysym(m_keySymbols, event, 0);\n"
        "\n"
        "    // If numlock is active and a keypad key is pressed, XOR the SHIFT state.\n"
        "    //  e.g., KP_4 => Shift+KP_Left, and Shift+KP_4 => KP_Left.\n"
        "    if (event->state & KKeyServer::modXNumLock()) {\n"
        "        xcb_keysym_t sym = xcb_key_symbols_get_keysym(m_keySymbols, keyCodeX, 0);\n"
        "        // If this is a keypad key,\n"
        "        if (sym >= XK_KP_Space && sym <= XK_KP_9) {\n"
        "            switch (sym) {\n"
        "            // Leave the following keys unaltered\n"
        "            // FIXME: The proper solution is to see which keysyms don't change when shifted.\n"
        "            case XK_KP_Multiply:\n"
        "            case XK_KP_Add:\n"
        "            case XK_KP_Subtract:\n"
        "            case XK_KP_Divide:\n"
        "                break;\n"
        "\n"
        "            default:\n"
        "                keyModX ^= KKeyServer::modXShift();\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "\n"
        "    int keyCodeQt;\n"
        "    KKeyServer::symXModXToKeyQt(keySymX, keyModX, &keyCodeQt);\n"
        "    // Split keycode and modifier\n"
        "    int keyModQt = keyCodeQt & Qt::KeyboardModifierMask;\n"
        "    keyCodeQt &= ~Qt::KeyboardModifierMask;\n"
        "\n"
        "    if (keyModQt & Qt::SHIFT && !KKeyServer::isShiftAsModifierAllowed(keyCodeQt)) {\n"
        "        keyModQt &= ~Qt::SHIFT;\n"
        "    }\n"
        "\n"
        "    if ((keyModQt == 0 || keyModQt == Qt::SHIFT) && (keyCodeQt >= Qt::Key_Space && keyCodeQt <= Qt::Key_AsciiTilde)) {\n"
        "        // security check: we don't allow shortcuts without modifier for \"normal\" keys\n"
        "        // this is to prevent a malicious application to grab shortcuts for all keys\n"
        "        // and by that being able to read out the keyboard\n"
        "        return false;\n"
        "    }\n"
        "\n"
        "    const QKeySequence seq(keyCodeQt | keyModQt);\n"
        "    // let's check whether we have a mapping shortcut\n"
        "    for (const auto &[key, value] : std::as_const(m_shortcuts).asKeyValueRange()) {\n"
        "        for (const auto &info : value) {\n"
        "            if (info.keys().contains(seq)) {\n"
        "                auto signal = QDBusMessage::createMethodCall(s_kglobalAccelService, key, s_componentInterface, QStringLiteral(\"invokeShortcut\"));\n"
        "                signal.setArguments(QList<QVariant>{QVariant(info.uniqueName())});\n"
        "                QDBusConnection::sessionBus().asyncCall(signal);\n"
        "                return true;\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    return false;\n"
        "}\n",
        "bool GlobalAccel::checkKeyPress(xcb_key_press_event_t *event)\n"
        "{\n"
        "    Q_UNUSED(event)\n"
        "    // Xlib/xcb-util-keysyms removido a proposito -- LINSI-OS es Wayland\n"
        "    // puro, m_keySymbols nunca se asigna (ver _patch_kscreenlocker()).\n"
        "    return false;\n"
        "}\n",
    ),
])

# greeter/CMakeLists.txt: X11::X11 y XCB::UTIL linkeados directo, sin
# ningún guard -- ninguno de los dos targets existe en nuestro sysroot.
patch_file("greeter/CMakeLists.txt", [
    (
        "    Qt::DBus\n"
        "    Qt::Quick\n"
        "    Qt::Qml\n"
        "    X11::X11\n"
        "    XCB::UTIL\n"
        "    Wayland::Client\n",
        "    Qt::DBus\n"
        "    Qt::Quick\n"
        "    Qt::Qml\n"
        "    Wayland::Client\n",
    ),
])

# greeter/greeterapp.cpp: FocusOutEventFilter (xcb-util's xcb_event.h) y
# el bloque XInternAtom/XChangeProperty (Xlib real) son las dos únicas
# partes de este archivo que de verdad necesitan X11/xcb-util -- el resto
# de las menciones de X11 (Qt::X11BypassWindowManagerHint,
# org_kde_ksld_x11window) son símbolos de Qt/del protocolo Wayland
# ksld.xml, no de Xlib, y no se tocan.
patch_file("greeter/greeterapp.cpp", [
    (
        "// Wayland\n"
        "#include <wayland-client.h>\n"
        "#include <wayland-ksld-client-protocol.h>\n"
        "// X11\n"
        "#include <X11/Xatom.h>\n"
        "#include <X11/Xlib.h>\n"
        "#include <fixx11h.h>\n"
        "//\n"
        "#include <xcb/xcb.h>\n"
        "#include <xcb/xcb_event.h>\n",
        "// Wayland\n"
        "#include <wayland-client.h>\n"
        "#include <wayland-ksld-client-protocol.h>\n"
        "// X11/xcb-util removidos a proposito -- LINSI-OS es Wayland puro\n"
        "// (ver _patch_kscreenlocker() en build-kde.sh). FocusOutEventFilter\n"
        "// tambien se saca mas abajo (dependia de xcb_event.h de xcb-util).\n",
    ),
    (
        "class FocusOutEventFilter : public QAbstractNativeEventFilter\n"
        "{\n"
        "public:\n"
        "    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override\n"
        "    {\n"
        "        Q_UNUSED(result)\n"
        "        if (eventType != QByteArrayLiteral(\"xcb_generic_event_t\")) {\n"
        "            return false;\n"
        "        }\n"
        "        auto event = static_cast<xcb_generic_event_t *>(message);\n"
        "        return XCB_EVENT_RESPONSE_TYPE(event) == XCB_FOCUS_OUT;\n"
        "    }\n"
        "};\n"
        "\n",
        "",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        installNativeEventFilter(new FocusOutEventFilter);\n"
        "    }\n",
        "",
    ),
    (
        "        if (view && view->winId() && KWindowSystem::isPlatformX11()) {\n"
        "            // showing greeter view window, set property\n"
        "            auto x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();\n"
        "            static Atom tag = XInternAtom(x11App->display(), \"_KDE_SCREEN_LOCKER\", False);\n"
        "            XChangeProperty(x11App->display(), view->winId(), tag, tag, 32, PropModeReplace, nullptr, 0);\n"
        "        }\n",
        "",
    ),
])

print("OK: kscreenlocker parcheado (CMakeLists.txt, ksldapp.cpp/.h, globalaccel.cpp, greeter/CMakeLists.txt, greeter/greeterapp.cpp)")
PYEOF
}

# ------------------------------------------------------------------------------
# KScreenLocker -- último de los 5 prerequisitos de kwin identificados
# contra el CMakeLists.txt real de kwin (2026-09-16). Dependencias reales
# confirmadas contra invent.kde.org/plasma/kscreenlocker/-/raw/master/CMakeLists.txt:
# ECM; Qt6 DBus/Widgets/Quick/Test; KF6 Crash/KCMUtils/KIO/GlobalAccel/
# I18n/IdleTime/Notifications/Solid/WindowSystem/XmlGui/Svg; PlasmaQuick;
# LayerShellQt; KF6Screen; PAM -- TODAS ya en el sysroot, ninguna nueva.
# Sin checks de X11 en el CMakeLists.txt real (release Wayland puro, no
# hizo falta ningún patch esta vez). Tarball real: "kscreenlocker"
# (confirmado en el listado de download.kde.org/stable/plasma/6.7.4/).
step_kscreenlocker() { _plasma_cmake_build KScreenLocker kscreenlocker; }
# Paths reales confirmados contra el log de instalación real (a diferencia
# de KGlobalAccelD, acá SÍ hay symlink ".so" sin versión, no hace falta
# usar el ".so.6" versionado).
step_verify_kscreenlocker() {
    log "Verificación: librería + greeter + KCM de KScreenLocker en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libKScreenLocker.so" \
        "${LFS_SYSROOT}/usr/lib/libexec/kscreenlocker_greet" \
        "${LFS_SYSROOT}/usr/lib/plugins/plasma/kcms/systemsettings/kcm_screenlocker.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de KScreenLocker"
    log "OK: KScreenLocker completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Vulkan-Headers + Vulkan-Loader -- sexto prerequisito real de kwin,
# descubierto recién al CORRER el primer intento de build (no en el
# research previo, que se apoyaba en la suposición heredada "Vulkan ya
# está compilado desde Mesa/Fase 6 Parte 2" -- FALSA: confirmado con
# `find` real sobre el sysroot que Mesa sólo instala los drivers ICD
# (libvulkan_radeon.so/libvulkan_intel.so + manifests JSON en
# /usr/share/vulkan/icd.d/), nunca el LOADER (libvulkan.so, lo que las
# apps linkean de verdad) ni los headers (vulkan/vulkan.h) -- dos
# proyectos aparte de KhronosGroup. CMake plano, sin ECM ni Qt, así que
# no usan ninguno de los dos helpers compartidos (_kf6_cmake_build/
# _plasma_cmake_build) -- se escriben standalone.
# Vulkan-Headers: header-only real (confirmado contra su CMakeLists.txt
# vía GitHub) -- ninguna dependencia, sólo instala vulkan/vulkan.h +
# VulkanHeadersConfig.cmake (target INTERFACE "Vulkan::Headers").
step_vulkan_headers() {
    require_toolchain
    log "Vulkan-Headers ${VULKAN_HEADERS_VERSION} para ${LFS_TGT} — header-only, CMake"

    cd "${LFS_SOURCES}"
    fetch "${VULKAN_HEADERS_MIRROR}/v${VULKAN_HEADERS_VERSION}.tar.gz" \
          "vulkan-headers-${VULKAN_HEADERS_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/vulkan-headers-${VULKAN_HEADERS_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/vulkan-headers-${VULKAN_HEADERS_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-vulkan-headers-${VULKAN_HEADERS_VERSION}"

    local src="${LFS_BUILD}/Vulkan-Headers-${VULKAN_HEADERS_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "Vulkan-Headers instalado en ${LFS_SYSROOT}/usr"
}
step_verify_vulkan_headers() {
    log "Verificación: Vulkan-Headers en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/include/vulkan/vulkan.h" \
        "${LFS_SYSROOT}/usr/share/cmake/VulkanHeaders/VulkanHeadersConfig.cmake"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de Vulkan-Headers"
    log "OK: Vulkan-Headers completo en el sysroot."
}
require_vulkan_headers() {
    [[ -e "${LFS_SYSROOT}/usr/include/vulkan/vulkan.h" ]] \
        || die "no está Vulkan-Headers en el sysroot -- corré primero: scripts/build-kde.sh vulkan-headers"
}

# Vulkan-Loader: el dispatch loader real (libvulkan.so) que las apps
# linkean -- en runtime hace dlopen() del ICD correcto usando los
# manifests JSON que Mesa YA instaló. BUILD_WSI_XCB_SUPPORT/
# BUILD_WSI_XLIB_SUPPORT/BUILD_WSI_XLIB_XRANDR_SUPPORT dan ON por
# default (confirmado contra su CMakeLists.txt real) -- se apagan los
# 3 a propósito (Wayland puro), dejando sólo BUILD_WSI_WAYLAND_SUPPORT
# (ya ON por default). A diferencia de KScreenLocker, este es un
# gateo real y limpio de CMake (mismo patrón que KWIN_BUILD_X11 de
# kwin) -- no hace falta ningún patch de fuente.
step_vulkan_loader() {
    require_toolchain
    require_vulkan_headers
    log "Vulkan-Loader ${VULKAN_LOADER_VERSION} para ${LFS_TGT} — CMake, sin WSI X11"

    cd "${LFS_SOURCES}"
    fetch "${VULKAN_LOADER_MIRROR}/v${VULKAN_LOADER_VERSION}.tar.gz" \
          "vulkan-loader-${VULKAN_LOADER_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/vulkan-loader-${VULKAN_LOADER_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/vulkan-loader-${VULKAN_LOADER_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-vulkan-loader-${VULKAN_LOADER_VERSION}"

    local src="${LFS_BUILD}/Vulkan-Loader-${VULKAN_LOADER_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF \
        -DBUILD_WSI_XCB_SUPPORT=OFF \
        -DBUILD_WSI_XLIB_SUPPORT=OFF \
        -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF \
        -DBUILD_WSI_WAYLAND_SUPPORT=ON

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "Vulkan-Loader instalado en ${LFS_SYSROOT}/usr"
}
step_verify_vulkan_loader() {
    log "Verificación: libvulkan.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libvulkan.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: Vulkan-Loader completo en el sysroot."
}

# ------------------------------------------------------------------------------
# libxcvt -- séptimo prerequisito real de kwin, descubierto en la SEGUNDA
# corrida real (después de resolver Vulkan): "pkg_check_modules(Libxcvt
# ... libxcvt>=0.1.1 REQUIRED)". Pese al nombre, es sólo el algoritmo
# VESA CVT para generar modelines de video (matemática pura, usada por
# el backend DRM de kwin para armar modos custom) -- confirmado leyendo
# su meson.build real: única dependencia es libm, nada de X11/XCB.
# gitlab.freedesktop.org bloquea la navegación (Anubis) pero el tarball
# se descarga directo igual (mismo caso que libdisplay-info).
step_libxcvt() {
    require_toolchain
    log "libxcvt ${LIBXCVT_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${LIBXCVT_MIRROR}/libxcvt-libxcvt-${LIBXCVT_VERSION}.tar.gz" \
          "libxcvt-${LIBXCVT_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libxcvt-${LIBXCVT_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libxcvt-${LIBXCVT_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libxcvt-${LIBXCVT_VERSION}"

    local src="${LFS_BUILD}/libxcvt-libxcvt-${LIBXCVT_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libxcvt instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libxcvt() {
    log "Verificación: libxcvt.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libxcvt.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libxcvt completo en el sysroot."
}

# ------------------------------------------------------------------------------
# KNightTime + sus 2 dependencias reales (Qt6 Positioning, KF6Holidays)
# -- octavo/noveno/décimo prerequisito real de kwin, descubierto en la
# TERCERA corrida real (después de resolver KF6_HOST_TOOLING): el
# feature_summary() final de kwin marca "KNightTime (required version
# >= 6.7.0) -- Needed for Night Light" como REQUIRED faltante --
# `find_package(KNightTime CONFIG)` con `set_package_properties(...
# TYPE REQUIRED)` (CMakeLists.txt real de kwin), algo que el mapeo
# original ("sin investigar todavía") no había marcado como bloqueante.
# KNightTime es del tren de Plasma (download.kde.org/stable/plasma/
# 6.7.4/knighttime-6.7.4.tar.xz, confirmado en el listado real) --
# calcula amanecer/atardecer para Night Light/Night Color. Su
# CMakeLists.txt real pide Qt6 Core/Gui/DBus/Positioning y KF6 Config/
# CoreAddons/DBusAddons/Holidays/I18n -- de ahí, dos piezas nuevas:
# Qt6 Positioning (submódulo de Qt6, mismo tren QT6_VERSION/QT6_MIRROR
# de siempre, nunca compilado hasta ahora) y KF6Holidays (framework KDE,
# mismo tren KDE_VERSION/KDE_FRAMEWORKS_MIRROR de siempre). KHolidays
# pide FLEX+BISON REQUIRED (genera un parser real desde una gramática,
# "plan2 parser") -- son herramientas de host, ya vienen en la imagen
# del contenedor (confirmado con "which flex bison" real), no hace
# falta agregar nada.
step_qtpositioning() {
    require_toolchain
    require_qtbase
    log "Qt6 (qtpositioning) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtpositioning-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtpositioning-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtpositioning-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtpositioning-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtpositioning"

    local src="${LFS_BUILD}/qtpositioning-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtpositioning-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtpositioning instalado en ${LFS_SYSROOT}/usr"
}
step_verify_qtpositioning() { _kf6_verify_lib qtpositioning libQt6Positioning.so; }

# qtlocation -- submódulo Qt6 SEPARADO de qtpositioning (tarball real
# distinto, confirmado con un wget: "qtlocation-everywhere-src-*"),
# descubierto recién al correr plasma-workspace real
# ("find_package(Qt6 ... COMPONENTS ... Location)" -- Qt6Location no
# estaba cubierto por qtpositioning). Mismo patrón cruzado simple.
step_qtlocation() {
    require_toolchain
    require_qtbase
    require_qtpositioning
    log "Qt6 (qtlocation) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtlocation-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtlocation-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtlocation-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtlocation-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtlocation"

    local src="${LFS_BUILD}/qtlocation-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtlocation-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtlocation instalado en ${LFS_SYSROOT}/usr"
}
step_verify_qtlocation() { _kf6_verify_lib qtlocation libQt6Location.so; }
require_qtpositioning() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libQt6Positioning.so" ]] \
        || die "no está qtpositioning en el sysroot -- corré primero: scripts/build-kde.sh qtpositioning"
}

step_kholidays() { _kf6_cmake_build KHolidays kholidays; }
step_verify_kholidays() { _kf6_verify_lib KHolidays libKF6Holidays.so; }

step_knighttime() { _plasma_cmake_build KNightTime knighttime; }
# Nombre real confirmado por el log de instalación: "libKNightTime.so"
# (SIN el prefijo "KF6" -- a diferencia de la mayoría de las libs de
# Tier 2/3, este target no sigue esa convención de nombre).
step_verify_knighttime() { _kf6_verify_lib KNightTime libKNightTime.so; }

# ------------------------------------------------------------------------------
# KWin (Tier 5) -- con los 5 prerequisitos de arriba completos, esto es
# lo único que faltaba. Investigado contra el CMakeLists.txt REAL del
# tarball kwin-6.7.4.tar.xz (no contra invent.kde.org/master -- lección
# de KScreenLocker: master puede estar meses adelantado/atrasado
# respecto al tag pineado). A diferencia de KScreenLocker, kwin SÍ
# gatea todo lo X11/XCB correctamente con un "if (KWIN_BUILD_X11)" real
# de CMake (15 componentes XCB + X11_XCB + Xwayland + X11, todo dentro
# del if) -- con KWIN_BUILD_X11=OFF (decisión ya tomada, Pilar 5) ese
# bloque entero ni se evalúa, sin necesidad de ningún patch de fuente.
# REQUIRED confirmados, todos ya en el sysroot: ECM; Qt6 (Core/Gui/
# Widgets/Quick/Qml/WaylandClient/...); KF6 (varios componentes);
# KDecoration3; epoxy>=1.3; Vulkan; Wayland>=1.24; WaylandProtocols>=
# 1.48; PlasmaWaylandProtocols>=1.21.0 (satisfecho por nuestro pin real
# 1.22.0); Canberra; Libinput>=1.28; UDev; Libdrm>=2.4.118; gbm; lcms2;
# libdisplay-info>=0.2.0 (vía pkg-config); KGlobalAccelD (si
# KWIN_BUILD_GLOBALSHORTCUTS, default ON); KScreenLocker (si
# KWIN_BUILD_SCREENLOCKER, default ON). hwdata es sólo TYPE RUNTIME acá
# (no build-time REQUIRED como en libdisplay-info), pero ya está de
# todos modos. Opcionales que se auto-desactivan solos si falta la dep
# (cmake_dependent_option real): KWIN_BUILD_ACTIVITIES (depende de
# PlasmaActivities_FOUND -- SÍ lo tenemos, queda ON), KWIN_BUILD_EIS
# (Libeis-1.0 -- no lo tenemos, se apaga solo),
# KWIN_BUILD_QACCESSIBILITYCLIENT/KWIN_BUILD_GAMECONTROLLER (ídem).
#
# -DKF6_HOST_TOOLING: bug real visto en el primer intento de configure
# ("Please provide a prefix with a native Qt build and pass
# -DKF6_HOST_TOOLING=path", src/wayland/tools/CMakeLists.txt:18) --
# MISMO problema de fondo de siempre (herramienta de build-time que no
# puede correr cruzada: acá "qtwaylandscanner_kde"), pero por primera
# vez kwin lo resuelve solo, con un ExternalProject_Add() real que
# compila una copia nativa de esa única herramienta usando
# "-DCMAKE_PREFIX_PATH=${NATIVE_PREFIX}" (NATIVE_PREFIX se deriva
# recortando KF6_HOST_TOOLING en la PRIMERA aparición de "/lib",
# confirmado leyendo el código real).
#
# Trampa real (segundo intento): KF6_HOST_TOOLING NO es exclusivo de
# kwin -- es una convención de KDE Frameworks entera. KF6ConfigConfig.cmake/
# KF6PackageConfig.cmake/KF6KCMUtilsConfig.cmake (los mismos 3 frameworks
# con herramientas de build-time de siempre) miran la MISMA variable
# global para decidir si buscar su "*ToolsTargets.cmake"/
# "*ToolingTargets.cmake"/"*CompilerTargets.cmake" nativo en vez del
# cruzado -- apenas se define KF6_HOST_TOOLING (obligatorio para
# wayland/tools), los 3 lookups se activan SÍ o SÍ (confirmado con el
# error real: "KCONFIGCOMPILER_PATH-NOTFOUND"/"KPACKAGE_TARGETSFILE-
# NOTFOUND"/"KCMUTILS_TARGETSFILE-NOTFOUND"). KConfig y KCMUtils YA
# tienen su export nativo real (de step_kconfig_native()/
# step_kcmutils_native(), instalados en KF6_NATIVE_INSTALL) -- sólo
# faltaban en el lugar exacto que este mecanismo busca
# (GNUInstallDirs multiarch de siempre: "lib/x86_64-linux-gnu/cmake/",
# no "lib/cmake/"). KPackage NUNCA se compiló nativo (nadie lo había
# necesitado) -- construirlo entero nativo (KArchive+KI18n+KCoreAddons
# nativos en cadena) sólo para un export que exporta un único target
# ("kpackagetool6", confirmado leyendo kpackage/CMakeLists.txt:115 y
# src/kpackagetool/CMakeLists.txt:16) que NADA en el build de kwin
# invoca de verdad sería desproporcionado -- se symlinkea el
# "*ToolsTargets.cmake" ya existente del build CRUZADO (sysroot) en su
# lugar: el target queda definido (apunta a un binario cruzado), pero
# como nunca se ejecuta durante el build de kwin, alcanza con que el
# archivo exista y el "include()" no falle. Si algún consumidor futuro
# SÍ necesitara correr kpackagetool6 de verdad en build-time, ahí sí
# haría falta el patrón nativo completo -- no antes.
#
# _patch_kwin() -- CUARTA aparición real del mismo bug sistémico de
# X11 (después de libplasma, libkscreen, kscreenlocker): includes de
# "private/qtx11extras_p.h" sin guard de preprocesador en dos
# ejecutables standalone de kwin (dialoghelper, killer -- diálogos de
# "aplicación no responde"/"terminar aplicación"), con el uso real
# SIEMPRE detrás de un runtime-check real ("isX11 = platformName() ==
# xcb"). "src/main.cpp" tiene el MISMO include pero YA está bien
# guardeado por upstream con "#if KWIN_BUILD_X11" real -- no hace falta
# tocarlo. "group.cpp"/"x11window.cpp" (el resto de los archivos que
# mencionan X11) ya están 100% excluidos de la compilación por el
# "if (KWIN_BUILD_X11) target_sources(...)" real del CMakeLists.txt --
# tampoco hace falta tocarlos.
_patch_kwin() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]

def patch_file(relpath, replacements):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            sys.exit(f"ERROR: ancla de patch no encontrada en {path}:\n{old!r}")
        if count > 1:
            sys.exit(f"ERROR: ancla de patch no es única en {path} ({count} veces):\n{old!r}")
        content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado ({len(replacements)} reemplazos)")

patch_file("src/helpers/dialoghelper/dialoghelper.cpp", [
    (
        "#include <qpa/qplatformwindow_p.h>\n"
        "\n"
        "#include <private/qtx11extras_p.h>\n"
        "#include <xcb/xcb.h>\n",
        "#include <qpa/qplatformwindow_p.h>\n"
        "\n"
        "#include <xcb/xcb.h>\n",
    ),
    (
        "    if (isX11) {\n"
        "        QX11Info::setAppUserTime(timestamp);\n"
        "    }\n"
        "\n"
        "    // KMessageDialog::Information doesn't let us add additional buttons...\n",
        "    // KMessageDialog::Information doesn't let us add additional buttons...\n",
    ),
])

patch_file("src/helpers/killer/killer.cpp", [
    (
        "#include <qpa/qplatformwindow_p.h>\n"
        "\n"
        "#include <private/qtx11extras_p.h>\n"
        "#include <xcb/xcb.h>\n"
        "\n"
        "#include <cerrno>\n",
        "#include <qpa/qplatformwindow_p.h>\n"
        "\n"
        "#include <xcb/xcb.h>\n"
        "\n"
        "#include <cerrno>\n",
    ),
    (
        "    if (isX11) {\n"
        "        QX11Info::setAppUserTime(timestamp);\n"
        "    }\n"
        "\n"
        "    QObject::connect(&dialog, &KillDialog::terminateRequested, &dialog, [&dialog, pid, &hostname, &isLocal] {\n",
        "    QObject::connect(&dialog, &KillDialog::terminateRequested, &dialog, [&dialog, pid, &hostname, &isLocal] {\n",
    ),
])

print("OK: kwin parcheado (dialoghelper.cpp, killer.cpp)")
PYEOF
}
#
# Dos intentos fallidos antes de esta versión, los dos por la MISMA
# causa raíz -- vale la pena dejarlos documentados porque el error de
# cada uno apuntaba a otra cosa y llevaba a un diagnóstico equivocado:
#
# 1º intento: "host_tooling" apuntaba a
# "${KF6_NATIVE_INSTALL}/lib/x86_64-linux-gnu/cmake" (con symlinks de
# los paquetes Qt6* de QT6_NATIVE_INSTALL adentro). Falló en cadena:
# primero un symlink directo a "KF6Package" cruzado calculaba mal su
# ruta absoluta (KF6PackageToolsTargets.cmake usa un _IMPORT_PREFIX
# calculado navegando ".." un número FIJO de niveles relativo a su
# propia ubicación, asumiendo el layout original de 3 niveles
# "lib/cmake/KF6Package" -- al vivir ahora en 4 niveles
# "lib/x86_64-linux-gnu/cmake/KF6Package" el cálculo daba un path sin
# sentido, "kf6-native-install/lib/bin/kpackagetool6"). Se resolvió
# ESE síntoma puntual con un stub propio (ver más abajo), pero el mismo
# problema de fondo reapareció enseguida con "Qt6::syncqt" (target de
# Qt6CoreTools) -- mismo cálculo de profundidad, mismo tipo de error,
# ahora en un archivo que no es nuestro y no tiene sentido stubear
# (syncqt es interno de la build de Qt, tira de MUCHOS más targets en
# cadena).
#
# 2º intento real, el que quedó: la causa raíz no es "symlink vs
# stub", es que KF6_NATIVE_INSTALL y QT6_NATIVE_INSTALL NO estaban a la
# misma profundidad de directorio (GNUInstallDirs detecta multiarch en
# builds nativos e inserta "x86_64-linux-gnu" -- confirmado en su
# momento con Breeze/kcmutils-native/kconfig-native, pero recién acá
# volvió a importar). Se agregó "-DCMAKE_INSTALL_LIBDIR=lib" a
# step_kconfig_native()/step_kcmutils_native() (ver esos comentarios)
# para que instalen SIN el segmento multiarch, igual que
# QT6_NATIVE_INSTALL -- con las dos profundidades iguales,
# "host_tooling" puede ser directamente QT6_NATIVE_INSTALL/lib/cmake
# (el árbol REAL de Qt6, sin ningún symlink ni cálculo relativo raro) y
# sólo hace falta symlinkear adentro los 2 paquetes de KF6 que de
# verdad existen (KF6Config, KF6KCMUtils) más el stub de KF6Package
# (que sigue haciendo falta: kpackagetool6 nunca se compiló nativo, ver
# el comentario original más abajo).
step_kwin() {
    require_kconfig_native
    require_kcmutils_native
    local host_tooling="${QT6_NATIVE_INSTALL}/lib/cmake"
    mkdir -p "${host_tooling}/KF6Package"
    ln -sf "${KF6_NATIVE_INSTALL}/lib/cmake/KF6Config" "${host_tooling}/KF6Config"
    ln -sf "${KF6_NATIVE_INSTALL}/lib/cmake/KF6KCMUtils" "${host_tooling}/KF6KCMUtils"
    # El symlink de directorio de arriba alcanza para que el include()
    # encuentre el archivo, pero KF6ConfigCompilerTargets.cmake/
    # KF6KCMUtilsToolingTargets.cmake calculan su propio _IMPORT_PREFIX
    # navegando ".." desde SU propia ubicación real (la del symlink,
    # dentro de QT6_NATIVE_INSTALL) -- terminan esperando el binario en
    # "${QT6_NATIVE_INSTALL}/lib/libexec/kf6/...", NO en
    # KF6_NATIVE_INSTALL (donde realmente vive). Error real visto:
    # "the imported target ... references ... qt6-native-install/lib/
    # libexec/kf6/kconfig_compiler_kf6 ... but this file does not
    # exist". Fix: symlinkear los BINARIOS reales (no sólo el
    # directorio cmake) exactamente en el path que ese cálculo espera.
    mkdir -p "${QT6_NATIVE_INSTALL}/lib/libexec/kf6"
    ln -sf "${KCONFIG_NATIVE_TOOL}" "${QT6_NATIVE_INSTALL}/lib/libexec/kf6/kconfig_compiler_kf6"
    ln -sf "${KCMUTILS_NATIVE_TOOL}" "${QT6_NATIVE_INSTALL}/lib/libexec/kf6/kcmdesktopfilegenerator"
    # KF6ConfigCompilerTargets.cmake exporta OTRO target además de
    # kconfig_compiler_kf6: "kconf_update" (migración de configs entre
    # versiones) -- kconfig-native lo compila igual (es parte del mismo
    # CMakeLists.txt), así que ya está disponible, sólo faltaba
    # symlinkearlo también.
    ln -sf "${KF6_NATIVE_INSTALL}/lib/libexec/kf6/kconf_update" "${QT6_NATIVE_INSTALL}/lib/libexec/kf6/kconf_update"
    # kpackagetool6 nunca se compiló nativo (nadie lo había necesitado
    # -- construirlo entero exigiría KArchive+KI18n+KCoreAddons nativos
    # en cadena, sólo para un target que NADA en el build de kwin
    # invoca de verdad). Stub con ruta absoluta ya resuelta -- inmune a
    # cualquier cálculo relativo de profundidad.
    cat > "${host_tooling}/KF6Package/KF6PackageToolsTargets.cmake" <<EOF
# Generado por step_kwin() (build-kde.sh) -- stub mínimo, ver el
# comentario largo arriba de step_kwin() para el porqué.
if(NOT TARGET KF6::kpackagetool6)
    add_executable(KF6::kpackagetool6 IMPORTED)
    set_target_properties(KF6::kpackagetool6 PROPERTIES
        IMPORTED_LOCATION "${LFS_SYSROOT}/usr/bin/kpackagetool6"
    )
endif()
EOF

    _plasma_cmake_build KWin kwin \
        -DKWIN_BUILD_X11=OFF \
        -DKF6_HOST_TOOLING="${host_tooling}"
}
# Paths reales confirmados por el log de instalación (compiló limpio a
# la primera vez que se resolvió toda la cadena de KF6_HOST_TOOLING):
# el binario principal es "kwin_wayland" (NO "kwin" a secas), más
# "kwin_wayland_wrapper" (wrapper real que lo invoca) y los dos helpers
# standalone parcheados (dialoghelper, killer).
step_verify_kwin() {
    log "Verificación: kwin_wayland + helpers en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/bin/kwin_wayland" \
        "${LFS_SYSROOT}/usr/bin/kwin_wayland_wrapper" \
        "${LFS_SYSROOT}/usr/lib/libexec/kwin_dialog_helper" \
        "${LFS_SYSROOT}/usr/lib/libexec/kwin_killer_helper"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de kwin"
    log "OK: kwin completo en el sysroot."
}

# ------------------------------------------------------------------------------
# QCoro6 -- prerequisito real REQUIRED de plasma-workspace
# ("find_package(QCoro6 REQUIRED COMPONENTS Core)", CMakeLists.txt real
# de plasma-workspace 6.7.4). Wrapper de corutinas de C++20 sobre Qt6,
# proyecto independiente (github.com/danvratil/qcoro), sin ningún tren
# de KDE/Qt. CMake plano, sólo pide Qt6 + Threads (confirmado contra su
# CMakeLists.txt real). Se apaga QTWEBSOCKETS (no tenemos qtwebsockets
# compilado y plasma-workspace sólo pide el componente "Core") y
# ejemplos/tests -- se dejan QTDBUS/QTNETWORK/QTQUICK/QML en su default
# (ON) porque esos módulos de Qt6 ya están todos en el sysroot.
step_qcoro() {
    require_toolchain
    log "QCoro6 ${QCORO_VERSION} para ${LFS_TGT} — CMake"

    cd "${LFS_SOURCES}"
    fetch "${QCORO_MIRROR}/v${QCORO_VERSION}.tar.gz" \
          "qcoro-${QCORO_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/qcoro-${QCORO_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/qcoro-${QCORO_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-qcoro-${QCORO_VERSION}"

    local src="${LFS_BUILD}/qcoro-${QCORO_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQCORO_BUILD_EXAMPLES=OFF \
        -DQCORO_BUILD_TESTING=OFF \
        -DQCORO_WITH_QTWEBSOCKETS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "QCoro6 instalado en ${LFS_SYSROOT}/usr"
}
# QCoro se compila como ESTÁTICA por default (".a", no ".so") --
# confirmado por el log real de instalación. _kf6_verify_lib asume
# ".so" bajo lib/, así que se verifica a mano.
step_verify_qcoro() {
    log "Verificación: libQCoro6Core.a en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libQCoro6Core.a"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: QCoro6 completo en el sysroot."
}

# ------------------------------------------------------------------------------
# ICU4C -- prerequisito real REQUIRED de plasma-workspace
# ("find_package(ICU COMPONENTS i18n uc)" + set_package_properties TYPE
# REQUIRED, "Better application groups in Kicker, timezone support").
# Build autotools en DOS pasadas -- documentado oficialmente
# (unicode-org.github.io/icu/userguide/icu4c/build.html): un build
# NATIVO completo primero (ICU necesita sus propias herramientas ya
# compiladas -- genrb, gennorm2, etc. -- para generar datos durante SU
# PROPIO build cruzado, no sólo para correr en el host), después el
# build cruzado real pasando "--with-cross-build=<dir de build nativo
# ABSOLUTO, no instalado>". Ambas pasadas comparten el mismo source
# extraído (build fuera del árbol, soportado nativamente por el
# configure de ICU).
step_icu_native() {
    log "ICU4C ${ICU_VERSION} NATIVO (build completo, para --with-cross-build) — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${ICU_MIRROR}/icu4c-${ICU_VERSION}-sources.tgz" \
          "icu4c-${ICU_VERSION}-sources.tgz"
    log_sha256 "${LFS_SOURCES}/icu4c-${ICU_VERSION}-sources.tgz"
    extract_once "${LFS_SOURCES}/icu4c-${ICU_VERSION}-sources.tgz" \
                 "${LFS_BUILD}/.extracted-icu-${ICU_VERSION}"

    rm -rf "${ICU_NATIVE_BUILD}"
    mkdir -p "${ICU_NATIVE_BUILD}"
    cd "${ICU_NATIVE_BUILD}"
    sh "${LFS_BUILD}/icu/source/runConfigureICU" Linux
    make -j"$(nproc)"

    log "ICU4C NATIVO (build completo) listo en ${ICU_NATIVE_BUILD}"
}
require_icu_native() {
    [[ -x "${ICU_NATIVE_BUILD}/bin/genrb" ]] \
        || die "no está ICU4C NATIVO -- corré primero: scripts/build-kde.sh icu-native"
}

step_icu() {
    require_toolchain
    require_icu_native
    log "ICU4C ${ICU_VERSION} para ${LFS_TGT} — Autotools cruzado (--with-cross-build)"

    local bdir="${LFS_BUILD}/icu-cross-build"
    rm -rf "${bdir}"
    mkdir -p "${bdir}"
    cd "${bdir}"

    # --with-data-packaging=archive: bug real visto en el primer
    # intento ("rm: symbol lookup error: libc.so.6: undefined symbol:
    # __pointer_chk_guard, version GLIBC_PRIVATE") durante "make
    # install" -- el modo por default ("auto", que arma un
    # libicudata.so + symlinks) hace que pkgdata invoque "rm"/"ln" vía
    # system() con un LD_LIBRARY_PATH apuntando al build NATIVO; el
    # crash se reproduce sólo en ESE contexto real (no reproducible
    # corriendo "rm" a mano con el mismo LD_LIBRARY_PATH aislado), así
    # que no vale la pena perseguir la causa exacta dentro de pkgdata.
    # "archive" empaqueta los datos en un único .dat en vez de una
    # librería compartida + symlinks -- evita ese post-proceso entero.
    # No afecta a los consumidores reales (KF6/Qt6 linkean contra
    # libicuuc/libicui18n igual, el empaquetado de datos es interno).
    CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++" \
    sh "${LFS_BUILD}/icu/source/configure" \
        --host="${LFS_TGT}" \
        --with-cross-build="${ICU_NATIVE_BUILD}" \
        --with-data-packaging=archive \
        --prefix=/usr \
        --disable-tests \
        --disable-samples

    # mkdir de "data/out/tmp": bug real de upstream en data/Makefile,
    # confirmado leyéndolo directo (no era una condición de carrera de
    # -j$(nproc) como se creyó en un intento anterior -- el error
    # "/bin/bash: line 1: out/tmp/icudata.lst: No such file or
    # directory" persistía IGUAL en serie con -j1). Causa raíz real: la
    # regla real de "$(PKGDATA_LIST): ..." tiene DOS ramas según
    # "ICUDATA_SOURCE_IS_NATIVE_TARGET" -- la rama "NO nativo" crea
    # $(OUTTMPDIR) antes de escribir; la rama "SÍ nativo" (la que
    # aplica acá, mismo endianness/plataforma que el build nativo) sólo
    # hace "echo \"$@\" > $@" SIN crear el directorio antes -- asume
    # que ya existe de un paso previo que en este build nunca corrió.
    # Se crea a mano antes de "make" en vez de parchear el Makefile
    # generado (efímero, se regenera con cada "configure").
    mkdir -p "${bdir}/data/out/tmp"
    make -j"$(nproc)"
    make install DESTDIR="${LFS_SYSROOT}"

    log "ICU4C instalado en ${LFS_SYSROOT}/usr"
}
step_verify_icu() {
    log "Verificación: libicuuc/libicui18n en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libicuuc.so" \
        "${LFS_SYSROOT}/usr/lib/libicui18n.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de ICU4C"
    log "OK: ICU4C completo en el sysroot."
}

# ------------------------------------------------------------------------------
# 7 frameworks KF6 nuevos, descubiertos recién al correr plasma-workspace
# real (find_package(KF6 ... COMPONENTS ... KDED Parts Prison
# StatusNotifierItem TextEditor TextWidgets Wallet) -- ninguno estaba en
# el mapa original de Tier 2, nunca hizo falta antes). Dependencias
# reales confirmadas contra el CMakeLists.txt real de cada uno (mismo
# tren KDE_VERSION/KDE_FRAMEWORKS_MIRROR de siempre):
#   - KDED, KParts, KWallet: sin dependencias externas nuevas (todo lo
#     que piden ya está en el sysroot) -- listos para compilar tal cual.
#   - KStatusNotifierItem: "find_package(X11)" es opcional (sin
#     REQUIRED) y sólo se evalúa si "NOT APPLE AND NOT WIN32" (cierto
#     para nuestro target Linux) -- se apaga explícito con
#     "-DWITHOUT_X11=ON" por prolijidad, aunque igual auto-desactivaría
#     solo al no encontrar X11 real.
#   - Prison: pide libqrencode SIEMPRE (sin opción para sacarlo) más
#     libdmtx/zxing-cpp si WITH_DMTX/WITH_ZXING (default ON los dos) --
#     se apagan esos dos, se agrega sólo libqrencode.
#   - KTextWidgets y KTextEditor: piden Qt6 TextToSpeech (submódulo
#     qtspeech, nunca compilado). En KTextWidgets es opcional
#     (WITH_TEXT_TO_SPEECH, default ON) pero en KTextEditor es
#     REQUIRED sin ninguna opción para sacarlo -- se compila qtspeech
#     una sola vez y listo, no vale la pena andar apagándolo en el otro.
#   - KTextEditor también pide KSyntaxHighlighting (framework KF6
#     nuevo, resaltado de sintaxis) y KParts (de la lista de arriba,
#     compilar antes) -- y KAuth si ENABLE_KAUTH (default ON en
#     Linux, `if (NOT WIN32 AND NOT HAIKU)` -- cierto para nuestro
#     target) -- se apaga con "-DENABLE_KAUTH=OFF" (integración con
#     polkit para editar archivos de sistema como root, no esencial
#     para un framework de edición de texto).
# Orden de build: qtspeech + libqrencode + KSyntaxHighlighting primero
# (dependencias externas), después KDED/KParts/KWallet/
# KStatusNotifierItem/Prison/KTextWidgets en cualquier orden, KTextEditor
# al final (depende de KParts + KSyntaxHighlighting).
# qtmultimedia -- dependencia OPCIONAL de qtspeech (find_package(Qt6
# ... Multimedia) sin REQUIRED), pero sin ella qtspeech NI SIQUIERA
# configura ningún target ("Skipping the build as the condition
# 'TARGET Qt6::Multimedia' is not met" -- error real visto en el primer
# intento). Sus backends reales (GStreamer/FFmpeg/PipeWire/ALSA) se
# auto-detectan vía "qt_feature()" (no hay ningún find_package()
# REQUIRED de por medio, confirmado leyendo su CMakeLists.txt real) --
# compila igual sin ninguno, sólo con los backends deshabilitados (no
# hace falta audio/video funcional de verdad, sólo que exista el target
# CMake "Qt6::Multimedia" para que qtspeech deje de saltearse).
step_qtmultimedia() {
    require_toolchain
    require_qtbase
    log "Qt6 (qtmultimedia) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtmultimedia-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtmultimedia-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtmultimedia-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtmultimedia-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtmultimedia"

    local src="${LFS_BUILD}/qtmultimedia-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtmultimedia-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtmultimedia instalado en ${LFS_SYSROOT}/usr"
}
step_verify_qtmultimedia() { _kf6_verify_lib qtmultimedia libQt6Multimedia.so; }
require_qtmultimedia() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libQt6Multimedia.so" ]] \
        || die "no está qtmultimedia en el sysroot -- corré primero: scripts/build-kde.sh qtmultimedia"
}

step_qtspeech() {
    require_toolchain
    require_qtbase
    require_qtmultimedia
    log "Qt6 (qtspeech) ${QT6_VERSION} para ${LFS_TGT} — build CRUZADO"

    cd "${LFS_SOURCES}"
    fetch "${QT6_MIRROR}/qtspeech-everywhere-src-${QT6_VERSION}.tar.xz" \
          "qtspeech-everywhere-src-${QT6_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/qtspeech-everywhere-src-${QT6_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/qtspeech-everywhere-src-${QT6_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-qtspeech"

    local src="${LFS_BUILD}/qtspeech-everywhere-src-${QT6_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${LFS_BUILD}/qtspeech-cross-build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DQT_HOST_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "qtspeech instalado en ${LFS_SYSROOT}/usr"
}
step_verify_qtspeech() { _kf6_verify_lib qtspeech libQt6TextToSpeech.so; }

# libqrencode -- dependencia externa REQUIRED real de Prison (generación
# de códigos QR), proyecto independiente (fukuchi/libqrencode en
# GitHub), CMake propio, sin ningún tren de KDE/Qt. Versión real en
# env.sh (LIBQRENCODE_VERSION/LIBQRENCODE_MIRROR).
step_libqrencode() {
    require_toolchain
    log "libqrencode ${LIBQRENCODE_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBQRENCODE_MIRROR}/v${LIBQRENCODE_VERSION}.tar.gz" \
          "libqrencode-${LIBQRENCODE_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libqrencode-${LIBQRENCODE_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libqrencode-${LIBQRENCODE_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libqrencode-${LIBQRENCODE_VERSION}"

    local src="${LFS_BUILD}/libqrencode-${LIBQRENCODE_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    # -DCMAKE_POLICY_VERSION_MINIMUM=3.5: libqrencode 4.1.1 declara
    # "cmake_minimum_required(VERSION" con un mínimo viejo que el CMake
    # moderno (4.x) ya no acepta ("Compatibility with CMake < 3.5 has
    # been removed") -- error real visto en el primer intento, fix
    # sugerido por el propio mensaje de CMake.
    # -DCMAKE_POSITION_INDEPENDENT_CODE=ON: bug real visto al linkear
    # Prison ("relocation R_X86_64_PC32 against symbol ... can not be
    # used when making a shared object; recompile with -fPIC") --
    # libqrencode se compila estática (".a") por default SIN -fPIC, y
    # Prison la linkea DENTRO de su propia librería compartida
    # (libKF6Prison.so) -- cualquier .a que termine dentro de un .so
    # necesita código PIC.
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_TOOLS=OFF \
        -DWITH_TESTS=OFF

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libqrencode instalado en ${LFS_SYSROOT}/usr"
}
# Se instala como ESTÁTICA (".a") por default -- confirmado por el log
# real de instalación, no pasamos BUILD_SHARED_LIBS. Sirve igual para
# que Prison la linkee.
step_verify_libqrencode() {
    log "Verificación: libqrencode.a en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libqrencode.a"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libqrencode completo en el sysroot."
}

step_kded()    { _kf6_cmake_build KDED kded; }
# KDED no instala ninguna librería -- sólo el daemon real
# (confirmado por el log de instalación: "kded6", sin ningún .so).
step_verify_kded() {
    log "Verificación: kded6 en el sysroot"
    local p="${LFS_SYSROOT}/usr/bin/kded6"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: KDED completo en el sysroot."
}

step_kparts()  { _kf6_cmake_build KParts kparts; }
step_verify_kparts() { _kf6_verify_lib KParts libKF6Parts.so; }

# libgpg-error -- dependencia de libgcrypt (releases conjuntas de
# GnuPG). Autotools clásico, cross estándar.
step_libgpgerror() {
    require_toolchain
    log "libgpg-error ${LIBGPGERROR_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBGPGERROR_MIRROR}/libgpg-error-${LIBGPGERROR_VERSION}.tar.bz2" \
          "libgpg-error-${LIBGPGERROR_VERSION}.tar.bz2"
    log_sha256 "${LFS_SOURCES}/libgpg-error-${LIBGPGERROR_VERSION}.tar.bz2"
    extract_once "${LFS_SOURCES}/libgpg-error-${LIBGPGERROR_VERSION}.tar.bz2" \
                 "${LFS_BUILD}/.extracted-libgpg-error-${LIBGPGERROR_VERSION}"

    local src="${LFS_BUILD}/libgpg-error-${LIBGPGERROR_VERSION}"
    cd "${src}"

    CC="${LFS_TGT}-gcc" \
    ./configure --host="${LFS_TGT}" --prefix=/usr --disable-doc

    make -j"$(nproc)"
    make install DESTDIR="${LFS_SYSROOT}"

    log "libgpg-error instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libgpgerror() { _kf6_verify_lib libgpg-error libgpg-error.so; }
require_libgpgerror() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libgpg-error.so" ]] \
        || die "no está libgpg-error en el sysroot -- corré primero: scripts/build-kde.sh libgpgerror"
}

# libgcrypt -- dependencia real REQUIRED de KWallet
# ("kwalletd needs libgcrypt to perform PBKDF2-SHA512 hashing").
step_libgcrypt() {
    require_toolchain
    require_libgpgerror
    log "libgcrypt ${LIBGCRYPT_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBGCRYPT_MIRROR}/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2" \
          "libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2"
    log_sha256 "${LFS_SOURCES}/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2"
    extract_once "${LFS_SOURCES}/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2" \
                 "${LFS_BUILD}/.extracted-libgcrypt-${LIBGCRYPT_VERSION}"

    local src="${LFS_BUILD}/libgcrypt-${LIBGCRYPT_VERSION}"
    cd "${src}"

    CC="${LFS_TGT}-gcc" \
    ./configure --host="${LFS_TGT}" --prefix=/usr \
        --with-gpg-error-prefix="${LFS_SYSROOT}/usr" \
        --disable-doc

    make -j"$(nproc)"
    make install DESTDIR="${LFS_SYSROOT}"

    log "libgcrypt instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libgcrypt() { _kf6_verify_lib libgcrypt libgcrypt.so; }
require_libgcrypt() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libgcrypt.so" ]] \
        || die "no está libgcrypt en el sysroot -- corré primero: scripts/build-kde.sh libgcrypt"
}

# Gpgmepp (GPGME) queda deliberadamente sin construir -- opcional en
# KWallet ("if (Gpgmepp_FOUND)", sin REQUIRED), sólo habilita un backend
# de wallet vía GPG además del backend gcrypt clásico. No hay consumidor
# real que lo exija -- mismo criterio que Union/KNightTime en su momento
# (no se agrega especulativamente).
#
# -DBUILD_KSECRETD=OFF: "ksecretd" (el daemon freedesktop Secret
# Service, alternativo/paralelo al kwalletd clásico) pide
# "find_package(Qca-qt6 REQUIRED 2.3.1)" -- QCA (Qt Cryptographic
# Architecture), otra dependencia externa nueva, real y sin ninguna
# opción para sacarla DEL ksecretd en sí. En vez de agregar QCA (+ lo
# que QCA necesite de plugin de backend), se deshabilita sólo
# ksecretd -- confirmado que "kwalletd" (BUILD_KWALLETD, default ON en
# Linux -- "if(NOT WIN32 AND NOT APPLE)") es un daemon INDEPENDIENTE,
# sin ninguna referencia a QCA en su propio CMakeLists.txt, y sigue
# compilando normal con el libgcrypt que ya construimos (ambos daemons
# comparten "kwalletbackend", que sólo pide libgcrypt). Wallet clásico
# funcional igual, sin agregar QCA especulativamente.
step_libsecret() {
    require_toolchain
    require_libgcrypt
    log "libsecret ${LIBSECRET_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${LIBSECRET_MIRROR}/libsecret-${LIBSECRET_VERSION}.tar.xz" \
          "libsecret-${LIBSECRET_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libsecret-${LIBSECRET_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libsecret-${LIBSECRET_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libsecret-${LIBSECRET_VERSION}"

    local src="${LFS_BUILD}/libsecret-${LIBSECRET_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -Dgtk_doc=false \
        -Dvapi=false \
        -Dintrospection=false \
        -Dmanpage=false

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libsecret instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libsecret() { _kf6_verify_lib libsecret libsecret-1.so; }
require_libsecret() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libsecret-1.so" ]] \
        || die "no está libsecret en el sysroot -- corré primero: scripts/build-kde.sh libsecret"
}

# Bug real de falso negativo en un check de CMake: blowfish.h incluye
# <stdint.h> condicionado a "HAVE_STDINT_H" (de
# check_include_files(stdint.h HAVE_STDINT_H)), pero ese check da
# "not found" en nuestro build cruzado aunque stdint.h obviamente
# existe para cualquier compilador C99+ real (mismo síntoma ya visto,
# sin consecuencia hasta ahora, en otros checks de "check_include_files"
# de este proyecto -- ej. KWin con sys/procctl.h) -- error real:
# "'uint32_t' was not declared in this scope" al compilar blowfish.cc.
# Se saca el guard del todo en vez de perseguir por qué el check de
# CMake da falso negativo -- <stdint.h> siempre existe acá.
_patch_kwallet() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]
old = "#if HAVE_STDINT_H\n#include <stdint.h>\n#endif\n"
new = "#include <stdint.h>\n"
# Mismo bug (falso negativo real de check_include_files(stdint.h) en
# cross) en 2 archivos distintos de kwalletbackend -- blowfish.h
# (primer intento) y sha1.cc (segundo, mismo patrón exacto).
for relpath in ("src/runtime/kwalletbackend/blowfish.h", "src/runtime/kwalletbackend/sha1.cc"):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        sys.exit(f"ERROR: ancla de patch no encontrada o no única en {path} ({count} veces)")
    content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado")
PYEOF
}
step_kwallet() {
    require_libgcrypt
    require_libsecret
    _kf6_cmake_build KWallet kwallet -DBUILD_KSECRETD=OFF
}
step_verify_kwallet() { _kf6_verify_lib KWallet libKF6Wallet.so; }

step_kstatusnotifieritem() { _kf6_cmake_build KStatusNotifierItem kstatusnotifieritem -DWITHOUT_X11=ON; }
step_verify_kstatusnotifieritem() { _kf6_verify_lib KStatusNotifierItem libKF6StatusNotifierItem.so; }

require_libqrencode() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libqrencode.a" ]] \
        || die "no está libqrencode en el sysroot -- corré primero: scripts/build-kde.sh libqrencode"
}
step_prison() {
    require_libqrencode
    _kf6_cmake_build Prison prison -DWITH_DMTX=OFF -DWITH_ZXING=OFF
}
step_verify_prison() { _kf6_verify_lib Prison libKF6Prison.so; }

require_qtspeech() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libQt6TextToSpeech.so" ]] \
        || die "no está qtspeech en el sysroot -- corré primero: scripts/build-kde.sh qtspeech"
}
# Sonnet -- framework KF6 de corrección ortográfica, descubierto recién
# como dependencia real de KTextWidgets ("find_package(KF6Sonnet ...
# REQUIRED)") -- NUNCA se había compilado en este proyecto pese a
# figurar por error como "ya construido" en el mapa mental heredado de
# sesiones anteriores (confirmado que no existe ningún KF6Sonnet* real
# en el sysroot antes de este fix -- lección: no asumir nada de un
# resumen viejo sin confirmarlo contra el sysroot real). Sin
# dependencias externas nuevas (sólo ECM + Qt6 Core/Widgets/Quick, todo
# ya en el sysroot) -- los backends reales de corrección (hunspell/
# aspell) son opcionales y quedan sin construir a propósito (mismo
# criterio que KSecretd/Union/KNightTime: sin consumidor real que exija
# corrección ortográfica funcional todavía). "-DSONNET_NO_BACKENDS=ON"
# evita que falle la build por no encontrar ninguno.
step_sonnet() { _kf6_cmake_build Sonnet sonnet -DSONNET_NO_BACKENDS=ON; }
step_verify_sonnet() { _kf6_verify_lib Sonnet libKF6SonnetCore.so; }
require_sonnet() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libKF6SonnetCore.so" ]] \
        || die "no está Sonnet en el sysroot -- corré primero: scripts/build-kde.sh sonnet"
}

step_ktextwidgets() {
    require_qtspeech
    require_sonnet
    _kf6_cmake_build KTextWidgets ktextwidgets
}
step_verify_ktextwidgets() { _kf6_verify_lib KTextWidgets libKF6TextWidgets.so; }

step_ksyntaxhighlighting() { _kf6_cmake_build KSyntaxHighlighting syntax-highlighting; }
step_verify_ksyntaxhighlighting() { _kf6_verify_lib KSyntaxHighlighting libKF6SyntaxHighlighting.so; }

require_kparts() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libKF6Parts.so" ]] \
        || die "no está KParts en el sysroot -- corré primero: scripts/build-kde.sh kparts"
}
step_ktexteditor() {
    require_qtspeech
    require_kparts
    _kf6_cmake_build KTextEditor ktexteditor -DENABLE_KAUTH=OFF
}
step_verify_ktexteditor() { _kf6_verify_lib KTextEditor libKF6TextEditor.so; }

# libndp -- dependencia real REQUIRED de NetworkManager
# ("dependency('libndp')", sin "required: false"). IPv6 Neighbor
# Discovery Protocol, proyecto chico e independiente
# (github.com/jpirko/libndp). El tarball de GitHub no trae "configure"
# pre-generado -- hace falta "autoreconf" (autoconf/automake/libtool ya
# están en el contenedor).
step_libndp() {
    require_toolchain
    log "libndp ${LIBNDP_VERSION} para ${LFS_TGT} — Autotools (autoreconf)"

    cd "${LFS_SOURCES}"
    fetch "${LIBNDP_MIRROR}/v${LIBNDP_VERSION}.tar.gz" \
          "libndp-${LIBNDP_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libndp-${LIBNDP_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libndp-${LIBNDP_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libndp-${LIBNDP_VERSION}"

    local src="${LFS_BUILD}/libndp-${LIBNDP_VERSION}"
    cd "${src}"

    if [[ ! -x ./configure ]]; then
        autoreconf -fi
    fi

    CC="${LFS_TGT}-gcc" \
    ./configure --host="${LFS_TGT}" --prefix=/usr

    make -j"$(nproc)"
    make install DESTDIR="${LFS_SYSROOT}"

    log "libndp instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libndp() { _kf6_verify_lib libndp libndp.so; }
require_libndp() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libndp.so" ]] \
        || die "no está libndp en el sysroot -- corré primero: scripts/build-kde.sh libndp"
}

# NetworkManager -- dependencia real REQUIRED de KF6NetworkManagerQt
# (libnm>=1.4.0 vía pkg-config). Se compila con el máximo de
# subsistemas opcionales apagados (ver comentario real en env.sh) --
# sólo hace falta "libnm" (la librería cliente) para que
# KF6NetworkManagerQt compile, no un daemon de red del sistema
# funcionando de verdad.
step_networkmanager() {
    require_toolchain
    require_libndp
    log "NetworkManager ${NETWORKMANAGER_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${NETWORKMANAGER_MIRROR}/NetworkManager-${NETWORKMANAGER_VERSION}.tar.xz" \
          "NetworkManager-${NETWORKMANAGER_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/NetworkManager-${NETWORKMANAGER_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/NetworkManager-${NETWORKMANAGER_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-NetworkManager-${NETWORKMANAGER_VERSION}"

    local src="${LFS_BUILD}/NetworkManager-${NETWORKMANAGER_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    # GETTEXTDATADIRS -- bug real: "msgfmt: cannot locate ITS rules for
    # data/org.freedesktop.NetworkManager.policy.in" al mergear
    # traducciones del archivo de polkit (msgfmt --xml necesita un
    # ".loc"/".its" real para saber qué elementos del XML son
    # traducibles). El contenedor tiene los its/loc de gettext para
    # otros esquemas (glade/gsettings/metainfo, confirmado con "dpkg -L
    # gettext-base") pero NINGUNO para el esquema de PolicyKit -- no es
    # parte del paquete "gettext" de Debian, normalmente lo trae
    # polkit/libpolkit-gobject-1-dev, que no existe para bookworm.
    #
    # Dos intentos fallidos antes de este: (1) apuntar
    # "GETTEXTDATADIRS" a un directorio propio -- msgfmt de este
    # gettext (0.21) nunca lo leyó de verdad para resolver its/loc (se
    # confirmó comparando "con" y "sin" la variable seteada: daba
    # exactamente el mismo resultado en ambos casos). (2) copiar el
    # ".loc"/".its" directo a "/usr/share/gettext-0.21/its/" (el
    # directorio real confirmado con "dpkg -L gettext-base") pero con
    # pattern="*.policy.in" -- seguía sin encontrarlo. Comparando contra
    # "metainfo.loc" real (pattern="*.metainfo.xml", SIN ".in" al
    # final, aunque el template real es "*.metainfo.xml.in") se
    # confirmó que msgfmt matchea el pattern CONTRA EL NOMBRE YA SIN EL
    # ".in" final -- variante real que funcionó: "pattern=\"*.policy\"".
    #
    # Fix real: copiar el ".loc"/".its" (mismo formato exacto que
    # "metainfo.loc"/"metainfo.its" ya instalados, confirmado
    # leyéndolos directo -- no adivinado) para el esquema real de
    # PolicyKit ("<policyconfig>", con "action/description" y
    # "action/message" como únicos textos traducibles) directo al
    # directorio real de gettext -- alcanza con que dure sólo esta
    # invocación del contenedor (todo pasa en el mismo proceso que el
    # build real, no hace falta que sobreviva a un "--rm" posterior).
    sudo -n tee /usr/share/gettext-0.21/its/polkit-policy.loc > /dev/null <<'EOF'
<?xml version="1.0"?>
<locatingRules>
  <locatingRule name="PolicyKit Policy" pattern="*.policy">
    <documentRule localName="policyconfig" target="polkit-policy.its"/>
  </locatingRule>
</locatingRules>
EOF
    sudo -n tee /usr/share/gettext-0.21/its/polkit-policy.its > /dev/null <<'EOF'
<?xml version="1.0"?>
<its:rules xmlns:its="http://www.w3.org/2005/11/its" version="2.0">
  <its:translateRule selector="/policyconfig" translate="no"/>
  <its:translateRule selector="/policyconfig/vendor |
                               /policyconfig/action/description |
                               /policyconfig/action/message"
                     translate="yes"/>
</its:rules>
EOF

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -Dppp=false \
        -Dmodem_manager=false \
        -Dovs=false \
        -Dnmtui=false \
        -Dnm_cloud_setup=false \
        -Dtests=no \
        -Ddocs=false \
        -Dintrospection=false \
        -Dvapi=false \
        -Dqt=false \
        -Dcrypto=null \
        -Dlibpsl=false \
        -Dconcheck=false \
        -Dnmcli=false

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "NetworkManager (libnm) instalado en ${LFS_SYSROOT}/usr"
}
step_verify_networkmanager() { _kf6_verify_lib NetworkManager libnm.so; }
require_networkmanager() {
    [[ -e "${LFS_SYSROOT}/usr/lib/libnm.so" ]] \
        || die "no está libnm en el sysroot -- corré primero: scripts/build-kde.sh networkmanager"
}

# KF6NetworkManagerQt -- dependencia real REQUIRED de plasma-workspace
# ("if (LINUX) find_package(KF6NetworkManagerQt ... REQUIRED) endif()"
# -- nuestro target ES Linux de verdad, no un caso de confundir host
# con target). Sin dependencias externas nuevas más allá de libnm (ECM
# + Qt6 Core/DBus/Network/Qml, todo ya en el sysroot). Tarball real:
# "networkmanager-qt" (con guiones, confirmado con un wget real --
# distinto de la convención "knetworkmanagerqt" que se probó primero y
# no existe).
step_knetworkmanagerqt() {
    require_networkmanager
    _kf6_cmake_build KF6NetworkManagerQt networkmanager-qt
}
step_verify_knetworkmanagerqt() { _kf6_verify_lib KF6NetworkManagerQt libKF6NetworkManagerQt.so; }

# ------------------------------------------------------------------------------
# polkit-qt-1 -- dependencia real REQUIRED de plasma-workspace
# ("find_package(PolkitQt6-1)" TYPE REQUIRED, "Communicate with
# localegen helper in region & lang kcm"). Proyecto independiente
# (download.kde.org/stable/polkit-qt-1/, sin carpeta de versión que
# siga KDE_VERSION). Sin dependencias externas nuevas (Qt6 Core/DBus/
# Widgets + polkit-gobject-1 vía pkg-config, todo ya en el sysroot).
step_polkitqt1() {
    require_toolchain
    log "polkit-qt-1 ${POLKITQT1_VERSION} para ${LFS_TGT} — CMake"

    cd "${LFS_SOURCES}"
    fetch "${POLKITQT1_MIRROR}/polkit-qt-1-${POLKITQT1_VERSION}.tar.xz" \
          "polkit-qt-1-${POLKITQT1_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/polkit-qt-1-${POLKITQT1_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/polkit-qt-1-${POLKITQT1_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-polkit-qt-1-${POLKITQT1_VERSION}"

    local src="${LFS_BUILD}/polkit-qt-1-${POLKITQT1_VERSION}"
    local toolchain="${LFS_BUILD}/cmake-cross-linsi.cmake"
    write_cmake_toolchain "${toolchain}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DQT_MAJOR_VERSION=6

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "polkit-qt-1 instalado en ${LFS_SYSROOT}/usr"
}
# Nombre real confirmado por el log de instalación: "libpolkit-qt6-
# core-1.so" (minúsculas, con guiones) -- distinto de mi primera
# suposición ("libPolkitQt6-1-core.so").
step_verify_polkitqt1() { _kf6_verify_lib PolkitQt6-1 libpolkit-qt6-core-1.so; }

# ------------------------------------------------------------------------------
# plasma-workspace (Tier 5, último paquete real de Fase 6 Parte 3) --
# investigado contra el CMakeLists.txt REAL del tarball
# plasma-workspace-6.7.4.tar.xz extraído (46 find_package() reales).
# X11 gateado limpio con 2 options de CMake reales
# (WITH_X11/WITH_X11_SESSION, default ON los dos) -- se apagan los dos,
# mismo criterio de siempre. Todo lo demás REQUIRED ya confirmado en el
# sysroot salvo QCoro6 e ICU4C (agregados recién arriba, más los 18
# prerequisitos reales documentados en docs/PENDIENTES.md).
#
# Bug real de upstream (a diferencia de WITH_X11, que sí está bien
# hecho): "ecm_optional_add_subdirectory(xembed-sni-proxy)" se agrega
# SIEMPRE, sin ningún "if(WITH_X11)" -- ese subdirectorio entero es
# X11 puro (linkea "X11::Xtst" real y pide "find_package(XCB ...
# REQUIRED COMPONENTS AUX XCB CURSOR RANDR IMAGE)" incondicional,
# confirmado leyendo su CMakeLists.txt real) -- es el proxy que hace
# aparecer íconos de bandeja de apps X11 viejas (vía XEmbed) en un
# systray Wayland-nativo, no tiene sentido en un build Wayland puro.
# Error real visto: "Could NOT find XCB (missing: UTIL IMAGE ICCCM)".
_patch_plasma_workspace() {
    local src="$1"
    python3 - "${src}" <<'PYEOF'
import sys

src = sys.argv[1]

def patch_file(relpath, replacements):
    path = f"{src}/{relpath}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    for old, new in replacements:
        count = content.count(old)
        if count == 0:
            sys.exit(f"ERROR: ancla de patch no encontrada en {path}:\n{old!r}")
        if count > 1:
            sys.exit(f"ERROR: ancla de patch no es única en {path} ({count} veces):\n{old!r}")
        content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {path} parcheado ({len(replacements)} reemplazos)")

patch_file("CMakeLists.txt", [
    (
        "ecm_optional_add_subdirectory(xembed-sni-proxy)\n",
        "if(WITH_X11)\n"
        "    ecm_optional_add_subdirectory(xembed-sni-proxy)\n"
        "endif()\n",
    ),
    (
        # gmenu-dbusmenu-proxy (proxy de menú global para apps GTK):
        # a diferencia de appmenu/menuimporter.cpp (que sí tiene guards
        # reales de "isPlatformX11()"), ACÁ el uso de KX11Extras/
        # QX11Info es INCONDICIONAL (constructor: "m_xConnection(QX11Info::
        # connection())"; init(): "connect(KX11Extras::self() ...)" sin
        # ningún check) -- confirmado leyendo menuproxy.cpp real. Es una
        # herramienta 100% X11, nunca adaptada a Wayland -- mismo
        # tratamiento que xembed-sni-proxy (deshabilitar el subdirectorio
        # entero) en vez de intentar parchear lógica de tracking de
        # ventanas que no tiene ningún equivalente real en Wayland acá.
        "ecm_optional_add_subdirectory(gmenu-dbusmenu-proxy)\n",
        "if(WITH_X11)\n"
        "    ecm_optional_add_subdirectory(gmenu-dbusmenu-proxy)\n"
        "endif()\n",
    ),
])

# Cuarto hallazgo real del bug sistémico de X11 en este proyecto (después
# de libplasma/libkscreen/KScreenLocker/kwin), esta vez 4 instancias
# repartidas en 3 subdirectorios distintos -- SIEMPRE el mismo patrón:
# "target_link_libraries(... X11::X11 ...)" incondicional en el
# CMakeLists.txt, mientras el código fuente real (cuando lo toca) SÍ
# está bien guardeado (krdb.cpp: "#if HAVE_X11" real alrededor del
# include Y del uso; shutdowndlg.cpp: ni siquiera incluye Xlib, sólo un
# "KWindowSystem::isPlatformX11()" runtime que gatea código genérico).
# krdb.cpp es el único caso donde el propio archivo YA gatea
# "XCB::XCB XCB::CURSOR" con "if(HAVE_X11)" pero se olvidó de meter
# "X11::X11" en ese mismo bloque -- inconsistencia real de upstream, no
# algo nuestro. Los otros 3 (logout-greeter, plasma-apply-colorscheme,
# plasma_accentcolor_service) ni siquiera necesitan X11::X11 de verdad
# (nada en su código fuente usa Xlib) -- se saca directo.
patch_file("kcms/krdb/CMakeLists.txt", [
    (
        "target_link_libraries(krdb PRIVATE Qt::Widgets Qt::DBus KF6::CoreAddons KF6::DBusAddons KF6::GuiAddons KF6::I18n KF6::WindowSystem KF6::ColorScheme X11::X11 Qt::GuiPrivate)\n",
        "target_link_libraries(krdb PRIVATE Qt::Widgets Qt::DBus KF6::CoreAddons KF6::DBusAddons KF6::GuiAddons KF6::I18n KF6::WindowSystem KF6::ColorScheme Qt::GuiPrivate)\n",
    ),
])

patch_file("logout-greeter/CMakeLists.txt", [
    (
        "    KF6::ConfigCore\n"
        "    X11::X11\n"
        "    LayerShellQt::Interface\n",
        "    KF6::ConfigCore\n"
        "    LayerShellQt::Interface\n",
    ),
])

patch_file("kcms/colors/CMakeLists.txt", [
    (
        "target_link_libraries(plasma-apply-colorscheme\n"
        "    Qt::Core\n"
        "    Qt::DBus\n"
        "    Qt::Gui\n"
        "    Qt::GuiPrivate\n"
        "    KF6::GuiAddons\n"
        "    KF6::KCMUtils\n"
        "    KF6::I18n\n"
        "    KF6::WindowSystem\n"
        "    KF6::DBusAddons\n"
        "    KF6::ColorScheme\n"
        "    PW::KWorkspace\n"
        "    X11::X11\n"
        "    krdb\n"
        ")\n",
        "target_link_libraries(plasma-apply-colorscheme\n"
        "    Qt::Core\n"
        "    Qt::DBus\n"
        "    Qt::Gui\n"
        "    Qt::GuiPrivate\n"
        "    KF6::GuiAddons\n"
        "    KF6::KCMUtils\n"
        "    KF6::I18n\n"
        "    KF6::WindowSystem\n"
        "    KF6::DBusAddons\n"
        "    KF6::ColorScheme\n"
        "    PW::KWorkspace\n"
        "    krdb\n"
        ")\n",
    ),
    (
        "target_link_libraries(plasma_accentcolor_service\n"
        "    Qt::Core\n"
        "    Qt::DBus\n"
        "    Qt::GuiPrivate\n"
        "    KF6::GuiAddons\n"
        "    KF6::KCMUtils\n"
        "    KF6::I18n\n"
        "    KF6::WindowSystem\n"
        "    KF6::ConfigCore\n"
        "    KF6::DBusAddons\n"
        "    KF6::ColorScheme\n"
        "    PW::KWorkspace\n"
        "    X11::X11\n"
        "    krdb\n"
        ")\n",
        "target_link_libraries(plasma_accentcolor_service\n"
        "    Qt::Core\n"
        "    Qt::DBus\n"
        "    Qt::GuiPrivate\n"
        "    KF6::GuiAddons\n"
        "    KF6::KCMUtils\n"
        "    KF6::I18n\n"
        "    KF6::WindowSystem\n"
        "    KF6::ConfigCore\n"
        "    KF6::DBusAddons\n"
        "    KF6::ColorScheme\n"
        "    PW::KWorkspace\n"
        "    krdb\n"
        ")\n",
    ),
])

# Quinto hallazgo real del bug sistémico de X11: "appmenu/
# menuimporter.cpp" incluye "<KWindowInfo>" sin guard, pero ese header
# NI SIQUIERA EXISTE en nuestro sysroot -- "kwindowinfo.cpp"/
# "KWindowInfo" están DENTRO del bloque "if(KWINDOWSYSTEM_X11)" del
# CMakeLists.txt real de KWindowSystem (Tier 2, ya cerrado hace
# semanas) junto con kkeyserver.cpp/kx11extras.cpp/netwm.cpp -- mismo
# grupo de símbolos X11-only ya documentado (ver KKeyServer/netwm.h en
# KScreenLocker). El único uso real está detrás de
# "KWindowSystem::isPlatformX11()" (siempre false) y es un filtro
# opcional (saltear el registro de menús contextuales en X11) -- sin
# "else" que preservar, en Wayland simplemente sigue de largo. Se saca
# el include y el bloque completo.
patch_file("appmenu/menuimporter.cpp", [
    (
        "#include <KWindowInfo>\n"
        "#include <KWindowSystem>\n",
        "#include <KWindowSystem>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KWindowInfo info(id, NET::WMWindowType, NET::WM2WindowClass);\n"
        "        NET::WindowTypes mask = NET::AllTypesMask;\n"
        "        auto type = info.windowType(mask);\n"
        "\n"
        "        // Menu can try to register, right click in gimp for example\n"
        "        if (type != NET::Unknown && (type & (NET::Menu | NET::DropdownMenu | NET::PopupMenu))) {\n"
        "            return;\n"
        "        }\n"
        "        m_windowClasses.insert(id, QString::fromLocal8Bit(info.windowClassClass()));\n"
        "    }\n"
        "\n",
        "",
    ),
])

# Sexto hallazgo real del bug sistémico de X11: "libtaskmanager/
# virtualdesktopinfo.cpp" -- a diferencia de todos los casos anteriores,
# ACÁ el propio archivo YA hace las cosas bien en su mayoría: la clase
# "XWindowPrivate" completa y el selector real (XWindowPrivate en X11,
# WaylandPrivate si no) están perfectamente envueltos en
# "#if HAVE_X11 ... #endif". DOS problemas reales, encontrados en dos
# intentos:
# 1. "#include <KX11Extras>" sin guard -- error real: "KX11Extras: No
#    such file or directory". Primer intento de fix: envolverlo en el
#    lugar donde estaba (junto a KWindowSystem, arriba del todo) --
#    falló con OTRO error real: "HAVE_X11 is not defined, evaluates to
#    0 [-Werror=undef]" (el proyecto compila con -Werror=undef) -- el
#    macro HAVE_X11 recién se define más abajo, vía
#    "#include <config-X11.h>". Fix real: mover el include guardeado a
#    donde YA existe un bloque real "#if HAVE_X11 ... #endif" para
#    "netwm.h" (después de config-X11.h), en vez de dejarlo donde
#    estaba.
# 2. El namespace "X11Info" (definido en este mismo archivo, no es un
#    header externo) llama
#    "qGuiApp->nativeInterface<QNativeInterface::QX11Application>()"
#    SIN ningún guard -- ese tipo sólo existe si Qt6Gui se compiló CON
#    soporte X11/xcb real (FEATURE_xcb=ON), que este proyecto apagó a
#    propósito -- error real: "'QX11Application' is not a member of
#    'QNativeInterface'". Sólo se usa dentro de métodos de
#    XWindowPrivate (ya guardeados) -- se envuelve el namespace entero.
patch_file("libtaskmanager/virtualdesktopinfo.cpp", [
    (
        "#include <KLocalizedString>\n"
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KLocalizedString>\n"
        "#include <KWindowSystem>\n",
    ),
    (
        "#if HAVE_X11\n"
        "#include <netwm.h>\n"
        "#endif // HAVE_X11\n"
        "\n"
        "namespace X11Info\n"
        "{\n"
        "[[nodiscard]] inline auto connection()\n"
        "{\n"
        "    return qGuiApp->nativeInterface<QNativeInterface::QX11Application>()->connection();\n"
        "}\n"
        "}\n",
        "#if HAVE_X11\n"
        "#include <KX11Extras>\n"
        "#include <netwm.h>\n"
        "\n"
        "namespace X11Info\n"
        "{\n"
        "[[nodiscard]] inline auto connection()\n"
        "{\n"
        "    return qGuiApp->nativeInterface<QNativeInterface::QX11Application>()->connection();\n"
        "}\n"
        "}\n"
        "#endif // HAVE_X11\n",
    ),
])

# Séptimo hallazgo: "libnotificationmanager/server.cpp" incluye
# "<KStartupInfo>" sin guard -- mismo grupo de símbolos X11-only de
# KWindowSystem que KWindowInfo/KKeyServer/netwm.h (kstartupinfo.cpp
# vive en el mismo bloque "if(KWINDOWSYSTEM_X11)" de Tier 2, ya
# confirmado antes). Uso real: "if (isPlatformWayland()) {...} else {
# KStartupInfoId startupId; ...}" -- como isPlatformWayland() siempre
# da true acá, la rama X11 (el "else") es código muerto real. Se saca
# el include y el "else" entero, dejando sólo la rama Wayland
# (incondicional -- ya no hace falta el "if" tampoco).
patch_file("libnotificationmanager/server.cpp", [
    (
        "#include <KStartupInfo>\n"
        "#include <KWaylandExtras>\n",
        "#include <KWaylandExtras>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformWayland()) {\n"
        "        auto tokenFuture = KWaylandExtras::xdgActivationToken(window, xdgActivationAppId);\n"
        "        tokenFuture.then(this, [this, actionName, notificationId, behavior](const QString &token) {\n"
        "            Q_EMIT d->ActivationToken(notificationId, token);\n"
        "            Q_EMIT d->ActionInvoked(notificationId, actionName);\n"
        "            if (behavior & Notifications::Close) {\n"
        "                Q_EMIT d->CloseNotification(notificationId);\n"
        "            }\n"
        "        });\n"
        "    } else {\n"
        "        KStartupInfoId startupId;\n"
        "        startupId.initId();\n"
        "\n"
        "        Q_EMIT d->ActivationToken(notificationId, QString::fromUtf8(startupId.id()));\n"
        "\n"
        "        Q_EMIT d->ActionInvoked(notificationId, actionName);\n"
        "        if (behavior & Notifications::Close) {\n"
        "            Q_EMIT d->CloseNotification(notificationId);\n"
        "        }\n"
        "    }\n"
        "}\n",
        "    auto tokenFuture = KWaylandExtras::xdgActivationToken(window, xdgActivationAppId);\n"
        "    tokenFuture.then(this, [this, actionName, notificationId, behavior](const QString &token) {\n"
        "        Q_EMIT d->ActivationToken(notificationId, token);\n"
        "        Q_EMIT d->ActionInvoked(notificationId, actionName);\n"
        "        if (behavior & Notifications::Close) {\n"
        "            Q_EMIT d->CloseNotification(notificationId);\n"
        "        }\n"
        "    });\n"
        "}\n",
    ),
])

# Octavo hallazgo: el mismo bug sistémico apareció repartido en MUCHOS
# más archivos de los esperados en plasma-workspace (11 detectados de
# una sola vez corriendo "ninja -k0" para juntar todos los errores
# reales en una sola pasada, en vez de uno a la vez) -- confirma que
# plasma-workspace (el shell completo: panel, escritorio, klipper,
# krunner, dashboard) tiene MUCHA más superficie de código dual X11/
# Wayland que kwin/kscreenlocker. Mismo patrón en todos: símbolos de
# KWindowSystem X11-only (KX11Extras/KStartupInfo/KUserTimestamp/
# netwm.h) sin guard de include, uso real siempre detrás de
# "isPlatformX11()"/"!isPlatformWayland()" (con la lógica Wayland real
# preservada donde había un "else" de verdad).
patch_file("applets/kicker/windowsystem.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowSystem>\n",
    ),
    (
        "        if (auto window = item->window(); KWindowSystem::isPlatformX11() && window) {\n"
        "            KX11Extras::forceActiveWindow(window->winId());\n"
        "        }\n",
        "",
    ),
])

patch_file("klipper/urlgrabber.cpp", [
    (
        "#include <netwm.h>\n"
        "\n"
        "#include \"klipper_debug.h\"\n",
        "#include \"klipper_debug.h\"\n",
    ),
])

patch_file("libnotificationmanager/portal_p.cpp", [
    (
        "#include <KStartupInfo>\n"
        "#include <KWaylandExtras>\n",
        "#include <KWaylandExtras>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformWayland()) {\n"
        "        KWaylandExtras::xdgActivationToken(window, appId).then(this, [activateWithPlatformData](const QString &token) {\n"
        "            activateWithPlatformData({\n"
        "                {u\"activation-token\"_s, token},\n"
        "            });\n"
        "        });\n"
        "    } else {\n"
        "        KStartupInfoId startupId;\n"
        "        startupId.initId();\n"
        "        activateWithPlatformData({\n"
        "            {u\"desktop-startup-id\"_s, QString::fromUtf8(startupId.id())},\n"
        "        });\n"
        "    }\n"
        "}\n",
        "    KWaylandExtras::xdgActivationToken(window, appId).then(this, [activateWithPlatformData](const QString &token) {\n"
        "        activateWithPlatformData({\n"
        "            {u\"activation-token\"_s, token},\n"
        "        });\n"
        "    });\n"
        "}\n",
    ),
])

# soliduiserver.cpp -- único caso donde KX11Extras YA estaba bien
# guardeado ("#if HAVE_X11" real) pero "KUserTimestamp" (mismo grupo de
# símbolos X11-only de KWindowSystem) se coló sin guard, con una
# llamada final INCONDICIONAL ("KUserTimestamp::updateUserTimestamp();"
# fuera de cualquier if) -- se guardea con el mismo criterio que ya usa
# el propio archivo para KX11Extras.
patch_file("soliduiserver/soliduiserver.cpp", [
    (
        "#include <KLocalizedString>\n"
        "#include <KPluginFactory>\n"
        "#include <KUserTimestamp>\n",
        "#include <KLocalizedString>\n"
        "#include <KPluginFactory>\n",
    ),
    (
        "#if HAVE_X11\n"
        "#include <KX11Extras>\n"
        "#endif\n",
        "#if HAVE_X11\n"
        "#include <KUserTimestamp>\n"
        "#include <KX11Extras>\n"
        "#endif\n",
    ),
    (
        "    // allow dialog activation even if it interrupts, better than trying hacks\n"
        "    // with keeping the dialog on top or on all desktops\n"
        "    KUserTimestamp::updateUserTimestamp();\n"
        "}\n",
        "    // allow dialog activation even if it interrupts, better than trying hacks\n"
        "    // with keeping the dialog on top or on all desktops\n"
        "#if HAVE_X11\n"
        "    KUserTimestamp::updateUserTimestamp();\n"
        "#endif\n"
        "}\n",
    ),
])

patch_file("applets/kicker/dashboardwindow.cpp", [
    (
        "#include <KWindowEffects>\n"
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowEffects>\n"
        "#include <KWindowSystem>\n",
    ),
    (
        "        showFullScreen();\n"
        "        if (KWindowSystem::isPlatformX11()) {\n"
        "            KX11Extras::forceActiveWindow(winId());\n"
        "        }\n"
        "    }\n"
        "}\n",
        "        showFullScreen();\n"
        "    }\n"
        "}\n",
    ),
    (
        "            if (KWindowSystem::isPlatformX11()) {\n"
        "                KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "            }\n",
        "",
    ),
    (
        "    } else if (event->type() == QEvent::FocusOut && KWindowSystem::isPlatformX11() && isVisible()) {\n"
        "        KX11Extras::forceActiveWindow(winId());\n"
        "    }\n"
        "\n"
        "    return QQuickWindow::event(event);",
        "    }\n"
        "\n"
        "    return QQuickWindow::event(event);",
    ),
])

patch_file("klipper/klipperpopup.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowSystem>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        const QRect screenGeometry = screen()->geometry();\n"
        "        QRect popupGeometry(position(), popupSize);\n"
        "        if (!screenGeometry.contains(popupGeometry)) {\n"
        "            popupGeometry.moveTo(std::clamp(x(), screenGeometry.left(), screenGeometry.right() - popupSize.width()),\n"
        "                                 std::clamp(y(), screenGeometry.top(), screenGeometry.bottom() - popupSize.height()));\n"
        "        }\n"
        "        setGeometry(popupGeometry);\n"
        "    } else {\n"
        "        resize(popupSize);\n"
        "    }\n"
        "}\n",
        "    resize(popupSize);\n"
        "}\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setOnAllDesktops(winId(), true);\n"
        "    }\n"
        "    PlasmaWindow::showEvent(event); // NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher\n"
        "    requestActivate();\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::forceActiveWindow(winId());\n"
        "    }\n"
        "}\n",
        "    PlasmaWindow::showEvent(event); // NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher\n"
        "    requestActivate();\n"
        "}\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        auto screenIt = std::ranges::find_if(screens, [](QScreen *screen) {\n"
        "            return screen->geometry().contains(QCursor::pos(screen));\n"
        "        });\n"
        "        QScreen *const shownOnScreen = screenIt != screens.cend() ? *screenIt : QGuiApplication::primaryScreen();\n"
        "        setPosition(QCursor::pos(shownOnScreen));\n"
        "        setScreen(shownOnScreen);\n"
        "        KX11Extras::setOnDesktop(winId(), KX11Extras::currentDesktop());\n"
        "    } else if (m_plasmashell && KWindowSystem::isPlatformWayland()) {\n",
        "    if (m_plasmashell && KWindowSystem::isPlatformWayland()) {\n",
    ),
])

patch_file("logout-greeter/shutdowndlg.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n"
        "#include <LayerShellQt/Window>\n",
        "#include <KWindowSystem>\n"
        "#include <LayerShellQt/Window>\n",
    ),
    (
        "#include <cstdio>\n"
        "#include <netwm.h>\n"
        "\n"
        "#include <X11/Xatom.h>\n"
        "#include <X11/Xutil.h>\n"
        "#include <fixx11h.h>\n"
        "\n"
        "#include <debug.h>\n",
        "#include <cstdio>\n"
        "\n"
        "#include <debug.h>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        constexpr auto role = std::string_view(\"logoutdialog\");\n"
        "        constexpr std::size_t roleLength = role.length();\n"
        "\n"
        "        auto x11App = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();\n"
        "        XChangeProperty(x11App->display(),\n"
        "                        winId(),\n"
        "                        XInternAtom(x11App->display(), \"WM_WINDOW_ROLE\", False),\n"
        "                        XA_STRING,\n"
        "                        8,\n"
        "                        PropModeReplace,\n"
        "                        reinterpret_cast<const unsigned char *>(role.data()),\n"
        "                        roleLength);\n"
        "\n"
        "        XClassHint classHint;\n"
        "        classHint.res_name = const_cast<char *>(\"ksmserver-logout-greeter\");\n"
        "        classHint.res_class = const_cast<char *>(\"ksmserver-logout-greeter\");\n"
        "        XSetClassHint(x11App->display(), winId(), &classHint);\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);\n"
        "    }\n",
        "",
    ),
])

# desktopview.cpp: además del patrón de siempre, dos usos de
# "qGuiApp->nativeInterface<QNativeInterface::QX11Application>()" como
# CONDICIÓN (no "isPlatformX11()") -- ese TIPO no existe si Qt6 se
# compiló sin soporte X11 (nuestro caso, FEATURE_xcb=OFF) -- es un
# error de COMPILACIÓN (el argumento de template no existe), no algo
# que dependa del valor en runtime. Mismo tratamiento: sacar el bloque
# completo (ambas instancias son código muerto de todos modos, real
# sólo tras iniciar sesión X11 real).
patch_file("shell/desktopview.cpp", [
    (
        "#include <KAuthorized>\n"
        "#include <KStartupInfo>\n"
        "#include <KWaylandExtras>\n"
        "#include <KX11Extras>\n",
        "#include <KAuthorized>\n"
        "#include <KWaylandExtras>\n",
    ),
    (
        "    } else {\n"
        "        KX11Extras::setType(winId(), NET::Desktop);\n"
        "        KX11Extras::setState(winId(), NET::KeepBelow);\n"
        "    }\n",
        "    }\n",
    ),
    (
        "            m_configView->hide();\n"
        "            m_configView->deleteLater();\n"
        "        } else {\n"
        "            m_configView->show();\n"
        "            auto window = qobject_cast<QWindow *>(m_configView);\n"
        "            if (window && qGuiApp->nativeInterface<QNativeInterface::QX11Application>()) {\n"
        "                KStartupInfo::setNewStartupId(window, qgetenv(\"DESKTOP_STARTUP_ID\"));\n"
        "            }\n"
        "            m_configView->requestActivate();\n"
        "            return;\n"
        "        }\n",
        "            m_configView->hide();\n"
        "            m_configView->deleteLater();\n"
        "        } else {\n"
        "            m_configView->show();\n"
        "            m_configView->requestActivate();\n"
        "            return;\n"
        "        }\n",
    ),
    (
        "    auto window = qobject_cast<QWindow *>(m_configView);\n"
        "    if (window && qGuiApp->nativeInterface<QNativeInterface::QX11Application>()) {\n"
        "        KStartupInfo::setNewStartupId(window, qgetenv(\"DESKTOP_STARTUP_ID\"));\n"
        "    }\n"
        "    m_configView->requestActivate();\n"
        "}\n"
        "\n"
        "void DesktopView::slotContainmentChanged()\n",
        "    m_configView->requestActivate();\n"
        "}\n"
        "\n"
        "void DesktopView::slotContainmentChanged()\n",
    ),
])

patch_file("applets/notifications/notificationapplet.cpp", [
    (
        "#include <KX11Extras>\n",
        "#include \"config-X11.h\"\n"
        "#include <KWindowSystem>\n"
        "#if HAVE_X11\n"
        "#include <KX11Extras>\n"
        "#endif // HAVE_X11\n",
    ),
    (
        "    if (window && window->winId()) {\n"
        "        KX11Extras::forceActiveWindow(window->winId());\n"
        "    }\n",
        "#if HAVE_X11\n"
        "    if (window && window->winId() && KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::forceActiveWindow(window->winId());\n"
        "    }\n"
        "#endif // HAVE_X11\n",
    ),
])

patch_file("applets/notifications/notificationwindow.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowSystem>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setOnAllDesktops(winId(), true);\n"
        "        KX11Extras::setType(winId(), NET::Notification);\n"
        "    }\n",
        "",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setType(winId(), critical ? NET::CriticalNotification : NET::Notification);\n"
        "    }\n",
        "",
    ),
])

# krunner/view.cpp: "x11windowscreenrelativepositioner.{h,cpp}" (la
# clase real que usa este archivo) está TOTALMENTE limpia -- no
# necesita ningún símbolo faltante para compilar (confirmado leyéndola
# entera: sólo un "if (!isPlatformX11()) return;" real adentro). El
# único problema es, de nuevo, el propio view.cpp.
patch_file("krunner/view.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowSystem>\n",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        m_x11Positioner = new X11WindowScreenRelativePositioner(this);\n"
        "    }\n",
        "",
    ),
    (
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::setOnAllDesktops(winId(), true);\n"
        "    }\n"
        "    QQuickWindow::showEvent(event);\n"
        "    requestActivate();\n"
        "    if (KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::forceActiveWindow(winId());\n"
        "    }\n"
        "}\n",
        "    QQuickWindow::showEvent(event);\n"
        "    requestActivate();\n"
        "}\n",
    ),
    (
        "    } else if (KWindowSystem::isPlatformX11()) {\n"
        "        screenIt = std::ranges::find_if(screens, [](QScreen *screen) {\n"
        "            return screen->geometry().contains(QCursor::pos(screen));\n"
        "        });\n"
        "    }\n",
        "    }\n",
    ),
    (
        "    } else if (KWindowSystem::isPlatformX11()) {\n"
        "        m_x11Positioner->setAnchors(Qt::TopEdge);\n"
        "        m_x11Positioner->setMargins(margins());\n"
        "        if (m_floating) {\n"
        "            KX11Extras::setOnDesktop(winId(), KX11Extras::currentDesktop());\n"
        "        } else {\n"
        "            KX11Extras::setOnAllDesktops(winId(), true);\n"
        "        }\n"
        "        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager);\n"
        "    }\n"
        "}\n",
        "    }\n"
        "}\n",
    ),
    (
        "    if (isVisible() && !QGuiApplication::focusWindow() && KWindowSystem::isPlatformX11()) {\n"
        "        KX11Extras::forceActiveWindow(winId());\n"
        "        return;\n"
        "    }\n",
        "",
    ),
])

# shellcorona.cpp: los 2 usos reales ya están bien guardeados con
# "#if HAVE_X11 ... #endif" -- sólo faltaba el include.
patch_file("shell/shellcorona.cpp", [
    (
        "#include <KWindowSystem>\n"
        "#include <KX11Extras>\n",
        "#include <KWindowSystem>\n"
        "#if HAVE_X11\n"
        "#include <KX11Extras>\n"
        "#endif // HAVE_X11\n",
    ),
])

# panelview.cpp: "integrateScreen()" y "canSetStrut()" YA están bien
# guardeados con "#if HAVE_X11" real (este último incluso usa
# "qGuiApp->nativeInterface<QNativeInterface::QX11Application>()"
# adentro -- inofensivo porque con HAVE_X11=0 el preprocesador saca
# ese bloque ENTERO antes de que el compilador lo vea). Dos problemas
# reales nuevos: el include de siempre, y una expresión booleana suelta
# ("!isPlatformX11() || KX11Extras::compositingActive()", FUERA de
# cualquier bloque "if" real) -- como "!isPlatformX11()" siempre da
# true acá, el "||" nunca llega a evaluar el lado derecho en runtime
# (cortocircuito) -- sacar esa mitad no cambia el comportamiento real,
# sólo saca el símbolo que no compila.
patch_file("shell/panelview.cpp", [
    (
        "#include <KLocalizedString>\n"
        "#include <KX11Extras>\n"
        "#include <kwindowsystem.h>\n",
        "#include <KLocalizedString>\n"
        "#include <kwindowsystem.h>\n"
        "#if HAVE_X11\n"
        "#include <KX11Extras>\n"
        "#endif // HAVE_X11\n",
    ),
    (
        "    if (!KWindowSystem::isPlatformX11() || KX11Extras::compositingActive()) {\n",
        "    if (!KWindowSystem::isPlatformX11()) {\n",
    ),
    (
        "        showTemporarily();\n"
        "        setFlags(flags() | Qt::WindowDoesNotAcceptFocus);\n"
        "        if (KWindowSystem::isPlatformX11()) {\n"
        "            KX11Extras::setState(winId(), NET::SkipSwitcher | NET::KeepAbove);\n"
        "        }\n"
        "        if (m_layerWindow) {\n"
        "            m_layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);\n"
        "            requestUpdate();\n"
        "        }\n"
        "    } else if (status == Plasma::Types::AcceptingInputStatus) {\n",
        "        showTemporarily();\n"
        "        setFlags(flags() | Qt::WindowDoesNotAcceptFocus);\n"
        "        if (m_layerWindow) {\n"
        "            m_layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);\n"
        "            requestUpdate();\n"
        "        }\n"
        "    } else if (status == Plasma::Types::AcceptingInputStatus) {\n",
    ),
    (
        "        if (KWindowSystem::isPlatformX11()) {\n"
        "            KX11Extras::forceActiveWindow(winId());\n"
        "        } else {\n"
        "            showTemporarily();\n"
        "        }\n",
        "        showTemporarily();\n",
    ),
    (
        "        restoreAutoHide();\n"
        "        setFlags(flags() | Qt::WindowDoesNotAcceptFocus);\n"
        "        if (KWindowSystem::isPlatformX11()) {\n"
        "            KX11Extras::setState(winId(), NET::SkipSwitcher | NET::KeepAbove);\n"
        "        }\n",
        "        restoreAutoHide();\n"
        "        setFlags(flags() | Qt::WindowDoesNotAcceptFocus);\n",
    ),
])

print("OK: plasma-workspace parcheado (xembed-sni-proxy, gmenu-dbusmenu-proxy, krdb, logout-greeter, colors, appmenu, virtualdesktopinfo, server, windowsystem, urlgrabber, portal_p, soliduiserver, dashboardwindow, klipperpopup, desktopview, notificationapplet, notificationwindow, krunner-view, shellcorona, panelview)")
PYEOF
}
step_plasma_workspace() {
    _plasma_cmake_build PlasmaWorkspace plasma-workspace \
        -DWITH_X11=OFF \
        -DWITH_X11_SESSION=OFF
}
# Verify con rutas reales confirmadas post-instalación (2026-09-16). Nota:
# Plasma 6 NO instala un binario "ksmserver" standalone -- la gestión de
# sesión se hizo cargo "plasma_session"/"startplasma-wayland" (confirmado
# con "find" real contra el sysroot recién instalado; sólo aparece
# "ksmserver-logout-greeter" en libexec y el .notifyrc, nada más).
step_verify_plasma_workspace() {
    log "Verificación: plasma-workspace en el sysroot"
    for f in plasmashell krunner plasma_session startplasma-wayland; do
        [[ -x "${LFS_SYSROOT}/usr/bin/${f}" ]] || die "Falta ${LFS_SYSROOT}/usr/bin/${f}"
    done
    [[ -x "${LFS_SYSROOT}/usr/lib/libexec/ksmserver-logout-greeter" ]] \
        || die "Falta ${LFS_SYSROOT}/usr/lib/libexec/ksmserver-logout-greeter"
    log "OK: plasmashell, krunner, plasma_session, startplasma-wayland, ksmserver-logout-greeter"
}

# ------------------------------------------------------------------------------
# KCMUtils -- framework de KDE Frameworks (KDE_VERSION 6.29.0, mismo tren
# que Tier 2, NO Plasma) descubierto recién como dependencia real de
# Aurorae (Tier 3) -- nunca apareció en el mapa original de Tier 2.
# Dependencias reales confirmadas contra su CMakeLists.txt
# (invent.kde.org/frameworks/kcmutils): ECM; Qt6 Widgets/Qml/Quick/
# QuickWidgets/Test + Qt6DBus; KF6 KIO/ItemViews/ConfigWidgets/
# CoreAddons/GuiAddons/I18n/XmlGui/WidgetsAddons + Kirigami (QML) --
# TODAS ya en el sysroot. Target real: "KF6KCMUtilsCore" (confirmado
# contra src/core/CMakeLists.txt real).
#
# Bug real encontrado recién al compilar Breeze (el primer consumidor
# real): KCMUtils instala "kcmdesktopfilegenerator" (genera .desktop
# desde JSON de metadata) en ${LFS_SYSROOT}/usr/lib/libexec/kf6/ -- un
# binario CRUZADO que Breeze invoca en TIEMPO DE BUILD para generar sus
# propios .desktop. Mismo problema de fondo de siempre (binario cruzado
# no corre en el contenedor -- acá literal "error while loading shared
# libraries: libQt6Core.so.6"). A diferencia de BreezeIcons, KCMUtils NO
# tiene un mecanismo KF6_HOST_TOOLING propio (confirmado contra su
# CMakeLists.txt real: no hay ningún "CMAKE_CROSSCOMPILING" ahí) -- pero
# SÍ tiene una opción "TOOLS_ONLY" real (`if (TOOLS_ONLY): find_package
# (Qt6 REQUIRED Core); add_subdirectory(tools); return()`), perfecta para
# un build nativo mínimo. Fix: compilar kcmutils-native con
# -DTOOLS_ONLY=ON (sólo pide Qt6::Core) y PISAR el binario cruzado roto
# del sysroot con el nativo -- mismo patrón exacto que llvm-config
# (Fase 6 Parte 2) y spa-json-dump (Fase 6 Parte 1), sólo que acá alcanza
# con copiar el binario, no hace falta tocar RPATH con patchelf.
# ------------------------------------------------------------------------------
step_kcmutils_native() {
    require_qtbase_native
    log "KCMUtils ${KDE_VERSION} NATIVO (sólo kcmdesktopfilegenerator, -DTOOLS_ONLY=ON) — CMake"

    cd "${LFS_SOURCES}"
    fetch "${KDE_FRAMEWORKS_MIRROR}/kcmutils-${KDE_VERSION}.tar.xz" \
          "kcmutils-${KDE_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/kcmutils-${KDE_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/kcmutils-${KDE_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-kcmutils-native-${KDE_VERSION}"

    local src="${LFS_BUILD}/kcmutils-${KDE_VERSION}"
    local bdir="${KF6_NATIVE_BUILD}/kcmutils"
    rm -rf "${bdir}"

    cmake -S "${src}" -B "${bdir}" -G Ninja \
        -DCMAKE_PREFIX_PATH="${QT6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_PREFIX="${KF6_NATIVE_INSTALL}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DTOOLS_ONLY=ON

    ninja -C "${bdir}" ${MAKEFLAGS}
    ninja -C "${bdir}" install

    log "KCMUtils NATIVO (kcmdesktopfilegenerator) instalado en ${KF6_NATIVE_INSTALL}"
}

# GNUInstallDirs detecta multiarch en el build NATIVO (contenedor
# Debian) e inserta "x86_64-linux-gnu" en el libdir por default -- la
# cruzada no lo hace. Originalmente esta ruta SÍ tenía el segmento
# multiarch (confirmado en su momento con la línea real "Installing:"
# del build nativo) -- se agregó "-DCMAKE_INSTALL_LIBDIR=lib" recién
# el 2026-09-16 (retrofit real, ver comentario largo en
# KCONFIG_NATIVE_TOOL más arriba y en step_kwin()) para alinear el
# layout de KF6_NATIVE_INSTALL con el de QT6_NATIVE_INSTALL (sin
# multiarch) -- lo necesitaba KF6_HOST_TOOLING de kwin.
KCMUTILS_NATIVE_TOOL="${KF6_NATIVE_INSTALL}/lib/libexec/kf6/kcmdesktopfilegenerator"

step_verify_kcmutils_native() {
    log "Verificación: kcmdesktopfilegenerator NATIVO"
    [[ -x "${KCMUTILS_NATIVE_TOOL}" ]] || die "no está ${KCMUTILS_NATIVE_TOOL}"
    echo "  [OK] ${KCMUTILS_NATIVE_TOOL}"
    log "OK: kcmutils NATIVO completo."
}

require_kcmutils_native() {
    [[ -x "${KCMUTILS_NATIVE_TOOL}" ]] \
        || die "no está kcmdesktopfilegenerator NATIVO -- corré primero: scripts/build-kde.sh kcmutils-native"
}

step_kcmutils() {
    require_kcmutils_native
    _kf6_cmake_build KCMUtils kcmutils
    # Pisar el binario cruzado (roto en el contenedor) con el nativo.
    cp -f "${KCMUTILS_NATIVE_TOOL}" \
          "${LFS_SYSROOT}/usr/lib/libexec/kf6/kcmdesktopfilegenerator"
    log "kcmdesktopfilegenerator del sysroot pisado con la versión NATIVA"
}
step_verify_kcmutils() { _kf6_verify_lib KCMUtils libKF6KCMUtilsCore.so; }

# aurorae -- motor de temas de decoración de ventanas "descargables de
# internet" para kwin (RUNTIME opcional para kwin, no REQUIRED -- pero
# entra por el alcance "todo desde el principio"). Dependencias reales
# confirmadas contra su CMakeLists.txt (invent.kde.org/plasma/aurorae):
# ECM; Qt6 Core/DBus/Quick/UiTools/Widgets; KF6 ColorScheme/Config/
# CoreAddons/I18n/KCMUtils/NewStuff/Package/Svg (KCMUtils recién agregado
# arriba, el resto ya en el sysroot); KDecoration3 (recién compilado).
# Produce un PLUGIN de KDecoration3, no una librería con nombre estable
# para linkear -- verify pendiente de confirmar contra el install real.
step_aurorae() { _plasma_cmake_build Aurorae aurorae; }
# Verify contra la ruta real confirmada tras el install (no una búsqueda
# genérica): "org.kde.kwin.aurorae.so" es el plugin real de KDecoration3
# (v1), instalado en /usr/lib/plugins/org.kde.kdecoration3/ -- confirmado
# leyendo las líneas "Installing:" reales del log de este mismo build.
# breeze -- el tema de decoración/estilo POR DEFECTO de kwin (RUNTIME
# opcional real para kwin, "For setting the default window decoration
# plugin" -- confirmado antes contra el CMakeLists.txt real de kwin).
# DISTINTO de breeze-icons (ya compilado en Tier 2c) -- éste es el motor
# de decoración de ventanas + widget style + tema de cursor, no íconos.
# Dependencias reales confirmadas contra su CMakeLists.txt
# (invent.kde.org/plasma/breeze): ECM; Qt6 Widgets/Core/Svg; KF6
# CoreAddons/ColorScheme/Config/GuiAddons/I18n/IconThemes/WindowSystem +
# KDecoration3 (WITH_DECORATIONS) + KCMUtils -- todas ya en el sysroot.
# BLOQUEANTE real encontrado ANTES de correr el build (no necesitó una
# vuelta fallida): este proyecto compila Qt5 Y Qt6 por default
# (`BUILD_QT5=ON`, `BUILD_QT6=ON`) -- este proyecto no tiene Qt5 en
# absoluto (Qt6 puro). Se fuerza `-DBUILD_QT5=OFF` explícito.
step_breeze() { _plasma_cmake_build Breeze breeze -DBUILD_QT5=OFF; }
# Ruta real confirmada tras el install (no el nombre adivinado
# "breezedecoration.so"): el plugin real se llama "org.kde.breeze.so",
# mismo esquema de nombres que "org.kde.kwin.aurorae.so" de Aurorae.
step_verify_breeze() {
    log "Verificación: plugin de decoración Breeze en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/plugins/org.kde.kdecoration3/org.kde.breeze.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: Breeze completo en el sysroot."
}

step_verify_aurorae() {
    log "Verificación: plugin de Aurorae en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/plugins/org.kde.kdecoration3/org.kde.kwin.aurorae.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: Aurorae completo en el sysroot."
}

step_verify_kirigami_addons() {
    log "Verificación: KF6KirigamiAddonsConfig.cmake en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/cmake/KF6KirigamiAddons/KF6KirigamiAddonsConfig.cmake"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: KirigamiAddons completo en el sysroot."
}

# ------------------------------------------------------------------------------
# libnl y lm-sensors -- dos prerequisitos REQUIRED reales de libksysguard
# encontrados investigando su CMakeLists.txt (invent.kde.org/plasma/
# libksysguard): "NL" (netlink, para leer sockets vía sock_diag) y
# "Sensors" (lm-sensors, para sensores de hardware). Ninguno de los dos
# estaba en el sysroot -- todo lo demás que pide (KF6 CoreAddons/Config/
# I18n/Auth/Service/Package/NewStuff/Solid, ZLIB, Libdrm, UDev, Libcap)
# ya estaba compilado desde fases anteriores.
# ------------------------------------------------------------------------------

# libnl -- Autotools estándar, mismo patrón de siempre.
step_libnl() {
    require_toolchain
    log "libnl ${LIBNL_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LIBNL_MIRROR}/libnl-${LIBNL_VERSION}.tar.gz" \
          "libnl-${LIBNL_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libnl-${LIBNL_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libnl-${LIBNL_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libnl-${LIBNL_VERSION}"

    local src="${LFS_BUILD}/libnl-${LIBNL_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static \
        --disable-cli

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'libnl*.la' -delete 2>/dev/null || true

    log "libnl instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libnl() {
    log "Verificación: libnl-3.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libnl-3.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libnl completo en el sysroot."
}

# lm-sensors -- Makefile plano propio (NI autotools NI CMake NI Meson,
# confirmado leyendo el Makefile real: "CC := gcc", sin ningún
# "--host=" de por medio) -- se cross-compila pisando CC/AR por línea de
# comandos, mismo criterio de fondo que "--host=" en otros lados
# (decirle al build system qué compilador usar), sólo que acá la forma
# de decírselo es distinta. PREFIX=/usr + DESTDIR de siempre. El tag real
# de GitHub es "V3-6-2" (con mayúscula), pero el archive SÍ pisa esa "V"
# al armar el directorio (confirmado real, contra la suposición inicial
# de que sólo la "v" minúscula se pisaba) -- extrae a "lm-sensors-3-6-2/",
# no "lm-sensors-V3-6-2/".
step_lmsensors() {
    require_toolchain
    log "lm-sensors ${LMSENSORS_VERSION} para ${LFS_TGT} — Makefile plano"

    cd "${LFS_SOURCES}"
    fetch "${LMSENSORS_MIRROR}/V${LMSENSORS_VERSION//./-}.tar.gz" \
          "lm-sensors-${LMSENSORS_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/lm-sensors-${LMSENSORS_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/lm-sensors-${LMSENSORS_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-lm-sensors-${LMSENSORS_VERSION}"

    local src="${LFS_BUILD}/lm-sensors-${LMSENSORS_VERSION//./-}"
    cd "${src}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    make ${MAKEFLAGS} \
        CC="${LFS_TGT}-gcc" \
        AR="${LFS_TGT}-ar" \
        PREFIX=/usr

    make DESTDIR="${LFS_SYSROOT}" \
        CC="${LFS_TGT}-gcc" \
        AR="${LFS_TGT}-ar" \
        PREFIX=/usr \
        install

    log "lm-sensors instalado en ${LFS_SYSROOT}/usr"
}
step_verify_lmsensors() {
    log "Verificación: libsensors.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libsensors.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: lm-sensors completo en el sysroot."
}

# libksysguard -- dependencias reales confirmadas contra su
# CMakeLists.txt (invent.kde.org/plasma/libksysguard): ECM; Qt6
# DBus/Network/Widgets/Qml/Quick; KF6 CoreAddons/Config/I18n/Auth/
# Service/Package/NewStuff/Solid; ZLIB/Libdrm/UDev/Libcap (todos ya en el
# sysroot desde fases anteriores); NL y Sensors (recién compilados
# arriba). "libpcap" (RECOMMENDED, no REQUIRED, sólo para medir uso de
# red por aplicación) se deja afuera a propósito por ahora -- mismo
# criterio que VA-API/NVK/glvnd en Mesa (Fase 6 Parte 2): no se agrega
# scope opcional sin que algo lo pida como REQUIRED. Target real:
# confirmar contra el install real (no asumir un nombre).
step_libksysguard() { _plasma_cmake_build KSysGuard libksysguard; }
# No hay un único "libKSysGuard.so" real (placeholder inicial
# equivocado) -- el proyecto produce varias librerías separadas
# (Formatter, procesos, sensores, caras de sensores, systemstats).
# Verify contra las 3 más centrales, confirmadas reales tras el install.
step_verify_libksysguard() {
    log "Verificación: librerías principales de KSysGuard en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libKSysGuardSensors.so" \
        "${LFS_SYSROOT}/usr/lib/libKSysGuardSystemStats.so" \
        "${LFS_SYSROOT}/usr/lib/libprocesscore.so"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de libksysguard en el sysroot"
    log "OK: KSysGuard completo en el sysroot."
}

# ------------------------------------------------------------------------------
# Prerequisitos reales de kwin (Tier 5) descubiertos investigando su
# CMakeLists.txt real (invent.kde.org/plasma/kwin). Con
# KWIN_BUILD_X11=OFF (decisión ya tomada), estos 5 son los únicos que
# faltan -- todo lo demás que kwin pide ya está compilado desde fases
# anteriores.
# ------------------------------------------------------------------------------

# libepoxy -- Meson, sin dependencias obligatorias (EGL/GL/X11 opcionales
# vía dependency(..., required: false)). Se apagan X11/GLX explícito
# (decisión Wayland puro) y se deja EGL prendido (lo necesita kwin real).
step_libepoxy() {
    require_toolchain
    log "libepoxy ${LIBEPOXY_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${LIBEPOXY_MIRROR}/${LIBEPOXY_VERSION}.tar.gz" \
          "libepoxy-${LIBEPOXY_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/libepoxy-${LIBEPOXY_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/libepoxy-${LIBEPOXY_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-libepoxy-${LIBEPOXY_VERSION}"

    local src="${LFS_BUILD}/libepoxy-${LIBEPOXY_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -Dx11=false \
        -Dglx=no \
        -Degl=yes

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libepoxy instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libepoxy() {
    log "Verificación: libepoxy.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libepoxy.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libepoxy completo en el sysroot."
}

# lcms2 -- Autotools estándar, tarball real de "make dist".
step_lcms2() {
    require_toolchain
    log "lcms2 ${LCMS2_VERSION} para ${LFS_TGT} — Autotools"

    cd "${LFS_SOURCES}"
    fetch "${LCMS2_MIRROR}/lcms2-${LCMS2_VERSION}.tar.gz" \
          "lcms2-${LCMS2_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/lcms2-${LCMS2_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/lcms2-${LCMS2_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-lcms2-${LCMS2_VERSION}"

    local src="${LFS_BUILD}/lcms2-${LCMS2_VERSION}"
    local bdir="${src}/build"
    mkdir -p "${bdir}"
    cd "${bdir}"

    PKG_CONFIG_LIBDIR="${LFS_SYSROOT}/usr/lib/pkgconfig:${LFS_SYSROOT}/usr/share/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}" \
    ../configure \
        --host="${LFS_TGT}" \
        --build="$(build_triplet)" \
        --prefix=/usr \
        --disable-static

    make ${MAKEFLAGS}
    make DESTDIR="${LFS_SYSROOT}" install
    find "${LFS_SYSROOT}/usr/lib" -maxdepth 1 -name 'liblcms2*.la' -delete 2>/dev/null || true

    log "lcms2 instalado en ${LFS_SYSROOT}/usr"
}
step_verify_lcms2() {
    log "Verificación: liblcms2.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/liblcms2.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: lcms2 completo en el sysroot."
}

# hwdata -- prerequisito real REQUIRED de libdisplay-info (necesita
# /usr/share/hwdata/pnp.ids para resolver nombres de fabricantes desde
# EDID), descubierto recién en un intento real de build. Pura data
# (pci.ids/usb.ids/pnp.ids), sin código que compilar -- Makefile propio
# con un ./configure real (script shell custom, no autoconf; "prefix=/usr"
# ya es el default, no hace falta pasarlo). Nada de --host= ni CC= --
# no hay ningún compilador de por medio.
step_hwdata() {
    require_toolchain
    log "hwdata ${HWDATA_VERSION} — Makefile (sólo datos, sin compilar)"

    cd "${LFS_SOURCES}"
    fetch "${HWDATA_MIRROR}/v${HWDATA_VERSION}.tar.gz" \
          "hwdata-${HWDATA_VERSION}.tar.gz"
    log_sha256 "${LFS_SOURCES}/hwdata-${HWDATA_VERSION}.tar.gz"
    extract_once "${LFS_SOURCES}/hwdata-${HWDATA_VERSION}.tar.gz" \
                 "${LFS_BUILD}/.extracted-hwdata-${HWDATA_VERSION}"

    local src="${LFS_BUILD}/hwdata-${HWDATA_VERSION}"
    cd "${src}"

    ./configure --prefix=/usr
    make DESTDIR="${LFS_SYSROOT}" install

    # Segunda instalación NATIVA -- bug real encontrado al compilar
    # libdisplay-info: pide hwdata con "dependency('hwdata', required:
    # false, native: true)" (confirmado contra el meson.build real), es
    # decir consulta el pkg-config NATIVO (del contenedor), no el del
    # sysroot cruzado -- porque pnp.ids ahí sólo se usa en TIEMPO DE BUILD
    # (genera una tabla C embebida vía un script python, nunca se linkea
    # en runtime). Instalar directo en el filesystem del contenedor NO
    # sirve -- cada "podman-compose run --rm" es efímero, se perdería en
    # la corrida siguiente. Se instala en cambio bajo ${LFS_BUILD}
    # (volumen con nombre, persiste entre corridas), mismo criterio ya
    # usado para QT6_NATIVE_INSTALL/KF6_NATIVE_INSTALL -- el consumidor
    # (libdisplay-info) apunta PKG_CONFIG_PATH ahí.
    make clean 2>/dev/null || true
    ./configure --prefix="${HWDATA_NATIVE_INSTALL}"
    make install

    log "hwdata instalado en ${LFS_SYSROOT}/usr y en ${HWDATA_NATIVE_INSTALL} (nativo, persistente)"
}
step_verify_hwdata() {
    log "Verificación: pnp.ids en el sysroot y en el prefix nativo"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/share/hwdata/pnp.ids" \
        "${HWDATA_NATIVE_INSTALL}/share/hwdata/pnp.ids"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de hwdata"
    log "OK: hwdata completo (sysroot + nativo)."
}

# libdisplay-info -- Meson, sin dependencias.
require_hwdata_native() {
    [[ -e "${HWDATA_NATIVE_INSTALL}/share/hwdata/pnp.ids" ]] \
        || die "no está hwdata NATIVO -- corré primero: scripts/build-kde.sh hwdata"
}

step_libdisplayinfo() {
    require_toolchain
    require_hwdata_native
    log "libdisplay-info ${LIBDISPLAYINFO_VERSION} para ${LFS_TGT} — Meson+Ninja"

    cd "${LFS_SOURCES}"
    fetch "${LIBDISPLAYINFO_MIRROR}/libdisplay-info-${LIBDISPLAYINFO_VERSION}.tar.xz" \
          "libdisplay-info-${LIBDISPLAYINFO_VERSION}.tar.xz"
    log_sha256 "${LFS_SOURCES}/libdisplay-info-${LIBDISPLAYINFO_VERSION}.tar.xz"
    extract_once "${LFS_SOURCES}/libdisplay-info-${LIBDISPLAYINFO_VERSION}.tar.xz" \
                 "${LFS_BUILD}/.extracted-libdisplay-info-${LIBDISPLAYINFO_VERSION}"

    local src="${LFS_BUILD}/libdisplay-info-${LIBDISPLAYINFO_VERSION}"
    cd "${src}"

    local crossfile="${LFS_BUILD}/meson-cross-linsi.ini"
    write_meson_crossfile "${crossfile}"

    local bdir="${src}/build"
    rm -rf "${bdir}"

    # Native-file real (no simplemente exportar PKG_CONFIG_PATH) -- bug
    # real encontrado: en un build CRUZADO, Meson NO hereda
    # PKG_CONFIG_PATH del shell para resolver dependencias "native: true"
    # (confirmado con un pkg-config real fuera de Meson, que SÍ encuentra
    # hwdata.pc con esa misma variable -- así que el problema es
    # específicamente cómo Meson arma el entorno para el pkg-config de la
    # "build machine", no pkg-config en sí). El mecanismo real y
    # sancionado de Meson para esto es `pkg_config_path` en
    # `[built-in options]` de un --native-file.
    local nativefile="${LFS_BUILD}/meson-native-linsi.ini"
    cat > "${nativefile}" <<EOF
[built-in options]
pkg_config_path = ['${HWDATA_NATIVE_INSTALL}/share/pkgconfig']
EOF

    meson setup "${bdir}" \
        --cross-file="${crossfile}" \
        --native-file="${nativefile}" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release

    ninja -C "${bdir}" ${MAKEFLAGS}
    DESTDIR="${LFS_SYSROOT}" ninja -C "${bdir}" install

    log "libdisplay-info instalado en ${LFS_SYSROOT}/usr"
}
step_verify_libdisplayinfo() {
    log "Verificación: libdisplay-info.so en el sysroot"
    local p="${LFS_SYSROOT}/usr/lib/libdisplay-info.so"
    [[ -e "${p}" ]] || die "no está ${p}"
    echo "  [OK] ${p}"
    log "OK: libdisplay-info completo en el sysroot."
}

# kglobalacceld -- REQUIRED real por kwin (find_package(KGlobalAccelD
# REQUIRED) si KWIN_BUILD_GLOBALSHORTCUTS=ON, default ON). NO es parte
# del framework KF6GlobalAccel (ya compilado) -- es su propio paquete del
# tren de Plasma (invent.kde.org/plasma/kglobalacceld, tarball real
# confirmado en el listado de download.kde.org/stable/plasma/6.7.4/).
# Dependencias reales confirmadas contra su CMakeLists.txt: ECM; Qt6
# DBus/Gui; KF6 Config/CoreAddons/GlobalAccel/Service/KIO/JobWidgets --
# todas ya en el sysroot. A diferencia de lo que sugiere el nombre
# "Daemon", no produce un ejecutable sino una librería/plugin
# (`add_library(KGlobalAccelD ...)`, confirmado contra src/CMakeLists.txt
# real) -- verify pendiente de confirmar contra el install real.
step_kglobalacceld() { _plasma_cmake_build KGlobalAccelD kglobalacceld; }
# Produce TANTO la librería (libKGlobalAccelD.so) COMO el daemon real
# (libexec/kglobalacceld) -- confirmado contra el install real, corrige
# la suposición inicial de que era sólo una librería.
step_verify_kglobalacceld() {
    log "Verificación: librería + daemon de KGlobalAccelD en el sysroot"
    local ok=1
    local p
    for p in \
        "${LFS_SYSROOT}/usr/lib/libKGlobalAccelD.so.0" \
        "${LFS_SYSROOT}/usr/lib/libexec/kglobalacceld"
    do
        if [[ -e "${p}" ]]; then echo "  [OK] ${p}"; else echo "  [FALTA] ${p}"; ok=0; fi
    done
    [[ "${ok}" -eq 1 ]] || die "falta algo de KGlobalAccelD"
    log "OK: KGlobalAccelD completo en el sysroot."
}

main() {
    local target="${1:-all}"
    case "${target}" in
        ecm)                      step_ecm ;;
        verify-ecm)               step_verify_ecm ;;
        qtbase-native)            step_qtbase_native ;;
        verify-qtbase-native)     step_verify_qtbase_native ;;
        qtshadertools-native)         step_qtshadertools_native ;;
        verify-qtshadertools-native)  step_verify_qtshadertools_native ;;
        qtsvg-native)                 step_qtsvg_native ;;
        verify-qtsvg-native)          step_verify_qtsvg_native ;;
        qtdeclarative-native)         step_qtdeclarative_native ;;
        verify-qtdeclarative-native)  step_verify_qtdeclarative_native ;;
        qtbase)                   step_qtbase ;;
        verify-qtbase)            step_verify_qtbase ;;
        qtshadertools)            step_qtshadertools ;;
        verify-qtshadertools)     step_verify_qtshadertools ;;
        qtdeclarative)            step_qtdeclarative ;;
        verify-qtdeclarative)     step_verify_qtdeclarative ;;
        qtsvg)                    step_qtsvg ;;
        verify-qtsvg)             step_verify_qtsvg ;;
        qt5compat)                step_qt5compat ;;
        verify-qt5compat)         step_verify_qt5compat ;;
        qttools-native)               step_qttools_native ;;
        verify-qttools-native)        step_verify_qttools_native ;;
        qttools)                  step_qttools ;;
        verify-qttools)           step_verify_qttools ;;
        qtwayland)                step_qtwayland ;;
        verify-qtwayland)         step_verify_qtwayland ;;
        isocodes)                     step_isocodes ;;
        verify-isocodes)              step_verify_isocodes ;;
        plasma-wayland-protocols)         step_plasma_wayland_protocols ;;
        verify-plasma-wayland-protocols)  step_verify_plasma_wayland_protocols ;;
        kcodecs)                  step_kcodecs ;;
        verify-kcodecs)           step_verify_kcodecs ;;
        kitemviews)               step_kitemviews ;;
        verify-kitemviews)        step_verify_kitemviews ;;
        kitemmodels)              step_kitemmodels ;;
        verify-kitemmodels)       step_verify_kitemmodels ;;
        kcoreaddons)              step_kcoreaddons ;;
        verify-kcoreaddons)       step_verify_kcoreaddons ;;
        kconfig-native)           step_kconfig_native ;;
        verify-kconfig-native)    step_verify_kconfig_native ;;
        kconfig)                  step_kconfig ;;
        verify-kconfig)           step_verify_kconfig ;;
        kwidgetsaddons)           step_kwidgetsaddons ;;
        verify-kwidgetsaddons)    step_verify_kwidgetsaddons ;;
        ki18n)                    step_ki18n ;;
        verify-ki18n)             step_verify_ki18n ;;
        kdbusaddons)              step_kdbusaddons ;;
        verify-kdbusaddons)       step_verify_kdbusaddons ;;
        zstd)                     step_zstd ;;
        verify-zstd)              step_verify_zstd ;;
        liblzma)                  step_liblzma ;;
        verify-liblzma)           step_verify_liblzma ;;
        karchive)                 step_karchive ;;
        verify-karchive)          step_verify_karchive ;;
        kglobalaccel)             step_kglobalaccel ;;
        verify-kglobalaccel)      step_verify_kglobalaccel ;;
        kguiaddons)               step_kguiaddons ;;
        verify-kguiaddons)        step_verify_kguiaddons ;;
        kidletime)                step_kidletime ;;
        verify-kidletime)         step_verify_kidletime ;;
        kwindowsystem)            step_kwindowsystem ;;
        verify-kwindowsystem)     step_verify_kwindowsystem ;;
        kcolorscheme)             step_kcolorscheme ;;
        verify-kcolorscheme)      step_verify_kcolorscheme ;;
        kauth)                    step_kauth ;;
        verify-kauth)             step_verify_kauth ;;
        kcrash)                   step_kcrash ;;
        verify-kcrash)            step_verify_kcrash ;;
        kcompletion)              step_kcompletion ;;
        verify-kcompletion)       step_verify_kcompletion ;;
        kconfigwidgets)           step_kconfigwidgets ;;
        verify-kconfigwidgets)    step_verify_kconfigwidgets ;;
        kservice)                 step_kservice ;;
        verify-kservice)          step_verify_kservice ;;
        kpackage)                 step_kpackage ;;
        verify-kpackage)          step_verify_kpackage ;;
        libltdl)                  step_libltdl ;;
        verify-libltdl)           step_verify_libltdl ;;
        libogg)                   step_libogg ;;
        verify-libogg)            step_verify_libogg ;;
        libvorbis)                step_libvorbis ;;
        verify-libvorbis)         step_verify_libvorbis ;;
        libcanberra)              step_libcanberra ;;
        verify-libcanberra)       step_verify_libcanberra ;;
        knotifications)           step_knotifications ;;
        verify-knotifications)    step_verify_knotifications ;;
        breezeicons-native)           step_breezeicons_native ;;
        verify-breezeicons-native)    step_verify_breezeicons_native ;;
        breezeicons)              step_breezeicons ;;
        verify-breezeicons)       step_verify_breezeicons ;;
        kiconthemes)              step_kiconthemes ;;
        verify-kiconthemes)       step_verify_kiconthemes ;;
        kdeclarative)             step_kdeclarative ;;
        verify-kdeclarative)      step_verify_kdeclarative ;;
        krunner)                  step_krunner ;;
        verify-krunner)           step_verify_krunner ;;
        kxmlgui)                  step_kxmlgui ;;
        verify-kxmlgui)           step_verify_kxmlgui ;;
        kirigami)                 step_kirigami ;;
        verify-kirigami)          step_verify_kirigami ;;
        ksvg)                     step_ksvg ;;
        verify-ksvg)              step_verify_ksvg ;;
        kbookmarks)               step_kbookmarks ;;
        verify-kbookmarks)        step_verify_kbookmarks ;;
        kjobwidgets)              step_kjobwidgets ;;
        verify-kjobwidgets)       step_verify_kjobwidgets ;;
        solid)                    step_solid ;;
        verify-solid)             step_verify_solid ;;
        kio)                      step_kio ;;
        verify-kio)               step_verify_kio ;;
        attica)                   step_attica ;;
        verify-attica)            step_verify_attica ;;
        knewstuff)                step_knewstuff ;;
        verify-knewstuff)         step_verify_knewstuff ;;
        plasma-activities)            step_plasma_activities ;;
        verify-plasma-activities)     step_verify_plasma_activities ;;
        plasma-activities-stats)        step_plasma_activities_stats ;;
        verify-plasma-activities-stats) step_verify_plasma_activities_stats ;;
        xorgproto)                step_xorgproto ;;
        verify-xorgproto)         step_verify_xorgproto ;;
        libxau)                   step_libxau ;;
        verify-libxau)            step_verify_libxau ;;
        libxdmcp)                 step_libxdmcp ;;
        verify-libxdmcp)          step_verify_libxdmcp ;;
        xcbproto)                 step_xcbproto ;;
        verify-xcbproto)          step_verify_xcbproto ;;
        libxcb)                   step_libxcb ;;
        verify-libxcb)            step_verify_libxcb ;;
        libplasma)                step_libplasma ;;
        verify-libplasma)         step_verify_libplasma ;;
        kwayland)                 step_kwayland ;;
        verify-kwayland)          step_verify_kwayland ;;
        layer-shell-qt)           step_layer_shell_qt ;;
        verify-layer-shell-qt)    step_verify_layer_shell_qt ;;
        kirigami-addons)          step_kirigami_addons ;;
        verify-kirigami-addons)   step_verify_kirigami_addons ;;
        libkscreen)               step_libkscreen ;;
        verify-libkscreen)        step_verify_libkscreen ;;
        kdecoration)              step_kdecoration ;;
        verify-kdecoration)       step_verify_kdecoration ;;
        kcmutils-native)          step_kcmutils_native ;;
        verify-kcmutils-native)   step_verify_kcmutils_native ;;
        kcmutils)                 step_kcmutils ;;
        verify-kcmutils)          step_verify_kcmutils ;;
        aurorae)                  step_aurorae ;;
        verify-aurorae)           step_verify_aurorae ;;
        breeze)                   step_breeze ;;
        verify-breeze)            step_verify_breeze ;;
        libnl)                    step_libnl ;;
        verify-libnl)             step_verify_libnl ;;
        lmsensors)                step_lmsensors ;;
        verify-lmsensors)         step_verify_lmsensors ;;
        libksysguard)             step_libksysguard ;;
        verify-libksysguard)      step_verify_libksysguard ;;
        libepoxy)                 step_libepoxy ;;
        verify-libepoxy)          step_verify_libepoxy ;;
        lcms2)                    step_lcms2 ;;
        verify-lcms2)             step_verify_lcms2 ;;
        hwdata)                   step_hwdata ;;
        verify-hwdata)            step_verify_hwdata ;;
        libdisplayinfo)           step_libdisplayinfo ;;
        verify-libdisplayinfo)    step_verify_libdisplayinfo ;;
        kglobalacceld)            step_kglobalacceld ;;
        verify-kglobalacceld)     step_verify_kglobalacceld ;;
        kscreenlocker)            step_kscreenlocker ;;
        verify-kscreenlocker)     step_verify_kscreenlocker ;;
        vulkan-headers)           step_vulkan_headers ;;
        verify-vulkan-headers)    step_verify_vulkan_headers ;;
        vulkan-loader)            step_vulkan_loader ;;
        verify-vulkan-loader)     step_verify_vulkan_loader ;;
        libxcvt)                  step_libxcvt ;;
        verify-libxcvt)           step_verify_libxcvt ;;
        qtpositioning)            step_qtpositioning ;;
        verify-qtpositioning)     step_verify_qtpositioning ;;
        kholidays)                step_kholidays ;;
        verify-kholidays)         step_verify_kholidays ;;
        knighttime)               step_knighttime ;;
        verify-knighttime)        step_verify_knighttime ;;
        kwin)                     step_kwin ;;
        verify-kwin)              step_verify_kwin ;;
        qcoro)                    step_qcoro ;;
        verify-qcoro)             step_verify_qcoro ;;
        icu-native)               step_icu_native ;;
        icu)                      step_icu ;;
        verify-icu)               step_verify_icu ;;
        qtlocation)               step_qtlocation ;;
        verify-qtlocation)        step_verify_qtlocation ;;
        qtmultimedia)             step_qtmultimedia ;;
        verify-qtmultimedia)      step_verify_qtmultimedia ;;
        qtspeech)                 step_qtspeech ;;
        verify-qtspeech)          step_verify_qtspeech ;;
        libqrencode)              step_libqrencode ;;
        verify-libqrencode)       step_verify_libqrencode ;;
        kded)                     step_kded ;;
        verify-kded)              step_verify_kded ;;
        kparts)                   step_kparts ;;
        verify-kparts)            step_verify_kparts ;;
        libgpgerror)              step_libgpgerror ;;
        verify-libgpgerror)       step_verify_libgpgerror ;;
        libgcrypt)                step_libgcrypt ;;
        verify-libgcrypt)         step_verify_libgcrypt ;;
        libsecret)                step_libsecret ;;
        verify-libsecret)         step_verify_libsecret ;;
        kwallet)                  step_kwallet ;;
        verify-kwallet)           step_verify_kwallet ;;
        kstatusnotifieritem)      step_kstatusnotifieritem ;;
        verify-kstatusnotifieritem) step_verify_kstatusnotifieritem ;;
        prison)                   step_prison ;;
        verify-prison)            step_verify_prison ;;
        sonnet)                   step_sonnet ;;
        verify-sonnet)            step_verify_sonnet ;;
        ktextwidgets)             step_ktextwidgets ;;
        verify-ktextwidgets)      step_verify_ktextwidgets ;;
        ksyntaxhighlighting)      step_ksyntaxhighlighting ;;
        verify-ksyntaxhighlighting) step_verify_ksyntaxhighlighting ;;
        ktexteditor)              step_ktexteditor ;;
        verify-ktexteditor)       step_verify_ktexteditor ;;
        libndp)                   step_libndp ;;
        verify-libndp)            step_verify_libndp ;;
        networkmanager)           step_networkmanager ;;
        verify-networkmanager)    step_verify_networkmanager ;;
        knetworkmanagerqt)        step_knetworkmanagerqt ;;
        verify-knetworkmanagerqt) step_verify_knetworkmanagerqt ;;
        polkitqt1)                step_polkitqt1 ;;
        verify-polkitqt1)         step_verify_polkitqt1 ;;
        plasma-workspace)         step_plasma_workspace ;;
        verify-plasma-workspace)  step_verify_plasma_workspace ;;
        all)
            step_ecm;              step_verify_ecm
            step_qtbase_native;    step_verify_qtbase_native
            step_qtshadertools_native; step_verify_qtshadertools_native
            step_qtsvg_native;     step_verify_qtsvg_native
            step_qtdeclarative_native; step_verify_qtdeclarative_native
            step_qtbase;           step_verify_qtbase
            step_qtshadertools;    step_verify_qtshadertools
            step_qtdeclarative;    step_verify_qtdeclarative
            step_qtsvg;            step_verify_qtsvg
            step_qt5compat;        step_verify_qt5compat
            step_qttools_native;   step_verify_qttools_native
            step_qttools;          step_verify_qttools
            step_qtwayland;        step_verify_qtwayland
            step_isocodes;         step_verify_isocodes
            step_plasma_wayland_protocols; step_verify_plasma_wayland_protocols
            step_kcodecs;          step_verify_kcodecs
            step_kitemviews;       step_verify_kitemviews
            step_kitemmodels;      step_verify_kitemmodels
            step_kcoreaddons;      step_verify_kcoreaddons
            step_kconfig_native;   step_verify_kconfig_native
            step_kconfig;          step_verify_kconfig
            step_kwidgetsaddons;   step_verify_kwidgetsaddons
            step_ki18n;            step_verify_ki18n
            step_kdbusaddons;      step_verify_kdbusaddons
            step_zstd;             step_verify_zstd
            step_liblzma;          step_verify_liblzma
            step_karchive;         step_verify_karchive
            step_kglobalaccel;     step_verify_kglobalaccel
            step_kguiaddons;       step_verify_kguiaddons
            step_kidletime;        step_verify_kidletime
            step_kwindowsystem;    step_verify_kwindowsystem
            step_kcolorscheme;     step_verify_kcolorscheme
            step_kauth;            step_verify_kauth
            step_kcrash;           step_verify_kcrash
            step_kcompletion;      step_verify_kcompletion
            step_kconfigwidgets;   step_verify_kconfigwidgets
            step_kservice;         step_verify_kservice
            step_kpackage;         step_verify_kpackage
            step_libltdl;          step_verify_libltdl
            step_libogg;           step_verify_libogg
            step_libvorbis;        step_verify_libvorbis
            step_libcanberra;      step_verify_libcanberra
            step_knotifications;   step_verify_knotifications
            step_breezeicons_native; step_verify_breezeicons_native
            step_breezeicons;      step_verify_breezeicons
            step_kiconthemes;      step_verify_kiconthemes
            step_kdeclarative;     step_verify_kdeclarative
            step_krunner;          step_verify_krunner
            step_kxmlgui;          step_verify_kxmlgui
            step_kirigami;         step_verify_kirigami
            step_ksvg;             step_verify_ksvg
            step_kbookmarks;       step_verify_kbookmarks
            step_kjobwidgets;      step_verify_kjobwidgets
            step_solid;            step_verify_solid
            step_kio;              step_verify_kio
            step_attica;           step_verify_attica
            step_knewstuff;        step_verify_knewstuff
            step_plasma_activities;       step_verify_plasma_activities
            step_plasma_activities_stats; step_verify_plasma_activities_stats
            step_xorgproto;        step_verify_xorgproto
            step_libxau;           step_verify_libxau
            step_libxdmcp;         step_verify_libxdmcp
            step_xcbproto;         step_verify_xcbproto
            step_libxcb;           step_verify_libxcb
            step_libplasma;        step_verify_libplasma
            step_kwayland;         step_verify_kwayland
            step_layer_shell_qt;   step_verify_layer_shell_qt
            step_kirigami_addons;  step_verify_kirigami_addons
            step_libkscreen;       step_verify_libkscreen
            step_kdecoration;      step_verify_kdecoration
            step_kcmutils_native;  step_verify_kcmutils_native
            step_kcmutils;         step_verify_kcmutils
            step_aurorae;          step_verify_aurorae
            step_breeze;           step_verify_breeze
            step_libnl;            step_verify_libnl
            step_lmsensors;        step_verify_lmsensors
            step_libksysguard;     step_verify_libksysguard
            step_libepoxy;         step_verify_libepoxy
            step_lcms2;            step_verify_lcms2
            step_hwdata;           step_verify_hwdata
            step_libdisplayinfo;   step_verify_libdisplayinfo
            step_kglobalacceld;    step_verify_kglobalacceld
            step_kscreenlocker;    step_verify_kscreenlocker
            step_vulkan_headers;   step_verify_vulkan_headers
            step_vulkan_loader;    step_verify_vulkan_loader
            step_libxcvt;          step_verify_libxcvt
            step_qtpositioning;    step_verify_qtpositioning
            step_kholidays;        step_verify_kholidays
            step_knighttime;       step_verify_knighttime
            step_kwin;             step_verify_kwin
            step_qcoro;            step_verify_qcoro
            step_icu_native
            step_icu;              step_verify_icu
            step_qtlocation;       step_verify_qtlocation
            step_qtmultimedia;     step_verify_qtmultimedia
            step_qtspeech;         step_verify_qtspeech
            step_libqrencode;      step_verify_libqrencode
            step_kded;             step_verify_kded
            step_kparts;           step_verify_kparts
            step_libgpgerror;      step_verify_libgpgerror
            step_libgcrypt;        step_verify_libgcrypt
            step_libsecret;        step_verify_libsecret
            step_kwallet;          step_verify_kwallet
            step_kstatusnotifieritem; step_verify_kstatusnotifieritem
            step_prison;           step_verify_prison
            step_sonnet;           step_verify_sonnet
            step_ktextwidgets;     step_verify_ktextwidgets
            step_ksyntaxhighlighting; step_verify_ksyntaxhighlighting
            step_ktexteditor;      step_verify_ktexteditor
            step_libndp;           step_verify_libndp
            step_networkmanager;   step_verify_networkmanager
            step_knetworkmanagerqt; step_verify_knetworkmanagerqt
            step_polkitqt1;        step_verify_polkitqt1
            step_plasma_workspace; step_verify_plasma_workspace
            log "Fase 6 Parte 3: Tier 0 (ECM) + Tier 1 (Qt6) + Tier 2 (KF6 completo) + Tier 3 en progreso (Plasma Activities + libplasma) completo. Sigue el resto de Tier 3 -- ver el mapa de dependencias al principio de este archivo."
            ;;
        *)
            die "target desconocido: ${target} (usar: ecm|qtbase-native|qtshadertools-native|qtdeclarative-native|qttools-native|qtbase|qtshadertools|qtdeclarative|qtsvg|qt5compat|qttools|qtwayland|isocodes|plasma-wayland-protocols|kcodecs|kitemviews|kitemmodels|kcoreaddons|kconfig|kwidgetsaddons|ki18n|kdbusaddons|karchive|kglobalaccel|kguiaddons|kidletime|kwindowsystem|all, cada uno con su verify-<paso>)"
            ;;
    esac
}

main "$@"
