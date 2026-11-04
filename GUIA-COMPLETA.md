# Guía completa: demostración de Couchbase con tres nodos

## 1. Iniciar el clúster

```powershell
docker compose up -d
docker compose ps
```

Con los tres nodos en ejecución, puedes abrir la consola por cualquiera de estos enlaces:

- Nodo 1: <http://localhost:8091>
- Nodo 2: <http://localhost:18091>
- Nodo 3: <http://localhost:28091>

Para aplicar los nuevos puertos a un clúster ya existente, recrea los nodos 2 y 3 uno por uno, esperando que cada uno se recupere antes de continuar:

```powershell
docker compose up -d couchbase-node2
docker compose ps
docker compose up -d couchbase-node3
docker compose ps
```

No uses `docker compose down -v`; los volúmenes conservan los datos.

## 2. Preparar los nombres de los nodos

Ejecuta estos comandos solo si vas a crear un clúster nuevo con nodos sin inicializar:

```powershell
docker exec couchbase-node1 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node1.demo.test
docker exec couchbase-node2 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node2.demo.test
docker exec couchbase-node3 couchbase-cli node-init -c 127.0.0.1 --node-init-hostname couchbase-node3.demo.test
```

## 3. Inicializar un clúster nuevo

Ejecuta solo en un nodo 1 nuevo:

```powershell
docker exec couchbase-node1 couchbase-cli cluster-init -c 127.0.0.1 --cluster-username Admin --cluster-password Admin1 --services data,index,query --cluster-ramsize 512
```

## 4. Agregar los nodos 2 y 3

```powershell
docker exec couchbase-node1 couchbase-cli server-add -c 127.0.0.1 -u Admin -p Admin1 --server-add couchbase-node2.demo.test:18091 --server-add-username Admin --server-add-password Admin1 --services data,index,query
docker exec couchbase-node1 couchbase-cli server-add -c 127.0.0.1 -u Admin -p Admin1 --server-add couchbase-node3.demo.test:18091 --server-add-username Admin --server-add-password Admin1 --services data,index,query
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
```

## 5. Habilitar failover automático y verificar nodos

```powershell
docker exec couchbase-node1 couchbase-cli setting-autofailover -c 127.0.0.1 -u Admin -p Admin1 --enable-auto-failover 1 --auto-failover-timeout 30 --max-failovers 1
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

## 6. Crear el bucket con una réplica

```powershell
docker exec couchbase-node1 couchbase-cli bucket-create -c 127.0.0.1 -u Admin -p Admin1 --bucket demo-bucket --bucket-type couchbase --bucket-ramsize 256 --bucket-replica 1
```

## 7. Cargar los productos

```powershell
.\cargar-datos.ps1
```

## 8. Crear el índice replicado

En **Query** (`http://localhost:8091`):

```sql
CREATE INDEX IF NOT EXISTS idx_producto_tipo
ON `demo-bucket`(tipo)
WHERE tipo = "producto"
WITH {"num_replica": 1};
```

## 9. Verificar los datos

```sql
SELECT COUNT(*) AS total_productos
FROM `demo-bucket`
WHERE tipo = "producto";
```

```sql
SELECT META(d).id AS id, d.nombre, d.categoria, d.precio, d.stock
FROM `demo-bucket` AS d
WHERE d.tipo = "producto"
LIMIT 5;
```

## 10. Simular la falla del nodo 2

```powershell
docker stop couchbase-node2
docker compose ps
```

## 11. Esperar al failover y repetir las consultas

```powershell
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

Cuando el nodo 2 aparezca como `inactiveFailed`, vuelve a ejecutar las consultas de la sección 9 en **Query**.

## Demostrar acceso a la interfaz cuando falla el nodo 1

1. Abre <http://localhost:18091> o <http://localhost:28091> e inicia sesión.
2. Desde Docker Desktop o PowerShell, detén solo el nodo 1:

   ```powershell
   docker stop couchbase-node1
   ```

3. La pestaña de `http://localhost:8091` dejará de responder. Abre o actualiza la consola del nodo 2 en <http://localhost:18091> o la del nodo 3 en <http://localhost:28091>.
4. Espera a que Couchbase complete el failover y verifica el estado de los nodos en **Servers**.
5. Ejecuta las consultas de la sección 9 desde la consola del nodo que sigue activo.
6. Para restaurar el nodo 1, sigue la sección 12, sustituyendo `couchbase-node2` por `couchbase-node1` y `couchbase-node2.demo.test` por `couchbase-node1.demo.test`.

La consola no se transfiere automáticamente de una dirección a otra: hay que abrir la URL de otro nodo. Esta configuración publica los puertos de la consola y Query en los nodos 2 y 3; no es un balanceador ni proporciona continuidad sin reconectar.

## 12. Recuperar el nodo 2

Si `server-list` muestra el nodo 2 activo, no ejecutes `recovery`; espera a que termine la sincronización. Si el nodo aparece como `inactiveFailed`, ejecuta:

```powershell
docker start couchbase-node2
docker exec couchbase-node1 couchbase-cli recovery -c 127.0.0.1 -u Admin -p Admin1 --server-recovery couchbase-node2.demo.test:8091 --recovery-type delta
docker exec couchbase-node1 couchbase-cli rebalance -c 127.0.0.1 -u Admin -p Admin1
docker exec couchbase-node1 couchbase-cli server-list -c 127.0.0.1 -u Admin -p Admin1
```

## 13. Confirmar los datos después de recuperar el nodo

Vuelve a ejecutar las consultas de la sección 9. El conteo debe ser de al menos `1000`.

## Reiniciar la demostración desde cero

**Este paso elimina los volúmenes del clúster y todos sus datos.**

```powershell
docker compose down -v
docker compose up -d
```

Después, repite los pasos desde la sección 2.
