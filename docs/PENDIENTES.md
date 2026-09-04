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

- **`build-infra.sh` (apk-tools + firma) nunca se confirmó.** Se entregó,
  `bash -n` limpio, pero no hay un log real ni un "listo" tuyo específico para
  este script. Puede haber corrido bien en algún momento sin que lo
  mencionaras — conviene correrlo (`scripts/build-infra.sh all`) y confirmar.
- **Raspberry Pi: `setup-repo-server.sh` sin confirmar ejecutado.** Te di la
  guía paso a paso por SSH, pero no hay confirmación de que hayas corrido el
  script en la Pi ni de que nginx haya quedado sirviendo en el puerto 8088.
- **Cloudflare Tunnel: `cloudflared-ingress-snippet.yml` sin confirmar
  mergeado.** No sé si ya agregaste esa regla a tu `config.yml` real del túnel
  ni si corriste `cloudflared tunnel route dns`.
- **Placeholder en `/etc/apk/repositories` dentro del sysroot.** Tiene un TODO
  con el hostname real pendiente — se actualiza recién cuando el repo de la Pi
  esté confirmado andando de verdad desde afuera (`curl -I
  https://tu-hostname/edge/main/x86_64/` devolviendo 200).
- **`.github/workflows/lint-scripts.yml` rechazado al escribir.** Las
  herramientas remotas no pueden tocar `.github/` (protección esperada) — te
  lo entregué en el chat, pendiente que lo copies vos a mano a
  `linsi-os\.github\workflows\lint-scripts.yml`.
- **CI/CD: pausado por decisión mutua, no resuelto.** Quedó sin definir qué
  runner usar (GitHub hosteado vs. self-hosted en tu PC o en la Pi). Ver la
  respuesta a tu pregunta de si hace falta tener la PC prendida 24/7, al final
  de este archivo.

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

## Fase 6 — Parte 2 (Mesa + LLVM, drivers gráficos) — 🟡 script escrito, SIN CORRER TODAVÍA (2026-08-29)

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

## Fase 6 — Parte 3 (no empezada)

- **Parte 3 — Qt6 + KDE Frameworks/kwin/plasma-workspace + tema oscuro/Nerd
  Fonts desde `/etc/skel/`:** no empezada, depende de la Parte 2. **Ya
  sabemos que va a necesitar libxml2** (ver más arriba, libxkbcommon
  compilado en Parte 1 sin xkbregistry por esto mismo) — cross-compilarlo y
  reactivar `-Denable-xkbregistry=true` en `step_libxkbcommon()` es un
  prerequisito de esta parte, no algo nuevo a descubrir ahí.

## Infraestructura de build

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
