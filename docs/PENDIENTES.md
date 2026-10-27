# LINSI-OS — Pendientes y deuda técnica

Registro vivo de lo que quedó abierto, sin confirmar, o pospuesto a propósito.
No existía este archivo hasta ahora — esto es la primera versión, armada
repasando todo lo hecho desde que empezamos. Lo voy actualizando a medida que
se resuelve o aparece algo nuevo.

## Fases 0 a 4 — estado real (repasado a fondo, no de memoria)

Fui a mirar directo los logs que hay guardados en tu carpeta para no
contestar de memoria. Resultado:

- **Fase 0 (cross-toolchain) y Fase 1 (kernel):** no hay un log dedicado sólo
  a Binutils/GCC pass 1 sueltos, pero `kernel-rebuild.log` (en la raíz de
  `linsi-os/`) es en realidad la corrida completa de `build-kernel.sh`, y
  termina con **todas** las opciones de hardening en `[OK]` (Lockdown, KASLR,
  IOMMU, BTRFS, EFI stub, SELinux, audit, nf_tables, dm-crypt, AES-NI) y el
  mensaje final `Fase 1 completa: kernel endurecido en /lfs/boot, módulos en
  /lfs/lib/modules`. Como compilar el kernel ya usa el cross-compiler de Fase
  0, esto confirma las dos fases juntas, aunque no haya un log con el nombre
  "toolchain" suelto. **No es deuda pendiente, sólo no está guardado bajo un
  nombre obvio** — lo aclaro para que sepas dónde mirar si alguna vez lo
  necesitás.
- **Fase 2 (Espacio de Usuario — glibc, libstdc++, binutils2, gcc2,
  attr/acl/libcap/util-linux, systemd, ncurses, uutils, zsh):** acá sí hay un
  hueco real. Sólo encontré log de **zsh** (`zsh-build.log`/`verify-zsh.log`)
  — nada de glibc, gcc2, systemd (el de esta fase), ncurses ni uutils tiene
  un log propio guardado. Todo indica que funcionó bien (Fase 3 y Fase 4 se
  construyen encima de ese mismo glibc/gcc2/systemd y están confirmadas), así
  que es más una laguna de *registro* que de *funcionamiento* — pero si algún
  día algo raro pasa en Fase 7/8 y no se entiende por qué, este es el primer
  lugar sin cobertura directa a revisar.
- **Fase 3 (Seguridad/SELinux):** bien cubierta — encontré log de build+verify
  para prácticamente cada uno de los 19 pasos (libmnl, libnftnl, nftables,
  libcap-ng, auditd, libargon2, popt, json-c, libaio, lvm2, cryptsetup, y el
  resto de SELinux junto en `fase3-selinux.log`). Nada pendiente acá.
- **Fase 4 (Comunicaciones):** 100% confirmada en la sesión anterior, log real
  con los 9 pasos + verifies en verde.

## Fase 5 — Infraestructura Autónoma

Plan con tres partes, sólo la primera corre dentro del contenedor de build
(ver el encabezado real de `scripts/build-infra.sh`):

- **(a) apk-tools + firma — ✅ CONFIRMADO (2026-09-30), primera corrida real.**
  `build-infra.sh all` corrido de punta a punta: `apk` 3.0.7 compilado e
  instalado (linkeado contra libssl/libcrypto/libz, confirmado con
  `readelf`), par RSA-4096 generado, pública instalada en
  `/etc/apk/keys/`, `repositories` con el placeholder esperado. En el camino
  salieron dos bugs reales (documentados en detalle en "Infraestructura de
  build" más abajo): un falso positivo en `step_verify_apk_signing()` (el
  `find` barría todo `/lfs`, incluida la privada en `/lfs/build` a
  propósito) y, mucho más grave, que **`/lfs/etc` nunca tuvo volumen
  persistente** — ya corregido agregando `linsios-etc:/lfs/etc` a
  `docker-compose.yml`. Confirmado con un `find` real en un contenedor
  NUEVO que todo sobrevive.
- **(b) Servidor de repo en la Raspberry Pi** — `setup-repo-server.sh` sin
  confirmar ejecutado. Te di la guía paso a paso por SSH, pero no hay
  confirmación de que hayas corrido el script en la Pi ni de que nginx haya
  quedado sirviendo en el puerto 8088.
- **Cloudflare Tunnel: `cloudflared-ingress-snippet.yml` sin confirmar
  mergeado.** No sé si ya agregaste esa regla a tu `config.yml` real del túnel
  ni si corriste `cloudflared tunnel route dns`.
- **Placeholder en `/etc/apk/repositories` dentro del sysroot.** Tiene un TODO
  con el hostname real pendiente — se actualiza recién cuando el repo de la Pi
  esté confirmado andando de verdad desde afuera (`curl -I
  https://tu-hostname/edge/main/x86_64/` devolviendo 200).
- ~~`.github/workflows/lint-scripts.yml` rechazado al escribir~~ —
  resuelto: el archivo ya está en el repo (confirmado 2026-10-22).
- **(c) CI/CD — criterio de cadencia decidido (2026-09-30), runner sin
  decidir todavía.** Dos triggers, no uno solo:
  1. **On-push** — cualquier commit que toque `scripts/*.sh` o `env.sh`
     dispara build de la fase afectada + verifies + (cuando exista Fase 7/8)
     empaquetado `.apk` + firma con la llave RSA + publicación al repo de la
     Pi. Frecuente ahora en desarrollo activo, esporádico una vez estable.
  2. **Programado (mensual, propuesto)** — reconstrucción completa +
     chequeo de versiones pinneadas en `env.sh` contra CVEs conocidos
     (kernel/OpenSSL/glibc/etc.), incluso sin que nadie toque el repo.
     Motivo: con el pilar de Seguridad de por medio, varios meses sin
     reconstruir "porque ya está estable" puede significar meses con CVEs
     conocidos sin parchear.
  - **Runner: sigue sin decidir.** Técnicamente cualquiera sirve (todo corre
    en contenedor, no hace falta hardware específico para el target
    x86_64) — la duda es de costo/duración (builds de la escala de Qt6+KDE
    de esta sesión tardaron horas, probablemente superan el free tier de
    GitHub Actions). La Pi queda descartada como runner (ARM64, necesitaría
    QEMU para x86_64, mucho más lento).
  - **Alcance real hoy:** hasta que exista empaquetado `.apk` (Fase 7/8), el
    job de CI construiría el sysroot y correría verifies, sin publicar
    paquetes instalables reales a la Pi todavía.
  - Sigue sin resolver si el runner es GitHub hosteado o self-hosted en tu
    PC. Ver la respuesta a tu pregunta de si hace falta tener la PC prendida
    24/7, al final de este archivo.

## Fase 6 — Parte 1 (fundación no gráfica) — ✅ COMPLETA (confirmada 2026-08-29)

**Confirmado con log real, `build-desktop.sh all` de punta a punta sin
errores:** D-Bus/polkit, fuentes/2D (freetype/harfbuzz/fontconfig/pixman/
cairo), Wayland + wayland-protocols, entrada (mtdev/libevdev/
xkeyboard-config/libinput/libxkbcommon) y audio (alsa-lib/lua/pipewire/
wireplumber) — todo instalado y verificado en el sysroot. El log completo
de la corrida que cerró la fase es
`logs/20260829-200453_build-desktop_all.log`.

Quedó un detalle chico para revisar más adelante, no bloqueante ahora:

- **Rutas systemd de wireplumber con `/lfs` duplicado.** El log muestra
  `Installing .../wireplumber.service to /lfs/lfs/usr/lib/systemd/user`
  (doble `/lfs`) en vez de `/lfs/usr/lib/systemd/user`. Probablemente la
  variable `systemduserunitdir` que wireplumber saca de `systemd.pc` ya
  viene con un `/lfs` de más desde cómo se configuró systemd en Fase 2, y
  al sumarle `DESTDIR=/lfs` queda duplicado. No rompe nada ahora (sysroot
  monolítico, sin booteo real todavía), pero si no se corrige antes de
  Fase 7/8, el `.service` de wireplumber va a terminar en el lugar
  equivocado cuando `/lfs` sea la raíz real. Vale la pena revisarlo cuando
  se llegue a empaquetar/bootear de verdad — no hace falta pararse a
  arreglarlo ahora.

Todo lo de abajo queda como registro histórico de los bugs reales que
aparecieron y cómo se resolvieron, por si algo parecido vuelve a pasar en
las Partes 2/3.

- **Bugs reales corregidos:** libffi (multilib →
  `--disable-multi-os-directory`), dbus (opción de meson inexistente
  `-Dsystemdsystemunitdir`), fontconfig (autotools → Meson por el bug de
  `va_copy` en cross-compiling), wayland (scanner nativo de bootstrap +
  `libexpat1-dev` agregado al Dockerfile), wayland-protocols (mismo problema
  del scanner nativo — la mitigación con `PKG_CONFIG_PATH` no alcanzó, hizo
  falta un `--native-file` explícito de Meson; ver el mecanismo compartido
  `write_meson_nativefile()` / `WAYLAND_SCANNER_NATIVE_PREFIX` en el script),
  y dos falsos positivos propios de verify (no bugs de build real):
  - `step_verify_wayland_protocols()` buscaba el `.pc` en `lib/pkgconfig`,
    pero Meson lo instala en `share/pkgconfig` para paquetes sin código
    compilado. Corregido también en el cross-file compartido, para que
    futuros pasos que necesiten `.pc` de ese tipo no tengan el mismo
    problema.
  - `step_verify_xkeyboard_config()` (2026-08-29) buscaba
    `/usr/share/X11/xkb/rules/base.xml`, pero `/usr/share/X11/xkb` se
    instala como **symlink absoluto** a `/usr/share/xkeyboard-config-2`. Como
    el proyecto nunca chrootea a `/lfs`, ese symlink resuelve contra la raíz
    real del contenedor y no contra el sysroot — da falso negativo aunque el
    build salió bien. Corregido para verificar directo
    `.../usr/share/xkeyboard-config-2/rules/base.xml`, sin pasar por el
    symlink.
- **libxkbcommon pedía libxml2 real (2026-08-29):** con
  `-Denable-xkbregistry=true` el build tira `Dependency "libxml-2.0" not
  found` — y libxml2 no está compilado en ningún lado del proyecto todavía.
  El núcleo de libxkbcommon (compilar keymaps, protocolo xkb de Wayland) NO
  necesita xkbregistry — esa API opcional es sólo para listar layouts
  disponibles (la usan selectores de teclado de un DE, ej. kxkbcommon en
  KDE). **Decisión:** se puso `-Denable-xkbregistry=false` por ahora, en vez
  de meter un `step_libxml2()` nuevo a mitad de Fase 6 Parte 1 sin
  necesitarlo todavía. **Queda pendiente para cuando arranque la Parte 3
  (Qt6/KDE):** agregar `step_libxml2()` cross-compilado (Meson) y volver a
  poner `-Denable-xkbregistry=true` — para entonces sí hace falta (kwin/System
  Settings necesitan listar layouts).
- **libxkbcommon, segunda vuelta (2026-08-29): mismo bug del scanner nativo
  que ya tuvimos con wayland y wayland-protocols.** Con
  `-Denable-wayland=true`, las herramientas `xkbcli ... wayland` piden un
  wayland-scanner NATIVO (`Build-time dependency wayland-scanner found: NO`)
  aparte de wayland-client/wayland-protocols del sysroot cruzado (esos dos sí
  se encontraban bien). Van tres paquetes seguidos con el mismo problema —
  cada vez que algo genera código a partir de XMLs de protocolo Wayland
  durante un build cruzado, hace falta el scanner nativo. **Fix:** se le
  agregó `--native-file` reusando `write_meson_nativefile()` /
  `WAYLAND_SCANNER_NATIVE_PREFIX`, igual que en los otros dos. Si el mismo
  error vuelve a aparecer en pipewire o wireplumber (ver "riesgo conocido"
  abajo), es el mismo fix de siempre: agregar `--native-file`.
- **Riesgo conocido, no confirmado:** pipewire/wireplumber (o pasos futuros de
  Mesa/Qt6) todavía podrían pedir el mismo "wayland-scanner nativo" que ya le
  hizo falta a wayland y wayland-protocols. Si tira el mismo error
  ("Dependency wayland-scanner not found"), el fix ya está listo para
  reusar: agregarle a ese paso `--native-file="${nativefile}"` con
  `write_meson_nativefile()`, como se hizo en los otros dos.
- **Lección general para los pasos que faltan:** ya van dos veces que un
  verify propio da falso positivo por asumir una convención de instalación
  de Meson que no era la real (`.pc` en `share/` en vez de `lib/`; symlink
  absoluto que no se puede seguir sin chroot). Antes de confiar en un `die`
  de verify, conviene mirar las líneas reales de `Installing ...` en el log
  del paso — no asumir la ruta "de manual" sin chequearla.
- **wireplumber pedía glib-compile-resources NATIVO de verdad (2026-08-29,
  variante nueva del mismo problema de fondo):** a diferencia de
  wayland-scanner (donde no existía ningún glib-compile-resources y hacía
  falta compilar uno native aparte), acá sí había uno en el PATH — pero era
  el CROSS-compilado en `${LFS_SYSROOT}/usr/bin` (Meson lo encuentra porque
  `env.sh` agrega ese directorio al PATH, al final). Al ejecutarlo sin
  chroot: `error while loading shared libraries: libgio-2.0.so.0: cannot
  open shared object file`. Es un binario linkeado contra el glibc
  CROSS-compilado de Fase 2, no contra el glibc real del contenedor —
  **misma arquitectura (x86_64) NO implica que un binario del sysroot se
  pueda ejecutar así de directo**; sólo funciona si no depende de librerías
  propias del sysroot (por eso pkg-config, que es del host, sí funciona
  bien; wayland-scanner necesitó su propio build nativo aparte). **Fix:**
  se instalaron `libglib2.0-bin` + `libglib2.0-dev-bin` de apt en el
  Dockerfile (mismo patrón que `libexpat1-dev` para wayland-scanner, pero
  acá alcanza con el paquete de Debian en vez de compilar desde cero) — el
  PATH ya prioriza `/usr/bin` (real) por sobre `${LFS_SYSROOT}/usr/bin`
  (agregado al final), así que una vez reconstruida la imagen Meson
  encuentra el nativo primero. **Corregido también el comentario en
  `env.sh`** que afirmaba (de forma ahora comprobada falsa) que "el binario
  cross-compilado corre perfecto en este mismo contenedor" sólo por ser la
  misma arquitectura — dejaba una trampa documentada para el próximo
  paquete de glib que hiciera falta (gdbus-codegen, glib-compile-schemas,
  que Qt6/KDE va a pedir).
- **wireplumber, tercera vuelta (2026-08-29): el mismo problema de fondo,
  variante todavía distinta.** Después del fix de glib-compile-resources, el
  build llegó a compilar TODO el código de wireplumber (wpctl, wpexec, el
  daemon, todos los módulos) y sólo falló en el último paso: generar
  `po/conf.pot`, que invoca `spa-json-dump` (herramienta chica y propia de
  PipeWire, sin paquete de Debian) sobre `wireplumber.conf`. El binario
  CROSS-compilado en `${LFS_SYSROOT}/usr/bin` tira `GLIBC_2.38' not found` —
  esta vez no es una librería faltante como con libgio, es un choque de
  VERSIÓN del propio glibc (el cross-compilado en Fase 2 es más nuevo que el
  de Debian bookworm del contenedor). **Fix:** en vez de otro paquete de apt
  (no existe uno para esta herramienta) o de LD_LIBRARY_PATH (más frágil
  todavía, mezclaría dos glibc distintos), se compila un `spa-json-dump`
  genuinamente NATIVO con un `gcc` directo (ni siquiera hace falta Meson acá
  -- confirmado contra el `meson.build`/`.c` reales de PipeWire que esta
  herramienta sólo necesita headers de SPA, sin nada para linkear), y se le
  pisa a Meson el binario vía `--native-file` (`[binaries] spa-json-dump =
  '...'`) en vez de dejar que lo encuentre solo por PATH. Ver
  `build_native_spa_json_dump()` en el script.
- **Bug propio (no de PipeWire/Meson) en el fix anterior, encontrado en la
  siguiente corrida (2026-08-29):** `build_native_spa_json_dump()` hacía
  `cd "${LFS_SOURCES}"` para bajar/extraer pipewire y nunca volvía al
  directorio del que la llamaban. Como `step_wireplumber()` ya había hecho
  `cd "${src}"` (el propio directorio fuente de wireplumber) antes de
  llamarla, el `meson setup` de wireplumber terminaba corriendo con el cwd
  equivocado (`/lfs/sources`) y tiraba `"Neither source directory ... nor
  build directory None contain a build file meson.build"` — ni siquiera
  llegaba a intentar compilar nada. **Corregido:** la función ahora guarda
  el cwd del que la llama al entrar y lo restaura antes de salir, pase lo
  que pase. Lección para cualquier helper nuevo que haga falta más adelante:
  si hace `cd` adentro, tiene que devolver el directorio como lo encontró.
- **spa-json-dump, segundo intento fallido (2026-08-29): el --native-file NO
  alcanzó, quedó exactamente el mismo error.** Investigando el
  `po/meson.build` real de wireplumber apareció el motivo: llama a
  `find_program('spa-json-dump', required: false)` SIN `native: true`. Sin
  ese kwarg, Meson resuelve el programa contra el `[binaries]` del CROSS
  FILE (lo que Meson llama "host machine" en su terminología invertida), NO
  contra el del native file -- ese sólo se consulta cuando el propio
  `find_program()` pide `native: true` explícito. Pisarlo en el nativefile
  no hacía nada; wireplumber seguía cayendo al fallback de PATH del cross
  file y volvía a agarrar el cross-compilado de siempre. **Fix real:**
  mover el override al `[binaries]` del cross-file (`write_meson_crossfile()`
  ahora acepta un segundo parámetro opcional `extra_binaries` para esto) --
  ya no hace falta `--native-file` en `step_wireplumber()`, sólo el
  cross-file de siempre con el binario nativo pisado adentro.
- **Lección para la lista de "riesgo conocido" de abajo:** no alcanza con
  saber "esto necesita un binario nativo" -- también hay que fijarse CÓMO lo
  busca el proyecto consumidor (`find_program()` con o sin `native: true`,
  `dependency()`, una variable de pkg-config, un path hardcodeado). El
  mecanismo de override correcto depende de eso, y adivinarlo (probar
  primero con --native-file porque fue lo que funcionó con
  wayland/wayland-protocols) puede no alcanzar, como pasó acá.
- **Patrón que se repite y conviene tener presente para lo que falta (Mesa,
  Qt6/KDE):** "misma arquitectura" (x86_64 cross == x86_64 host) NO
  garantiza que un binario cross-compilado se pueda ejecutar directo sin
  chroot. Van tres casos reales distintos de esto en Fase 6 Parte 1: (1)
  wayland-scanner -- ni existía nativo, hubo que compilar uno aparte; (2)
  glib-compile-resources -- existía pero le faltaban librerías (glibc
  cross-compilado, no el del contenedor); (3) spa-json-dump -- existía,
  encontraba sus librerías, pero pedía símbolos de una versión de glibc más
  nueva que la del contenedor. Los tres se resuelven igual: conseguir un
  binario NATIVO de verdad (apt si hay paquete, compilarlo aparte si no) y
  asegurarse de que Meson lo use en vez del cross-compilado (--native-file o
  PATH bien ordenado) -- nunca parchear con variables de entorno tipo
  LD_LIBRARY_PATH.
- **Flags de Meson dejados en default a propósito** en `step_dbus()` y
  `step_wayland_protocols()` — no pude confirmar esos nombres exactos contra
  el `meson_options.txt` real de esas versiones puntuales, y preferí no
  arriesgar un "Unknown option" adivinando. Si falta alguna funcionalidad más
  adelante, revisar ahí primero.

## Fase 6 — Parte 2 (Mesa + LLVM, drivers gráficos) — ✅ COMPLETA (confirmada 2026-09-04)

Este título pasó por "script escrito, SIN CORRER TODAVÍA" (2026-08-29) y
"EN CURSO, corriendo de verdad" antes de esto -- cerrado ahora de verdad,
con `verify-mesa` en `[OK]` de punta a punta contra el sysroot real
(`logs/20260904-113651_build-mesa_verify-mesa.log`):

```
[OK] /lfs/usr/lib/libgallium-26.2.1.so (iris+radeonsi+nouveau+llvmpipe linkeados adentro)
[OK] /lfs/usr/lib/gbm/dri_gbm.so
[OK] /lfs/usr/lib/libvulkan_radeon.so
[OK] /lfs/usr/lib/libvulkan_intel.so
[OK] libEGL.so presente
OK: Mesa completo en el sysroot.
```

El build real de Mesa (`ninja`+`ninja install`, ver
`logs/20260904-060402_build-mesa_mesa.log`) ya había terminado 2872/2872 +
76/76 targets sin un solo error desde antes -- lo que faltaba era el
Vigésimo cuarto "error real" de más abajo, que en realidad era un falso
negativo del propio `step_verify_mesa()`, no un problema de Mesa. Con eso
corregido, las tres familias de GPU del laboratorio (Intel iris, AMD
radeonsi/RADV, Nvidia nouveau + llvmpipe de fallback) quedan con drivers
Gallium/Vulkan instalados y verificados en el sysroot. Sigue Fase 6 Parte 3
(Qt6 + KDE), ver esa sección más abajo para el prerequisito ya identificado
(libxml2 + reactivar `-Denable-xkbregistry=true`).

La extensión de la sección de "errores reales" de acá abajo (24 entradas)
es el registro completo de las corridas reales que llevaron hasta acá, no
trabajo especulativo -- son los errores concretos que tiró el build real,
cada uno con su causa raíz confirmada contra la fuente real de Mesa/LLVM
antes de tocar nada, no parches a ciegas. La gran mayoría ya están
cerrados; tres tramos tuvieron que corregirse a sí mismos después de
resultar incompletos (Décimo octavo→Décimo noveno, Décimo noveno parte
2→Vigésimo, y el propio verify en el Vigésimo cuarto) -- señalado explícito
en cada caso, no escondido.

- **Script nuevo:** `scripts/build-mesa.sh` (independiente de
  `build-desktop.sh`, mismo patrón de siempre: se basta a sí mismo, no
  sourcea otros scripts de fase). Targets: `libdrm`, `verify-libdrm`,
  `llvm-native`, `llvm`, `verify-llvm`, `glslang-native`, `spirv-headers`,
  `spirv-tools`, `verify-spirv-tools`, `spirv-llvm-translator`,
  `verify-spirv-llvm-translator`, `elfutils`, `verify-elfutils`, `mesa`,
  `verify-mesa`, `all` (los del bloque SPIRV agregados 2026-09-02, ver el
  "Duodécimo error real" más abajo; `elfutils`/`verify-elfutils`
  agregados el mismo día, ver el "Décimo sexto error real").
- **Alcance de hardware, confirmado por vos:** el laboratorio tiene máquinas
  mixtas (Nvidia RTX 3060, AMD RX 7700, gráfica integrada Intel, "etc"), o
  sea que no se puede asumir una sola marca — el driver stack tiene que
  cubrir las tres.
- **Decisiones de drivers tomadas** (confirmadas contra el
  `meson_options.txt` real de Mesa, vía el mirror de GitHub porque
  `gitlab.freedesktop.org` está bloqueado por robots.txt en este sandbox):
  - `gallium-drivers = iris,radeonsi,nouveau,swrast` → iris (Intel), radeonsi
    (AMD OpenGL), nouveau (Nvidia open-source), swrast (fallback por
    software si no hay GPU soportada).
  - `vulkan-drivers = amd,intel` → RADV (AMD) y ANV (Intel). **Nvidia/nouveau
    todavía no tiene una opción de Vulkan en Mesa** (no existe NVK como
    opción de build estable en esta versión), así que en la 3060 vamos a
    tener OpenGL vía nouveau pero no Vulkan nativo por ahora — es una
    limitación real de Mesa, no algo que nos falte compilar.
  - LLVM se compila con `LLVM_TARGETS_TO_BUILD="X86;AMDGPU"` — hace falta
    como librería para radeonsi/RADV y como motor del fallback por software
    (llvmpipe), aunque no estemos compilando Clang.
- **Quedó deliberadamente afuera de esta primera pasada** (no es que se
  olvidó, es scope recortado a propósito):
  - **Vulkan por software (lavapipe / `vulkan-drivers=swrast`)** — confirmado
    contra una guía real de GLFS que esto necesita un build completo de
    Clang (no sólo las librerías de LLVM), y eso es mucho más scope. Si algún
    día hace falta correr apps Vulkan sin GPU compatible, es la próxima
    pieza a agregar.
  - **VA-API / VDPAU** (aceleración de video) — necesitan libva/libvdpau, que
    todavía no están compilados.
  - **glvnd** (selector de driver GL multi-vendor) — sólo hace falta si en
    algún momento se suma un driver propietario de Nvidia además de nouveau.
  - **NVK** (el driver Vulkan nativo que Nvidia/Mesa están desarrollando para
    su propia GPU) — todavía no es una opción de build estable en la versión
    de Mesa que estamos usando.
- **La parte más delicada / menos verificada de todo el proyecto hasta
  ahora: cómo se resuelve `llvm-config` dentro del sysroot.** LLVM se
  compila dos veces: una nativa (sólo para sacar `llvm-tblgen` y
  `llvm-config` utilizables dentro del contenedor) y otra cross (la que
  termina en el sysroot). El problema es el mismo que ya vimos tres veces en
  Parte 1 (wayland-scanner, glib-compile-resources, spa-json-dump): un
  binario cross-compilado para x86_64 no anda necesariamente en el
  contenedor aunque sea "la misma arquitectura", porque la glibc no es la
  misma. La solución acá es: compilar `llvm-config` NATIVO pero configurado
  con el prefix real del sysroot (`${LFS_SYSROOT}/usr`), y al final del
  build cross de LLVM, pisar el `llvm-config` cross-compilado (roto) con ese
  binario nativo. `step_verify_llvm()` corre ese `llvm-config` ya pisado y
  chequea que `--includedir` devuelva una ruta que empiece con el sysroot —
  si eso falla, el problema está ahí, no en Mesa. **Esto no se pudo probar
  contra un build real todavía — es la apuesta de diseño más incierta de
  todo el proyecto y hay que estar atento a esa verificación específica.**
- **Cómo correrlo:** `podman-compose run --rm builder scripts/build-mesa.sh
  all`. A diferencia del fix de glib-compile-resources en Parte 1, **esta
  vez no hizo falta tocar el Dockerfile**, así que no hace falta
  `podman-compose build` antes — el contenedor ya tiene todo lo necesario.
  Es totalmente esperable que este paso necesite una o más vueltas de
  ida y vuelta con errores reales, igual que pasó con wayland-scanner en
  Parte 1.
- **Bug propio encontrado y corregido antes de entregar el script:** el
  array de flags de CMake para LLVM tenía
  `-DLLVM_TARGETS_TO_BUILD=X86;AMDGPU` sin comillas — el `;` sin comillas
  corta el comando en bash (síntoma: `syntax error near unexpected token
  ';'`). Se corrigió comillando todo el flag:
  `"-DLLVM_TARGETS_TO_BUILD=X86;AMDGPU"`. Confirmado con `bash -n` antes de
  entregarlo.
- **Primer error real (2026-08-29), ya corregido: `libdrm_intel.so` faltante
  frenaba `step_verify_libdrm()`.** Log real:
  `Run-time dependency pciaccess found: NO` → meson desactiva sola la
  compilación de `intel/` dentro de libdrm (no hace falta pciaccess salvo
  para eso), y el script moría en la verificación siguiente porque yo había
  puesto `libdrm_intel` en la lista de "obligatorios" sin chequear si
  realmente hacía falta. Investigado contra el `meson.build` real de `iris`
  en Mesa: **iris sólo depende de `libdrm` genérico, nunca de
  `libdrm_intel`/`intel_bufmgr`** — eso es exclusivo del driver clásico
  i965/crocus (pre-Gen8, no lo usamos) y de la DDX de X11 xf86-video-intel
  (no aplica, este proyecto es Wayland puro). Como no hace falta, no tiene
  sentido cross-compilar libpciaccess sólo para tenerlo — sería scope
  creep sin beneficio real, mismo criterio que ya se usó para dejar afuera
  lavapipe/VA-API/glvnd. Se corrigió `step_verify_libdrm()` para tratar
  `libdrm_intel.so` como informativo (no frena el build) y se corrigió el
  comentario de la Parte 1 de este bloque, que decía (mal) que las
  cabeceras por-vendor "se instalan solas sin flags extra".
- **Segundo error real (2026-08-30), ya corregido — justo la parte que ya
  había avisado como más incierta de todo el proyecto: `llvm-config`
  reventaba al ejecutarlo.** Log real:
  `/lfs/usr/bin/llvm-config: symbol lookup error:
  /lfs/usr/bin/../lib/libc.so.6: undefined symbol: __pointer_chk_guard,
  version GLIBC_PRIVATE`. Investigado a fondo contra el código real de LLVM
  (llvm-config.cpp y el historial de AddLLVM.cmake en llvm/llvm-project):
  el prefix SÍ quedaba bien grabado en el binario (eso funcionaba), pero
  LLVM compila su tooling con un RPATH relativo a propósito
  (`$ORIGIN/../lib`, para que sea relocalizable) — y al copiar el
  `llvm-config` nativo a `${LFS_SYSROOT}/usr/bin/`, ese RPATH relativo pasó
  a apuntar a `${LFS_SYSROOT}/usr/lib`, la carpeta de librerías del
  SYSROOT (la glibc cruzada de Fase 2), no la del contenedor. Es la cuarta
  vuelta del mismo problema de fondo de toda Fase 6 (mezclar binario y
  glibc de mundos distintos aunque sea "la misma arquitectura"), pero acá
  el binario en sí SÍ era nativo — lo que estaba mal era a qué librerías
  terminaba apuntando por culpa de dónde lo copiamos. Se corrigió
  reescribiendo el RPATH del binario ya copiado con **patchelf**
  (`patchelf --set-rpath "${LLVM_NATIVE_BUILD}/lib" .../llvm-config`), que
  apunta al build nativo de LLVM (con su propia libLLVM.so compatible) sin
  tocar las rutas que reporta `llvm-config` (esas están grabadas aparte, en
  tiempo de compilación, y ya estaban bien). **Esto agregó `patchelf` al
  Dockerfile (apt, capa de paquetes base) — hace falta `podman-compose
  build` antes de volver a correr `build-mesa.sh`, a diferencia del fix de
  libdrm de más arriba.**
- **Tercer error real (2026-08-30), ya corregido: `-Dgallium-drivers=...,
  swrast` no es un choice válido en Mesa 26.2.1.** Log real: `ERROR: Value
  "swrast" for option "gallium-drivers" is not in allowed choices: "all,
  auto, asahi, crocus, d3d12, ethosu, etnaviv, freedreno, i915, iris, lima,
  llvmpipe, nouveau, panfrost, r300, r600, radeonsi, rocket, softpipe,
  svga, tegra, v3d, vc4, virgl, zink"`. "swrast" era el nombre viejo de la
  opción en versiones antiguas de Mesa; hoy está separada en `llvmpipe`
  (software con JIT de LLVM, la que realmente queríamos, ya que compilamos
  LLVM justo para esto) y `softpipe` (software puro, sin LLVM). Se corrigió
  a `-Dgallium-drivers=iris,radeonsi,nouveau,llvmpipe`. Importante: el
  archivo `.so` que termina instalado sigue llamándose `swrast_dri.so`
  igual que antes (confirmado contra el `meson.build` real del target dri
  de Mesa) — por eso `step_verify_mesa()` NO cambió, sigue buscando
  `swrast_dri.so`, eso no era el bug. Nota aparte: `vulkan-drivers=swrast`
  (para lavapipe, ya fuera de scope) es una opción DIFERENTE que si sigue
  llamándose así — no confundir los dos namespaces.
  No hizo falta tocar el Dockerfile para este fix.
- **Cuarto error real (2026-08-30), ya corregido: `-Dgallium-vdpau=disabled`
  ya no es un option válido en Mesa 26.2.1.** Log real: `ERROR: Unknown
  option: "gallium-vdpau"`. A diferencia del error de `swrast` (que era un
  rename), este es una eliminación lisa y llana: Mesa upstream sacó el
  soporte nativo de VDPAU de Gallium (confirmado contra un reporte de bug
  real de Gentoo, "gallium-vdpau option removed from upstream" — no hay
  ningún nombre nuevo al que migrar, la funcionalidad ya no está). Como
  VDPAU/VA-API ya estaban fuera de scope de este primer pase (ver arriba,
  necesitan libva/libvdpau que no compilamos), la opción simplemente se
  sacó del comando de `meson setup` en vez de "dejarla en disabled" — no
  hay nada que deshabilitar si la opción no existe. `-Dgallium-va=disabled`
  sí se mantuvo (esa opción todavía existe y el build real la aceptó sin
  problema). De paso se corrigió un warning real no fatal en el mismo log
  (`DEPRECATION: Option "gles2" value 'true' is replaced by 'enabled'`):
  `-Dgles2=true` → `-Dgles2=enabled`.
  No hizo falta tocar el Dockerfile para este fix tampoco.
- **Quinto error real (2026-08-30), ya corregido: `-Dosmesa=false` tampoco
  es un option válido en Mesa 26.2.1.** Log real: `ERROR: Unknown option:
  "osmesa"`. Mismo patrón exacto que `gallium-vdpau`: OSMesa (renderizado
  3D off-screen, sin display/GPU real) fue eliminado de Mesa upstream, no
  renombrado (confirmado por reportes reales de otros proyectos afectados,
  ej. conda-forge/mesalib-feedstock issue "OSMesa removed upstream from
  Mesa project"). Como este proyecto nunca lo necesitó (siempre hay GPU
  real o llvmpipe de fallback, nunca off-screen puro) y ya lo queríamos en
  `false`, sacar la flag no cambia nada — se sacó del comando de `meson
  setup` igual que gallium-vdpau. No hizo falta tocar el Dockerfile.
  **Patrón que se repite:** de los 5 errores reales de Fase 6 Parte 2 hasta
  ahora, 3 fueron opciones de Meson de Mesa que cambiaron de nombre o
  desaparecieron entre la versión que yo tenía en mente al escribir el
  script y la 26.2.1 real (swrast→llvmpipe, gallium-vdpau eliminada, osmesa
  eliminada) — nada de esto se puede prevenir de antemano sin acceso al
  `meson_options.txt` real de esa versión exacta (gitlab.fd.o bloqueado en
  el sandbox); el patrón de "correr, leer el error real, corregir" sigue
  siendo el único camino confiable acá.
- **Sexto error real (2026-08-31), ya corregido, distinto a los anteriores:
  falta `glslangValidator` en el contenedor.** Log real: `Program
  'glslangValidator' not found or not executable`. Mesa lo usa en tiempo de
  build para compilar shaders internos (GLSL -> SPIR-V). A diferencia de
  los cinco errores anteriores (todos sobre nombres/existencia de opciones
  de Meson), este es una herramienta nativa que directamente faltaba
  instalar -- pero, a diferencia de wayland-scanner o llvm-config, es el
  caso SIMPLE: glslangValidator sólo genera código en tiempo de build,
  nunca corre en el sysroot final, así que no hace falta cross-compilar
  nada ni pisar binarios ni tocar RPATH -- alcanza con el paquete de apt
  `glslang-tools` (confirmado que existe en Debian bookworm). Se agregó al
  Dockerfile (con su propio comentario numerado, ítem 10) y se agregó un
  chequeo defensivo en `step_mesa()` (`command -v glslangValidator`) que
  avisa claro si falta, en vez de dejar que Meson tire el error genérico.
  **Esto sí requiere `podman-compose build` antes de reintentar** (a
  diferencia de los fixes de swrast/vdpau/osmesa de más arriba, que sólo
  tocaban el script).
- **CORRECCIÓN al error anterior + séptimo error real (2026-08-31): el
  glslang-tools de apt SÍ se encuentra, pero es DEMASIADO VIEJO.** Log
  real: `ERROR: Problem encountered: glslang >= 12.2 is required.` — con
  `Program glslangValidator found: YES (/usr/bin/glslangValidator)`
  confirmando que sí lo encontró, sólo que la versión no alcanza. Debian
  bookworm quedó congelado en una versión de glslang de 2022; Mesa 26.2.1
  (mucho más nueva) pide algo más reciente. Mismo motivo de fondo que ya
  llevó a instalar meson por pip y Rust por rustup en vez de apt (Fase 2:
  "no depender de qué tan vieja sea la de apt") — pero acá no hay
  pip/rustup equivalente para glslang, así que se compila de fuente,
  NATIVO, con CMake+Ninja (mismo patrón que LLVM, pero mucho más simple:
  glslangValidator sólo genera código en tiempo de build, nunca corre en
  el sysroot final, así que no hace falta nada de lo que hizo delicado a
  LLVM -- ni dos etapas, ni RPATH, ni prefix apuntando al sysroot).
  `-DENABLE_OPT=OFF` evita necesitar SPIRV-Tools como dependencia externa
  (confirmado contra el CMakeLists.txt real de glslang). Se agregó
  `step_glslang_native()` (target nuevo `glslang-native`) a
  `build-mesa.sh`, y `step_mesa()` ahora pisa `glslangValidator` vía
  `extra_binaries` del cross-file (mismo mecanismo ya probado con
  spa-json-dump en build-desktop.sh) para que Mesa use el compilado nuevo
  en vez del de apt. El paquete `glslang-tools` de apt se deja instalado
  igual (no molesta, y puede servir para otra cosa más adelante) pero ya
  no es lo que Mesa termina usando. Agregado a `env.sh`:
  `GLSLANG_VERSION="16.3.0"` (release real de GitHub, KhronosGroup/glslang
  no está en gitlab.fd.o) y `GLSLANG_MIRROR`. No hizo falta tocar el
  Dockerfile para este fix (glslang se compila con las mismas herramientas
  nativas -- cmake, ninja, gcc -- que ya estaban instaladas para LLVM).
- **Octavo error real (2026-09-01), ya corregido: el glslangValidator nativo
  recién compilado NO se usó -- Mesa siguió encontrando el de apt.** Log
  real: `Program glslangValidator found: YES (/usr/bin/glslangValidator)`
  seguido otra vez de `ERROR: glslang >= 12.2 is required` -- confirmando
  que el glslangValidator nuevo (compilado en el paso anterior) SÍ existe y
  funciona, pero el override que le pusimos a `write_meson_crossfile()`
  (mismo mecanismo que funcionó con spa-json-dump en build-desktop.sh) no
  tuvo efecto acá. A diferencia de spa-json-dump -- donde confirmamos
  leyendo el `po/meson.build` REAL de wireplumber que su `find_program()`
  no usa `native: true`, por eso el cross-file era el lugar correcto --
  esta vez no se pudo confirmar en vivo si el `find_program('glslangValidator')`
  de Mesa 26.2.1 usa `native: true` o no (dos fuentes de un mismo mirror de
  GitHub se contradijeron entre sí y con el comportamiento real). En vez de
  seguir adivinando cuál mecanismo usa Mesa, se pisó el binario en LOS DOS
  archivos a la vez -- `write_meson_crossfile()` Y `write_meson_nativefile()`
  -- con el mismo `extra_binaries`. No cuesta nada extra y cubre cualquiera
  de los dos caminos que Meson termine tomando. No hizo falta tocar el
  Dockerfile.
- **Noveno error real (2026-08-31/09-01), ya corregido -- el mensaje de
  error era ENGAÑOSO.** Con glslangValidator ya resuelto, el siguiente
  error fue `meson.build:1136:2: ERROR: Problem encountered: Python >= 3.10
  not found`, a pesar de que el mismo log mostraba
  `Program python3.11 found: YES 3.11.2` -- ¡3.11.2 sí es >= 3.10! El texto
  resumido de la terminal no alcanzaba para entender qué pasaba, así que
  esta vez pedí el `meson-log.txt` completo en vez de seguir adivinando
  (`podman-compose run --rm builder bash -c "tail -100
  /lfs/build/mesa-mesa-26.2.1/build/meson-logs/meson-log.txt"` -- ese
  archivo vive adentro del volumen de Podman, no se puede leer directo
  desde afuera). Ahí se vio el comando real que Meson corre para validar
  cada candidato de Python:
  ```
  python3.11 -c '... try: import mako \n except: sys.exit(1) ...'
  ```
  Ese `import mako` fallaba (el módulo no está instalado) -- Mesa genera
  gran parte de su código fuente con plantillas Mako en tiempo de build, y
  Meson resume CUALQUIER falla de esa validación combinada
  (versión+módulos) con el mismo mensaje genérico de versión, sin
  mencionar que en realidad era el módulo el que faltaba. Mismo patrón ya
  documentado como un problema conocido de Meson (issue real de
  mesonbuild/meson sobre mensajes de detección de Python engañosos). Se
  agregó `python3-mako` al Dockerfile (ítem 11) -- acá SÍ alcanza con apt
  sin drama de versión, Mesa sólo pide mako >=0.8.0 (de 2013), un piso
  bajísimo a diferencia de meson/glslang. **Esto sí requiere
  `podman-compose build` antes de reintentar.**
  **Lección para la próxima vez que un error no tenga sentido:** pedir el
  `meson-log.txt` completo (o el log equivalente de la herramienta que
  esté fallando) ANTES de ponerse a investigar con búsquedas web sobre el
  código fuente del proyecto -- tiene el comando exacto que se corrió y su
  salida real, mucho más confiable que reconstruir la lógica leyendo
  mirrors de GitHub que pueden no coincidir con la versión exacta en uso.
- **Décimo error real (2026-09-01), ya corregido -- mismo mensaje engañoso
  que el noveno, pero otra causa distinta.** Después de reconstruir la
  imagen con `python3-mako` (ítem 11), volvió a salir el mismo
  `meson.build:1136:2: ERROR: Problem encountered: Python >= 3.10 not
  found` con `python3.11` encontrado igual. Como ya habíamos visto que este
  mensaje puede tapar cualquier cosa, fui directo al `meson-log.txt`
  completo de nuevo en vez de asumir que era mako otra vez. El log mostró
  que el chequeo de mako ahora SÍ pasaba, pero el siguiente paso del mismo
  script (`python3 -c 'import yaml'`) fallaba con
  `ModuleNotFoundError: No module named 'yaml'` -- Mesa también usa PyYAML
  en tiempo de build (genera código de tablas de formato/extensiones desde
  YAML). Se agregó `python3-yaml` al Dockerfile (ítem 12), mismo patrón que
  mako: apt alcanza sin drama de versión. **Requiere `podman-compose
  build` antes de reintentar.**
  **Confirma la lección del error anterior:** un mismo mensaje resumido de
  Meson puede esconder más de una causa real distinta en pasos sucesivos —
  conviene revisar el `meson-log.txt` de nuevo cada vez que el mensaje
  resumido no cierre, en vez de asumir que es la misma causa ya conocida.
- **Undécimo error real (2026-09-01), ya corregido -- una suposición
  documentada resultó equivocada.** Con mako y yaml resueltos, Mesa avanzó
  mucho más lejos en el configure (todos los checks de compilador, libdrm,
  etc. en verde) y recién ahí falló:
  ```
  llvm-config found: NO need ['>= 18.0.0']
  Run-time dependency LLVM found: NO  (tried config-tool)
  ...
  ERROR: Neither a subproject directory nor a llvm.wrap file was found.
  ```
  El comentario original en `build-mesa.sh` (armado antes de correr el
  build real) asumía que alcanzaba con que `${LFS_SYSROOT}/usr/bin`
  estuviera al final del PATH para que Mesa encontrara el `llvm-config`
  nativo-con-RPATH-parcheado ahí instalado -- **esa suposición era
  incorrecta.** `dependency('llvm', method: 'config-tool')` es una
  dependencia de host machine (el target real, en terminología de Meson)
  en un build cruzado, y para ese tipo de dependencias el mecanismo
  config-tool de Meson NO cae al PATH del contenedor si el binario no está
  declarado explícito en el `[binaries]` del cross-file -- confirmado
  contra la documentación real de Meson (`llvm-config` figura ahí mismo
  como config-tool pisable) y contra el issue real `mesonbuild/meson#2921`.
  **Fix:** se agregó `llvm-config = '${LFS_SYSROOT}/usr/bin/llvm-config'`
  al `[binaries]` del cross-file en `step_mesa()`, mismo mecanismo que ya
  se usa ahí mismo para `glslangValidator`. No hizo falta tocar el
  Dockerfile ni tocar LLVM -- el binario ya andaba bien, sólo hacía falta
  decirle a Meson dónde está en vez de confiar en que lo iba a encontrar
  solo.
  **Lección:** una suposición de diseño documentada en el código (aunque
  esté bien fundamentada con research previo) sigue siendo una suposición
  hasta que el build real la confirma -- este mismo archivo ya tenía la
  cita al issue de Meson correcta, pero interpretada al revés de cómo
  terminó comportándose en la práctica.
- **Duodécimo error real (2026-09-01/02), corregido -- decisión Opción B
  tomada y research completo hecho en la PC de escritorio (48GB RAM).** Con
  `llvm-config` ya resuelto, Mesa avanzó mucho más en el configure y falló
  en:
  ```
  llvm-config found: YES (/lfs/usr/bin/llvm-config) 23.1.0
  Run-time dependency LLVM (...) found: YES 23.1.0
  Run-time dependency llvmspirvlib found: NO  (tried pkg-config)
  meson.build:2078:21: ERROR: Dependency "LLVMSPIRVLib" not found (tried pkg-config)
  ```
  **Causa raíz:** con `iris` (gallium) e `intel_vk`/anv (vulkan) habilitados
  para el Intel real del lab, el meson.build de Mesa activa
  `with_driver_using_cl` -- hace falta compilar `mesa-clc`/`intel_clc`, su
  compilador interno de OpenCL C a SPIR-V para shaders/kernels internos de
  esos dos drivers.

  Entre el corte de acceso a la compu anterior y esta sesión había quedado
  sin decidir entre dos opciones (documentadas en un archivo aparte,
  `CONTEXTO_PENDIENTE_MESA.md`, que ya se puede borrar -- este es el volcado
  completo a este archivo, como decía esa nota que había que hacer):
  - Opción A: sacar iris/intel de la config y dejar Intel para una pasada
    aparte.
  - **Opción B (la elegida, con los 48GB de la PC de escritorio):** agregar
    Clang + SPIRV-Tools + SPIRV-LLVM-Translator al pipeline de
    `build-mesa.sh` para tener las 3 GPUs (Nvidia/AMD/Intel) en esta misma
    pasada.

  **Research adicional que NO estaba en `CONTEXTO_PENDIENTE_MESA.md`** (esa
  nota se había escrito sin poder leer el `meson.build` real de
  mesa-26.2.1 -- esta vez sí, extraído directo del propio
  `sources/mesa-26.2.1.tar.gz` ya descargado, en vez de un mirror
  desactualizado de GitHub):
  - **SPIRV-Tools (`>= 2024.1`) es OBLIGATORIO además de LLVMSPIRVLib** --
    componente nuevo que la nota anterior no había detectado (`dep_spirv_tools`
    se resuelve apenas `with_clc=true`, línea ~2084 del meson.build real).
  - **`dep_clang` ya NO usa `dependency('clang', method:'cmake')`** en
    Mesa 26.2.1 (eso era de versiones viejas) -- usa
    `cpp.find_library('clang-cpp', dirs: llvm_libdir)` primero. Con
    `-Dshared-llvm=enabled` (ya lo teníamos), alcanza con que exista
    `libclang-cpp.so` en el sysroot -- mucho más simple que linkear ~15
    librerías estáticas de Clang una por una.
  - **libclc (el proyecto externo) NO hace falta**, a diferencia de lo que
    decía la nota anterior. `dep_clc` (la dependencia `libclc` externa) sólo
    se resuelve `if with_gallium_rusticl or with_microsoft_clc` -- ninguno
    de los dos está en nuestra selección de drivers
    (`iris,radeonsi,nouveau,llvmpipe` / `amd,intel`). `with_clc` queda en
    `true` igual (por iris/intel_vk), pero el código que de verdad usa
    libclc (`nir_load_libclc.c`, en `src/compiler/clc/meson.build` real)
    sólo se agrega `if dep_clc.found()`, y nunca se resuelve en nuestro
    caso. Esto simplifica bastante la Opción B: no hace falta
    cross-compilar libclc (bitcode LLVM por-target para spirv/spirv64, la
    parte más pesada y delicada que se había anticipado).
  - **SPIRV-Headers**: no tiene versión propia. SPIRV-Tools y
    SPIRV-LLVM-Translator piden cada uno un commit DISTINTO (confirmado
    contra el `DEPS` real de SPIRV-Tools y el `spirv-headers-tag.conf` real
    de SPIRV-LLVM-Translator) -- se bajan dos checkouts separados, uno por
    consumidor, en vez de asumir que son intercambiables.
  - **SPIRV-LLVM-Translator no usa tags con fecha** como SPIRV-Tools -- usa
    branches `llvm_release_XXX` (el wiki de releases del repo está
    desactualizado desde la v11, no sirve). `git ls-remote --heads` en vivo
    confirmó que existe `llvm_release_230`, y su `CMakeLists.txt` real fija
    `BASE_LLVM_VERSION=23.1.0` -- coincide exacto con nuestro LLVM, así que
    es la rama correcta (no una suposición por continuidad numérica). Se
    fijó el commit exacto que esa rama tenía al momento de este research
    (no "la punta de la rama", que se mueve).
  - **Cross-compilar Clang necesita un tool nativo nuevo**: `clang-tblgen`
    (mismo mecanismo que `llvm-tblgen`, confirmado contra
    `clang/CMakeLists.txt` real de la tag `llvmorg-23.1.0`, que documenta el
    patrón `-DCLANG_TABLEGEN=.../clang-tblgen` para sus propios builds
    "bootstrap"). `step_llvm_native()` ahora también lo compila, y
    `step_llvm()` lo pasa vía `-DCLANG_TABLEGEN=...`.

  **Todo esto ya está reflejado en `scripts/env.sh`** (versiones/commits de
  SPIRV-Headers, SPIRV-Tools y SPIRV-LLVM-Translator, con los links de dónde
  salió cada uno) **y en `scripts/build-mesa.sh`** (nuevos targets
  `spirv-headers`, `spirv-tools`, `spirv-llvm-translator`, LLVM ahora con
  `LLVM_ENABLE_PROJECTS=clang`, y `step_mesa()` con los chequeos previos
  correspondientes) -- **sin correr todavía**, queda para la próxima corrida
  real en la PC de escritorio.
- **Décimo tercer error real (2026-09-02), corregido -- primera corrida real
  de la Opción B en la PC de escritorio, falló linkeando un binario que ni
  Mesa ni nadie de este proyecto necesita:**
  ```
  : && /lfs/tools/bin/x86_64-linsi-linux-gnu-gcc --sysroot=/lfs ...
  tools/clang/tools/clang-fuzzer/dictionary/CMakeFiles/clang-fuzzer-dictionary.dir/dictionary.c.o
  -o bin/clang-fuzzer-dictionary ... lib/libLLVM.so.23.1 && :
  .../ld: warning: libstdc++.so.6, needed by lib/libLLVM.so.23.1, not found
  .../ld: lib/libLLVM.so.23.1: undefined reference to
  `std::ctype<char>::_M_widen_init() const@GLIBCXX_3.4.11'
  [... decenas más de símbolos GLIBCXX/CXXABI sin resolver ...]
  collect2: error: ld returned 1 exit status
  ninja: build stopped: subcommand failed.
  ```
  **Causa raíz:** `step_llvm()` pedía `ninja` sin target (= "all"), que
  intenta construir los ~4600 targets de LLVM+Clang, incluidas ~180
  herramientas standalone que este proyecto no usa (`llvm-mca`,
  `llvm-objdump`, `clang-fuzzer-dictionary`, etc.). `clang-fuzzer-dictionary`
  (en `clang/tools/clang-fuzzer/dictionary/`) es, de toda esa lista, la
  ÚNICA que se arma desde una fuente puramente en C (`dictionary.c`) --
  CMake por eso elige `gcc` (no `g++`) como driver de link para ese target
  puntual, y `gcc` no agrega `-lstdc++` automáticamente aunque el binario
  dependa de `libLLVM.so` (que sí es C++). Confirmado contra el
  `CMakeLists.txt` real de ese directorio (tag `llvmorg-23.1.0`): no hay
  ningún flag de CMake que lo desactive individualmente --
  `add_clang_subdirectory(clang-fuzzer)` en `clang/tools/CMakeLists.txt` es
  incondicional. Importante: esto NO es un problema de `libLLVM.so` ni de
  `libclang-cpp.so` en sí -- ambas ya habían linkeado bien antes en el mismo
  log; el que falla es un binario de test/fuzzing que no nos interesa.

  **Fix real:** en vez de parchear ese target puntual (ni ninguno de los
  otros ~180 que tampoco usamos), dejar de pedir "all" y pedirle a ninja
  sólo los 4 targets con nombre bien definido que Mesa efectivamente
  necesita (confirmado contra `llvm/CMakeLists.txt` y `clang/CMakeLists.txt`
  reales): `LLVM` (el .so, `dep_llvm` de Mesa), `clang-cpp` (el .so,
  `dep_clang`), `llvm-headers` y `clang-headers` (headers instalados, los
  usa `mesa-clc`/`clc_helpers.cpp` directo). Cada uno trae un target
  `install-<nombre>` autogenerado por `add_llvm_install_targets()`
  (`AddLLVM.cmake` real) que depende sólo de construir el target
  correspondiente -- entonces `ninja LLVM clang-cpp llvm-headers
  clang-headers` + `ninja install-LLVM install-clang-cpp install-llvm-headers
  install-clang-headers` nunca le pide nada a ninja sobre
  `clang-fuzzer-dictionary` ni el resto de binarios sueltos que no usamos.
  Ya aplicado en `step_llvm()` de `build-mesa.sh`, validado con `bash -n` y
  `shellcheck -S warning -e SC1091` (limpio), sin tocar `step_verify_llvm()`
  (sigue buscando `libLLVM*.so*`/`libclang-cpp.so*` en el sysroot, que estos
  4 targets siguen produciendo igual).

  **Lección:** al cross-compilar un proyecto ajeno enorme (LLVM/Clang acá),
  nunca pedir el target por defecto ("all"/sin target) sólo porque "compila
  todo, seguro"-- ese "todo" casi siempre incluye binarios de test/fuzzing/
  debug que ni el proyecto propio necesita y que pueden fallar por razones
  que no tienen nada que ver con lo que en verdad se está usando. Conviene
  identificar los targets de librería/instalación puntuales que el
  consumidor real (acá, Mesa) necesita y pedir sólo esos.
- **Décimo cuarto error real (2026-09-02), corregido -- efecto colateral
  directo del error anterior, apareció en la misma corrida al llegar a
  SPIRV-LLVM-Translator (con SPIRV-Tools ya compilado e instalado sin
  problemas):**
  ```
  -- Using SPIR-V Headers from
            /lfs/build/SPIRV-Headers-575b6512579ebde466ed3dfc04e413439d14d95d
  CMake Error at CMakeLists.txt:82 (find_package):
    Could not find a package configuration file provided by "LLVM"
    (requested version 23.1.0) with any of the following names:
      LLVMConfig.cmake
      llvm-config.cmake
    Add the installation prefix of "LLVM" to CMAKE_PREFIX_PATH or set
    "LLVM_DIR" to a directory containing one of the above files.
  -- Configuring incomplete, errors occurred!
  ```
  **Causa raíz:** al acotar `step_llvm()` a los 4 targets `LLVM
  clang-cpp llvm-headers clang-headers` (fix del error anterior), quedó
  afuera -sin querer- un quinto componente que ningún consumidor había
  necesitado hasta ahora: `LLVMConfig.cmake` (+ `LLVMConfigVersion.cmake` +
  `LLVMExports.cmake`), lo que usa `find_package(LLVM)` de
  SPIRV-LLVM-Translator para ubicar a LLVM. `-DLLVM_DIR=.../usr/lib/cmake/llvm`
  ya estaba bien puesto en `step_spirv_llvm_translator()` -- el problema es
  que ese directorio quedaba vacío, porque esos `.cmake` no los instala
  `install-LLVM` ni ninguno de los otros tres. Confirmado contra el
  `llvm/cmake/modules/CMakeLists.txt` real (tag `llvmorg-23.1.0`): esos
  archivos se generan con `configure_file()` en tiempo de *cmake* (ya
  existen apenas corre el `cmake -S ... -B ...` de `step_llvm()`, no hace
  falta compilar nada más) y se instalan con `COMPONENT cmake-exports`,
  vía un target autogenerado aparte, `install-cmake-exports` (mismo
  mecanismo `add_llvm_install_targets()` de siempre, pero sin `DEPENDS`
  -- por eso no arrastra ningún build adicional).

  **Fix real:** agregar `install-cmake-exports` a la línea de `ninja
  install-*` de `step_llvm()`, junto a los otros cuatro. No hizo falta
  tocar la línea de build (`ninja LLVM clang-cpp llvm-headers
  clang-headers`), porque este componente no compila nada, sólo copia
  archivos ya generados. Se sumó también un chequeo de
  `LLVMConfig.cmake` a `step_verify_llvm()`, para que la falta de este
  componente puntual se detecte ahí la próxima vez y no recién en
  SPIRV-LLVM-Translator, dos pasos después. Validado con `bash -n` y
  `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** cuando se acota un target grande a sólo lo que un
  consumidor conocido necesita (Mesa, en el error anterior), conviene
  revisar también qué necesitan los pasos *intermedios* del propio
  pipeline (acá, SPIRV-LLVM-Translator, que no es lo que Mesa linkea
  directamente pero sí depende de encontrar a LLVM vía CMake) antes de
  asumir que la lista de targets ya está completa.

  **Esta lección queda corregida por el error siguiente (Décimo quinto):
  acotar targets de LLVM/Clang a mano no compone con `find_package(LLVM)`
  en modo CONFIG, sin importar cuántos componentes intermedios se vayan
  agregando a mano. La forma correcta era otra desde el principio.**
- **Décimo quinto error real (2026-09-02), corregido -- con
  `install-cmake-exports` ya instalado (fix anterior), CMake avanzó un
  paso más en SPIRV-LLVM-Translator y volvió a fallar, ahora tratando de
  *usar* un componente de LLVM que nunca se instaló:**
  ```
  CMake Error at /lfs/usr/lib/cmake/llvm/LLVMExports.cmake:1148
  (message):
    The imported target "LLVMDemangle" references the file
       "/lfs/usr/lib/libLLVMDemangle.a"
    but this file does not exist.
  -- Configuring incomplete, errors occurred!
  ```
  (con los correspondientes fallos en cascada de
  `step_verify_spirv_llvm_translator()` y, más abajo, de Mesa y su
  verificación -- ambos consecuencia directa de este mismo error, no
  bugs nuevos).

  **Causa raíz:** acotar el *build* a 4 targets (Ronda 2 del error
  anterior) nunca acota lo que CMake *exporta*. Confirmado contra
  `AddLLVM.cmake` real: la macro `add_llvm_library` (y
  `add_llvm_component_library`, que la usa por dentro) agrega SIEMPRE el
  nombre de cada librería a la propiedad global `LLVM_EXPORTS`, sin
  ninguna condición sobre si esa librería terminó siendo parte del build
  pedido. LLVM define ~80 de estas librerías (`LLVMDemangle`,
  `LLVMSupport`, `LLVMCore`, etc.); pedir sólo `LLVM`/`clang-cpp`/
  `llvm-headers`/`clang-headers` construyó igual el `.so` agregado
  (`libLLVM.so`) pero no las ~80 librerías estáticas individuales que lo
  componen. `LLVMExports.cmake` (generado por `install-cmake-exports`,
  ya instalado) las lista a todas igual, apuntando a rutas
  (`libLLVMDemangle.a`, etc.) que jamás se compilaron. Cualquier
  consumidor en modo `find_package(LLVM CONFIG)` (como
  SPIRV-LLVM-Translator) carga ese archivo entero al hacer
  `include(LLVMExports.cmake)`, así que basta con que UN componente
  falte para que falle la configuración completa, aunque el proyecto en
  cuestión sólo use `LLVM`/`clang-cpp`. No hay forma de acotar el build
  "desde afuera" (eligiendo qué construir) que sea compatible con este
  mecanismo -- hay que acotarlo "desde adentro", con el mecanismo que
  LLVM ya provee para eso.

  **Fix real:** revertir por completo el acotado de targets de la Ronda
  2 -- volver a `ninja` (sin argumentos) y `ninja install` (sin
  argumentos) en `step_llvm()`, o sea el build e install COMPLETOS,
  igual que antes del Décimo tercer error. Para evitar el problema
  original de esa ronda (el link roto de `clang-fuzzer-dictionary`), se
  usa en cambio el mecanismo real que LLVM expone para esto: cada
  subcarpeta de `clang/tools/` recibe automáticamente un flag
  `CLANG_TOOL_<NOMBRE>_BUILD` (confirmado contra
  `create_subdirectory_options()`, invocada como
  `create_subdirectory_options(CLANG TOOL)` al principio del
  `clang/tools/CMakeLists.txt` real, y consumida por
  `add_llvm_subdirectory()`/`add_clang_subdirectory()` en
  `AddLLVM.cmake`/`AddClang.cmake`). Agregando
  `-DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF` al `cmake` de configuración, esa
  subcarpeta ni siquiera se agrega al build (`add_subdirectory()` no se
  llama), así que `clang-fuzzer-dictionary` desaparece del grafo de
  ninja sin tocar ningún otro target -- y con el build completo, las ~80
  librerías que `LLVMExports.cmake` necesita quedan todas instaladas de
  verdad. Ya aplicado en `step_llvm()` de `build-mesa.sh`; no hizo falta
  tocar `step_verify_llvm()` (los chequeos existentes de
  `libLLVM*.so*`/`libclang-cpp.so*`/`llvm-config --includedir`/
  `LLVMConfig.cmake` siguen siendo válidos, ahora con más garantía
  porque todo lo que verifican existe de verdad). Validado con `bash -n`
  y `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** cuando un proyecto de terceros expone un mecanismo
  genérico para desactivar partes puntuales del build (acá,
  `create_subdirectory_options()` + `<PROYECTO>_<TIPO>_<NOMBRE>_BUILD`),
  conviene buscarlo primero y usarlo, en vez de tratar de lograr el
  mismo resultado "desde afuera" acotando a mano qué targets pedirle a
  ninja. Lo segundo puede funcionar para el build en sí, pero rompe
  silenciosamente cualquier mecanismo del proyecto que asuma que "lo que
  se construye" y "lo que se declara disponible" (acá, `LLVM_EXPORTS`)
  son la misma cosa -- como pasó acá con dos errores reales seguidos
  (Décimo cuarto y Décimo quinto) que en realidad eran síntomas del
  mismo problema de fondo.
- **Décimo sexto error real (2026-09-02), corregido -- con LLVM+Clang y
  SPIRV-LLVM-Translator ya completos en el sysroot (Décimo quinto error
  ya resuelto), la corrida real de `mesa` avanzó bastante más lejos que
  nunca antes en este proyecto y recién ahí frenó:**
  ```
  Run-time dependency LLVM (modules: ...) found: YES 23.1.0
  Run-time dependency llvmspirvlib found: YES 23.1.0.0
  Run-time dependency spirv-tools found: YES 2026.3.1
  Library clang-cpp found: YES
  Run-time dependency libelf found: NO  (tried pkg-config and cmake)
  Library elf found: NO
  meson.build:2149:2: ERROR: Problem encountered: Gallium driver
    radeonsi requires libelf
  ```
  (con la consiguiente falla en cascada de `verify-mesa`, que reportó
  faltantes de `iris_dri.so`, `radeonsi_dri.so`, `nouveau_dri.so`,
  `swrast_dri.so`, `libvulkan_radeon.so`, `libvulkan_intel.so` y
  `libEGL.so` -- todos consecuencia directa de que Mesa nunca llegó a
  compilar nada, no bugs nuevos).

  **Causa raíz:** el driver Gallium `radeonsi` (AMD, elegido para la RX
  7700 real del lab -- ver aviso al principio de `build-mesa.sh`) usa
  libelf en su runtime linker de ELF (`src/amd/common/ac_rtld.c`, para
  relocar en tiempo de ejecución los binarios que el propio backend
  AMDGPU de LLVM produce al compilar shaders) -- no es opcional para
  esta selección de drivers. Ningún paso anterior de este proyecto
  compiló libelf para `${LFS_TGT}`: el `libelf-dev` que ya estaba en el
  `Dockerfile` es del compilador NATIVO del contenedor (build machine),
  y esto es un build cruzado -- Mesa resuelve dependencias contra
  `${LFS_SYSROOT}`, no contra el sysroot del host, así que ese paquete
  de apt no cuenta para nada acá.

  **Fix real:** se agregó `step_elfutils()`/`step_verify_elfutils()`
  nuevos a `build-mesa.sh` (entre SPIRV-LLVM-Translator y Mesa, tanto en
  el dispatch de `main()` como en la secuencia `all`), y una
  precondición nueva en `step_mesa()` que frena con mensaje claro si
  falta. Se compila el paquete elfutils COMPLETO por Autotools
  (`--host=${LFS_TGT} --build=$(build_triplet) --prefix=/usr`, mismo
  patrón que `step_libnftnl()` de `build-security.sh`), NO sólo el
  subdirectorio `libelf/` a mano: confirmado contra el `Makefile.am`
  real del proyecto (rama principal, research en vivo del 2026-09-02)
  que `SUBDIRS` ahí es una lista fija sin ningún equivalente al
  `create_subdirectory_options()` de LLVM/Clang -- no hay mecanismo
  oficial para levantar sólo una parte, así que recortarlo a mano acá
  hubiera repetido el mismo error de fondo que el Décimo quinto (ver su
  Lección, arriba). No hacía falta arriesgarse: elfutils es chico,
  construir debuginfod/libdw/libasm/eu-* de más son segundos, no las
  horas de LLVM.

  Tampoco se instala/verifica un `libelf.pc`: confirmado contra
  `libelf/Makefile.am` real que esta librería nunca generó uno (no hay
  `libelf.pc.in` en el árbol) -- por eso el log de Mesa arriba prueba
  las DOS rutas (`Run-time dependency` vía pkg-config/cmake, y por
  separado `Library elf` vía `cc.find_library`) antes de rendirse; a
  nosotros nos alcanza con que exista `libelf.so` instalado, que es lo
  que la segunda ruta encuentra. `step_verify_elfutils()` chequea
  `libelf.h` + `libelf.so*` en el sysroot, no un `.pc` inexistente.

  Flags de configure elegidos: `--disable-nls` (no hace falta i18n
  acá); `--disable-libdebuginfod`/`--disable-debuginfod` (el
  `configure.ac` real ya los deja en "no" solo si no encuentra
  libcurl/json-c/libmicrohttpd/libarchive/sqlite3 -- ninguno está en el
  sysroot -- pero se pasan explícitos para no depender de ese
  autodescubrimiento, mismo criterio que ya se usa en todo el proyecto
  para lo que se elige apagar a propósito). zlib (el único requisito
  "mandatory" real de elfutils, confirmado contra el `configure.ac`:
  "zlib is mandatory") ya estaba en el sysroot desde `build-comms.sh`;
  bzip2/xz/zstd quedan en su default "auto" y se autodesactivan solos.

  Efecto secundario necesario: `build-mesa.sh` no tenía ningún paso
  Autotools hasta ahora (libdrm/LLVM/SPIRV-*/Mesa son todos Meson o
  CMake), así que tampoco tenía el helper `build_triplet()` que sí
  existe en `build-security.sh`/`build-desktop.sh`/
  `build-userspace.sh`/`build-comms.sh` -- se agregó la misma
  definición exacta (`"${LFS_BUILD}/binutils-${BINUTILS_VERSION}/config.guess"`)
  a `build-mesa.sh`. Sin este agregado, `step_elfutils()` hubiera
  fallado en runtime con "build_triplet: command not found" -- se
  encontró revisando qué helpers locales tiene realmente el archivo
  antes de dar el fix por terminado, no asumiendo que estaba porque
  otros scripts del proyecto lo tienen.

  Versión de elfutils (`0.191`) y su mirror (`sourceware.org/elfutils/ftp`)
  quedaron marcados `VERIFICAR` en `env.sh`: `sourceware.org` devolvió
  403 desde este sandbox de research (mismo problema ya documentado ahí
  para zlib.net/gitlab.fd.o), así que la versión se confirmó indirecto
  contra la portada real del proyecto en vez de por fetch directo del
  tarball -- pero `LVM2_MIRROR`/`BZIP2_MIRROR` de este mismo `env.sh` ya
  usan `sourceware.org` con éxito en corridas reales de este proyecto,
  así que el dominio en sí no debería ser problema para el contenedor
  del usuario. Falta confirmación empírica de esta corrida puntual.

  Validado con `bash -n` y `shellcheck -S warning -e SC1091` (limpio)
  sobre `build-mesa.sh` y `env.sh`.

  **Lección:** un dependencia "hard requirement" de un driver
  específico (acá, radeonsi -> libelf) puede quedar completamente
  invisible hasta que el build real llega literalmente a esa línea del
  `meson.build` -- ni el research previo de Mesa (que sí encontró
  Clang/SPIRV-Tools/LLVMSPIRVLib de antemano, leyendo el `meson.build`
  real) lo había marcado, porque el research se había enfocado en
  `with_driver_using_cl` (Intel) y no en los requisitos propios de cada
  gallium driver elegido por separado. Conviene, para la Parte 3 en
  adelante, revisar los `meson.build`/`CMakeLists.txt` reales de lo que
  sigue buscando explícitamente cada línea de `require`/`error` por
  driver/feature habilitado, no sólo las dependencias que ya se sabía
  que iban a hacer falta.
- **Décimo séptimo error real (2026-09-02), corregido -- primera corrida
  real de `step_elfutils()` (fix anterior) rompió compilando `libcpu/`,
  ni siquiera llegó a Mesa (`libelf` de hecho compiló bien, antes de
  `libcpu/` en el orden de `SUBDIRS`):**
  ```
  ../../libcpu/riscv_disasm.c: In function 'riscv_disasm':
  ../../libcpu/riscv_disasm.c:1259:46: error: initialization discards
    'const' qualifier from pointer target type
    [-Werror=discarded-qualifiers]
   1259 |                   struct known_csrs *found = bsearch (&key, known,
        |                                              ^~~~~~~
  cc1: all warnings being treated as errors
  make[2]: *** [Makefile:547: riscv_disasm.o] Error 1
  ```
  Primer intento de fix: un parche de una línea con `sed` a ese archivo
  puntual (agregar el `const` que faltaba en la declaración de `found`),
  confirmado contra el mirror de GitHub del branch principal de
  elfutils que ya tiene esa misma línea arreglada río arriba. Ese parche
  compiló bien, pero la corrida siguiente (con `libcpu/` ya sin
  problemas) rompió en otro lado:
  ```
  ../../libdw/dwarf_getsrclines.c: In function 'read_srclines':
  ../../libdw/dwarf_getsrclines.c:332:27: error: initialization discards
    'const' qualifier from pointer target type
    [-Werror=discarded-qualifiers]
    332 |           uint8_t *endp = memchr (dirp, '\0', lineendp - dirp);
        |                           ^~~~~~
  [... dos ocurrencias más del mismo patrón en el mismo archivo,
  líneas 408 y 796 ...]
  cc1: all warnings being treated as errors
  make[3]: *** [Makefile:909: dwarf_getsrclines.o] Error 1
  ```
  (con las caídas en cascada esperables de `verify-elfutils`, `mesa` --
  frenada limpio por la precondición de `step_mesa()`, tal como se
  diseñó -- y `verify-mesa`: ningún driver de Mesa se llegó a compilar
  porque Mesa ni arrancó.)

  **Causa raíz:** el mismo bug de fondo en DOS archivos distintos --
  SISTÉMICO, no un typo puntual en `riscv_disasm.c`. El glibc
  cross-compilado de este proyecto (Fase 2) le da a varias funciones de
  `<string.h>`/`<search.h>` (`bsearch`, `memchr`, y probablemente otras
  que todavía no se tocaron) overloads const-correctos bajo
  `_FORTIFY_SOURCE=3` (activo acá, confirmado en el log de `configure`:
  "checking whether to add -D_FORTIFY_SOURCE=2 or =3 to CFLAGS... yes
  -D_FORTIFY_SOURCE=3") -- devuelven un puntero `const` cuando el
  argumento de entrada ya es `const`. elfutils 0.191 es de antes de que
  esos overloads existieran en glibc, así que varios lugares del código
  asignan ese resultado a una variable sin `const`. Cada uno de esos
  choca con `-Werror=discarded-qualifiers`, que elfutils trae de
  fábrica (confirmado contra `config/eu.am` real:
  `AM_CFLAGS` incluye `$(if $($(*F)_no_Werror),,-Werror)`, sin ningún
  `--disable-werror` global que lo apague entero). Ninguno de los dos
  archivos afectados hasta ahora es algo que este proyecto use
  (`riscv_disasm.c` es el desensamblador RISC-V; `dwarf_getsrclines.c`
  es DWARF, que tampoco hace falta para `libelf` -- Mesa sólo necesita
  la librería `libelf` en sí, no `libdw`), pero como es TODO el paquete
  el que se compila (ver Décimo sexto error real, arriba, y su
  justificación de por qué no se acota a mano), no alcanza con parchear
  archivo por archivo cada vez que aparece uno nuevo -- no hay forma de
  saber cuántos más hay sin correr el build completo primero.

  **Fix real (reemplaza el parche de `riscv_disasm.c` de arriba):** en
  vez de seguir parchando archivo por archivo, `step_elfutils()` ahora
  pasa `CFLAGS="-g -O2 -Wno-error=discarded-qualifiers"` al `configure`,
  apagando SÓLO esa clase de warning (el resto de los `-Werror` de
  elfutils sigue intacto) para TODO el paquete de una vez. Funciona
  porque, confirmado contra `config/eu.am` real, la regla de compilación
  de Automake pone `$(AM_CFLAGS)` (donde vive el `-Werror` de fábrica de
  elfutils) ANTES que `$(CFLAGS)` en la línea real de `gcc` -- un
  `-Wno-error=<clase>` que aparece DESPUÉS en la misma línea de comando
  gana para esa clase puntual, sin tocar el resto. Se agrega `-g -O2`
  explícito porque autoconf sólo los pone de default si `CFLAGS` viene
  sin setear desde afuera -- si el proyecto lo setea (como acá), hay que
  repetirlos a mano o se pierden; confirmado contra el `configure.ac`
  real que lo que se pase acá sobrevive completo hasta el `Makefile`
  final (el bloque de detección de `_FORTIFY_SOURCE` hace
  `CFLAGS="$fortified_cflags $save_CFLAGS"`, anteponiendo
  `-D_FORTIFY_SOURCE=3` a lo que ya había, sin descartarlo). El parche
  de una línea a `riscv_disasm.c` se sacó del script (ya no hace falta,
  este fix lo cubre a él también). Validado con `bash -n` y
  `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** cuando un `-Werror` heredado de un proyecto de terceros
  (no algo que este proyecto haya elegido) rompe por el mismo patrón de
  incompatibilidad compilador/libc en MÁS DE UN archivo, no conviene
  seguir la misma respuesta puntual del primer error (un parche de una
  línea) para el segundo -- esa repetición es la señal de que el bug es
  sistémico, y ahí conviene apagar la clase de warning específica en vez
  de perseguir cada archivo nuevo build tras build. Apagar sólo esa
  clase (no todo `-Werror`) mantiene el resto del control de calidad de
  elfutils intacto -- es un punto intermedio entre "parchear cada
  archivo a mano" (no escala) y "bajar todos los warnings a nivel
  proyecto" (demasiado general, tira control de calidad real que no
  tiene nada que ver con este bug puntual).

- **Décimo octavo error real (2026-09-02/03), fix INSUFICIENTE (corregido/
  completado recién por el Décimo noveno, más abajo) -- con elfutils ya
  completo (Décimo séptimo error), el `meson setup` de Mesa pasó entero
  (`Run-time dependency libelf found: YES 0.191`, 467 build targets) y
  `ninja` llegó a construir 1370/2879 targets, mucho más lejos que en
  cualquier intento anterior, antes de romper acá:**
  ```
  FAILED: src/intel/blorp/blorp_shaders.spv
  .../build/src/compiler/clc/mesa_clc -o src/intel/blorp/blorp_shaders.spv ...
  .../build/src/compiler/clc/mesa_clc: error while loading shared
    libraries: libLLVM.so.23.1: cannot open shared object file: No such
    file or directory
  ninja: build stopped: subcommand failed.
  ```
  Consecuencia esperable de que `ninja` frenó a mitad de camino:
  `verify-mesa` volvió a mostrar TODOS los drivers como `[FALTA]` --
  igual que antes de este intento, aunque la causa real ya es otra por
  completo (por eso "siguen los mismos faltantes" en la salida es
  engañoso: el build llegó muchísimo más lejos que nunca).

  **Causa raíz:** con `iris`/`intel_vk` habilitados, Mesa compila
  `mesa_clc` (`src/compiler/clc/mesa_clc`) -- un ejecutable que el propio
  `ninja` invoca EN TIEMPO DE BUILD (no al final) para traducir shaders
  internos en OpenCL C (`blorp_shaders.cl`, etc.) a SPIR-V. Mismo
  mecanismo ya documentado para `llvm-config` en `step_llvm()`: el
  `--cross-file` de Mesa pisa `llvm-config` apuntando a
  `${LFS_SYSROOT}/usr/bin/llvm-config` -- un binario que, aunque es
  NATIVO de arquitectura, se compiló con
  `-DCMAKE_INSTALL_PREFIX="${LFS_SYSROOT}/usr"`, así que reporta rutas de
  link/include DENTRO del sysroot cruzado. Meson linkea `mesa_clc` contra
  ESE `llvm-config`, y el binario resultante termina apuntando a la
  `libLLVM.so` CRUZADA de `${LFS_SYSROOT}/usr/lib` en vez de la nativa
  real de `${LLVM_NATIVE_BUILD}/lib` -- y como este proyecto nunca
  chrootea a `/lfs`, el loader real del contenedor no la encuentra. Es el
  mismo patrón de fondo que "CORREGIDO (2026-08-29)" en `env.sh`
  (`wayland-scanner`/`glib-compile-resources`: un ejecutable de
  arquitectura nativa, pero linkeado sin querer contra una librería del
  sysroot cruzado).

  A diferencia de `wayland-scanner`/`glslangValidator`, `mesa_clc` no se
  puede reconstruir aparte en un prefix propio -- es un target más
  dentro del mismo árbol de build de Mesa, generado por el propio
  `meson.build` de Mesa, no un paquete externo.

  **Fix:** en `step_mesa()`, antes del `ninja -C "${bdir}" ${MAKEFLAGS}`
  completo, se agregó un paso previo que (a) usa
  `ninja -C "${bdir}" -t targets all` para listar TODOS los targets del
  grafo ya generado por `meson setup` y filtra los que terminan en
  `clc` (cubre `mesa_clc` y cualquier otro ejecutable `*_clc` que Mesa
  agregue, sin hardcodear el nombre), (b) los compila aparte con
  `ninja -C "${bdir}" ${MAKEFLAGS} <targets>`, y (c) les corrige el
  RPATH con `patchelf --set-rpath "${LLVM_NATIVE_BUILD}/lib"` -- la
  MISMA librería nativa que ya usa `llvm-config` nativo (ver
  `step_llvm()`, mismo mecanismo, mismo directorio). Recién después de
  eso se lanza el `ninja -C "${bdir}" ${MAKEFLAGS}` completo: `ninja` no
  vuelve a linkear esos binarios (ninguno de sus inputs cambió), así que
  el RPATH corregido sobrevive intacto cuando el resto del build los
  invoca para generar los `.spv`. Se valida `command -v patchelf`
  primero (mismo chequeo que ya usa `step_llvm()`). Validado con
  `bash -n` y `shellcheck -S warning -e SC1091` (limpio).

  **Lección (esta parte sigue siendo válida):** la lección de `env.sh`
  ("si una herramienta de build falla con 'error while loading shared
  libraries', la solución NO es tocar LD_LIBRARY_PATH -- es conseguir una
  versión genuinamente nativa y apuntarle el RPATH") se sigue cumpliendo
  incluso cuando la herramienta problemática no es un paquete aparte sino
  un target intermedio del mismo build -- hace falta un paso de `ninja`
  explícito y acotado ANTES del build completo, en vez de un post-build
  único como con `llvm-config`, porque acá el binario se usa DURANTE el
  resto de la compilación, no después. **Lo que este error NO tenía en
  cuenta (ver Décimo noveno):** el `patchelf --set-rpath` se aplicó
  limpio, sin ningún error, pero el corte de build volvió a pasar
  EXACTAMENTE IGUAL en el intento siguiente -- ese fue el motivo real de
  "che, podés trabajar en serio? porque siguen los mismos faltantes" del
  usuario. Un fix que corre sin errores no es lo mismo que un fix
  verificado: faltó comprobar, ANTES de dar el tema por cerrado, que
  `${LLVM_NATIVE_BUILD}/lib` realmente tuviera algo adentro para que el
  RPATH apuntara.

- **Décimo noveno error real (2026-09-03), parte 2 del fix REVERTIDA por el
  Vigésimo error real (2026-09-04, ver más abajo) -- el resto de este fix
  (partes 1 y 3) sigue vigente y correcto:**

- **Décimo noveno error real (2026-09-03), corregido -- mismo error que el
  Décimo octavo (`mesa_clc: error while loading shared libraries:
  libLLVM.so.23.1: cannot open shared object file`), IDÉNTICO en el
  siguiente intento pese al patchelf de RPATH ya aplicado:**

  **Causa raíz real, en dos partes (confirmadas con `readelf -d` y `ldd`
  reales sobre el `mesa_clc` construido, a pedido explícito -- correr esto
  no toca el build, sólo lee lo que ya estaba compilado):**
  ```
   0x000000000000001d (RUNPATH)  [/lfs/build/llvm-native-build/lib]
   NEEDED  libLLVM.so.23.1
   NEEDED  libclang-cpp.so.23.1
   ...
  /lib/x86_64-linux-gnu/libstdc++.so.6: version `GLIBCXX_3.4.32' not found
  /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found
          libLLVM.so.23.1 => not found
          libclang-cpp.so.23.1 => not found
  ```
  1. `ls -la ${LLVM_NATIVE_BUILD}/lib` mostró que ese directorio, hasta
     este momento, sólo tenía los `.a` estáticos de `llvm-tblgen`/
     `llvm-config`/`clang-tblgen` -- CERO `.so`. El RPATH del Décimo
     octavo apuntaba, sin fallar, a un directorio real pero VACÍO de lo
     que hacía falta -- de ahí que "corriera sin error" y aun así no
     sirviera de nada.
  2. Más de fondo (esto es lo que el Décimo octavo no vio): `mesa_clc`
     pedía símbolos de glibc/libstdc++ MÁS NUEVOS que los del contenedor
     (`GLIBC_2.38`, Debian bookworm trae 2.36; `GLIBCXX_3.4.32`, más nueva
     que la de `build-essential`/gcc-12 de bookworm) -- un choque de
     VERSIÓN (mismo patrón que `spa-json-dump` en `build-desktop.sh`), no
     un problema de RPATH, y ningún patchelf lo arregla porque está
     grabado en el propio código objeto (símbolos versionados que pide el
     binario). Confirmado leyendo el `meson.build` real de Mesa
     (`src/compiler/clc/meson.build`, mirror de GitHub `mirror/mesa`):
     ```
     native : not meson.can_run_host_binaries(),
     ```
     con el comentario real de Mesa arriba: "If we can run host binaries
     directly, just build mesa_clc for the host. Most commonly this
     happens when doing a cross compile from an x86_64 build machine to
     an x86 host". Acá `LFS_TGT` es la MISMA arquitectura que el host
     (x86_64), así que `can_run_host_binaries()` da `true`, `native` da
     `false`, y Mesa compila `mesa_clc` con el compilador del
     **cross-file** (el propio cross-toolchain de Fase 0) en vez del
     `--native-file` -- exactamente la misma trampa que ya describe
     "CORREGIDO (2026-08-29)" en `env.sh` para `wayland-scanner`/
     `glib-compile-resources`, pero acá Mesa la elige a propósito como
     optimización (asume que un binario del host, misma arquitectura,
     corre bien directo) -- una asunción válida en un cross-compile típico
     (host más nuevo que el target embebido) pero FALSA acá, donde el
     target (`LFS_TGT`) es la glibc RECIÉN compilada, más nueva que la del
     contenedor. Confirmado también contra el `meson.build` real de la
     raíz de Mesa: `dep_llvm`/`dep_spirv_tools` se declaran SIN `native:`
     en ningún lado, así que siempre se resuelven en contexto host/cruzado
     (vía el `llvm-config` del `--cross-file`) sin importar si el
     ejecutable que los consume es `native:true` o no -- es el mismo
     mecanismo real que usa cualquier cross-build de verdad de Mesa (ARM,
     etc.): `mesa_clc` nativo, pero linkeado igual contra el `dep_llvm`
     del host/cruzado.

  **Fix, tres partes (`step_llvm_native()` + `step_mesa()` en
  `build-mesa.sh`):**
  1. `step_llvm_native()` ahora TAMBIÉN construye los targets de CMake
     `LLVM` y `clang-cpp` (antes sólo pedía `llvm-tblgen llvm-config
     clang-tblgen`) -- con `-DCLANG_LINK_CLANG_DYLIB=ON` agregado a su
     `cmake` (mismo flag que ya usa `step_llvm()` del lado cruzado) y
     `-DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF` por las dudas (mismo motivo que
     `step_llvm()`, aunque acá no debería hacer falta al pedir targets
     puntuales). Esto deja `libLLVM.so`/`libclang-cpp.so` NATIVAS de
     verdad en `${LLVM_NATIVE_BUILD}/lib`, con verificación explícita
     (`find ... || die`) de que existan antes de seguir.
  2. **[REVERTIDO por el Vigésimo error real, 2026-09-04 -- ver esa entrada
     más abajo, NO aplicar este paso]** En `src/compiler/clc/meson.build`
     (fuente de Mesa ya descomprimida), un `sed` idempotente + verificado
     cambiaba `native : not meson.can_run_host_binaries(),` por
     `native : true,` (con cuidado de no "tragarse" la coma final adentro
     del comentario agregado -- un caso de prueba real confirmó que un
     primer intento sin esto rompía la sintaxis del `meson.build`). Esto
     forzaba a `mesa_clc` a compilarse con el compilador NATIVO de punta a
     punta, eliminando el choque de versión de glibc/libstdc++ -- pero
     dejaba a `mesa_clc` (ahora `native:true`) linkeando contra
     `idep_mesaclc`/`_libmesaclc`, que sigue sin `native:` en ese mismo
     archivo (contexto host/cruzado por default): el siguiente `meson
     setup` rompía con "Tried to mix a host machine library ("libmesaclc")
     with a build machine target "mesa_clc"". Ver Vigésimo error real.
  3. El `patchelf --set-rpath "${LLVM_NATIVE_BUILD}/lib"` del Décimo
     octavo se deja tal cual, como red de seguridad -- Meson no siempre
     agrega un RPATH automático para una dependencia resuelta por
     config-tool (como `dep_llvm` acá), así que aunque `mesa_clc` ya
     compile nativo, puede seguir sin encontrar `libLLVM.so`/
     `libclang-cpp.so` en tiempo de ejecución sin esto -- la diferencia
     con el Décimo octavo es que esta vez el directorio al que apunta
     tiene contenido real (parte 1).
  3 nuevas verificaciones agregadas en `step_mesa()`: falla temprano y
  claro si `${LLVM_NATIVE_BUILD}/lib` no tiene `libLLVM.so`/
  `libclang-cpp.so` nativas, y si el `sed` al `meson.build` de Mesa no
  encontró el texto esperado (evita un fix silencioso a medias si Mesa
  cambia de versión). Validado con `bash -n` y
  `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** que un `patchelf`/fix corra sin tirar error no prueba que
  haya arreglado el problema real -- hay que verificar el resultado
  (`ldd`, o el propio build volviendo a andar) antes de dar un error por
  cerrado, más todavía cuando el mensaje de error que sigue apareciendo es
  IDÉNTICO al de antes: esa repetición exacta es la señal de que el fix
  anterior no tocó la causa de fondo, no de que "sea el mismo problema de
  siempre" sin más (acá, de hecho, el build había avanzado muchísimo --
  1370/2879 antes vs. terminar la fase de compilación entera y llegar al
  link del binario final ahora -- el mensaje de error idéntico escondía
  una causa distinta). Separado de eso: cuando una herramienta de
  build-time que el propio proyecto de terceros compila (no un paquete
  externo que buscamos) decide sola si compilarse nativa o cruzada según
  "misma arquitectura = corre directo" (`can_run_host_binaries()`), esa
  asunción vale para el caso típico de cross-compiling (target más viejo/
  chico que el host) pero no necesariamente para este proyecto, donde el
  "target" tiene una glibc más nueva que el propio contenedor de build --
  hay que estar atento a este patrón en cualquier build de terceros que
  Mesa/LLVM/otros activen más adelante, no sólo acá.

- **Vigésimo error real (2026-09-04), corregido -- consecuencia directa de
  la parte 2 del fix del Décimo noveno (el `sed` a
  `src/compiler/clc/meson.build` forzando `native : true` en el
  `executable('mesa_clc', ...)`):**

  ```
  src/compiler/clc/meson.build:129:18: ERROR: Tried to mix a host machine
  library ("libmesaclc") with a build machine target "mesa_clc" This is
  not possible in a cross build.
  ```

  Error de **configure** de Meson (`meson setup` nunca llega a `ninja`),
  no de build -- confirmado con el log completo del usuario: `llvm-native`
  terminó perfecto (3605/3605 targets, `libLLVM.so.23.1`/
  `libclang-cpp.so.23.1` NATIVAS presentes), el `sed` del Décimo noveno
  prendió bien (`[fase6-2] mesa_clc forzado a native:true en
  .../src/compiler/clc/meson.build`), pero el `meson setup` que sigue
  rompió antes de terminar de configurar.

  **Causa raíz real (confirmada leyendo el archivo completo real,
  `mirror/mesa`, rama `main`, `src/compiler/clc/meson.build`):**
  ```meson
  _libmesaclc = static_library(
    'libmesaclc',
    files_libmesaclc,
    ...
    dependencies: [idep_nir, dep_clang, dep_llvm, dep_llvmspirvlib,
                   idep_mesautil, dep_spirv_tools, idep_vtn, dep_version]
  )
  idep_mesaclc = declare_dependency(link_with : _libmesaclc, ...)

  if get_option('mesa-clc') != 'system' and (with_driver_using_cl or ...)
    prog_mesa_clc = executable(
      'mesa_clc', ['mesa_clc.c'], ...,
      dependencies : [idep_mesaclc, dep_llvm, dep_spirv_tools, idep_getopt],
      native : not meson.can_run_host_binaries(),  # <- el sed de acá
      install : get_option('install-mesa-clc'),
    )
  endif
  ```
  El `sed` del Décimo noveno sólo tocaba el `native:` del `executable()`
  de `mesa_clc`. Pero `_libmesaclc` (la librería estática de la que
  depende vía `idep_mesaclc`) se declara **sin** `native:` -- Meson la deja
  en contexto host/cruzado por default. Con `mesa_clc` ya `native:true`
  (contexto "build machine") pero `idep_mesaclc` seguía en contexto host
  ("host machine"), Meson rechaza el link: exactamente el error de arriba.
  Parchear TAMBIÉN `_libmesaclc` a `native:true` no hubiera alcanzado
  tampoco -- esa librería a su vez depende de `dep_llvm`/`dep_clang`/
  `dep_spirv_tools`/`dep_llvmspirvlib`, que en el `meson.build` RAÍZ real de
  Mesa (confirmado leyéndolo completo) **también** se declaran sin
  `native:` -- forzar sólo `_libmesaclc` hubiera reproducido el mismo
  choque un nivel más abajo, contra `dep_llvm`. La única forma de arreglar
  esto de raíz parcheando meson.build a mano sería declarar una segunda
  copia NATIVE completa de LLVM/Clang/SPIRV-Tools/LLVMSPIRVLib adentro del
  propio árbol de Mesa -- inviable.

  **La receta real de Mesa para este problema exacto** (confirmada en
  `meson.options`: opción `mesa-clc` con choices `['enabled', 'system',
  'auto']`, descripción de `install-mesa-clc`: *"Install the mesa-clc
  compiler (if needed for cross builds)"*; y en `docs.mesa3d.org/
  android.html`, sección "cross-compiling the nvk driver", que documenta
  exactamente este flujo de dos pasadas) es no tocar el `meson.build` de
  Mesa para nada. En cambio:
  1. Se compila un `mesa_clc` + `vtn_bindgen2` **100% NATIVOS** en un build
     de Mesa completamente aparte (nueva `step_mesa_clc_native()` en
     `build-mesa.sh`, nuevo target `mesa-clc-native`), sin `--cross-file`,
     con `-Dplatforms= -Dgallium-drivers= -Dvulkan-drivers=` (nada de
     drivers, no hace falta ninguno para esto) y
     `-Dmesa-clc=enabled -Dinstall-mesa-clc=true` (fuerza `with_clc=true`
     y la instalación de ambos binarios sin importar drivers). Esto
     necesitó DOS dependencias nativas nuevas que no existían todavía:
     **SPIRV-Tools NATIVO** (`step_spirv_tools_native()`, nuevo target
     `spirv-tools-native`) y **SPIRV-LLVM-Translator NATIVO**
     (`step_spirv_llvm_translator_native()`, nuevo target
     `spirv-llvm-translator-native`) -- ambos mismos flags de CMake que sus
     contrapartes cruzadas, sin `--cross-file`, instalados en prefijos
     nativos aparte bajo `${LFS_BUILD}` (nunca en el sysroot). El
     `LLVM_DIR` de SPIRV-LLVM-Translator-native apunta directo a
     `${LLVM_NATIVE_BUILD}/lib/cmake/llvm` -- LLVM genera su
     `LLVMConfig.cmake` de "build tree" en tiempo de `cmake configure`, sin
     hacer falta instalar nada (mecanismo estándar de LLVM/CMake).
  2. `mesa_clc` NATIVO se patchelfea con
     `--set-rpath ${LLVM_NATIVE_BUILD}/lib` (mismo motivo que la red de
     seguridad del Décimo noveno: linkea contra `libLLVM.so`/
     `libclang-cpp.so` NATIVAS en un directorio no estándar) y se verifica
     con `ldd | grep 'not found'` antes de dar el paso por bueno --
     `vtn_bindgen2` no lo necesita (sus dependencias son todas internas de
     Mesa, sin LLVM, confirmado leyendo su `executable()` real en
     `src/compiler/spirv/meson.build`).
  3. En `step_mesa()` (el build CRUZADO real): se revierte el `sed` del
     Décimo noveno parte 2 (ya no se toca
     `src/compiler/clc/meson.build`), se agrega `-Dmesa-clc=system` al
     `meson setup`, y se pisan `mesa_clc`/`vtn_bindgen2` en el
     `--native-file` apuntando a los binarios NATIVOS del paso 1
     (`find_program(..., native : true)` los busca ahí, no en el PATH del
     contenedor). Con `-Dmesa-clc=system` y sin rusticl, `with_clc` queda
     en `false` para este build cruzado -- Mesa ni siquiera procesa
     `src/compiler/clc/meson.build` acá, así que la mezcla de contextos ya
     no puede pasar. Se retira también el bloque de la "red de seguridad"
     (detectar ejecutables `*_clc` en el grafo de ninja y patchelearlos)
     porque ya no existe ningún target así en este build.
  4. Confirmado que ningún otro lugar del árbol real de Mesa necesita un
     ajuste más: `idep_mesaclc` sólo lo consume `mesa_clc` (único
     `executable()`/`declare_dependency()` en todo
     `src/compiler/clc/meson.build`), y `prog_mesa_clc`/
     `prog_vtn_bindgen2` (los binarios ya compilados) sólo se invocan como
     comando de un `custom_target()` en `src/intel/blorp/meson.build`
     (`blorp_shaders_spv`, compila `blorp_shaders.cl` a SPIR-V) -- no se
     linkean contra nada, así que basta con que el binario NATIVO exista y
     corra.

  Cambios en `build-mesa.sh`: 3 steps nuevos (`step_spirv_tools_native()`,
  `step_spirv_llvm_translator_native()`, `step_mesa_clc_native()`, targets
  `spirv-tools-native`/`spirv-llvm-translator-native`/`mesa-clc-native`),
  `step_mesa()` con el `sed` revertido + `-Dmesa-clc=system` +
  `--native-file` extendido + red de seguridad retirada, secuencia `all)`
  actualizada. Validado con `bash -n` y `shellcheck -S warning -e SC1091`
  (limpio, sin findings).

  **Lección:** un `native:true` a mano en UN SOLO target de un
  `meson.build` de terceros no alcanza si ese target depende de otros
  targets/dependencias del MISMO archivo (o de archivos relacionados) que
  también necesitan ser consistentes en contexto host-vs-build -- Meson lo
  chequea estrictamente y no mezcla. Antes de parchear un `native:` puntual
  a mano, vale la pena buscar primero si el proyecto YA tiene un mecanismo
  oficial para este problema exacto (acá: la opción `mesa-clc=system` +
  `install-mesa-clc`, pensada literalmente para "necesito esta herramienta
  de build-time nativa en un cross build") -- earlier hubiera evitado dos
  vueltas completas de debug (Décimo noveno parte 2 + este Vigésimo). La
  búsqueda que lo destapó fue simple: la propia documentación oficial de
  Mesa para cross-compiling (`docs.mesa3d.org/android.html`) ya trae la
  receta completa, no hizo falta inventar nada.

- **Vigésimo primer error real (2026-09-04), corregido -- primer error real
  de COMPILACIÓN (no de configure) del build `mesa-clc-native` nuevo del
  Vigésimo error real, llegó hasta 375/390 targets antes de romper:**

  ```
  ../mesa-mesa-26.2.1/src/compiler/clc/clc_helpers.cpp:45:10: fatal error:
  clang/Config/config.h: No such file or directory
     45 | #include <clang/Config/config.h>
  ```

  **Causa raíz** (confirmada leyendo la línea de compilación completa real
  del log): Mesa resuelve `dep_clang` con
  `cpp.find_library('clang-cpp', dirs: llvm_libdir, required: false)` --un
  `find_library()` puro, que sólo aporta el flag de LINKEO contra
  `libclang-cpp.so`, nunca include dirs (a diferencia de `dep_llvm`, que sí
  es un `dependency('llvm', method: 'config-tool', ...)` completo y por eso
  sí aporta sus propios `-isystem`: la línea de compilación real tenía
  `-isystem .../llvm-project-23.1.0.src/llvm/include -isystem .../llvm-
  native-build/include` -- dos rutas, las dos de LLVM, CERO de Clang). En
  el build CRUZADO esto no se nota porque LLVM+Clang quedan instalados
  COMPLETOS en `${LFS_SYSROOT}/usr` (Fase 6 normal) -- los headers de
  Clang caen en una ruta de include estándar del sysroot, sin hacer falta
  ningún `-I` explícito. En el build `mesa-clc-native` nuevo, en cambio,
  LLVM+Clang nativos nunca se instalan (se usan directo desde su árbol de
  build, `step_llvm_native()` nunca corre `ninja install`) -- sus headers
  no están en ningún include path por default, y como `dep_clang` no
  aporta ninguno, el compilador no tiene forma de encontrarlos.

  **Fix** (`step_mesa_clc_native()`): agregar a mano, vía `CFLAGS`/
  `CXXFLAGS` en el propio `meson setup` (mismo mecanismo que ya usa
  `step_elfutils()`, Meson lo graba como flags base del proyecto en tiempo
  de configure), las mismas dos rutas que Meson ya arma solo para LLVM,
  pero del lado de Clang: `<llvm-project fuente>/clang/include` (headers
  públicos normales) y `${LLVM_NATIVE_BUILD}/tools/clang/include`
  (headers generados por CMake en tiempo de configure -- éste
  `clang/Config/config.h` entre ellos -- bajo el layout estándar del
  monorepo LLVM, donde cada "tool" agregado vía `LLVM_ENABLE_PROJECTS`
  arma su propio árbol de build reflejando su árbol de fuente; mismo
  patrón que `${LLVM_NATIVE_BUILD}/include` para los generados de LLVM
  mismo). Dos verificaciones nuevas antes de tocar Meson: que el
  directorio fuente exista, y que `clang/Config/config.h` realmente esté
  generado en el árbol de build nativo (evita repetir el error de forma
  más críptica si la estructura de LLVM cambia de versión).

  Validado con `bash -n` y `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** no todas las `dependency()`/`find_library()` de un
  `meson.build` de terceros aportan lo mismo -- un `find_library()` sólo
  linkea, nunca agrega include dirs, a diferencia de una `dependency()`
  completa (pkg-config o config-tool). Cuando un build cruzado "esconde"
  este tipo de gaps porque todo termina instalado en una ruta de include
  estándar del sysroot, un build NATIVO aparte (como el `mesa-clc-native`
  de este proyecto, que a propósito usa binarios sin instalar desde su
  árbol de build) los destapa -- no alcanza con mirar qué dependencias
  declara el `meson.build`, hay que fijarse CÓMO las resuelve cada una.

- **Vigésimo segundo error real (2026-09-04), corregido -- primera vez que
  mesa_clc NATIVO corre DE VERDAD, invocado por el build cruzado real de
  Mesa (1366/2872 targets, confirma que todo el fix del Vigésimo error real
  funciona en la práctica, no sólo en teoría):**

  ```
  /lfs/build/mesa-clc-native-install/bin/mesa_clc -o
  src/intel/blorp/blorp_shaders.spv ... ../src/intel/blorp/blorp_shaders.cl
  -- ... -cl-std=cl2.0 ...
  <built-in>:439:10: fatal error: 'opencl-c-base.h' file not found
  ```

  **Causa raíz** (confirmada releyendo `src/compiler/clc/meson.build` real
  completo, ya citado en el Vigésimo error real más arriba): Mesa tiene DOS
  estrategias para que `mesa_clc` encuentre sus headers de OpenCL-C
  (`opencl-c-base.h`/`opencl-c.h`, que Clang necesita para compilar código
  `-cl-std=cl2.0`):
  1. **"Bundled"**: los empaqueta ADENTRO del binario en tiempo de
     compilación (vía `xxd`, con `-DUSE_STATIC_OPENCL_C_H=1`) -- se activa
     solo si `not _shared_llvm`, o a mano con
     `-Dmesa-clc-bundle-headers=enabled` (confirmado en `meson.options`:
     *"Bundle the OpenCL headers into the mesa-clc binary (default to
     bundle if static LLVM is used)"*).
  2. **"Runtime"** (lo que nos tocó, LLVM nativo es compartida): los busca
     en disco en `<LLVM_LIB_DIR>/clang/<version>/include/`, ruta armada en
     base al `llvm_libdir` que reporta `llvm-config` en tiempo de
     compilación de `mesa_clc`. Ese directorio
     (`${LLVM_NATIVE_BUILD}/lib/clang/23/include/`) nunca se generó --
     `step_llvm_native()` sólo pide targets puntuales de CMake
     (`llvm-tblgen llvm-config clang-tblgen LLVM clang-cpp`), ninguno de
     los cuales copia/genera el "resource directory" de headers builtin de
     Clang.

  **Fix** (`step_mesa_clc_native()`): en vez de perseguir qué target de
  CMake genera ese directorio (frágil, ligado a la estructura interna de
  Clang, mismo tipo de fragilidad que ya costó dos rondas con LLVM en el
  Décimo quinto error real), se fuerza la estrategia 1 con
  `-Dmesa-clc-bundle-headers=enabled` -- cero dependencia de rutas en disco
  en tiempo de ejecución, apropiado para un binario NATIVO pre-compilado
  que se usa desde OTRO build (el cruzado) donde ni siquiera existe
  `${LLVM_NATIVE_BUILD}` en el mismo contexto de resolución de rutas.

  Validado con `bash -n` y `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** cuando una herramienta de build-time se va a usar
  desacoplada de su propio entorno de compilación (acá: `mesa_clc`
  compilado en un build nativo aparte, después invocado desde un build
  cruzado distinto), conviene preferir la opción que empaqueta sus recursos
  ADENTRO del binario en vez de la que los busca por ruta relativa en
  tiempo de ejecución -- la segunda asume que el binario sigue viviendo
  "cerca" de donde se compiló, una asunción que ya rompió dos veces en este
  mismo tramo del proyecto (RPATH de LLVM, ahora esto).

- **Vigésimo tercer error real (2026-09-04), corregido -- consecuencia
  directa del fix del Vigésimo segundo (forzar
  `-Dmesa-clc-bundle-headers=enabled`), esta vez a tiempo de CONFIGURE de
  Meson, no de ejecución:**

  ```
  src/compiler/clc/meson.build:25:20: ERROR: File
  /lfs/build/llvm-native-build/lib/clang/23/include/opencl-c-base.h does
  not exist.
  ```

  **Causa raíz**: el gap real no era "runtime vs. bundled" (esa parte del
  Vigésimo segundo fix era correcta) -- era que
  `${LLVM_NATIVE_BUILD}/lib/clang/23/include/` **nunca se generó**, ni con
  la estrategia runtime (ahí el error salía recién al ejecutar `mesa_clc`,
  más tarde y más críptico) ni con la bundled (acá, Meson necesita LEER el
  archivo en el propio `meson setup` para empaquetarlo, así que el mismo
  gap aparece antes, en el configure). `step_llvm_native()` sólo pedía 5
  targets puntuales de CMake (`llvm-tblgen llvm-config clang-tblgen LLVM
  clang-cpp`) -- ninguno genera ese directorio como efecto secundario.
  Confirmado contra `clang/lib/Headers/CMakeLists.txt` real
  (`llvm-project`, rama `main`): el target real se llama
  **`clang-resource-headers`** (`add_library(clang-resource-headers
  INTERFACE ${out_files})`), con `opencl-c.h`/`opencl-c-base.h` entre los
  headers que copia a `lib/clang/<version>/include/` (vía
  `get_clang_resource_dir()`) -- exactamente la ruta que pedía Meson.

  **Fix**: agregar `clang-resource-headers` a la lista de targets de
  `ninja` en `step_llvm_native()`, más una verificación nueva
  (`find ... opencl-c-base.h`) antes de dar el paso por bueno. Con esto ya
  no hace falta re-pensar la estrategia bundled-vs-runtime del Vigésimo
  segundo -- sigue siendo la correcta, sólo le faltaba el directorio de
  origen.

  Validado con `bash -n` y `shellcheck -S warning -e SC1091` (limpio).

  **Lección:** un build de CMake con targets puntuales (en vez de "ninja"
  a secas) no arma automáticamente TODO lo que un consumidor final va a
  necesitar -- cada target nuevo que se agrega río abajo (acá:
  `-Dmesa-clc-bundle-headers=enabled`) puede destapar que faltaba un target
  más arriba que nadie pidió todavía. No es un fix mal hecho ni señal de
  que el enfoque esté mal -- es el costo normal de pedir sólo lo que hace
  falta en vez de compilar LLVM+Clang completos (que sí tardan horas): cada
  gap se cierra en segundos (agregar un target a una lista existente), no
  en horas (no hace falta recompilar nada de lo ya hecho, sólo lo nuevo).

- **Vigésimo cuarto "error real" (2026-09-04) — no fue un fallo de build de
  Mesa, fue un falso negativo del propio `step_verify_mesa()`.** Con el
  Vigésimo tercero ya corregido, la corrida real (`llvm-native` →
  `mesa-clc-native` → `mesa` → `verify-mesa`) completó `ninja`/`ninja install`
  de Mesa dos veces seguidas sin un solo error (`logs/20260904-060402_build-
  mesa_mesa.log`: primero 2872/2872 targets, después 76/76 más por el
  `git_sha1.h` siempre-stale de Meson arrastrando un puñado de recompilaciones
  en cascada al correr `ninja install` — ninguna de las dos corridas tiene un
  solo `FAILED`/`ERROR`) — pero `verify-mesa` igual reportó
  `[FALTA] iris_dri.so / radeonsi_dri.so / nouveau_dri.so / swrast_dri.so`.

  **Causa raíz confirmada** (leyendo el `meson.build` real de Mesa, mirror de
  GitHub `mirror/mesa`, rama `main` — mismo mecanismo que 26.2.1 en este
  tramo del árbol):
  - `src/gallium/targets/dri/meson.build` compila UN solo `shared_library()`
    con los 4 drivers Gallium (`iris`, `radeonsi`, `nouveau`, `llvmpipe`)
    linkeados adentro (`dependencies: [... driver_iris, driver_radeonsi,
    driver_nouveau, ...]`), lo instala directo en `${libdir}` (sin `/dri`)
    con el nombre `libgallium-<versión>.so` (`libname_suffix` +
    `meson.project_version()`) — confirmado en el log real:
    `Installing src/gallium/targets/dri/libgallium-26.2.1.so to /lfs/usr/lib`.
  - El ÚNICO `meson.add_install_script(install_megadrivers, ...)` de ese
    archivo (el que arma los símlinks `<driver>_dri.so` → el .so combinado)
    está condicionado por `with_gallium_va` — y este proyecto compila con
    `-Dgallium-va=disabled` a propósito (VA-API fuera de scope, ver Fase 6
    Parte 2 más arriba). Para el gallium DRI "clásico" (OpenGL/EGL, no VA) el
    archivo simplemente NO arma ningún símlink `iris_dri.so`/etc. en ninguna
    parte — nunca existió esa instalación para esta selección de opciones.
  - Ese esquema de símlinks-por-vendor es lo que consume
    `loader_open_driver_lib()` (`src/loader/loader.c` real: arma
    `"<path>/<driver_name><suffix>.so"` a mano y hace `dlopen()`) — pero eso
    es el loader del camino GLX/X11 clásico, y este proyecto compila con
    `-Dglx=disabled -Dplatforms=wayland` (glvnd también disabled) — ese
    loader ni se construye acá.
  - El camino que sí importa (Wayland vía EGL + GBM) NO usa `dlopen()` por
    nombre de vendor en absoluto: confirmado en `src/egl/meson.build` real
    (`if with_dri: link_for_egl += libgallium_dri` — libEGL.so linkea el
    megadriver COMPLETO en tiempo de build) y en
    `src/gbm/backends/dri/meson.build` real (`link_with : [libloader,
    libgallium_dri]` en el `shared_library('dri_gbm', ...)`, confirmado
    instalado en el mismo log: `Linking target
    src/gbm/backends/dri/dri_gbm.so` + `Installing ... dri_gbm.so to
    /lfs/usr/lib/gbm`). O sea: para esta combinación de opciones
    (Wayland-only, sin GLX), Mesa deliberadamente no genera los archivos que
    el verify estaba buscando — no es que falten, es que la arquitectura de
    esta build no los necesita ni los produce.

  **Fix:** `step_verify_mesa()` corregido para chequear el artefacto real
  (`${LFS_SYSROOT}/usr/lib/libgallium-${MESA_VERSION}.so`, con los 4 drivers
  Gallium adentro) y su consumidor real de Wayland
  (`${LFS_SYSROOT}/usr/lib/gbm/dri_gbm.so`), en vez de los 4 símlinks
  `*_dri.so` que esta configuración de Mesa nunca instala. Los chequeos de
  Vulkan (`libvulkan_radeon.so`/`libvulkan_intel.so`, ya `[OK]` antes — son
  ICDs separados, ANV/RADV, no pasan por este mecanismo) y de `libEGL.so`
  quedan intactos, no eran parte del problema. Sólo se corrigió `bash -n`
  contra este cambio (limpio) — `shellcheck` no está disponible en este
  entorno de trabajo puntual (ni en el host Windows ni en el `Dockerfile` del
  proyecto); pendiente correrlo cuando haya un entorno con la herramienta a
  mano, aclarado acá para no dar por hecho una validación que no se hizo.

  **Lección:** ya es la tercera vez en Fase 6 (ver "Lección general" de la
  Parte 1, sobre `.pc` en `share/` vs `lib/` y el symlink de xkeyboard-config)
  que un `verify` propio asume una convención de instalación "de manual" en
  vez de confirmar contra las líneas reales de `Installing .../` del log —
  acá el costo fue peor porque el build real había terminado perfecto
  (2872/2872, cero errores) y el mensaje "[FALTA]" sugería fuertemente lo
  contrario. Antes de tratar un `[FALTA]` de un verify propio como una señal
  de que el build falló, vale la pena confirmar primero si el build en sí
  tiró algún error real (`grep -iE "error|FAILED"` sobre el log de build) —
  si no tiró ninguno, el problema más probable es el verify, no el build.

## Infraestructura — incidente real de disco (2026-09-04, no es un bug de build)

Durante la primera corrida de `qttools` (build CRUZADO), el compilador tiró
errores reales pero ENGAÑOSOS: `internal compiler error: Bus error` +
`fatal error: error writing to /tmp/cc*.s: Input/output error`, repetido en
decenas de archivos distintos de `src/designer/`. **No era un bug de GCC ni
de Qt** — el disco C: de Windows llegó a **0 bytes libres** (893GB usados
de ~893GB) mientras la VM de Podman (WSL2, `ext4.vhdx` dinámico) intentaba
seguir creciendo para la compilación. Eso rompió escrituras a disco DENTRO
de la VM a mitad de compilación, y terminó corrompiendo el filesystem raíz
de la propia distro WSL (`podman-machine-default` quedó sin poder arrancar:
`getpwnam(root) failed`, ni `wsl --shutdown` alcanzaba para repararla).

**Diagnóstico, sin tomar ninguna acción destructiva:** confirmado con
PowerShell (`Get-PSDrive`) y con `df -h` desde Git Bash en paralelo — cero
bytes libres en C:, 232GB libres en D:. **Recuperación real:** se vació la
papelera de reciclaje de Windows (`Clear-RecycleBin`, seguro, ya eran
archivos que el usuario había marcado para borrar) — liberó 27.6GB, más de
lo esperado. Con eso, `wsl --shutdown` + `podman machine start` volvió a
funcionar sin problema, y se confirmó que **ningún dato se perdió** (los 4
volúmenes con nombre de Podman —`linsios-tools`/`linsios-build`/
`linsios-sysroot`/`linsios-boot`— y todo lo compilado hasta ahora,
incluidos `libQt6Core.so` y `libgallium-26.2.1.so`, sobrevivieron intactos
— la corrupción fue sólo del filesystem raíz de la distro en sí, no del
overlay/volúmenes de datos).

**Pendiente, decisión ya tomada (2026-09-04): NO mover la VM a D: todavía.**
Se evaluó mudar el `ext4.vhdx` de la máquina Podman de C: a D: (232GB
libres ahí) para eliminar el problema de raíz, pero esta versión de WSL
(2.5.10.0) no tiene un comando de "mover en el lugar" — sólo
`--export`/`--unregister`/`--import`, una secuencia de varios pasos sobre
una VM recién recuperada de una corrupción, con riesgo real de dejarla peor
si algo falla a mitad de camino. Se pospone a propósito para cuando haya
tiempo de hacerlo con cuidado, sin build corriendo en paralelo — 27.6GB
libres en C: alcanza para seguir compilando por ahora (el disco de la VM
tiene margen hasta 100GB nominales, usa 67GB reales en C: al momento de
este incidente). `powercfg /hibernate off` (libera otros ~20GB de
`hiberfil.sys`) quedó identificado pero sin correr — necesita una terminal
elevada (admin), esta sesión no tiene esos privilegios.

**Lección para el futuro:** si vuelve a aparecer un error de compilación
que mencione "Bus error", "Input/output error" al escribir en `/tmp`, o
cualquier falla rara que no tenga que ver con el código en sí y que golpee
archivos sin relación entre ellos, revisar espacio en disco del HOST
(`Get-PSDrive` en PowerShell) antes de asumir que es un bug real del
compilador o del proyecto que se esté compilando.

## Tier 2 (KDE Frameworks 6) — mapa de dependencias real (research 2026-09-04)

Con Tier 0 (ECM) y Tier 1 (Qt6) completos, arrancó el research de Tier 2
contra fuente real (`CMakeLists.txt` de cada framework, bajados de
`invent.kde.org/frameworks/<repo>`, rama `master` — la misma versión de
dependencias que la release 6.29.0 real, confirmado que el listado completo
de tarballs de esa release en `download.kde.org/stable/frameworks/6.29/`
incluye los ~70 paquetes del tren, más `attica`/`breeze-icons` en la misma
base). Todavía SIN escribir ningún script de Tier 2 -- esto es el mapa,
antes de tocar código.

**Tier 2a — sólo necesitan Qt6 (ya completo) + librerías de sistema ya
compiladas en este proyecto, ningún otro KF6:**
- `kcodecs`, `kitemviews`, `kitemmodels` — sólo Qt.
- `kcoreaddons` — Qt Core + `LibMount` REQUIRED (ya compilado, util-linux de
  Fase 2) + `Inotify` opcional (headers del kernel, ya disponibles).
- `kconfig` — Qt Xml/Gui/DBus (todos ya en el sysroot).
- `kwidgetsaddons` — Qt Widgets.
- `ki18n` — Qt Core + `LibIntl` (parte de glibc, ya disponible) +
  `IsoCodes` (paquete de datos XML/JSON, **nuevo, sin compilar todavía**).
- `kdbusaddons` — Qt DBus + Gui(private).
- `karchive` — Qt Core + ZLIB/BZip2/LibLZMA/OpenSSL, **los 4 ya
  compilados** en este proyecto (Fase 2/Fase 4).
- `kglobalaccel` — Qt DBus/Gui/Widgets, ningún KF6.
- `kguiaddons`, `kidletime`, `kwindowsystem` — Qt Gui/Wayland +
  **`PlasmaWaylandProtocols` (nuevo, ver más abajo)**, condicionado a un
  build option real por framework (`WITH_X11`/`WITH_WAYLAND` en
  kguiaddons, confirmado leyendo el `if()` real del CMakeLists — con la
  decisión ya tomada de Wayland puro, va `-DWITH_X11=OFF -DWITH_WAYLAND=ON`
  en los tres).

**Prerequisito nuevo encontrado: `PlasmaWaylandProtocols`.** No es parte
del tren de KDE Frameworks (se versiona aparte — kwin real pedía `1.21.0`,
no un número `6.x`) ni tiene tarball en `download.kde.org/stable/plasma/`
pese a aparecer listado ahí (probado, 404 real). Fuente real confirmada:
mirror de GitHub `KDE/plasma-wayland-protocols`, tag `v1.21.0` (coincide
exacto con lo que pide kwin) — mismo patrón `archive/refs/tags` que ya usa
este proyecto para otros paquetes sin tarball de "make dist". Es,
igual que `wayland-protocols` (Fase 6 Parte 1), sólo protocolos XML +
build con ECM/CMake — debería ser liviano.

**Tier 2b — dependen de frameworks de Tier 2a:**
- `kcolorscheme` — KF6Config, KF6GuiAddons, KF6I18n.
- `kauth` — KF6CoreAddons.
- `kcrash` — KF6CoreAddons.
- `kcompletion` — KF6Codecs, KF6Config, KF6WidgetsAddons.
- `kconfigwidgets` — KF6CoreAddons, KF6Codecs, KF6Config, KF6GuiAddons,
  KF6I18n, KF6WidgetsAddons, KF6ColorScheme.
- `kservice` — KF6Config, KF6CoreAddons, KF6I18n, (opcional KF6DocTools).
- `kpackage` — KF6Archive, KF6I18n, KF6CoreAddons, (opcional KF6DocTools).
- `knotifications` — KF6Config REQUIRED, opcional Canberra (ya compilado
  en Tier 4 de kwin... en realidad Canberra es Tier 4 de plasma-workspace,
  **todavía sin compilar** — ver mapa original al principio de este
  archivo).
- `kdoctools` — Qt Core + KF6Archive + KF6I18n (opcional) + `LibXslt`/
  `LibXml2` (libxml2 ya compilado, Fase 6 Parte 3 prerequisito) +
  `DocBookXML4`/`DocBookXSL` (**nuevos**, paquetes de datos XML, no
  librerías de código).

**Tier 2c — dependen de Tier 2b (más profundo):**
- `kiconthemes` — KF6Archive, KF6I18n, KF6WidgetsAddons, KF6ColorScheme,
  **KF6BreezeIcons** (nuevo — el tema de íconos Breeze en sí, versionado en
  el mismo tren 6.29.0, es un prerequisito real de código, no sólo un tema
  visual opcional).
- `kdeclarative` — KF6I18n, KF6Config, KF6GuiAddons, (opcional
  KF6GlobalAccel, KF6WidgetsAddons).
- `krunner` — KF6Config, KF6CoreAddons, KF6I18n, (opcional
  KF6ItemModels), KF6WindowSystem.
- `kxmlgui` — KF6CoreAddons, KF6ItemViews, KF6Config, KF6ConfigWidgets,
  KF6GuiAddons, KF6I18n, KF6IconThemes, KF6WidgetsAddons, (opcional
  KF6GlobalAccel).
- `ksvg` (el componente "Svg" que pide kwin, distinto de `Qt6::Svg`) —
  Qt Quick/Gui/Qml/Svg/QuickControls2 + KF6 (lista cortada en el grep, hay
  que revisar completa cuando se llegue a este paso).

**Tier 2d — las piezas pesadas, todavía no mapeadas en profundidad:**
- `kcmutils` — depende de **KF6KIO** (el framework más grande de todos,
  todavía sin research propio) + KF6ItemViews, KF6ConfigWidgets,
  KF6CoreAddons, KF6GuiAddons, KF6I18n, KF6XmlGui, KF6WidgetsAddons.
- `knewstuff` — KF6Archive, KF6Config, KF6CoreAddons, KF6I18n, KF6Package,
  KF6WidgetsAddons, **KF6Attica REQUIRED** (nuevo, cliente de servicios web
  de KDE Store — paquete separado, mismo tren 6.29.0), opcional
  KF6Kirigami/KF6Syndication.

**Sin empezar research todavía:** KF6KIO en profundidad (bloquea
`kcmutils`, que kwin pide `REQUIRED`), Kirigami/KirigamiAddons (Tier 3 del
mapa original), y todo lo del "tren de Plasma"/Tier 4 del mapa original
(QCoro6, ICU, libcanberra, libei, lcms2, hwdata, etc.).

**Tier 2a — ✅ COMPLETO y verificado (2026-09-04).** Los 13 módulos
(`isocodes`, `plasma-wayland-protocols`, `kcodecs`, `kitemviews`,
`kitemmodels`, `kcoreaddons`, `kconfig`, `kwidgetsaddons`, `ki18n`,
`kdbusaddons`, `karchive`, `kglobalaccel`, `kguiaddons`, `kidletime`,
`kwindowsystem`) más dos prerequisitos nuevos descubiertos en la corrida
real (`zstd`, `liblzma`) — todos compilados, instalados y verificados en
el sysroot. Errores reales encontrados y corregidos, todos documentados en
el código con su causa raíz:

1. **`BUILD_PYTHON_BINDINGS`** (Shiboken6/PySide6) prendido por defecto en
   varios frameworks, pide `Python3 Development` que el Dockerfile no
   tiene instalado (`python3-dev`). Apagado en el helper compartido
   `_kf6_cmake_build()` para los 13 módulos de una vez.
2. **`WITH_X11`** (ON por defecto en Linux) rompía `kdbusaddons`
   compilando `kdbusservice.cpp` (`private/qtx11extras_p.h` no existe
   porque Qt6 se compiló sin X11 a propósito). Resultó ser una opción
   general de KF6, no sólo de los 3 frameworks con soporte Wayland
   explícito — apagada también en el helper compartido.
3. **`libzstd` y `liblzma`**, dos prerequisitos reales de `karchive` que el
   research original no había detectado (usan `pkg_check_modules()` y
   `find_package()` sin `REQUIRED` respectivamente, pero ambos se vuelven
   obligatorios de verdad vía `option(WITH_LIBZSTD/WITH_LIBLZMA ... ON)` +
   `ecm_feature_summary()` al final). Se agregaron `step_zstd()`
   (facebook/zstd v1.5.7) y `step_liblzma()` (tukaani-project/xz v5.8.3)
   nuevos — corrigiendo además un comentario anterior de este archivo que
   decía (mal) que los 4 ya estaban compilados.
4. **`kwindowsystem` usa `KWINDOWSYSTEM_X11`/`KWINDOWSYSTEM_WAYLAND`, no
   `WITH_X11`/`WITH_WAYLAND`** como kguiaddons/kidletime — exactamente el
   riesgo que ya se había anotado por adelantado en el comentario del
   código antes de correrlo. Corregido con el nombre real de opción de
   ese framework en particular.
5. Dos falsos negativos de verify (mismo patrón .pc en `share/pkgconfig`
   vs `lib/pkgconfig` ya visto varias veces en este proyecto): `iso-codes`
   y su propio guard `require_isocodes()`.

**Tier 2b — ✅ COMPLETO y verificado (2026-09-04)**, excepto `kdoctools`
(diferido a propósito, ver más abajo). Los 9 módulos (`kcolorscheme`,
`kauth`, `kcrash`, `kcompletion`, `kconfigwidgets`, `kservice`, `kpackage`,
`libcanberra` + prerequisitos, `knotifications`) compilados, instalados y
verificados. Cadena de prerequisitos reales encontrados en la corrida,
ninguno estaba en el mapa original:

- **`Canberra` resultó REQUIRED de verdad** en Linux normal (el mapa
  original lo había anotado como opcional, cierto sólo para
  plasma-workspace) — confirmado leyendo el `if()` real de
  `knotifications`. Cadena completa de prerequisitos nuevos, cada uno
  encontrado en la corrida real del anterior, ninguno anticipable sin
  correr:
  1. **`libltdl`** (de GNU libtool) — libcanberra carga sus backends de
     audio como módulos dinámicos. Truco real: sólo hace falta compilar el
     subdirectorio `libltdl/` del tarball de libtool (tiene su propio
     `configure` standalone), no libtool completo — y ese subdirectorio
     necesita el flag `--enable-ltdl-install` (OFF por default) para que
     `make install` instale algo — sin el flag, compila una "convenience
     library" interna (`libltdlc.la`) y no instala nada, sin ningún error
     visible (primer intento real: `make install` corrió limpio pero no
     dejó ni `libltdl.so` ni `ltdl.h` en el sysroot).
  2. **`libogg` + `libvorbis`** — "### Vorbis (mandatory) ###" en el
     `configure.ac` real de libcanberra (reproduce sonidos de tema
     codificados en Ogg Vorbis). Xiph.Org los publica separados,
     libvorbis depende de libogg.
  - `libcanberra` en sí: `--enable-alsa` (ya compilado), sin pulse/
    gstreamer/gtk. Primer script Autotools de este archivo (Tier 0-2 fue
    CMake/Meson puro hasta acá) — se agregó `build_triplet()` (ya existía)
    y el patrón `--host/--build` sin `CC=` explícito, igual que el resto
    del proyecto.
  - **Nota menor, no bloqueante:** el install de libcanberra dejó los
    `.service` de systemd en `/lfs/lfs/usr/lib/systemd/system` (`/lfs`
    duplicado) — mismo bug de fondo ya documentado para wireplumber en
    Fase 6 Parte 1 (`systemduserunitdir` de systemd.pc con `/lfs` de más,
    sumado a `DESTDIR=/lfs`). No rompe nada ahora (sysroot monolítico, sin
    booteo real todavía); revisar junto con el de wireplumber cuando se
    llegue a empaquetar de verdad.
- Otro falso negativo de verify corregido antes de correr (no hizo falta
  un segundo intento): `require_isocodes()` tenía la misma ruta mal que ya
  se había corregido en `step_verify_isocodes()`.

**`kdoctools` diferido a propósito** (no bloquea nada de lo que sigue —
`kservice`/`kpackage` ya confirmaron que `KF6DocTools` es opcional en
ambos): necesita `LibXslt`, `DocBookXML4` y `DocBookXSL`, tres
dependencias nuevas sin investigar todavía. Se retoma si algo del árbol
más adelante lo pide de verdad como `REQUIRED`.

**Tier 2c — ✅ COMPLETO y verificado (2026-09-04).** Los 6 módulos
(`kiconthemes`, `kdeclarative`, `krunner`, `kxmlgui`, `kirigami`, `ksvg`) +
`breezeicons` (nativo y cruzado) — todos compilados, instalados y
verificados. Hallazgo más importante de este tramo:

- **`BreezeIcons` destapó un mecanismo de KF6 equivalente al `QT_HOST_PATH`
  de Qt6, pero propio de KDE Frameworks: `KF6_HOST_TOOLING`.** El build
  CRUZADO rompió invocando su propio `generate-symbolic-dark`
  ("error while loading shared libraries: libQt6Core.so.6") -- mismo
  problema de fondo de siempre (binario cruzado invocado en tiempo de
  build), pero confirmado leyendo `tools/CMakeLists.txt` real que KF6 ya
  tiene su convención propia para esto: `if (CMAKE_CROSSCOMPILING AND
  KF6_HOST_TOOLING): find_program(... PATHS ${KF6_HOST_TOOLING} ...)`.
  Se agregó `step_breezeicons_native()` (con `-DINSTALL_HOST_TOOLS=ON`,
  la variable real que gatea el install de esas dos herramientas) +
  `KF6_NATIVE_BUILD`/`KF6_NATIVE_INSTALL` (mismo patrón que
  `QT6_NATIVE_*`) — el build cruzado apunta ahí con
  `-DKF6_HOST_TOOLING="${KF6_NATIVE_INSTALL}/bin"`. A diferencia de Qt6,
  el build nativo de BreezeIcons NO necesita nada especial (ni toolchain
  file ni acotar targets a mano): como es 100% nativo de punta a punta, el
  propio `generate-symbolic-dark` corre bien solo durante su propio build,
  sin el problema de glibc cruzada. **Vale la pena tener este mecanismo
  presente para el resto de Tier 2d/3** (Kirigami/KirigamiAddons, KIO,
  etc. — cualquiera podría tener el mismo patrón).
- **`ksvg` necesitaba `KF6KirigamiPlatform`**, no anticipado en el mapa
  original. Se agregó `step_kirigami()` — Kirigami en sí resultó
  sorprendentemente liviano de dependencias: CERO frameworks KF6, sólo Qt6
  (ya completo), confirmado leyendo su `CMakeLists.txt` real. Compiló
  limpio al primer intento.
- Dos falsos negativos de verify corregidos (nombres de paquete/librería
  reales distintos de lo asumido, sin volver a correr el build): BreezeIcons
  (`KF6BreezeIcons`, no `BreezeIcons` a secas) y KDeclarative (no produce
  ninguna librería principal propia — sólo plugins QML +
  `libKF6CalendarEvents.so`, se verifica el paquete cmake en vez de una lib
  inexistente).

**Tier 2d (parte 1: desbloqueadores de KF6KIO) — ✅ COMPLETO y verificado
(2026-09-04).** `KF6KIO` (el framework más grande de todo KF6) resultó
necesitar 3 frameworks nuevos que no estaban en el mapa original de este
documento — descubierto leyendo su `CMakeLists.txt` real en
`invent.kde.org/frameworks/kio`:

- **`KF6Solid`** (para `kio_trash`), **`KF6Bookmarks`** y
  **`KF6JobWidgets`**. Los tres módulos compilaron **limpio al primer
  intento**, sin ningún error real — primera vez en todo Fase 6 Parte 3
  que un tramo entero no encuentra nada que arreglar.
- Nombres de repo/tarball reales confirmados antes de escribir código
  (evitando adivinar, después de que un primer intento con
  `frameworks/bookmarks` y `frameworks/jobwidgets` diera 404 en
  invent.kde.org): son **`kbookmarks`** y **`kjobwidgets`** (con el
  prefijo "k", a diferencia de `solid`, que NO lo lleva).
- `kbookmarks` y `kjobwidgets` sólo dependen de frameworks ya compilados
  (`KF6Config`, `KF6CoreAddons`, `KF6WidgetsAddons`, `KF6Notifications`) —
  nada nuevo.
- `solid` necesitaba `FLEX`/`BISON` (ya en el Dockerfile desde Fase 0,
  herramientas de host puras para generar el parser de `Predicate`, sin
  el problema de binario-cruzado-en-build-time) y, en el bloque
  `CMAKE_SYSTEM_NAME MATCHES Linux` de su `CMakeLists.txt`, `LibMount` y
  `UDev` como `REQUIRED`. Se confirmó por adelantado (antes de correr el
  build) que ambas ya existen en el sysroot — `libmount.so`+headers de
  Fase 2/util-linux, `libudev.so`+headers de Fase 2/systemd — con un
  `find` real dentro del contenedor, así que no hizo falta agregar ningún
  paso nuevo de librería del sistema.
- Se agregaron `step_kbookmarks()`/`step_kjobwidgets()`/`step_solid()` (y
  sus `verify-*`) usando el helper compartido `_kf6_cmake_build()`, sin
  flags extra — los tres siguen el patrón estándar del resto de Tier 2.

**Tier 2d (parte 2: `KF6KIO`) — ✅ COMPLETO y verificado (2026-09-04).**
El framework más grande de todo KF6 compiló **limpio al primer intento**,
sin ningún error real — igual que sus 3 desbloqueadores. Confirma que el
mapa de dependencias armado con research previo (contra el
`CMakeLists.txt` real, sección "Tier 2 — mapa de dependencias real" más
arriba) estaba completo: `KF6Config`, `KF6CoreAddons`, `KF6I18n`,
`KF6Service`, `KF6Crash`, `KF6Solid`, `KF6WindowSystem`, `KF6Bookmarks`,
`KF6ColorScheme`, `KF6Completion`, `KF6GuiAddons`, `KF6IconThemes`,
`KF6ItemViews`, `KF6JobWidgets`, `KF6WidgetsAddons`, `KF6DBusAddons` — las
16 dependencias KF6 ya estaban en el sysroot antes de empezar. `ACL`
(sólo `RECOMMENDED`, no `REQUIRED`) se omitió sin agregar la librería, sin
bloquear el build. `WITH_X11=OFF` y `LibMount` (ya presente desde Fase
2/util-linux) tampoco dieron problema.

**Tier 2d (parte 3: `KF6Attica` + `knewstuff`) — ✅ COMPLETO y verificado
(2026-09-04).** Cierra Tier 2d y con él **todo KF6 (Tier 2 completo)**.

- **`Attica`** resultó ser el framework más liviano de todo el proyecto:
  sólo `ECM` + `Qt6 Core/Network`, cero dependencias KF6 propias
  (confirmado contra su `CMakeLists.txt` real en
  `invent.kde.org/frameworks/attica`). Compiló limpio al primer intento.
  Librería real: `libKF6Attica.so`.
- **`knewstuff`** necesita `KF6Archive`, `KF6Config`, `KF6CoreAddons`,
  `KF6I18n`, `KF6Package`, `KF6WidgetsAddons`, `KF6Attica` (los 7
  `REQUIRED`, todos ya en el sysroot) + `Qt6 Gui/Widgets/Xml/Qml/Quick/
  QuickWidgets`. `KF6Kirigami` (`OPTIONAL`, para los componentes QML) se
  detectó solo porque ya está compilado; `KF6Syndication` (`OPTIONAL`,
  sólo para soporte OPDS) se omitió a propósito — no está en el mapa de
  este proyecto y nada lo pide como `REQUIRED`. Compiló limpio al primer
  intento. Librería principal real: `libKF6NewStuffCore.so` (confirmado
  contra `src/core/CMakeLists.txt` real — el target se llama
  `KF6NewStuffCore`, no `KF6KNewStuff` ni `KF6NewStuff` a secas; también
  produce `libKF6NewStuffWidgets.so` y plugins QML).

**Balance de todo Tier 2d:** los 6 módulos (`kbookmarks`, `kjobwidgets`,
`solid`, `KIO`, `attica`, `knewstuff`) compilaron **limpio al primer
intento, sin un solo error real** — el tramo más largo de Fase 6 Parte 3
sin ningún hallazgo que documentar más allá de investigación de mapeo de
dependencias. Confirma que el research previo (leer el `CMakeLists.txt`
real de cada paquete ANTES de escribir código) sigue siendo la práctica
correcta: cuando el mapa de dependencias está bien armado de antemano, el
build cruzado no tiene sorpresas.

**Tier 2 (KDE Frameworks 6) — ✅ COMPLETO en su totalidad (2026-09-04).**
Los 4 tramos (2a/2b/2c/2d) + Tier 0 (ECM) + Tier 1 (Qt6) cubren todo lo
necesario para Tier 3.

## Tier 3 (tren de Plasma) — arranque real (2026-09-04)

### Retrofit real sobre Tier 1 (Qt6) -- descubierto recién acá, ya "✅ COMPLETO"

Al intentar `libplasma` por primera vez, `ecm_find_qmlmodule(Qt5Compat.GraphicalEffects REQUIRED)`
falló con un warning real: `qmldir not found in /usr/lib/qml/... or
/lfs/build/qt6-native-install/qml/.../qmldir`. Root cause confirmado
leyendo `${LFS_SYSROOT}/usr/lib/cmake/Qt6/QtInstallPaths.cmake` real:
**Qt6 (sin flags extra) instala sus propios módulos QML en `/usr/qml`**,
mientras que **KDE/ECM los busca en `/usr/lib/qml`** (confirmado contra
`KDEInstallDirs6.cmake` real: intenta preguntarle a Qt vía
`ecm_query_qt(... QT_INSTALL_QML)`, que en un build CRUZADO termina
consultando el `qtpaths` NATIVO por error de fondo, y cae al fallback
real `LIBDIR/qml`). Mismo criterio que usan distros reales
(Fedora/Arch fijan `INSTALL_QMLDIR` para que coincida con el de KDE) —
se alineó Qt a la convención de KDE, no al revés:

- Se agregó `-DINSTALL_QMLDIR=lib/qml` a `step_qtbase()` (cruzado) y se
  **recompiló qtbase** (reescribe `QtInstallPaths.cmake` para todo el
  árbol de Qt).
- Se **recompilaron** `qtdeclarative`, `qtsvg`, `qt5compat` y `qtwayland`
  (cruzados) para que su contenido QML se reinstale en la ruta corregida
  -- confirmado con un find real: `Qt5Compat.GraphicalEffects` ahora
  aparece en `/usr/lib/qml/Qt5Compat/GraphicalEffects/qmldir`.
- Segundo bug real encontrado en la MISMA vuelta: el tool nuevo de Qt
  6.11 `svgtoqml` (paquete `Qt6QuickTools`, necesario para que
  `qtdeclarative` CRUZADO encuentre su host tool) sólo se agrega al build
  si `TARGET Qt::Quick AND QT_FEATURE_quick_vectorimage` -- y esa feature
  depende de `Qt::SvgPrivate` (confirmado contra los `CMakeLists.txt`
  reales de `qtdeclarative`), pero **nunca existió un `qtsvg-native`** en
  este proyecto (sólo el cruzado). Se agregó `step_qtsvg_native()` +
  `step_verify_qtsvg_native()` + `require_qtsvg_native()` (Tier 1,
  mismo patrón `QT6_NATIVE_INSTALL` de siempre) y se recompiló
  `qtdeclarative-native` -- confirmado: `Qt6QuickTools` aparece recién
  después. Se limpiaron los ~24MB huérfanos de `/usr/qml` tras el
  retrofit (nada los busca ahí después del fix).
- **Incidente de infraestructura aparte, resuelto en el medio:** el DNS
  interno de la red de Podman se colgó a mitad de sesión (el contenedor
  no resolvía ningún host, aunque la VM WSL2 por fuera sí) -- mismo tipo
  de degradación que la crisis de disco anterior. Se resolvió con
  `podman machine stop` + `podman machine start` (no toca los volúmenes
  con nombre, sin pérdida de datos), confirmado con un DNS real desde
  adentro del contenedor antes de seguir.

### libxcb y su cadena — nuevo, agregado sólo para un bug real de libplasma

`libplasma` v6.7.4 tiene `src/plasma/private/blureffectwatcher_p.h` con
`#include <xcb/xcb.h>` **sin ningún guard de preprocesador**, pese a que
el uso real del símbolo sí está guardeado (`#if HAVE_X11`, indefinido en
este proyecto). Decisión tomada junto con el usuario: compilar un libxcb
real y mínimo (nunca se linkea de verdad en runtime) en vez de parchear
este include puntual -- ver más abajo por qué el patch SÍ terminó siendo
necesario para el resto de casos similares. Cadena real de dependencias
(xorg.freedesktop.org, accesible en vivo a diferencia de
gitlab.freedesktop.org): `xorgproto` (headers puros, últimas versión
2025.1) → `libXau` 1.0.12 + `libXdmcp` 1.1.5 (autenticación X, cada uno
independiente) → `xcb-proto` 1.17.0 (specs XML + módulo python
"xcbgen") → `libxcb` 1.17.0. Los 5 compilaron limpio, sólo 2 falsos
negativos de verify corregidos (`xorgproto.pc`/`xcb-proto.pc` no
existen como tales -- xorgproto no genera un .pc combinado, cada
sub-protocolo mantiene el suyo; verify corregido a `xproto.pc`/
`xcb-proto.pc` reales, en `/usr/share/pkgconfig`, no `/usr/lib/pkgconfig`).

### libplasma — ✅ COMPLETO (2026-09-04), primer parche real de todo el proyecto

Con libxcb resuelto, apareció un SEGUNDO bug del mismo patrón pero mucho
más grande: `theme_p.cpp` incluye `<KX11Extras>` sin guard. A diferencia
de xcb.h, la solución "agregar la librería real" acá era desproporcionada
-- `KX11Extras` sólo existe si `KWindowSystem` se compila con
`KWINDOWSYSTEM_X11=ON`, que exige Xlib real (`find_package(X11
REQUIRED)`) + `xcb-util` + `xcb-util-keysyms` + `icccm` (confirmado
contra el `CMakeLists.txt` real de kwindowsystem) -- meter Xlib de
verdad en el sysroot choca de frente con el Pilar 5 ("Wayland puro").
Decidido junto con el usuario: **parchear la fuente** en vez de eso.

Investigando más, resultó ser un bug **sistemático** de esta tag exacta,
no un caso aislado -- confirmado contra el código real, apareció en
**5 archivos** con **13 usos** de `KX11Extras`/`KWindowInfo`, casi todos
detrás de un chequeo de runtime (`KWindowSystem::isPlatformX11()`, que en
Wayland puro siempre da falso) que no alcanza para que compile sin la
librería real:

- `src/plasma/private/theme_p.cpp` (4 reemplazos: el include + 3 usos,
  incluido un CUARTO bug relacionado descubierto recién en el segundo
  intento real: `BlurEffectWatcher` sólo implementa su método virtual
  puro heredado -- `QAbstractNativeEventFilter::nativeEventFilter` --
  adentro de un `#if HAVE_X11` en su propio header, dejándola abstracta
  con `HAVE_X11=0`; `new BlurEffectWatcher()` en este archivo no estaba
  guardeado -- "invalid new-expression of abstract class type" real).
- `src/plasmaquick/plasmawindow.cpp` (3 reemplazos) y
  `src/plasmaquick/appletpopup.cpp` (2 reemplazos) -- ninguno de los dos
  incluía `config-plasma.h` todavía, hubo que agregarlo (mismo que ya usa
  `dialog.cpp`, mismo target `PlasmaQuick`) para que `HAVE_X11` exista de
  verdad -- si no, `-Werror=undef` (real, en los flags de compilación)
  rompe el build igual.
- `src/plasmaquick/dialog.cpp` (7 reemplazos -- el más grande, ya tenía
  un `#if HAVE_X11` real en otra parte del mismo archivo para un caso
  distinto, confirmando que es el mismo criterio que usa upstream).
- `src/declarativeimports/core/windowthumbnail.cpp` (3 reemplazos --
  necesitó `config-x11.h`, no `config-plasma.h`, el que CMake genera
  realmente en ese mismo directorio).

Cada reemplazo preserva el comportamiento de runtime REAL para
`HAVE_X11=0` (confirmado leyendo cada call site antes de tocarlo -- varios
`if (!isPlatformX11() || ...)` ya evaluaban siempre verdadero en Wayland
por el propio short-circuit, y varios `else` ya eran el camino Wayland
real vía `PlasmaShellWaylandIntegration`/ícono de fallback). Implementado
como `_patch_libplasma()` en `scripts/build-kde.sh`: reemplazos de texto
exacto vía Python (no un `.patch` con números de línea, para no depender
de que el offset coincida byte a byte con la tag real) -- falla fuerte y
explícito si algún ancla no aparece o no es única. Se agregó un hook
genérico a `_plasma_cmake_build()` (busca una función `_patch_<tarname>`
y la corre una sola vez, marcador `.patched-<tarname>`) para que futuros
parches de Tier 3 (kwin/plasma-workspace son candidatos reales al mismo
patrón) no necesiten duplicar la lógica.

Confirmado con un build real limpio (sin errores) tras las 4 rondas de
parche + rebuild, y `verify-libplasma` real: `libPlasma.so`. De paso,
`PlasmaQuick` **NO es un paquete Tier 3 aparte** como decía el mapa
original -- vive en el mismo tarball/CMake project que libplasma
(`src/plasmaquick/`), se compiló y se instaló junto (`libPlasmaQuick.so`
confirmado en el mismo log de install) -- corrección al mapa de
dependencias.

### KWayland, layer-shell-qt, KirigamiAddons -- ✅ COMPLETOS (2026-09-16), sin errores reales

Los tres compilaron limpio al primer intento tras el research previo.

- **KWayland** (la de Plasma, namespace `Plasma::`, distinta de
  `Qt6WaylandClient` de Tier 1 y de `KF6WindowSystem`): destapó un mismatch
  real de versión -- pide `PlasmaWaylandProtocols >= 1.22.0`, y este
  proyecto tenía pinneado 1.21.0 (el mínimo que necesitaba kwin en el
  research original). Se subió el pin del proyecto entero a **1.22.0**
  (confirmado tag real `v1.22.0`, 10-sep-2026, en
  `github.com/KDE/plasma-wayland-protocols/tags` -- sigue satisfaciendo a
  kwin, que sólo pide `>= 1.21.0`).
  - **Bug real de infraestructura encontrado en el mismo paso:** al subir
    la versión, `step_plasma_wayland_protocols()` tiró
    `CMake Error: The source directory ".../plasma-wayland-protocols-1.22.0"
    does not exist` pese a que el log decía "ya extraído". Causa raíz: el
    marcador de `extract_once()` para ese paso (y para los helpers
    compartidos `_kf6_cmake_build()`/`_plasma_cmake_build()`) usaba
    `.extracted-<tarname>` **sin la versión** -- al haber extraído
    1.21.0 antes, ese marcador ya existía, y `extract_once()` daba por
    hecho que 1.22.0 también estaba extraído sin haberlo estado nunca.
    **Fix aplicado en los 3 lugares** (el paso puntual + los 2 helpers
    compartidos): el marcador ahora incluye la versión
    (`.extracted-<tarname>-<versión>`), previniendo el mismo bug para
    cualquier futuro bump de versión de cualquier paquete ya compilado.
  - Target real: `KWaylandClient` (namespace `Plasma::`), NO "KWayland" a
    secas -- confirmado contra `src/client/CMakeLists.txt` real.
- **layer-shell-qt**: integra el protocolo `wlr-layer-shell` con Qt6.
  Sin sorpresas -- todas las dependencias (Wayland Client+Server >= 1.3,
  WaylandProtocols, xkbcommon) ya estaban. Target real:
  `LayerShellQtInterface` (no "layer-shell", que es sólo el plugin QPA
  interno).
- **KirigamiAddons**: versionado en un tercer ciclo de release, separado
  tanto de KDE Frameworks como del tren de Plasma (confirmado listando
  `download.kde.org/stable/kirigami-addons/`, última real 1.13.1,
  2026-07-20; repo real bajo `invent.kde.org/libraries/kirigami-addons`,
  NO `frameworks/`, donde 404 primero). Se agregó `step_kirigami_addons()`
  como función propia (no encaja en `_kf6_cmake_build()` ni
  `_plasma_cmake_build()`, cada uno atado a su propia variable de
  versión). Es mayormente QML puro (formcard, delegates, statefulapp),
  sin una única lib monolítica -- se verifica contra
  `KF6KirigamiAddonsConfig.cmake`.

### libkscreen (KF6Screen) -- ✅ COMPLETO (2026-09-16), tercer y cuarto+quinto hallazgo real del mismo bug de X11

Sin opciones de X11/XRandR declaradas en su `CMakeLists.txt` (confirmado
-- ni siquiera existe un `WITH_X11` ahí), pero apareció el mismo patrón de
bug sistemático de esta release de KDE **tres veces más**, en formas cada
vez más distintas -- confirma que vale la pena tener el patrón siempre
presente de acá en adelante:

1. **`src/libdpms/dpms.cpp`**: `#include <QtGui/private/qtx11extras_p.h>`
   sin guard (header PRIVADO de Qt6Gui, sólo existe con
   `-DFEATURE_xcb=ON` -- este proyecto compiló Qt con `OFF` a propósito).
   El uso real (`QX11Info::isPlatformX11()`) sí estaba detrás de un
   runtime-check real, con un `else if` de Wayland al lado. Se sacó el
   include + el branch X11 completo, dejando sólo el camino Wayland real
   (mismo criterio que ya se usó en libplasma: preservar el
   comportamiento real, no inventar uno nuevo).
2. **`src/libdpms/xcbdpmshelper.cpp`**: a diferencia del anterior, este
   archivo es **100% implementación X11/XCB**, sin nada portable adentro
   -- no tiene sentido guardearlo línea por línea. Se sacó directo del
   `target_sources()` de `src/libdpms/CMakeLists.txt` (junto con
   `XCB::XCB XCB::DPMS XCB::RANDR` de su `target_link_libraries()`, que
   ya no hacían falta). Importante: **no hizo falta agregar ninguna
   librería nueva** -- `libxcb-dpms`/`libxcb-randr` ya estaban compilados
   desde el libxcb mínimo agregado para libplasma; el problema era
   puramente el header privado de Qt, no una librería faltante.
3. **`src/backendmanager.cpp`**: mismo patrón que el punto 1 (include sin
   guard + runtime-check real con rama Wayland al lado) pero en el
   selector de qué backend de verdad usar (XRandR vs KWayland). Mismo
   fix: sacar el include + la rama X11 completa.
4. **`backends/xrandr/` (target `KSC_XRandR`)**: el hallazgo más
   interesante de los cuatro -- este backend SÍ está bien gateado por
   upstream (`if(${XCB_RANDR_FOUND})`, real, en `backends/CMakeLists.txt`)
   pero el gate se disparó igual **porque este proyecto SÍ tiene
   libxcb-randr compilado** (efecto colateral real del libxcb mínimo
   agregado para libplasma: habilita sin querer código KDE que asume que
   "tener libxcb-randr" implica "tener el resto de la integración X11 de
   Qt", cosa que acá nunca es cierta). Como el backend XRandR nunca se
   iba a poder seleccionar en runtime de todos modos (ya se sacó del
   punto 3), se sacó el `add_subdirectory(xrandr)` entero del build, sin
   importar `XCB_RANDR_FOUND`.

Los 4 parches quedan en `_patch_libkscreen()` (mismo mecanismo genérico de
`_plasma_cmake_build()` que ya se usó para libplasma). Compiló limpio
después. Target real: `KF6Screen` (namespace `Plasma::Screen`, tarball
`libkscreen`).

**Lección reforzada:** el libxcb mínimo agregado para satisfacer un solo
`#include <xcb/xcb.h>` en libplasma tiene un efecto colateral real en
cualquier paquete downstream que haga su propio `find_package(XCB
COMPONENTS ...)` -- activa código X11 opcional que de otra forma hubiera
quedado apagado solo. Vale la pena revisar esto de entrada en kwin (que
sí tiene muchísimas más rutas X11 condicionales) en vez de descubrirlo
recién al compilar.

### KDecoration3, KCMUtils, Aurorae -- ✅ COMPLETOS (2026-09-16)

- **KDecoration3** (`kdecoration`, tarball sin el "3"): REQUIRED real por
  kwin (`find_package(KDecoration3 ... REQUIRED)`, confirmado). Muy
  liviano -- sólo ECM + Qt6 Core/Gui/Test + KF6I18n, todo ya en el
  sysroot. Compiló limpio al primer intento. Target real: `kdecorations3`
  (namespace `KDecoration3::`, `EXPORT_NAME KDecoration`).
- **KCMUtils**: dependencia nueva descubierta recién al investigar Aurorae
  -- NO estaba en el mapa original de Tier 2 (KDE Frameworks). Es del
  tren de KDE Frameworks (KDE_VERSION 6.29.0), no de Plasma, así que usa
  `_kf6_cmake_build()` como el resto de Tier 2, aunque se agregó bien
  entrado Tier 3. Compiló limpio, produce `KF6KCMUtilsCore`,
  `KF6KCMUtils` y `KF6KCMUtilsQuick`.
- **Aurorae**: motor de temas de decoración de ventanas "descargables de
  internet" para kwin (RUNTIME opcional, no REQUIRED, pero entra por
  "todo desde el principio"). Compiló limpio -- todas sus dependencias
  (KDecoration3, KCMUtils, KF6 ColorScheme/Config/CoreAddons/I18n/
  NewStuff/Package/Svg) ya estaban en el sysroot para cuando le tocó el
  turno. Produce PLUGINS de KDecoration3, no una librería con nombre
  estable -- verify corregido para chequear la ruta real confirmada tras
  el install (`/usr/lib/plugins/org.kde.kdecoration3/org.kde.kwin.aurorae.so`),
  no una búsqueda genérica.

### Breeze -- ✅ COMPLETO (2026-09-16), destapó DOS herramientas cruzadas rotas que nunca se habían invocado antes

Breeze (`breeze`, el tema de decoración/estilo/cursor **por defecto** de
kwin -- DISTINTO de `breeze-icons`, ya compilado en Tier 2c) resultó ser
el primer paquete de todo el proyecto en ejercitar dos herramientas de
KF6 que hasta ahora nunca se habían invocado de verdad en ningún build
anterior, pese a llevar semanas compiladas:

- **Bloqueante encontrado ANTES de correr el build** (no en una vuelta
  fallida): este proyecto compila Qt5 Y Qt6 por default
  (`BUILD_QT5=ON`), y este proyecto no tiene Qt5 en absoluto. Se agregó
  `-DBUILD_QT5=OFF` explícito a `step_breeze()`.
- **`kcmdesktopfilegenerator` (de KCMUtils) roto en el contenedor** --
  primer uso real de esta herramienta desde que se compiló KCMUtils hace
  unas horas (Aurorae no llegó a necesitarla). Mismo problema de fondo de
  siempre: el binario CRUZADO no corre en el contenedor
  (`libQt6Core.so.6: cannot open shared object file`). A diferencia de
  BreezeIcons, KCMUtils no tiene ningún mecanismo `KF6_HOST_TOOLING`
  propio (confirmado contra su `CMakeLists.txt` real) -- pero SÍ tiene
  una opción real `TOOLS_ONLY` (`if (TOOLS_ONLY): find_package(Qt6
  REQUIRED Core); add_subdirectory(tools); return()`), perfecta para un
  build nativo mínimo. Se agregó `step_kcmutils_native()`
  (`-DTOOLS_ONLY=ON`, sólo pide Qt6::Core) y se modificó `step_kcmutils()`
  para pisar el binario roto del sysroot con el nativo vía `cp -f`
  (mismo patrón que `llvm-config`/`patchelf` en Fase 6 Parte 2, sólo que
  acá alcanza con copiar, sin tocar RPATH). **Sorpresa real de ruta**:
  GNUInstallDirs detecta multiarch en el build NATIVO (contenedor Debian)
  e inserta `x86_64-linux-gnu` en el libdir
  (`.../lib/x86_64-linux-gnu/libexec/kf6/...`) -- la ruta CRUZADA no lo
  hace (`.../lib/libexec/kf6/...`, sin el segmento de triplete). Las dos
  rutas quedaron documentadas explícitas en el script, no asumidas.
- **`kconfig_compiler_kf6` (de KConfig, Tier 2a, compilado hace semanas)
  también roto en el contenedor** -- Breeze es el PRIMER paquete de todo
  el proyecto que realmente invoca `kconfig_add_kcfg_files()` (compila
  `.kcfg` a C++) en su build; ningún consumidor de KF6 anterior había
  ejercitado esto de verdad, así que el bug quedó latente sin
  manifestarse durante semanas. Confirmado con `ldd` real: ni
  `libQt6Xml.so.6` ni `libQt6Core.so.6` resolvían, más un choque de
  versión de `GLIBCXX` contra el `libstdc++` del contenedor. KConfig
  tampoco tiene `TOOLS_ONLY` ni `KF6_HOST_TOOLING` propio -- se agregó
  `step_kconfig_native()` con un build mínimo real
  (`-DKCONFIG_USE_GUI=OFF -DKCONFIG_USE_QML=OFF -DUSE_DBUS=OFF`, sólo
  pide Qt6 Core+Xml, ambos ya nativos) y el mismo `cp -f` en
  `step_kconfig()`. Confirmado con `ldd` real después del fix: ahora sí
  resuelve contra las libs nativas.

Tras los dos fixes, Breeze compiló limpio. Verify corregido contra la
ruta real del plugin (`org.kde.breeze.so`, no "breezedecoration.so" como
se había asumido -- mismo esquema de nombres que `org.kde.kwin.aurorae.so`
de Aurorae).

**Lección para lo que falta (kwin, plasma-workspace):** cualquier
framework de KF6 que genere una herramienta de build propia (buscar
`add_executable()` bajo un directorio `tools/`) es sospechoso de tener
este mismo problema latente, **incluso si el framework en sí ya está
compilado y verificado hace tiempo** -- el bug sólo se manifiesta la
PRIMERA VEZ que algún consumiente real invoca esa herramienta específica
en su propio build, no al compilar el framework que la provee. No alcanza
con que `verify-<framework>` haya dado OK.

### KSysGuard (`libksysguard`) -- ✅ COMPLETO (2026-09-16), cierra Tier 3

Dependencias reales confirmadas contra su `CMakeLists.txt`
(invent.kde.org/plasma/libksysguard): ECM; Qt6 DBus/Network/Widgets/Qml/
Quick; KF6 CoreAddons/Config/I18n/Auth/Service/Package/NewStuff/Solid;
ZLIB/Libdrm/UDev/Libcap (ya en el sysroot); **dos prerequisitos nuevos
REQUIRED, ninguno en el mapa original**:

- **libnl** (netlink, "para leer sockets vía sock_diag") -- Autotools
  estándar, sin sorpresas, versión real 3.12.0
  (github.com/thom311/libnl/releases, tag `libnl3_12_0`).
- **lm-sensors / libsensors** ("para sensores de hardware") -- el primer
  paquete de todo el proyecto con un **Makefile plano propio** (ni
  autotools ni CMake ni Meson) -- se cross-compila pisando `CC=`/`AR=`
  por línea de comandos en vez de `--host=`. Versión real 3.6.2 (última
  tag real, github.com/lm-sensors/lm-sensors/tags, "V3-6-2",
  13-ene-2024 -- el proyecto no tuvo release nueva desde entonces, no es
  un pin viejo a propósito). **Bug real encontrado:** el archive de
  GitHub para el tag "V3-6-2" extrae a `lm-sensors-3-6-2/`, NO
  `lm-sensors-V3-6-2/` como se asumió al principio -- **GitHub SÍ pisa
  la "V" mayúscula del tag**, no sólo la "v" minúscula (el patrón
  documentado hasta ahora en este proyecto, ej. `plasma-wayland-protocols`,
  sólo había confirmado el caso minúscula). Vale la pena tener esto
  presente para cualquier futuro paquete con tag en mayúscula.

`libpcap` (RECOMMENDED, no REQUIRED, sólo para medir uso de red por
aplicación) se dejó afuera a propósito -- mismo criterio que VA-API/NVK/
glvnd en Mesa (Fase 6 Parte 2): no se agrega scope opcional sin que algo
lo pida como REQUIRED.

Compiló limpio al primer intento (con libnl/lm-sensors ya resueltos). No
produce una única `libKSysGuard.so` (el mapa original asumía mal) sino
varias librerías separadas -- `libKSysGuardFormatter.so`,
`libprocesscore.so`, `libKSysGuardSensors.so`, `libKSysGuardSensorFaces.so`,
`libKSysGuardSystemStats.so` -- verify corregido para chequear las 3 más
centrales contra el install real.

## Tier 3 (tren de Plasma) -- ✅ COMPLETO en su totalidad (2026-09-16)

Cierra Tier 3 completo: `PlasmaActivities`/`PlasmaActivitiesStats`,
`libplasma` (con `PlasmaQuick` incluido), `KWayland`, `layer-shell-qt`,
`KirigamiAddons`, `libkscreen`, `KDecoration3`, `KCMUtils`, `Aurorae`,
`Breeze`, `KSysGuard` -- todos compilados y verificados. `Union` queda
deliberadamente pospuesto: ningún consumidor real (ni kwin, ni ningún
paquete de Tier 3) lo pide como `REQUIRED` -- no se agrega
especulativamente, se retoma si algo lo exige de verdad más adelante.

**Próximo paso real, ya investigado contra el `CMakeLists.txt` real de
kwin** (`invent.kde.org/plasma/kwin`, confirmado en vivo, incluye la
lista completa de `find_package()` con REQUIRED/opcional marcado): con
`KWIN_BUILD_X11=OFF` (decisión ya tomada, saca de la ecuación XCB/X11
real completos), los prerequisitos REQUIRED nuevos que faltan son:

- **lcms2** (Little CMS 2, gestión de color) -- confirmado que NO está en
  el sysroot todavía.
- **libdisplay-info** (`>= 0.2.0`, parseo de EDID de monitores) --
  tampoco está.
- **KScreenLocker** -- REQUIRED si `KWIN_BUILD_SCREENLOCKER=ON` (default
  ON) -- paquete completo de Plasma, sin investigar todavía.
- **KGlobalAccelD** -- REQUIRED si `KWIN_BUILD_GLOBALSHORTCUTS=ON`
  (default ON) -- sin confirmar todavía si es parte de `kglobalaccel`
  (ya compilado) o un paquete/daemon aparte.
- **epoxy** (`libepoxy`, dispatch de funciones GL) -- confirmado que NO
  está en el sysroot (Mesa no lo provee, es un proyecto separado de
  Tomas Frydrych/Adam Jackson).

Todo lo demás que pide kwin (Qt6, KF6 Auth/ColorScheme/Config/
CoreAddons/Crash/DBusAddons/GlobalAccel/GuiAddons/I18n/IdleTime/Package/
Service/Svg/WidgetsAddons/WindowSystem + Declarative/KCMUtils/NewStuff/
XmlGui/Runner/Notifications, KWayland, KDecoration3, KNightTime¹,
Wayland/WaylandProtocols/PlasmaWaylandProtocols -- con versiones mínimas
que EXACTAMENTE coinciden con lo que ya tenemos instalado (1.26.0/1.49/
1.22.0, confirmado línea por línea), Canberra, Libinput, UDev, Libdrm,
gbm, EGL, Vulkan, PipeWire, libevdev) ya está compilado desde fases
anteriores. Breeze/Aurorae/PlasmaActivities/Kirigami/libplasma son
RUNTIME opcionales, ya cubiertos también.

¹ `KNightTime` (día/noche automático) todavía no está investigado ni
compilado -- queda para cuando se llegue a esa parte de la lista.

## Prerequisitos de kwin (Tier 4) -- avance real (2026-09-16)

De los 5 prerequisitos REQUIRED identificados arriba, se resolvieron
`lcms2`, `libdisplay-info` (vía `hwdata`), `libepoxy` y `KGlobalAccelD`;
`KScreenLocker` quedó como el último, en compilación al momento de
escribir esto.

### libepoxy -- ✅ COMPLETO, dos bugs reales de fetch/opciones Meson

**Bug 1 -- URL de descarga inexistente.** Se asumió el patrón habitual
de release assets de GitHub
(`.../releases/download/1.5.10/libepoxy-1.5.10.tar.gz`) pero ese asset
NO existe -- libepoxy no publica tarballs de release, sólo tags de git.
Confirmado con el Browser tool (WebFetch no puede renderizar el listado
de assets de GitHub, que es JS). Fix: usar el archive automático de
GitHub para el tag (`archive/refs/tags/1.5.10.tar.gz`, que sí existe
siempre para cualquier tag).

**Bug 2 -- tipos de opción Meson mezclados dentro del mismo proyecto.**
Primer intento: `-Dx11=false -Dglx=false` → error de Meson: `"glx"` es
`type: 'combo'` con choices `auto`/`yes`/`no`, no boolean. Segundo
intento (corrigiendo por analogía): `-Dx11=no -Dglx=no` → error inverso:
`"x11"` SÍ es `type: 'boolean'`. Causa raíz confirmada leyendo el
`meson_options.txt` real del tarball extraído: `x11` es `boolean`
mientras que `glx`/`egl` son `combo` -- no hay un patrón uniforme, hay
que mirar cada opción. Flags finales que compilaron limpio:
`-Dx11=false -Dglx=no -Degl=yes`.

**Lección:** nunca asumir el tipo de una opción Meson por su nombre o
por analogía con una opción vecina del mismo proyecto -- confirmar
`meson_options.txt` real antes de pasar flags.

### lcms2 -- ✅ COMPLETO, sin sorpresas

Autotools estándar (`./configure --host=${LFS_TGT} --prefix=/usr` +
`make DESTDIR="${LFS_SYSROOT}" install`). Tag real de release:
`lcms2.19.1` (sin guión antes de la versión, confirmado contra
`github.com/mm2/Little-CMS/releases`). Verifica `liblcms2.so`.

### hwdata + libdisplay-info -- ✅ COMPLETO, primer bug real de
dependencias Meson `native: true` en un build cruzado

**Síntoma:** `libdisplay-info` fallaba con
`File /usr/share/hwdata/pnp.ids does not exist.` incluso después de
agregar `hwdata` al sysroot y confirmar que el archivo SÍ estaba en
`${LFS_SYSROOT}/usr/share/hwdata/pnp.ids`.

**Causa raíz** (confirmada leyendo el `meson.build` real de
libdisplay-info extraído dentro del contenedor -- `gitlab.freedesktop.org`
está bloqueado para WebFetch/Browser, pero el tarball ya descargado y
extraído sí es legible): la dependencia está declarada como
`dependency('hwdata', required: false, native: true)`. El flag
`native: true` le dice a Meson que resuelva esa dependencia contra la
máquina de BUILD (el contenedor), no contra el sysroot cruzado --
porque `pnp.ids` sólo se usa en tiempo de build, por un script Python
generador de código (`gen-search-table.py`) que arma una tabla C
embebida; nunca se linkea ni se usa en runtime. Por eso instalarlo en
el sysroot nunca alcanzaba.

**Intento de fix rechazado antes de implementar:** instalar hwdata
directo en `/usr/share/hwdata` del contenedor (sin `DESTDIR`). Se
descartó de inmediato porque los contenedores de
`podman-compose run --rm` son efímeros -- cualquier escritura al
filesystem propio del contenedor se pierde al salir, rompiendo la
reproducibilidad entre corridas separadas del script.

**Fix real aplicado:** `step_hwdata()` ahora hace DOS instalaciones:
la de siempre al sysroot (`DESTDIR="${LFS_SYSROOT}"`, para cualquier
consumidor runtime futuro) más una segunda pasada nativa
(`./configure --prefix="${HWDATA_NATIVE_INSTALL}"`, sin `DESTDIR`) que
instala en el volumen persistente `${LFS_BUILD}/hwdata-native-install`
-- mismo patrón que `QT6_NATIVE_INSTALL`/`KF6_NATIVE_INSTALL`, nunca en
el filesystem efímero del contenedor.

**Intento de fix #2, también fallido:** pasar
`PKG_CONFIG_PATH="${HWDATA_NATIVE_INSTALL}/share/pkgconfig"` como
prefijo de entorno inline en el propio comando `meson setup`. Volvió a
fallar con el mismo error exacto. Se confirmó vía el `meson-log.txt`
real que Meson invoca `pkg-config --modversion hwdata` SIN heredar ese
`PKG_CONFIG_PATH` para dependencias `native: true` en un build cruzado
-- aislado además con una invocación de `pkg-config` standalone
(fuera de Meson) que sí resolvía `hwdata.pc` correctamente con el mismo
env var, confirmando que el bug es específico de cómo Meson arma su
entorno para ese código de resolución de dependencias nativas.

**Fix correcto aplicado:** reemplazar el prefijo inline por un
`--native-file` real de Meson (análogo al `write_meson_crossfile()` ya
usado para el `--cross-file`, pero para el lado nativo), con contenido:

```ini
[built-in options]
pkg_config_path = ['${HWDATA_NATIVE_INSTALL}/share/pkgconfig']
```

pasado junto al `--cross-file` existente. Compiló limpio a la primera
con este cambio.

**Lección:** una dependencia Meson `native: true` en un build cruzado
NO hereda `PKG_CONFIG_PATH` del shell que invoca, aunque `pkg-config`
standalone con el mismo env var sí funcione. La única forma confiable
de inyectarle un pkgconfig path adicional es un `--native-file` con
`[built-in options] pkg_config_path = [...]`.

### KGlobalAccelD -- ✅ COMPLETO, último de los 5 prerequisitos originales

Compiló limpio con `_plasma_cmake_build KGlobalAccelD kglobalacceld`,
sin ningún bug real. Instala TANTO una librería
(`libKGlobalAccelD.so.0`, sin symlink `.so` sin versión -- confirmado,
no hace falta para lo que lo consume) COMO el daemon real
(`/usr/lib/libexec/kglobalacceld`, activado por systemd/dbus vía
`plasma-kglobalaccel.service`). El verify inicial (placeholder genérico
con `find -iname '*kglobalaccel*'`) se reemplazó por chequeos exactos
de ambos artefactos reales.

### KScreenLocker -- 🟡 en compilación, sexto hallazgo real del bug sistémico de X11 (el más grande hasta ahora)

**Trampa real:** el `CMakeLists.txt` de `invent.kde.org/plasma/kscreenlocker`
rama `master` (fetch inicial, vía WebFetch) YA no tiene ningún check de
X11 -- upstream lo sacó por completo en una versión posterior a la
6.7.4 que tenemos pineada. El research inicial contra `master` dio
"sin X11, sin sorpresas" y llevó a escribir `step_kscreenlocker()` sin
ningún patch. El build real contra el TARBALL 6.7.4 (no contra
`master`) falló de entrada:

```
-- Could NOT find X11 (missing: X11_X11_LIB)
-- Could NOT find XCB_KEYSYMS (missing: XCB_KEYSYMS_LIBRARY XCB_KEYSYMS_INCLUDE_DIR) (found version "")
-- Could NOT find XCB_UTIL (missing: XCB_UTIL_LIBRARY XCB_UTIL_INCLUDE_DIR) (found version "")
CMake Error ... Could NOT find XCB (missing: KEYSYMS UTIL) (found version "1.17.0")
```

**Lección (nueva, distinta a la de GitHub/tags):** para un paquete de
KDE que sigue el release train de Plasma, el `CMakeLists.txt` de la
rama `master` de `invent.kde.org` puede estar MUY adelantado respecto
al tag/tarball realmente pineado (acá, meses de diferencia de refactors
de X11) -- nunca alcanza con mirar `master`, hay que leer el
`CMakeLists.txt` DEL TARBALL YA EXTRAÍDO cuando algo no cierra con lo
que dice `master`.

**Causa raíz real** (leída directamente del `CMakeLists.txt` del
tarball 6.7.4 extraído dentro del contenedor): `find_package(XCB MODULE
REQUIRED COMPONENTS XCB KEYSYMS UTIL XTEST)` -- REQUIRED de verdad, sin
ningún guard -- más `X11::X11`/`XCB::UTIL` linkeados directo (sin guard)
en `greeter/CMakeLists.txt`. Investigando el USO real de X11 en el
código (no sólo el `find_package`), se confirmó el mismo patrón
sistémico ya documentado para `KX11Extras` y `libkscreen`, pero repartido
en **3 archivos** en vez de 1-2:

- **`ksldapp.cpp`**: `m_isX11 = X11Info::isPlatformX11()` gatea en
  runtime 6 bloques de código real (`initializeX11()` con
  `XGetScreenSaver`/`XSetScreenSaver`, `establishGrab()` con
  `XSync`/`XServerGrabber`/`grabKeyboard()`/`grabMouse()` -- Xlib real
  vía `XGrabKeyboard`/`XGrabPointer`/`XIGrabDevice` --, y
  `showLockWindow()` instanciando la clase `X11Locker`). Además,
  `cleanUp()` tenía una llamada a `XSetScreenSaver()` **sin ningún
  guard de `m_isX11`** -- bug real aparte, no sólo el patrón de
  siempre.
- **`globalaccel.cpp`**: `X11Info::isPlatformX11()` gatea
  `xcb_key_symbols_alloc()`/`xcb_key_symbols_free()` (de
  `xcb-util-keysyms`, un paquete aparte que no tenemos) y
  `checkKeyPress()` usa símbolos de `<X11/keysym.h>` (Xlib real) para
  interpretar keypads.
- **`greeter/greeterapp.cpp`**: `KWindowSystem::isPlatformX11()` gatea
  la clase `FocusOutEventFilter` (necesita `xcb_event.h` de
  `xcb-util`) y un bloque `XInternAtom`/`XChangeProperty` (Xlib real).

`doUnlock()` (en `ksldapp.cpp`) usa `xcb_ungrab_keyboard`/
`xcb_ungrab_pointer`/`xcb_flush` -- funciones del núcleo de `libxcb`
(NO de `xcb-util`) -- así que ese bloque compila fino con nuestro
libxcb mínimo y no hizo falta tocarlo. `Qt::X11BypassWindowManagerHint`
y `org_kde_ksld_x11window` (protocolo Wayland `ksld.xml`) tampoco son
símbolos de Xlib/xcb-util pese al nombre, no se tocaron.

**Decisión, confirmada con Juani antes de tocar el código** (por ser
justo el componente de bloqueo de pantalla -- área de seguridad -- y
ser bastante más grande que los parches anteriores): mismo criterio ya
aprobado para `KX11Extras`/`libkscreen` -- sacar el código X11 muerto
en vez de compilar Xlib/xcb-util real, ya que TODO uso real está detrás
de un runtime-check que siempre da `false` en un release Wayland puro
(`m_isX11`/`KWindowSystem::isPlatformX11()` nunca detectan una sesión
X11 si no hay ningún QPA `xcb` cargado). Aplicado vía
`_patch_kscreenlocker()` (mismo hook genérico `_patch_<tarname>` de
siempre): saca `find_package(X11)`/`find_package(XCB ...)` y
`x11locker.cpp/.h` de `CMakeLists.txt`; fuerza `m_isX11 = false` y
elimina `initializeX11()`, el grab real completo
(`establishGrab`/`grabKeyboard`/`grabMouse`/`XServerGrabber`) y el
`X11Locker`/`XSync` final de `showLockWindow()` en `ksldapp.cpp`; saca
la asignación/liberación de `m_keySymbols` y reduce `checkKeyPress()` a
`return false;` (su comportamiento real, dado que `m_keySymbols` nunca
se asignaba) en `globalaccel.cpp`; saca `X11::X11`/`XCB::UTIL` de
`greeter/CMakeLists.txt`; y saca `FocusOutEventFilter` + el bloque
`XInternAtom`/`XChangeProperty` de `greeter/greeterapp.cpp`.

Dependencias reales confirmadas SÍ correctas (todas ya en el sysroot,
ninguna dependencia nueva): ECM; Qt6 DBus/Widgets/Quick/Test; KF6
Crash/KCMUtils/KIO/GlobalAccel/I18n/IdleTime/Notifications/Solid/
WindowSystem/XmlGui/Svg; PlasmaQuick; LayerShellQt; KF6Screen; PAM.
Tarball real: `kscreenlocker-6.7.4.tar.xz` (confirmado en el listado de
`download.kde.org/stable/plasma/6.7.4/`).

**Tres rondas más de errores reales tras el primer intento del patch**
(cada una resuelta con el mismo criterio: leer el error real, confirmar
contra el source real, corregir):

1. `CMakeLists.txt:199 (target_link_libraries): Target "KScreenLocker"
   links to: X11::X11 ... but the target was not found` -- había un
   SEGUNDO lugar con `X11::X11`/`XCB::KEYSYMS` linkeados directo, en el
   target de la librería principal `KScreenLocker` (no sólo en
   `greeter/CMakeLists.txt`, que ya estaba parcheado). Agregado a la
   misma lista de reemplazos de `CMakeLists.txt`.
2. Mismo error, ahora con `XCB::XCB` -- al sacar el `find_package(XCB
   ...)` ENTERO (no sólo X11), también se perdió el target CMake
   `XCB::XCB` que sí usa de verdad `doUnlock()` (vía `xcb_ungrab_keyboard`/
   `xcb_ungrab_pointer`, del núcleo de libxcb, ya en el sysroot). Fix:
   en vez de sacar el `find_package(XCB ...)` del todo, se lo angosta a
   `find_package(XCB MODULE REQUIRED COMPONENTS XCB)` -- sólo el
   componente núcleo, sin KEYSYMS/UTIL/XTEST.
3. `ksldapp.cpp:459:31: error: 'X11Info' has not been declared` --
   `doUnlock()` usa `X11Info::connection()`, pero `X11Info` vive en
   `x11info.h`, que ya se había sacado del todo del archivo. Se creía
   que este bloque "compilaba fino" por usar sólo xcb núcleo -- cierto
   para las funciones xcb, pero no para el namespace `X11Info` en sí.
   Fix: sacar el bloque completo `if (m_isX11) { ... }` de `doUnlock()`
   (dead code, igual que los demás).
4. `globalaccel.cpp:8:10: fatal error: KKeyServer: No such file or
   directory` -- `KKeyServer` (utilidad de conversión de keysyms/
   modificadores) es parte de **KWindowSystem** (`src/kkeyserver.h`),
   ya compilado en Tier 2 hace semanas, pero su instalación está
   gateada a soporte X11 real (confirmado en su `CMakeLists.txt`: "we
   install kkeyserver_x11.h which needs the X11 headers available") --
   igual que build de KWindowSystem sin X11 (mismo criterio de
   siempre), el header nunca se instaló. De sus funciones, sólo
   `isShiftAsModifierAllowed()` seguía viva en runtime real (en
   `keyEvent()`, la ruta de shortcuts Wayland) tras sacar el código
   muerto de `checkKeyPress()` -- lógica pura de `Qt::Key`, sin nada de
   Xlib/xcb pese a vivir en un header gateado a X11. En vez de re-tocar
   KWindowSystem (Tier 2 ya cerrado), se copió esa función verbatim
   (confirmada línea por línea contra `kwindowsystem-6.29.0/src/
   kkeyserver.cpp`, líneas 106-297) como estática local de
   `globalaccel.cpp`. `calculateGrabMasks()` (única otra función que
   usaba `KKeyServer::`, ya muerta tras sacar su único caller) se sacó
   también -- de lo contrario fallaba igual por símbolos indefinidos
   aunque nunca se llamara.
5. `globalaccel.cpp:8:10: fatal error: netwm.h: No such file or
   directory` -- mismo patrón que KKeyServer (el `netwm.h` completo de
   KWindowSystem vive en `src/platforms/xcb/netwm.h`, sólo con X11
   real), pero acá NINGÚN símbolo `NET::`/`NETWinInfo` se usaba en todo
   el archivo -- era un include muerto, no una dependencia real. Se
   sacó directo.

**Resultado final: ✅ COMPLETO**, compiló y se instaló limpio. Artefactos
reales confirmados vía el log de instalación:
`/lfs/usr/lib/libKScreenLocker.so{,.6,.6.7.4}` (con symlink sin versión
esta vez, a diferencia de KGlobalAccelD), `/lfs/usr/lib/libexec/
kscreenlocker_greet` (el greeter), `/lfs/usr/lib/plugins/plasma/kcms/
systemsettings/kcm_screenlocker.so` (el KCM de configuración). Verify
actualizado con estos 3 paths exactos.

**Con esto se cierran los 5 prerequisitos de kwin** identificados
contra su `CMakeLists.txt` real: lcms2 ✅, libdisplay-info ✅,
KGlobalAccelD ✅, libepoxy ✅, KScreenLocker ✅. Próximo paso real:
investigar y escribir `step_kwin()` (Tier 5) con `KWIN_BUILD_X11=OFF`.

## Tier 5 (kwin) -- ✅ COMPLETO (2026-09-16), 13 intentos reales hasta compilar limpio

Investigado contra el `CMakeLists.txt` REAL del tarball
`kwin-6.7.4.tar.xz` extraído (no contra `invent.kde.org/plasma/kwin`
rama `master` -- lección aprendida recién con KScreenLocker: `master`
puede estar meses adelantado o atrasado respecto al tag pineado). Con
`KWIN_BUILD_X11=OFF`, kwin gatea TODO lo X11/XCB (15 componentes XCB +
X11_XCB + Xwayland + X11 real) dentro de un `if(KWIN_BUILD_X11)`
correcto -- a diferencia de KScreenLocker, upstream lo hizo bien acá,
sin necesitar ningún patch para ESE bloque.

### Tres prerequisitos nuevos, descubiertos recién al CORRER el build real

**1. Vulkan (Headers + Loader)** -- `find_package(Vulkan REQUIRED)`
fallaba con "Could NOT find Vulkan". Se creía cubierto por Mesa (Fase 6
Parte 2), pero Mesa sólo instala los DRIVERS ICD
(`libvulkan_radeon.so`/`libvulkan_intel.so` + manifests JSON en
`/usr/share/vulkan/icd.d/`) -- el LOADER real (`libvulkan.so`, lo que
las apps linkean, que hace `dlopen()` del ICD correcto en runtime) y
los headers (`vulkan/vulkan.h`) son DOS proyectos aparte de
KhronosGroup, nunca compilados. Se agregaron `Vulkan-Headers` (header-
only, sin dependencias) y `Vulkan-Loader` (con
`BUILD_WSI_XCB_SUPPORT=OFF`/`BUILD_WSI_XLIB_SUPPORT=OFF`/
`BUILD_WSI_XLIB_XRANDR_SUPPORT=OFF` -- gateo real y limpio de CMake,
sin necesitar ningún patch), pineados a `v1.4.362` (ambos taggean en
lockstep). Ambos compilaron limpio a la primera.

**2. libxcvt** -- `pkg_check_modules(Libxcvt ... libxcvt>=0.1.1
REQUIRED)` (no aparece con `find_package()`, por eso no salió en el
mapeo inicial). Pese al nombre (viene del mundo Xorg/DRM), es sólo el
algoritmo VESA CVT para generar modelines de video -- matemática pura
(confirmado leyendo su `meson.build` real: única dependencia es
`libm`), usada por el backend DRM de kwin. `gitlab.freedesktop.org`
bloquea la navegación (Anubis) pero la descarga directa del tarball
funciona igual (mismo caso ya documentado para libdisplay-info) --
confirmado con un `wget` real. Versión real: `0.1.3` (Arch Linux la
empaqueta; el propio repo no lista releases navegables por el
bloqueo). Compiló limpio a la primera.

**3. KNightTime + 2 dependencias reales (Qt6 Positioning,
KF6Holidays)** -- el `feature_summary()` final marcaba KNightTime
(`>= 6.7.0`, `TYPE REQUIRED`, "Needed for Night Light") como faltante.
Es del tren de Plasma (`knighttime-6.7.4.tar.xz`, calcula amanecer/
atardecer). Su `CMakeLists.txt` real pide Qt6 Positioning (submódulo
de Qt6 nunca compilado hasta ahora, mismo tren QT6_VERSION de siempre)
y KF6Holidays (framework KDE, mismo tren KDE_VERSION de siempre --
pide FLEX+BISON REQUIRED para generar un parser real, "plan2 parser",
pero ambos ya vienen en la imagen del contenedor, confirmado con
`which flex bison`). Los 3 compilaron limpio a la primera, en cadena
(qtpositioning → kholidays → knighttime).

### El problema real más grande: `KF6_HOST_TOOLING` (7 iteraciones)

**Síntoma inicial:** `src/wayland/tools/CMakeLists.txt:18: Please
provide a prefix with a native Qt build and pass
-DKF6_HOST_TOOLING=path`. Es el mismo problema de fondo de siempre
(herramienta de build-time -- acá `qtwaylandscanner_kde` -- que no
puede correr cruzada), pero por primera vez kwin lo resuelve con un
mecanismo propio: un `ExternalProject_Add()` real que compila una
copia nativa de esa única herramienta usando
`-DCMAKE_PREFIX_PATH=${NATIVE_PREFIX}` (NATIVE_PREFIX se deriva
recortando `KF6_HOST_TOOLING` en la PRIMERA aparición de "/lib").

**Trampa real:** `KF6_HOST_TOOLING` NO es exclusivo de kwin -- es una
convención de KDE Frameworks entera. `KF6ConfigConfig.cmake`/
`KF6PackageConfig.cmake`/`KF6KCMUtilsConfig.cmake` (los mismos 3
frameworks con herramientas de build-time de siempre, ver Tier 3) miran
la MISMA variable global para decidir si buscar su
`*CompilerTargets.cmake`/`*ToolsTargets.cmake`/`*ToolingTargets.cmake`
nativo en vez del cruzado. Apenas se define (obligatorio para
wayland/tools), los 3 lookups se activan sí o sí.

**Iteración 1 (symlink de directorio a `KF6_NATIVE_INSTALL/lib/
x86_64-linux-gnu/cmake`, con Qt6 symlinkeado adentro):** falló primero
en `KF6PackageToolsTargets.cmake` -- nunca se había compilado
`kpackagetool6` nativo (nadie lo había necesitado hasta ahora).
Analizando el archivo real (`kpackage/CMakeLists.txt:115` +
`src/kpackagetool/CMakeLists.txt:16`) se confirmó que exporta un ÚNICO
target, y que nada en el build de kwin lo invoca de verdad -- construir
KPackage entero nativo (con KArchive+KI18n+KCoreAddons nativos en
cadena) hubiese sido desproporcionado. Se escribió un stub propio
(`add_executable(KF6::kpackagetool6 IMPORTED)` con
`IMPORTED_LOCATION` apuntando al binario CRUZADO real del sysroot) en
vez de compilar nada nuevo.

**Iteración 2:** el mismo síntoma reapareció con `Qt6::syncqt` (target
interno de `Qt6CoreTools`, tirado por la cadena `find_package(Qt6 ...
Core)`) -- **causa raíz real, la misma en TODAS las iteraciones
siguientes**: los `*Targets.cmake` que CMake genera calculan su
`_IMPORT_PREFIX` navegando ".." un número FIJO de niveles relativo a
su propia ubicación real. `QT6_NATIVE_INSTALL` instala sin segmento
multiarch (`lib/cmake/...`, 3 niveles) pero `KF6_NATIVE_INSTALL`
instalaba CON segmento multiarch (`lib/x86_64-linux-gnu/cmake/...`, 4
niveles) -- GNUInstallDirs detecta multiarch en builds nativos
(contenedor Debian), la cruzada no. Symlinkear un archivo a una
profundidad distinta de la que asume rompe el cálculo con un path sin
sentido cada vez (confirmado con 3 casos reales:
`kf6-native-install/lib/bin/kpackagetool6`, y después variantes
similares para `syncqt`/`kconfig_compiler_kf6`/`kconf_update`).

**Iteración 3, la que quedó (fix real de la causa raíz):** se agregó
`-DCMAKE_INSTALL_LIBDIR=lib` a `step_kconfig_native()` y
`step_kcmutils_native()` (retrofit sobre pasos ya completos de Tier 2/3)
para que instalen SIN el segmento multiarch, alineando su profundidad
con `QT6_NATIVE_INSTALL`. Con las dos profundidades iguales,
`KF6_HOST_TOOLING` pasa a ser directamente
`${QT6_NATIVE_INSTALL}/lib/cmake` (el árbol REAL de Qt6, sin ningún
symlink) y sólo hace falta symlinkear ADENTRO los 2 paquetes KF6 que sí
existen (`KF6Config`, `KF6KCMUtils`) más el stub de `KF6Package`.
`KCMUTILS_NATIVE_TOOL`/`KCONFIG_NATIVE_TOOL` se actualizaron a las
rutas nuevas (`lib/libexec/kf6/...`, sin multiarch).

**Iteraciones 4-6:** con la profundidad ya alineada, `KF6Config`/
`KF6KCMUtils` symlinkeados como DIRECTORIO calculan su `_IMPORT_PREFIX`
correctamente (¡`qt6-native-install`, el prefix del symlink!) -- pero
eso NO es donde vive el binario real (`kf6-native-install`, un prefix
FÍSICO distinto). Se resolvió symlinkeando los 3 BINARIOS reales
(`kconfig_compiler_kf6`, `kconf_update`, `kcmdesktopfilegenerator` --
confirmados los 3 nombres reales grepeando
`KF6ConfigCompilerTargets.cmake`/`KF6KCMUtilsToolingTargets.cmake`
directo, sin ir de a uno por prueba y error) en
`${QT6_NATIVE_INSTALL}/lib/libexec/kf6/`, exactamente en el path que el
cálculo de `_IMPORT_PREFIX` espera.

**Lección (aplica a todo el proyecto, no sólo kwin):** un symlink a un
archivo/directorio generado por `install(EXPORT ...)` de CMake NO es
equivalente a que el archivo esté físicamente ahí -- estos archivos
casi siempre calculan rutas relativas a su propia ubicación en vez de
usar rutas absolutas. La única forma robusta de "mover" un
`*Targets.cmake` exportado a otro lugar es: (a) que el prefix real
tenga la MISMA profundidad de directorio que el original, o (b)
generar un stub propio con rutas absolutas ya resueltas, sin ningún
cálculo relativo.

### Cuarto hallazgo real del bug sistémico de X11 (el mismo de
libplasma/libkscreen/KScreenLocker, pero mucho más chico esta vez)

`ninja` falló compilando `dialoghelper.cpp` (helper standalone del
diálogo "aplicación no responde"): `fatal error: private/
qtx11extras_p.h: No such file or directory`. Búsqueda en todo el árbol
de kwin encontró 5 archivos con el patrón, pero sólo 2 tenían el bug
real:

- `src/helpers/dialoghelper/dialoghelper.cpp` y `src/helpers/killer/
  killer.cpp` (diálogos standalone de "no responde"/"terminar
  aplicación"): include sin guard, uso real (`QX11Info::
  setAppUserTime()`) detrás de un runtime-check real
  (`platformName() == "xcb"`, siempre falso acá) -- parcheados sacando
  el include y el bloque `if (isX11) { ... }`.
- `src/main.cpp`: tiene el MISMO include, pero ya está bien guardeado
  por upstream con `#if KWIN_BUILD_X11 ... #endif` real -- no hacía
  falta tocarlo.
- `group.cpp`/`x11window.cpp`: ya estaban 100% excluidos de la
  compilación por el propio `if (KWIN_BUILD_X11) target_sources(...)`
  del `CMakeLists.txt` -- tampoco hacía falta tocarlos.

`doUnlock()`-style usos de xcb CORE puro (`xcb_generic_event_t` etc.
en `main.cpp`) compilan fino con nuestro libxcb mínimo, sin parche --
mismo criterio que en KScreenLocker.

### Resultado final

Compiló e instaló limpio: `/lfs/usr/bin/kwin_wayland` (el binario
principal -- NO "kwin" a secas), `/lfs/usr/bin/kwin_wayland_wrapper`,
`/lfs/usr/lib/libexec/kwin_dialog_helper`,
`/lfs/usr/lib/libexec/kwin_killer_helper`. Verify actualizado con estos
4 paths exactos.

**Próximo paso real**: `step_plasma_workspace()` (Tier 5, último
paquete de Fase 6 Parte 3) -- sin research todavía.

## plasma-workspace (Tier 5) -- ✅ COMPLETO (2026-09-17), cadena de 20 prerequisitos nuevos + el bug sistémico de X11 más grande del proyecto

Investigado contra el `CMakeLists.txt` REAL del tarball
`plasma-workspace-6.7.4.tar.xz` (46 `find_package()` reales). X11
gateado limpio con 2 options de CMake reales (`WITH_X11`/
`WITH_X11_SESSION`, default ON los dos) -- se apagan los dos, sin
necesitar ningún patch. A diferencia de kwin (que sólo agregó 3
prerequisitos nuevos), plasma-workspace destapó una cadena mucho más
larga -- 18 paquetes nuevos reales hasta ahora, casi todos compilados
limpio a la primera con el nombre de librería adivinado correctamente
(evidencia de que el research previo del proyecto para las dependencias
"chicas" ya viene siendo sólido):

**Directos de plasma-workspace:**
- **QCoro6** (`v0.13.0`, github.com/danvratil/qcoro) -- wrapper de
  corutinas C++20 sobre Qt6. `QCORO_WITH_QTWEBSOCKETS=OFF` (no
  compilado, sólo se pide el componente Core); se instala como
  ESTÁTICA (`.a`, no `.so`).
- **ICU4C** (`78.3`, unicode-org/icu) -- el más complicado de compilar
  de toda la sesión, 3 bugs reales distintos:
  1. `rm: symbol lookup error: libc.so.6: undefined symbol:
     __pointer_chk_guard` durante `make install` (pkgdata invocando
     `rm`/`ln` vía `system()` con un `LD_LIBRARY_PATH` apuntando al
     build nativo) -- resuelto con `--with-data-packaging=archive` en
     vez de perseguir la causa exacta dentro de pkgdata.
  2. `out/tmp/icudata.lst: No such file or directory` -- bug real de
     upstream en `data/Makefile`: la rama "ICUDATA_SOURCE_IS_NATIVE_TARGET"
     hace `echo "$@" > $@` sin crear `$(OUTTMPDIR)` antes (la otra rama
     sí lo hace) -- se crea el directorio a mano antes de `make`.
  3. Build cruzado de dos pasadas real, documentado oficialmente
     (unicode-org.github.io/icu/userguide/icu4c/build.html): un build
     NATIVO completo primero (`runConfigureICU Linux`, sin install,
     sólo queda el directorio de build), después el cruzado con
     `--with-cross-build=<dir nativo>`.
- **libxcvt** (`0.1.3`, xorg/lib/libxcvt) -- descubierto vía
  `pkg_check_modules`, no `find_package()` (por eso no salió en el
  mapeo inicial de kwin). Matemática pura (algoritmo VESA CVT), sin
  nada de X11 pese al nombre.
- **Qt6 Location** (submódulo separado de Qt6Positioning, tarball real
  distinto) -- `find_package(Qt6 ... COMPONENTS Location)`.
- **KF6NetworkManagerQt** (`networkmanager-qt`, con guiones -- no
  "knetworkmanagerqt") -- pide `libnm>=1.4.0` vía `pkg_search_module`
  REQUIRED. **Este es el bloqueo actual** -- ver abajo.

**7 frameworks KF6 nuevos** (`find_package(KF6 ... COMPONENTS ... KDED
Parts Prison StatusNotifierItem TextEditor TextWidgets Wallet)`,
ninguno en el mapa original de Tier 2):
- **KDED**: sin librería, sólo el daemon `kded6`.
- **KParts**: sin sorpresas.
- **KStatusNotifierItem**: `-DWITHOUT_X11=ON` (X11 opcional, sin
  REQUIRED, pero se apaga explícito por prolijidad).
- **Prison** (códigos QR/barras): pide `libqrencode` SIEMPRE (sin
  opción para sacarlo) -- `-DWITH_DMTX=OFF -DWITH_ZXING=OFF` para los
  2 backends opcionales que si quedan prendidos piden libdmtx/
  zxing-cpp. **Bug real de link**: `libqrencode.a` se compila sin
  `-fPIC` por default -- falla al linkearla DENTRO de
  `libKF6Prison.so` (`relocation ... can not be used when making a
  shared object`) -- fix: `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` en el
  build de libqrencode.
- **KWallet**: la cadena de dependencias más larga de todas --
  `LibGcrypt` REQUIRED real (`kwalletd needs libgcrypt to perform
  PBKDF2-SHA512 hashing`), NO opcional (a diferencia de `Gpgmepp`/GPGME,
  que sí lo es -- se deja sin construir). `ksecretd` (el daemon
  freedesktop Secret Service, alternativo a `kwalletd`) pide
  `Qca-qt6 REQUIRED` aparte -- se deshabilita con
  `-DBUILD_KSECRETD=OFF` en vez de agregar QCA (confirmado que
  `kwalletd`, el daemon clásico, es independiente y sigue funcional
  con sólo libgcrypt). `kwalletd` en sí pide `libsecret-1` REQUIRED
  (vía pkg-config) sin ninguna opción. **Bug real de upstream**: dos
  archivos de `kwalletbackend` (`blowfish.h`, `sha1.cc`) incluyen
  `<stdint.h>` condicionado a `HAVE_STDINT_H`, un macro de
  `check_include_files(stdint.h ...)` que da **falso negativo** en
  nuestro build cruzado (mismo síntoma ya visto sin consecuencia en
  otros checks de este proyecto) -- error real:
  `'uint32_t' was not declared in this scope`. Se sacó el guard
  (`_patch_kwallet()`, primer uso real del hook de patch en
  `_kf6_cmake_build()` -- antes sólo lo tenía `_plasma_cmake_build()`,
  se agregó ahí también).
- **KTextWidgets** y **KTextEditor**: piden Qt6 TextToSpeech
  (submódulo `qtspeech`, nunca compilado). En KTextEditor es
  REQUIRED sin ninguna opción para sacarlo. `qtspeech` a su vez
  **no configura NINGÚN target** si no encuentra Qt6Multimedia
  (opcional, pero sin él qtspeech se salta entero: "Skipping the
  build as the condition 'TARGET Qt6::Multimedia' is not met") --
  se agregó **Qt6 Multimedia** (submódulo `qtmultimedia`) también,
  compilando sin ningún backend real (GStreamer/FFmpeg/PipeWire vía
  `qt_feature()`, ninguno REQUIRED) -- sólo hace falta que exista el
  target CMake, no audio/video funcional de verdad.
  KTextEditor también pide **KSyntaxHighlighting** (framework KF6
  nuevo) y **KParts**, y `KAuth` si `ENABLE_KAUTH` (default ON en
  Linux real, no un caso de confundir host con target) --
  `-DENABLE_KAUTH=OFF` para no agregar KAuth+polkit especulativamente.
  KTextWidgets también pide **Sonnet** (corrección ortográfica) --
  **nunca se había compilado en este proyecto pese a figurar como "ya
  construido" en el mapa heredado de sesiones anteriores** (confirmado
  que no existía ningún `KF6Sonnet*` real en el sysroot -- lección:
  nunca confiar en un resumen de sesión vieja sin confirmar contra el
  sysroot real). Sonnet en sí no pide nada externo nuevo --
  `-DSONNET_NO_BACKENDS=ON` porque los backends reales (hunspell/
  aspell) son opcionales y quedan sin construir (sin consumidor real
  que exija corrección ortográfica funcional todavía).

**Investigación tercerizada:** para mapear las dependencias reales de
los 7 frameworks KF6 de una sola vez (en vez de una corrida real por
cada uno), se delegó la investigación inicial a un sub-agente
(fetch de los 7 `CMakeLists.txt` reales vía invent.kde.org). Su reporte
tuvo un error real de mezclar plataforma HOST con plataforma TARGET
(ej. "X11 se desactiva en Windows", "KAuth se desactiva en Windows") --
como el TARGET de este proyecto es Linux (no importa que el build corra
en un host Windows), esas conclusiones eran falsas para nuestro caso;
se verificaron a mano las condiciones reales de CMake
(`if (NOT WIN32 AND NOT HAIKU)`, etc.) contra nuestro TARGET antes de
confiar en ellas -- lección: un sub-agente puede confundir contexto de
plataforma igual que cualquier razonamiento sin verificación real.

**Resuelto: KF6NetworkManagerQt pedía `libnm>=1.4.0` (NetworkManager)
real vía pkg-config, sin ninguna opción para sacarlo.** A diferencia de
todo lo anterior (bibliotecas chicas, autocontenidas), NetworkManager es
un subsistema completo -- consultado con Juani si construirlo entero o
pausar la sesión; eligió construirlo completo. Investigado contra el
`meson.build` real de `NetworkManager/1.50` (Meson, `1.50.0` -- versión
PAR, estable según la convención de versionado real de GNOME, confirmada
con el marcador `LATEST-IS-1.50.0` real en
`download.gnome.org/sources/NetworkManager/1.50/`):

- **libndp** (`v1.9`, github.com/jpirko/libndp) -- única dependencia
  nueva de verdad (`dependency('libndp')` sin opción, todo lo demás --
  uuid, libudev, dbus-1, gio-unix-2.0/glib, polkit-gobject-1 -- ya
  estaba en el sysroot). El tarball de GitHub no trae `configure`
  pre-generado -- `autoreconf -fi` antes de `./configure`.
- **Minimización agresiva de features** (no se quiere el daemon
  completo, sólo `libnm` como librería cliente para KF6NetworkManagerQt):
  `-Dppp=false -Dmodem_manager=false -Dovs=false -Dnmtui=false
  -Dnm_cloud_setup=false -Dtests=no -Ddocs=false -Dintrospection=false
  -Dvapi=false -Dqt=false -Dcrypto=null -Dlibpsl=false
  -Dconcheck=false -Dnmcli=false`.
- **Bug real de infraestructura:** `xsltproc` no estaba en la imagen del
  contenedor (`find_program('xsltproc')` sin `required: false` en el
  `meson.build` real). Al ser una herramienta NATIVA faltante (no del
  sysroot cruzado), el fix real y durable es agregarlo al `Dockerfile`
  (ítem 14 de su lista numerada) y reconstruir la imagen
  (`podman-compose build builder`) -- distinto del patrón ya conocido de
  "el filesystem del contenedor `--rm` es efímero": acá el fix vive en
  la imagen misma, no en una escritura dentro de un contenedor de una
  sola corrida.
- **Bug real de gettext/ITS:** el merge de traducciones del `.policy` de
  polkit (`msgfmt --xml`) fallaba porque gettext 0.21 no tenía reglas ITS
  (Internationalization Tag Set) para `*.policy`. Confirmado leyendo
  directo `/usr/share/gettext-0.21/its/metainfo.loc`/`.its` reales
  dentro del contenedor (formato real: `.loc` es
  `<locatingRules><locatingRule pattern="*.ext"><documentRule
  localName="..." target="foo.its"/></locatingRule></locatingRules>`,
  `.its` es ITS-2.0 estándar). **Gotcha real confirmado:** el `pattern`
  se matchea contra el nombre de archivo CON el `.in` final YA SACADO
  (el `metainfo.loc` real usa `pattern="*.metainfo.xml"` pese a que las
  plantillas se llaman `*.metainfo.xml.in`) -- el primer intento con
  `pattern="*.policy.in"` falló en silencio hasta corregirlo a
  `pattern="*.policy"`. También confirmado que la variable de entorno
  `GETTEXTDATADIRS` NO funcionó como mecanismo de inyección en este
  build exacto de gettext 0.21 (probado con y sin, mismo error) -- el
  único fix real fue escribir los archivos `.loc`/`.its` con `sudo tee`
  DIRECTO en el path de búsqueda real confirmado
  (`/usr/share/gettext-0.21/its/`), dentro de la MISMA invocación de
  `podman-compose run` que el build real (seguro para un contenedor
  efímero porque ambas cosas pasan en una sola corrida).
- **PolkitQt6-1** (`0.201.1`) -- compilado aparte como prerequisito de
  KF6NetworkManagerQt/plasma-workspace (verify corregido al nombre real
  instalado: `libpolkit-qt6-core-1.so`).

Con NetworkManager+libndp+PolkitQt6-1 resueltos, plasma-workspace pasó a
compilar de verdad -- y ahí apareció el bug sistémico de X11 más grande
de todo el proyecto (más grande incluso que KScreenLocker en kwin):

### El bug sistémico de X11 en plasma-workspace (18+ archivos reales)

Mismo patrón ya visto en libplasma/libkscreen/KScreenLocker/kwin: código
fuente de KDE 6.7.4 que incluye headers exclusivos de X11 (`KX11Extras`,
`KWindowInfo`, `KStartupInfo`, `KUserTimestamp`, `netwm.h`, `KKeyServer`,
`xcb/xcb.h`, `qtx11extras_p.h`, `QNativeInterface::QX11Application`) SIN
guard de preprocesador, pese a que el uso real de esos símbolos SÍ está
protegido en tiempo de ejecución (`KWindowSystem::isPlatformX11()`) o a
veces con un `#if HAVE_X11` real pero incompleto (guarda el uso, no el
include). Encontrado y corregido con `ninja -k0` (colecta TODOS los
errores reales de compilación en una sola pasada -- mucho más eficiente
que el loop de un error a la vez para un patch surface de este tamaño) a
lo largo de ~16 corridas reales, todo dentro de `_patch_plasma_workspace()`
en `scripts/build-kde.sh`:

- `CMakeLists.txt` -- `xembed-sni-proxy` y `gmenu-dbusmenu-proxy`
  gateados detrás de `if(WITH_X11)` (antes se intentaban compilar
  siempre).
- `kcms/krdb/CMakeLists.txt`, `logout-greeter/CMakeLists.txt`,
  `kcms/colors/CMakeLists.txt` (2 targets) -- sacado el link
  incondicional a `X11::X11`.
- `appmenu/menuimporter.cpp`, `libnotificationmanager/server.cpp`,
  `libnotificationmanager/portal_p.cpp`, `klipper/urlgrabber.cpp`
  (include muerto), `soliduiserver/soliduiserver.cpp` (`KUserTimestamp`)
  -- código muerto sacado.
- `libtaskmanager/virtualdesktopinfo.cpp` -- 2 rondas: primero un
  problema de ORDEN de macro (`#if HAVE_X11` referenciado ANTES del
  `#include <config-X11.h>` que lo define -- error real de
  `-Werror=undef`, hay que mover el bloque guardado a DESPUÉS del
  include), después el namespace local `X11Info` (usaba
  `QNativeInterface::QX11Application`, un TIPO que no existe cuando el
  propio Qt6 se compiló sin xcb/`FEATURE_xcb`).
- `applets/kicker/windowsystem.cpp`, `applets/kicker/dashboardwindow.cpp`
  (3 bloques) -- código muerto sacado.
- `klipper/klipperpopup.cpp` (4 bloques, algunos con rama `else` real
  preservada).
- `applets/notifications/notificationwindow.cpp` (2 bloques),
  `krunner/view.cpp` (5 bloques) -- código muerto sacado.
- `logout-greeter/shutdowndlg.cpp` -- llamadas Xlib reales (no sólo
  muertas) sacadas.
- `shell/desktopview.cpp` -- 4 reemplazos, incluidas 2 condiciones
  `QNativeInterface::QX11Application` (el mismo problema de TIPO
  inexistente que en `virtualdesktopinfo.cpp`).
- `shell/shellcorona.cpp` -- sólo el include (el uso ya estaba
  guardado).
- `shell/panelview.cpp` -- include + un `if` con
  `compositingActive()` mal formado + 6 bloques `refreshStatus()` en
  total (repartidos en 2 rondas), uno de ellos con rama real: `if
  (isPlatformX11()) { KX11Extras::forceActiveWindow(...); } else {
  showTemporarily(); }` colapsado a sólo `showTemporarily();`.
- **`applets/notifications/notificationapplet.cpp`** -- el último en
  caer, y el único con un error propio (no de upstream): al agregar un
  guard de RUNTIME (`isPlatformX11()`) nuevo alrededor de una llamada
  antes incondicional a `KX11Extras::forceActiveWindow()`, se guardó el
  USO pero no el **`#include <KX11Extras>`** -- que sigue fallando
  regardless del guard de runtime, porque el header no existe en el
  sysroot. Peor: a diferencia de `soliduiserver.cpp`/`shellcorona.cpp`/
  `panelview.cpp` (que YA traían `#include "config-X11.h"` en el
  upstream original), este archivo nunca lo tuvo -- típeo real:
  `"HAVE_X11" is not defined, evaluates to 0 [-Werror=undef]`. Fix real:
  agregar `#include "config-X11.h"` + envolver tanto el include de
  `<KX11Extras>` como el bloque de uso completo en `#if HAVE_X11 ...
  #endif`.

**Build final (build16, 2026-09-17): plasma-workspace compiló e instaló
limpio, 0 `FAILED:` en todo el log.** `step_verify_plasma_workspace()`
corregido con rutas reales confirmadas post-instalación -- **Plasma 6 NO
instala un `ksmserver` standalone** (la sesión la maneja
`plasma_session`/`startplasma-wayland`; sólo queda
`ksmserver-logout-greeter` en `libexec/` y el `.notifyrc`, nada más,
confirmado con `find` real). Verify real, corrido y en verde:
`plasmashell`, `krunner`, `plasma_session`, `startplasma-wayland` (en
`bin/`) + `ksmserver-logout-greeter` (en `lib/libexec/`).

**Con esto queda compilado el núcleo de Plasma** (corregido 2026-10-22:
acá decía "Fase 6 Parte 3 COMPLETA", pero `plasma-workspace` solo no da un
escritorio usable — ver la sección siguiente).

## Escritorio usable (Fase 6 Parte 3, continuación) — 🟡 en curso desde 2026-10-22

Al revisar qué faltaba (2026-10-22) se confirmó con `grep` que
`build-kde.sh` no tiene ningún paso para los componentes de Plasma que
están por encima de `plasma-workspace`: el paquete de escritorio, un login
manager, `systemsettings`, los applets de red y audio, ni aplicaciones base.
Tampoco se compilaron las dependencias opcionales que la decisión "alcance:
todo desde el principio" (2026-09-04) incluía: Baloo, PackageKitQt6,
AppStreamQt, KIOExtras/KIOFuse, libei, AccountsService,
QAccessibilityClient6, KExiv2Qt6, Union. Decisión de Juani (2026-10-22):
completar el escritorio antes del primer arranque de prueba en QEMU.

### Research (2026-10-22) contra los `CMakeLists.txt` reales de Plasma 6.7.4

Lista de tarballs confirmada contra `download.kde.org/stable/plasma/6.7.4/`.
**`plasma-login-manager` sale como parte de Plasma 6.7.4** — no hace falta
SDDM aparte. Los 15 paquetes del núcleo del escritorio se bajaron y se
leyeron dentro del contenedor (`/lfs/build/research-desktop/`), no con
WebFetch: un primer pase con WebFetch resumía con un modelo chico y perdía
el anidamiento de los `if()`, así que todo lo condicional se verificó
leyendo el archivo real.

**Se resuelve con opciones oficiales, sin parches:**
- `kscreen` y `plasma5support`: `WITH_X11=OFF`.
- `plasma-nm`: Qt WebEngine (Chromium entero) sólo se pide con
  `BUILD_OPENCONNECT=ON` — se apaga.
- `plasma-desktop`: `BUILD_KCM_MOUSE_X11=OFF` / `BUILD_KCM_TOUCHPAD_X11=OFF`
  (esos backends piden headers de drivers del servidor X, `xorg-libinput`).
- `powerdevil`: pide `XCB RANDR DPMS` REQUIRED, pero los da la libxcb que
  ya está en el sysroot.
- `plasma-login-manager`: pide `xau` (ya en el sysroot), PAM y systemd.

**Tres decisiones tomadas con Juani:**
1. **plasma-desktop exige libX11** (`set_package_properties(X11 ... TYPE
   REQUIRED)` sin condición) y `XCB REQUIRED COMPONENTS XCB SHM IMAGE`. El
   KCM de distribución de teclado y `kaccess` ya están detrás de
   `if(X11_Xkb_FOUND AND XCB_XKB_FOUND)`.
   - **Primera decisión (revertida):** compilar libX11 + libxkbfile sólo
     como librerías cliente, para tener el KCM de teclado. Se compilaron
     (ver "Progreso real") y recién después, al leer el código real del
     KCM, apareció que tampoco alcanzaba: `kcms/keyboard` usa
     `QX11Info::display()` / `qtx11extras_p.h` (sólo existe con **Qt6
     compilado con la plataforma xcb**) y `KX11Extras`/`KWindowInfo` (sólo
     con **KWindowSystem compilado con X11**). Tenerlo exigía meter soporte
     X11 real en Qt — mucho más que "librerías cliente". Error de
     planificación propio: la opción se ofreció sin haber leído el código
     del KCM.
   - **Decisión final (Juani, 2026-10-22), por la filosofía del sistema:
     parchear, Wayland puro.** El documento fundacional lo dice explícito
     (Pilar 5: "se construye exclusivamente sobre Wayland"; sección 6:
     "sin arrastrar compatibilidad con X11"); además Seguridad (menos
     superficie) y Robustez (~15 paquetes menos). Sin KCM gráfico de
     teclado: el layout queda fijo en `/etc/skel` (`kxkbrc`) y kwin lo
     aplica en Wayland. libX11/libxkbfile/xtrans se sacaron del sysroot
     (`make uninstall` / `ninja uninstall`, más los `.so` de libX11 a mano
     porque el step borra los `.la` y libtool los necesita para
     desinstalar) y del script. xcb-util + xcb-util-image se quedan: `XCB
     IMAGE` sigue siendo REQUIRED.
2. **plasma-pa exige `libpulse` y `libpulse-mainloop-glib`.** Decisión:
   compilar PulseAudio **sólo como librería cliente, con el daemon
   apagado**. Habla con el `pipewire-pulse` que ya está; no hay servidor
   PulseAudio en el sistema (el pilar "sin PulseAudio" se refiere al
   servidor). Además pide `KF6PulseAudioQt` (pulseaudio-qt).
3. **plasma-nm exige `ModemManagerQt`** sin condición, y los 23 archivos
   que lo usan no tienen ningún guard. Decisión: **compilar ModemManager
   mínimo + ModemManagerQt** (mismo enfoque que NetworkManager), sin parches.

**Dependencias nuevas detectadas:** frameworks KF6 knotifyconfig,
kunitconversion, qqc2-desktop-style y modemmanager-qt; terceros
pulseaudio-qt, qtkeychain, libpulse (+ libsndfile), ModemManager,
xcb-util-image, y xdg-desktop-portal (runtime de xdg-desktop-portal-kde).
Konsole y Dolphin salen de KDE Gear (otro tren de versiones) — research
aparte.

### Progreso real (2026-10-22)

- **xcb-util 0.4.1 + xcb-util-image 0.4.1 — ✅ a la primera** (últimas en
  `xorg.freedesktop.org/archive/individual/xcb/`). libX11 1.8.14,
  libxkbfile 1.2.0 y xtrans 1.6.0 también compilaron a la primera, pero se
  descartaron (ver decisión 1). Mientras estuvieron en el sysroot, los
  helpers pasaban `-DCMAKE_DISABLE_FIND_PACKAGE_X11=ON` para que ningún
  `find_package(X11)` opcional las tomara solo (los tres frameworks de
  abajo se compilaron así); al sacarlas, el flag se quitó.
- **Frameworks KF6 — ✅ a la primera:** knotifyconfig, kunitconversion,
  qqc2-desktop-style (plugin `org.kde.desktop` en
  `usr/lib/plugins/kf6/kirigami/platform/`).
- **Bug del doble sysroot (`/lfs/lfs`) — dos casos más encontrados y
  corregidos.** Al revisar los logs de TODO el proyecto (`grep -l
  "/lfs/lfs/" logs/*.log`) aparecieron, además de los cuatro de
  `build-desktop.sh` ya corregidos el 2026-09-30:
  - **libcanberra**: 3 `.service` de systemd perdidos (ya figuraba como
    "nota menor" más abajo, pendiente). Fix: `--with-systemdsystemunitdir`.
  - **NetworkManager**: 4 unidades systemd (`NetworkManager.service`,
    `-dispatcher`, `-wait-online`, `nm-priv-helper`) y su política de
    polkit, perdidas desde el 2026-09-16. El cross-file de Meson de
    `build-kde.sh` tiene `sys_root`, y Meson con eso setea
    `PKG_CONFIG_SYSROOT_DIR` solo — misma causa raíz. Fix:
    `-Dsystemdsystemunitdir=` para las unidades; la política de polkit no
    tiene opción de override (`meson.build` línea 506), así que se agregó
    `merge_doubled_sysroot()` (mueve lo que haya caído en `/lfs/lfs` al
    sysroot real y deja en el log qué movió).
  - Los verifies de los dos ahora chequean esos archivos — que ningún
    verify los mirara es justamente lo que dejó pasar el bug semanas.
- **Terceros para plasma-pa/plasma-nm — ✅ todos compilados y verificados:**
  qtkeychain 0.17.0 (a la primera), pulseaudio-qt 1.9.0, libpulse 17.0
  (sólo cliente; el verify confirma que NO se instaló el daemon),
  libsndfile 1.2.2, ModemManager 1.24.2 (mínimo) y modemmanager-qt.
  Dos errores reales en el primer intento:
  - **libsndfile**: `Compatibility with CMake < 3.5 has been removed from
    CMake` (línea 1 de su `CMakeLists.txt`) — mismo caso que libqrencode,
    mismo fix: `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.
  - **ModemManager**: `Assert failed: udevdir must be explicitly given if
    udev support is disabled` (`meson.build` línea 199) — fix:
    `-Dudevdir=/usr/lib/udev`. `udev=false` porque con udev pide libgudev,
    que no está; consecuencia: el daemon no detecta módems por hotplug (en
    el laboratorio no hay).
  - En ModemManager, `merge_doubled_sysroot` movió sólo la política de
    polkit (`org.freedesktop.ModemManager1.policy`) — lo esperado, es lo
    único sin opción de override.
- **Red de seguridad agregada:** nueve paquetes de Plasma leen rutas de
  systemd con `pkg_get_variable()` (polkit-kde-agent-1, kscreen,
  plasma-login-manager, kactivitymanagerd, xdg-desktop-portal-kde,
  powerdevil, plasma-desktop/kaccess…). `_kf6_cmake_build()` y
  `_plasma_cmake_build()` llaman a `merge_doubled_sysroot` después de
  instalar, así lo que caiga en `/lfs/lfs` se mueve y queda en el log.
- **Paquetes de Plasma 6.7.4 — los 16 ✅ compilados y verificados:**
  plasma5support, kactivitymanagerd, qqc2-breeze-style, plasma-integration,
  **plasma-desktop** (shell `org.kde.plasma.desktop`), systemsettings,
  kde-cli-tools, polkit-kde-agent-1, milou, kscreen, powerdevil, plasma-nm,
  plasma-pa, **plasma-login-manager** (`plasmalogin.service`),
  xdg-desktop-portal-kde y print-manager (los dos últimos con la impresión,
  ver más abajo). Errores reales y fixes, en orden:
  - **Mismo bug sistémico de X11 de siempre** (include X11-only sin guard,
    uso detrás de un chequeo de runtime) en polkit-kde-agent-1
    (`policykitlistener.cpp`), kscreen (`osd/osd.cpp`), plasma-nm
    (`libs/handler.cpp`, `kded/secretagent.cpp`, `kded/pindialog.cpp`) y
    powerdevil (`kwinkscreenhelpereffect.cpp`, `actions/bundled/dpms.cpp` —
    acá además `HAVE_XCB` sale de `XCB_FOUND` pero el código usa
    `QX11Info`, que necesita Qt con xcb: se fuerza `HAVE_XCB 0` y en
    `dpms.cpp` queda sólo la rama de Wayland). Parches agrupados en
    `_apply_x11_patches()`.
  - **plasma-integration**: `BUILD_QT5=OFF` (default ON, pediría Qt5
    entero); X11 `TYPE REQUIRED` → OPTIONAL; `XCB::XCB` linkeado sin usarse
    (el plugin lo carga cualquier app Qt, no tiene que arrastrar libxcb);
    `x11integration.cpp` se compilaba siempre (incluye `<NETWM>`) — sale
    del build y el miembro `QScopedPointer<X11Integration>` queda detrás del
    mismo `HAVE_X11` que su instanciación.
  - **plasma-desktop** (5 rondas): X11 `TYPE REQUIRED` → OPTIONAL;
    `find_package(KSMServerDBusInterface CONFIG REQUIRED)` vestigial
    (plasma-workspace sólo compila ksmserver con `WITH_X11`, y nada en
    plasma-desktop usa esa variable); 4 includes X11 muertos
    (`KKeyServer`, `KWindowInfo`, `netwm.h`, `fixx11h.h`); `XKBDIR` de
    pkg-config con el sysroot adentro Y compilado en el binario — se le saca
    el prefijo; la comprobación de esa ruta además falla porque
    xkeyboard-config 2.48 instala `X11/xkb` como symlink ABSOLUTO a
    `/usr/share/xkeyboard-config-2` (bien en el sistema real, colgado en el
    sysroot) — se acepta el symlink; y un bug de upstream:
    `ConfigureChecks.cmake` usa `check_function_exists`/`check_include_files`
    sin incluir sus módulos.
  - **plasma-desktop pedía un XML de kwin roto:** `qdbusxml2cpp` rechazó
    `org.kde.kwin.InputDevice.xml` (7 propiedades con `type=""`). Causa
    raíz: la QtDBus NATIVA (la de `qdbuscpp2xml`, que genera ese XML en el
    build de kwin) carga `libdbus-1.so.3` en runtime para calcular firmas
    de tipos compuestos (`QRectF`, `QSizeF`, `QList<uint>`) y el contenedor
    no la tenía — devuelve firma vacía sin avisar. Fix durable:
    `libdbus-1-3` al Dockerfile (ítem 15) + imagen reconstruida + kwin
    recompilado (el XML quedó con 0 propiedades vacías). Era el único XML
    instalado con el problema (`grep -l 'type=""'`).
  - **kactivitymanagerd**: `find_package(Boost 1.58 REQUIRED)` — sólo usa
    `boost/range` (header-only): se copian los headers de Boost 1.92.0 al
    sysroot (`step_boost_headers`).
  - **plasma-login-manager**: elige su plantilla PAM leyendo
    `/etc/os-release` (no existe en el sysroot) — `-DPAM_OS_CONFIGURATION=debian`,
    porque la cadena PAM de Fase 4 ya es estilo Debian (`common-*`), así
    que hereda sola faillock + FIDO2. El greeter linkeaba `X11::X11` sin
    usar Xlib — se saca el link.
  - **plasma-pa** compiló a la primera; el que fallaba era el verify:
    `find ... | head -n1` con `set -o pipefail` — con muchas coincidencias
    (los `.mo`), `head` cierra el pipe, `find` muere con SIGPIPE y
    `pipefail` mata el script en silencio. Todos los verifies nuevos pasaron
    a `find ... -print -quit`.
- **xdg-desktop-portal-kde destrabó la impresión:** su `print.cpp` usa
  `QtPrintSupport/private/qcups_p.h` (`QCUPSSupport`) sin condición, y el
  Qt6 de este proyecto se había compilado sin CUPS — de fondo, **el sistema
  entero no podía imprimir** (Qt sin CUPS sólo imprime a PDF).

### Impresión (2026-10-22 / 2026-10-27)

**Decisión de Juani: "CUPS + filtros, sin ghostscript".** En el laboratorio
hoy no hay impresoras ni servidor de impresión; el sistema queda listo para
cuando se conecte una. Research contra los tarballs reales:
- CUPS 2.4.20 compila libcups + `cupsd` juntos; dependencias (OpenSSL,
  zlib, PAM, systemd, dbus) ya en el sysroot.
- libcupsfilters 2.2 **reemplazó qpdf por PDFio** (C, chico, del autor de
  CUPS): `PKG_CHECK_MODULES([LIBPDFIO], [pdfio >= 1.6.4])` sin condición.
- PDF→raster NO está en libcupsfilters: invoca **ghostscript o mupdf** como
  binarios externos (opciones `--disable-ghostscript`/`--disable-mutool`).
  Sin ellos se imprime en impresoras que aceptan PDF directo (la mayoría de
  las de red modernas); ghostscript se agrega si aparece una que lo necesite.
- Sin Avahi (`--with-dnssd=no`): impresoras por IPP a mano, sin
  autodescubrimiento.

**Compilado y verificado:** PDFio 1.6.5, CUPS 2.4.20, libcupsfilters 2.2.1,
libppd 2.1.1, cups-filters 2.0.1 (27 filtros + `driverless` + backends),
qtbase con `-DFEATURE_cups=ON` (plugin `libcupsprintersupport.so` +
`qcups_p.h`), print-manager (KCM de impresoras, `SCP_INSTALL=OFF`) y
xdg-desktop-portal-kde. Errores reales, en orden:
- **CUPS 2.4.20 — bug de upstream sin DNS-SD:** `cupsEnumDests()` usa
  `data.num_local`/`data.local_dests` con `data` de tipo
  `_cups_getdata_t`, que nunca declara esos campos (sólo la variante con
  DNS-SD) — `error: '_cups_getdata_t' has no member named 'num_local'`. Con
  Avahi (lo normal) no se ve. Fix: declarar los dos campos (el código ya los
  inicializa en 0/NULL y los libera).
- **libcupsfilters:** `BUILT_SOURCES` genera un archivo de prueba ejecutando
  `gen-lorem-text`, compilado CRUZADO (`GLIBC_2.38 not found`). Son datos
  para `make check` — `make BUILT_SOURCES=` los saltea sin tocar la fuente.
  Además, `merge_doubled_sysroot` movió los banners de CUPS que caían en
  `/lfs/lfs` (la red de seguridad funcionando).
- **libppd 2.1.1 — bug de upstream sin renderizadores:** con todos
  apagados, `CUPS_PDFTOPS_RENDERER` queda vacío y `pdftops.c` hace
  `renderer = CUPS_PDFTOPS_RENDERER;` (`expected expression before ';'`).
  Fix: el `configure` arranca con `GS` por default en vez de vacío (el
  filtro busca gs en runtime y falla claro si no está).
- `cups-config` del sysroot es seguro en build cruzado: con prefix `/usr`
  devuelve `--cflags` vacío y `--libs -lcups` (confirmado).
- **libcupsfilters — ruta del sysroot compilada (lo encontró
  `check-sysroot.sh`):** su configure toma `CUPS_DATADIR` con `pkg-config
  --variable=cups_datadir cups`, que con `PKG_CONFIG_SYSROOT_DIR` vuelve
  `/lfs/usr/share/cups` — quedaba en `config.h` (dentro de la librería) y
  como ruta de instalación. Fix: el configure le saca el sysroot a ese
  valor (`_patch_libcupsfilters_datadir`).
- **print-manager:** el mismo bug sistémico de X11 en 3 archivos de un
  solo golpe (`libkcups/KCupsPasswordDialog.cpp`,
  `configure-printer/ConfigurePrinterInterface.cpp` — if/else que queda en
  la rama de Wayland, con `<QWindow>` incluido directo porque lo traía
  `KX11Extras` de forma transitiva — y `print-queue/PrintQueue.cpp`, donde
  `KUserTimestamp::userTimestamp()` es código vivo: se pasa `0`, que es lo
  que esa función devuelve fuera de X11). `SCP_INSTALL=OFF` (sin
  PackageKit). Además `download.kde.org` mandaba siempre a un mirror de
  Brasil caído (`linorg.usp.br`); el tarball se bajó del mirror de GWDG y se
  controló contra el sha256 oficial de `download.kde.org` (idéntico).
- **Orden de `all`:** qtbase ahora necesita CUPS antes; `step_cups` va
  delante de `step_qtbase` (CUPS sólo depende de fases anteriores).

### Directorio de plugins de Qt desalineado con KDE (2026-10-27) — CRÍTICO

Al revisar dónde instalaba Qt el plugin de CUPS: Qt tenía compilado
`plugins` (= `/usr/plugins`) como directorio de plugins, pero TODO KDE
instala en `/usr/lib/plugins` (`KDE_INSTALL_QTPLUGINDIR` cae al fallback de
KDEInstallDirs6 en build cruzado). En el sistema real Qt sólo mira su propio
directorio: **ningún plugin de kwin, applet de Plasma, KCM, módulo de kded
ni el tema de plataforma de KDE se hubiera encontrado.** Mismo bug y mismo
criterio que `INSTALL_QMLDIR=lib/qml` (2026-09-04): se alinea Qt a KDE con
`-DINSTALL_PLUGINSDIR=lib/plugins` en qtbase (los demás módulos lo heredan
de su config) y se recompilaron los 10 módulos de Qt que instalan plugins;
se borró el `/usr/plugins` viejo (todas sus carpetas tenían reemplazo).
`check-sysroot.sh` suma un tercer chequeo: `QT6_INSTALL_PLUGINS`/
`QT6_INSTALL_QML` tienen que ser `lib/plugins`/`lib/qml` y `/usr/plugins` no
tiene que existir.

**Lección de procedimiento (error propio, 2026-10-27):** editar
`build-kde.sh` mientras un build en segundo plano lo está ejecutando corta
la corrida — bash lee el script de a pedazos y, si las líneas se mueven,
sigue desde un punto equivocado (`p_verify_systemsettings: command not
found` al final del step de qtbase, que sí había instalado bien). No editar
scripts con un build en curso.
- **Otros pendientes del escritorio:** kpipewire (módulo QML
  `org.kde.pipewire`, RUNTIME de plasma-desktop: miniaturas de ventanas en
  el taskmanager bajo Wayland), layout de teclado fijo + tema oscuro + Nerd
  Fonts en `/etc/skel`, Konsole y Dolphin (KDE Gear), y las dependencias
  opcionales de la decisión "alcance: todo" (Baloo, PackageKitQt6,
  AppStreamQt, KIOExtras/KIOFuse, libei, AccountsService,
  QAccessibilityClient6, KExiv2Qt6, Union).
- **Refactor sin cambio de comportamiento:** las reglas ITS de gettext para
  `.policy` de polkit (fix real de NetworkManager) pasaron a un helper,
  `install_polkit_its_rules()`, porque ModemManager necesita lo mismo.

## Fase 6 — Parte 3 (Qt6 + KDE Frameworks/Plasma) — 🟡 núcleo compilado (2026-09-17), escritorio usable en curso (2026-10-22)

Prerequisito de xkbregistry ya cumplido (ver más abajo). El trabajo real de
Parte 3 (Qt6/KF6/kwin/plasma-workspace en sí) arrancó el mismo día: research
completo contra fuente real antes de escribir nada (`invent.kde.org` y
`github.com/qt` SÍ accesibles desde este sandbox, a diferencia de
`gitlab.freedesktop.org`/`gitlab.gnome.org` en research anteriores —
confirmado en vivo), y **Tier 0 (extra-cmake-modules) ya compilado, instalado
y verificado en el sysroot**, primer intento, sin errores reales.

### Decisiones tomadas (2026-09-04)

- **Qt6 6.11.2** — último release estable real (confirmado contra los tags
  reales de `github.com/qt/qtbase`). Supera cómodo el `QT_MIN_VERSION` real
  que declara kwin (`6.10.0`, leído directo de su `CMakeLists.txt` real).
  Mismo criterio de "vanguardia" que el resto del proyecto: última versión
  real, no el piso mínimo de un consumidor.
- **KDE Frameworks 6 + tren de Plasma en 6.29.0** — el `KF6_MIN_VERSION` real
  que declaran kwin (`6.27.0`) y plasma-workspace (`6.26.0`) en sus propios
  `CMakeLists.txt`; se fija el tren completo en `6.29.0`, el último
  REALMENTE PUBLICADO en `download.kde.org/stable/frameworks/` (confirmado
  en vivo listando ese directorio — la rama `master` de los repos
  individuales ya apunta a `6.30.0` sin publicar todavía, no sirve como
  fuente de versión real).
- **XWayland/X11: sacado por completo, Wayland puro.** No es una preferencia
  técnica improvisada de esta sesión — el propio documento fundacional del
  proyecto (`docs/LINSI-OS.pdf`, Pilar 5 "Vanguardia", sección 2.5) lo dice
  explícito: *"en lugar de mantener compatibilidad con X11 ... LINSI-OS se
  construye exclusivamente sobre Wayland"*, y la sección 6 ("Originalidad")
  lo repite: *"sin arrastrar compatibilidad con X11 ni PulseAudio"*. kwin
  trae XWayland/X11 prendido por defecto (`KWIN_BUILD_X11=ON` en su
  `CMakeLists.txt` real) — cuando se llegue a `step_kwin()`, va con
  `KWIN_BUILD_X11=OFF` a propósito, sin libxcb/Xwayland en el sysroot.
- **Alcance: todo desde el principio.** A diferencia del criterio "mínimo
  primero" usado en Mesa (VA-API/glvnd/NVK afuera a propósito), acá se pidió
  explícitamente el desktop completo desde el arranque — incluidas las
  piezas que el `CMakeLists.txt` real de plasma-workspace no marca
  `REQUIRED` (Baloo, NetworkManagerQt, PackageKitQt6, AppStreamQt,
  KIOExtras/KIOFuse).

### Mapa de dependencias confirmado (no inventado — contra los
`find_package()` reales de `kwin` y `plasma-workspace`, bajados de
`invent.kde.org`)

El detalle completo, con las citas de línea de cada `find_package()`, vive
en el header de `scripts/build-kde.sh` (nuevo script de esta parte, mismo
patrón autocontenido que `build-mesa.sh` — no sourcea otros scripts de
fase). Resumen por tier:

- **Tier 0 — build tooling:** `cmake >= 3.29` (bloqueante real: el cmake de
  apt del Dockerfile es 3.25.1, `extra-cmake-modules` exige 3.29 en su
  propio `CMakeLists.txt` — resuelto con `pip3 install cmake>=3.29`, mismo
  criterio ya usado para meson/Rust) + `extra-cmake-modules` (ECM) en sí
  (sólo módulos `.cmake`, `LANGUAGES NONE`, nada que cross-compilar). **✅
  Compilado, instalado y verificado — primer intento, sin errores reales**
  (`logs/20260904-115956_build-kde_ecm.log` /
  `logs/20260904-120013_build-kde_verify-ecm.log`).
- **Tier 1 — Qt6 (CMake):** `qtbase`, `qtshadertools`, `qtdeclarative`,
  `qtsvg`, `qt5compat`, `qttools`, `qtwayland`. Necesita un Qt NATIVO aparte
  para cross-compilar (moc/rcc/qmlcachegen tienen que correr en el
  contenedor de build) — mismo patrón "herramienta nativa aparte" ya
  resuelto 4 veces en Fase 6 Parte 2 (mesa_clc/llvm-config/wayland-scanner/
  glslangValidator), pero ésta es la pieza completa más delicada de Parte
  3. **Sin empezar — research propio pendiente antes del primer
  `step_qtbase_native()`.**
- **Tier 2 — KDE Frameworks 6 (KF6 ≥ 6.27.0):** Auth, ColorScheme, Config,
  CoreAddons, Crash, DBusAddons, GlobalAccel, GuiAddons, I18n, IdleTime,
  Package, Service, Svg, WidgetsAddons, WindowSystem, Declarative,
  KCMUtils, NewStuff, XmlGui, Runner, DocTools, NetworkManagerQt,
  QuickCharts, UserFeedback, Baloo. Lista de componentes CONFIRMADA contra
  los `find_package(KF6 ... COMPONENTS)` reales de kwin/plasma-workspace —
  sus propias dependencias transitivas (KNewStuff en particular arrastra
  KIO/Attica, bastante pesado) se descubren building, mismo método que ya
  funcionó en Mesa. **Sin empezar.**
- **Tier 3 — "tren de Plasma" (versionado junto a Plasma, no Frameworks):**
  Plasma (libplasma), PlasmaQuick, KWayland (la de KDE, distinta de
  `Qt6WaylandClient`), PlasmaActivities(+Stats), KSysGuard, KF6Screen,
  LayerShellQt, KF6Kirigami+KF6KirigamiAddons, KNightTime, KDecoration3,
  Breeze/Aurorae, Union, KWinDBusInterface, ScreenSaverDBusInterface,
  PlasmaWaylandProtocols (protocolos XML propios de KDE, mismo patrón
  wayland-scanner que wayland-protocols de Fase 6 Parte 1). **Sin
  empezar.**
- **Tier 4 — terceros nuevos** (nada de esto compilado en el proyecto
  todavía): QCoro6, ICU, libcanberra, libei, lcms2, hwdata,
  AccountsService, AppStreamQt, PolkitQt6-1, QAccessibilityClient6,
  PackageKitQt6, KExiv2Qt6, KIOExtras, KIOFuse. **Sin empezar.**
- **Tier 5 — kwin y plasma-workspace en sí** (con `KWIN_BUILD_X11=OFF`).
  **Sin empezar.**

### Tier 1 (Qt6) — primeros pasos reales (2026-09-04)

- **`step_qtbase_native()` escrito y corrido — ✅ completo y verificado**
  (`logs/20260904-121946_build-kde_qtbase-native.log` tras el fix,
  `logs/20260904-122156_build-kde_verify-qtbase-native.log`). Primer build
  NATIVO de Qt6 de todo el proyecto (mismo patrón "herramienta nativa
  aparte" ya usado 4+ veces en Mesa, acá aplicado a Qt entero por primera
  vez) — produce `moc`/`rcc`/`uic` + el paquete `Qt6CoreTools` que el build
  CRUZADO va a necesitar vía `-DQT_HOST_PATH`.
  - **Primer error real:** `ERROR: The OpenGL functionality tests failed!`
    — CMake Error duro (no auto-disable), porque el contenedor no tiene
    ningún dev package de OpenGL a nivel host (a propósito, este proyecto
    nunca quiso GL del lado del contenedor). Confirmado contra
    `src/gui/configure.cmake` real de qtbase 6.11.2: `opengl` depende de
    `opengl_desktop`/`opengl_dynamic`/`opengles2`, controlados por el
    switch documentado `INPUT_opengl` (equivalente CMake de
    `./configure -opengl no` de qmake clásico). **Fix:**
    `-DINPUT_opengl=no` — esta build nativa sólo importa por sus binarios
    de herramientas, nunca renderiza nada.
  - **Segundo hallazgo (falso negativo del propio verify, no un error de
    build):** `step_verify_qtbase_native()` buscaba `moc`/`rcc`/`uic` en
    `bin/`, pero Qt6 los instala en `libexec/` (confirmado en la corrida
    real: `find` sobre el prefix nativo) — Qt6 separa binarios de cara al
    usuario final (`bin/`) de herramientas de desarrollo "privadas"
    (`libexec/`), y acá no hay ningún binario del primer tipo. **Fix:**
    corregidas las tres rutas del verify.
- **`step_qtshadertools_native()` escrito y corrido — ✅ completo y
  verificado, sin errores reales de build** (compiló limpio al primer
  intento: `qsb`, `libQt6ShaderTools.so`, `Qt6ShaderToolsTools` — mismo
  prefix compartido `QT6_NATIVE_INSTALL`, vía `CMAKE_PREFIX_PATH` para
  encontrar el `qtbase-native` recién instalado). Único ajuste necesario fue
  al propio verify: `qsb` queda en `bin/` (no en `libexec/` como
  moc/rcc/uic) — confirmado en la instalación real, corregido antes de
  correr el verify por primera vez (no hizo falta un segundo intento
  fallido).
- **`step_qtdeclarative_native()` escrito y corrido — ✅ completo y
  verificado, sin errores reales de build** (compiló limpio, más grande que
  los dos anteriores — motor QML completo con Quick Controls/Labs/
  QmlCompiler/etc. como submódulos internos, tardó más de 590s — corrió en
  background y terminó con exit code 0). `qmlcachegen`/`qmltyperegistrar`
  confirmados en `libexec/` + `Qt6QmlTools` instalado.
  (`logs/20260904-124201_build-kde_verify-qtdeclarative-native.log`).
- **Resuelto: NO hace falta un `qtwayland-native` aparte.** El
  `qtwaylandscanner` (el scanner de protocolos que necesitaría un
  `qtwayland-native`) YA quedó instalado como parte de `qtbase-native`
  (`libexec/qtwaylandscanner` + el paquete `Qt6WaylandScannerTools` con sus
  macros) — confirmado con un `find` real sobre el prefix nativo, Qt6
  aparentemente empaquetó esta herramienta dentro de qtbase mismo en vez de
  en el módulo qtwayland separado. **Con esto, el bootstrap NATIVO de Qt6
  para este proyecto queda completo con sólo 3 módulos** (qtbase,
  qtshadertools, qtdeclarative) — no hacen falta versiones nativas de
  qtsvg/qt5compat/qttools/qtwayland (ninguno de esos aporta herramientas de
  build-time que otro módulo necesite, a diferencia de los tres ya
  compilados).
- **`step_qtbase()` (build CRUZADO real) escrito y corrido — ✅ completo y
  verificado.** Usa `write_cmake_toolchain()` + `-DQT_HOST_PATH=
  "${QT6_NATIVE_INSTALL}"` (mecanismo real de `qtbase/cmake/README.md`) para
  encontrar moc/rcc/uic/qsb/qmlcachegen/qtwaylandscanner de los 3 pasos
  nativos. Confirmado en el sysroot: `libQt6Core.so`, `libQt6Gui.so`,
  `libQt6Widgets.so`, `libQt6DBus.so`, `Qt6Config.cmake`
  (`logs/20260904-125659_build-kde_verify-qtbase.log`).
  - **Primer error real:** `Feature "opengl_desktop": Forcing to "ON" breaks
    its condition ... WrapOpenGL_FOUND = "FALSE"`. La configuración inicial
    usaba `-DINPUT_opengl=desktop`, asumiendo que como Mesa (Fase 6 Parte 2)
    da Gallium/OpenGL completo para las 3 GPU del lab, correspondía el GL de
    escritorio clásico. **Causa raíz, confirmada con un `find` real sobre el
    sysroot:** Mesa nunca generó `libGL.so` — sólo `libGLESv2.so`/
    `libGLESv1_CM.so`. El motivo es coherente con decisiones ya tomadas en
    Fase 6 Parte 2: `build-mesa.sh` compila con `-Dplatforms=wayland`, sin
    `-Dglx` ni glvnd, y el `libGL.so` clásico está atado a GLX/al dispatch
    multi-vendor (glvnd) — ninguno de los dos está en este proyecto (el
    header `GL/gl.h` sí se instala igual, pero eso no alcanza para
    `find_library(GL)`). **Fix:** `-DINPUT_opengl=es2` — usa `libGLESv2.so`
    (que sí existe) vía contexto EGL, el camino estándar que el propio Qt
    documenta para setups Wayland-only sin GLX
    (`doc.qt.io/qt-6/embedded-linux.html`, EGLFS/GLESv2).
  - **Hallazgo importante para el resto de Tier 1:** qtbase por sí solo YA
    instaló `Qt6WaylandClient` + `Qt6WaylandClientPlugins.cmake` +
    `Qt6WlShellIntegrationPrivate` — el plugin QPA de Wayland (el que
    permite a cualquier app Qt renderizar como cliente Wayland) parece venir
    integrado adentro de qtbase mismo en esta versión, no exclusivamente del
    módulo `qtwayland` separado. Sin confirmar todavía qué le falta al
    módulo `qtwayland` en sí (probablemente `QtWaylandCompositor`, la
    librería que un compositor como kwin necesita para el lado SERVIDOR del
    protocolo, distinta del lado cliente que ya quedó cubierto acá) — se
    confirma cuando se llegue a ese paso.
- **`step_qtshadertools()` (CRUZADO) escrito y corrido — ✅ completo y
  verificado, sin errores reales.** `libQt6ShaderTools.so` confirmado en el
  sysroot (`logs/20260904-131126_build-kde_verify-qtshadertools.log`). A
  diferencia del build nativo, este cruzado no instaló un binario `qsb`
  cruzado (sólo la librería) — no bloqueante, nada de lo compilado hasta
  ahora lo necesita.
- **`step_qtdeclarative()` (CRUZADO) escrito y corrido — ✅ completo y
  verificado, sin errores reales.** El módulo más grande de Tier 1 (motor
  QML/Quick + QuickControls2/Labs/QmlCompiler completos), corrió en
  background por superar el timeout de una sesión interactiva normal — exit
  code 0, `libQt6Qml.so`/`libQt6Quick.so` confirmados
  (`logs/20260904-132952_build-kde_verify-qtdeclarative.log`).
- **Con esto, los 3 módulos Qt6 más delicados de Tier 1 (qtbase/
  qtshadertools/qtdeclarative) están completos tanto nativos como cruzados,
  sin ningún error real en el lado cruzado más allá del fix de
  `INPUT_opengl` en qtbase.**
- **`step_qtsvg()`, `step_qt5compat()` (CRUZADOS) — ✅ completos y
  verificados, sin ningún error real** (`libQt6Svg.so`/
  `libQt6Core5Compat.so` confirmados).
- **`step_qttools()` — necesitó un `qttools-native` que el mapa original NO
  había anticipado.** Primer intento del build CRUZADO falló en el
  configure: `Failed to find the host tool "Qt6::lconvert". It is part of
  the Qt6LinguistTools package`. A diferencia del resto de Tier 1 (donde el
  build nativo sólo hacía falta si OTRO módulo consumía sus herramientas),
  acá lo que pasa es que el propio módulo qttools invoca `lconvert`
  internamente durante SU PROPIO build cruzado — mismo patrón de fondo que
  moc/rcc/qsb/qmlcachegen, sólo que el consumidor es el mismo módulo. Se
  agregó `step_qttools_native()` (mismo prefix compartido
  `QT6_NATIVE_INSTALL`) y con eso el build cruzado terminó limpio.
  `libQt6UiTools.so` (el componente que kwin pide explícito) confirmado.
- **`step_qtwayland()` (CRUZADO) — ✅ completo y verificado, sin errores
  reales.** `libQt6WaylandCompositor.so` confirmado — la pieza que faltaba
  después de que qtbase ya trajera integrado el lado cliente
  (`Qt6WaylandClient`).
- **Tier 1 (Qt6) queda COMPLETO** — los 7 módulos (qtbase, qtshadertools,
  qtdeclarative, qtsvg, qt5compat, qttools, qtwayland) compilados,
  instalados y verificados en el sysroot, tanto en su forma nativa (donde
  hacía falta: qtbase/qtshadertools/qtdeclarative/qttools) como cruzada.
  Sigue Tier 2 (KDE Frameworks 6), que recién empieza con ECM ya en el
  sysroot desde Tier 0.

  **Nota aparte, incidente de infraestructura real durante este tramo (no
  un bug de build):** en medio de `qttools`, el disco C: de Windows llegó a
  0 bytes libres, lo que causó errores de compilación reales pero
  engañosos ("Bus error" / "Input/output error" en `/tmp`) y terminó
  corrompiendo el filesystem de la VM de Podman. Recuperado sin pérdida de
  datos liberando espacio (papelera de reciclaje) — detalle completo en la
  sección "Infraestructura — incidente real de disco" más arriba en este
  mismo archivo. Mudar la VM a D: quedó pospuesto a propósito para cuando
  haya tiempo de hacerlo con cuidado.

### Sub-sección: prerequisito de xkbregistry (completo y confirmado
2026-09-04)

- **Parte 3 — Qt6 + KDE Frameworks/kwin/plasma-workspace + tema oscuro/Nerd
  Fonts desde `/etc/skel/`:** todavía no arrancó (Qt6/KDE en sí), depende de
  la Parte 2 (ya completa, ver más arriba). El prerequisito ya identificado
  acá abajo desde antes (libxml2 + reactivar `-Denable-xkbregistry=true`)
  quedó **escrito, sin correr todavía** (2026-09-04):
  - **`step_libxml2()` nuevo en `build-desktop.sh`** (targets `libxml2` /
    `verify-libxml2`, numerado "18b" a propósito, entre libinput y
    libxkbcommon, sin renumerar el resto): libxml2 2.15.3 cross-compilado
    con Meson (confirmado contra el `meson.build` real de
    `GNOME/libxml2` tag `v2.15.3` que esta versión sí tiene build de Meson,
    no hace falta autotools) — `-Dpython=disabled` (no cross-compilamos
    Python, nadie en el proyecto usa los bindings) y `-Ddocs=disabled`
    (sin xsltproc/docbook en el Dockerfile). Produce `libxml2.so` +
    `libxml-2.0.pc` (confirmado el `filebase: 'libxml-2.0'` real del
    `pkgmod.generate()`) + headers en
    `${LFS_SYSROOT}/usr/include/libxml2/libxml/`.
  - **`step_libxkbcommon()` actualizado:** ahora exige `libxml-2.0.pc` en el
    sysroot antes de correr, y `-Denable-xkbregistry=false` pasó a `true` —
    produce además `libxkbregistry.so` + `xkbregistry.pc` (confirmado contra
    el `meson.build` real de libxkbcommon 1.13.2: `get_option(
    'enable-xkbregistry')`, `filebase: 'xkbregistry'`). `step_verify_libxkbcommon()`
    actualizado para chequear los dos artefactos nuevos, no sólo
    `libxkbcommon.so`.
  - Versión/mirror agregados a `env.sh`: `LIBXML2_VERSION="2.15.3"` (tag real
    `v2.15.3` de `GNOME/libxml2`, sha256 real confirmado bajando el tarball:
    `5c6060277173270356c3f1c321a640ab629bdabc5e5ba9095b99e00759ba0c39`,
    extrae a `libxml2-2.15.3/` con el "v" pisado por GitHub, patrón normal
    para este proyecto).
  - **Validado con `bash -n` (limpio) sobre `build-desktop.sh` y `env.sh`.**
    `shellcheck` sigue sin estar disponible en este entorno de trabajo (ni
    host Windows ni `Dockerfile` del proyecto) — mismo aviso que el
    Vigésimo cuarto error real de Fase 6 Parte 2, no se repite acá para no
    dar por hecha una validación que no se hizo.
  - **Corrido y confirmado el mismo día (2026-09-04), sin ningún error real
    en ninguno de los dos pasos** — a diferencia del patrón habitual de este
    proyecto (algo tira al menos un error real la primera vez), acá
    `libxml2` compiló limpio al primer intento
    (`logs/20260904-114350_build-desktop_libxml2.log`) y la recompilación de
    `libxkbcommon` con `-Denable-xkbregistry=true` también
    (`logs/20260904-114429_build-desktop_libxkbcommon.log`). Los cuatro
    targets nuevos/tocados confirmados en verde:
    ```
    [OK] /lfs/usr/lib/libxml2.so
    [OK] /lfs/usr/lib/pkgconfig/libxml-2.0.pc
    [OK] /lfs/usr/include/libxml2/libxml/parser.h
    [OK] /lfs/usr/lib/libxkbcommon.so
    [OK] /lfs/usr/lib/libxkbregistry.so
    [OK] /lfs/usr/lib/pkgconfig/xkbregistry.pc
    ```
  - Después de esto, recién empieza el trabajo nuevo de verdad de Parte 3:
    Qt6 (QtBase mínimo compilado sólo contra Wayland, sin X11/xcb) y, sobre
    él, KDE Frameworks/kwin/plasma-workspace. Todavía no investigado en
    profundidad — va a necesitar su propio research de opciones de build
    antes de escribir nada, mismo criterio que se usó para Mesa.

## Infraestructura de build

- **BUG REAL CRÍTICO encontrado y corregido (2026-10-22): el sysroot no
  tenía el runtime de C++/GCC — ningún programa C++ del sistema hubiera
  arrancado.** Apareció al recompilar libxkbcommon: dos binarios suyos
  fallaron al linkear contra `libicuuc.so` con `undefined reference to
  __gxx_personality_v0@CXXABI_1.3` — el linker no encontraba la libstdc++
  que `libicuuc.so` pide como NEEDED. Un chequeo de clausura (cada NEEDED
  de cada ELF del sysroot tiene que existir en el sysroot) confirmó:
  `libstdc++.so.6` faltaba para **848 binarios**, `libgcc_s.so.1` para
  **845** y `libgomp.so.1` para 30. Todo lo demás resolvía.
  - **Causa raíz de libstdc++ (confirmada en el log real de Fase 2,
    `logs/20260902-041334_build-userspace_all.log`):** `step_libstdcxx` sí
    la instalaba, pero en `/lfs/usr/lib/../lib64` — su configure le
    pregunta el directorio al cross-gcc con `-print-multi-os-directory`,
    que devuelve `../lib64` (toolchain multilib). Y ese `lib64` lo borraban
    ENTERO dos `rm -rf "${LFS_SYSROOT}/usr/lib64"` puestos "por las dudas"
    para limpiar restos de OpenSSL (`build-comms.sh`, Fase 4) y de libffi
    (`build-desktop.sh`, Fase 6 P1). El verify de Fase 2 nunca lo vio:
    `g++` linkea contra la libstdc++ del **toolchain**
    (`/lfs/tools/x86_64-linsi-linux-gnu/lib64`), no la del sysroot.
  - **libgcc_s/libgomp nunca llegaron:** GCC pass 2 se instala con
    `--prefix=${LFS_TOOLS}`, así que sus librerías de runtime del target
    sólo existían en el toolchain.
  - **Fix:** paso nuevo `gcc-runtime` en `build-userspace.sh` (después de
    `gcc2`) que copia las versiones FINALES de `libstdc++.so.6`,
    `libgcc_s.so.1` y `libgomp.so.1` (las que compila GCC pass 2) del
    toolchain a `/usr/lib`, junto a glibc, y borra la libstdc++ de
    bootstrap de `/usr/lib64` para que no queden dos copias. Se sacaron los
    dos `rm -rf lib64` (los `--libdir`/`--disable-multi-os-directory` de
    OpenSSL y libffi ya evitan que caigan ahí).
  - **Primer intento descartado:** pasarle `--with-toolexeclibdir=/usr/lib`
    a `step_libstdcxx` y recompilarla. Falló (`tzdb.cc: 'mutex' does not
    name a type`) porque ese paso es la libstdc++ de BOOTSTRAP, pensada
    para el GCC pass1; recompilarla hoy, con pass 2 en el toolchain, no es
    su condición original. Además la libstdc++ final ya existía (la de
    pass 2) — se volvió `step_libstdcxx` a su versión validada.
- **Rutas del sysroot compiladas en binarios (2026-10-22).** Escaneando la
  sección `.rodata` de los 1944 ELF del sysroot aparecieron rutas con
  `/lfs` que en el sistema real no existen — misma causa raíz que
  `/lfs/lfs` (variables de pkg-config que vuelven con el sysroot adentro, o
  `AC_PATH_TOOL` encontrando binarios del sysroot por el PATH que arma
  `env.sh`), pero acá quedan COMPILADAS, no en una ruta de instalación:
  - **libxkbcommon/libxkbregistry** (`/lfs/usr/share/X11/xkb`,
    `/lfs/usr/share/xkeyboard-config-2`): en el sistema real no hubiera
    cargado NINGÚN layout de teclado (kwin depende de esto). Fix: bloque en
    su `meson.build` que le saca el `sys_root` a las cuatro rutas antes de
    usarlas (la raíz "legacy" no tiene opción de override).
  - **kded6** (`/lfs/usr/lib/libexec/kf6/kconf_update`, vía
    `$<TARGET_FILE:KF6::kconf_update>`): no hubiera migrado configuración
    de usuario. Fix: `${KDE_INSTALL_FULL_LIBEXECDIR_KF}/kconf_update`.
  - **ki18n** (`ISO_CODES_PREFIX "/lfs/usr"`, de `FindIsoCodes` de ECM):
    sin nombres de países/regiones. Fix: se le saca el prefijo del sysroot
    a `IsoCodes_PREFIX` después del `find_package`.
  - **LVM2** (regla udev `69-dm-lvm.rules` llamando a
    `/lfs/usr/bin/systemd-run`): la autoactivación de LVM hubiera fallado.
    Fix: `--with-systemd-run=/usr/bin/systemd-run`.
  - Los hits restantes (`/lfs/usr/include/...` en wireplumber y
    QtQuickTest) son `__FILE__` en mensajes de diagnóstico: inofensivos.
- **`scripts/check-sysroot.sh` (nuevo):** corre los dos chequeos (clausura de
  librerías + rutas `/lfs` en `.rodata` y en archivos de runtime) sobre
  todo el sysroot y sale con error si encuentra algo. Conviene correrlo
  después de cualquier tanda de builds — los verifies por paso no ven
  ninguno de estos dos problemas.
- **Pendiente para Fase 8 (anotado, no se puede arreglar en el sysroot):**
  todos los ELF piden como intérprete `/lib64/ld-linux-x86-64.so.2`, pero
  en el sysroot el loader está en `/usr/lib/ld-linux-x86-64.so.2` y no
  existen `/lib64`, `/lib`, `/bin` ni `/sbin` (fuera de `/lfs/usr`, `/lfs/etc`
  y `/lfs/boot` nada persiste entre corridas). El rootfs de la imagen final
  tiene que crear los symlinks "usrmerge" (`/lib64 -> usr/lib`, `/lib ->
  usr/lib`, `/bin -> usr/bin`, `/sbin -> usr/bin`) — sin `/lib64` no
  arranca NINGÚN binario dinámico. Lo mismo para `/etc/os-release`, que no
  existe en el sysroot (plasma-login-manager lo leía para elegir su
  plantilla PAM).

- **BUG REAL GRAVE encontrado y resuelto (2026-09-30): `/lfs/etc` nunca tuvo
  volumen persistente — cualquier config real se perdía entre corridas
  separadas de `podman-compose run --rm`.** Descubierto al retomar Fase 5
  (confirmar `build-infra.sh` por primera vez): `step_apk_signing()` escribía
  la llave pública + `repositories` en `${LFS_SYSROOT}/etc/apk/...`, el verify
  de ESA MISMA corrida daba bien, pero un `find` real en un contenedor NUEVO
  confirmó que `/lfs/etc` no existía en absoluto. Revisando
  [`docker-compose.yml`](../docker-compose.yml): los únicos volúmenes
  persistentes eran `linsios-tools:/lfs/tools`, `linsios-build:/lfs/build`,
  `linsios-sysroot:/lfs/usr` y `linsios-boot:/lfs/boot` — `/lfs/etc` vivía en
  el filesystem efímero del contenedor y se borraba en cada `--rm`. Mismo
  patrón ya conocido ("el filesystem del contenedor `--rm` es efímero") pero
  nunca antes detectado para `/etc` porque nadie había confirmado su
  contenido en una corrida nueva hasta ahora.
  - **Alcance real confirmado con `grep` sobre todos los scripts de fase:**
    afectaba `build-comms.sh` (Fase 4 — PAM: `/etc/pam.d/*`,
    `/etc/security/faillock.conf`; DNS-over-TLS: `/etc/systemd/resolved.conf`)
    y varios pasos de Fase 6 Parte 1 cuyos propios `ninja install` depositan
    configs reales en `/etc` (dbus: `/etc/dbus-1/{system,session}.conf`;
    fontconfig: `/etc/fonts/fonts.conf` + 23 symlinks en `/etc/fonts/conf.d`;
    pipewire: `/etc/security/limits.d/25-pw-rlimits.conf`; polkit:
    `/etc/polkit-1/rules.d`) además de Fase 5 (`apk-signing`). Es decir: Fase
    4 y Fase 6 Parte 1, ambas dadas por "✅ completas" hace semanas, nunca
    habían dejado ese contenido persistido de verdad entre corridas
    separadas.
  - **Fix real:** agregado el volumen `linsios-etc:/lfs/etc` a
    `docker-compose.yml` (mismo patrón que `linsios-sysroot`/`linsios-boot`).
    Como los build-dirs de dbus/fontconfig/pipewire/polkit seguían intactos
    en el volumen persistente `/lfs/build` (nunca se habían borrado), no hizo
    falta recompilar nada — alcanzó con re-correr `pam-config`/
    `network-config` (Fase 4, instantáneo, sólo escriben archivos) y
    `DESTDIR=/lfs ninja -C <bdir> install` sobre los build-dirs ya existentes
    de dbus/fontconfig/pipewire (Fase 6 Parte 1). `build-infra.sh all` (Fase
    5) se re-corrió completo.
  - **Confirmado en un contenedor NUEVO (la prueba real):** `find /lfs/etc
    -type f` lista los 12 archivos esperados (apk/keys, apk/repositories,
    dbus-1, fonts, pam.d×4, security×2, systemd/resolved.conf) + 23 symlinks
    de fontconfig, y sobreviven a una corrida posterior.
- **BUG REAL #2, encontrado reinstalando lo anterior: unidades systemd de
  dbus/polkit/pipewire/wireplumber duplicaban el sysroot en la ruta
  (`/lfs/lfs/usr/lib/systemd/...` en vez de `/lfs/usr/lib/systemd/...`).**
  Confirmado que esto YA pasaba en los logs originales de Fase 6 Parte 1
  (`logs/20260829-*.log`) — no es algo nuevo, viene de semanas atrás sin que
  nadie lo notara (ningún verify de esas fases chequea contenido de unidades
  systemd). **Causa raíz real:** `systemd.pc` define
  `systemdsystemunitdir`/`systemduserunitdir` en relativo
  (`${prefix}/lib/systemd/system` → `/usr/lib/systemd/system`, confirmado
  leyendo el `.pc` real instalado). El problema es la combinación de DOS
  mecanismos de apuntar al sysroot que no deberían mezclarse para esta
  variable puntual: `PKG_CONFIG_SYSROOT_DIR="${LFS_SYSROOT}"` (necesario para
  que OTRAS dependencias como glib resuelvan Cflags/Libs contra el sysroot)
  ya reescribe esta variable custom a una ruta absoluta con el sysroot
  adentro en tiempo de `meson setup` (queda horneada así en `build.ninja`), y
  después `DESTDIR="${LFS_SYSROOT}" ninja install` vuelve a prepender el
  sysroot sobre esa ruta YA absoluta — de ahí el doble.
  - **Fix real por paquete** (los 4 confirman compilando limpio y con rutas
    correctas en un contenedor nuevo):
    - **dbus**: opción real `-Dsystemd_system_unitdir=`/
      `-Dsystemd_user_unitdir=` (con guion bajo entre "systemd" y "system").
      Un intento anterior (2026-08-27) había probado
      `-Dsystemdsystemunitdir=` (SIN el primer guion bajo) y, al fallar con
      "Unknown option", concluyó — incorrecto — que dbus no tenía ningún
      override. Sí lo tiene, con otro nombre exacto.
    - **polkit**: opción real `-Dsystemdsystemunitdir=` (sin ningún guion
      bajo, a diferencia de dbus). Pero **`sysusers_dir`/`tmpfiles_dir` NO
      tienen ninguna opción de override** (confirmado leyendo el
      `meson_options.txt` real) — para esos dos archivos
      (`polkit.conf`/`polkit-tmpfiles.conf`) no quedó otra que corregir la
      ruta a mano con un `mv` post-install dentro de `step_polkit()`.
    - **pipewire** y **wireplumber**: opción real
      `-Dsystemd-system-unit-dir=`/`-Dsystemd-user-unit-dir=` (con guiones,
      no guión bajo).
  - Los 4 `step_*()` en `scripts/build-desktop.sh` quedaron actualizados con
    la opción real correspondiente (+ el `mv` puntual en polkit), cada uno
    documentado inline con la causa raíz real.
- **Docker Desktop reemplazado por `podman-compose`** (2026-08-29) — Docker
  Desktop no arrancaba en tu máquina, así que se sacó la dependencia por
  completo. De acá en más usá `podman-compose` (con guion) para todo, no
  `docker-compose.exe` ni `podman compose` (sin guion).
- **Versionado con git inicializado recién ahora (2026-09-01)** — hasta este
  punto todo el trabajo (Fases 0 a 6 Parte 2, con todos los fixes de Mesa
  incluidos) se venía escribiendo directo en tu carpeta sin ningún repo git
  atrás — ni un commit. Se armó recién: `git init -b main`, un `.gitignore`
  que excluye `sources/` (~765MB de tarballs de upstream, se re-descargan
  solos con `fetch()`) y `logs/`/`*.log` (se regeneran en cada build), y un
  commit inicial (`ff27b17`) con las 23 fuentes reales del proyecto
  (Dockerfile, docker-compose.yml, todos los scripts de fase, env.sh,
  este mismo archivo, los READMEs de fase y el workflow de `.github`).
  El repo queda **local únicamente** — el push a GitHub lo hace Juani
  directamente, no yo. De acá en adelante, cada fix real de build (como los
  9 de Mesa+LLVM de esta sesión) debería ir en su propio commit chico en vez
  de acumularse todo suelto — así el historial queda útil para volver atrás
  si algo se rompe.

## Decisiones ya tomadas (no son deuda, quedan acá como referencia)

- **Empaquetado:** sysroot monolítico hasta el final de Fase 6. Recién en
  Fase 7/8 se arma `.apk` real por paquete.
- **CI/CD — respuesta pendiente que nunca te di:** "¿si te doy mi PC de
  escritorio [como runner self-hosted], tengo que tenerla prendida 24/7?" —
  No, no hace falta. Un runner self-hosted sólo necesita estar *online* en el
  momento en que querés que corra un job: si hacés push con la PC apagada, el
  job de GitHub Actions queda en cola esperando, sin fallar, hasta que
  prendas la PC y el servicio del runner se reconecte. La única desventaja es
  que no tenés feedback de CI hasta ese momento. (Esto sigue sin resolver la
  discusión de fondo: la Pi es ARM64 y el build es x86_64, así que un runner
  en la Pi necesitaría QEMU y sería mucho más lento — la PC de escritorio no
  tiene ese problema por ser la misma arquitectura.)
