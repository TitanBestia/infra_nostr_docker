# Instrucciones

El repositorio se parte de cero. No se entrega un script para completar: la tarea consiste en escribirlo. Los pasos siguientes indican qué debe hacer cada parte y por qué, no las líneas exactas a copiar.

## 1. Descargar y levantar las imágenes

Las dos imágenes ya están publicadas en Docker Hub y no requieren construcción. El relay es `scsibug/nostr-rs-relay` y el cliente es `bracr10/coracle`.

Se descargan con `docker pull` y se levantan con `docker run`, cada uno en segundo plano y publicando su puerto hacia la máquina anfitriona. Consultar la página de cada imagen en Docker Hub para determinar qué puerto expone internamente.

Ambos contenedores deben conectarse a una misma red creada con `docker network create`. Sin esa red no existe comunicación entre los componentes, que es justamente lo que evalúa la práctica.

## 2. Configurar la descripción del relay

El relay lee su configuración de un archivo `config.toml`, donde se define la descripción con la que se presenta ante los clientes. Debe decir exactamente `Relay local de practica para Docker - USUARIO`, reemplazando `USUARIO` por el usuario de GitHub propio. Eso hace que la evidencia sea única y no pueda copiarse de otro compañero.

Existen dos formas de hacer llegar ese archivo al contenedor:

- **Montarlo desde el disco.** Se enlaza el archivo local con la ruta que el relay espera dentro del contenedor, al momento de crearlo. Es la más simple y deja la configuración versionada en el repositorio.
- **Copiarlo al contenedor ya creado.** Se copia con `docker cp` y se reinicia el contenedor. Funciona, pero se pierde al eliminar el contenedor y hay que repetirlo en cada despliegue.

Cualquiera de las dos es válida.

## 3. Escribir y ejecutar el script de despliegue

Todo lo anterior se automatiza en un script que crea la red, descarga las imágenes y levanta ambos contenedores.

Conviene incorporar una pausa después de arrancar cada contenedor. Un contenedor recién creado no responde de inmediato, y sin esa espera el script puede anunciar un despliegue correcto cuando el servicio todavía no está listo.

Antes de ejecutarlo hay que otorgar permisos de ejecución con `chmod +x`. Un archivo `.sh` recién creado no es ejecutable y el sistema responde `Permission denied`. Lo mismo aplica al script de limpieza.

## 4. Verificar en el cliente

Abrir en el navegador el puerto de la máquina anfitriona donde quedó corriendo el cliente web. En la barra izquierda ingresar a **Relays**, ubicar el relay correspondiente a `localhost` y pulsar **Info**.

Si allí aparece la descripción configurada en el paso 2, el relay está bien desplegado y bien configurado. Esa es la evidencia de la tarea.

## 5. Escribir el script de limpieza

Se escribe un segundo script, separado del anterior, que detenga y elimine ambos contenedores y borre la red.

Van separados a propósito: la limpieza se ejecuta muchas veces durante las pruebas, y además el despliegue falla si los contenedores ya existen, por lo que limpiar es el paso previo natural para volver a empezar.

## 6. Ejecutar la limpieza y comprobar

Ejecutar el script de limpieza y verificar que no quedó nada, listando los contenedores y las redes existentes.

## Contenido del repositorio

- Script de despliegue.
- Script de limpieza.
- Archivo `config.toml` con la descripción personalizada.
- Documentación con los requisitos previos, el orden de ejecución de los scripts y la URL donde se accede al cliente web.
