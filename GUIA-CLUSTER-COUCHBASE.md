# Guía: clúster Couchbase de tres nodos con Docker Compose

Estos pasos están pensados para ejecutarse desde PowerShell, en la carpeta que contiene `docker-compose.yml`. El nodo 1 inicializa el clúster; los nodos 2 y 3 se agregan a ese mismo clúster. No son tres clústeres separados.

> **Importante:** en este ejemplo se usa `Admin` / `Admin1`, que son credenciales de demostración. Cámbialas por credenciales seguras si el entorno no es desechable. Usa la misma contraseña en los comandos de los tres nodos.

## 1. Revisar los nombres de los nodos

El archivo Compose configura estos nombres DNS completos:

- `couchbase-node1.demo.test`
- `couchbase-node2.demo.test`
- `couchbase-node3.demo.test`

Configurar nombres estables antes de inicializar evita que Couchbase registre una IP dinámica o un nombre corto. Si ya inicializaste el nodo 1 antes de establecer su hostname, cambiar Compose no modifica el nombre que el clúster ya guardó.

## 2. (Opcional) Empezar desde cero

Compose asigna un volumen persistente distinto a cada nodo. Los datos se conservan al detener o recrear los contenedores, siempre que no elimines esos volúmenes. Para reiniciar la demostración desde cero:

```powershell
docker compose down -v
docker compose up -d
```

`docker compose down -v` elimina los volúmenes y **borra todos los datos**. No lo ejecutes si necesitas conservar el clúster actual. Si solo quieres detener y volver a iniciar el proyecto conservando los datos, usa `docker compose down` y luego `docker compose up -d` (sin `-v`).

## 3. Confirmar que los tres contenedores están ejecutándose

```powershell
docker compose ps
```

Espera a que `couchbase-node1`, `couchbase-node2` y `couchbase-node3` aparezcan como activos antes de continuar.

## 4. Asignar nombres internos a los nodos

Antes de crear el clúster, configura el hostname que Couchbase anunciará. El hostname de Docker por sí solo no basta:

```powershell
docker exec couchbase-node1 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node1.demo.test
docker exec couchbase-node2 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node2.demo.test
docker exec couchbase-node3 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node3.demo.test
```

Cada comando debe indicar `SUCCESS: Node initialized`. Hazlo solo en nodos nuevos que aún no se hayan inicializado ni agregado a un clúster.

## 5. Inicializar el clúster en el nodo 1

Ejecuta este paso **solo una vez en un nodo 1 nuevo**:

```powershell
docker exec couchbase-node1 couchbase-cli cluster-init -c 127.0.0.1 --cluster-username Admin --cluster-password Admin1 --services data,index,query --cluster-ramsize 512
```

La salida debe indicar `SUCCESS: Cluster initialized`. No vuelvas a ejecutar `cluster-init` si el clúster ya está inicializado.

## 6. Agregar los nodos 2 y 3

El puerto `18091` es el endpoint HTTPS de cada nodo. El nombre completo evita el rechazo de nombres cortos. Ejecuta ambos comandos:

```powershell
docker exec couchbase-node1 couchbase-cli server-add -c 127.0.0.1 -u Admin -p Admin1 --server-add couchbase-node2.demo.test:18091 --server-add-username Admin --server-add-password Admin1 --services data,index,query
docker exec couchbase-node1 couchbase-cli server-add -c 127.0.0.1 -u Admin -p Admin1 --server-add couchbase-node3.demo.test:18091 --server-add-username Admin --server-add-password Admin1 --services data,index,query
```

Espera a que cada comando indique `SUCCESS` antes de seguir. Si una contraseña de nodo no es `Admin1`, sustituye `--server-add-password` por la contraseña real.

## 7. Rebalancear

Agregar cada servidor lo incorpora a la lista de nodos pendientes. El rebalanceo aplica ambos cambios al clúster:

```powershell
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
```

Espera a que termine correctamente.

## 8. Configurar failover automático

Habilita el failover automático y limita la demostración a una conmutación. Se configura un umbral de detección de 30 segundos:

```powershell
docker exec couchbase-node1 couchbase-cli setting-autofailover -c 127.0.0.1 -u Admin -p Admin1 --enable-auto-failover 1 --auto-failover-timeout 30 --max-failovers 1
```

La salida debe indicar `SUCCESS`. El failover automático está disponible en Couchbase Enterprise Edition; comprueba la edición si este comando no está disponible.

## 9. Verificar los tres nodos

```powershell
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

La lista debe mostrar tres servidores, incluido `couchbase-node1.demo.test`, `couchbase-node2.demo.test` y `couchbase-node3.demo.test`. También puedes iniciar sesión en <http://localhost:8091> y revisar la sección **Servers**.

## 10. Crear un bucket con una réplica

Cuando el clúster ya tenga los tres nodos activos, crea un bucket Couchbase con una réplica. Combinada con el failover automático, la réplica permite mantener los datos disponibles si falla un nodo:

```powershell
docker exec couchbase-node1 couchbase-cli bucket-create -c 127.0.0.1 -u Admin -p Admin1 --bucket demo-bucket --bucket-type couchbase --bucket-ramsize 256 --bucket-replica 1
```

La opción `--bucket-replica 1` solicita una copia de los datos en otro nodo. Confirma que el bucket se creó con:

```powershell
docker exec couchbase-node1 couchbase-cli bucket-list -c 127.0.0.1 -u Admin -p Admin1
```

La salida debe incluir `demo-bucket`. También puedes revisar el bucket en <http://localhost:8091>, en la sección **Buckets**. Una réplica protege contra la caída de un nodo, no contra la caída simultánea de varios nodos.

## 11. Cargar documentos desde un archivo JSON

El proyecto incluye `data\productos.json` con **1.000 productos** de ejemplo y el script `cargar-datos.ps1`, que los inserta en `demo-bucket` mediante el endpoint de consultas de Couchbase. Asegúrate primero de que el clúster esté activo, el nodo 1 publique el puerto `8093` y el bucket exista. Desde PowerShell, en la carpeta del proyecto, ejecuta:

```powershell
.\cargar-datos.ps1
```

El script usa las credenciales de demostración `Admin` / `Admin1` y los valores predeterminados del proyecto. Puedes especificar otros valores sin editar el script:

```powershell
.\cargar-datos.ps1 -ClusterUrl "http://localhost:8093/query/service" -Bucket "demo-bucket" -Username "Admin" -Password "Admin1"
```

Cada documento tiene un campo `id`, que el script utiliza como clave del documento en Couchbase. El comando usa `UPSERT`; volverlo a ejecutar actualiza esos mismos documentos en lugar de crear duplicados. Por ello, puedes repetir la ingesta para corregir datos ya cargados. El script informa el avance cada 100 productos. Después, comprueba la cantidad cargada desde **Query** en la interfaz web:

```sql
CREATE INDEX IF NOT EXISTS idx_producto_tipo
ON `demo-bucket`(tipo)
WHERE tipo = "producto"
WITH {"num_replica": 1};
```

Este índice secundario tiene una réplica para que la consulta siga teniendo un índice disponible si falla el nodo que aloja el índice principal. Espera a que el índice y su réplica estén **Online** en la sección **Indexes** antes de probar la caída. Después, cuenta los productos:

```sql
SELECT COUNT(*) AS total_productos
FROM `demo-bucket`
WHERE tipo = "producto";
```

El resultado debe ser de al menos `1000`. Para revisar algunos registros, ejecuta:

```sql
SELECT META(d).id AS id, d.nombre, d.categoria, d.precio, d.stock
FROM `demo-bucket` AS d
WHERE d.tipo = "producto"
LIMIT 5;
```

## 12. Demostración en vivo: desconexión y recuperación

Realiza esta prueba solo con datos de práctica. Mantén los nodos 1 y 3 encendidos: el nodo 1 publica la consola web y el endpoint de consultas en este Compose. Antes de empezar, confirma que los tres nodos estén activos y muestra el total de productos:

```powershell
docker compose ps
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

En **Query**, ejecuta el `COUNT(*)` de la sección anterior y anota el resultado. Luego, desde PowerShell, simula la desconexión del nodo 2:

```powershell
docker stop couchbase-node2
docker compose ps
```

Espera a que termine el failover automático; puede tardar más que los 30 segundos configurados. Comprueba el estado con:

```powershell
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

Cuando el nodo 2 aparezca como `inactiveFailed`, el failover terminó. No ejecutes un failover manual. Vuelve a ejecutar `COUNT(*)` en **Query**: debe devolver al menos `1000`. Ejecuta también la consulta de muestra de la sección anterior; debe mostrar cinco productos. Puede haber errores temporales durante la detección y la conmutación; espera a que el clúster complete el failover y reintenta. La consulta debe ejecutarse contra el nodo 1, que sigue activo.

Para mantener acceso a la consola si se detiene el nodo 1, abre la consola de otro nodo en <http://localhost:18091> (nodo 2) o <http://localhost:28091> (nodo 3). La interfaz no se cambia automáticamente: hay que abrir la URL alternativa.

Para recuperar el nodo, vuelve a iniciarlo:

```powershell
docker start couchbase-node2
docker compose ps
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

Si el nodo 2 vuelve a aparecer activo, espera a que termine su sincronización. Si Couchbase lo marca como fallido y lo deja fuera del clúster, solicita su recuperación incremental y rebalancea:

```powershell
docker exec couchbase-node1 couchbase-cli recovery -c 127.0.0.1 -u Admin -p Admin1 --server-recovery couchbase-node2.demo.test:8091 --recovery-type delta
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
```

Si el nodo 2 ya se muestra activo, **no ejecutes** los comandos de recuperación. Después de recuperarlo, espera a que el rebalanceo termine, vuelve a ejecutar el `COUNT(*)` y confirma que los tres nodos están activos y el resultado sigue siendo al menos `1000`.

Los volúmenes nombrados conservan los datos locales de cada nodo cuando el contenedor se detiene o se recrea. Las réplicas del bucket permiten continuar tras la caída de un nodo; no elimines los volúmenes con `docker compose down -v` si quieres conservar los datos.

## Si algo falla

- **`Short names are not allowed`:** usa los nombres completos, como `couchbase-node2.demo.test`, no `couchbase-node2`.
- **Error TLS al conectar al puerto `8091`:** para `--server-add` prueba el puerto HTTPS `18091`, como en el comando anterior.
- **Un nodo aparece con una IP en Couchbase:** se omitió el paso 4 o el nodo ya estaba inicializado antes de asignar su hostname. Para esta práctica, si puedes descartar los datos, usa la sección 2 y repite los pasos. No ejecutes `cluster-init` de nuevo sobre un clúster que ya está inicializado.
- **`server-add` falla:** no continúes con el rebalanceo; revisa el mensaje completo y confirma que los tres contenedores estén activos con `docker compose ps`.
- **La consulta falla tras detener un nodo:** comprueba que el failover haya terminado y que el índice `idx_producto_tipo` y su réplica estén **Online**. Si sigue fallando, revisa la consola y los registros antes de continuar; no fuerces el failover.
