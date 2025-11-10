# GuardDuty Realtime Alerts - Enable Realtime Alerts for GuardDuty

## Descripción
Scripts para implementar y verificar alertas en tiempo real de Amazon GuardDuty siguiendo la regla: **"Enable Realtime Alerts for GuardDuty"**

## ¿Qué son las Alertas en Tiempo Real de GuardDuty?
Las alertas en tiempo real permiten recibir notificaciones inmediatas cuando GuardDuty detecta actividades maliciosas o sospechosas, utilizando Amazon SNS y Amazon EventBridge para entregar notificaciones por email, SMS, o otros endpoints.

### Beneficios:
- **Respuesta inmediata** a amenazas críticas
- **Notificaciones personalizadas** por severidad
- **Múltiples canales** de notificación
- **Escalamiento automático** para diferentes tipos de amenazas
- **Integración** con herramientas de respuesta a incidentes

## Scripts Disponibles

### 1. `enable-guardduty-realtime-alerts.sh`
**Propósito**: Configurar alertas en tiempo real para GuardDuty
**Perfiles soportados**: `metrokia`, `AZLOGICA`, y otros

#### Uso:
```bash
# Configuración básica
./enable-guardduty-realtime-alerts.sh metrokia

# Con suscripción email automática
./enable-guardduty-realtime-alerts.sh metrokia security@company.com
./enable-guardduty-realtime-alerts.sh AZLOGICA admin@company.com
```

#### Características:
- ✅ Verificación previa de GuardDuty habilitado
- ✅ Creación automática de SNS Topic
- ✅ Configuración de políticas de seguridad
- ✅ Suscripción email opcional
- ✅ Múltiples reglas de EventBridge por severidad
- ✅ Formateo inteligente de mensajes
- ✅ Detección específica de cryptomining/malware

### 2. `verify-guardduty-alerts.sh`
**Propósito**: Verificar la configuración de alertas en tiempo real

#### Uso:
```bash
# Para cualquier perfil
./verify-guardduty-alerts.sh metrokia
./verify-guardduty-alerts.sh AZLOGICA
```

#### Verificaciones:
- 🔍 Estado del SNS Topic
- 🔍 Suscripciones configuradas y confirmadas
- 🔍 Reglas de EventBridge activas
- 🔍 Targets correctamente configurados
- 🔍 Patrones de eventos por severidad
- 🔍 Prueba de conectividad opcional

## Flujo de Trabajo Recomendado

### 1. Verificar GuardDuty Habilitado
```bash
./verify-guardduty-status.sh metrokia
./verify-guardduty-status.sh AZLOGICA
```

### 2. Configurar Alertas en Tiempo Real
```bash
./enable-guardduty-realtime-alerts.sh metrokia security@company.com
./enable-guardduty-realtime-alerts.sh AZLOGICA admin@company.com
```

### 3. Verificar Configuración de Alertas
```bash
./verify-guardduty-alerts.sh metrokia
./verify-guardduty-alerts.sh AZLOGICA
```

### 4. Confirmar Suscripciones Email
- Revisar bandeja de entrada
- Hacer clic en "Confirm subscription"
- Verificar estado en AWS Console

## Arquitectura de Alertas

### Componentes:
1. **Amazon GuardDuty**: Service de detección de amenazas
2. **Amazon EventBridge**: Enrutamiento de eventos
3. **Amazon SNS**: Sistema de notificaciones
4. **Reglas personalizadas**: Filtrado por severidad

### Flujo de Alertas:
```
GuardDuty Finding → EventBridge Rule → SNS Topic → Email/SMS/Webhook
```

## Configuración Automática

### SNS Topic Creado:
- **Nombre**: `guardduty-realtime-alerts`
- **Display Name**: "GuardDuty Security Alerts"
- **Política**: Acceso restringido a EventBridge y cuenta actual

### Reglas de EventBridge:

#### 1. Alta/Crítica Severidad (≥7.0)
- **Nombre**: `GuardDuty-HighSeverity-Alerts`
- **Patrón**: Severidad numérica ≥ 7.0
- **Formato**: Mensaje detallado con información completa
- **Urgencia**: IMMEDIATE ACTION REQUIRED

#### 2. Severidad Media (4.0-6.9)
- **Nombre**: `GuardDuty-MediumSeverity-Summary`
- **Patrón**: Severidad numérica 4.0-6.9
- **Formato**: Mensaje resumido
- **Urgencia**: Review when convenient

#### 3. Cryptomining/Malware
- **Nombre**: `GuardDuty-Cryptocurrency-Mining`
- **Patrón**: Tipos específicos de amenaza
- **Formato**: Alerta crítica especializada
- **Urgencia**: IMMEDIATE ISOLATION REQUIRED

## Formatos de Mensaje

### Alerta de Alta Severidad:
```
🚨 GUARDDUTY ALERT - HIGH/CRITICAL SEVERITY

📊 Severity: 8.5
🎯 Type: Trojan:EC2/DropPoint
📋 Title: EC2 instance is communicating with a disreputable IP address
📝 Description: EC2 instance has established a TCP connection with IP address on a Trojan list

🔍 Details:
• Account: 123456789012
• Region: us-east-1
• Service: EC2
• Resource Type: Instance
• Time: 2025-11-10T15:30:00Z

🌐 Console: https://us-east-1.console.aws.amazon.com/guardduty/home?region=us-east-1

⚠️ IMMEDIATE ACTION REQUIRED
```

### Alerta de Cryptomining:
```
🚨🔴 CRITICAL THREAT DETECTED 🔴🚨

💰 CRYPTOCURRENCY MINING / MALWARE

📊 Severity: 8.8
🎯 Type: CryptoCurrency:EC2/BitcoinTool.B
📋 Title: EC2 instance is communicating with Bitcoin mining pools

🔍 Account: 123456789012
🌍 Region: us-east-1
⏰ Time: 2025-11-10T15:30:00Z

⚠️⚠️ IMMEDIATE ISOLATION AND INVESTIGATION REQUIRED ⚠️⚠️
```

## Tipos de Suscripciones Soportadas

### Email
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:guardduty-realtime-alerts \
  --protocol email \
  --notification-endpoint security-team@company.com \
  --profile metrokia
```

### SMS
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:guardduty-realtime-alerts \
  --protocol sms \
  --notification-endpoint +1234567890 \
  --profile metrokia
```

### HTTPS Webhook
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:guardduty-realtime-alerts \
  --protocol https \
  --notification-endpoint https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
  --profile metrokia
```

### Lambda Function
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:guardduty-realtime-alerts \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:us-east-1:ACCOUNT:function:process-security-alert \
  --profile metrokia
```

## Integración con Herramientas

### Slack
```python
# Lambda function para Slack
import json
import urllib3

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    slack_message = {
        "text": f"🚨 GuardDuty Alert: {message['detail']['title']}",
        "attachments": [{
            "color": "danger" if message['detail']['severity'] >= 7.0 else "warning",
            "fields": [
                {"title": "Severity", "value": str(message['detail']['severity']), "short": True},
                {"title": "Type", "value": message['detail']['type'], "short": True},
                {"title": "Account", "value": message['detail']['accountId'], "short": True},
                {"title": "Region", "value": message['detail']['region'], "short": True}
            ]
        }]
    }
    
    http = urllib3.PoolManager()
    response = http.request('POST', 
                           'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK',
                           body=json.dumps(slack_message),
                           headers={'Content-Type': 'application/json'})
    
    return {"statusCode": 200}
```

### PagerDuty
```python
# Lambda function para PagerDuty
import json
import requests

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    if message['detail']['severity'] >= 7.0:  # Solo alertas críticas
        pagerduty_payload = {
            "routing_key": "YOUR_INTEGRATION_KEY",
            "event_action": "trigger",
            "payload": {
                "summary": f"GuardDuty: {message['detail']['title']}",
                "severity": "critical" if message['detail']['severity'] >= 8.0 else "error",
                "source": message['detail']['service']['serviceName'],
                "custom_details": {
                    "type": message['detail']['type'],
                    "account_id": message['detail']['accountId'],
                    "region": message['detail']['region'],
                    "resource_type": message['detail']['resource']['resourceType']
                }
            }
        }
        
        response = requests.post(
            'https://events.pagerduty.com/v2/enqueue',
            json=pagerduty_payload
        )
    
    return {"statusCode": 200}
```

### Microsoft Teams
```python
# Lambda function para Teams
import json
import urllib3

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    teams_message = {
        "@type": "MessageCard",
        "@context": "http://schema.org/extensions",
        "themeColor": "FF0000" if message['detail']['severity'] >= 7.0 else "FFA500",
        "summary": f"GuardDuty Alert: {message['detail']['title']}",
        "sections": [{
            "activityTitle": "🚨 Amazon GuardDuty Alert",
            "activitySubtitle": message['detail']['title'],
            "facts": [
                {"name": "Severity", "value": str(message['detail']['severity'])},
                {"name": "Type", "value": message['detail']['type']},
                {"name": "Account", "value": message['detail']['accountId']},
                {"name": "Region", "value": message['detail']['region']}
            ]
        }]
    }
    
    http = urllib3.PoolManager()
    response = http.request('POST',
                           'YOUR_TEAMS_WEBHOOK_URL',
                           body=json.dumps(teams_message),
                           headers={'Content-Type': 'application/json'})
    
    return {"statusCode": 200}
```

## Personalización Avanzada

### Filtros Personalizados
```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [{"numeric": [">=", 7.0]}],
    "type": [{"prefix": "Backdoor"}, {"prefix": "Trojan"}],
    "service": {
      "serviceName": ["guardduty"]
    },
    "resource": {
      "resourceType": ["Instance"]
    }
  }
}
```

### Horarios de Notificación
```python
# Lambda function con horarios
import json
from datetime import datetime, timezone

def lambda_handler(event, context):
    current_hour = datetime.now(timezone.utc).hour
    
    # Solo alertas críticas fuera de horario laboral (18:00-08:00 UTC)
    if current_hour < 8 or current_hour >= 18:
        severity_threshold = 8.0
    else:
        severity_threshold = 7.0
    
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    if message['detail']['severity'] < severity_threshold:
        return {"statusCode": 200, "body": "Alert suppressed due to time/severity"}
    
    # Procesar alerta normalmente...
```

### Agregación de Alertas
```python
# Lambda para agrupar alertas similares
import json
import boto3
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('guardduty-alert-aggregation')

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    # Crear clave de agregación
    agg_key = f"{message['detail']['type']}#{message['detail']['accountId']}"
    
    # Verificar si ya existe en la ventana de tiempo
    response = table.get_item(Key={'aggregation_key': agg_key})
    
    if 'Item' in response:
        # Actualizar contador
        table.update_item(
            Key={'aggregation_key': agg_key},
            UpdateExpression='SET alert_count = alert_count + :inc',
            ExpressionAttributeValues={':inc': 1}
        )
    else:
        # Primera ocurrencia, crear entrada
        table.put_item(Item={
            'aggregation_key': agg_key,
            'alert_count': 1,
            'first_seen': datetime.utcnow().isoformat(),
            'ttl': int((datetime.utcnow() + timedelta(hours=1)).timestamp())
        })
        
        # Enviar alerta solo en primera ocurrencia
        # ... código para enviar alerta ...
```

## Monitoreo y Métricas

### CloudWatch Metrics
```bash
# Crear alarma para fallos de entrega
aws cloudwatch put-metric-alarm \
  --alarm-name "SNS-GuardDuty-Delivery-Failures" \
  --alarm-description "Alert when SNS fails to deliver GuardDuty notifications" \
  --metric-name "NumberOfNotificationsFailed" \
  --namespace "AWS/SNS" \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=TopicName,Value=guardduty-realtime-alerts \
  --evaluation-periods 1
```

### Dashboard de Alertas
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", "guardduty-realtime-alerts"],
          [".", "NumberOfNotificationsDelivered", ".", "."],
          [".", "NumberOfNotificationsFailed", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "GuardDuty Alert Delivery Metrics"
      }
    }
  ]
}
```

## Gestión de Costos

### Precios SNS (región us-east-1):
- **Publicación**: $0.50 por millón de requests
- **Email**: $2.00 por 100,000 emails
- **SMS**: $0.75 por mensaje (varía por país)
- **HTTP/HTTPS**: $0.60 por millón de requests

### Optimización:
1. **Filtrar por severidad** para reducir volumen
2. **Usar agregación** para hallazgos similares
3. **Configurar horarios** para alertas no críticas
4. **Revisar suscripciones** regularmente

## Troubleshooting

### Emails No Llegan
1. **Verificar suscripción confirmada**
2. **Revisar carpeta de spam/junk**
3. **Verificar política del Topic**
4. **Comprobar límites de SNS**

### EventBridge No Dispara
1. **Verificar patrones de eventos**
2. **Comprobar estado de reglas (ENABLED)**
3. **Verificar permisos de targets**
4. **Revisar logs de CloudWatch**

### Demasiadas Alertas
1. **Ajustar filtros de severidad**
2. **Implementar agregación**
3. **Usar horarios de supresión**
4. **Configurar trusted IP lists en GuardDuty**

### Permisos Requeridos
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Publish",
        "sns:ListSubscriptionsByTopic",
        "events:PutRule",
        "events:PutTargets",
        "events:ListRules",
        "events:ListTargetsByRule"
      ],
      "Resource": "*"
    }
  ]
}
```

## Pruebas y Validación

### Generar Hallazgo de Prueba
```bash
# Crear instancia con nombre sospechoso (genera hallazgo)
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t2.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=malicious-activity}]'
```

### Simular Tráfico Sospechoso
```bash
# Desde instancia EC2, hacer requests a IPs conocidas como maliciosas
# SOLO EN AMBIENTE DE PRUEBAS
curl -m 5 198.51.100.1  # IP de ejemplo en documentación
```

### Verificar Entrega
1. **Revisar métricas de SNS**
2. **Comprobar logs de EventBridge**
3. **Verificar bandeja de entrada**
4. **Usar mensaje de prueba del script**

## Mejores Prácticas

### Configuración:
1. **Múltiples suscripciones** para redundancia
2. **Diferentes canales** por severidad
3. **Formateo claro** de mensajes
4. **Escalamiento automático** para críticos

### Operaciones:
1. **Confirmar suscripciones** inmediatamente
2. **Probar alertas** regularmente
3. **Documentar procedimientos** de respuesta
4. **Mantener contactos** actualizados

### Seguridad:
1. **Políticas restrictivas** en SNS Topics
2. **Cifrado en tránsito** para endpoints
3. **Logs de auditoría** habilitados
4. **Acceso por roles** específicos