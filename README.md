# Mantenimiento Mac 🚀

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://apple.com)
[![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20(M1%2FM2%2FM3%2FM4)-orange.svg)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138.svg)](https://swift.org)
[![Version](https://img.shields.io/badge/version-1.2.0-green.svg)](https://github.com/hamstersoftwarecol/mantenimientoMAC)
[![Organization](https://img.shields.io/badge/by-Hamster%20Software-purple.svg)](https://github.com/hamstersoftwarecol)

> **Mantenimiento Mac** es una utilidad nativa, rápida y segura diseñada para macOS (Apple Silicon). Permite auditar el software instalado, analizar y limpiar cachés de usuario de forma segura, y realizar desinstalaciones individuales o por lotes con inspección inteligente de residuos sin requerir permisos de superusuario (`sudo`).

Desarrollado y mantenido por **[Hamster Software](https://github.com/hamstersoftwarecol)**.

---

## ✨ Características Principales

- 🔍 **Auditoría completa de programas**: Inventario de aplicaciones locales (`/Applications`, `~/Applications`), aplicaciones del sistema y paquetes/casks de **Homebrew**.
- 🧹 **Limpieza segura de cachés**: Detección de cachés de aplicaciones (`~/Library/Caches` y Homebrew) con visualización de tamaño y traslado controlado a la Papelera (sin borrado permanente inmediato).
- 📦 **Desinstalación por lotes**: Selección múltiple de programas con comprobación de bloqueos (aplicaciones abiertas, apps del sistema y dependencias de Homebrew).
- 🕵️ **Revisión profunda de residuos**: Identificación precisa de datos residuales asociados por bundle ID (preferencias, Application Support, registros, estado guardado y cachés).
- 🛡️ **Seguridad por diseño**: No requiere privilegios de administrador, no fuerza eliminaciones destructivas y previene errores con dependencias activas.

---

## 📖 Guía de Uso

### Limpieza de cachés
1. Abre **Mantenimiento Mac.app** con doble clic desde esta carpeta.
2. Pulsa **Analizar mi Mac**. Esta operación solo lee información.
3. En **Programas instalados**, revisa aplicaciones y paquetes de Homebrew. Busca por nombre, ubicación u origen.
4. En **Cachés**, revisa tamaños y rutas. Cierra las aplicaciones cuyas cachés quieras limpiar y vuelve a analizar.
5. Selecciona únicamente los elementos que quieras limpiar y pulsa **Limpiar seleccionadas…**.
6. Revisa el resumen y confirma **Enviar a la Papelera**.

El espacio de los elementos trasladados no se libera hasta que vacías la Papelera desde Finder. La aplicación nunca la vacía. Puedes recuperar los elementos desde la Papelera mediante Finder. Las aplicaciones pueden volver a crear sus cachés.

## Desinstalar uno o varios programas

1. Analiza tu Mac y abre **Programas instalados**.
2. Marca las casillas de los programas que quieras desinstalar. También puedes usar ⌘ clic o Mayúsculas clic para selección múltiple. **Seleccionar resultados** agrega los programas que coinciden con la búsqueda; **Quitar selección** desmarca todos. La selección se conserva al buscar, y el contador y resumen incluyen también programas seleccionados que el filtro oculta.
3. Pulsa **Desinstalar N programas…**. Revisa los programas listos, los bloqueados y sus residuos agrupados. Se muestran rutas, tamaños y tipos: cachés, preferencias, registros, estado guardado y datos de la aplicación.
4. Marca únicamente los residuos que quieras quitar; todos empiezan sin seleccionar. Los perfiles y preferencias pueden ser útiles si reinstalas el programa.
5. Pulsa **Revisar resumen…** y revisa el orden de programas y las rutas seleccionadas. Los programas bloqueados se muestran como omitidos.
6. Confirma una sola vez con **Desinstalar N programas**. La aplicación ejecutará el lote secuencialmente y mostrará el resultado de cada programa; luego actualizará el inventario.

**Seleccionar cachés** en la revisión marca solo las cachés elegibles de los programas listos. No marca datos ni preferencias. Puedes añadir otros residuos individualmente antes de revisar el resumen.

Un fallo de un programa no impide procesar los siguientes. **Detener lote** conserva los programas que aún no comenzaron: termina primero la operación del programa actual y sus residuos seleccionados. No interrumpe un desinstalador de Homebrew en marcha.

Las aplicaciones locales de `/Applications` y `~/Applications` y los residuos seleccionados se envían a la Papelera. Las aplicaciones de macOS, esta herramienta y aplicaciones abiertas se bloquean. La herramienta no solicita privilegios ni cierra otros programas.

Los paquetes de Homebrew se desinstalan con Homebrew: **el paquete puede eliminarse sin pasar por la Papelera** y los casks pueden ejecutar su propio desinstalador. La herramienta no fuerza el borrado de dependencias, no usa `--zap` ni `--ignore-dependencies`, y desactiva el autoremove. Si una fórmula tiene dependientes, solo se permite continuar cuando todos ellos también están seleccionados y listos: se desinstalan primero los dependientes. Un dependiente no seleccionado, bloqueado o que permanece instalado tras un fallo mantiene la protección. Las comprobaciones se repiten antes de cada programa. Los casks que instalan varias aplicaciones o cuyo destino no pueda verificarse se derivan a Homebrew para revisar su alcance completo. Se bloquea también una aplicación aparentemente local si Homebrew registra un destino o nombre de aplicación coincidente que no se ha verificado. Si un desinstalador requiere permisos o interacción externa, la operación puede fallar; se informa y se conservan los residuos. Consulta el [manual oficial de Homebrew](https://docs.brew.sh/Manpage) para su comportamiento de desinstalación.

Los residuos se buscan por identificador exacto de la aplicación en carpetas específicas de tu `Library`. También se muestran coincidencias exactas por nombre en Application Support y Logs con un aviso de posible uso compartido. No se exploran documentos, Group Containers ni carpetas arbitrarias. Si otra instalación usa el mismo identificador, se conservan los residuos compartidos. **No encontrar residuos no garantiza que no existan archivos en otras ubicaciones.**

Si la desinstalación falla, no se trasladan sus residuos. Si falla un traslado posterior, se informa qué residuo no se pudo quitar. Un error o tiempo límite de Homebrew puede dejar una operación parcial: revisa el inventario y el mensaje antes de reintentar.

## Alcance

- Aplicaciones en `/Applications`, `~/Applications` y `/System/Applications`, incluidas subcarpetas; no busca todas las aplicaciones que puedas guardar en otras ubicaciones.
- Fórmulas y casks instalados de Homebrew, leído desde sus ubicaciones habituales para Apple Silicon e Intel. El análisis no actualiza Homebrew ni desinstala paquetes.
- Entradas de `~/Library/Caches` y la caché que devuelve Homebrew si está dentro de tu carpeta de usuario y se llama `Homebrew`. Las rutas simbólicas se excluyen.
- Asociación de cachés por identificador exacto de la aplicación; las demás se muestran como **Sin identificar**. Los orígenes no verificados se muestran como **Aplicación local**.
- Tamaño lógico estimado; puede diferir del espacio físico ocupado. Una medición incompleta y los errores de permisos aparecen explícitamente.

La limpieza de cachés no analiza cachés del sistema, datos en contenedores, documentos, contraseñas ni configuraciones. El análisis de desinstalación sí puede mostrar preferencias y datos de contenedores con identificador exacto, siempre sin seleccionarlos. No pide permisos de administrador. No limpia al abrirse ni ejecuta tareas programadas. Usa el mismo acceso a archivos que tu usuario; las restricciones de privacidad de macOS pueden impedir algunas lecturas. Revisa **Ver incidencias** o las observaciones de desinstalación para saber qué no se pudo analizar.

Los elementos asociados a aplicaciones abiertas se bloquean cuando se puede comprobar su identificador. Las entradas **Sin identificar** pueden estar siendo usadas: verifica la ruta y cierra el programa correspondiente antes de seleccionarlas.

## Desarrollo

Se necesitan las herramientas de desarrollo de Apple. No hay dependencias externas.

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

La suite crea aplicaciones y datos temporales y simula el traslado en un destino temporal. Simula Homebrew en la frontera de procesos para verificar los argumentos, dependientes, fallos y verificación posterior. No limpia cachés reales, desinstala programas reales ni vacía la Papelera. La aplicación tiene firma ad hoc para uso local; no es una distribución notarizada por Apple.
