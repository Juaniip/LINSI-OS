# LINSI-OS · Fase 0 — "El Taller"

Entorno de construcción para LINSI-OS, la distro propia del Laboratorio LINSI.
Corresponde a la **Fase 0** del documento fundacional (ver
[`docs/PILARES_FUNDACIONALES_LINSI-OS.md`](./PILARES_FUNDACIONALES_LINSI-OS.md)):
un entorno que no hereda dependencias del host, donde se compila el
cross-compiler (Binutils + GCC) y las cabeceras de Linux que después usan la
Fase 1 (kernel) y la Fase 2 (espacio de usuario).

Hay dos formas de usarlo — elegí la que te resulte más cómoda. Los scripts de
build (`scripts/env.sh`, `scripts/build-cross-toolchain.sh`) son **los mismos**
en ambos casos.

## Opción A · Podman (recomendada)

El build corre completamente aislado del host, en un contenedor con
volúmenes persistentes para no volver a descargar/compilar todo cada vez.
**El proyecto usa `podman-compose` (con guion), no `docker-compose.exe` ni
`podman compose` sin guion** — se migró desde Docker Desktop por
incompatibilidades con parte del hardware del laboratorio (ver
`docs/PENDIENTES.md`, sección "Infraestructura de build").

```bash
# 1. Construir la imagen del Taller
podman-compose build

# 2. Compilar el cross-toolchain completo (Binutils + headers Linux + GCC)
podman-compose run --rm builder scripts/build-cross-toolchain.sh all

# 3. (opcional) Entrar a una shell dentro del contenedor para trabajar a mano
podman-compose run --rm builder bash
```

Los volúmenes con nombre (`linsios-tools`, `linsios-build`, `linsios-sysroot`,
`linsios-boot`) persisten entre corridas (`podman volume ls` para verlos) —
no hace falta recompilar de cero cada vez. `./sources` (con los tarballs
descargados) es una carpeta normal del proyecto, no un volumen, y no está
versionada en git (se re-descarga sola).

## Opción B · WSL2 sin Podman

Si preferís no usar contenedores y trabajar directo en una distro Ubuntu de WSL2:

```powershell
# En Windows (PowerShell como administrador), si todavía no tenés WSL:
wsl --install -d Ubuntu-24.04
```

```bash
# Adentro de la distro WSL:
cd scripts
chmod +x setup-wsl.sh build-cross-toolchain.sh
./setup-wsl.sh
LFS=$HOME/linsi-os-lfs LFS_TGT=x86_64-linsi-linux-gnu ./build-cross-toolchain.sh all
```

**Trade-off:** en WSL el entorno ya no está aislado del host — paquetes que
tengas instalados en esa distro pueden influir en la build. Es más rápido para
arrancar, pero se aleja del espíritu "no heredar dependencias del host" de la
Fase 0. Para algo que eventualmente va a ser una ISO que otros van a instalar,
Podman es la opción más segura a largo plazo; WSL sirve bien para iterar rápido
mientras se prueban los scripts.

## Qué hace `build-cross-toolchain.sh`

Sigue el enfoque estándar tipo LFS (Linux From Scratch), capítulo 5:

1. **Binutils (pass 1)** — ensamblador y linker cruzados para el triplet
   `x86_64-linsi-linux-gnu`.
2. **Cabeceras de la API de Linux** — se instalan en el sysroot (`$LFS/usr/include`)
   para que, más adelante, glibc (Fase 2) sepa cómo hablar con el kernel.
3. **GCC (pass 1)** — compilador cruzado "sólo C", sin libc todavía
   (`--without-headers`), suficiente para compilar el propio kernel en Fase 1.
4. Verificación rápida: compila un `.c` mínimo con el nuevo `x86_64-linsi-linux-gnu-gcc`
   y confirma que el binario resultante es un ELF válido.

Podés correr un paso puntual en vez del build completo:

```bash
podman-compose run --rm builder scripts/build-cross-toolchain.sh binutils
podman-compose run --rm builder scripts/build-cross-toolchain.sh headers
podman-compose run --rm builder scripts/build-cross-toolchain.sh gcc
podman-compose run --rm builder scripts/build-cross-toolchain.sh verify
```

## Versiones fijadas

Están en `scripts/env.sh` (`BINUTILS_VERSION`, `GCC_VERSION`, `LINUX_VERSION`,
`GMP_VERSION`, `MPFR_VERSION`, `MPC_VERSION`). El kernel es 7.2 (la versión
que vamos a usar en todo el proyecto, ver README-FASE1.md); Binutils/GCC son
un set conocido-bueno al momento de armar esto — antes de una build "real"
convendría chequear si hay versiones más nuevas en ftp.gnu.org.

## Qué queda listo para la Fase 1

Al terminar `make toolchain` vas a tener, dentro del volumen `linsios-tools`
(montado en `/lfs/tools` dentro del contenedor):

- `x86_64-linsi-linux-gnu-gcc`, `-ld`, `-as`, `-readelf`, etc.
- Cabeceras del kernel en `/lfs/usr/include` (volumen `linsios-sysroot`).

## Fase 1 ya está armada

Ver `README-FASE1.md` — kernel endurecido (Lockdown, KASLR, mitigación DMA,
BTRFS, EFI) compilado con este mismo cross-toolchain.
