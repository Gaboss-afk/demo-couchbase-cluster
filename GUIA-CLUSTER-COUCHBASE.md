# Guía: clúster Couchbase de dos nodos con Docker Compose

Estos pasos están pensados para ejecutarse desde PowerShell, en la carpeta que contiene `docker-compose.yml`. El nodo 1 inicializa el clúster; el nodo 2 se agrega a ese mismo clúster. No son dos clústeres separados.

> **Importante:** en este ejemplo se usa `Admin` / `Admin1`, que son credenciales de demostración. Cámbialas por credenciales seguras si el entorno no es desechable. Usa la misma contraseña en los comandos de ambos nodos.

## 1. Revisar los nombres de los nodos

El archivo Compose configura estos nombres DNS completos:

- `couchbase-node1.demo.test`
- `couchbase-node2.demo.test`

Configurar nombres estables antes de inicializar evita que Couchbase registre una IP dinámica o un nombre corto. Si ya inicializaste el nodo 1 antes de establecer su hostname, cambiar Compose no modifica el nombre que el clúster ya guardó.

## 2. (Opcional) Empezar desde cero

Omite esta sección si quieres conservar tu clúster actual. Los servicios no tienen volúmenes configurados; al eliminar los contenedores se perderán los datos almacenados en ellos.

```powershell
docker compose down
docker compose up -d
```

No ejecutes `docker compose down` si necesitas preservar los datos actuales.

## 3. Confirmar que ambos contenedores están ejecutándose

```powershell
docker compose ps
```

Espera a que `couchbase-node1` y `couchbase-node2` aparezcan como activos antes de continuar.

## 4. Inicializar el clúster en el nodo 1

Ejecuta este paso **solo una vez en un nodo 1 nuevo**:

```powershell
docker exec couchbase-node1 couchbase-cli cluster-init -c 127.0.0.1 --cluster-username Admin --cluster-password Admin1 --services data,index,query --cluster-ramsize 512
```

La salida debe indicar `SUCCESS: Cluster initialized`. No vuelvas a ejecutar `cluster-init` si el clúster ya está inicializado.

## 5. Agregar el nodo 2

El puerto `18091` es el endpoint HTTPS del nodo 2. El nombre completo evita el rechazo de nombres cortos:

```powershell
docker exec couchbase-node1 couchbase-cli server-add -c 127.0.0.1 -u Admin -p Admin1 --server-add couchbase-node2.demo.test:18091 --server-add-username Admin --server-add-password Admin1 --services data,index,query
```

Espera a que el comando indique `SUCCESS` antes de seguir. Si la contraseña del nodo 2 no es `Admin1`, sustituye `--server-add-password` por la contraseña real de ese nodo.

## 6. Rebalancear

Agregar el servidor lo incorpora a la lista de nodos pendientes. El rebalanceo aplica el cambio al clúster:

```powershell
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
```

Espera a que termine correctamente.

## 7. Verificar el resultado

```powershell
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

La lista debe mostrar dos servidores, incluido `couchbase-node1.demo.test` y `couchbase-node2.demo.test`. También puedes iniciar sesión en <http://localhost:8091> y revisar la sección **Servers**.

## 8. Crear un bucket con una réplica

Cuando el clúster ya tenga los dos nodos activos, crea un bucket Couchbase con una réplica. Para `bucket-create`, las credenciales se indican con `-u` y `-p`:

```powershell
docker exec couchbase-node1 couchbase-cli bucket-create -c 127.0.0.1 -u Admin -p Admin1 --bucket demo-bucket --bucket-type couchbase --bucket-ramsize 256 --bucket-replica 1
```

La opción `--bucket-replica 1` solicita una copia de los datos en otro nodo. Confirma que el bucket se creó con:

```powershell
docker exec couchbase-node1 couchbase-cli bucket-list -c 127.0.0.1 -u Admin -p Admin1
```

La salida debe incluir `demo-bucket`. También puedes revisar el bucket en <http://localhost:8091>, en la sección **Buckets**. Para demostrar la replicación, inserta documentos en este bucket y consulta su disponibilidad durante la prueba de desconexión de un nodo.

## 9. Cargar documentos desde un archivo JSON

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
CREATE PRIMARY INDEX IF NOT EXISTS ON `demo-bucket`;
```

Cuando termine la creación del índice, cuenta los productos:

```sql
SELECT COUNT(*) AS total_productos
FROM `demo-bucket`
WHERE tipo = "producto";
```

El resultado debe ser de al menos `1000`. Para revisar algunos registros, ejecuta:

```sql
SELECT META(d).id AS id, d.nombre, d.categoria, d.precio, d.stock
FROM `demo-bucket` AS d
WHERE d.tipo = "producto";
```

## 10. Demostración en vivo: desconexión y recuperación

Realiza esta prueba solo con datos de práctica. Mantén el nodo 1 encendido: es el que publica la consola web y el endpoint de consultas en este Compose. Antes de empezar, confirma que ambos nodos estén activos y muestra el total de productos:

```powershell
docker compose ps
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

En **Query**, ejecuta el `COUNT(*)` de la sección anterior y anota el resultado. Luego, desde PowerShell, simula la desconexión del nodo 2:

```powershell
docker stop couchbase-node2
docker compose ps
```

Muestra el estado del clúster en **Servers** y vuelve a intentar la consulta. Couchbase puede no responder por todos los documentos mientras el nodo está fuera, porque algunas particiones activas pueden residir en ese nodo. En un clúster de dos nodos no se debe asumir que el failover será automático; anota el comportamiento que observas, sin forzar el failover durante esta demostración básica.

Para recuperar el nodo, vuelve a iniciarlo:

```powershell
docker start couchbase-node2
docker compose ps
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

Espera a que el nodo 2 vuelva a aparecer activo y termine su sincronización. Después, ejecuta de nuevo el `COUNT(*)` y confirma que ambos nodos están presentes y los documentos siguen disponibles.

Si el nodo se muestra como activo, **no ejecutes** los comandos de recuperación siguientes. Solo si Couchbase lo marcó como fallido y lo retiró del clúster, puedes solicitar la recuperación incremental y rebalancear:

```powershell
docker exec couchbase-node1 couchbase-cli recovery -c 127.0.0.1 -u Admin -p Admin1 --server-recovery couchbase-node2.demo.test:8091 --recovery-type delta
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
```

No uses `--force` ni un failover forzado como parte rutinaria de la exposición: puede producir pérdida de datos o dejar el clúster en un estado que requiera pasos adicionales. Dos nodos son suficientes para demostrar replicación configurada y una interrupción controlada, pero no garantizan failover automático ni disponibilidad continua de todas las particiones. Para demostrar failover automático de forma más sólida, prepara al menos tres nodos.

## Si algo falla

- **`Short names are not allowed`:** usa `couchbase-node2.demo.test`, no `couchbase-node2`.
- **Error TLS al conectar al puerto `8091`:** para `--server-add` prueba el puerto HTTPS `18091`, como en el comando anterior.
- **El nodo 1 aparece con una IP:** el clúster se inicializó antes de configurar un hostname estable. Para esta práctica, si puedes descartar los datos, usa la sección 2 y repite los pasos con los hostnames ya definidos. No hay que ejecutar `cluster-init` de nuevo sobre el clúster actual.
- **`server-add` falla:** no continúes con el rebalanceo; revisa el mensaje completo y confirma que ambos contenedores estén activos con `docker compose ps`.
