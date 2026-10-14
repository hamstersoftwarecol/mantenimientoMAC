# Desinstalación y revisión de residuos

Ampliación aprobada en conversación: botón «Desinstalar…» en programas, análisis previo de residuos, selección explícita, confirmación y resultado. La implementación continúa en la carpeta autorizada; no se desinstala ninguna aplicación real durante las pruebas.

## Flujo

Seleccionar un programa en el inventario y abrir «Desinstalar…». El análisis muestra rutas, tipos, tamaños incompletos e incidencias. Todos los residuos empiezan sin seleccionar. El paquete/aplicación es el objetivo de desinstalación; los residuos son opcionales. Se presenta un resumen separado antes de ejecutar. Una operación ocupada bloquea otros análisis/limpiezas.

Las aplicaciones locales se envían a la Papelera. Los paquetes Homebrew se desinstalan usando su token y tipo verificados y sin opciones force, ignore-dependencies, zap ni autoremove. El texto explica que Homebrew puede eliminar el paquete sin pasar por la Papelera y ejecutar el desinstalador de su cask. Las fórmulas con dependientes instalados se bloquean y se vuelven a comprobar al ejecutar. Si una desinstalación falla, no se trasladan sus residuos. Después se actualiza el inventario y se muestra cada resultado.

## Asociación de archivos

Identificador exacto de bundle para hijos de Library/Caches, Library/Logs, Library/Application Support, Library/Containers, Library/Preferences (id.plist), Library/Saved Application State (id.savedState). En Application Support y Logs se muestran adicionalmente coincidencias exactas con el nombre/executable de la app como posibles residuos, con aviso de posible uso compartido, sin seleccionar. Nunca se deduce propiedad por un prefijo de proveedor ni se exploran Group Containers, documentos o directorios arbitrarios.

Los containers y Application Support pueden contener datos personales y se etiquetan como datos. Preferencias pueden contener configuración y se etiquetan explícitamente. Ninguna coincidencia de nombre es garantía de propiedad exclusiva: el usuario revisa rutas. Se omite la limpieza de residuos si hay otro bundle instalado con el mismo identificador. Las fórmulas sin aplicación asociada no reciben residuos inferidos.

## Seguridad

Se bloquean componentes de macOS, identificadores com.apple.*, esta herramienta y aplicaciones abiertas (incluida coincidencia por ruta real). Se rechazan enlaces en aplicaciones/residuos y ancestros. El programa no pide privilegios ni cierra aplicaciones automáticamente.

Al ejecutar se valida de nuevo la identidad del bundle, tipo/token Homebrew y que el paquete continúa instalado. Los residuos deben figurar en el análisis y pertenecer al conjunto recalculado de candidatos exactos permitidos. Raíces, rutas externas y archivos sustituidos se rechazan. La aplicación local debe estar bajo /Applications o ~/Applications; otros destinos de Homebrew se gestionan solo a través de Homebrew.

Para Homebrew se conservan token, tipo y destino dentro del modelo, incluyendo al fusionar casks con .app. Se desactiva auto actualización, analytics y autoremove. Se comprueba el resultado y se permite un tiempo mayor para el comando de desinstalación. No se cancela un desinstalador en marcha desde la UI; un tiempo límite se informa como estado incierto y no provoca limpieza de residuos.

## Pruebas y entrega

Pruebas con aplicaciones, preferencias y datos temporales: candidatos exactos, selección no predeterminada, conservación de datos no seleccionados, bloqueos de programas abiertos/sistema/identidad modificada, enlaces, externos y dependientes. Homebrew se simula en la frontera de procesos con argumentos capturados; nunca se ejecuta uninstall durante la verificación. Compilación y revisión visual del análisis y confirmación, cancelando antes de ejecutar en aplicaciones reales. Versión 1.1.0 de Mantenimiento Mac.app y guía actualizada.
