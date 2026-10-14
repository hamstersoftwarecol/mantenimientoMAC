# Mantenimiento Mac — diseño

Diseño basado en la propuesta aprobada: aplicación local con ventana en español, inventario de programas, análisis de cachés y limpieza por selección y confirmación.

## Entrega y plataforma

Aplicación nativa para macOS 13 o posterior, compilada para Apple Silicon en este equipo. Se entregará `Mantenimiento Mac.app` en la carpeta del proyecto, junto con fuentes e instrucciones. SwiftUI y Foundation, sin dependencias externas ni conexión de red. No se instala automáticamente ni se ejecuta al iniciar sesión.

## Ventana y flujo

Dos pestañas: «Programas instalados» y «Cachés». El usuario pulsa «Analizar» para actualizar ambas. La ventana muestra progreso y mantiene la interacción disponible mientras trabaja en segundo plano. No analiza ni borra nada al abrirse.

El inventario muestra nombre, versión disponible, origen y ubicación; permite buscar por nombre. Examina /Applications, ~/Applications y /System/Applications, incluyendo subcarpetas habituales. Identifica aplicaciones por sus metadatos .app y deduplica por ruta. Consulta Homebrew con procesos separados y argumentos explícitos: lista de fórmulas y casks instalados en JSON, sin actualizar Homebrew. Detecta brew en /opt/homebrew/bin/brew y /usr/local/bin/brew. Relaciona los casks con aplicaciones solo cuando sus artefactos ofrecen evidencia suficiente; en otro caso conserva las entradas separadas. «Aplicación local» significa que no se verificó una asociación con Homebrew; no identifica con certeza el instalador original. Las fórmulas aparecen como paquetes y herramientas, aunque no tengan ventana.

La pestaña de cachés muestra ubicación, propietario identificado o «Sin identificar», tamaño estimado y estado. Orden inicial por tamaño descendente. Todas las filas empiezan sin seleccionar. El usuario puede buscar, seleccionar filas y ver el total estimado seleccionado. Un tamaño incompleto se etiqueta y nunca se presenta como medición exacta.

## Alcance del análisis

Se examinan entradas inmediatas de ~/Library/Caches y, si Homebrew está disponible, su carpeta de caché obtenida con `brew --cache`. Se deduplican rutas solapadas. Se relacionan carpetas con aplicaciones por coincidencia exacta del identificador del bundle, o con Homebrew por su raíz verificada. No se adivina el propietario a partir de similitudes de nombre.

No se exploran caches del sistema, /Library/Caches, contenedores de aplicaciones, Application Support, navegadores fuera de Library/Caches, documentos ni configuraciones. La ventana explica ese alcance. Los errores de permisos y de lectura se muestran como incidencias; una carpeta inaccesible no cuenta como cero bytes.

El cálculo usa tamaños de archivos regulares, omite enlaces simbólicos y no recorre sus destinos. Es una estimación del contenido lógico, no una promesa de espacio físico recuperado. Se permite detener un análisis. Los procesos de Homebrew tienen tiempo límite y sus errores no impiden ver las aplicaciones locales.

## Limpieza y límites

«Limpiar seleccionadas» abre un resumen de rutas, cantidad y tamaño estimado. La confirmación explica que las aplicaciones pueden volver a crear las cachés y que conviene cerrarlas primero. Se excluyen cachés asociadas a aplicaciones actualmente abiertas cuando se puede verificar su identificador. Las cachés sin propietario permanecen claramente marcadas; requieren selección expresa como todas las demás.

Tras confirmar, se vuelven a validar las rutas. Solo se permiten hijos directos de las raíces de caché aprobadas, nunca la raíz misma. Se rechazan enlaces simbólicos en la entrada y en sus ancestros y rutas que escapen de las raíces. La operación mueve las entradas seleccionadas a la Papelera mediante la API de macOS; nunca vacía la Papelera ni usa borrado permanente. Si el traslado falla, muestra el error sin sustituirlo por borrado permanente. Se indica que el espacio en disco no se libera hasta vaciar la Papelera, una acción externa al programa.

El resultado informa qué entradas se trasladaron y cuáles fallaron. Después se actualiza el análisis. No solicita privilegios de administrador, no desinstala programas y no ejecuta comandos de mantenimiento generales. El programa registra resultados de la operación en pantalla, sin guardar un inventario persistente por defecto.

## Organización interna

Modelos compartidos para aplicaciones, paquetes, entradas de caché e incidencias. Un servicio de inventario lee aplicaciones y Homebrew; otro mide cachés; otro valida y mueve entradas a la Papelera. El estado de la ventana coordina tareas y resultados. La seguridad de rutas se mantiene independiente de la interfaz para probarla con carpetas temporales.

## Verificación

Pruebas con archivos temporales para tamaños, cachés parcialmente ilegibles cuando sea reproducible, deduplicación, rechazo de raíces, rutas externas y enlaces simbólicos. Pruebas de lectura de JSON de Homebrew con ejemplos de fórmulas y casks. Prueba de la limpieza únicamente en una carpeta temporal de caché autorizada por el entorno de prueba, nunca en cachés reales del usuario. Compilación de la aplicación y revisión de la ventana con inventario y análisis reales de solo lectura si los permisos lo permiten. Ninguna limpieza real forma parte de la verificación.
