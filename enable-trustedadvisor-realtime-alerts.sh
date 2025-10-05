#!/bin/bash
# enable-trustedadvisor-realtime-alerts.sh
# Perfil y región
PROFILE="azcenit"
REGION="us-east-1"

echo "=== Configurando alertas en tiempo real para Trusted Advisor ==="
echo "Perfil: $PROFILE | Región: $REGION"

# Nombre del SNS Topic
TOPIC_NAME="trustedadvisor-alerts"

# Crear SNS Topic si no existe
TOPIC_ARN=$(aws sns create-topic --name $TOPIC_NAME --profile $PROFILE --region $REGION --query 'TopicArn' --output text)
echo "✔ SNS Topic creado o existente: $TOPIC_ARN"

# Crear EventBridge Rule para Trusted Advisor Findings
RULE_NAME="TrustedAdvisorRealTimeFindings"
RULE_ARN=$(aws events put-rule \
    --name $RULE_NAME \
    --event-pattern '{
      "source": ["aws.trustedadvisor"],
      "detail-type": ["Trusted Advisor Check Item Refresh Notification"]
    }' \
    --state ENABLED \
    --profile $PROFILE \
    --region $REGION \
    --query 'RuleArn' --output text)
echo "✔ Regla EventBridge creada: $RULE_NAME ($RULE_ARN)"

# Dar permisos al EventBridge para publicar al SNS Topic
# Nota: Agregar suscripción de email después manualmente si es necesario
# aws sns subscribe \
#     --topic-arn $TOPIC_ARN \
#     --protocol email \
#     --notification-endpoint tu-email@ejemplo.com \
#     --profile $PROFILE \
#     --region $REGION

# Dar permisos a EventBridge para publicar al SNS Topic
aws sns add-permission \
    --topic-arn $TOPIC_ARN \
    --label "EventBridgePublishPermission" \
    --aws-account-id $(aws sts get-caller-identity --profile $PROFILE --query Account --output text) \
    --action-name Publish \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "⚠ Permisos ya configurados o error menor"

aws events put-targets \
    --rule $RULE_NAME \
    --targets "Id"="1","Arn"="$TOPIC_ARN" \
    --profile $PROFILE \
    --region $REGION
echo "✔ Regla asociada al SNS Topic"

echo "✅ Trusted Advisor Real-Time Alerts habilitadas"
echo "SNS Topic ARN: $TOPIC_ARN"

