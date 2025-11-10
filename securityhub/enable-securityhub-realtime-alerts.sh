#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
PROFILE="azcenit"
REGION="us-east-1"
SNS_TOPIC_NAME="securityhub-alerts"
RULE_NAME="SecurityHubRealTimeFindings"
STANDARDS_ARN="arn:aws:securityhub:::ruleset/aws-foundational-security-best-practices/v/1.0.0"

echo "=== Habilitando Security Hub en $REGION ==="

# 1️⃣ Verificar si Security Hub ya está habilitado
#!/usr/bin/env bash
set -euo pipefail

# enable-securityhub-realtime-alerts.sh
# Parameterized and safer version: accepts AWS profile and optional email to auto-subscribe.

if [ $# -lt 1 ]; then
    echo "Uso: $0 <aws-profile> [notification-email]"
    echo "Ejemplo: $0 metrokia security-team@example.com"
    exit 1
fi

PROFILE="$1"
NOTIFY_EMAIL="${2:-}"
REGION="us-east-1"
SNS_TOPIC_BASE="securityhub-alerts"
RULE_NAME_HIGH="SecurityHubRealTimeFindingsHighCritical"
RULE_NAME_MEDIUM="SecurityHubRealTimeFindingsMedium"
STANDARDS_ARN="arn:aws:securityhub:$REGION::standards/aws-foundational-security-best-practices/v/1.0.0"

echo "=== Configurando alertas en tiempo real de Security Hub ==="
echo "Perfil: $PROFILE | Región: $REGION"

# Validate AWS credentials
echo "🔍 Validando credenciales..."
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" --output json 2>/dev/null) || {
    echo "❌ Credenciales inválidas para perfil '$PROFILE'"
    exit 1
}
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
echo "✅ Credenciales válidas - Account: $ACCOUNT_ID | Arn: $ARN"

# Ensure Security Hub is enabled
echo "🛡️ Verificando Security Hub..."
if ! aws securityhub describe-hub --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
    echo "Security Hub no está habilitado. Habilitando..."
    aws securityhub enable-security-hub --profile "$PROFILE" --region "$REGION"
    echo "✔ Security Hub habilitado"
else
    echo "✔ Security Hub ya habilitado"
fi

# Ensure AWS Foundational standard is enabled (idempotent)
echo "📚 Habilitando estándar AWS Foundational (si no está habilitado)..."
aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn="$STANDARDS_ARN" \
    --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
echo "✔ Estándar verificado"

# Create SNS topics (unique per account to avoid collisions)
SNS_TOPIC_NAME="${SNS_TOPIC_BASE}-${ACCOUNT_ID}"
echo "🔔 Creando SNS Topic para HIGH/CRITICAL: $SNS_TOPIC_NAME"
SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --profile "$PROFILE" --region "$REGION" --query 'TopicArn' --output text)
echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# Create SNS topic for MEDIUM (separate noise channel)
SNS_TOPIC_MEDIUM_NAME="${SNS_TOPIC_BASE}-medium-${ACCOUNT_ID}"
echo "🔔 Creando SNS Topic para MEDIUM: $SNS_TOPIC_MEDIUM_NAME"
SNS_TOPIC_MEDIUM_ARN=$(aws sns create-topic --name "$SNS_TOPIC_MEDIUM_NAME" --profile "$PROFILE" --region "$REGION" --query 'TopicArn' --output text)
echo "✔ SNS Topic MEDIUM creado: $SNS_TOPIC_MEDIUM_ARN"

# Secure the topic: allow EventBridge to publish but restrict by SourceAccount
echo "🔒 Configurando política del SNS Topic (restringida a EventBridge del account)..."
read -r -d '' POLICY_DOCUMENT <<EOF || true
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgePublish",
      "Effect": "Allow",
      "Principal": {"Service": "events.amazonaws.com"},
      "Action": "sns:Publish",
      "Resource": "$SNS_TOPIC_ARN",
      "Condition": {"StringEquals": {"aws:SourceAccount": "$ACCOUNT_ID"}}
    }
  ]
}
EOF

aws sns set-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --attribute-name Policy --attribute-value "$POLICY_DOCUMENT" --profile "$PROFILE" --region "$REGION"
aws sns set-topic-attributes --topic-arn "$SNS_TOPIC_MEDIUM_ARN" --attribute-name Policy --attribute-value "$POLICY_DOCUMENT" --profile "$PROFILE" --region "$REGION"
echo "✔ Políticas aplicadas a los topics"

# Create EventBridge rule for HIGH/CRITICAL
echo "⚡ Creando regla de EventBridge para HIGH/CRITICAL..."
aws events put-rule --name "$RULE_NAME_HIGH" --event-pattern '{"source":["aws.securityhub"],"detail-type":["Security Hub Findings - Imported"],"detail":{"findings":{"Severity":{"Label":["HIGH","CRITICAL"]}}}}' --state ENABLED --profile "$PROFILE" --region "$REGION"

aws events put-targets --rule "$RULE_NAME_HIGH" --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION"

# Add permission for EventBridge to publish (already handled by topic policy) - idempotent

echo "✔ Regla HIGH/CRITICAL creada y asociada al SNS Topic"

# Create EventBridge rule for MEDIUM
echo "⚡ Creando regla de EventBridge para MEDIUM..."
aws events put-rule --name "$RULE_NAME_MEDIUM" --event-pattern '{"source":["aws.securityhub"],"detail-type":["Security Hub Findings - Imported"],"detail":{"findings":{"Severity":{"Label":["MEDIUM"]}}}}' --state ENABLED --profile "$PROFILE" --region "$REGION" || true

aws events put-targets --rule "$RULE_NAME_MEDIUM" --targets "Id"="1","Arn"="$SNS_TOPIC_MEDIUM_ARN" --profile "$PROFILE" --region "$REGION" || true

echo "✔ Regla MEDIUM creada y asociada al SNS Topic MEDIUM"

# Optionally subscribe provided email to topics
if [ -n "$NOTIFY_EMAIL" ]; then
    echo "📧 Suscribiendo $NOTIFY_EMAIL a los topics..."
    aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$NOTIFY_EMAIL" --profile "$PROFILE" --region "$REGION" >/dev/null
    aws sns subscribe --topic-arn "$SNS_TOPIC_MEDIUM_ARN" --protocol email --notification-endpoint "$NOTIFY_EMAIL" --profile "$PROFILE" --region "$REGION" >/dev/null
    echo "✔ Peticiones de suscripción enviadas a $NOTIFY_EMAIL. Revisa el correo y confirma la suscripción."
fi

# Final verification
echo ""
echo "🔎 Verificando reglas y topics..."
aws events list-rules --region "$REGION" --profile "$PROFILE" --query "Rules[?contains(Name, 'SecurityHub')].{Name:Name,State:State}" --output table || true
aws sns list-topics --region "$REGION" --profile "$PROFILE" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_BASE')].TopicArn" --output table || true

echo ""
echo "✅ Security Hub realtime alerts configurado"
echo "  - SNS Topic HIGH/CRITICAL: $SNS_TOPIC_ARN"
echo "  - SNS Topic MEDIUM: $SNS_TOPIC_MEDIUM_ARN"
echo "  - EventBridge rule HIGH/CRITICAL: $RULE_NAME_HIGH"
echo "  - EventBridge rule MEDIUM: $RULE_NAME_MEDIUM"

if [ -z "$NOTIFY_EMAIL" ]; then
    echo "Para suscribirte por email (HIGH/CRITICAL):"
    echo "  aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint you@example.com --profile $PROFILE --region $REGION"
    echo "Para suscribirte por email (MEDIUM):"
    echo "  aws sns subscribe --topic-arn $SNS_TOPIC_MEDIUM_ARN --protocol email --notification-endpoint you@example.com --profile $PROFILE --region $REGION"
fi

echo "Notas:"
echo " - Las políticas del SNS topic restringen publicaciones a EventBridge provenientes de este account."
echo " - Revisa la consola de EventBridge y SNS si necesitas permisos adicionales para cross-account."
echo " - Considera integrar con SSO/email distribution lists para producción."

echo "=== Proceso completado ==="
    --output table


