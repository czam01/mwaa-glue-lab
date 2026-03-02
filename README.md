# MWAA ETL Lab - Pipeline Completo con AWS

![AWS](https://img.shields.io/badge/AWS-MWAA-orange?logo=amazon-aws)
![Airflow](https://img.shields.io/badge/Airflow-3.0.6-blue?logo=apache-airflow)
![Python](https://img.shields.io/badge/Python-3.10-green?logo=python)
![License](https://img.shields.io/badge/License-Educational-yellow)
![Level](https://img.shields.io/badge/Level-Intermediate-orange)
![Duration](https://img.shields.io/badge/Duration-2--3h-blue)
![Cost](https://img.shields.io/badge/Cost-~$2--5-red)

Laboratorio práctico para aprender a crear pipelines ETL de producción usando Amazon MWAA (Managed Workflows for Apache Airflow) con S3, Glue y Athena.

---

## Índice

- [¿Qué aprenderás?](#-qué-aprenderás)
- [Arquitectura del Pipeline](#-arquitectura-del-pipeline)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Inicio Rápido](#-inicio-rápido)
- [Servicios AWS Utilizados](#-servicios-aws-utilizados)
- [Limpieza de Recursos](#-limpieza-de-recursos)
- [Contenido del DAG](#-contenido-del-dag)
- [Documentación](#-documentación-adicional)


---

## ¿Qué aprenderás?

- Crear y configurar un ambiente de Amazon MWAA
- Orquestar servicios de datos de AWS con Airflow
- Implementar un pipeline ETL completo 
- Usar Glue Crawlers y Glue ETL Jobs
- Validar datos con Athena
- Implementar notificaciones con SNS

## Arquitectura del Pipeline

```
S3 Raw → Glue Crawler → Glue ETL Job → Glue Crawler → Athena → SNS
```

El pipeline procesa datos CSV, los transforma a Parquet, y valida los resultados automáticamente.

## Estructura del Proyecto

```
mwaa-glue-lab/
├── dags/
│   └── s3_glue_athena_etl.py          # DAG de Airflow (10 tasks)
├── scripts/
│   ├── glue_etl_script.py             # Script PySpark para transformación
│   ├── glue-trust-policy.json         # Política IAM para Glue
│   ├── mwaa-trust-policy.json         # Política IAM para MWAA
│   ├── mwaa-execution-policy.json     # Permisos de ejecución
│   ├── requirements.txt               # Dependencias de Airflow
│   ├── sample_data.csv                # Datos de ejemplo
│   ├── setup.sh                       # Setup automatizado ⚡
│   └── cleanup.sh                     # Cleanup automatizado 
├── LAB-MWAA-ETL.md                    # Guía completa del laboratorio
└── README.md                          # Este archivo
```

## Inicio Rápido

**¿Quieres empezar YA?** → Lee [QUICKSTART.md](QUICKSTART.md) para tener todo funcionando en ~1 hora.

### Opción 1: Setup Automatizado (Recomendado)

```bash
# 1. Clonar o descargar este repositorio
cd mwaa-glue-lab

# 2. Dar permisos de ejecución a los scripts
chmod +x scripts/setup.sh scripts/cleanup.sh

# 3. Ejecutar setup (toma ~5 minutos)
cd scripts
./setup.sh

# 4. Seguir las instrucciones para crear el ambiente MWAA
# Ver LAB-MWAA-ETL.md - Fase 2
```

### Opción 2: Setup Manual

Sigue la guía completa paso a paso en [LAB-MWAA-ETL.md](LAB-MWAA-ETL.md)

## Servicios AWS Utilizados

- **Amazon MWAA** - Orquestación con Apache Airflow
- **Amazon S3** - Almacenamiento de datos
- **AWS Glue** - ETL y catálogo de datos
- **Amazon Athena** - Consultas SQL
- **Amazon SNS** - Notificaciones
- **IAM** - Gestión de permisos

## Limpieza de Recursos

```bash
cd scripts
./cleanup.sh mwaa-etl-lab-XXXXX  # Reemplaza XXXXX con tu timestamp
```

El script eliminará automáticamente:
- Ambiente MWAA
- Glue Jobs y Crawlers
- Base de datos de Glue
- SNS Topics
- Roles IAM
- Buckets S3

## Contenido del DAG

El DAG implementa 10 tasks secuenciales:

1. **upload_raw_data** - Sube CSV a S3
2. **crawl_raw_data** - Ejecuta Glue Crawler en datos raw
3. **wait_for_raw_crawl** - Espera a que termine el crawler
4. **run_glue_job** - Ejecuta transformación PySpark
5. **wait_for_glue_job** - Espera a que termine el job
6. **crawl_processed_data** - Cataloga datos procesados
7. **wait_for_processed_crawl** - Espera al segundo crawler
8. **validate_with_athena** - Ejecuta query de validación
9. **wait_for_athena** - Espera resultado de Athena
10. **notify_result** - Envía notificación SNS

## Nivel

**Intermedio** - Requiere conocimientos básicos de:
- AWS (S3, IAM)
- Python
- Conceptos de ETL
- SQL básico

## Duración

- Setup automatizado: 30-40 minutos
- Setup manual: 2-3 horas
- Ejecución del pipeline: 5-10 minutos

## Prerequisitos

- Cuenta AWS con permisos de administrador
- AWS CLI instalado y configurado
- Bash shell (Linux/Mac/WSL)
- Editor de texto

## Documentación Adicional

- **[QUICKSTART.md](QUICKSTART.md)** - Guía de inicio rápido (~1 hora)
- **[LAB-MWAA-ETL.md](LAB-MWAA-ETL.md)** - Guía completa paso a paso
- [Documentación de MWAA](https://docs.aws.amazon.com/mwaa/)
- [Apache Airflow Providers Amazon](https://airflow.apache.org/docs/apache-airflow-providers-amazon/)
- [AWS Glue Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practices.html)


## Créditos

Este laboratorio fue creado como parte del contenido educativo para la comunidad AWS en español.

**Inspirado por**:
- AWS Data Hero Program
- CloudCamp Community
- Apache Airflow Community

**Servicios AWS utilizados**:
- Amazon MWAA
- AWS Glue
- Amazon S3
- Amazon Athena
- Amazon SNS

---

## Comparte tu Experiencia

¿Completaste el lab? ¡Compártelo!

- LinkedIn: Menciona `@Carlos Zambrano`,`@AWS` y `@CloudCamp`

**Aviso importante**: Este proyecto incurre en costos de AWS. Los usuarios son responsables de todos los cargos. Siempre ejecuta el cleanup después del lab.

