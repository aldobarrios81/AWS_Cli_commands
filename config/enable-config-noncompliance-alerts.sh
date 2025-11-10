#!/bin/bash
# enable-config-noncompliance-alerts.sh
# Configura alertas en tiempo real para AWS Config Non-Compliance

PROFILE="xxxxxxx"
REGION="us-east-1"
SNS_TOPIC_NAME="awsconfig-noncompliance-alerts"

echo "=== Configurando alertas en tiempo real de AWS Config Non-Compliance ==="
echo "Perfil: $PROFILE | Región: $REGION"

# Crear SNS Topic
SNS_TOPIC_ARN=$(aws sns create-topic --name $SNS_TOPIC_NAME --profile $PROFILE --region $REGION --output text)
echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# Crear EventBridge Rule
RULE_NAME="ConfigNonComplianceRealTime"
RULE_ARN=$(aws events put-rule \
    --name $RULE_NAME \
    --event-pattern '{
      "source": ["aws.config"],
      "detail-type": ["Config Rules Compliance Change"],
      "detail": {"newEvaluationResult":{"complianceType":["NON_COMPLIANT"]}}
    }' \
    --state ENABLED \
    --profile $PROFILE \
    --region $REGION \
    --output text)
echo "✔ Regla EventBridge creada: $RULE_NAME ($RULE_ARN)"

# Asociar regla con SNS Topic
aws events put-targets \
    --rule $RULE_NAME \
    --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
    --profile $PROFILE \
    --region $REGION
echo "✔ Regla asociada al SNS Topic"

echo "=== Configuración completada ✅ ==="
echo "SNS Topic ARN: $SNS_TOPIC_ARN"

