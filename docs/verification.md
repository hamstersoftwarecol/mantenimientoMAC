# Verificación de la primera versión

## Proceso

Proyecto nuevo en la carpeta autorizada, sin repositorio Git. Se implementó directamente después de aprobación del diseño y del documento. No se realizó instalación en /Applications.

## Evidencia

Suite final: **21/21 comprobaciones aprobadas**. La revisión independiente no encontró otros errores demostrables después del hallazgo de los destinos de casks.

- Ciclo de pruebas primero: validación/medición falló inicialmente 3 de 10 casos; tras implementar y corregir el manejo de rutas todas aprobaron.
- Foundation estandariza algunas rutas `/private/tmp` como `/tmp`, introduciendo un enlace de sistema. La política conserva componentes literales de las rutas y verifica ancestros en lugar de depender de esa estandarización.
- Parser y lectura de metadatos fallaron inicialmente 4 casos; después pasaron 14/14.
- Análisis y traslado controlado fallaron inicialmente 4 casos; después pasaron 19/19.
- Revisión independiente encontró que los casks debían conservar destinos explícitos. Se reprodujo con un artefacto renombrado en `/Custom/Apps/Renamed.app`; se corrigió el parser y se usa asociación por destino absoluto verificado. Sin destino absoluto se conserva el cask como entrada independiente.
- Se corrigió la representación de cero bytes para evitar la palabra inglesa «Zero».
- Pruebas de límites: raíz, hijo anidado, ruta externa, enlace seleccionado, ancestro simbólico, cancelación y tiempo límite del proceso.
- Limpieza: operación inyectada que mueve un elemento temporal a una carpeta temporal; prueba de conservación de datos externos y bloqueo de aplicación abierta. No se probó un borrado permanente ni se limpió ninguna caché real.
- Compilación arm64 para macOS 13, bundle local y firma ad hoc verificada. El compilador de SwiftUI requirió autorización para ejecutarse fuera del sandbox.
- Revisión visual de la ventana inicial y del análisis terminado. Resultado de solo lectura observado: 249 programas/paquetes, 107 entradas de caché, aproximadamente 4,11 GB y 12 incidencias. Son mediciones de ese momento, no un inventario completo de todas las ubicaciones del disco.

## Límites

La confirmación y la revalidación de rutas reducen errores de selección. La API de Papelera trabaja por ruta, por lo que no ofrece una transacción atómica entre la comprobación y el traslado frente a una sustitución concurrente por otro proceso. No se pretende proteger frente a procesos maliciosos del mismo usuario.

No se verificó visualmente en macOS 13 ni en otro Mac; se compiló con ese mínimo de plataforma y se probó en el equipo actual. No se verificó un traslado de caché real a la Papelera; se verificó la misma lógica de selección y validación con un destino temporal controlado.

## Ampliación 1.1.0: desinstalación

- Se añadieron 22 comprobaciones; suite completa: 43/43 aprobadas.
- Antes de implementar, 12 casos nuevos fallaron por ausencia de las capacidades de desinstalación. Se comprobaron traslado de aplicación local, selección de residuos, conservación de datos no seleccionados, bloqueo por ruta de aplicación abierta, cambios de metadatos, enlaces sustituidos, protección de macOS y de la propia herramienta, e identificadores compartidos.
- Homebrew se verificó mediante una frontera de procesos controlada: argumentos de uninstall por tipo/token, rechazo de tokens que parecen opciones, dependencia instalada que aparece después del análisis, comprobación posterior y fallo de cask sin trasladar sus residuos. Nunca se ejecutó `brew uninstall` durante la verificación.
- La revisión independiente encontró un fallo con artefactos relativos de casks. Se reprodujeron tres fallos y se corrigieron: cask de destino no verificado, cask multiaplicación y una aplicación aparentemente local que Homebrew registra por nombre. Ahora se bloquean estos casos; no se infiere un destino de instalación por parecido.
- Se revisó visualmente la nueva selección de programa, análisis de residuos, selección inicial vacía y resumen de confirmación usando una aplicación instalada solo para lectura. Se canceló desde el resumen; no se pulsó Confirmar desinstalación. La aplicación seguía presente en el inventario.
- Bundle actualizado a versión 1.1.0 y firma ad hoc verificada. Se conserva el formato arm64 para macOS 13 o posterior.

Limitaciones de esta ampliación: la búsqueda de residuos está restringida a rutas concretas de Library e identificadores/nombres exactos; no garantiza localizar todos los archivos de cualquier programa. Los casks sin destino de aplicación verificable, con varias aplicaciones o que requieren interacción/permisos externos necesitan gestionarse directamente con Homebrew. La operación real de Homebrew y la API de Papelera no se ejecutaron sobre programas instalados del usuario como parte de estas pruebas.

## Ampliación 1.2.0: lotes

- Suite completa: 54/54 comprobaciones aprobadas. Ocho casos de lote fallaron inicialmente antes de implementar el coordinador; el caso de dependencias seleccionadas falló antes de añadir el orden de ejecución.
- Verificado con fixtures: dos aplicaciones locales, deduplicación, conservación de datos no seleccionados, fallo aislado que permite continuar, selección externa que rechaza todo el lote, aplicación abierta omitida, cancelación entre programas, y selección de un residuo.
- Homebrew simulado: dependiente seleccionado se procesa antes de la dependencia; dependiente externo o protegido mantiene el bloqueo. La ejecución conserva las comprobaciones individuales y no pasa cancelación al desinstalador en marcha.
- Revisión independiente sin hallazgos accionables; el revisor también ejecutó las 54 pruebas.
- Interfaz: columna de casillas y selección múltiple comprobadas en aplicación compilada. Se verificó que una aplicación seleccionada permanece contada al buscar otra, que el contador llega a dos y que la revisión agrupa ambas con residuos sin seleccionar.
- Para evitar modificar la selección de la ventana del usuario se abrió una copia con el mismo ejecutable e identificador distinto en build/Mantenimiento Prueba.app. Hubo interacción simultánea del usuario en ambas ventanas; la automatización rechazó algunos clics por cambios de estado. El agente no pulsó la confirmación final de desinstalación. La ventana mostró posteriormente un resultado de lote iniciado fuera de las acciones del agente. No se atribuye esa operación a la suite automatizada.
- Bundle principal 1.2.0 compilado para arm64/macOS 13 y firma verificada. Guía actualizada con selección al filtrar, revisión única, omisión de bloqueados y detención después del programa actual.
