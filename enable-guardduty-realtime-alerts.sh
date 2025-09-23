#!/usr/bin/env bash
set -euo pipefail

PROFILE="xxxxxxxx"
DEFAULT_REGION="us-east-1"
SNS_TOPIC_NAME="guardduty-alerts"   # Nombre del topic SNS que se creará en cada región

echo "=== Configurando alertas en tiempo real de GuardDuty ==="
echo "Perfil: $PROFILE | Región inicial: $DEFAULT_REGION"

# Obtener todas las regiones habilitadas
REGIONS=$(aws ec2 describe-regions \
    --region "$DEFAULT_REGION" \
    --profile "$PROFILE" \
    --query "Regions[].RegionName" \
    --output text)

for region in $REGIONS; do
    echo
    echo "-> Región: $region"

    # 1. Crear (o reutilizar) un SNS Topic
    TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --region "$region" \
        --profile "$PROFILE" \
        --query 'TopicArn' \
        --output text)
    echo "   SNS Topic: $TOPIC_ARN"

    # 2. Crear regla de EventBridge para disparar en cada hallazgo de GuardDuty
    RULE_NAME="GuardDutyRealTimeFindings"
    aws events put-rule \
        --name "$RULE_NAME" \
        --event-pattern '{
            "source": ["aws.guardduty"],
            "detail-type": ["GuardDuty Finding"]
        }' \
        --state ENABLED \
        --region "$region" \
        --profile "$PROFILE"

    # 3. Conectar la regla al SNS Topic como destino
    aws events put-targets \
        --rule "$RULE_NAME" \
        --targets "Id"="1","Arn"="$TOPIC_ARN" \
        --region "$region" \
        --profile "$PROFILE"

    # 4. Dar permisos a EventBridge para publicar en el Topic
    aws sns add-permission \
        --topic-arn "$TOPIC_ARN" \
        --label "AllowEventBridgePublish" \
        --aws-account-id "$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)" \
        --action-name "Publish" \
        --region "$region" \
        --profile "$PROFILE" \
        || true  # Ignorar error si ya existe la política

    echo "   ✔ Alertas en tiempo real activadas (SNS + EventBridge)."
done

echo
echo "=== Listo. Recuerda suscribirte al Topic SNS en cada región (email/SMS/endpoint) ==="

