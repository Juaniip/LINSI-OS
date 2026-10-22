# Guía de desarrollo original (versión corta)

> **Nota de archivo:** este es el texto original de `GUIA DESARROLLO
> LINSI-OS.txt`, la primera versión (resumida) de la visión de las 8 fases,
> escrita antes de empezar la implementación. Se conserva acá como registro
> histórico — la versión vigente, más detallada y con el estado real de cada
> fase, es [`../PILARES_FUNDACIONALES_LINSI-OS.md`](../PILARES_FUNDACIONALES_LINSI-OS.md).
> Contenido sin modificar respecto del `.txt` original.

## Cimientos y Sistema Base

**Fase 0 (El Taller):** Para no heredar dependencias del host, el entorno de
construcción arranca en un contenedor Docker con volúmenes persistentes.
Aquí se compila el cross-compiler (Binutils, GCC/Clang) y las cabeceras de
Linux para forjar binarios completamente independientes desde cero.

**Fase 1 (El Núcleo):** Se descarga el kernel puro y se aplica un
endurecimiento estricto. Se activa Kernel Lockdown para que ni siquiera el
usuario root pueda modificar el código en memoria, y KASLR para evadir
exploits aleatorizando las direcciones. Se recorta la superficie de ataque
deshabilitando puertos DMA y se integra soporte BTRFS en el núcleo para
gestionar snapshots. El arranque se delega a systemd-boot con Secure Boot
habilitado.

**Fase 2 (Espacio de Usuario):** Se adopta glibc como librería C. Aunque
cede el purismo de mitigación de errores de musl, garantiza compatibilidad
nativa para un uso diario sin fricciones operativas entre el laboratorio, la
universidad y las tareas corporativas. Se integra systemd para gobernar la
concurrencia de servicios, y se reemplazan las utilidades clásicas por
uutils (escritas en Rust) para erradicar fallos de memoria, utilizando Zsh
como shell predeterminada.

## Seguridad, Red y Repositorios

**Fase 3 (El Escudo):** Los datos en reposo se aseguran con cifrado LUKS2
utilizando el algoritmo Argon2id, el cual satura intencionalmente la memoria
para neutralizar ataques de fuerza bruta por GPU. Se implementa SELinux con
políticas estrictas para enjaular procesos vulnerados, respaldado por un
firewall nftables de denegación por defecto y auditoría inmutable
encriptada vía auditd.

**Fase 4 (Comunicaciones):** systemd-networkd asume el control de las
interfaces aplicando aleatorización de direcciones MAC. Las resoluciones se
encriptan forzando DNS-over-TLS para evitar interceptaciones de red. La
autenticación a través de Linux-PAM exige alta entropía, bloquea ataques
automatizados con pam_faillock y requiere tokens físicos FIDO2.

**Fase 5 (Infraestructura Autónoma):** El gestor apk-tools administra el
software. El servidor de repositorios opera desde la Raspberry Pi 5 de 8GB,
aislado mediante un túnel Zero Trust de Cloudflare que cachea los paquetes,
maneja el protocolo HTTPS y oculta la IP real. Todo el software se compila y
despliega automáticamente vía CI/CD, exigiendo una firma criptográfica
inquebrantable para autorizar su instalación.

## Entorno Gráfico y Estética

**Fase 6 (Interfaz Moderna):** Wayland reemplaza a X11 para aislar la
lectura de ventanas y teclados. El motor Qt6 se compila exclusivamente para
Wayland, levantando el entorno KDE Plasma 6 impulsado por Mesa y Vulkan para
asegurar aceleración de hardware. PipeWire gestiona la pila multimedia
eliminando latencias, y el sistema copia un entorno estandarizado (tema
oscuro, tipografías Nerd) desde `/etc/skel/`.

## Ecosistema Híbrido y Despliegue

**Fase 7 (Contenerización):** Para mantener la librería base intacta, el
software cerrado o de entretenimiento se instala mediante Flatpak. Este
modelo comparte librerías deduplicadas en disco sin pérdida de rendimiento
de CPU o GPU, garantizando los cuadros por segundo nativos. El desarrollo de
software y las pruebas académicas se aíslan en contenedores efímeros
utilizando Podman o Distrobox.

**Fase 8 (ISO y Distribución):** El sistema se comprime en una imagen
SquashFS de solo lectura para arrancar desde memoria RAM. El instalador
universal Calamares, personalizado con QML, automatiza el despliegue al
disco físico, configurando particiones BTRFS y el cifrado LUKS en minutos.
