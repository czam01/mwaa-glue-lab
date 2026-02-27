# Inicio Rápido - MWAA ETL Lab

Esta guía te permite tener el lab funcionando en menos de 1 hora.

## Pasos Rápidos

### 1. Preparar el ambiente

```bash

# Dar permisos de ejecución
chmod +x scripts/setup.sh scripts/cleanup.sh
```

### 2. Ejecutar setup automatizado

```bash
cd scripts
./setup.sh
```

**Tiempo**: ~5 minutos

El script creará:
- 5 buckets de S3
- Base de datos de Glue
- 2 Glue Crawlers
- 1 Glue ETL Job
- SNS Topic
- 2 Roles IAM
- Archivo de variables de Airflow

**Guarda el PREFIX** que aparece al final (ej: `mwaa-etl-lab-1234567890`)

### 3. Suscribirse al SNS Topic

```bash
# Reemplaza con tu email y el ARN que te dio el script
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:010438496281:etl-pipeline-alerts \
  --protocol email \
  --notification-endpoint czam01@gmail.com
```

Confirma la suscripción desde tu email.

### 4. Crear ambiente MWAA

Ve a la consola de AWS → Amazon MWAA → Create environment

**Configuración básica:**
- Name: `mwaa-etl-lab`
- Airflow version: `2.8.1`
- S3 Bucket: `s3://mwaa-etl-lab-XXXXX-mwaa` (usa tu PREFIX)
- DAGs folder: `dags/`
- Requirements file: `requirements/requirements.txt`

**Networking:**
- VPC: Default VPC
- Subnets: Selecciona 2 subnets públicas
- Web server access: Public network

**Permissions:**
- Execution role: `MWAAExecutionRole`

**Environment class:**
- `mw1.small`

Click "Create environment"

**Tiempo**: 20-30 minutos ☕

### 5. Subir el DAG

Mientras se crea el ambiente MWAA:

```bash
# Desde la carpeta raíz del proyecto
aws s3 cp dags/s3_glue_athena_etl.py s3://mwaa-etl-lab-XXXXX-mwaa/dags/
```

### 6. Configurar variables en Airflow

Una vez que el ambiente MWAA esté disponible:

1. Abre la consola de MWAA
2. Click en `mwaa-etl-lab`
3. Click en "Open Airflow UI"
4. Ve a **Admin → Variables**
5. Click en "Import Variables"
6. Selecciona el archivo `airflow-variables-mwaa-etl-lab-XXXXX.json` generado por el script

**Alternativa manual**: Copia y pega los valores que te dio el script de setup.

### 7. Ejecutar el pipeline

1. En Airflow UI, ve a **DAGs**
2. Busca `s3_glue_athena_etl`
3. Activa el toggle (debe estar en azul)
4. Click en el nombre del DAG
5. Click en el botón "Play" (▶️)
6. Selecciona "Trigger DAG"

**Tiempo de ejecución**: 5-10 minutos

### 8. Verificar resultados

**En Airflow:**
- Verás las 10 tareas ejecutándose secuencialmente
- Todas deben terminar en verde ✅

**En tu email:**
- Recibirás una notificación de SNS con el resultado

**En Athena:**
```sql
SELECT * FROM etl_lab_db.output LIMIT 10;
```

### 9. Limpiar recursos

**IMPORTANTE**: No olvides limpiar para evitar costos.

```bash
cd scripts
./cleanup.sh mwaa-etl-lab-XXXXX  # Usa tu PREFIX
```

**Tiempo**: 20-30 minutos

---

## 📊 Resumen de Tiempos

| Paso | Tiempo |
|------|--------|
| Setup automatizado | 5 min |
| Crear ambiente MWAA | 20-30 min |
| Configurar variables | 2 min |
| Ejecutar pipeline | 5-10 min |
| Cleanup | 20-30 min |
| **TOTAL** | **~1 hora** |

---

## 🐛 Problemas Comunes

### El DAG no aparece en Airflow UI
**Solución**: Espera 2-3 minutos. Airflow sincroniza cada 5 minutos.

### Error: "Variable not found"
**Solución**: Verifica que importaste el archivo de variables correctamente.

### Error: "Access Denied" en S3
**Solución**: Verifica que el rol MWAAExecutionRole tiene los permisos correctos.

### El crawler falla
**Solución**: Verifica que el archivo CSV se subió a S3 correctamente.

---

## 📚 ¿Quieres más detalles?

Lee la guía completa en [LAB-MWAA-ETL.md](LAB-MWAA-ETL.md)

---

## ✅ Checklist

- [ ] Ejecutar `setup.sh`
- [ ] Guardar el PREFIX
- [ ] Suscribirse al SNS topic
- [ ] Crear ambiente MWAA
- [ ] Subir DAG a S3
- [ ] Importar variables en Airflow
- [ ] Ejecutar el pipeline
- [ ] Verificar resultados
- [ ] Ejecutar `cleanup.sh`

---

¡Listo! Ahora tienes un pipeline ETL de producción funcionando en AWS 🚀
