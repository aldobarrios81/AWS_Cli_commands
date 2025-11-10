# S3 Access Logging - Enable S3 Access Logging

## Descripción
Scripts para implementar y verificar el logging de acceso en buckets de S3 siguiendo la regla: **"Enable S3 Access Logging"**

## ¿Qué es S3 Access Logging?
S3 Access Logging proporciona registros detallados de las solicitudes realizadas a un bucket de S3. Cada registro de acceso contiene detalles sobre una sola solicitud de acceso, como:
- Solicitante
- Nombre del bucket
- Tiempo de solicitud
- Acción de solicitud
- Estado de respuesta
- Código de error (si corresponde)

## Scripts Disponibles

### 1. `enable-s3-access-logging-all.sh`
**Propósito**: Habilitar S3 Access Logging en TODOS los buckets de la cuenta
**Perfiles soportados**: `metrokia`, `AZLOGICA`, y otros

#### Uso:
```bash
# Para perfil metrokia
./enable-s3-access-logging-all.sh metrokia

# Para perfil AZLOGICA  
./enable-s3-access-logging-all.sh AZLOGICA
```

#### Características:
- ✅ Crea bucket central de logs si no existe
- ✅ Configura políticas de seguridad en bucket de logs
- ✅ Habilita logging en todos los buckets (excepto el de logs)
- ✅ Configuración de lifecycle para gestión de costos
- ✅ Bloqueo de acceso público en bucket de logs
- ✅ Prefijos organizados por bucket origen

### 2. `verify-s3-logging-status.sh`
**Propósito**: Verificar el estado del logging de acceso en buckets S3

#### Uso:
```bash
# Para cualquier perfil
./verify-s3-logging-status.sh metrokia
./verify-s3-logging-status.sh AZLOGICA
```

#### Verificaciones:
- 🔍 Estado de logging por bucket
- 🔍 Existencia de bucket central de logs
- 🔍 Estadísticas de cumplimiento
- 🔍 Identificación de buckets sin logging

## Flujo de Trabajo Recomendado

### 1. Verificación Inicial
```bash
./verify-s3-logging-status.sh metrokia
./verify-s3-logging-status.sh AZLOGICA
```

### 2. Habilitar S3 Access Logging
```bash
./enable-s3-access-logging-all.sh metrokia
./enable-s3-access-logging-all.sh AZLOGICA
```

### 3. Verificación Final
```bash
./verify-s3-logging-status.sh metrokia
./verify-s3-logging-status.sh AZLOGICA
```

## Configuración Automática

### Bucket Central de Logs
- **Nombre**: `central-s3-logs-{ACCOUNT_ID}`
- **Región**: `us-east-1`
- **Configuraciones**:
  - ✅ Acceso público bloqueado
  - ✅ Versioning habilitado
  - ✅ Política restrictiva para S3 Logging Service
  - ✅ Lifecycle policy para gestión de costos

### Estructura de Logs
```
central-s3-logs-{ACCOUNT_ID}/
├── bucket1/
│   ├── 2025-11-10-logs
│   └── 2025-11-11-logs
├── bucket2/
│   ├── 2025-11-10-logs
│   └── 2025-11-11-logs
└── bucket3/
    ├── 2025-11-10-logs
    └── 2025-11-11-logs
```

## Política de Bucket de Logs

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::central-s3-logs-{ACCOUNT_ID}/*",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:s3:::*"
        },
        "StringEquals": {
          "aws:SourceAccount": "{ACCOUNT_ID}"
        }
      }
    },
    {
      "Sid": "S3ServerAccessLogsDeliveryRootAccess",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::central-s3-logs-{ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceAccount": "{ACCOUNT_ID}"
        }
      }
    }
  ]
}
```

## Gestión de Costos (Lifecycle Policy)

Los logs se mueven automáticamente según esta política:
- **Día 0-30**: Standard Storage
- **Día 30-90**: Standard-IA (Infrequent Access)
- **Día 90-365**: Glacier
- **Después de 365 días**: Eliminación automática

## Beneficios de Seguridad

1. **Trazabilidad Completa**: Registro de todos los accesos a buckets
2. **Detección de Anomalías**: Identificar patrones de acceso inusuales
3. **Cumplimiento**: Satisface requisitos de auditoría y compliance
4. **Forense**: Investigación de incidentes de seguridad
5. **Monitoreo**: Base para alertas y dashboards de seguridad

## Información de Logs

Cada entrada de log contiene:
- **Bucket Owner**: Propietario del bucket
- **Bucket**: Nombre del bucket
- **Time**: Tiempo de la solicitud (UTC)
- **Remote IP**: Dirección IP del solicitante
- **Requester**: Principal AWS que realizó la solicitud
- **Request ID**: ID único de la solicitud
- **Operation**: Operación solicitada
- **Key**: "Clave" (nombre de archivo) del objeto
- **Request-URI**: Request-URI parte de la HTTP request
- **HTTP status**: Código de estado HTTP
- **Error Code**: Código de error S3 (si aplica)
- **Bytes Sent**: Número de bytes de respuesta
- **Object Size**: Tamaño total del objeto
- **Total Time**: Tiempo total para procesar la solicitud
- **Turn-Around Time**: Tiempo desde S3 recibió la solicitud completa
- **Referrer**: Valor del header HTTP referer
- **User-Agent**: Valor del header HTTP user-agent
- **Version Id**: ID de versión en el request
- **Host Id**: Host ID del request
- **Signature Version**: Versión de firma usado para autenticar
- **Cipher Suite**: Suite de cifrado negociado para SSL
- **Authentication Type**: Tipo de autenticación usado
- **Host Header**: Endpoint usado para conectar a S3
- **TLS version**: Versión TLS negociada

## Consideraciones Importantes

### Tiempos de Entrega
- Los logs pueden tardar **hasta 24 horas** en aparecer
- Los logs se entregan de forma **best effort**
- No hay garantía de entrega del 100%

### Formato de Logs
- Los logs se almacenan en formato de texto plano
- Un registro por línea
- Campos separados por espacios
- Algunos campos pueden estar vacíos (representados como "-")

### Costos
- **Sin costo** por habilitar el logging
- **Costos de almacenamiento** por los logs generados
- **Costos de solicitudes** por entregar los logs al bucket destino

## Análisis de Logs

### Herramientas Recomendadas
- **AWS Athena**: Consultas SQL sobre logs
- **Amazon CloudWatch Insights**: Análisis en tiempo real
- **AWS CloudTrail Insights**: Detección de patrones anómalos
- **Herramientas de terceros**: Splunk, ELK Stack, etc.

### Consultas Útiles
```sql
-- Top 10 IPs con más solicitudes
SELECT remote_ip, COUNT(*) as request_count
FROM s3_access_logs
GROUP BY remote_ip
ORDER BY request_count DESC
LIMIT 10;

-- Errores 4xx y 5xx
SELECT operation, http_status_code, COUNT(*) as error_count
FROM s3_access_logs
WHERE http_status_code >= 400
GROUP BY operation, http_status_code
ORDER BY error_count DESC;

-- Objetos más descargados
SELECT key, COUNT(*) as download_count
FROM s3_access_logs
WHERE operation = 'REST.GET.OBJECT'
GROUP BY key
ORDER BY download_count DESC
LIMIT 20;
```

## Troubleshooting

### Error de Credenciales
```bash
# Verificar configuración
aws configure list --profile metrokia
aws configure list --profile AZLOGICA

# Verificar acceso
aws sts get-caller-identity --profile metrokia
aws sts get-caller-identity --profile AZLOGICA
```

### Bucket de Logs No Creado
```bash
# Verificar permisos necesarios
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
  --action-names s3:CreateBucket s3:PutBucketLogging \
  --resource-arns arn:aws:s3:::*
```

### Logs No Aparecen
1. **Esperar 24 horas**: Los logs pueden tardar
2. **Verificar política del bucket**: Debe permitir logging.s3.amazonaws.com
3. **Verificar región**: Bucket y configuración deben estar en la misma región
4. **Verificar permisos**: El bucket destino debe tener los permisos correctos

### Sin Permisos para Configurar Logging
Asegurar que el usuario/rol tenga:
- `s3:PutBucketLogging`
- `s3:GetBucketLogging`
- `s3:CreateBucket` (para bucket de logs)
- `s3:PutBucketPolicy` (para bucket de logs)
- `s3:PutPublicAccessBlock` (para bucket de logs)