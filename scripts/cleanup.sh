#!/bin/bash

# ============================================================================
# Script de Cleanup para MWAA ETL Lab
# ============================================================================
# Este script elimina TODOS los recursos creados durante el lab
# para evitar costos innecesarios
#
# Uso: ./cleanup.sh <PREFIX>
# Ejemplo: ./cleanup.sh mwaa-etl-lab-1234567890
# ============================================================================

set -e  # Salir si hay algún error

# Verificar que se proporcionó el PREFIX
if [ -z "$1" ]; then
    echo "❌ Error: Debes proporcionar el PREFIX"
    echo "Uso: ./cleanup.sh <PREFIX>"
    echo "Ejemplo: ./cleanup.sh mwaa-etl-lab-1234567890"
    exit 1
fi

PREFIX=$1
REGION="us-east-1"  # Cambia esto a tu región
GLUE_ROLE_NAME="GlueETLRole"
MWAA_ROLE_NAME="MWAAExecutionRole"
GLUE_DATABASE="etl_lab_db"
GLUE_JOB_NAME="transactions_etl_job"
RAW_CRAWLER="raw_data_crawler"
PROCESSED_CRAWLER="processed_data_crawler"
SNS_TOPIC="etl-pipeline-alerts"
MWAA_ENV_NAME="mwaa-etl-lab"

echo "🧹 Iniciando cleanup de MWAA ETL Lab..."
echo "   PREFIX: ${PREFIX}"
echo ""
echo "⚠️  ADVERTENCIA: Esto eliminará TODOS los recursos del lab"
read -p "¿Estás seguro? (escribe 'yes' para continuar): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelado"
    exit 0
fi

echo ""

# ============================================================================
# PASO 1: Eliminar ambiente MWAA (si existe)
# ============================================================================
echo "🗑️  Paso 1/8: Eliminando ambiente MWAA..."

if aws mwaa get-environment --name ${MWAA_ENV_NAME} --region ${REGION} 2>/dev/null; then
    echo "   Eliminando ambiente MWAA (esto puede tardar 20-30 minutos)..."
    aws mwaa delete-environment --name ${MWAA_ENV_NAME} --region ${REGION}
    echo "   ⏳ Esperando a que se elimine el ambiente..."
    
    # Esperar hasta que el ambiente se elimine
    while aws mwaa get-environment --name ${MWAA_ENV_NAME} --region ${REGION} 2>/dev/null; do
        echo "   Todavía eliminando..."
        sleep 60
    done
    
    echo "   ✅ Ambiente MWAA eliminado"
else
    echo "   ℹ️  No se encontró ambiente MWAA"
fi
echo ""

# ============================================================================
# PASO 2: Eliminar Glue Job
# ============================================================================
echo "🗑️  Paso 2/8: Eliminando Glue Job..."

if aws glue get-job --job-name ${GLUE_JOB_NAME} --region ${REGION} 2>/dev/null; then
    aws glue delete-job --job-name ${GLUE_JOB_NAME} --region ${REGION}
    echo "   ✅ Glue Job eliminado"
else
    echo "   ℹ️  No se encontró Glue Job"
fi
echo ""

# ============================================================================
# PASO 3: Eliminar Glue Crawlers
# ============================================================================
echo "🗑️  Paso 3/8: Eliminando Glue Crawlers..."

if aws glue get-crawler --name ${RAW_CRAWLER} --region ${REGION} 2>/dev/null; then
    aws glue delete-crawler --name ${RAW_CRAWLER} --region ${REGION}
    echo "   ✅ Crawler raw eliminado"
else
    echo "   ℹ️  No se encontró crawler raw"
fi

if aws glue get-crawler --name ${PROCESSED_CRAWLER} --region ${REGION} 2>/dev/null; then
    aws glue delete-crawler --name ${PROCESSED_CRAWLER} --region ${REGION}
    echo "   ✅ Crawler processed eliminado"
else
    echo "   ℹ️  No se encontró crawler processed"
fi
echo ""

# ============================================================================
# PASO 4: Eliminar tablas de Glue Data Catalog
# ============================================================================
echo "🗑️  Paso 4/8: Eliminando tablas de Glue Data Catalog..."

# Obtener todas las tablas de la base de datos
TABLES=$(aws glue get-tables \
    --database-name ${GLUE_DATABASE} \
    --region ${REGION} \
    --query 'TableList[].Name' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$TABLES" ]; then
    for table in $TABLES; do
        aws glue delete-table \
            --database-name ${GLUE_DATABASE} \
            --name ${table} \
            --region ${REGION}
        echo "   ✅ Tabla eliminada: ${table}"
    done
else
    echo "   ℹ️  No se encontraron tablas"
fi
echo ""

# ============================================================================
# PASO 5: Eliminar base de datos de Glue
# ============================================================================
echo "🗑️  Paso 5/8: Eliminando base de datos de Glue..."

if aws glue get-database --name ${GLUE_DATABASE} --region ${REGION} 2>/dev/null; then
    aws glue delete-database --name ${GLUE_DATABASE} --region ${REGION}
    echo "   ✅ Base de datos eliminada"
else
    echo "   ℹ️  No se encontró base de datos"
fi
echo ""

# ============================================================================
# PASO 6: Eliminar SNS Topic
# ============================================================================
echo "🗑️  Paso 6/8: Eliminando SNS Topic..."

SNS_TOPIC_ARN=$(aws sns list-topics \
    --region ${REGION} \
    --query "Topics[?contains(TopicArn, '${SNS_TOPIC}')].TopicArn" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$SNS_TOPIC_ARN" ]; then
    aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN} --region ${REGION}
    echo "   ✅ SNS Topic eliminado"
else
    echo "   ℹ️  No se encontró SNS Topic"
fi
echo ""

# ============================================================================
# PASO 7: Eliminar roles IAM
# ============================================================================
echo "🗑️  Paso 7/8: Eliminando roles IAM..."

# Eliminar rol de MWAA
if aws iam get-role --role-name ${MWAA_ROLE_NAME} 2>/dev/null; then
    aws iam delete-role-policy \
        --role-name ${MWAA_ROLE_NAME} \
        --policy-name MWAAExecutionPolicy 2>/dev/null || true
    aws iam delete-role --role-name ${MWAA_ROLE_NAME}
    echo "   ✅ Rol MWAA eliminado"
else
    echo "   ℹ️  No se encontró rol MWAA"
fi

# Eliminar rol de Glue
if aws iam get-role --role-name ${GLUE_ROLE_NAME} 2>/dev/null; then
    aws iam detach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true
    aws iam delete-role --role-name ${GLUE_ROLE_NAME}
    echo "   ✅ Rol Glue eliminado"
else
    echo "   ℹ️  No se encontró rol Glue"
fi
echo ""

# ============================================================================
# PASO 8: Vaciar y eliminar buckets de S3
# ============================================================================
echo "🗑️  Paso 8/8: Eliminando buckets de S3..."

BUCKETS=(
    "${PREFIX}-raw"
    "${PREFIX}-processed"
    "${PREFIX}-scripts"
    "${PREFIX}-athena-results"
    "${PREFIX}-mwaa"
)

for bucket in "${BUCKETS[@]}"; do
    if aws s3 ls s3://${bucket} 2>/dev/null; then
        echo "   Vaciando bucket: ${bucket}"
        aws s3 rm s3://${bucket} --recursive --region ${REGION}
        aws s3 rb s3://${bucket} --region ${REGION}
        echo "   ✅ Bucket eliminado: ${bucket}"
    else
        echo "   ℹ️  No se encontró bucket: ${bucket}"
    fi
done
echo ""

# ============================================================================
# RESUMEN
# ============================================================================
echo "✅ Cleanup completado exitosamente!"
echo ""
echo "📋 Recursos eliminados:"
echo "   • Ambiente MWAA: ${MWAA_ENV_NAME}"
echo "   • Glue Job: ${GLUE_JOB_NAME}"
echo "   • Glue Crawlers: ${RAW_CRAWLER}, ${PROCESSED_CRAWLER}"
echo "   • Glue Database: ${GLUE_DATABASE}"
echo "   • SNS Topic: ${SNS_TOPIC}"
echo "   • IAM Roles: ${GLUE_ROLE_NAME}, ${MWAA_ROLE_NAME}"
echo "   • Buckets S3: ${PREFIX}-*"
echo ""
echo "💰 Ya no se generarán costos por estos recursos"
echo ""
