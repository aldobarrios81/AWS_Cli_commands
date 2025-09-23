#!/bin/bash
# Habilitar alertas en tiempo real para IAM Access Analyzer
# Perfil: xxxxxx
# Región: us-east-1

PROFILE="xxxxxxx"
REGION="us-east-1"
ANALYZER_NAME="default-access-analyzer"
SNS_TOPIC_NAME="iam-access-analyzer-alerts"

echo "=== Configurando alertas en tiempo real para IAM Access Analyzer ==="

# 1️⃣ Crear SNS Topic
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "TopicArn" \
    --output text)

echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# 2️⃣ Crear regla EventBridge para hallazgos
RULE_NAME="IAMAccessAnalyzerRealTimeFindings"

RULE_ARN=$(aws events put-rule \
    --name "$RULE_NAME" \
    --event-pattern "{
        \"source\": [\"aws.access-analyzer\"],
        \"detail-type\": [\"Access Analyzer Finding\"]
    }" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "RuleArn" \
    --output text)

echo "✔ Regla EventBridge creada: $RULE_NAME ($RULE_ARN)"

# 3️⃣ Asociar la regla al SNS Topic
aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Regla asociada al SNS Topic"
echo "✅ Alertas en tiempo real para IAM Access Analyzer habilitadas"
echo "SNS Topic ARN: $SNS_TOPIC_ARN"

