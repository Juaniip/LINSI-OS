> **Nota de archivo:** conversión a Markdown de `Informe_Avance_LINSI-OS.docx`
> (original conservado en la raíz de `LINSIOS/`, formato Word, por si hace
> falta para una entrega formal). Es un **informe de avance puntual**,
> redactado en septiembre de 2026 cuando la Fase 6 Parte 2 (Mesa/LLVM)
> todavía estaba en curso — es una fotografía de ese momento, no un
> documento vivo. **No se actualizó su contenido al convertirlo**, para no
> alterar lo que efectivamente se escribió/entregó. Para el estado actual
> real del proyecto (muy posterior a lo que describe este informe), ver
> [`../PENDIENTES.md`](../PENDIENTES.md).

# INFORME DE AVANCE DE DESARROLLO

## LINSI-OS: diseño, construcción y estado actual de una distribución GNU/Linux propia

**Laboratorio LINSI — Trabajo de desarrollo de sistemas operativos**

- **Autor:** Juan Ignacio (Juaniip)
- **Carrera:** Ingeniería en Sistemas de Información
- **Fecha:** Septiembre de 2026

---

## 1. Introducción

El presente informe documenta el estado de avance del desarrollo de
LINSI-OS, una distribución GNU/Linux construida desde el código fuente para
uso interno del Laboratorio LINSI. A diferencia de una distribución
convencional, que se ensambla a partir de paquetes binarios ya compilados
por terceros, LINSI-OS se construye siguiendo una metodología de tipo Linux
From Scratch (LFS): cada componente del sistema —desde el compilador
cruzado hasta el entorno gráfico— se descarga en su forma de código fuente,
se verifica criptográficamente y se compila específicamente para el
triplete de destino `x86_64-linsi-linux-gnu`, sin heredar dependencias del
sistema operativo anfitrión utilizado para compilar.

Este enfoque, si bien exige un esfuerzo de ingeniería considerablemente
mayor que el de una distribución basada en paquetes preexistentes, permite
un control total sobre las opciones de compilación, las políticas de
seguridad aplicadas a cada componente y la superficie de ataque final del
sistema. El objetivo declarado del proyecto es alcanzar, a mediano plazo, un
nivel de madurez comparable al de distribuciones de referencia como Debian,
Arch Linux o Red Hat, entendiendo que ese objetivo excede el alcance de
este informe y constituye una meta de largo plazo del Laboratorio.

El desarrollo se organiza en ocho fases incrementales, cada una responsable
de una capa del sistema (toolchain, núcleo, espacio de usuario, seguridad,
comunicaciones, infraestructura de distribución de paquetes, interfaz
gráfica y, finalmente, empaquetado en una imagen ISO instalable). Este
informe describe el trabajo realizado en cada fase, los problemas técnicos
reales encontrados durante la implementación —y su resolución
fundamentada—, y el estado actual del proyecto al momento de redacción.

## 2. Objetivos

### 2.1. Objetivo general

Diseñar, construir y documentar una distribución GNU/Linux propia,
endurecida en materia de seguridad, apta para el uso cotidiano del
Laboratorio LINSI en tareas académicas, de investigación y de desarrollo de
software.

### 2.2. Objetivos específicos

- Construir un entorno de compilación cruzada aislado del sistema
  anfitrión, que garantice reproducibilidad y trazabilidad de cada
  componente compilado.
- Compilar un núcleo Linux endurecido, con mitigaciones activas contra las
  clases de ataque más relevantes (manipulación de memoria del núcleo,
  ataques por DMA, arranque no verificado).
- Construir un espacio de usuario completo y coherente (biblioteca C,
  gestor de servicios, utilidades básicas) sobre el núcleo anterior.
- Incorporar una capa de seguridad en profundidad: cifrado de disco,
  control de acceso obligatorio (SELinux), firewall de denegación por
  defecto y auditoría inmutable.
- Asegurar las comunicaciones de red y la autenticación de usuarios,
  incluyendo soporte de autenticación multifactor con tokens físicos FIDO2.
- Diseñar una infraestructura autónoma de distribución de paquetes firmados
  criptográficamente, con integración continua.
- Construir un entorno gráfico moderno basado en Wayland, con aceleración
  de hardware real (Mesa/Vulkan) y el entorno de escritorio KDE Plasma 6.
- Producir, en una etapa posterior, una imagen ISO instalable mediante un
  instalador gráfico.

## 3. Marco de desarrollo y metodología

El entorno de compilación se ejecuta dentro de un contenedor Podman
(originalmente especificado sobre Docker Desktop; se migró a Podman por
incompatibilidades del primero con el hardware disponible), orquestado
mediante `docker-compose.yml`. Este aislamiento cumple una doble función:
por un lado, evita que bibliotecas o herramientas instaladas en el sistema
anfitrión del desarrollador contaminen la compilación de LINSI-OS; por
otro, garantiza que cualquier persona del laboratorio pueda reproducir
exactamente el mismo entorno de build en su propia máquina.

A diferencia de un proceso de bootstrap LFS clásico, el proyecto no
realiza `chroot` al sistema de archivos de destino (sysroot) durante la
construcción. Todos los paquetes se instalan mediante la combinación
estándar de Autotools/Meson/CMake con `--prefix=/usr` y `DESTDIR` apuntando
al sysroot (`/lfs`), lo cual permite compilar sin necesidad de emular o
ejecutar directamente binarios de destino dentro del entorno de build. Esta
decisión de diseño tiene una implicancia técnica relevante que se desarrolla
en la Sección 6: un binario recién compilado para el sysroot de destino no
es, en general, ejecutable de forma directa dentro del contenedor de build,
incluso compartiendo la misma arquitectura de conjunto de instrucciones
(x86_64), porque sus dependencias dinámicas (glibc, en particular) fueron
compiladas para ese mismo sysroot y no para el sistema del contenedor.

Cada fase del desarrollo está implementada como un script de shell
autocontenido (`scripts/build-*.sh`), que no depende de otros scripts de
fase y que define sus propias funciones auxiliares de registro,
verificación y manejo de errores. Cada script expone pasos individuales
invocables por separado (por ejemplo, `build-kernel.sh configure`,
`build-kernel.sh build`, `build-kernel.sh verify`) además de un target
`all` que ejecuta la fase completa. Cada paso relevante concluye con una
verificación automática (`verify`) que confirma, mediante inspección de los
artefactos generados, que el resultado del paso es el esperado.

Todas las corridas de build quedan registradas automáticamente: el punto de
entrada del contenedor redirige la salida estándar de cada ejecución hacia
un archivo de log con marca temporal, visible desde el sistema anfitrión.
Esta práctica resultó fundamental para el diagnóstico de errores durante la
Fase 6, como se detalla en la Sección 6.

## 4. Arquitectura general del sistema

La arquitectura de LINSI-OS se organiza en capas estrictamente
dependientes, donde cada fase consume los artefactos producidos por la
anterior:

- **Fase 0 — El Taller:** entorno de compilación cruzada (toolchain).
- **Fase 1 — El Núcleo:** kernel Linux endurecido.
- **Fase 2 — Espacio de Usuario:** biblioteca C, gestor de servicios y
  utilidades base.
- **Fase 3 — El Escudo:** cifrado, control de acceso obligatorio, firewall
  y auditoría.
- **Fase 4 — Comunicaciones:** red, DNS cifrado y autenticación.
- **Fase 5 — Infraestructura Autónoma:** gestor de paquetes propio y
  distribución firmada.
- **Fase 6 — Interfaz Moderna:** Wayland, aceleración gráfica y entorno de
  escritorio KDE Plasma 6.
- **Fase 7 — Contenerización:** Flatpak, Podman y Distrobox para software
  de terceros y entornos de desarrollo aislados.
- **Fase 8 — ISO y Distribución:** imagen SquashFS de solo lectura e
  instalador gráfico Calamares.

Esta organización en capas responde a una decisión deliberada de minimizar
el acoplamiento entre fases: cada script de build es independiente y sólo
asume la existencia de los artefactos ya instalados en el sysroot
compartido, nunca del estado interno de otro script. Esto facilita tanto el
diagnóstico de errores —cada fase puede ejecutarse y depurarse de forma
aislada— como la eventual paralelización del trabajo entre distintos
integrantes del laboratorio.

## 5. Desarrollo por fases

### 5.1. Fase 0 — El Taller (entorno de compilación cruzada)

Siguiendo el capítulo 5 de la metodología LFS, se construyó un compilador
cruzado completo para el triplete `x86_64-linsi-linux-gnu`. El proceso
comprendió tres etapas secuenciales: primero, Binutils (ensamblador y
enlazador cruzados); segundo, la instalación de las cabeceras de la API de
Linux en el sysroot, necesarias para que la biblioteca C de la Fase 2 pueda
comunicarse correctamente con el núcleo; y tercero, GCC en su primera pasada
(`--without-headers`), un compilador estrictamente de C sin biblioteca
estándar, suficiente para compilar el propio núcleo de la Fase 1. El
resultado se validó compilando un programa mínimo en C y verificando que el
binario producido fuera un ELF válido para el triplete de destino.

### 5.2. Fase 1 — El Núcleo (kernel endurecido)

Con el compilador cruzado disponible, se compiló el núcleo Linux 7.2
aplicando un conjunto de opciones de configuración de seguridad mergeadas
sobre la configuración por defecto de x86_64. Las medidas de endurecimiento
incorporadas, con su justificación técnica, se resumen en la Tabla 1.

**Tabla 1 — Medidas de endurecimiento del kernel**

| Medida de endurecimiento | Justificación técnica |
|---|---|
| Kernel Lockdown (modo Force Integrity) con firma obligatoria de módulos | Impide que incluso el usuario root modifique memoria del núcleo en ejecución, cargue módulos sin firmar o realice volcados de memoria; reduce drásticamente la superficie de post-explotación. |
| KASLR (aleatorización de direcciones del núcleo y de memoria) | Dificulta la explotación de vulnerabilidades de corrupción de memoria al impedir que un atacante conozca de antemano direcciones fijas del núcleo. |
| IOMMU (Intel VT-d / AMD-Vi) con modo DMA estricto y Thunderbolt/FireWire deshabilitados | Confina el acceso DMA de dispositivos externos, neutralizando vectores de ataque de tipo Thunderclap sobre puertos de alta velocidad. |
| Soporte de sistema de archivos BTRFS con ACL | Habilita snapshots del sistema de archivos a nivel de núcleo, utilizados en fases posteriores para recuperación ante fallos. |
| EFI Stub | Permite que la imagen del núcleo sea arrancada directamente por firmware UEFI; sienta la base para el enrolado de Secure Boot, previsto para la Fase 8. |

El resultado de la compilación (imagen `bzImage` y módulos) fue verificado
automáticamente contra el archivo de configuración resultante, confirmando
que todas las opciones de endurecimiento quedaron efectivamente activas.

### 5.3. Fase 2 — Espacio de usuario

Sobre el núcleo compilado se construyó la biblioteca C del sistema
(glibc), la biblioteca de C++ (libstdc++), una segunda pasada de Binutils y
GCC —ya enlazados contra la glibc recién compilada, a diferencia del
compilador de C puro de la Fase 0— y el conjunto de utilidades base del
sistema: `attr`, `acl`, `libcap` y `util-linux` para la gestión de permisos
extendidos y utilidades de sistema de archivos; systemd como gestor de
servicios e inicialización; ncurses para interfaces de texto; **uutils**,
una reimplementación de las utilidades clásicas de GNU coreutils escrita en
Rust, adoptada deliberadamente para eliminar una clase completa de
vulnerabilidades de corrupción de memoria propias de C; y Zsh como
intérprete de línea de comandos predeterminado.

### 5.4. Fase 3 — El Escudo (seguridad en profundidad)

Esta fase incorpora la estrategia de defensa en profundidad del sistema,
compuesta por diecinueve pasos de compilación independientes. En materia de
cifrado de datos en reposo, se implementó LUKS2 sobre `libcryptsetup` y
LVM2, utilizando Argon2id como función de derivación de clave; esta función
satura deliberadamente el uso de memoria durante el cómputo, lo cual
encarece de forma significativa los ataques de fuerza bruta acelerados por
GPU respecto de funciones de derivación más antiguas. En materia de control
de acceso obligatorio, se compiló la pila completa de SELinux (`libsepol`,
`libselinux`, `libsemanage`, `checkpolicy` y `policycoreutils`), que
permite confinar procesos comprometidos a un conjunto mínimo de acciones
autorizadas por política, incluso si dicho proceso se ejecuta con
privilegios elevados. Se complementó con un firewall nftables (sobre
`libmnl` y `libnftnl`) configurado con política de denegación por defecto, y
con auditd para el registro inmutable de eventos de auditoría.

### 5.5. Fase 4 — Comunicaciones

Se aseguró la capa de comunicaciones del sistema en dos frentes. Del lado
de la red, `systemd-networkd` asume el control de las interfaces con
aleatorización de direcciones MAC —dificultando el rastreo del equipo a
nivel de red local— y se fuerza DNS-over-TLS para evitar la interceptación
o manipulación de resoluciones de nombres. Del lado de la autenticación, se
reconstruyó Linux-PAM incorporando el módulo `pam_u2f` (sobre `libfido2` y
`libcbor`), lo que permite exigir un token físico FIDO2 como segundo factor
de autenticación, y se incorporó `pam_faillock` para mitigar ataques de
fuerza bruta contra credenciales locales mediante bloqueo progresivo de
intentos.

### 5.6. Fase 5 — Infraestructura autónoma

Esta fase, orientada a dotar a LINSI-OS de un mecanismo propio de
distribución de software, contempla la compilación de `apk-tools` como
gestor de paquetes y la configuración de un esquema de firma criptográfica
obligatoria para la instalación de paquetes, de modo que ningún paquete no
firmado por el laboratorio pueda instalarse en un equipo con LINSI-OS. El
diseño previsto contempla, además, un servidor de repositorio alojado en
una Raspberry Pi 5 de 8 GB, expuesto de forma segura mediante un túnel Zero
Trust de Cloudflare —que oculta la dirección IP real del servidor y
gestiona el cifrado HTTPS del lado del proveedor—, y un flujo de
integración continua que compile y firme automáticamente cada nueva
versión de un paquete.

Al momento de redacción de este informe, los scripts correspondientes a
esta fase se encuentran escritos y sintácticamente verificados, pero su
ejecución efectiva —tanto la compilación de `apk-tools` como la puesta en
marcha del servidor en la Raspberry Pi— aún no cuenta con confirmación
empírica, y la decisión respecto de qué tipo de ejecutor (runner) utilizar
para la integración continua permanece abierta. Este punto se retoma en la
Sección 8 como pendiente prioritario.

### 5.7. Fase 6 — Interfaz moderna

La Fase 6 introduce el entorno gráfico del sistema y se subdivide en tres
partes de complejidad creciente.

**Parte 1 — Fundación no gráfica.** Comprende toda la infraestructura de la
que depende un entorno gráfico moderno sin incluir aún el propio compositor
ni los drivers de aceleración: la capa de comunicación entre procesos y
permisos (D-Bus, polkit), el subsistema de renderizado de fuentes y
gráficos 2D (freetype, harfbuzz, fontconfig, pixman, cairo), el protocolo
Wayland junto con sus extensiones (wayland-protocols), la pila completa de
entrada de dispositivos (mtdev, libevdev, xkeyboard-config, libinput,
libxkbcommon) y la pila de audio moderna (alsa-lib, PipeWire, WirePlumber).
Esta parte se completó y verificó en su totalidad.

**Parte 2 — Mesa y LLVM (drivers gráficos), en curso.** Esta etapa compila
la biblioteca gráfica Mesa 26.2.1 —que provee los drivers OpenGL y Vulkan
de código abierto para las tres familias de GPU presentes en el laboratorio
(NVIDIA, AMD e Intel integrada)— junto con LLVM, del cual Mesa depende para
la compilación en tiempo de ejecución de shaders mediante los drivers de la
familia Gallium. Al momento de redacción, libdrm y LLVM se encuentran
compilados, instalados y verificados en el sysroot de destino; la
compilación de Mesa propiamente dicha se encuentra en curso, habiéndose
resuelto diez incidencias reales de compilación durante el proceso. Estas
incidencias, su causa raíz y su resolución se documentan en detalle en la
Sección 6, por constituir el aporte técnico más relevante del período
cubierto por este informe.

**Parte 3 — Qt6 y KDE Plasma (no iniciada).** Prevista para compilar el
framework Qt6 exclusivamente contra Wayland y, sobre él, el entorno de
escritorio KDE Plasma 6, con un tema oscuro y tipografías Nerd Font
distribuidas por defecto a los nuevos usuarios mediante `/etc/skel/`. Su
inicio está supeditado a la finalización de la Parte 2, de la cual depende
directamente.

## 6. Problemas técnicos relevantes y lecciones aprendidas

Durante el desarrollo se presentaron dificultades técnicas no triviales,
cuya resolución fundamentada constituye en sí misma un aporte documental
para el resto del equipo. Se destacan tres categorías recurrentes.

### 6.1. Ejecución de binarios del sysroot cruzado dentro del entorno de build

Un supuesto inicial razonable, pero incorrecto, era que un binario recién
compilado para el sysroot de destino podría ejecutarse sin problemas dentro
del propio contenedor de build, dado que ambos comparten la arquitectura
x86_64. La experiencia real refutó este supuesto en al menos tres variantes
distintas durante la Parte 1 de la Fase 6: en el caso de `wayland-scanner`,
la herramienta nativa simplemente no existía y debió compilarse una versión
separada específicamente para ejecutarse en el entorno de build; en el caso
de `glib-compile-resources`, el binario del sysroot cruzado sí existía pero
fallaba al cargar bibliotecas compartidas propias de la glibc cruzada,
inexistente en el contenedor; y en el caso de `spa-json-dump`, el binario
cargaba sus bibliotecas correctamente pero requería símbolos de una versión
de glibc más reciente que la disponible en el contenedor de build. Las tres
variantes se resolvieron con el mismo principio general: obtener un binario
genuinamente nativo (mediante el gestor de paquetes del contenedor cuando
existía, o compilándolo aparte cuando no) y asegurar, mediante el mecanismo
de archivos de Meson (`cross-file` o `native-file`, según cómo cada
proyecto invoque `find_program()`), que la herramienta de build utilice ese
binario nativo en lugar del cruzado.

Un caso posterior, durante la compilación de LLVM en la Parte 2, presentó
una variante adicional del mismo problema de fondo: el binario
`llvm-config`, siendo genuinamente nativo, fallaba en tiempo de ejecución
por un error de resolución de símbolos de glibc (`undefined symbol`,
versión `GLIBC_PRIVATE`) una vez copiado al sysroot de destino. La causa
fue que su RPATH —diseñado deliberadamente por LLVM como una ruta relativa
al propio binario (`$ORIGIN`) para permitir su reubicación— terminaba
resolviendo, tras la copia, contra la biblioteca C del sysroot cruzado en
lugar de la nativa. La corrección consistió en reescribir explícitamente el
RPATH del binario con la herramienta `patchelf`, apuntándolo a un
directorio de bibliotecas nativas conocido, desacoplando así la ruta de
búsqueda de bibliotecas en tiempo de ejecución de las rutas de instalación
asumidas en tiempo de compilación.

### 6.2. Mensajes de error de Meson que ocultan la causa real

Durante la compilación de Mesa se identificó, en dos oportunidades
independientes, un patrón de comportamiento problemático del sistema de
build Meson: cuando una validación combinada de versión y disponibilidad de
módulos falla, Meson reporta un único mensaje genérico de error (`Python >=
3.10 not found`) independientemente de cuál de las condiciones subyacentes
fue la que realmente falló. En ambos casos, la versión de Python instalada
satisfacía ampliamente el requisito mínimo declarado; el fallo real
correspondía, en la primera oportunidad, a la ausencia del módulo `mako`
(requerido por Mesa para generar código fuente a partir de plantillas), y
en la segunda, a la ausencia del módulo `yaml` (PyYAML, requerido para
generar tablas de formato y extensiones a partir de descripciones en YAML).
Este comportamiento se corresponde con un problema documentado
públicamente en el repositorio del propio proyecto Meson.

La lección metodológica extraída, y adoptada como práctica de trabajo para
el resto del proyecto, es que ante un mensaje de error que no resulta
internamente consistente con el resto de la salida del build, corresponde
inspeccionar el archivo de log completo de la herramienta subyacente
(`meson-log.txt`, en este caso) antes de invertir tiempo en investigar el
código fuente del proyecto contra fuentes externas. Dicho archivo registra
el comando exacto ejecutado por Meson y su salida real, resultando
sistemáticamente más confiable que la reconstrucción de la lógica de
validación a partir de réplicas de terceros del repositorio, que en más de
una ocasión resultaron no coincidir entre sí ni con la versión exacta
utilizada por el proyecto.

### 6.3. Evolución de opciones de configuración entre versiones de un mismo proyecto

Se constató que las opciones de configuración expuestas por el sistema de
build de Mesa no son estables entre versiones: la opción `swrast` del
driver Gallium fue renombrada a `llvmpipe`, y las opciones `gallium-vdpau` y
`osmesa` fueron eliminadas por completo entre la versión asumida
inicialmente en la planificación y la versión 26.2.1 efectivamente
utilizada. Dado que el repositorio canónico del proyecto
(`gitlab.freedesktop.org`) resultó inaccesible desde el entorno de
desarrollo utilizado, y que las réplicas disponibles en otras plataformas
presentaron información contradictoria entre sí, se adoptó como fuente de
verdad primaria y definitiva la salida real del propio proceso de build,
corrigiendo la configuración de forma iterativa a partir de cada error
concreto reportado.

## 7. Gestión de versiones y control de cambios

Hasta el período inmediatamente anterior a este informe, el desarrollo del
proyecto no contaba con un repositorio de control de versiones: la
totalidad de los archivos se gestionaba directamente sobre el sistema de
archivos local, sin historial de cambios. Se identificó esta carencia como
un riesgo relevante para la trazabilidad del proyecto y se procedió a
inicializar un repositorio Git local, junto con un archivo de exclusión
(`.gitignore`) que deja fuera del control de versiones tanto el código
fuente de terceros descargado durante el build (reproducible de forma
determinística a partir de las versiones y sumas de verificación
declaradas) como los archivos de registro generados automáticamente en
cada ejecución. El primer commit incorpora la totalidad de los artefactos
propios del proyecto —scripts de build, archivos de configuración del
contenedor, documentación de fases y flujo de integración continua— y se
establece como práctica de trabajo, a partir de este punto, registrar cada
corrección técnica relevante como un commit individual, de forma de
preservar un historial útil ante la eventual necesidad de revertir un
cambio.

## 8. Estado actual del proyecto

*(estado al momento de redactar este informe — ver `PENDIENTES.md` para el
estado real y actualizado)*

- **Fases 0 a 4:** completas y verificadas mediante registros reales de
  ejecución.
- **Fase 5:** implementada a nivel de script, pendiente de confirmación
  empírica de ejecución (compilación de `apk-tools`, puesta en marcha del
  servidor de repositorio y decisión de infraestructura de integración
  continua).
- **Fase 6, Parte 1:** completa y verificada.
- **Fase 6, Parte 2:** en curso; libdrm y LLVM completos y verificados,
  compilación de Mesa en progreso tras la resolución de diez incidencias
  reales de build.
- **Fase 6, Parte 3, Fase 7 y Fase 8:** no iniciadas, en espera de la
  finalización de las etapas previas de las que dependen.

## 9. Trabajo futuro

- Confirmar la compilación exitosa de Mesa y completar la verificación de
  los drivers OpenGL y Vulkan generados para las tres familias de GPU
  objetivo.
- Iniciar la Fase 6, Parte 3 (Qt6 y KDE Plasma 6), que requerirá incorporar
  libxml2 al conjunto de dependencias ya compiladas para reactivar el
  soporte de xkbregistry, necesario para el selector de distribución de
  teclado del entorno de escritorio.
- Confirmar empíricamente la Fase 5 mediante la ejecución real de los
  scripts de infraestructura y resolver la decisión pendiente respecto del
  ejecutor de integración continua a utilizar.
- Iniciar la Fase 7 (contenerización de software de terceros mediante
  Flatpak, y entornos de desarrollo aislados mediante Podman/Distrobox) y,
  finalmente, la Fase 8 (empaquetado en imagen SquashFS e instalador
  Calamares).
- Evaluar las implicancias de cumplimiento de licencias de software libre
  (GPL/LGPL) derivadas de la distribución del núcleo Linux, glibc y
  systemd como parte de una imagen del sistema, de forma previa a
  cualquier distribución de LINSI-OS fuera del ámbito interno del
  laboratorio.

## 10. Conclusiones

El desarrollo de LINSI-OS hasta el presente demuestra la viabilidad técnica
de construir, desde el código fuente y con un enfoque de seguridad en
profundidad, una distribución GNU/Linux funcional adaptada a las
necesidades específicas del Laboratorio LINSI. La decisión metodológica de
aislar completamente el entorno de compilación del sistema anfitrión, si
bien incrementó la complejidad y el tiempo de diagnóstico ante fallos
—particularmente en lo relativo a la distinción entre herramientas nativas
y cruzadas durante la Fase 6—, resultó consistente con el objetivo de
reproducibilidad planteado desde el inicio del proyecto, y permitió, en
cada incidencia encontrada, arribar a una causa raíz verificable en lugar
de una solución paliativa.

El estado actual del proyecto, con las cuatro primeras fases completas y
verificadas, la fundación no gráfica de la interfaz completa, y la
compilación de los drivers gráficos en su etapa final de resolución de
incidencias, resulta consistente con una trayectoria de avance sostenido
hacia el objetivo general planteado. Los principales riesgos abiertos
identificados a la fecha son la falta de confirmación empírica de la Fase 5
y las obligaciones de cumplimiento de licencias de software libre asociadas
a la eventual distribución del sistema fuera del laboratorio, ambos
señalados como prioridades para el próximo período de trabajo.
