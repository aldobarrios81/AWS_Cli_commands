#!/bin/bash
# Habilita Security Hub y alertas en tiempo real vía SNS
# Perfil fijo: xxxxxx | Región fija: us-east-1

PROFILE="xxxxxx"
REGION="us-east-1"
SNS_TOPIC_NAME="securityhub-alerts"
RULE_NAME="SecurityHubRealTimeFindings"
STANDARDS_ARN="arn:aws:securityhub:::ruleset/aws-foundational-security-best-practices/v/1.0.0"

echo "=== Habilitando Security Hub en $REGION ==="

# 1️⃣ Verificar si Security Hub ya está habilitado
SH_STATUS=$(aws securityhub get-enabled-standards --region "$REGION" --profile "$PROFILE" --query 'StandardsSubscriptions' --output text 2>/dev/null)

if [ -z "$SH_STATUS" ]; then
    echo "Activando Security Hub..."
    aws securityhub enable-security-hub \
        --region "$REGION" \
        --profile "$PROFILE"
    echo "✔ Security Hub habilitado"
else
    echo "✔ Security Hub ya está habilitado"
fi

# 2️⃣ Habilitar estándar AWS Foundational Security Best Practices
echo "Habilitando estándar AWS Foundational Security Best Practices..."
aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn="$STANDARDS_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Estándar habilitado"

# 3️⃣ Crear SNS Topic para alertas
echo "Creando SNS Topic para alertas..."
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text)
echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# 4️⃣ Crear regla EventBridge para hallazgos de Security Hub
echo "Creando regla EventBridge para hallazgos..."
aws events put-rule \
    --name "$RULE_NAME" \
    --event-pattern '{
        "source": ["aws.securityhub"],
        "detail-type": ["Security Hub Findings - Imported"]
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Regla EventBridge creada: $RULE_NAME"

# 5️⃣ Asociar regla al SNS Topic
echo "Asociando regla al SNS Topic..."
aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Regla asociada al SNS Topic"

echo "=== Security Hub con alertas en tiempo real configurado ✅ ==="
echo "SNS Topic ARN: $SNS_TOPIC_ARN"

