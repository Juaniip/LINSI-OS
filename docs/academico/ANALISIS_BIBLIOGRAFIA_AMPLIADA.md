> **Nota de archivo:** conversión a Markdown de `Analisis 2.docx` (original
> en la raíz de `LINSIOS/`). Es una salida de ChatGPT — una bibliografía
> académica ampliada en formato APA 7 para el documento fundacional de
> LINSI-OS, organizada por líneas de investigación. Es un insumo externo
> para la formulación académica del proyecto, no documentación técnica de
> build ni una posición oficial del equipo. Conversación original:
> <https://chatgpt.com/s/t_6a9abd1af8e881918e780fc8b1d200dc>

# Bibliografía académica ampliada para LINSI-OS

Para el documento LINSI-OS conviene ampliar bastante la bibliografía, mejor
organizada por líneas de investigación, porque no todos los papers sirven
para fundamentar el mismo componente. El documento fundacional plantea
explícitamente construcción desde fuente, hardening, privacidad, robustez,
reproducibilidad, Rust, SELinux, FIDO2, firma de paquetes, Wayland/PipeWire
y aislamiento mediante contenedores. A continuación, una bibliografía
ampliada en APA 7, priorizando publicaciones académicas y técnicas
relevantes hasta 2026.

## 1. Linux, arquitectura de sistemas y seguridad de sistemas operativos

### 1.1. Evaluación cuantitativa de seguridad de sistemas operativos

**Kapera, A., & Niemiec, M. (2026).** A methodology for quantitative
security evaluation of operating systems: Scenario-based comparison of
Qubes OS and Windows 11. *Electronics, 15*(10), 2110.
<https://doi.org/10.3390/electronics15102110>

Pertinencia: ⭐⭐⭐⭐⭐ — probablemente uno de los papers más importantes para
agregar al trabajo. Propone una metodología reproducible para cuantificar
la postura de seguridad de un sistema operativo utilizando mitigaciones
asociadas a MITRE ATT&CK y escenarios de ataque, comparando Qubes OS y
Windows 11 con métricas cuantitativas de mitigación. La idea es
reutilizable para LINSI-OS: LINSI-OS → MITRE ATT&CK → técnicas mitigadas →
score → comparación con otras distros. Podría convertirse en la base
metodológica para demostrar científicamente si LINSI-OS realmente es más
seguro.

### 1.2. SHARD

**Abubakar, M., Ahmad, A., Fonseca, P., & Xu, D. (2021).** SHARD:
Fine-grained kernel specialization with context-aware hardening. En *30th
USENIX Security Symposium (USENIX Security 21)* (pp. 3843–3860). USENIX
Association.

Muy pertinente para el planteo de reducir superficie de ataque mediante
especialización del kernel: analiza qué partes del kernel necesita
realmente una aplicación y restringe las partes expuestas al atacante.
Para LINSI-OS plantea: *¿cuánto código/funcionalidad del kernel necesita
realmente el laboratorio?*

### 1.3. Temporal System Call Specialization

**Ghavamnia, S., Palit, T., Mishra, S., & Polychronakis, M. (2020).**
Temporal system call specialization for attack surface reduction. En *29th
USENIX Security Symposium (USENIX Security 20)* (pp. 1749–1766). USENIX
Association.

Buen antecedente para justificar que reducir funcionalidades disponibles
durante la ejecución puede disminuir la superficie de ataque; el prototipo
deshabilitó más syscalls de seguridad crítica que enfoques anteriores.

## 2. Kernel hardening y superficie de ataque

### 2.1. Linux kernel self-protection

**Linux Kernel Documentation. (2026).** Kernel self-protection.
<https://docs.kernel.org/security/self-protection.html>

No es un paper académico, pero debería estar en el marco técnico de
LINSI-OS: estructura la autoprotección del kernel alrededor de reducción de
superficie, aislamiento de memoria, mitigaciones y prevención de
explotación. Útil para conectar KASLR + Lockdown + restricciones de
interfaces + hardening con una estrategia de seguridad coherente.

### 2.2. BeeBox

**Jin, D., Gaidis, A. J., & Kemerlis, V. P. (2024).** BeeBox: Hardening BPF
against transient execution attacks. En *33rd USENIX Security Symposium
(USENIX Security 24)* (pp. 613–630). USENIX Association.

Muy interesante para una discusión avanzada de attack surface y
rendimiento: incluso mecanismos diseñados para ser seguros, como BPF/eBPF,
agregan superficie de ataque y requieren hardening específico. Ayuda a
demostrar que agregar una mitigación no siempre significa que el sistema
global sea más seguro.

### 2.3. GhostRace

**Ragab, H., Mambretti, A., Kurmus, A., & Giuffrida, C. (2024).** GhostRace:
Exploiting and mitigating speculative race conditions. En *33rd USENIX
Security Symposium (USENIX Security 24)* (pp. 6185–6202). USENIX
Association.

Antecedente para estudiar ataques de microarquitectura y mitigaciones del
kernel, particularmente si LINSI-OS quiere sostener que su configuración
del kernel ofrece protección frente a categorías modernas de ataques.

### 2.4. InSpectre Gadget

**Wiebing, S., de Faveri Tron, A., Bos, H., & Giuffrida, C. (2024).**
InSpectre Gadget: Inspecting the residual attack surface of
cross-privilege Spectre v2. En *33rd USENIX Security Symposium (USENIX
Security 24)* (pp. 577–594). USENIX Association.

Muy útil para mostrar que mitigaciones existentes no equivalen a
eliminación total de una superficie de ataque: encuentra gadgets
explotables residuales en el kernel Linux a pesar de mitigaciones
desplegadas.

## 3. Rust y seguridad de memoria

Área donde más conviene ampliar la bibliografía porque LINSI-OS da un peso
importante a la sustitución de utilidades C por Rust.

### 3.1. Rust-for-Linux

**Li, H., Guo, L., Yang, Y., Wang, S., & Xu, M. (2024).** An empirical
study of Rust-for-Linux: The success, dissatisfaction, and compromise. En
*2024 USENIX Annual Technical Conference (USENIX ATC 24)*. USENIX
Association.

Debería ser obligatorio en el estado del arte. Estudió el proyecto
Rust-for-Linux (6 drivers, 269 issues, 763 pull requests, 1.540 commits,
3.611 mensajes, 12.501 discusiones) y concluye que Rust puede aumentar la
capacidad de seguridad del kernel, pero no elimina completamente los
problemas porque `unsafe` sigue siendo necesario, con costos de rendimiento
en determinados drivers. Para LINSI-OS es importante porque evita una
afirmación excesiva como "Rust elimina las vulnerabilidades" — la
formulación correcta es "Rust puede reducir determinadas clases de errores
de memoria, pero no constituye por sí mismo una garantía de seguridad
integral."

### 3.2. ASTERINAS

**Peng, Y., Tian, H., Zhang, J., et al. (2025).** ASTERINAS: A Linux
ABI-compatible, Rust-based framekernel OS with a small and sound TCB. En
*2025 USENIX Annual Technical Conference (USENIX ATC 25)* (pp. 307–323).
USENIX Association.

Antecedente muy cercano conceptualmente, aunque arquitectónicamente más
ambicioso que LINSI-OS: combina Linux ABI + Rust + TCB pequeño +
aislamiento intra-kernel, con soporte para más de 210 syscalls y un TCB de
memoria segura de ~14% del código. Permite posicionar LINSI-OS frente a una
línea más radical (Linux → Rust → kernel redesign → smaller TCB).

### 3.3. Rust y sistemas críticos

**Seidel, L., & Beier, J. (2024).** Bringing Rust to safety-critical
systems in space. *arXiv*. <https://doi.org/10.48550/arXiv.2405.18135>

Estudia la migración parcial de sistemas C a Rust, mostrando beneficios de
seguridad y desafíos de adopción, además de vulnerabilidades descubiertas
durante un caso de estudio de reescritura.

### 3.4. Rust y memoria

**Xia, T., Huang, K., Yu, D., et al. (2025).** LiteRSan: Lightweight
memory safety via Rust-specific program analysis and selective
instrumentation. *arXiv*. <https://arxiv.org/abs/2509.16389>

Útil para una discusión avanzada: Rust no implica que desaparezcan los
problemas de memoria, especialmente cuando existe código `unsafe`.

## 4. Reproducible Builds y supply-chain security

Debería ser una de las líneas centrales del trabajo, porque LINSI-OS
explícitamente utiliza build aislado, logs, Git y control del proceso de
compilación.

### 4.1. Reproducible Builds

**Lamb, C., & Zacchiroli, S. (2022).** Reproducible builds: Increasing the
integrity of software supply chains. *IEEE Software, 39*(2), 62–69.
<https://doi.org/10.1109/MS.2021.3117341>

Probablemente el paper más importante de esta categoría: diferencia entre
confiar en el código fuente y confiar en el binario producido; busca que
distintas reconstrucciones produzcan artefactos bit-a-bit idénticos.

### 4.2. Supply-chain security y adopción

**Williams, L., & Migues, S. (2025).** Establishing a baseline of software
supply chain security task adoption by software organizations. *arXiv*.
<https://arxiv.org/abs/2509.08083>

Muy útil para colocar LINSI-OS dentro del problema actual de supply-chain
security: entrevistó a 61 profesionales de nueve organizaciones y encontró
que ciertas prácticas nuevas de seguridad de componentes y build
infrastructure todavía tienen adopción relativamente temprana.

### 4.3. Secure Software Supply Chain Summit

**Lin, E., Ghebremichael, J., Enck, W., et al. (2025).** S3C2 Summit
2025-03: Industry Secure Supply Chain Summit. *arXiv*.
<https://arxiv.org/abs/2510.24920>

Buena publicación complementaria para contextualizar problemas actuales de
SBOM, infraestructura de build, commits maliciosos, componentes,
compliance, LLMs y software supply chain.

## 5. Qubes OS y aislamiento

No como competidor directo, sino como otra filosofía de security-by-design.

### 5.1. Qubes OS

**Rutkowska, J., & Wojtczuk, R. (2010).** Qubes architecture specification
v0.3. Qubes OS Project.

El documento arquitectónico original plantea aislamiento mediante Xen y
separación de dominios para minimizar el impacto de compromisos. Qubes
continúa utilizando una estrategia de security-by-compartmentalization,
separando aplicaciones y componentes críticos como networking y USB.

### 5.2. Qubes como objeto de investigación actual

**De Gregorio, A. (2026).** Qubes OS security in the public record.
*arXiv*. <https://doi.org/10.48550/arXiv.2607.14587>

Especialmente interesante: analiza 109 Security Bulletins de Qubes entre
2011 y 2025 y estudia la dependencia de componentes upstream, encontrando
que una parte importante de los problemas reportados procede de Xen,
CPU/microarquitectura y otros componentes externos. Enseñanza para
LINSI-OS: construir componentes propios no elimina automáticamente el
riesgo, puede trasladarlo hacia otros componentes upstream.

## 6. Seguridad del proceso de build

**Rutkowska, J. (2016).** Security challenges for the Qubes build process.
Qubes OS Project.

No es paper académico, pero es una referencia técnica excelente: discute
explícitamente verificación de fuentes, firmas, commits, paquetes,
confianza en build infrastructure y la posibilidad de comprometer la
máquina del desarrollador. Muy comparable con la preocupación de LINSI-OS
por aislar el entorno de compilación.

## 7. SELinux / Mandatory Access Control

**Loscocco, P., & Smalley, S. (2001).** Integrating flexible support for
security policies into the Linux operating system. En *Proceedings of the
2001 USENIX Annual Technical Conference*. USENIX Association.

Trabajo clásico y fundacional para incorporar mandatory access control al
kernel Linux.

**Jiang, Y., Liu, W., Ma, F., et al. (2026).** USEC: A user-requirement-driven
mandatory access control framework for operating systems. En *19th USENIX
Symposium on Operating Systems Design and Implementation (OSDI '26)*.
USENIX Association.

Particularmente valioso: cuestiona limitaciones prácticas de los sistemas
MAC convencionales y propone un enfoque orientado a requisitos de usuario.
Para LINSI-OS abre una línea experimental: *¿qué costo de configuración,
rendimiento y compatibilidad introduce SELinux cuando se lo utiliza como
control obligatorio por defecto?*

## 8. FIDO2 / autenticación fuerte

**Yadav, T. K., & Seamons, K. (2023).** A security and usability analysis
of local attacks against FIDO2. *arXiv*.
<https://arxiv.org/abs/2308.02973>

Importante porque evita tratar FIDO2 como una solución perfecta: analiza
ataques locales, extensiones de navegador, dispositivos físicos y
problemas de UX, identificando debilidades en implementaciones existentes.
Permite estudiar FIDO2 en términos de beneficio de seguridad + costo de
usabilidad + threat model.

## 9. Sistemas Linux endurecidos

**secureblue** — aunque no es un paper académico, debería aparecer
obligatoriamente como antecedente tecnológico directo: distribución
endurecida basada en Fedora Atomic, con hardening, SELinux, restricciones
de interfaces, reducción de privilegios, controles de dispositivos y otras
defensas. El propio LINSI-OS identifica a secureblue como su antecedente
más próximo:

| | LINSI-OS | secureblue |
|---|---|---|
| Construcción propia desde fuente | Cross-compilation | Infraestructura Fedora |
| Userland Rust | Sí | Parcialmente |
| FIDO2 integrado | Sí | Depende configuración |
| Repository propio | Sí, propuesta LINSI | — |
| Signed packages | Sí | Sí |
| Wayland-only | Sí | Sí |
| SELinux | Sí | Sí |
| Build aislado | Sí | Sí |
| Objetivo | Laboratorio universitario | — |

Esto puede ser un capítulo entero del estado del arte.

## 10. GrapheneOS como referencia de Security-by-Design

Aunque no es Linux desktop, es útil como caso de estudio de un sistema
operativo modificado donde la seguridad se diseña como propiedad sistémica.

**Böhning, et al. (2026).** The investigator's friend and foe: A forensic
analysis of GrapheneOS. *Forensic Science International: Digital
Investigation, 56*, 302048. <https://doi.org/10.1016/j.fsidi.2026.302048>

Compara GrapheneOS con Android y analiza tanto mecanismos de seguridad
como las consecuencias sobre la adquisición forense, encontrando que las
medidas de privacidad/seguridad de GrapheneOS dificultan considerablemente
determinados métodos de adquisición remota. Para LINSI-OS abre un concepto
interesante: una mejora de seguridad puede aumentar la resistencia del
sistema pero simultáneamente reducir la capacidad de recuperación forense.

## 11. Modelos de seguridad que deberían aparecer

- **MITRE ATT&CK.** MITRE. (2026). *MITRE ATT&CK® Enterprise*. MITRE
  Corporation. <https://attack.mitre.org/> — para mapear amenaza → técnica
  ATT&CK → mitigación → control LINSI-OS. Conecta muy bien con Kapera &
  Niemiec (2026).
- **SLSA.** SLSA. (2026). *Supply-chain Levels for Software Artifacts
  (SLSA)*. OpenSSF. <https://slsa.dev/> — para evaluar la seguridad de la
  cadena source → build → artifact → provenance → distribution.

## 12. Bibliografía priorizada para el alumno

**Nivel A — lectura obligatoria**

| Referencia | Motivo |
|---|---|
| Kapera & Niemiec, 2026 | Método cuantitativo para medir seguridad del OS |
| Lamb & Zacchiroli, 2022 | Reproducible builds |
| Li et al., 2024 | Rust + Linux |
| Peng et al., 2025 | OS basado en Rust |
| Abubakar et al., 2021 | Reducción de attack surface |
| Jiang et al., 2026 | Evolución de MAC |
| De Gregorio, 2026 | Evaluación longitudinal de Qubes |
| secureblue | Principal comparación práctica |
| Linux From Scratch | Base metodológica |
| SLSA | Supply-chain |

**Nivel B — muy recomendable**

| Referencia | Tema |
|---|---|
| Jin et al., 2024 | Kernel hardening |
| Wiebing et al., 2024 | Attack surface residual |
| Ragab et al., 2024 | Kernel + microarquitectura |
| Yadav & Seamons, 2023 | FIDO2 |
| Seidel & Beier, 2024 | Rust en sistemas críticos |
| Williams & Migues, 2025 | Supply chain |
| Lin et al., 2025 | Supply chain industrial |
| Böhning et al. (GrapheneOS forensic study), 2026 | Security/privacy vs forensics |

## 13. Una línea de investigación especialmente buena para LINSI-OS

Después de ampliar el estado del arte, reformularía la posible contribución
así: *"Evaluación experimental de una arquitectura Security-by-Design para
GNU/Linux basada en construcción desde código fuente, hardening del
kernel, control obligatorio de acceso y cadena de suministro
reproducible."*

Cinco dimensiones, con sus métricas:

- **Security:** attack surface, ATT&CK mitigations, servicios expuestos,
  privileged components.
- **Supply chain:** reproducibility, provenance, signatures, build
  isolation.
- **Privacy:** network metadata exposure, storage protection,
  authentication.
- **Robustness:** rollback, recovery, snapshot performance.
- **Usability:** boot, RAM, aplicación, compatibilidad, percepción del
  usuario.

### El hallazgo más interesante de esta ampliación

El proyecto no debería intentar demostrar que cada tecnología de LINSI-OS
es novedosa, porque la literatura demuestra que prácticamente ninguna lo es
individualmente. Lo interesante está en estudiar qué ocurre cuando estas
decisiones se combinan dentro de una cadena de construcción controlada y se
las evalúa experimentalmente como una arquitectura integral. Esto encaja
perfectamente con el propio documento, que reconoce que Rust, Wayland y
otras decisiones ya existen en proyectos grandes, pero argumenta que la
combinación específica bajo una base construida desde cero es lo
distintivo del proyecto.

Además, el paper de Kapera & Niemiec (2026) da una oportunidad
extraordinariamente buena: en vez de afirmar subjetivamente que LINSI-OS
es "más seguro," se puede medir su postura de seguridad de manera
reproducible y compararla con otros sistemas. Ese es el camino que más
elevaría el trabajo desde "proyecto de desarrollo de una distro" hacia
"investigación aplicada de seguridad de sistemas operativos."
