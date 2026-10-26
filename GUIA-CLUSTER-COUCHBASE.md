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

## Si algo falla

- **`Short names are not allowed`:** usa `couchbase-node2.demo.test`, no `couchbase-node2`.
- **Error TLS al conectar al puerto `8091`:** para `--server-add` prueba el puerto HTTPS `18091`, como en el comando anterior.
- **El nodo 1 aparece con una IP:** el clúster se inicializó antes de configurar un hostname estable. Para esta práctica, si puedes descartar los datos, usa la sección 2 y repite los pasos con los hostnames ya definidos. No hay que ejecutar `cluster-init` de nuevo sobre el clúster actual.
- **`server-add` falla:** no continúes con el rebalanceo; revisa el mensaje completo y confirma que ambos contenedores estén activos con `docker compose ps`.
