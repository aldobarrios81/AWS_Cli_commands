#!/usr/bin/env bash
set -euo pipefail

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil] [email_opcional]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    echo ""
    echo "Ejemplos:"
    echo "  $0 metrokia"
    echo "  $0 AZLOGICA security@company.com"
    echo "  $0 metrokia admin@company.com"
    exit 1
fi

PROFILE="$1"
EMAIL_ENDPOINT="${2:-}"  # Email opcional como segundo parámetro
DEFAULT_REGION="us-east-1"
SNS_TOPIC_NAME="guardduty-realtime-alerts"

echo "=== Configurando alertas en tiempo real de GuardDuty ==="
echo "Perfil: $PROFILE | Región: $DEFAULT_REGION"
if [ -n "$EMAIL_ENDPOINT" ]; then
    echo "Email de notificación: $EMAIL_ENDPOINT"
fi
echo ""

# Verificar credenciales y mostrar información de la cuenta
echo "🔍 Verificando credenciales para perfil: $PROFILE"
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    echo "Verificar configuración: aws configure list --profile $PROFILE"
    exit 1
fi

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account' 2>/dev/null)
CURRENT_USER=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)

echo "✅ Credenciales válidas"
echo "   📋 Account ID: $ACCOUNT_ID"
echo "   👤 Usuario/Rol: $CURRENT_USER"
echo ""

# Verificar que GuardDuty esté habilitado primero
REGION="$DEFAULT_REGION"
echo "🛡️ Verificando que GuardDuty esté habilitado en $REGION..."
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" || "$DETECTOR_ID" == "null" ]]; then
    echo "❌ Error: GuardDuty no está habilitado en $REGION"
    echo "💡 Primero ejecutar: ./enable-guardduty-all-regions.sh $PROFILE"
    exit 1
fi

echo "✅ GuardDuty habilitado (Detector ID: $DETECTOR_ID)"
echo ""

# 1. Crear SNS Topic para alertas
echo "📧 Configurando SNS Topic para alertas..."
TOPIC_ARN=$(aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$TOPIC_ARN" ]; then
    echo "✅ SNS Topic configurado: $TOPIC_ARN"
else
    echo "❌ Error creando SNS Topic"
    exit 1
fi

# 2. Configurar atributos del Topic (políticas de entrega)
echo "⚙️ Configurando atributos del SNS Topic..."
aws sns set-topic-attributes \
    --topic-arn "$TOPIC_ARN" \
    --attribute-name DisplayName \
    --attribute-value "GuardDuty Security Alerts" \
    --region "$REGION" \
    --profile "$PROFILE"

# Política del Topic para permitir EventBridge
TOPIC_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Id": "GuardDutyAlertsPolicy",
  "Statement": [
    {
      "Sid": "AllowEventBridgePublish",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "$TOPIC_ARN",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "$ACCOUNT_ID"
        }
      }
    },
    {
      "Sid": "AllowAccountOwnerAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": [
        "SNS:GetTopicAttributes",
        "SNS:SetTopicAttributes",
        "SNS:AddPermission",
        "SNS:RemovePermission",
        "SNS:DeleteTopic",
        "SNS:Subscribe",
        "SNS:ListSubscriptionsByTopic",
        "SNS:Publish"
      ],
      "Resource": "$TOPIC_ARN"
    }
  ]
}
EOF
)

aws sns set-topic-attributes \
    --topic-arn "$TOPIC_ARN" \
    --attribute-name Policy \
    --attribute-value "$TOPIC_POLICY" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✅ Política del SNS Topic configurada"

# 3. Suscribir email si se proporcionó
if [ -n "$EMAIL_ENDPOINT" ]; then
    echo "📨 Suscribiendo email: $EMAIL_ENDPOINT"
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "$TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$EMAIL_ENDPOINT" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'SubscriptionArn' \
        --output text)
    
    if [ $? -eq 0 ]; then
        echo "✅ Suscripción email configurada"
        echo "📧 IMPORTANTE: Revisar el email y confirmar la suscripción"
    else
        echo "⚠️ Error configurando suscripción email"
    fi
fi

# 4. Crear reglas de EventBridge para diferentes severidades
echo ""
echo "🔔 Configurando reglas de EventBridge..."

# Regla para hallazgos críticos y altos (7.0+)
RULE_NAME_HIGH="GuardDuty-HighSeverity-Alerts"
echo "📋 Creando regla para severidad alta/crítica: $RULE_NAME_HIGH"

HIGH_SEVERITY_PATTERN=$(cat <<EOF
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [
      {"numeric": [">=", 7.0]}
    ]
  }
}
EOF
)

aws events put-rule \
    --name "$RULE_NAME_HIGH" \
    --description "GuardDuty High/Critical Severity Findings" \
    --event-pattern "$HIGH_SEVERITY_PATTERN" \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

# Conectar regla de alta severidad al SNS Topic
aws events put-targets \
    --rule "$RULE_NAME_HIGH" \
    --targets "Id"="1","Arn"="$TOPIC_ARN","InputTransformer"="{
        \"InputPathsMap\": {
            \"severity\": \"$.detail.severity\",
            \"type\": \"$.detail.type\",
            \"title\": \"$.detail.title\",
            \"description\": \"$.detail.description\",
            \"accountId\": \"$.detail.accountId\",
            \"region\": \"$.detail.region\",
            \"service\": \"$.detail.service.serviceName\",
            \"resourceType\": \"$.detail.resource.resourceType\",
            \"time\": \"$.time\"
        },
        \"InputTemplate\": \"🚨 GUARDDUTY ALERT - HIGH/CRITICAL SEVERITY\\n\\n📊 Severity: <severity>\\n🎯 Type: <type>\\n📋 Title: <title>\\n📝 Description: <description>\\n\\n🔍 Details:\\n• Account: <accountId>\\n• Region: <region>\\n• Service: <service>\\n• Resource Type: <resourceType>\\n• Time: <time>\\n\\n🌐 Console: https://<region>.console.aws.amazon.com/guardduty/home?region=<region>\\n\\n⚠️ IMMEDIATE ACTION REQUIRED\"
    }" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✅ Regla de alta severidad configurada"

# Regla para hallazgos medios (4.0-6.9) - Solo resumen diario
RULE_NAME_MEDIUM="GuardDuty-MediumSeverity-Summary"
echo "📋 Creando regla para severidad media: $RULE_NAME_MEDIUM"

MEDIUM_SEVERITY_PATTERN=$(cat <<EOF
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [
      {"numeric": [">=", 4.0]},
      {"numeric": ["<", 7.0]}
    ]
  }
}
EOF
)

aws events put-rule \
    --name "$RULE_NAME_MEDIUM" \
    --description "GuardDuty Medium Severity Findings" \
    --event-pattern "$MEDIUM_SEVERITY_PATTERN" \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

# Para severidad media, usar un formato más simple
aws events put-targets \
    --rule "$RULE_NAME_MEDIUM" \
    --targets "Id"="1","Arn"="$TOPIC_ARN","InputTransformer"="{
        \"InputPathsMap\": {
            \"severity\": \"$.detail.severity\",
            \"type\": \"$.detail.type\",
            \"title\": \"$.detail.title\",
            \"region\": \"$.detail.region\",
            \"time\": \"$.time\"
        },
        \"InputTemplate\": \"ℹ️ GuardDuty Finding - Medium Severity\\n\\n📊 Severity: <severity>\\n🎯 Type: <type>\\n📋 Title: <title>\\n🌍 Region: <region>\\n⏰ Time: <time>\\n\\nReview when convenient.\"
    }" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✅ Regla de severidad media configurada"

# 5. Crear regla adicional para tipos específicos de amenaza (opcional)
RULE_NAME_CRYPTO="GuardDuty-Cryptocurrency-Mining"
echo "📋 Creando regla para detección de cryptomining: $RULE_NAME_CRYPTO"

CRYPTO_PATTERN=$(cat <<EOF
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "type": [
      {"wildcard": "*CryptoCurrency*"},
      {"wildcard": "*Trojan*"},
      {"wildcard": "*Backdoor*"}
    ]
  }
}
EOF
)

aws events put-rule \
    --name "$RULE_NAME_CRYPTO" \
    --description "GuardDuty Cryptocurrency Mining and Malware Detection" \
    --event-pattern "$CRYPTO_PATTERN" \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"

aws events put-targets \
    --rule "$RULE_NAME_CRYPTO" \
    --targets "Id"="1","Arn"="$TOPIC_ARN","InputTransformer"="{
        \"InputPathsMap\": {
            \"severity\": \"$.detail.severity\",
            \"type\": \"$.detail.type\",
            \"title\": \"$.detail.title\",
            \"accountId\": \"$.detail.accountId\",
            \"region\": \"$.detail.region\",
            \"time\": \"$.time\"
        },
        \"InputTemplate\": \"🚨🔴 CRITICAL THREAT DETECTED 🔴🚨\\n\\n💰 CRYPTOCURRENCY MINING / MALWARE\\n\\n📊 Severity: <severity>\\n🎯 Type: <type>\\n📋 Title: <title>\\n\\n🔍 Account: <accountId>\\n🌍 Region: <region>\\n⏰ Time: <time>\\n\\n⚠️⚠️ IMMEDIATE ISOLATION AND INVESTIGATION REQUIRED ⚠️⚠️\"
    }" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✅ Regla de cryptomining/malware configurada"

echo ""
echo "=============================================================="
echo "✅ ALERTAS EN TIEMPO REAL CONFIGURADAS - GUARDDUTY"
echo "=============================================================="
echo ""
echo "📊 Resumen de configuración:"
echo "  - Región: $REGION"
echo "  - Account ID: $ACCOUNT_ID"
echo "  - SNS Topic: $TOPIC_ARN"
echo "  - Detector GuardDuty: $DETECTOR_ID"
echo ""
echo "🔔 Reglas de EventBridge creadas:"
echo "  ✅ $RULE_NAME_HIGH (Severidad ≥7.0)"
echo "  ✅ $RULE_NAME_MEDIUM (Severidad 4.0-6.9)"
echo "  ✅ $RULE_NAME_CRYPTO (Cryptomining/Malware)"
echo ""

if [ -n "$EMAIL_ENDPOINT" ]; then
    echo "📧 Suscripción de email:"
    echo "  - Email: $EMAIL_ENDPOINT"
    echo "  - Estado: Pendiente confirmación"
    echo "  📨 IMPORTANTE: Revisar email y confirmar suscripción"
    echo ""
fi

echo "🔍 Verificación manual:"
echo "  aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN --profile $PROFILE"
echo "  aws events list-rules --name-prefix GuardDuty --profile $PROFILE"
echo ""
echo "🌐 Consola SNS:"
echo "  https://$REGION.console.aws.amazon.com/sns/v3/home?region=$REGION#/topic/$TOPIC_ARN"
echo ""
echo "📋 Para agregar más suscripciones:"
echo "  aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@domain.com --profile $PROFILE"
echo "  aws sns subscribe --topic-arn $TOPIC_ARN --protocol sms --notification-endpoint +1234567890 --profile $PROFILE"
echo ""
echo "💡 Las alertas se activarán cuando GuardDuty detecte nuevas amenazas"
echo ""

