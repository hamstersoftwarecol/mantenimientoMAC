# Mantenimiento Mac Implementation Plan

> **For agentic workers:** Ejecutar en esta sesión, usando pruebas antes de implementar y revisión final.

**Goal:** Entregar una aplicación nativa en español para inventariar aplicaciones y analizar y trasladar cachés seleccionadas a la Papelera.

**Architecture:** Servicios Foundation separados para inventario, medición y validación; SwiftUI coordina tareas fuera del hilo principal. Una política de rutas restringe cada traslado a hijos directos de raíces verificadas.

**Tech Stack:** Swift 5 compatible, SwiftUI, AppKit, Foundation; compilación con swiftc, sin descargas.

**Spec:** docs/superpowers/specs/2026-10-13-limpiador-mac-design.md

## Global Constraints

- macOS 13 o posterior; interfaz en español.
- Solo cachés del usuario y Homebrew; nunca borrar permanentemente ni vaciar Papelera.
- Análisis cancelable, sin ejecutar al abrir; inventario sin actualizar Homebrew.
- Ninguna limpieza real durante la verificación.

## Task 1: Medición y seguridad

Files: Sources/Core.swift, Tests/main.swift, scripts/test.sh.
Interfaces: CachePolicy.validate(URL); CacheScanner.measure(URL, cancellation); Measurement(bytes, incomplete).

- [x] Escribir pruebas de un directorio de 11 bytes con enlace externo de 100 bytes; esperar 11, sin recorrer enlace.
- [x] Probar rechazo de raíz, hijo anidado, ruta externa y enlace; permitir hijo inmediato.
- [x] Ejecutar scripts/test.sh; comprobar falla de las capacidades aún no implementadas.
- [x] Implementar validación por componentes, rechazo de enlaces en ancestros y medición cancelable.
- [x] Ejecutar scripts/test.sh; esperar todas las pruebas aprobadas.

## Task 2: Inventario y análisis

Files: Sources/Inventory.swift, Sources/Analysis.swift, Tests/main.swift.
Interfaces: Inventory.scan(cancelled) -> InventoryResult; BrewParser.parse(Data) -> [InstalledProgram]; Analysis.scan(cancelled, progress) -> ScanResult.

- [x] Probar JSON con fórmula instalada, cask con artefacto .app y JSON inválido; probar carpeta .app temporal con Info.plist.
- [x] Ejecutar pruebas antes de implementar parser y lector.
- [x] Implementar listado local, procesos con límite de tiempo, parsers y asociación exacta por identificador/artefacto.
- [x] Implementar raíces de cachés sin solapamientos, incidencias y orden por bytes.
- [x] Ejecutar pruebas y análisis de solo lectura con ejecutable diagnóstico.

## Task 3: Ventana y entrega

Files: Sources/App.swift, Sources/Cleaner.swift, scripts/build.sh, README.md, Resources/Info.plist.
Interfaces: Cleaner.clean(entries, roots, runningBundles) -> [CleanOutcome]; ViewModel usa ScanResult.

- [x] Probar selección inválida que no altera archivo externo; probar traslado de archivo temporal a una carpeta de destino temporal mediante operación inyectada (la operación de producción usa trashItem).
- [x] Implementar limpieza con revalidación e identificación de aplicaciones abiertas.
- [x] Implementar dos pestañas, búsqueda, progreso/cancelación, selección sin valores preseleccionados, confirmación con rutas y resultados.
- [x] Compilar .app local con deployment target macOS 13 y firma ad hoc; comprobar bundle.
- [x] Revisar ventana usando herramientas disponibles; documentar cualquier límite de revisión visual.
- [x] Revisar código, ejecutar suite final y entregar enlace a aplicación y guía.

## Decisiones de ejecución

La carpeta es un proyecto nuevo sin repositorio Git. Se trabaja directamente en la carpeta autorizada; no se crea un worktree ni se realizan commits ficticios. Se ejecuta inline para completar la implementación ya autorizada sin otra ronda de selección de método.
