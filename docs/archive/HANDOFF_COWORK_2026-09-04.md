> **Nota de archivo:** handoff generado el 2026-09-04 al final de una sesión
> de Claude Code corrida por el bridge de escritorio de Cowork (no esta
> misma sesión/entorno) — de ahí las convenciones de la sección 6-7 sobre
> `SendUserFile`/`device_bash`, que ya no aplican (esta sesión tiene acceso
> directo a filesystem/podman). Todo lo técnico que describe (Fase 6 Parte
> 2, Mesa+LLVM) está **completo y confirmado** desde entonces — ver
> `../PENDIENTES.md`. Se conserva sin modificar como registro histórico del
> estado exacto en el que quedó esa sesión.

# LINSI-OS — Contexto para continuar (Fase 6 Parte 2: Mesa + LLVM)

Este documento es un handoff completo para retomar el trabajo en otra sesión
de Claude Code. Está pensado para que quien lo lea no necesite el historial
de chat anterior — toda la info relevante está acá o referenciada al archivo
correcto del repo.

## Qué es este proyecto

**LINSI-OS**: distro Linux hardened, construida desde cero con metodología
LFS (Linux From Scratch), para el Laboratorio LINSI (UTN Facultad Regional
La Plata). Dueño del proyecto: Juan Ignacio Wilt ("Juani"). El repo vive en
`C:\Users\Juanii\Desktop\LINSIOS\linsi-os` (Windows), se compila dentro de
contenedores `podman-compose` (NO chroot), target `x86_64-linsi-linux-gnu`
(cross-compilación real: el "host" del build es una glibc/toolchain propia,
distinta de la del contenedor que hace de build machine).

Documento de arquitectura/visión completo: `docs/PENDIENTES.md` en el repo —
tiene TODO el historial de fases, decisiones y errores reales encontrados,
con causa raíz y fix para cada uno. **Leer ese archivo primero** si hace
falta más contexto de fases anteriores (0 a 5, Fase 6 Parte 1 completa).

## Estado actual: Fase 6 Parte 2 — Mesa + LLVM (drivers gráficos)

Script: `scripts/build-mesa.sh`. Hardware del laboratorio es mixto (Nvidia
RTX 3060, AMD RX 7700, Intel integrada) → drivers elegidos:
`gallium-drivers=iris,radeonsi,nouveau,llvmpipe`, `vulkan-drivers=amd,intel`
(no hay NVK estable en esta versión de Mesa, así que Nvidia queda sin
Vulkan nativo por ahora — limitación conocida de Mesa, no algo que falte
compilar).

### Último commit: `fc1c533` (rama `main`)

Los últimos commits, de más viejo a más nuevo, todos con mensaje
descriptivo + `Co-Authored-By: Claude Sonnet 5` + `Claude-Session`:

```
3882c16  mesa_clc/vtn_bindgen2 100% nativos via -Dmesa-clc=system (Vigesimo error real)
bc0bd04  agregar cd al source de Mesa antes de meson setup en mesa-clc-native
e09d85a  agregar include dirs de Clang al build mesa-clc-native (Vigesimo primer error real)
1270d9f  forzar bundling de headers OpenCL-C en mesa_clc nativo (Vigesimo segundo error real)
fc1c533  agregar target clang-resource-headers al build nativo de LLVM (Vigesimo tercer error real)
```

### El problema de fondo que se viene resolviendo (Vigésimo → Vigésimo tercero)

Mesa, al compilar con Intel/AMD reales habilitados, necesita compilar
`mesa_clc` (compilador interno de OpenCL-C a SPIR-V, usado en tiempo de
build por Mesa mismo para pre-compilar shaders internos como
`blorp_shaders.cl`). El primer intento (Décimo noveno) fue forzar
`native:true` a mano en el `meson.build` de Mesa — funcionó a medias pero
generó un error de "mezcla de contextos" de Meson imposible de resolver
parcheando el archivo (ver Vigésimo error real en `PENDIENTES.md` para el
diagnóstico completo).

**La solución real y definitiva** (siguiendo la receta oficial de Mesa para
este escenario, `docs.mesa3d.org/android.html`): compilar `mesa_clc` +
`vtn_bindgen2` en un build de Mesa **completamente aparte, 100% nativo, sin
drivers** (`step_mesa_clc_native()`, nuevo target `mesa-clc-native`), y
pasarle esos binarios ya compilados al build cruzado real vía
`-Dmesa-clc=system` + `--native-file`. Esto agregó 3 steps nuevos al script:

- `spirv-tools-native` — SPIRV-Tools compilado nativo (sin `--cross-file`)
- `spirv-llvm-translator-native` — SPIRV-LLVM-Translator compilado nativo
- `mesa-clc-native` — el build de Mesa aparte que produce los binarios

Cada uno de estos, al correr por primera vez de verdad, destapó un error
puntual más (normal en LFS — no es que el enfoque esté mal, es que cada
corrida real llega más lejos y encuentra el siguiente gap concreto):

1. **Vigésimo primero**: faltaban las rutas de include de Clang
   (`clc_helpers.cpp` no encontraba `clang/Config/config.h`) — Mesa resuelve
   `dep_clang` con un `find_library()` puro que no aporta `-I`, a diferencia
   de `dep_llvm`. Fix: `CFLAGS`/`CXXFLAGS` con `-isystem` a mano en el
   `meson setup` de `mesa-clc-native`.
2. **Vigésimo segundo**: con eso ya andando, `mesa_clc` compiló y el build
   cruzado real lo INVOCÓ de verdad (llegó a 1366/2872 targets, compilando
   `blorp_shaders.cl`) — pero `mesa_clc` no encontraba `opencl-c-base.h` en
   tiempo de ejecución (busca ese header por ruta relativa a
   `LLVM_LIB_DIR/clang/<version>/include/`, algo que nunca se generó). Fix:
   `-Dmesa-clc-bundle-headers=enabled` — empaqueta los headers DENTRO del
   binario en vez de buscarlos en disco.
3. **Vigésimo tercero** (el más reciente, recién commiteado): el fix
   anterior movió el mismo problema de "el directorio no existe" de tiempo
   de EJECUCIÓN a tiempo de CONFIGURE de Meson (necesita leer el archivo
   para empaquetarlo). La causa real: `step_llvm_native()` nunca generaba
   `lib/clang/<version>/include/` porque le faltaba pedir el target de
   CMake `clang-resource-headers` (confirmado contra
   `clang/lib/Headers/CMakeLists.txt` real de `llvm-project`). Fix: agregado
   ese target a la lista de `ninja` en `step_llvm_native()`.

### Próximo paso inmediato (nunca ejecutado todavía — el Vigésimo tercer fix es nuevo)

Como el último fix tocó `step_llvm_native()`, hay que rehacerlo primero
(rápido, no recompila LLVM entero — solo el target nuevo). Comandos en
orden exacto:

```powershell
podman-compose run --rm builder scripts/build-mesa.sh llvm-native
podman-compose run --rm builder scripts/build-mesa.sh mesa-clc-native
podman-compose run --rm builder scripts/build-mesa.sh mesa
podman-compose run --rm builder scripts/build-mesa.sh verify-mesa
```

`spirv-tools-native` y `spirv-llvm-translator-native` YA están hechos, no
hace falta repetirlos (a menos que algo los invalide).

Si `mesa` corre completo, `verify-mesa` debería mostrar `[OK]` en:
`iris_dri.so`, `radeonsi_dri.so`, `nouveau_dri.so`, `swrast_dri.so`,
`libvulkan_radeon.so`, `libvulkan_intel.so`, `libEGL.so`. Si eso pasa,
Fase 6 Parte 2 queda completa (falta solo Qt6/KDE, Fase 6 Parte 3, sin
empezar).

## Convenciones de trabajo de este proyecto (importantes, no te las saltees)

1. **Nunca inventar un fix.** Antes de tocar `scripts/build-mesa.sh` para un
   error nuevo, investigar la fuente REAL del proyecto de turno (Mesa,
   LLVM, etc.) vía WebFetch/WebSearch contra mirrors de GitHub —
   `gitlab.freedesktop.org` está bloqueado por robots.txt en sandboxes de
   Claude, usar `https://raw.githubusercontent.com/mirror/mesa/main/...` o
   `https://raw.githubusercontent.com/llvm/llvm-project/main/...`. Citar el
   archivo/línea real en el comentario del fix.
2. **Documentar cada error real en `docs/PENDIENTES.md`**, formato ya
   establecido: entrada numerada ("Nº error real"), texto exacto del error,
   causa raíz con cita de fuente real, fix aplicado, y una "Lección". Si un
   fix anterior resulta incompleto, no lo borres — marcalo explícito como
   superseded/corregido por el nuevo (así se hizo con Décimo octavo→Décimo
   noveno, y Décimo noveno parte 2→Vigésimo). Esto es un log honesto, no un
   lugar para esconder que algo salió mal a la primera.
3. **Validar TODO edit a un script** con `bash -n <script>` y
   `shellcheck -S warning -e SC1091 <script>` antes de darlo por bueno.
4. **Nunca correr el build vos mismo si no tenés `podman`/`podman-compose`
   disponible** (esta sesión de Claude, corriendo por el bridge del
   escritorio, no lo tiene instalado en la VM Linux del usuario). Dale al
   usuario el/los comando(s) EXACTOS para correr, uno por línea, listo para
   copiar/pegar en PowerShell — no describir el comando, imprimirlo literal
   (preferencia explícita del usuario).
5. **Nunca re-correr el build ni auto-programar checks proactivamente.**
   Solo actuar cuando el usuario pega output real de una corrida, o dice
   "listo"/"termino".
6. **Sincronizar cambios a la máquina del usuario** con `SendUserFile` +
   `device_commit_files` (bridge al escritorio), y commitear con `git`
   corrido vía `device_bash` en la ruta real del repo. El working dir local
   de Claude (si lo hay) es sólo una copia de trabajo — el repo real y el
   `git log` que importa están en la máquina del usuario.
7. **Lock files viejos de git**: este bridge a veces deja `.git/index.lock`,
   `.git/HEAD.lock` o `.git/objects/*/tmp_obj_*` colgados entre llamadas
   (el sandbox por default no deja borrar archivos sin permiso explícito).
   Si un commit falla con "Unable to create .../index.lock: File exists",
   pedir permiso de borrado para la carpeta conectada, y limpiar esos
   archivos sueltos antes de reintentar.
8. Mensajes de commit siempre con:
   ```
   Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
   Claude-Session: <url de la sesión actual>
   ```
   (esa URL cambia por sesión — usar la que corresponda a la sesión activa,
   no reusar la de sesiones viejas).

## Logs de cada corrida

`podman-compose` monta `./logs` (repo) → `/lfs/logs` (contenedor). El
entrypoint graba ahí automáticamente cada corrida, nombrado
`<timestamp>_<script>_<target>.log`. Sirve para diagnosticar sin depender de
que el usuario pegue el output completo — se puede leer directo desde la
carpeta del repo si hace falta revisar algo que no se pegó en el chat.
