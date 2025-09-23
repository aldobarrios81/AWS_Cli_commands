#!/bin/bash
# enable-securityhub-auto-enable-all.sh
# Habilita Security Hub y auto-enable de todos los controles del estándar AWS Foundational Security Best Practices

set -e

PROFILE="xxxxxx"
REGION="us-east-1"
STANDARD_ARN="arn:aws:securityhub:::ruleset/aws-foundational-security-best-practices/v/1.0.0"

echo "=== Habilitando Security Hub en $REGION ==="
aws securityhub enable-security-hub \
    --profile $PROFILE \
    --region $REGION >/dev/null 2>&1 || echo "✔ Security Hub ya habilitado"

echo "=== Habilitando estándar AWS Foundational Security Best Practices ==="
SUBSCRIPTION_ARN=$(aws securityhub batch-enable-standards \
    --standards-subscription-arns $STANDARD_ARN \
    --profile $PROFILE \
    --region $REGION \
    --query 'StandardsSubscriptions[0].StandardsSubscriptionArn' \
    --output text)

echo "✔ Estándar habilitado: $SUBSCRIPTION_ARN"

echo "=== Listando controles del estándar ==="
CONTROL_ARNS=$(aws securityhub describe-standards-controls \
    --standards-subscription-arn $SUBSCRIPTION_ARN \
    --profile $PROFILE \
    --region $REGION \
    --query 'Controls[*].StandardsControlArn' \
    --output text)

echo "=== Activando auto-enable en todos los controles ==="
for CONTROL in $CONTROL_ARNS; do
    echo "-> Habilitando auto-enable para: $CONTROL"
    aws securityhub update-standards-control \
        --standards-control-arn $CONTROL \
        --enable-automation \
        --profile $PROFILE \
        --region $REGION
done

echo "✅ Todos los controles de Security Hub están configurados con auto-enable"

