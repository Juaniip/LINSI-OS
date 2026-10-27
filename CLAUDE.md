# LINSI-OS — Contexto para Claude Code

Este archivo lo lee Claude Code automáticamente al abrir una sesión en este
repo. Es un índice, no un duplicado: los detalles viven en los archivos que
señala abajo. Objetivo: que una sesión nueva (ej. en otra PC) pueda retomar
el proyecto sin que Juani tenga que reexplicar nada.

## Qué es este proyecto

LINSI-OS: una distro Linux hecha a medida para el laboratorio (LINSI, UTN
FRLP), construida en 8 fases estilo LFS, cada una sosteniendo uno de cinco
pilares de diseño (Seguridad, Privacidad, Robustez, Estética, Vanguardia).
El build es cross-compilado dentro de contenedores Podman (triplet
`x86_64-linsi-linux-gnu`, sin chroot, todo con `--prefix=/usr` +
`DESTDIR="${LFS_SYSROOT}"`), orquestado por scripts en `scripts/*.sh`.

## Dónde está cada cosa

- **`docs/PENDIENTES.md`** — la ÚNICA fuente de verdad del estado real del
  proyecto, fase por fase, con cada error real encontrado durante el build
  y cómo se resolvió. Léelo entero (o al menos las últimas secciones) antes
  de tocar cualquier script de build. **No confundir con ningún otro
  `PENDIENTES.md` que pueda aparecer suelto en la raíz del repo** — si
  aparece uno ahí, es una copia vieja/importada de otro lado, no la
  referencia real; avisar a Juani en vez de asumir cuál es la vigente.
- **`scripts/build-kde.sh`** — el script activo en este momento (Fase 6
  Parte 3: Qt6 + KDE Frameworks + Plasma). Tiene su propio mapa de
  dependencias por tier en el comentario de cabecera.
- **`scripts/env.sh`** — todas las versiones/mirrors pinneados, con el
  research real detrás de cada uno (por qué esa versión, de dónde sale el
  tarball).
- Los demás `scripts/build-*.sh` (cross-toolchain, kernel, desktop, mesa)
  corresponden a fases ya completas — no hace falta tocarlos salvo que
  aparezca un bug real en algo que dependa de ellos.

## Estado actual (resumen — el detalle real vive en `docs/PENDIENTES.md`)

Fases 0 a 4 (toolchain, kernel, espacio de usuario, seguridad,
comunicaciones) completas. Fase 6: Partes 1 y 2 completas; de la Parte 3
está compilado el núcleo de Plasma (Qt6, KF6, kwin, plasma-workspace,
2026-09-17) y, desde 2026-10-22, el escritorio en sí: plasma-desktop,
plasma-login-manager, systemsettings, plasma-nm/plasma-pa, powerdevil,
kscreen, etc. (los 16 paquetes), más impresión completa (CUPS 2.4.20 +
filtros de OpenPrinting sin ghostscript + Qt con cups + print-manager +
xdg-desktop-portal-kde). Qt quedó alineado con KDE también en el
directorio de plugins (`lib/plugins`, 2026-10-27 — antes Qt no hubiera
encontrado ningún plugin de KDE). Wayland puro sostenido (sin libX11, sin KCM
de teclado — el layout va fijo en `/etc/skel`). Faltan Konsole/Dolphin,
kpipewire, `/etc/skel` (layout, tema oscuro, Nerd Fonts). Nada se arrancó
todavía en una máquina real ni en QEMU — **antes de eso, correr
`scripts/check-sysroot.sh`**: el 2026-10-22 encontró que faltaba el
runtime de C++ (libstdc++/libgcc_s/libgomp, ningún programa C++ hubiera
arrancado) y rutas `/lfs` compiladas en libxkbcommon/kded/ki18n/LVM2; hoy
da 0 problemas. **Fase 5 (infraestructura
autónoma) parcial:** parte (a) — apk-tools + firma — confirmada recién
(2026-09-30, ver más abajo); partes (b) servidor de repo en la Raspberry
Pi y (c) CI/CD siguen pendientes (ver `docs/PENDIENTES.md`). Fase 6 Parte
3 en detalle: Tier 0 (ECM), Tier 1 (Qt6), Tier 2 (KDE Frameworks 6
completo, incluido KIO y knewstuff), **Tier 3 (tren de Plasma) completo
en su totalidad**, Tier 4/5 (kwin) y **Tier 5 (plasma-workspace, último
paquete de la fase) ✅ COMPLETO** (2026-09-16/17) --
`PlasmaActivities`/`Stats`, `libplasma`+`PlasmaQuick`, `KWayland`,
`layer-shell-qt`, `KirigamiAddons`, `libkscreen`, `KDecoration3`,
`KCMUtils`, `Aurorae`, `Breeze`, `KSysGuard`. `Union` queda
deliberadamente pospuesto (sin consumidor real que lo pida `REQUIRED`).

Tier 3 dejó dos precedentes importantes para lo que sigue: (1) el
**primer parche a código fuente de KDE** de todo el proyecto (bug
sistemático de upstream: includes de X11 -- `KX11Extras`, `xcb.h`,
`qtx11extras_p.h` -- sin guard de preprocesador en un release Wayland
puro), resuelto caso por caso sacando el código X11 en vez de agregar
soporte X11 real; y (2) **herramientas de KF6 con binarios cruzados que
sólo fallan la PRIMERA VEZ que algo las invoca de verdad** (`kcmdesktopfilegenerator`
de KCMUtils, `kconfig_compiler_kf6` de KConfig -- este último compilado
hacía semanas sin que nadie lo hubiera ejercitado hasta Breeze) -- el
fix es siempre el mismo patrón ya usado en Fase 6 Parte 2
(`llvm-config`/`glslangValidator`): compilar un native mínimo y pisar el
binario roto del sysroot.

Los 5 prerequisitos de kwin (`lcms2`, `libdisplay-info`, `KGlobalAccelD`,
`libepoxy`, `KScreenLocker`) y **kwin mismo (Tier 5) están ✅ COMPLETOS**
(2026-09-16). `KScreenLocker` tuvo el bug sistémico de X11 más grande
hasta ahora, repartido en 3 archivos reales (`ksldapp.cpp`,
`globalaccel.cpp`, `greeter/greeterapp.cpp`) con lógica real de grab de
teclado/mouse -- confirmado y aprobado con Juani antes de tocarlo por
ser el componente de bloqueo de pantalla. También reveló un patrón
nuevo: símbolos de **KWindowSystem** (`KKeyServer`, `netwm.h`) que sólo
se instalan con soporte X11 real -- resuelto sin re-tocar KWindowSystem
(Tier 2 ya cerrado): reimplementación local de la única función viva
(`isShiftAsModifierAllowed`) y eliminación del include muerto
(`netwm.h`).

**kwin** trajo 3 prerequisitos nuevos no detectados en el research
inicial (Vulkan-Headers+Loader -- Mesa sólo da los drivers ICD, nunca
el loader real --, libxcvt -- via `pkg_check_modules`, no
`find_package()` --, KNightTime+Qt6Positioning+KF6Holidays) y el
problema más grande de todo Tier 3-5: `KF6_HOST_TOOLING`, una
convención de KDE Frameworks entera (no sólo de kwin) que exige que
las herramientas nativas de Qt6 y de KF6 (KConfig/KCMUtils/KPackage)
vivan a la MISMA profundidad de directorio -- roto por el multiarch de
GNUInstallDirs en los builds nativos. Fix real de la causa raíz:
`-DCMAKE_INSTALL_LIBDIR=lib` agregado a `step_kconfig_native()`/
`step_kcmutils_native()` (retrofit sobre Tier 2/3 ya cerrados). Un
cuarto hallazgo (más chico) del bug sistémico de X11 apareció en 2
helpers standalone de kwin (`dialoghelper.cpp`/`killer.cpp`). Binario
real instalado: `/lfs/usr/bin/kwin_wayland`. Ver `docs/PENDIENTES.md`
(secciones "Prerequisitos de kwin (Tier 4)" y "Tier 5 (kwin)") para el
detalle completo -- vale la pena leerlo antes de tocar cualquier otro
paquete que use `KF6_HOST_TOOLING` o native-tooling en general.

**plasma-workspace** (Tier 5, último paquete de Fase 6 Parte 3) está
**✅ COMPLETO** (2026-09-17): destapó una cadena de 20 prerequisitos
nuevos (mucho más larga que la de kwin) -- QCoro6, ICU4C (el build más
complicado de la sesión: 3 bugs reales de upstream/entorno), libxcvt,
Qt6 Location/Positioning/Speech/Multimedia, 7 frameworks KF6 nunca
compilados antes (KDED, KParts, KWallet + libgcrypt + libgpg-error +
libsecret, KStatusNotifierItem, Prison + libqrencode, KTextWidgets +
Sonnet, KTextEditor + KSyntaxHighlighting) y, el más grande, **NetworkManager
completo + libndp + PolkitQt6-1** para `KF6NetworkManagerQt` (decisión
explícita de Juani: construirlo completo en vez de buscar un atajo),
con dos bugs reales de entorno en el camino (`xsltproc` faltante en la
imagen del contenedor -- agregado al `Dockerfile` y reconstruida la
imagen -- y un bug de reglas ITS de gettext para el merge de
traducciones del `.policy` de polkit). Sonnet en particular reveló que
el mapa heredado de "ya construido" de sesiones anteriores tenía un
error real -- nunca se había compilado pese a figurar como completo.
Una vez resueltos los prerequisitos, apareció **el bug sistémico de X11
más grande del proyecto** (mismo patrón ya visto en libplasma/
libkscreen/KScreenLocker/kwin: includes X11-only sin guard de
preprocesador), repartido en 18+ archivos reales de plasma-workspace --
encontrado y corregido con `ninja -k0` (colecta todos los errores de
compilación de una sola pasada) en vez del loop de a un error por vez.
**Build final limpio, 0 errores, verify real en verde**
(`plasmashell`/`krunner`/`plasma_session`/`startplasma-wayland`/
`ksmserver-logout-greeter` -- Plasma 6 no instala un `ksmserver`
standalone). Con esto queda compilado el **núcleo** de Plasma; el
escritorio usable (plasma-desktop, login manager, etc.) se sigue en la
sección "Escritorio usable" de `docs/PENDIENTES.md`. Ver `docs/PENDIENTES.md` (sección "plasma-workspace
(Tier 5)") para el detalle completo de los 20 prerequisitos, los dos
bugs de NetworkManager y el catálogo completo de los 18+ archivos con
parches de X11.

**Bug de infraestructura grave encontrado y resuelto (2026-09-30):**
`/lfs/etc` nunca tuvo volumen persistente en `docker-compose.yml` —
cualquier config real escrita ahí (PAM/DNS-over-TLS de Fase 4; dbus/
fontconfig/pipewire/polkit de Fase 6 Parte 1; apk-signing de Fase 5) se
perdía entre corridas separadas de `podman-compose run --rm`, aunque el
verify de la MISMA corrida diera bien. Fix: agregado el volumen
`linsios-etc:/lfs/etc`. De paso apareció un segundo bug real, más viejo
(ya estaba en los logs de Fase 6 Parte 1 de hace semanas, nadie lo había
notado): las unidades systemd de dbus/polkit/pipewire/wireplumber
duplicaban el sysroot en la ruta (`/lfs/lfs/usr/lib/systemd/...`) por
combinar `PKG_CONFIG_SYSROOT_DIR` + `DESTDIR` sobre la misma variable —
corregido pasando la ruta de instalación ya relativa a mano en los 4
`step_*()` de `build-desktop.sh`. Ambos confirmados con un `find` real en
un contenedor NUEVO. Ver `docs/PENDIENTES.md` (sección "Infraestructura
de build") para el detalle completo de causa raíz y fix por paquete.

## Preferencias de trabajo (no son del proyecto, son de cómo trabajar acá)

- **Nunca hacer `git commit`.** Juani commitea él mismo después de revisar
  — esto aplica siempre, no sólo si lo pide explícito en el momento.
- **No entregar archivos en `.zip`** — trabajar con archivos sueltos directo.
- **No auto-programarse checkeos.** Esperar a que Juani avise
  "listo"/"termino"/"tiro error" antes de revisar logs o volver a correr
  algo, salvo que él mismo pida seguir sin frenar.
- **Identidad de git para los commits de este proyecto:** `Juan Ignacio` /
  `juaniwilt@gmail.com`. Si una PC nueva no tiene esto configurado
  todavía, puede hacer falta `git config user.name` / `user.email` (local
  al repo, no global, salvo que Juani diga lo contrario).
- **Disciplina de todo el proyecto:** "correr, leer el error real,
  corregir con evidencia" — nunca adivinar contra documentación
  desactualizada o memoria de una versión anterior de un paquete. Antes de
  escribir un `step_*()` nuevo, confirmar dependencias contra el
  `CMakeLists.txt`/`meson.build`/`configure.ac` REAL de esa versión
  exacta (invent.kde.org, download.kde.org, xorg.freedesktop.org — todos
  accesibles en vivo; `gitlab.freedesktop.org`/`gitlab.gnome.org` NO lo
  están desde este sandbox).

## Al terminar cualquier paso de build

Actualizar `docs/PENDIENTES.md` con el mismo nivel de detalle que ya
tiene: log real del error, causa raíz confirmada contra fuente primaria
(no suposiciones), y qué se cambió. Ese archivo es lo que hace posible
retomar el proyecto en otra máquina sin perder contexto — mantenerlo así.
