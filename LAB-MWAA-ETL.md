# Lab: Pipeline ETL Completo con MWAA, S3, Glue y Athena

## Objetivo
Aprenderás a crear un pipeline ETL de producción usando MWAA (Managed Workflows for Apache Airflow) que orquesta servicios de datos de AWS. Al final del lab, tendrás un DAG que automáticamente procesa datos CSV, los transforma con Glue, y los valida con Athena.

**Lo que construirás:**
Un pipeline automatizado que toma datos de transacciones en CSV, los limpia, los convierte a Parquet, y valida que todo funcionó correctamente.

---

## Servicios AWS
- **Amazon MWAA** (Apache Airflow gestionado)
- **Amazon S3** (almacenamiento de datos)
- **AWS Glue** (ETL y catálogo de datos)
- **Amazon Athena** (consultas SQL)
- **Amazon SNS** (notificaciones)

---

## Nivel
**Intermedio**

---

## Duración estimada
**2-3 horas**

---

## Prerequisitos
- Cuenta AWS con acceso a consola
- Conocimientos básicos de Python
- Familiaridad con conceptos de ETL

---

## Estructura de Archivos del Lab

Este laboratorio incluye todos los archivos necesarios organizados en carpetas:

```
mwaa-glue-lab/
├── dags/
│   └── s3_glue_athena_etl.py          # DAG de Airflow (pipeline completo)
├── scripts/
│   ├── glue_etl_script.py             # Script PySpark para Glue ETL
│   ├── glue-trust-policy.json         # Política IAM para Glue
│   ├── mwaa-trust-policy.json         # Política IAM para MWAA
│   ├── mwaa-execution-policy.json     # Permisos de ejecución MWAA
│   ├── requirements.txt               # Dependencias de Airflow
│   ├── sample_data.csv                # Datos de ejemplo
│   ├── setup.sh                       # Script automatizado de setup
│   └── cleanup.sh                     # Script automatizado de cleanup
└── LAB-MWAA-ETL.md                    # Esta guía
```

**Opciones para ejecutar el lab:**

1. **Opción rápida (recomendada)**: Usa los scripts automatizados
   - `./scripts/setup.sh` - Crea toda la infraestructura
   - `./scripts/cleanup.sh <PREFIX>` - Elimina todos los recursos

2. **Opción manual**: Sigue los pasos detallados en las fases 1-4
   - Ideal para aprender cada componente
   - Todos los archivos ya están listos para usar

---

**Flujo:**
1. Subir CSV → S3 Raw
2. Crawler cataloga datos raw
3. Glue Job transforma CSV → Parquet
4. Crawler cataloga datos procesados
5. Athena valida resultados
6. SNS notifica éxito/fallo

---

## Pasos del Lab

###  OPCIÓN RÁPIDA: Setup Automatizado

Si quieres crear toda la infraestructura de forma automática, usa el script de setup:

```bash
# Dar permisos de ejecución
chmod +x scripts/setup.sh scripts/cleanup.sh

# Ejecutar setup (toma ~5 minutos)
cd scripts
./setup.sh
```

El script creará automáticamente:
- Todos los buckets de S3
- Base de datos y crawlers de Glue
- Glue ETL Job
- SNS Topic
- Roles IAM necesarios
- Subirá todos los archivos a S3

Al finalizar, te dará los valores para configurar las variables en MWAA.

**Luego salta directamente a la [Fase 2: Configurar MWAA](#fase-2-configurar-amazon-mwaa)**

---

### OPCIÓN MANUAL: Paso a Paso

Si prefieres aprender creando cada recurso manualmente, sigue las fases a continuación:

### FASE 1: Preparación de Infraestructura AWS

#### Paso 1.1: Crear buckets de S3

Necesitamos 4 buckets para organizar nuestros datos:

```bash
# Reemplaza YOUR-UNIQUE-PREFIX con algo único (ej: tu nombre-fecha)
PREFIX="mwaa-etl-lab-$(date +%s)"

aws s3 mb s3://${PREFIX}-raw
aws s3 mb s3://${PREFIX}-processed
aws s3 mb s3://${PREFIX}-scripts
aws s3 mb s3://${PREFIX}-athena-results
```

**¿Por qué 4 buckets?**
- `raw`: Datos originales sin procesar
- `processed`: Datos limpios en formato Parquet
- `scripts`: Código de Glue ETL
- `athena-results`: Resultados de consultas SQL

#### Paso 1.2: Crear base de datos en Glue Data Catalog

```bash
aws glue create-database \
  --database-input '{
    "Name": "etl_lab_db",
    "Description": "Base de datos para el Lab de MWAA"
  }'
```

#### Paso 1.3: Crear rol IAM para Glue

Usa el archivo `scripts/glue-trust-policy.json` incluido en el lab.

Crea el rol:

```bash
aws iam create-role \
  --role-name GlueETLRole \
  --assume-role-policy-document file://scripts/glue-trust-policy.json

# Adjunta políticas necesarias
aws iam attach-role-policy \
  --role-name GlueETLRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

aws iam attach-role-policy \
  --role-name GlueETLRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

#### Paso 1.4: Crear Glue Crawlers

**Crawler para datos raw:**

```bash
aws glue create-crawler \
  --name raw_data_crawler \
  --role GlueETLRole \
  --database-name etl_lab_db \
  --targets "{\"S3Targets\": [{\"Path\": \"s3://${PREFIX}-raw/input/\"}]}"
```

**Crawler para datos procesados:**

```bash
aws glue create-crawler \
  --name processed_data_crawler \
  --role GlueETLRole \
  --database-name etl_lab_db \
  --targets "{\"S3Targets\": [{\"Path\": \"s3://${PREFIX}-processed/output/\"}]}"
```

#### Paso 1.5: Crear script de Glue ETL

El script de Glue ETL ya está incluido en `scripts/glue_etl_script.py`.

Sube el script a S3:

```bash
aws s3 cp scripts/glue_etl_script.py s3://${PREFIX}-scripts/glue_etl_script.py
```

#### Paso 1.6: Crear Glue Job

```bash
aws glue create-job \
  --name transactions_etl_job \
  --role GlueETLRole \
  --command '{
    "Name": "glueetl",
    "ScriptLocation": "s3://'${PREFIX}'-scripts/glue_etl_script.py",
    "PythonVersion": "3"
  }' \
  --default-arguments '{
    "--job-language": "python",
    "--enable-metrics": "true",
    "--enable-continuous-cloudwatch-log": "true"
  }' \
  --glue-version "4.0" \
  --max-retries 0 \
  --timeout 60
```

#### Paso 1.7: Crear SNS Topic

```bash
aws sns create-topic --name etl-pipeline-alerts

# Suscríbete con tu email
aws sns subscribe \
  --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:etl-pipeline-alerts \
  --protocol email \
  --notification-endpoint tu-email@ejemplo.com
```

**Importante**: Confirma la suscripción desde tu email.

---

### FASE 2: Configurar Amazon MWAA

#### Paso 2.1: Crear bucket para MWAA

```bash
aws s3 mb s3://${PREFIX}-mwaa
aws s3api put-object --bucket ${PREFIX}-mwaa --key dags/
aws s3api put-object --bucket ${PREFIX}-mwaa --key plugins/
aws s3api put-object --bucket ${PREFIX}-mwaa --key requirements/
```

#### Paso 2.2: Crear archivo requirements.txt

El archivo `scripts/requirements.txt` ya está incluido en el lab.

Súbelo a S3:

```bash
aws s3 cp scripts/requirements.txt s3://${PREFIX}-mwaa/requirements/requirements.txt
```

#### Paso 2.3: Crear el DAG de Airflow

El DAG completo ya está incluido en `dags/s3_glue_athena_etl.py`.

Sube el DAG a S3:

```bash
aws s3 cp dags/s3_glue_athena_etl.py s3://${PREFIX}-mwaa/dags/


```python
"""
MWAA ETL Pipeline: S3 → Glue → Athena
Orquesta un pipeline completo de datos usando servicios nativos de AWS
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.models import Variable
from airflow.providers.amazon.aws.operators.s3 import S3CreateObjectOperator
from airflow.providers.amazon.aws.operators.glue_crawler import GlueCrawlerOperator
from airflow.providers.amazon.aws.sensors.glue_crawler import GlueCrawlerSensor
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.sensors.glue import GlueJobSensor
from airflow.providers.amazon.aws.operators.athena import AthenaOperator
from airflow.providers.amazon.aws.sensors.athena import AthenaSensor
from airflow.providers.amazon.aws.operators.sns import SnsPublishOperator

# Configuración de variables (se configuran en MWAA UI)
SOURCE_BUCKET = Variable.get("source_bucket")
SOURCE_KEY = Variable.get("source_key")
DESTINATION_BUCKET = Variable.get("destination_bucket")
SCRIPTS_BUCKET = Variable.get("scripts_bucket")
ATHENA_RESULTS_BUCKET = Variable.get("athena_results_bucket")
GLUE_DATABASE = Variable.get("glue_database")
GLUE_JOB_NAME = Variable.get("glue_job_name")
RAW_CRAWLER_NAME = Variable.get("raw_crawler_name")
PROCESSED_CRAWLER_NAME = Variable.get("processed_crawler_name")
GLUE_IAM_ROLE = Variable.get("glue_iam_role")
SNS_TOPIC_ARN = Variable.get("sns_topic_arn")

# Datos de ejemplo para el CSV
SAMPLE_CSV_DATA = """transaction_id,customer_id,amount,product,date
1,C001,150.50,Laptop,2025-01-15
2,C002,75.25,Mouse,2025-01-15
3,C003,200.00,Keyboard,2025-01-15
4,C004,50.00,Cable,2025-01-15
5,C005,300.75,Monitor,2025-01-15
"""

default_args = {
    "owner": "data-team",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="s3_glue_athena_etl",
    default_args=default_args,
    description="Pipeline ETL completo con S3, Glue y Athena",
    schedule="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["etl", "glue", "athena", "production"],
) as dag:

    # Task 1: Subir datos raw a S3
    upload_raw_data = S3CreateObjectOperator(
        task_id="upload_raw_data",
        s3_bucket=SOURCE_BUCKET,
        s3_key=SOURCE_KEY,
        data=SAMPLE_CSV_DATA,
        replace=True,
        aws_conn_id="aws_default",
    )

    # Task 2: Ejecutar Glue Crawler en datos raw
    crawl_raw_data = GlueCrawlerOperator(
        task_id="crawl_raw_data",
        config={"Name": RAW_CRAWLER_NAME},
        wait_for_completion=False,
        aws_conn_id="aws_default",
    )

    # Task 3: Esperar a que termine el crawler raw
    wait_for_raw_crawl = GlueCrawlerSensor(
        task_id="wait_for_raw_crawl",
        crawler_name=RAW_CRAWLER_NAME,
        poke_interval=30,
        timeout=600,
        aws_conn_id="aws_default",
    )

    # Task 4: Ejecutar Glue ETL Job
    run_glue_job = GlueJobOperator(
        task_id="run_glue_job",
        job_name=GLUE_JOB_NAME,
        script_location=f"s3://{SCRIPTS_BUCKET}/glue_etl_script.py",
        s3_bucket=SCRIPTS_BUCKET,
        iam_role_name=GLUE_IAM_ROLE,
        script_args={
            "--source_path": f"s3://{SOURCE_BUCKET}/input/",
            "--destination_path": f"s3://{DESTINATION_BUCKET}/output/",
        },
        wait_for_completion=False,
        verbose=True,
        aws_conn_id="aws_default",
    )

    # Task 5: Esperar a que termine el Glue Job
    wait_for_glue_job = GlueJobSensor(
        task_id="wait_for_glue_job",
        job_name=GLUE_JOB_NAME,
        run_id=run_glue_job.output,
        poke_interval=60,
        timeout=1800,
        aws_conn_id="aws_default",
    )

    # Task 6: Ejecutar Glue Crawler en datos procesados
    crawl_processed_data = GlueCrawlerOperator(
        task_id="crawl_processed_data",
        config={"Name": PROCESSED_CRAWLER_NAME},
        wait_for_completion=False,
        aws_conn_id="aws_default",
    )

    # Task 7: Esperar a que termine el crawler procesado
    wait_for_processed_crawl = GlueCrawlerSensor(
        task_id="wait_for_processed_crawl",
        crawler_name=PROCESSED_CRAWLER_NAME,
        poke_interval=30,
        timeout=600,
        aws_conn_id="aws_default",
    )

    # Task 8: Validar con Athena
    validate_with_athena = AthenaOperator(
        task_id="validate_with_athena",
        query=f"SELECT COUNT(*) as total_records FROM {GLUE_DATABASE}.output",
        database=GLUE_DATABASE,
        output_location=f"s3://{ATHENA_RESULTS_BUCKET}/",
        workgroup="primary",
        aws_conn_id="aws_default",
    )

    # Task 9: Esperar resultado de Athena
    wait_for_athena = AthenaSensor(
        task_id="wait_for_athena",
        query_execution_id=validate_with_athena.output,
        poke_interval=10,
        timeout=300,
        aws_conn_id="aws_default",
    )

    # Task 10: Notificar resultado
    notify_result = SnsPublishOperator(
        task_id="notify_result",
        target_arn=SNS_TOPIC_ARN,
        message=f"Pipeline ETL completado - Fecha: {{{{ ds }}}}",
        subject="MWAA ETL Pipeline - Resultado",
        trigger_rule="all_done",
        aws_conn_id="aws_default",
    )

    # Definir dependencias (flujo secuencial)
    (
        upload_raw_data
        >> crawl_raw_data
        >> wait_for_raw_crawl
        >> run_glue_job
        >> wait_for_glue_job
        >> crawl_processed_data
        >> wait_for_processed_crawl
        >> validate_with_athena
        >> wait_for_athena
        >> notify_result
    )
```

**Nota**: Puedes revisar el código completo del DAG en el archivo `dags/s3_glue_athena_etl.py`.

#### Paso 2.4: Crear rol IAM para MWAA

Usa los archivos de políticas incluidos en `scripts/`:
- `scripts/mwaa-trust-policy.json`
- `scripts/mwaa-execution-policy.json`

Crea el rol:

```bash
aws iam create-role \
  --role-name MWAAExecutionRole \
  --assume-role-policy-document file://scripts/mwaa-trust-policy.json

aws iam put-role-policy \
  --role-name MWAAExecutionRole \
  --policy-name MWAAExecutionPolicy \
  --policy-document file://scripts/mwaa-execution-policy.json
```

#### Paso 2.5: Crear ambiente MWAA

**Opción A: Desde la consola AWS** (Recomendado para principiantes)

1. Ve a Amazon MWAA en la consola AWS
2. Click en "Create environment"
3. Configuración:
   - **Name**: `mwaa-etl-lab`
   - **Airflow version**: 2.8.1
   - **S3 Bucket**: `s3://${PREFIX}-mwaa`
   - **DAGs folder**: `dags/`
   - **Requirements file**: `requirements/requirements.txt`
   - **Execution role**: `MWAAExecutionRole`
   - **Environment class**: `mw1.small`
   - **Network**: Usa VPC default y subnets públicas
   - **Web server access**: Public network
4. Click "Create environment"

**Tiempo de creación**: 20-30 minutos ☕

**Opción B: Con AWS CLI**

```bash
# Primero necesitas obtener subnet IDs de tu VPC default
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[0:2].SubnetId" --output text | tr '\t' ',')

aws mwaa create-environment \
  --name mwaa-etl-lab \
  --airflow-version 3.0.6 \
  --source-bucket-arn arn:aws:s3:::${PREFIX}-mwaa \
  --dag-s3-path dags/ \
  --requirements-s3-path requirements/requirements.txt \
  --execution-role-arn arn:aws:iam::ACCOUNT_ID:role/MWAAExecutionRole \
  --network-configuration "SubnetIds=${SUBNET_IDS}" \
  --environment-class mw1.small \
  --webserver-access-mode PUBLIC_ONLY \
  --logging-configuration '{
    "DagProcessingLogs": {"Enabled": true, "LogLevel": "INFO"},
    "SchedulerLogs": {"Enabled": true, "LogLevel": "INFO"},
    "TaskLogs": {"Enabled": true, "LogLevel": "INFO"},
    "WorkerLogs": {"Enabled": true, "LogLevel": "INFO"},
    "WebserverLogs": {"Enabled": true, "LogLevel": "INFO"}
  }'
```

---

### FASE 3: Configurar Variables en MWAA

Una vez que el ambiente MWAA esté disponible:

1. Abre la consola de MWAA
2. Click en tu ambiente `mwaa-etl-lab`
3. Click en "Open Airflow UI"
4. Ve a **Admin → Variables**
5. Agrega las siguientes variables:

| Key                      | Value                                    |
|--------------------------|------------------------------------------|
| `source_bucket`          | `mwaa-etl-lab-XXXXX-raw`                 |
| `source_key`             | `input/transactions.csv`                 |
| `destination_bucket`     | `mwaa-etl-lab-XXXXX-processed`           |
| `scripts_bucket`         | `mwaa-etl-lab-XXXXX-scripts`             |
| `athena_results_bucket`  | `mwaa-etl-lab-XXXXX-athena-results`      |
| `glue_database`          | `etl_lab_db`                             |
| `glue_job_name`          | `transactions_etl_job`                   |
| `raw_crawler_name`       | `raw_data_crawler`                       |
| `processed_crawler_name` | `processed_data_crawler`                 |
| `glue_iam_role`          | `GlueETLRole`                            |
| `sns_topic_arn`          | `arn:aws:sns:REGION:ACCOUNT:etl-alerts` |

**Reemplaza** `XXXXX` con tu timestamp único y `REGION`/`ACCOUNT` con tus valores.

---

### FASE 4: Ejecutar el Pipeline

#### Paso 4.1: Activar el DAG

1. En Airflow UI, ve a **DAGs**
2. Busca `s3_glue_athena_etl`
3. Activa el toggle (debe estar en azul)

#### Paso 4.2: Ejecutar manualmente

1. Click en el nombre del DAG
2. Click en el botón "Play" (▶️) en la esquina superior derecha
3. Selecciona "Trigger DAG"

#### Paso 4.3: Monitorear ejecución

Verás el grafo del DAG con 10 tareas:

```
upload_raw_data → crawl_raw_data → wait_for_raw_crawl → 
run_glue_job → wait_for_glue_job → crawl_processed_data → 
wait_for_processed_crawl → validate_with_athena → 
wait_for_athena → notify_result
```

**Colores:**
- 🟢 Verde: Éxito
- 🔴 Rojo: Fallo
- 🟡 Amarillo: En ejecución
- ⚪ Gris: Pendiente

**Tiempo estimado**: 5-10 minutos

---

## Validación

### Verificar que el pipeline funcionó

#### 1. Revisar logs en Airflow
- Click en cada tarea → "Log"
- Busca mensajes de éxito

#### 2. Verificar datos en S3

```bash
# Ver datos raw
aws s3 ls s3://${PREFIX}-raw/input/

# Ver datos procesados (Parquet)
aws s3 ls s3://${PREFIX}-processed/output/
```

#### 3. Consultar con Athena

Ve a la consola de Athena y ejecuta:

```sql
SELECT * FROM etl_lab_db.output LIMIT 10;
```

Deberías ver tus transacciones con la columna `processed_date` agregada.

#### 4. Verificar notificación SNS
Revisa tu email, deberías tener un mensaje de SNS con el resultado del pipeline.

---

## Limpieza (Cleanup)

**IMPORTANTE**: Elimina todos los recursos para evitar costos.

### OPCIÓN RÁPIDA: Cleanup Automatizado

Usa el script de cleanup para eliminar todo de forma automática:

```bash
cd scripts
./cleanup.sh mwaa-etl-lab-XXXXX  # Reemplaza XXXXX con tu timestamp
```

El script eliminará automáticamente todos los recursos creados durante el lab.

**Tiempo estimado**: 20-30 minutos (principalmente esperando que MWAA se elimine)

---

### OPCIÓN MANUAL: Cleanup Paso a Paso

Si prefieres eliminar los recursos manualmente:

### Paso 1: Eliminar ambiente MWAA

```bash
aws mwaa delete-environment --name mwaa-etl-lab
```

Espera 20-30 minutos hasta que se elimine completamente.

### Paso 2: Eliminar Glue resources

```bash
aws glue delete-job --job-name transactions_etl_job
aws glue delete-crawler --name raw_data_crawler
aws glue delete-crawler --name processed_data_crawler
aws glue delete-database --name etl_lab_db
```

### Paso 3: Eliminar roles IAM

```bash
aws iam delete-role-policy --role-name MWAAExecutionRole --policy-name MWAAExecutionPolicy
aws iam delete-role --role-name MWAAExecutionRole

aws iam detach-role-policy --role-name GlueETLRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam detach-role-policy --role-name GlueETLRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam delete-role --role-name GlueETLRole
```

### Paso 4: Eliminar SNS topic

```bash
aws sns delete-topic --topic-arn arn:aws:sns:REGION:ACCOUNT:etl-pipeline-alerts
```

### Paso 5: Vaciar y eliminar buckets S3

```bash
aws s3 rm s3://${PREFIX}-raw --recursive
aws s3 rm s3://${PREFIX}-processed --recursive
aws s3 rm s3://${PREFIX}-scripts --recursive
aws s3 rm s3://${PREFIX}-athena-results --recursive
aws s3 rm s3://${PREFIX}-mwaa --recursive

aws s3 rb s3://${PREFIX}-raw
aws s3 rb s3://${PREFIX}-processed
aws s3 rb s3://${PREFIX}-scripts
aws s3 rb s3://${PREFIX}-athena-results
aws s3 rb s3://${PREFIX}-mwaa
```

---

## Recursos adicionales

- [Documentación oficial de MWAA](https://docs.aws.amazon.com/mwaa/)
- [Apache Airflow Providers Amazon](https://airflow.apache.org/docs/apache-airflow-providers-amazon/)
- [AWS Glue Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practices.html)
- [Athena Performance Tuning](https://docs.aws.amazon.com/athena/latest/ug/performance-tuning.html)

**¿Preguntas o problemas?** Déjame saber y te ayudo a resolverlos.

**¿Te gustó el lab?** Compártelo con la comunidad AWS en español.
