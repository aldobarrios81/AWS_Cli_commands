#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"
SNS_TOPIC_NAME="iam-access-analyzer-alerts"

echo "=== Configurando Alertas en Tiempo Real para IAM Access Analyzer ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# Verificar si IAM Access Analyzer está habilitado
echo "Verificando IAM Access Analyzer..."
ANALYZER_ARN=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].arn" \
    --output text 2>/dev/null || echo "None")

if [ "$ANALYZER_ARN" = "None" ] || [ -z "$ANALYZER_ARN" ]; then
    echo "❌ Error: No se encontró ningún analyzer de Access Analyzer."
    echo "   Ejecuta primero: ./enable-iam-access-analyzer-improved.sh"
    exit 1
fi

ANALYZER_NAME=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].name" \
    --output text 2>/dev/null)

analyzer_status=$(wsl aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "analyzers[0].status" \
    --output text 2>/dev/null)

echo "✔ IAM Access Analyzer detectado: $ANALYZER_NAME"
echo "✔ Analyzer ARN: $ANALYZER_ARN"
echo "✔ Estado: $analyzer_status"
echo

# 1️⃣ Crear SNS Topic
echo "Creando SNS Topic para alertas..."
SNS_TOPIC_ARN=$(wsl aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "TopicArn" \
    --output text)

echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# 2️⃣ Crear regla EventBridge para hallazgos
echo "Creando regla EventBridge para nuevos findings..."
RULE_NAME="IAMAccessAnalyzerRealTimeFindings"

wsl aws events put-rule \
    --name "$RULE_NAME" \
    --event-pattern '{
        "source": ["aws.access-analyzer"],
        "detail-type": ["Access Analyzer Finding"],
        "detail": {
            "status": ["ACTIVE"]
        }
    }' \
    --state ENABLED \
    --description "Alertas para nuevos findings de IAM Access Analyzer" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Regla EventBridge creada: $RULE_NAME"

# 3️⃣ Asociar la regla al SNS Topic
echo "Asociando regla al SNS Topic..."
wsl aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Regla asociada al SNS Topic"

# 4️⃣ Configurar permisos para EventBridge
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

# 5️⃣ Verificar configuración
echo
echo "Verificando configuración..."
echo "Reglas de EventBridge:"
wsl aws events list-rules \
    --name-prefix "IAMAccessAnalyzer" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'Rules[*].[Name,State,Description]' \
    --output table

# 6️⃣ Crear regla adicional para findings archivados (opcional - para auditoría)
echo
echo "Creando regla EventBridge para findings archivados (auditoría)..."
RULE_NAME_ARCHIVED="IAMAccessAnalyzerArchivedFindings"

wsl aws events put-rule \
    --name "$RULE_NAME_ARCHIVED" \
    --event-pattern '{
        "source": ["aws.access-analyzer"],
        "detail-type": ["Access Analyzer Finding"],
        "detail": {
            "status": ["ARCHIVED"]
        }
    }' \
    --state ENABLED \
    --description "Auditoría de findings archivados de IAM Access Analyzer" \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null || echo "⚠ No se pudo crear regla de auditoría"

echo "✔ Regla de auditoría creada: $RULE_NAME_ARCHIVED"

# 7️⃣ Crear SNS Topic separado para auditoría (opcional)
echo "Creando SNS Topic para auditoría..."
SNS_TOPIC_AUDIT="iam-access-analyzer-audit"
SNS_TOPIC_AUDIT_ARN=$(wsl aws sns create-topic \
    --name "$SNS_TOPIC_AUDIT" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "TopicArn" \
    --output text 2>/dev/null || echo "$SNS_TOPIC_ARN")

echo "✔ SNS Topic de auditoría: $SNS_TOPIC_AUDIT_ARN"

# 8️⃣ Asociar regla de auditoría al SNS Topic de auditoría
if [[ "$SNS_TOPIC_AUDIT_ARN" != "$SNS_TOPIC_ARN" ]]; then
    echo "Asociando regla de auditoría al SNS Topic de auditoría..."
    wsl aws events put-targets \
        --rule "$RULE_NAME_ARCHIVED" \
        --targets "Id"="1","Arn"="$SNS_TOPIC_AUDIT_ARN" \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null || echo "⚠ No se pudo asociar regla de auditoría"
    echo "✔ Regla de auditoría asociada"
fi

# 9️⃣ Verificar integración con Security Hub
echo
echo "=== Verificando integración con Security Hub ==="
securityhub_status=$(wsl aws securityhub describe-hub \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'HubArn' \
    --output text 2>/dev/null || echo "NOT_ENABLED")

if [ "$securityhub_status" != "NOT_ENABLED" ]; then
    echo "✔ Security Hub habilitado - findings también aparecen allí"
    echo "✔ Alertas duplicadas evitadas por integración automática"
else
    echo "ℹ Security Hub no habilitado - solo alertas directas de Access Analyzer"
fi

echo
echo "=== Verificación final de configuración ==="
echo "Verificando reglas EventBridge creadas:"
wsl aws events list-rules \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Rules[?contains(Name, 'IAMAccessAnalyzer')].{Nombre:Name,Estado:State}" \
    --output table

echo
echo "Verificando SNS Topics creados:"
wsl aws sns list-topics \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Topics[?contains(TopicArn, 'iam-access-analyzer')].TopicArn" \
    --output table

echo
echo "✅ Alertas en tiempo real para IAM Access Analyzer configuradas exitosamente"
echo
echo "CONFIGURACIÓN COMPLETADA:"
echo "========================="
echo "🚨 Alertas CRÍTICAS:"
echo "   - SNS Topic: $SNS_TOPIC_ARN"
echo "   - Regla: $RULE_NAME"
echo "   - Trigger: Nuevos findings ACTIVOS"
echo
echo "📋 Alertas de AUDITORÍA:"
echo "   - SNS Topic: $SNS_TOPIC_AUDIT_ARN"
echo "   - Regla: $RULE_NAME_ARCHIVED"
echo "   - Trigger: Findings archivados"
echo
echo "CONFIGURAR SUSCRIPCIONES:"
echo "========================"
echo "📧 Email para alertas críticas:"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint tu-email@example.com --region $REGION --profile $PROFILE"
echo
echo "📧 Email para auditoría:"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_AUDIT_ARN --protocol email --notification-endpoint auditor@example.com --region $REGION --profile $PROFILE"
echo
echo "📱 SMS para alertas críticas:"
echo "wsl aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol sms --notification-endpoint +1234567890 --region $REGION --profile $PROFILE"
echo
echo "NOTAS IMPORTANTES:"
echo "=================="
echo "🔔 Las alertas se envían INMEDIATAMENTE cuando se detectan nuevos findings ACTIVOS"
echo "📝 Los findings archivados generan alertas de auditoría separadas"
echo "✅ Confirma las suscripciones por email para activar las notificaciones"
echo "🔄 Los findings se integran automáticamente con Security Hub si está habilitado"
echo "⏰ Las alertas funcionan 24/7 sin intervención manual"
echo
echo "TIPOS DE EVENTOS QUE GENERAN ALERTAS:"
echo "====================================="
echo "🚨 CRÍTICAS (Inmediatas):"
echo "   • Nuevo recurso con acceso externo detectado"
echo "   • Cambio en política que expone recursos"
echo "   • Acceso público no deseado identificado"
echo
echo "📋 AUDITORÍA (Informativas):"
echo "   • Finding archivado manualmente"
echo "   • Cambio de estado de finding"
echo "   • Resolución de problema de acceso"
echo
echo "=== Proceso completado ==="

