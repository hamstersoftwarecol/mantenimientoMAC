# Desinstalación Implementation Plan

> **For agentic workers:** Implementación inline con pruebas antes del código y revisión independiente final.

**Goal:** Añadir desinstalación con análisis y selección de residuos a la aplicación local existente.

**Architecture:** El inventario conserva identidad de Homebrew; Uninstaller analiza y valida archivos y ejecuta una operación local o Homebrew por una frontera inyectable. SwiftUI presenta análisis, selección, confirmación y resultados.

**Tech Stack:** Swift, SwiftUI, Foundation y AppKit existentes, sin nuevas dependencias.

**Spec:** docs/superpowers/specs/2026-10-13-desinstalacion-design.md

## Global Constraints

- No ejecutar desinstalaciones reales durante las pruebas.
- Sin privilegios, force, ignore-dependencies, zap ni autoremove.
- Residuos sin selección inicial; no limpiar si la desinstalación falla.
- Revalidar identidades y rutas, bloquear programas abiertos y sistema.

## Tareas

1. Inventario: añadir tipo/token de Homebrew y ejecutable de aplicación; probar conservación al leer y fusionar casks.
2. Análisis: construir candidatos limitados por identidad, medirlos, bloquear duplicados y registrar incidencias. Pruebas con Library temporal y enlaces externos.
3. Ejecución: comprobar identidad/app abierta/dependientes; trasladar selección a destino temporal en tests y construir comandos Homebrew sin opciones destructivas adicionales. Probar errores sin limpiar residuos.
4. Interfaz: selección de programa, análisis cancelable, residuos con tipos, resumen y confirmación, resultados y actualización. Compilar y probar UI sin pulsar confirmación final.
5. Revisión independiente, suite y firma final; actualizar README y versión.

## Verificaciones

`zsh scripts/test.sh` debe probar comportamientos usando fixtures, observar las fallas antes de implementar cada bloque y terminar sin fallos. `zsh scripts/build.sh` debe generar bundle arm64 válido y firma ad hoc comprobable. Las comprobaciones manuales usan aplicaciones instaladas solo para lectura.

## Resultado

Tareas 1–5 completadas. Suite de 43 comprobaciones aprobada; aplicación 1.1.0 compilada y firmada. Revisión independiente: artefactos relativos de casks corregidos con tres pruebas que fallaron antes de la corrección y pasaron después. UI de revisión y confirmación comprobada y cancelada, sin ninguna desinstalación real. Alcance y límites documentados en README.md y docs/verification.md.
