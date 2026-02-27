"""
Glue ETL Script - Transformación de datos CSV a Parquet
Lee datos raw desde S3, aplica transformaciones y escribe resultado en formato Parquet
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import current_date

# Obtener argumentos del job
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source_path', 'destination_path'])

# Inicializar contextos de Spark y Glue
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

print(f"Leyendo datos desde: {args['source_path']}")

# Leer datos raw desde S3 (CSV con headers)
df = spark.read.option("header", "true").csv(args['source_path'])

print(f"Registros leídos: {df.count()}")

# Transformaciones
# 1. Eliminar filas con valores nulos en cualquier columna
df_clean = df.dropna()

# 2. Agregar columna de fecha de procesamiento
df_clean = df_clean.withColumn("processed_date", current_date())

print(f"Registros después de limpieza: {df_clean.count()}")
print("Schema del DataFrame procesado:")
df_clean.printSchema()

# Escribir resultado como Parquet en S3
print(f"Escribiendo datos a: {args['destination_path']}")
df_clean.write.mode("overwrite").parquet(args['destination_path'])

print("ETL completado exitosamente")

job.commit()
