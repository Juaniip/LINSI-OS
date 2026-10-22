# Documentación de LINSI-OS

Esta carpeta es el único lugar centralizado de documentación del proyecto
(reorganizado el 2026-09-15 — antes había archivos sueltos de contexto y
handoffs dispersos por fuera del repo, en la carpeta `LINSIOS/` de
Windows; se consolidó todo acá).

## Documentación técnica vigente

- **[LINSI-OS.pdf](./LINSI-OS.pdf)** — Documento fundacional del proyecto: concepción, los cinco pilares (Seguridad, Privacidad, Robustez, Estética, Vanguardia), objetivos, arquitectura y metodología de construcción.
- **[PILARES_FUNDACIONALES_LINSI-OS.md](./PILARES_FUNDACIONALES_LINSI-OS.md)** — Los cinco pilares fundacionales en detalle, con el mapeo de cada fase técnica contra el pilar que sostiene, y una nota de estado actualizada.
- **[PENDIENTES.md](./PENDIENTES.md)** — La fuente de verdad del estado real del proyecto: estado de cada fase, decisiones tomadas y el registro completo de errores reales de compilación, su causa raíz y su corrección. Se actualiza a medida que se avanza.
- **[README-FASE0.md](./README-FASE0.md)** — Fase 0: entorno de compilación cruzada (El Taller).
- **[README-FASE1.md](./README-FASE1.md)** — Fase 1: compilación del núcleo endurecido (El Núcleo).

## [`academico/`](./academico/) — material de cátedra, no documentación técnica de build

- **[INFORME_AVANCE_2026-09.md](./academico/INFORME_AVANCE_2026-09.md)** — Informe de avance formal para la materia (autor: Juan Ignacio, septiembre 2026). Es una fotografía puntual de ese momento del proyecto, no un documento vivo — para el estado actual, ver `PENDIENTES.md`. El original en Word queda en la raíz de `LINSIOS/` por si hace falta para una entrega.
- **[ANALISIS_PERTINENCIA_ACADEMICA.md](./academico/ANALISIS_PERTINENCIA_ACADEMICA.md)** — Análisis externo (ChatGPT) de la pertinencia académica del proyecto, contrastado contra antecedentes técnicos.
- **[ANALISIS_BIBLIOGRAFIA_AMPLIADA.md](./academico/ANALISIS_BIBLIOGRAFIA_AMPLIADA.md)** — Bibliografía académica ampliada en APA 7 (ChatGPT), organizada por líneas de investigación.

## [`archive/`](./archive/) — registro histórico, contenido superseded

- **[CONTEXTO_PENDIENTE_MESA.md](./archive/CONTEXTO_PENDIENTE_MESA.md)** — Nota de contexto puntual sobre la decisión de Mesa/LLVM (Opción B); su contenido ya está volcado en `PENDIENTES.md`.
- **[GUIA_DESARROLLO_ORIGINAL.md](./archive/GUIA_DESARROLLO_ORIGINAL.md)** — La primera versión (resumida) de la visión de las 8 fases, anterior a `PILARES_FUNDACIONALES_LINSI-OS.md`.
- **[HANDOFF_COWORK_2026-09-04.md](./archive/HANDOFF_COWORK_2026-09-04.md)** — Handoff de una sesión anterior (Fase 6 Parte 2, Mesa/LLVM), de un entorno de trabajo (bridge de Cowork) distinto al actual. Todo lo técnico que describe ya está completo.
