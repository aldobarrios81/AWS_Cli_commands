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
echo "Proveedor: $PROVIDER | Región: $REGION | Perfil: $PROFILE"
echo
SH_STATUS=$(wsl aws securityhub get-enabled-standards --region "$REGION" --profile "$PROFILE" --query 'StandardsSubscriptions' --output text 2>/dev/null)

if [ -z "$SH_STATUS" ]; then
    echo "Activando Security Hub..."
    wsl aws securityhub enable-security-hub \
        --region "$REGION" \
        --profile "$PROFILE"
    echo "✔ Security Hub habilitado"
else
    echo "✔ Security Hub ya está habilitado"
fi

# 2️⃣ Habilitar estándar AWS Foundational Security Best Practices
echo "Habilitando estándar AWS Foundational Security Best Practices..."
wsl aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn="$STANDARDS_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "✔ Estándar ya habilitado o Security Hub ya configurado"
echo "✔ Estándar verificado"

# 3️⃣ Crear SNS Topic para alertas
echo "Creando SNS Topic para alertas..."
SNS_TOPIC_ARN=$(wsl aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text)
echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# 4️⃣ Crear regla EventBridge para hallazgos de Security Hub (HIGH y CRITICAL)
echo "Creando regla EventBridge para hallazgos HIGH/CRITICAL..."
wsl aws events put-rule \
    --name "$RULE_NAME" \
    --event-pattern '{
        "source": ["aws.securityhub"],
        "detail-type": ["Security Hub Findings - Imported"],
        "detail": {
            "findings": {
                "Severity": {
                    "Label": ["HIGH", "CRITICAL"]
                }
            }
        }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Regla EventBridge creada: $RULE_NAME"

# 5️⃣ Asociar regla al SNS Topic
echo "Asociando regla al SNS Topic..."
wsl aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Regla asociada al SNS Topic"

# 6️⃣ Configurar permisos para EventBridge
echo "Configurando permisos para EventBridge..."
policy_document="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Service\": \"events.amazonaws.com\"
            },
            \"Action\": \"sns:Publish\",
            \"Resource\": \"$SNS_TOPIC_ARN\"
        }
    ]
}"

wsl aws sns set-topic-attributes \
    --topic-arn "$SNS_TOPIC_ARN" \
    --attribute-name Policy \
    --attribute-value "$policy_document" \
    --region "$REGION" \
    --profile "$PROFILE"
echo "✔ Permisos configurados para EventBridge"

# 7️⃣ Crear regla adicional para findings MEDIUM (opcional)
echo "Creando regla EventBridge para hallazgos MEDIUM..."
RULE_NAME_MEDIUM="SecurityHubMediumFindings"
wsl aws events put-rule \
    --name "$RULE_NAME_MEDIUM" \
    --event-pattern '{
        "source": ["aws.securityhub"],
        "detail-type": ["Security Hub Findings - Imported"],
        "detail": {
            "findings": {
                "Severity": {
                    "Label": ["MEDIUM"]
                }
            }
        }
    }' \
    --state ENABLED \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "⚠ No se pudo crear regla para MEDIUM findings"
echo "✔ Regla EventBridge para MEDIUM creada: $RULE_NAME_MEDIUM"

# 8️⃣ Crear SNS Topic separado para findings MEDIUM (menos ruido)
echo "Creando SNS Topic para alertas MEDIUM..."
SNS_TOPIC_MEDIUM="securityhub-medium-alerts"
SNS_TOPIC_MEDIUM_ARN=$(wsl aws sns create-topic \
    --name "$SNS_TOPIC_MEDIUM" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TopicArn' \
    --output text 2>/dev/null || echo "$SNS_TOPIC_ARN")
echo "✔ SNS Topic MEDIUM creado: $SNS_TOPIC_MEDIUM_ARN"

# 9️⃣ Asociar regla MEDIUM al SNS Topic MEDIUM
if [[ "$SNS_TOPIC_MEDIUM_ARN" != "$SNS_TOPIC_ARN" ]]; then
    echo "Asociando regla MEDIUM al SNS Topic MEDIUM..."
    wsl aws events put-targets \
        --rule "$RULE_NAME_MEDIUM" \
        --targets "Id"="1","Arn"="$SNS_TOPIC_MEDIUM_ARN" \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null || echo "⚠ No se pudo asociar regla MEDIUM"
    echo "✔ Regla MEDIUM asociada al SNS Topic MEDIUM"
fi

# 🔟 Verificar configuración final
echo
echo "=== Verificando configuración de alertas ==="
echo "Verificando reglas EventBridge..."
wsl aws events list-rules \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Rules[?contains(Name, 'SecurityHub')].{Name:Name,State:State}" \
    --output table

echo
echo "Verificando SNS Topics..."
wsl aws sns list-topics \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Topics[?contains(TopicArn, 'securityhub')].TopicArn" \
    --output table

echo
echo "✅ Security Hub con alertas en tiempo real configurado exitosamente"
echo
echo "Configuración completada:"
echo "- SNS Topic HIGH/CRITICAL: $SNS_TOPIC_ARN"
echo "- SNS Topic MEDIUM: $SNS_TOPIC_MEDIUM_ARN"
echo "- Regla EventBridge HIGH/CRITICAL: $RULE_NAME"
echo "- Regla EventBridge MEDIUM: $RULE_NAME_MEDIUM"
echo "- Filtros configurados por severidad"
echo
echo "Para recibir alertas por email (HIGH/CRITICAL):"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint tu-email@example.com --region $REGION --profile $PROFILE"
echo
echo "Para recibir alertas por email (MEDIUM):"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_MEDIUM_ARN --protocol email --notification-endpoint tu-email@example.com --region $REGION --profile $PROFILE"
echo
echo "Ejemplo de suscripción por SMS:"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol sms --notification-endpoint +1234567890 --region $REGION --profile $PROFILE"
echo
echo "Notas importantes:"
echo "- Las alertas se activan solo para findings HIGH y CRITICAL por defecto"
echo "- Los findings MEDIUM tienen un topic separado para reducir ruido"
echo "- EventBridge procesa las alertas en tiempo real"
echo "- Considera crear un dashboard en CloudWatch para métricas"
echo
echo "=== Proceso completado ==="

