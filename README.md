# Lab 15 · CloudFormation: una app Docker en EC2 sin tocar la consola de EC2

Laboratorio GLAB-S15 de Desarrollo de Soluciones en la Nube (TECSUP, Jaime Farfán).
Repositorio: https://github.com/JasonGomezzz/lab15-dsn

Levanté una instancia EC2 con Docker y un contenedor web usando solo plantillas YAML de CloudFormation. Hice el stack desde la consola de AWS (como pide el enunciado) y comprobé todo también por terminal.

## Qué hay en el repo

| Archivo | Para qué sirve |
|---|---|
| `cloudformation/01-ec2-docker.yaml` | Pasos 1 a 4: EC2 + Security Group (puerto 80) + nginx en Docker |
| `cloudformation/02-ec2-docker-hello.yaml` | Paso 5: misma plantilla con `nginxdemos/hello` |
| `cloudformation/03-ec2-docker-desafios.yaml` | Desafíos 1, 2 y 3: etiquetas, Key Pair como parámetro e imagen elegible (`nginx`, `nginxdemos/hello`, `httpd`) |
| `scripts/verificar.sh` | Muestra stack, recursos, instancia, respuesta HTTP y contenedor por SSH |
| `scripts/limpiar.sh` | Borra el stack (y el Key Pair si se pide) para no pagar de más |

Las capturas y salidas de terminal están en `docs/` y no se suben al repo (están en `.gitignore`).

## Cómo reproducirlo

Necesito AWS CLI v2 con credenciales configuradas y región `us-east-1`.

```bash
# 1. Validar las plantillas
aws cloudformation validate-template --template-body file://cloudformation/01-ec2-docker.yaml

# 2. Key Pair para los desafíos (la clave queda fuera del repo)
aws ec2 create-key-pair --key-name lab-cloudformation-key \
  --query KeyMaterial --output text > ~/.ssh/lab-cloudformation-key.pem
chmod 400 ~/.ssh/lab-cloudformation-key.pem

# 3. Crear el stack base (equivale a Create stack > Upload a template file)
aws cloudformation create-stack --stack-name lab-cloudformation-docker \
  --template-body file://cloudformation/01-ec2-docker.yaml
aws cloudformation wait stack-create-complete --stack-name lab-cloudformation-docker

# 4. Actualizar a la plantilla de desafíos (SshCidr = mi IP pública)
aws cloudformation update-stack --stack-name lab-cloudformation-docker \
  --template-body file://cloudformation/03-ec2-docker-desafios.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=KeyName,ParameterValue=lab-cloudformation-key \
               ParameterKey=SshCidr,ParameterValue="$(curl -s https://checkip.amazonaws.com)/32" \
               ParameterKey=AppImage,ParameterValue=nginxdemos/hello \
               ParameterKey=InstanceType,UsePreviousValue=true \
               ParameterKey=LatestAmiId,UsePreviousValue=true
aws cloudformation wait stack-update-complete --stack-name lab-cloudformation-docker

# 5. Cambiar la aplicación sin reemplazar la instancia
aws cloudformation update-stack --stack-name lab-cloudformation-docker --use-previous-template \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=AppImage,ParameterValue=httpd \
               ParameterKey=KeyName,UsePreviousValue=true ParameterKey=SshCidr,UsePreviousValue=true \
               ParameterKey=InstanceType,UsePreviousValue=true ParameterKey=LatestAmiId,UsePreviousValue=true

# 6. Ver todo
./scripts/verificar.sh

# 7. Limpieza
./scripts/limpiar.sh lab-cloudformation-docker --con-key-pair
```

## Diferencias con el enunciado

Fueron necesarias porque la plantilla original no funciona tal como está en una cuenta nueva.

| # | El enunciado dice | Qué pasó | Qué hice |
|---|---|---|---|
| 1 | `InstanceType: t2.micro` | CloudFormation devolvió `CREATE_FAILED` con "The specified instance type is not eligible for Free Tier" y el stack quedó en `ROLLBACK_COMPLETE`. | Parametricé el tipo y usé `t3.micro`, que sí es elegible en mi cuenta. Borré el stack fallido y repetí. |
| 2 | `ImageId: ami-0c02fb55956c7d316` | Es un Amazon Linux 2 de 2022 y solo existe en una región. | Tomo el AMI vigente de Amazon Linux 2023 desde un parámetro SSM. |
| 3 | `amazon-linux-extras install docker` | Ese comando no existe en Amazon Linux 2023. | `dnf install -y docker`. |
| 4 | SSH (22) abierto a `0.0.0.0/0` | El diagrama del enunciado solo muestra el puerto 80. | La plantilla 01 abre solo el 80. En la 03, SSH queda restringido a mi IP con `/32` y el parámetro rechaza `0.0.0.0/0`. |
| 5 | Paso 5: cambiar `docker run` en `UserData` y actualizar | El stack llegó a `UPDATE_COMPLETE`, pero la página seguía mostrando nginx. `UserData` solo corre en el primer arranque de la instancia. | En la plantilla 03 el contenedor lo lanza `cfn-init` y `cfn-hup` vuelve a ejecutarlo cuando cambian los metadatos. Para eso agregué un rol IAM con un único permiso (`cloudformation:DescribeStackResource` sobre este stack). |
| 6 | La IP pública cambia | CloudFormation detuvo e inició la instancia al actualizar y la IP cambió (de `34.228.20.171` a `54.87.201.224`). | Agregué una Elastic IP en la plantilla 03. |

## Pruebas que hice

| Caso | Qué probé | Resultado real |
|---|---|---|
| CP01 | Stack base con `t2.micro` | `ROLLBACK_COMPLETE`, error de Free Tier |
| CP02 | Stack base con `t3.micro` | `CREATE_COMPLETE`, nginx responde 200 y muestra "Welcome to nginx!" |
| CP03 | Actualizar a `nginxdemos/hello` (plantilla 02) | `UPDATE_COMPLETE`, la instancia conserva el ID pero la página sigue siendo nginx |
| CP04 | Actualizar a la plantilla 03 | Cambios: 3 recursos nuevos, SG e instancia reemplazados. Nueva instancia con etiqueta `Name = Laboratorio-Docker` y página "Hello World" |
| CP05 | Cambiar `AppImage` a `httpd` | Modify sin reemplazo. En unos 50 segundos la página pasó a "It works! Apache httpd" |
| CP06 | `SshCidr` con `0.0.0.0/0` y con `999.1.1.1/32` | `ValidationError` en ambos. Con mi IP `/32`, acepta |
| CP07 | SSH con el Key Pair y `docker ps` | Contenedor `web` con imagen `httpd`, puerto 80, y `docker` y `cfn-hup` activos |

## Evidencia

Las capturas son de pantalla completa en Brave, con la URL visible y sin marcas de la herramienta de automatización. Están en `docs/capturas/`:

| Archivos | Qué muestran |
|---|---|
| `F1` a `F3` | Primer intento con `t2.micro`: parámetros, `ROLLBACK_COMPLETE` y el motivo del error de Free Tier |
| `01` a `07` | Creación del stack base: plantilla subida, nombre y parámetros, revisión, en progreso, `CREATE_COMPLETE`, recursos y salidas |
| `08` y `09` | Instancia en EC2 y página "Welcome to nginx!" por la IP pública |
| `10` a `12` | Actualización con la plantilla 02: plantilla subida, vista previa (`Modify`) y `UPDATE_COMPLETE` |
| `13` a `18` | Plantilla 03: parámetros, conjunto de cambios, en progreso, `UPDATE_COMPLETE`, instancia con etiqueta `Name` y página "Hello World" |
| `19` a `22` | Desafío nivel 3: `AppImage = httpd`, conjunto de cambios, `UPDATE_COMPLETE` y "It works!" de Apache |
| `23` | Salidas finales del stack |

Las salidas de terminal están en `docs/evidencias/` (`01` a `09`). Ambas carpetas quedan fuera del repo.

## Conclusiones

1. **El primer stack me falló y aprendí a leer los eventos.** Lo creé con `t2.micro` como decía el enunciado y terminó en `ROLLBACK_COMPLETE`. La causa estaba en el evento `CREATE_FAILED`: mi cuenta ya no acepta ese tipo de instancia en el plan gratuito. Lo cambié a `t3.micro` y desde entonces reviso siempre la pestaña Eventos antes de suponer qué pasó.

2. **Pensé que actualizar el `UserData` bastaba, pero no.** Cambié `nginx` por `nginxdemos/hello`, el stack salió en `UPDATE_COMPLETE` y la página seguía mostrando nginx. Entendí que el `UserData` solo corre en el primer arranque. Para que la app cambie al actualizar tuve que usar `cfn-init` con `cfn-hup`, y ahí vi que un `UPDATE_COMPLETE` verde no garantiza que la aplicación cambió.

3. **La plantilla del enunciado no servía tal cual en una cuenta nueva.** `amazon-linux-extras` no existe en Amazon Linux 2023, así que usé `dnf`. El AMI fijo era de una sola región y de 2022, así que lo reemplacé por un parámetro de SSM que siempre trae el vigente. Me di cuenta de que copiar un laboratorio sin revisarlo habría dejado el stack roto desde el inicio.

4. **Cuidé la seguridad sin romper lo que pedía el lab.** El enunciado abría el puerto 22 a todo internet. Lo dejé solo para mi IP con `/32` y el parámetro rechaza `0.0.0.0/0`, lo probé con un change set. Para que `cfn-hup` pudiera leer los metadatos creé un rol con un solo permiso, `DescribeStackResource` sobre este stack, en vez de darle acceso amplio.

5. **Con la infraestructura en un archivo pude repetir todo sin acordarme de los clics.** Rehice el laboratorio completo desde cero y cambiar entre `nginx`, `hello` y `httpd` fue cambiar un parámetro. Eliminar el stack se llevó la instancia, la IP elástica y el rol de una sola vez, y no quedó nada cobrando. Para mí esa es la ventaja real de Infrastructure as Code.

## Limpieza

Al terminar eliminé el stack con `./scripts/limpiar.sh lab-cloudformation-docker --con-key-pair`. Comprobé que las dos instancias del lab quedaron en `terminated`, que no queda ninguna Elastic IP ni el rol IAM, y que el Key Pair se borró en AWS y en mi equipo.
