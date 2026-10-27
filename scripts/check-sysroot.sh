#!/usr/bin/env bash
# ==============================================================================
# LINSI-OS · chequeos de integridad del sysroot (no compila nada)
# ------------------------------------------------------------------------------
# Los verifies de cada paso miran que un archivo exista; no ven si el sistema
# final podría CORRER. Estos chequeos sí, y los dos encontraron bugs reales
# el 2026-10-22 (ver docs/PENDIENTES.md, "Infraestructura de build"):
#
#   1. Clausura de librerías: cada librería NEEDED de cada ELF del sysroot
#      tiene que existir en el sysroot. Encontró libstdc++/libgcc_s/libgomp
#      ausentes (848 binarios C++ no hubieran arrancado).
#   2. Rutas del sysroot filtradas: todo se instala con DESTDIR=${LFS_SYSROOT}
#      (/lfs) y prefix /usr; si "/lfs/..." queda compilado en la .rodata de un
#      binario o escrito en un archivo de runtime, en el sistema real apunta a
#      la nada. Encontró libxkbcommon, kded6, ki18n y una regla udev de LVM2.
#      Se ignoran los /lfs/usr/include/... (nombres __FILE__ en mensajes de
#      diagnóstico, no rutas que se abran). La info de debug, que tiene rutas
#      /lfs/build legítimas, queda afuera porque sólo se mira .rodata.
#
# Uso: scripts/check-sysroot.sh   (sale con 1 si encuentra algo)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/lfs/scripts/env.sh
source "${SCRIPT_DIR}/env.sh"

READELF="${LFS_TOOLS}/bin/${LFS_TGT}-readelf"
OBJCOPY="${LFS_TOOLS}/bin/${LFS_TGT}-objcopy"
pattern="${LFS_SYSROOT}/(usr|etc|var|boot)[A-Za-z0-9_./+-]*"
tmp="$(mktemp)"; have="$(mktemp)"; need="$(mktemp)"
trap 'rm -f "${tmp}" "${have}" "${need}"' EXIT

is_elf() { [[ "$(head -c4 "$1" 2>/dev/null | tail -c3)" == "ELF" ]]; }

mapfile -t elfs < <(find "${LFS_SYSROOT}/usr/bin" "${LFS_SYSROOT}/usr/sbin" "${LFS_SYSROOT}/usr/lib" \
                         -type f \( -perm -u+x -o -name '*.so*' \) 2>/dev/null)

problems=0

echo "== 1. Clausura de librerías (NEEDED que no existen en el sysroot)"
find "${LFS_SYSROOT}/usr/lib" \( -type f -o -type l \) -name '*.so*' -printf '%f\n' 2>/dev/null | sort -u > "${have}"
for f in "${elfs[@]}"; do
    is_elf "${f}" || continue
    "${READELF}" -d "${f}" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sed "s#\$# ${f#"${LFS_SYSROOT}"}#"
done > "${need}"
while read -r count soname; do
    problems=$((problems + 1))
    echo "  FALTA ${soname} (lo piden ${count} binarios, p. ej. $(awk -v s="${soname}" '$1==s{print $2; exit}' "${need}"))"
done < <(awk '{print $1}' "${need}" | sort | uniq -c | while read -r c n; do grep -qxF "${n}" "${have}" || echo "${c} ${n}"; done)

echo "== 2. Rutas del sysroot filtradas a binarios y archivos de runtime"
for f in "${elfs[@]}"; do
    is_elf "${f}" || continue
    "${OBJCOPY}" -O binary --only-section=.rodata "${f}" "${tmp}" 2>/dev/null || continue
    hits="$(grep -aoE "${pattern}" "${tmp}" | grep -v "^${LFS_SYSROOT}/usr/include/" | sort -u || true)"
    if [[ -n "${hits}" ]]; then
        problems=$((problems + 1))
        echo "  ELF ${f#"${LFS_SYSROOT}"}: $(echo "${hits}" | head -3 | tr '\n' ' ')"
    fi
done
while IFS= read -r f; do
    if grep -qE "${pattern}" "${f}" 2>/dev/null; then
        problems=$((problems + 1))
        echo "  TXT ${f#"${LFS_SYSROOT}"}: $(grep -oE "${pattern}" "${f}" | sort -u | head -2 | tr '\n' ' ')"
    fi
done < <(find "${LFS_SYSROOT}/usr/share" "${LFS_SYSROOT}/usr/lib" "${LFS_SYSROOT}/etc" -type f \
              \( -name '*.service' -o -name '*.desktop' -o -name '*.conf' -o -name 'qmldir' \
                 -o -name '*.json' -o -name '*.xml' -o -name '*.rules' -o -name '*.policy' \) \
              -not -path '*/pkgconfig/*' -not -path '*/cmake/*' 2>/dev/null)

echo "== 3. Directorios de plugins/QML de Qt alineados con los de KDE"
# Qt sólo busca plugins y módulos QML donde se compiló (QT6_INSTALL_*); KDE
# instala en lib/plugins y lib/qml. Si no coinciden, en el sistema real Qt no
# encuentra nada de KDE (pasó con los plugins hasta 2026-10-27).
qtcfg="$(grep -rh 'set(QT6_INSTALL_\(PLUGINS\|QML\) ' "${LFS_SYSROOT}/usr/lib/cmake/Qt6/" 2>/dev/null | sort -u || true)"
for want in 'set(QT6_INSTALL_PLUGINS "lib/plugins")' 'set(QT6_INSTALL_QML "lib/qml")'; do
    if ! grep -qF "${want}" <<<"${qtcfg}"; then
        problems=$((problems + 1))
        echo "  Qt no tiene ${want} -- tiene: $(tr '\n' ' ' <<<"${qtcfg}")"
    fi
done
if [[ -d "${LFS_SYSROOT}/usr/plugins" ]]; then
    problems=$((problems + 1))
    echo "  existe ${LFS_SYSROOT}/usr/plugins (restos de un Qt compilado con otro directorio de plugins)"
fi

echo "ELF revisados: ${#elfs[@]} -- problemas: ${problems}"
[[ "${problems}" -eq 0 ]]
