# Guía: demostración desde la interfaz de Couchbase

## Antes de empezar

Inicia los tres contenedores desde Docker Desktop. Comprueba que `couchbase-node1`, `couchbase-node2` y `couchbase-node3` estén ejecutándose.

Abre la consola de cualquiera de los nodos e inicia sesión con las credenciales del clúster. Para la configuración de demostración son `Admin` / `Admin1`.

- Nodo 1: <http://localhost:8091>
- Nodo 2: <http://localhost:18091>
- Nodo 3: <http://localhost:28091>

> Couchbase administra el clúster y los datos desde su consola web, pero la interfaz no puede detener el contenedor Docker que representa un nodo. Para simular una falla, usa Docker Desktop para detener el contenedor. Los nodos 2 y 3 tienen sus propias direcciones de consola; si se detiene el nodo 1, abre la URL de uno de ellos.

## Si el clúster todavía no está configurado

1. En la pantalla inicial, selecciona **Setup New Cluster**.
2. Introduce el nombre del clúster y las credenciales de administrador.
3. Selecciona los servicios **Data**, **Index** y **Query**.
4. Completa la configuración inicial del nodo 1.
5. Ve a **Servers** y selecciona **Add Server**.
6. Agrega `couchbase-node2.demo.test` y `couchbase-node3.demo.test`, con las credenciales configuradas para esos nodos y los servicios **Data**, **Index** y **Query**.
7. Cuando los tres servidores aparezcan como pendientes, selecciona **Rebalance** y espera a que termine.
8. En **Settings** > **Auto-Failover**, habilita el failover automático, configura el tiempo de espera en `30` segundos y el máximo de failovers en `1`.

Si la consola no acepta los nombres de host, o si Couchbase anuncia direcciones IP en lugar de los nombres `*.demo.test`, detén la configuración y sigue los pasos de inicialización de nombres de nodo de `GUIA-COMPLETA.md`.

## Crear el bucket

1. Abre **Buckets** y selecciona **Add Bucket**.
2. Escribe `demo-bucket` como nombre.
3. Selecciona el tipo **Couchbase**.
4. Configura la cuota de memoria y establece **Replicas** en `1`.
5. Crea el bucket.

## Cargar los documentos

La consola web no carga directamente el archivo `data\productos.json` usando el script del proyecto. Ejecuta `.\cargar-datos.ps1` desde PowerShell, como indica `GUIA-COMPLETA.md`. Después vuelve a la consola web.

## Crear el índice y consultar los productos

1. Abre **Query**.
2. Ejecuta:

   ```sql
   CREATE INDEX IF NOT EXISTS idx_producto_tipo
   ON `demo-bucket`(tipo)
   WHERE tipo = "producto"
   WITH {"num_replica": 1};
   ```

3. Abre **Indexes** y espera a que el índice y su réplica aparezcan **Online**.
4. En **Query**, ejecuta y anota el resultado:

   ```sql
   SELECT COUNT(*) AS total_productos
   FROM `demo-bucket`
   WHERE tipo = "producto";
   ```

5. Ejecuta esta consulta para mostrar algunos documentos:

   ```sql
   SELECT META(d).id AS id, d.nombre, d.categoria, d.precio, d.stock
   FROM `demo-bucket` AS d
   WHERE d.tipo = "producto"
   LIMIT 5;
   ```

## Simular la caída del nodo 2

1. Deja abierta la consola de Couchbase en el nodo 1.
2. En Docker Desktop, abre el proyecto y detén únicamente el contenedor `couchbase-node2`. No detengas ni elimines los otros contenedores.
3. En Couchbase, abre **Servers** y espera a que el nodo 2 aparezca como fallido. El failover puede tardar más que los 30 segundos configurados.
4. Cuando Couchbase haya completado el failover, vuelve a **Query**.
5. Ejecuta otra vez el `COUNT(*)` y la consulta de muestra. El conteo esperado es de al menos `1000`.
6. Si una consulta falla durante la detección o el failover, espera a que **Servers** muestre el nodo como fallido y vuelve a intentarlo. No inicies un failover manual.

## Mantener acceso a la consola si se detiene el nodo 1

1. Antes de detener el nodo 1, confirma que los nodos 2 y 3 estén activos.
2. En Docker Desktop, detén únicamente `couchbase-node1`.
3. La dirección <http://localhost:8091> dejará de responder. Abre la consola en <http://localhost:18091> (nodo 2) o <http://localhost:28091> (nodo 3).
4. Inicia sesión si hace falta, espera a que **Servers** refleje el failover y ejecuta las consultas desde **Query**.
5. Para devolver el nodo 1, sigue **Recuperar el nodo 2** cambiando el nombre del contenedor y del servidor por `couchbase-node1`.

La interfaz no migra automáticamente entre nodos ni mantiene necesariamente la pestaña anterior conectada. Debes abrir la dirección de otro nodo; estas direcciones son accesos alternativos, no un balanceador.

## Recuperar el nodo 2

1. En Docker Desktop, inicia de nuevo `couchbase-node2`.
2. En **Servers**, comprueba si el nodo vuelve a estar activo o si aparece como fallido y fuera del clúster.
3. Si la consola ofrece una opción **Recover** para ese nodo, selecciónala y elige recuperación delta/incremental cuando esté disponible.
4. Si el nodo se muestra activo, espera a que termine su sincronización; no lo agregues otra vez.
5. Si la consola no ofrece la recuperación o no permite completar el rebalanceo, usa los comandos de recuperación de la sección 12 de `GUIA-COMPLETA.md`.
6. Espera a que los tres nodos aparezcan activos y el rebalanceo termine.
7. En **Query**, ejecuta de nuevo `COUNT(*)` y confirma que los productos siguen disponibles.
