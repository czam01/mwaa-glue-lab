#!/bin/bash

# ============================================================================
# Script de Setup para MWAA ETL Lab
# ============================================================================
# Este script automatiza la creación de toda la infraestructura AWS necesaria
# para el lab
#
# Uso: sh setup.sh
# ============================================================================

set -e 

echo "Iniciando setup de MWAA ETL Lab"
echo ""

# ============================================================================
# CONFIGURACIÓN
# ============================================================================
PREFIX="mwaa-etl-lab-$(date +%s)"
REGION="us-east-1"  
GLUE_ROLE_NAME="GlueETLRole"
MWAA_ROLE_NAME="MWAAExecutionRole"
GLUE_DATABASE="etl_lab_db"
GLUE_JOB_NAME="transactions_etl_job"
RAW_CRAWLER="raw_data_crawler"
PROCESSED_CRAWLER="processed_data_crawler"
SNS_TOPIC="etl-pipeline-alerts"

echo "Configuración:"
echo "   Prefix: ${PREFIX}"
echo "   Region: ${REGION}"
echo ""

# ============================================================================
# PASO 1: Crear buckets de S3
# ============================================================================
echo "Paso 1/8: Creando buckets de S3..."

aws s3 mb s3://${PREFIX}-raw --region ${REGION}
aws s3 mb s3://${PREFIX}-processed --region ${REGION}
aws s3 mb s3://${PREFIX}-scripts --region ${REGION}
aws s3 mb s3://${PREFIX}-athena-results --region ${REGION}
aws s3 mb s3://${PREFIX}-mwaa --region ${REGION}

# Crear estructura de carpetas en bucket MWAA
aws s3api put-object --bucket ${PREFIX}-mwaa --key dags/
aws s3api put-object --bucket ${PREFIX}-mwaa --key plugins/
aws s3api put-object --bucket ${PREFIX}-mwaa --key requirements/

echo "Buckets creados"
echo ""

# ============================================================================
# PASO 2: Subir archivos a S3
# ============================================================================
echo "Paso 2/8: Subiendo archivos a S3..."

# Subir script de Glue
aws s3 cp glue_etl_script.py s3://${PREFIX}-scripts/glue_etl_script.py

# Subir requirements.txt para MWAA
aws s3 cp requirements.txt s3://${PREFIX}-mwaa/requirements/requirements.txt

# Subir datos de ejemplo
aws s3 cp sample_data.csv s3://${PREFIX}-raw/input/transactions.csv

echo "Archivos subidos"
echo ""

# ============================================================================
# PASO 3: Crear base de datos en Glue
# ============================================================================
echo "Paso 3/8: Creando base de datos en Glue..."

aws glue create-database \
  --database-input "{
    \"Name\": \"${GLUE_DATABASE}\",
    \"Description\": \"Database for MWAA ETL Lab\"
  }" \
  --region ${REGION}

echo "Base de datos creada: ${GLUE_DATABASE}"
echo ""

# ============================================================================
# PASO 4: Crear rol IAM para Glue
# ============================================================================
echo "Paso 4/8: Creando rol IAM para Glue..."

aws iam create-role \
  --role-name ${GLUE_ROLE_NAME} \
  --assume-role-policy-document file://glue-trust-policy.json

aws iam attach-role-policy \
  --role-name ${GLUE_ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole

aws iam attach-role-policy \
  --role-name ${GLUE_ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

echo "Rol IAM creado: ${GLUE_ROLE_NAME}"
echo ""

# Esperar a que el rol se propague
echo "Esperando propagación del rol (30 segundos)..."
sleep 30

# ============================================================================
# PASO 5: Crear Glue Crawlers
# ============================================================================
echo "Paso 5/8: Creando Glue Crawlers..."

# Crawler para datos raw
aws glue create-crawler \
  --name ${RAW_CRAWLER} \
  --role ${GLUE_ROLE_NAME} \
  --database-name ${GLUE_DATABASE} \
  --targets "{\"S3Targets\": [{\"Path\": \"s3://${PREFIX}-raw/input/\"}]}" \
  --region ${REGION}

# Crawler para datos procesados
aws glue create-crawler \
  --name ${PROCESSED_CRAWLER} \
  --role ${GLUE_ROLE_NAME} \
  --database-name ${GLUE_DATABASE} \
  --targets "{\"S3Targets\": [{\"Path\": \"s3://${PREFIX}-processed/output/\"}]}" \
  --region ${REGION}

echo "Crawlers creados"
echo ""

# ============================================================================
# PASO 6: Crear Glue Job
# ============================================================================
echo "Paso 6/8: Creando Glue Job..."

aws glue create-job \
  --name ${GLUE_JOB_NAME} \
  --role ${GLUE_ROLE_NAME} \
  --command "{
    \"Name\": \"glueetl\",
    \"ScriptLocation\": \"s3://${PREFIX}-scripts/glue_etl_script.py\",
    \"PythonVersion\": \"3\"
  }" \
  --default-arguments "{
    \"--job-language\": \"python\",
    \"--enable-metrics\": \"true\",
    \"--enable-continuous-cloudwatch-log\": \"true\"
  }" \
  --glue-version "4.0" \
  --max-retries 0 \
  --timeout 60 \
  --region ${REGION}

echo "Glue Job creado: ${GLUE_JOB_NAME}"
echo ""

# ============================================================================
# PASO 7: Crear SNS Topic
# ============================================================================
echo "Paso 7/8: Creando SNS Topic..."

SNS_TOPIC_ARN=$(aws sns create-topic \
  --name ${SNS_TOPIC} \
  --region ${REGION} \
  --query 'TopicArn' \
  --output text)

echo "   SNS Topic creado: ${SNS_TOPIC_ARN}"
echo ""
echo "    IMPORTANTE: Suscríbete al topic con tu email:"
echo "   aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint tu-email@ejemplo.com"
echo ""

# ============================================================================
# PASO 8: Crear rol IAM para MWAA
# ============================================================================
echo "Paso 8/8: Creando rol IAM para MWAA..."

# Actualizar la política con el prefix correcto
sed "s/PREFIX/${PREFIX}/g" mwaa-execution-policy.json > mwaa-execution-policy-updated.json

aws iam create-role \
  --role-name ${MWAA_ROLE_NAME} \
  --assume-role-policy-document file://mwaa-trust-policy.json

aws iam put-role-policy \
  --role-name ${MWAA_ROLE_NAME} \
  --policy-name MWAAExecutionPolicy \
  --policy-document file://mwaa-execution-policy-updated.json

echo "   Rol IAM creado: ${MWAA_ROLE_NAME}"
echo ""

# ============================================================================
# RESUMEN
# ============================================================================
echo "Setup completado exitosamente!"
echo ""
echo "Resumen de recursos creados:"
echo "   • Buckets S3: ${PREFIX}-{raw,processed,scripts,athena-results,mwaa}"
echo "   • Glue Database: ${GLUE_DATABASE}"
echo "   • Glue Crawlers: ${RAW_CRAWLER}, ${PROCESSED_CRAWLER}"
echo "   • Glue Job: ${GLUE_JOB_NAME}"
echo "   • SNS Topic: ${SNS_TOPIC_ARN}"
echo "   • IAM Roles: ${GLUE_ROLE_NAME}, ${MWAA_ROLE_NAME}"
echo ""
echo "Próximos pasos:"
echo "   1. Suscríbete al SNS topic con tu email"
echo "   2. Crea el ambiente MWAA desde la consola AWS"
echo "   3. Sube el DAG a s3://${PREFIX}-mwaa/dags/"
echo "   4. Configura las variables en Airflow UI"
echo ""
echo "Guarda estos valores para configurar las variables en MWAA:"
echo ""
echo "source_bucket=${PREFIX}-raw"
echo "source_key=input/transactions.csv"
echo "destination_bucket=${PREFIX}-processed"
echo "scripts_bucket=${PREFIX}-scripts"
echo "athena_results_bucket=${PREFIX}-athena-results"
echo "glue_database=${GLUE_DATABASE}"
echo "glue_job_name=${GLUE_JOB_NAME}"
echo "raw_crawler_name=${RAW_CRAWLER}"
echo "processed_crawler_name=${PROCESSED_CRAWLER}"
echo "glue_iam_role=${GLUE_ROLE_NAME}"
echo "sns_topic_arn=${SNS_TOPIC_ARN}"
echo ""
echo "Guarda el PREFIX para el cleanup: ${PREFIX}"
echo ""

# ============================================================================
# GENERAR ARCHIVO DE VARIABLES
# ============================================================================
echo "Generando archivo de variables de Airflow..."

cat > airflow-variables-${PREFIX}.json <<EOF
{
  "source_bucket": "${PREFIX}-raw",
  "source_key": "input/transactions.csv",
  "destination_bucket": "${PREFIX}-processed",
  "scripts_bucket": "${PREFIX}-scripts",
  "athena_results_bucket": "${PREFIX}-athena-results",
  "glue_database": "${GLUE_DATABASE}",
  "glue_job_name": "${GLUE_JOB_NAME}",
  "raw_crawler_name": "${RAW_CRAWLER}",
  "processed_crawler_name": "${PROCESSED_CRAWLER}",
  "glue_iam_role": "${GLUE_ROLE_NAME}",
  "sns_topic_arn": "${SNS_TOPIC_ARN}"
}
EOF

echo "Archivo generado: airflow-variables-${PREFIX}.json"
echo ""
echo "   Puedes importar estas variables en Airflow UI:"
echo "   Admin → Variables → Import Variables → Selecciona el archivo"
echo ""
