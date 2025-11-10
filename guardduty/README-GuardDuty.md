# Amazon GuardDuty - Enable Amazon GuardDuty

## Descripción
Scripts para implementar y verificar Amazon GuardDuty siguiendo la regla: **"Enable Amazon GuardDuty"**

## ¿Qué es Amazon GuardDuty?
Amazon GuardDuty es un servicio de detección de amenazas que utiliza machine learning, análisis de comportamiento y feed de inteligencia de amenazas para identificar actividades maliciosas y comportamientos anómalos en tu entorno de AWS.

### Características Principales:
- **Detección de amenazas en tiempo real**
- **Machine Learning y análisis de comportamiento**
- **Análisis de DNS, VPC Flow Logs y CloudTrail**
- **Feed de inteligencia de amenazas**
- **Sin infraestructura que gestionar**

## Scripts Disponibles

### 1. `enable-guardduty-all-regions.sh`
**Propósito**: Habilitar Amazon GuardDuty en la región principal (us-east-1)
**Perfiles soportados**: `metrokia`, `AZLOGICA`, y otros

#### Uso:
```bash
# Para perfil metrokia
./enable-guardduty-all-regions.sh metrokia

# Para perfil AZLOGICA  
./enable-guardduty-all-regions.sh AZLOGICA
```

#### Características:
- ✅ Detección automática de estado actual
- ✅ Configuración con características avanzadas
- ✅ Frecuencia de hallazgos optimizada (15 minutos)
- ✅ Habilitación de protecciones adicionales
- ✅ Fallback a configuración básica si las avanzadas fallan
- ✅ Actualización de detectores existentes

### 2. `verify-guardduty-status.sh`
**Propósito**: Verificar el estado y configuración de GuardDuty

#### Uso:
```bash
# Para cualquier perfil
./verify-guardduty-status.sh metrokia
./verify-guardduty-status.sh AZLOGICA
```

#### Verificaciones:
- 🔍 Estado del detector de GuardDuty
- 🔍 Características avanzadas habilitadas
- 🔍 Frecuencia de publicación de hallazgos
- 🔍 Hallazgos recientes (últimos 7 días)
- 🔍 Configuración de notificaciones
- 🔍 Puntuación de seguridad

## Flujo de Trabajo Recomendado

### 1. Verificación Inicial
```bash
./verify-guardduty-status.sh metrokia
./verify-guardduty-status.sh AZLOGICA
```

### 2. Habilitar GuardDuty
```bash
./enable-guardduty-all-regions.sh metrokia
./enable-guardduty-all-regions.sh AZLOGICA
```

### 3. Verificación Final
```bash
./verify-guardduty-status.sh metrokia
./verify-guardduty-status.sh AZLOGICA
```

## Características Avanzadas Habilitadas

### Protecciones Adicionales:
1. **S3 Data Events**: Monitoreo de actividades sospechosas en S3
2. **EKS Audit Logs**: Análisis de logs de auditoría de Kubernetes
3. **EBS Malware Protection**: Detección de malware en volúmenes EBS
4. **RDS Login Events**: Monitoreo de eventos de login a bases de datos
5. **EKS Runtime Monitoring**: Monitoreo en tiempo de ejecución de EKS
6. **Lambda Network Logs**: Análisis de tráfico de red de Lambda

### Configuración Optimizada:
- **Frecuencia de hallazgos**: 15 minutos (máxima frecuencia)
- **Estado**: Habilitado permanentemente
- **Service Role**: Creado automáticamente por AWS

## Tipos de Amenazas Detectadas

### 1. Reconnaissance (Reconocimiento)
- Port scanning
- Network probing
- Unusual API call patterns

### 2. Instance Compromises
- Cryptocurrency mining
- Malware infections
- Backdoor communications
- Data exfiltration

### 3. Account Compromises
- Unusual console logins
- API calls from unusual locations
- Privilege escalation attempts
- Suspicious IAM activity

### 4. Bucket Compromises
- Suspicious S3 access patterns
- Data exfiltration from S3
- Unusual S3 API calls

### 5. DNS Exfiltration
- DNS tunneling
- Domain Generation Algorithm (DGA) domains
- Communication with known malicious domains

## Niveles de Severidad

- **LOW (0.1 - 3.9)**: Actividad sospechosa menor
- **MEDIUM (4.0 - 6.9)**: Actividad moderadamente sospechosa
- **HIGH (7.0 - 8.9)**: Actividad altamente sospechosa
- **CRITICAL (9.0 - 10.0)**: Actividad crítica que requiere atención inmediata

## Configuración de Notificaciones

### EventBridge (Recomendado)
```bash
# Crear regla para hallazgos de alta severidad
aws events put-rule \
    --name GuardDutyHighSeverityFindings \
    --event-pattern '{
        "source": ["aws.guardduty"],
        "detail-type": ["GuardDuty Finding"],
        "detail": {
            "severity": [7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 9.0, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 10.0]
        }
    }' \
    --profile metrokia

# Agregar target (SNS, Lambda, etc.)
aws events put-targets \
    --rule GuardDutyHighSeverityFindings \
    --targets "Id"="1","Arn"="arn:aws:sns:us-east-1:ACCOUNT:security-alerts" \
    --profile metrokia
```

### CloudWatch Alarms
```bash
# Crear alarma para hallazgos críticos
aws cloudwatch put-metric-alarm \
    --alarm-name "GuardDuty-Critical-Findings" \
    --alarm-description "Alert on critical GuardDuty findings" \
    --metric-name "FindingCount" \
    --namespace "AWS/GuardDuty" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=DetectorId,Value=DETECTOR_ID \
    --evaluation-periods 1 \
    --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:security-alerts \
    --profile metrokia
```

## Integración con AWS Security Hub

GuardDuty se integra automáticamente con AWS Security Hub si está habilitado:

```bash
# Habilitar Security Hub
aws securityhub enable-security-hub --profile metrokia

# Los hallazgos de GuardDuty aparecerán automáticamente en Security Hub
```

## Gestión de Costos

### Precios (región us-east-1):
- **CloudTrail Analysis**: $4.00/million eventos
- **DNS Logs Analysis**: $1.50/GB
- **VPC Flow Logs Analysis**: $1.00/GB
- **S3 Data Events**: $0.80/million eventos
- **EKS Audit Logs**: $0.50/GB
- **Malware Protection**: $0.20/GB escaneado

### Optimización de Costos:
1. **Usar Intelligent Tiering** para datos S3
2. **Configurar filtros** para reducir eventos innecesarios
3. **Revisar regularmente** las características habilitadas
4. **Usar tags** para tracking de costos

## Respuesta a Incidentes

### Proceso Recomendado:
1. **Identificación**: Revisar hallazgo en consola
2. **Análisis**: Evaluar severidad y contexto
3. **Contención**: Aislar recursos afectados
4. **Erradicación**: Eliminar amenaza
5. **Recuperación**: Restaurar servicios
6. **Lecciones aprendidas**: Mejorar defensas

### Automatización de Respuesta:
```python
# Ejemplo: Lambda para respuesta automática
import boto3

def lambda_handler(event, context):
    # Obtener detalles del hallazgo
    finding = event['detail']
    severity = finding['severity']
    
    if severity >= 7.0:  # High/Critical
        # Notificar equipo de seguridad
        sns = boto3.client('sns')
        sns.publish(
            TopicArn='arn:aws:sns:us-east-1:ACCOUNT:security-team',
            Message=f"Critical GuardDuty Finding: {finding['title']}",
            Subject='URGENT: Security Alert'
        )
        
        # Si es compromiso de instancia, crear snapshot
        if 'EC2' in finding['service']['serviceName']:
            ec2 = boto3.client('ec2')
            # Lógica para crear snapshot y aislar instancia
```

## Mejores Prácticas

### Configuración:
1. **Habilitar en todas las regiones utilizadas**
2. **Configurar notificaciones** para severidades altas
3. **Integrar con Security Hub** para vista centralizada
4. **Usar trusted IP lists** para reducir falsos positivos
5. **Configurar threat intelligence feeds** personalizados

### Monitoreo:
1. **Revisar hallazgos diariamente**
2. **Crear dashboards** en CloudWatch
3. **Establecer SLAs** para respuesta a incidentes
4. **Realizar ejercicios** de respuesta a incidentes
5. **Mantener playbooks** actualizados

### Operaciones:
1. **Entrenar al equipo** en interpretación de hallazgos
2. **Documentar procedimientos** de respuesta
3. **Mantener inventario** de activos críticos
4. **Realizar auditorías** regulares de configuración
5. **Implementar SOAR** para automatización

## Análisis de Hallazgos

### Campos Importantes:
- **Type**: Tipo de amenaza detectada
- **Severity**: Nivel de criticidad (0-10)
- **Confidence**: Nivel de confianza (0-10)
- **Service**: Servicio AWS afectado
- **Resource**: Recurso específico afectado
- **RemoteIpDetails**: Información de IP externa
- **Action**: Acción maliciosa detectada

### Consultas Útiles (CloudWatch Insights):
```sql
-- Top 10 tipos de hallazgos
fields @timestamp, type, severity
| filter @message like /GuardDuty/
| stats count() by type
| sort count desc
| limit 10

-- Hallazgos por severidad
fields @timestamp, severity, title
| filter severity >= 7.0
| sort @timestamp desc
| limit 50

-- IPs más frecuentes en hallazgos
fields @timestamp, service.remoteIpDetails.ipAddressV4, type
| filter service.remoteIpDetails.ipAddressV4 exists
| stats count() by service.remoteIpDetails.ipAddressV4
| sort count desc
| limit 20
```

## Troubleshooting

### Error de Credenciales
```bash
# Verificar configuración
aws configure list --profile metrokia
aws configure list --profile AZLOGICA

# Verificar permisos
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
  --action-names guardduty:CreateDetector guardduty:GetDetector \
  --resource-arns "*"
```

### GuardDuty No Se Habilita
1. **Verificar permisos IAM** necesarios
2. **Verificar Service-Linked Role**
3. **Verificar limitaciones de región**
4. **Contactar soporte AWS** si persiste

### Sin Hallazgos Generados
1. **Esperar 24-48 horas** para datos iniciales
2. **Verificar fuentes de datos** (CloudTrail, DNS, VPC Flow Logs)
3. **Generar tráfico de prueba** (opcional)
4. **Revisar trusted IP lists**

### Permisos Requeridos
El usuario/rol debe tener:
- `guardduty:CreateDetector`
- `guardduty:GetDetector`
- `guardduty:UpdateDetector`
- `guardduty:ListDetectors`
- `guardduty:ListFindings`
- `guardduty:GetFindings`
- `iam:CreateServiceLinkedRole` (para crear service role)

## Integración con Otros Servicios

### AWS Config
- Reglas para validar configuración de GuardDuty
- Remediation automática para configuraciones incorrectas

### AWS Systems Manager
- Documentos de runbook para respuesta a incidentes
- Patch management para instancias comprometidas

### AWS CloudFormation
- Templates para despliegue consistente
- Stack sets para múltiples cuentas/regiones

### Herramientas de Terceros
- Splunk, ELK Stack para análisis avanzado
- SIEM solutions para correlación
- Herramientas de orquestación (Phantom, Demisto)