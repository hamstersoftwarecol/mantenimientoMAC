# Desinstalación por lotes Implementation Plan

**Goal:** Seleccionar varios programas, revisar sus residuos conjuntamente y ejecutar la desinstalación automáticamente tras una sola confirmación.

**Architecture:** Reutilizar las reglas de Uninstaller para cada programa. Un plan de lote conserva los planes individuales y el orden de ejecución; el coordinador ejecuta secuencialmente con revalidación y resultados por programa. SwiftUI ofrece casillas y selección múltiple, revisión agrupada y resumen único.

**Spec:** Ampliación del flujo aprobado en docs/superpowers/specs/2026-10-13-desinstalacion-design.md, autorizada en conversación.

## Reglas

- Nada se desinstala durante análisis ni pruebas reales.
- Los residuos empiezan sin seleccionar; la revisión y confirmación incluyen todos los programas, incluso selecciones ocultas por búsqueda.
- Los programas bloqueados se muestran y se omiten. Un error de un programa no impide procesar los demás.
- Los paquetes Homebrew seleccionados que dependen entre sí se ordenan dependientes primero, sin forzar dependencias; un dependiente externo mantiene el bloqueo. La protección se vuelve a comprobar en cada ejecución.
- Los residuos compartidos entre planes se conservan y se explica la omisión.
- «Detener lote» detiene antes del siguiente programa, sin interrumpir un desinstalador en marcha.

## Tareas

1. Escribir pruebas de lote para dos aplicaciones, deduplicación, conservación de datos no seleccionados, fallo aislado, selección externa rechazada y cancelación entre programas; observar fallos e implementar coordinador.
2. Probar e implementar orden de dependencias seleccionadas y bloqueo por dependientes externos.
3. Sustituir selección simple por múltiple y casillas; adaptar la revisión a grupos con un único resumen y confirmación.
4. Incorporar progreso y resultados por programa, actualización final del inventario y parada entre programas.
5. Compilar versión 1.2.0, revisión independiente, comprobar selección múltiple/revisión/cancelación en UI, ejecutar suite completa y actualizar guía.

## Validación

`zsh scripts/test.sh`: solo aplicaciones/datos temporales y frontera Homebrew simulada. `zsh scripts/build.sh`: aplicación arm64 macOS 13 y firma local verificada. En UI se cancela antes de confirmar sobre aplicaciones instaladas.

## Resultado

Tareas completadas. 54/54 pruebas y revisión independiente sin hallazgos. Versión 1.2.0 compilada y firmada. Se comprobaron casillas, selección de dos programas al filtrar y revisión agrupada en UI; la comprobación posterior del resumen se cruzó con acciones simultáneas del usuario y no se automatizó la confirmación final. Véase docs/verification.md para la evidencia y sus límites.
