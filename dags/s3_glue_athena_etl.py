"""
MWAA ETL Pipeline: S3 → Glue → Athena
Orquesta un pipeline completo de datos usando servicios de AWS

Este DAG implementa un ETL de producción que:
1. Sube datos raw a S3
2. Crea un Glue Data Catalog con un Crawler
3. Transforma datos con Glue ETL Job (PySpark)
4. Re-cataloga datos procesados
5. Valida resultados con Athena
6. Notifica vía SNS

Autor: Carlos Zambrano
Versión: 1.0
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

# ============================================================================
# CONFIGURACIÓN DE VARIABLES
# ============================================================================
# Estas variables deben configurarse en MWAA UI: Admin → Variables → Import Variables → Overwrite

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

# ============================================================================
# DATOS DE EJEMPLO
# ============================================================================
# CSV de ejemplo con transacciones
SAMPLE_CSV_DATA = """transaction_id,customer_id,amount,product,date
1,C001,150.50,Laptop,2025-01-15
2,C002,75.25,Mouse,2025-01-15
3,C003,200.00,Keyboard,2025-01-15
4,C004,50.00,Cable,2025-01-15
5,C005,300.75,Monitor,2025-01-15
6,C006,125.00,Webcam,2025-01-16
7,C007,89.99,Headphones,2025-01-16
8,C008,45.50,USB Hub,2025-01-16
9,C009,199.99,Printer,2025-01-17
10,C010,350.00,Desk,2025-01-17
"""

# ============================================================================
# CONFIGURACIÓN DEL DAG
# ============================================================================
default_args = {
    "owner": "data-team",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
    "email_on_retry": False,
}

with DAG(
    dag_id="s3_glue_athena_etl",
    default_args=default_args,
    description="Pipeline ETL completo con S3, Glue y Athena",
    schedule="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["etl", "glue", "athena", "production", "data-hero"],
) as dag:

    # ========================================================================
    # TASK 1: Subir datos raw a S3
    # ========================================================================
    upload_raw_data = S3CreateObjectOperator(
        task_id="upload_raw_data",
        s3_bucket=SOURCE_BUCKET,
        s3_key=SOURCE_KEY,
        data=SAMPLE_CSV_DATA,
        replace=True,
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 2: Ejecutar Glue Crawler en datos raw
    # ========================================================================
    # El crawler escanea el bucket S3 y registra el schema en Glue Data Catalog
    crawl_raw_data = GlueCrawlerOperator(
        task_id="crawl_raw_data",
        config={"Name": RAW_CRAWLER_NAME},
        wait_for_completion=False,  # No bloquear worker
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 3: Esperar a que termine el crawler raw
    # ========================================================================
    wait_for_raw_crawl = GlueCrawlerSensor(
        task_id="wait_for_raw_crawl",
        crawler_name=RAW_CRAWLER_NAME,
        poke_interval=30,  # Revisar cada 30 segundos
        timeout=600,  # Timeout de 10 minutos
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 4: Ejecutar Glue ETL Job
    # ========================================================================
    # Job de PySpark que transforma CSV → Parquet con limpieza de datos
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
        wait_for_completion=False,  # No bloquear worker
        verbose=True,  # Logs detallados en CloudWatch
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 5: Esperar a que termine el Glue Job
    # ========================================================================
    wait_for_glue_job = GlueJobSensor(
        task_id="wait_for_glue_job",
        job_name=GLUE_JOB_NAME,
        run_id=run_glue_job.output,  # ID del run anterior
        poke_interval=60,  # Revisar cada minuto
        timeout=1800,  # Timeout de 30 minutos
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 6: Ejecutar Glue Crawler en datos procesados
    # ========================================================================
    # Cataloga los archivos Parquet generados por el ETL
    crawl_processed_data = GlueCrawlerOperator(
        task_id="crawl_processed_data",
        config={"Name": PROCESSED_CRAWLER_NAME},
        wait_for_completion=False,
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 7: Esperar a que termine el crawler procesado
    # ========================================================================
    wait_for_processed_crawl = GlueCrawlerSensor(
        task_id="wait_for_processed_crawl",
        crawler_name=PROCESSED_CRAWLER_NAME,
        poke_interval=30,
        timeout=600,
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 8: Validar con Athena
    # ========================================================================
    # Query SQL para validar que los datos procesados existen
    validate_with_athena = AthenaOperator(
        task_id="validate_with_athena",
        query=f"""
            SELECT 
                COUNT(*) as total_records,
                COUNT(DISTINCT customer_id) as unique_customers,
                SUM(CAST(amount AS DOUBLE)) as total_amount
            FROM {GLUE_DATABASE}.output
            WHERE processed_date IS NOT NULL
        """,
        database=GLUE_DATABASE,
        output_location=f"s3://{ATHENA_RESULTS_BUCKET}/",
        workgroup="primary",
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 9: Esperar resultado de Athena
    # ========================================================================
    wait_for_athena = AthenaSensor(
        task_id="wait_for_athena",
        query_execution_id=validate_with_athena.output,
        poke_interval=10,
        timeout=300,
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # TASK 10: Notificar resultado
    # ========================================================================
    # Envía notificación SNS con el resultado del pipeline
    notify_result = SnsPublishOperator(
        task_id="notify_result",
        target_arn=SNS_TOPIC_ARN,
        message="""
        Pipeline ETL Completado
        
        Fecha de ejecución: {{ ds }}
        DAG: {{ dag.dag_id }}
        Run ID: {{ run_id }}
        Estado: {{ ti.state }}
        
        El pipeline ha procesado los datos exitosamente.
        Revisa los resultados en Athena.
        """,
        subject="MWAA ETL Pipeline - Resultado",
        trigger_rule="all_done",  # Ejecutar siempre, incluso si hay fallos
        aws_conn_id="aws_default",
    )

    # ========================================================================
    # DEFINIR DEPENDENCIAS (Flujo secuencial)
    # ========================================================================
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
