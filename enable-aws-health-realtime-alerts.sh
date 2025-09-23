#!/bin/bash
# enable-aws-health-realtime-alerts.sh
# Perfil y región
PROFILE=${1:-xxxxxxx}
REGION=${2:-us-east-1}

echo "=== Configurando alertas en tiempo real para AWS Health Events ==="
echo "Perfil: $PROFILE | Región: $REGION"

# Nombre del SNS Topic
TOPIC_NAME="aws-health-alerts"

# Crear SNS Topic si no existe
TOPIC_ARN=$(aws sns create-topic --name $TOPIC_NAME --profile $PROFILE --region $REGION --query 'TopicArn' --output text)
echo "✔ SNS Topic creado o existente: $TOPIC_ARN"

# Crear EventBridge Rule para AWS Health Events
RULE_NAME="AWSHealthRealTimeEvents"
RULE_ARN=$(aws events put-rule \
    --name $RULE_NAME \
    --event-pattern '{
        "source": ["aws.health"],
        "detail-type": ["AWS Health Event"]
    }' \
    --state ENABLED \
    --profile $PROFILE \
    --region $REGION \
    --query 'RuleArn' --output text)
echo "✔ Regla EventBridge creada: $RULE_NAME ($RULE_ARN)"

# Suscribirse al SNS Topic (correo de ejemplo)
aws sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol email \
    --notification-endpoint felipe.castillo@azlogica.com \
    --profile $PROFILE \
    --region $REGION

# Asociar la regla de EventBridge al SNS Topic
aws events put-targets \
    --rule $RULE_NAME \
    --targets "Id"="1","Arn"="$TOPIC_ARN" \
    --profile $PROFILE \
    --region $REGION
echo "✔ Regla asociada al SNS Topic"

echo "✅ AWS Health Real-Time Alerts habilitadas"
echo "SNS Topic ARN: $TOPIC_ARN"

