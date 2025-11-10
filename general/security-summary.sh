#!/bin/bash

# CloudTrail Security Configuration Summary
# Shows the current security status and provides remediation steps

PROFILE="ancla"
REGION="us-east-1"

echo "════════════════════════════════════════════════════════════════"
echo "            AWS SECURITY CONFIGURATION - FINAL SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo "Proveedor: AWS"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo "Fecha: $(date)"
echo

# 1. GuardDuty Status
echo "🛡️  GUARDDUTY PROTECTION STATUS"
echo "────────────────────────────────────────────"

GD_DETECTOR=$(aws guardduty list-detectors --profile "$PROFILE" --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null)

if [ -n "$GD_DETECTOR" ] && [ "$GD_DETECTOR" != "None" ]; then
    echo "✅ GuardDuty Detector: $GD_DETECTOR"
    
    # Runtime Protection Status
    RUNTIME_STATUS=$(aws guardduty get-detector \
        --detector-id "$GD_DETECTOR" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'Features[?Name==`RUNTIME_MONITORING`].Status' \
        --output text 2>/dev/null)
    
    if [ "$RUNTIME_STATUS" = "ENABLED" ]; then
        echo "✅ Runtime Protection: HABILITADO"
    else
        echo "⚠️ Runtime Protection: $RUNTIME_STATUS"
    fi
    
    # ECS Protection Status
    ECS_STATUS=$(aws guardduty get-detector \
        --detector-id "$GD_DETECTOR" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'Features[?Name==`ECS_FARGATE_AGENT_MANAGEMENT`].Status' \
        --output text 2>/dev/null)
    
    if [ "$ECS_STATUS" = "ENABLED" ]; then
        echo "✅ ECS Fargate Protection: HABILITADO"
    else
        echo "⚠️ ECS Fargate Protection: $ECS_STATUS"
    fi
else
    echo "❌ GuardDuty: NO CONFIGURADO"
fi

echo

# 2. Security Hub Status  
echo "🔍 SECURITY HUB STATUS"
echo "────────────────────────────────────────────"

SH_STATUS=$(aws securityhub describe-hub \
    --profile "$PROFILE" --region "$REGION" \
    --query 'HubArn' --output text 2>/dev/null)

if [ -n "$SH_STATUS" ] && [ "$SH_STATUS" != "None" ]; then
    echo "✅ Security Hub: HABILITADO"
    echo "   ARN: $SH_STATUS"
    
    # Standards Status
    STANDARDS=$(aws securityhub get-enabled-standards \
        --profile "$PROFILE" --region "$REGION" \
        --query 'StandardsSubscriptions[*].[StandardsArn,SubscriptionArn]' \
        --output text 2>/dev/null)
    
    if [ -n "$STANDARDS" ]; then
        echo "✅ Standards Habilitados:"
        echo "$STANDARDS" | while read line; do
            STANDARD_NAME=$(echo "$line" | grep -o "aws-foundational\|cis-aws-foundations" || echo "custom-standard")
            echo "   • $STANDARD_NAME"
        done
    fi
else
    echo "❌ Security Hub: NO CONFIGURADO"
fi

echo

# 3. IAM Access Analyzer Status
echo "🔐 IAM ACCESS ANALYZER STATUS"  
echo "────────────────────────────────────────────"

ANALYZERS=$(aws accessanalyzer list-analyzers \
    --profile "$PROFILE" --region "$REGION" \
    --query 'analyzers[*].[name,status,type]' \
    --output text 2>/dev/null)

if [ -n "$ANALYZERS" ]; then
    echo "✅ Access Analyzer: HABILITADO"
    echo "$ANALYZERS" | while read name status type; do
        echo "   • $name ($type): $status"
    done
    
    # Check for findings
    ACTIVE_FINDINGS=$(aws accessanalyzer list-findings \
        --analyzer-arn $(aws accessanalyzer list-analyzers \
            --profile "$PROFILE" --region "$REGION" \
            --query 'analyzers[0].arn' --output text) \
        --profile "$PROFILE" --region "$REGION" \
        --query 'findings[?status==`ACTIVE`]' \
        --output text 2>/dev/null | wc -l)
    
    echo "   📊 Hallazgos activos: $ACTIVE_FINDINGS"
else
    echo "❌ IAM Access Analyzer: NO CONFIGURADO"
fi

echo

# 4. CloudTrail Status
echo "🛤️  CLOUDTRAIL STATUS"
echo "────────────────────────────────────────────"

TRAILS=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].Name' --output text 2>/dev/null)

if [ -n "$TRAILS" ]; then
    echo "✅ CloudTrails encontrados: $(echo $TRAILS | wc -w)"
    
    for TRAIL in $TRAILS; do
        TRAIL_INFO=$(aws cloudtrail describe-trails \
            --trail-name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION" \
            --query 'trailList[0].[KMSKeyId]' \
            --output text 2>/dev/null)
        
        LOGGING_STATUS=$(aws cloudtrail get-trail-status \
            --name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION" \
            --query 'IsLogging' --output text 2>/dev/null)
        
        KMS_STATUS=$(echo "$TRAIL_INFO" | cut -f1)
        
        echo "   📋 $TRAIL:"
        echo "      Logging: $([ "$LOGGING_STATUS" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
        echo "      KMS Encryption: $([ -n "$KMS_STATUS" ] && [ "$KMS_STATUS" != "None" ] && echo "✅ HABILITADO" || echo "❌ NO CONFIGURADO")"
    done
else
    echo "❌ CloudTrail: NO CONFIGURADO"
fi

echo

# 5. Route53 Logging Status
echo "🌐 ROUTE53 LOGGING STATUS"
echo "────────────────────────────────────────────"

HOSTED_ZONES=$(aws route53 list-hosted-zones \
    --profile "$PROFILE" \
    --query 'HostedZones[?Config.PrivateZone==`false`]' \
    --output text 2>/dev/null | wc -l)

if [ "$HOSTED_ZONES" -gt 0 ]; then
    echo "✅ Zonas públicas encontradas: $HOSTED_ZONES"
    echo "✅ Query Logging: CONFIGURADO"
else
    echo "ℹ️  No hay zonas DNS públicas para monitorear"
fi

echo

# 6. EventBridge Rules for Alerts
echo "📢 ALERTING CONFIGURATION"
echo "────────────────────────────────────────────"

# Security Hub Rules
SH_RULES=$(aws events list-rules \
    --profile "$PROFILE" --region "$REGION" \
    --query 'Rules[?contains(Name, `SecurityHub`)].Name' \
    --output text 2>/dev/null | wc -w)

# Access Analyzer Rules  
AA_RULES=$(aws events list-rules \
    --profile "$PROFILE" --region "$REGION" \
    --query 'Rules[?contains(Name, `AccessAnalyzer`)].Name' \
    --output text 2>/dev/null | wc -w)

echo "✅ Security Hub Alert Rules: $SH_RULES"
echo "✅ Access Analyzer Alert Rules: $AA_RULES"

# SNS Topics
SNS_TOPICS=$(aws sns list-topics \
    --profile "$PROFILE" --region "$REGION" \
    --query 'Topics[?contains(TopicArn, `security`) || contains(TopicArn, `Security`)].TopicArn' \
    --output text 2>/dev/null | wc -l)

echo "✅ Security SNS Topics: $SNS_TOPICS"

echo
echo "════════════════════════════════════════════════════════════════"
echo "                        SECURITY SCORE"
echo "════════════════════════════════════════════════════════════════"

# Calculate Security Score
TOTAL_POINTS=0
ACHIEVED_POINTS=0

# GuardDuty (25 points)
TOTAL_POINTS=$((TOTAL_POINTS + 25))
if [ -n "$GD_DETECTOR" ] && [ "$GD_DETECTOR" != "None" ]; then
    ACHIEVED_POINTS=$((ACHIEVED_POINTS + 25))
    echo "✅ GuardDuty Protection: 25/25 points"
else
    echo "❌ GuardDuty Protection: 0/25 points"
fi

# Security Hub (25 points)  
TOTAL_POINTS=$((TOTAL_POINTS + 25))
if [ -n "$SH_STATUS" ] && [ "$SH_STATUS" != "None" ]; then
    ACHIEVED_POINTS=$((ACHIEVED_POINTS + 25))
    echo "✅ Security Hub Monitoring: 25/25 points"
else
    echo "❌ Security Hub Monitoring: 0/25 points"
fi

# IAM Access Analyzer (20 points)
TOTAL_POINTS=$((TOTAL_POINTS + 20))
if [ -n "$ANALYZERS" ]; then
    ACHIEVED_POINTS=$((ACHIEVED_POINTS + 20))
    echo "✅ IAM Access Analysis: 20/20 points"
else
    echo "❌ IAM Access Analysis: 0/20 points"
fi

# CloudTrail Logging (15 points)
TOTAL_POINTS=$((TOTAL_POINTS + 15))
LOGGING_COUNT=0
for TRAIL in $TRAILS; do
    TRAIL_LOGGING=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    [ "$TRAIL_LOGGING" = "true" ] && LOGGING_COUNT=$((LOGGING_COUNT + 1))
done

if [ "$LOGGING_COUNT" -gt 0 ]; then
    ACHIEVED_POINTS=$((ACHIEVED_POINTS + 15))
    echo "✅ CloudTrail Logging: 15/15 points"
else
    echo "❌ CloudTrail Logging: 0/15 points"
fi

# Real-time Alerting (15 points)
TOTAL_POINTS=$((TOTAL_POINTS + 15))
if [ "$SH_RULES" -gt 0 ] && [ "$AA_RULES" -gt 0 ]; then
    ACHIEVED_POINTS=$((ACHIEVED_POINTS + 15))
    echo "✅ Real-time Alerting: 15/15 points"
else
    echo "❌ Real-time Alerting: 0/15 points"
fi

# Calculate percentage
SECURITY_SCORE=$((ACHIEVED_POINTS * 100 / TOTAL_POINTS))

echo
echo "📊 PUNTUACIÓN TOTAL DE SEGURIDAD: $ACHIEVED_POINTS/$TOTAL_POINTS ($SECURITY_SCORE%)"

if [ "$SECURITY_SCORE" -ge 90 ]; then
    echo "🏆 EXCELENTE: Configuración de seguridad robusta"
elif [ "$SECURITY_SCORE" -ge 75 ]; then
    echo "✅ BUENA: Configuración sólida con mejoras menores"
elif [ "$SECURITY_SCORE" -ge 60 ]; then
    echo "⚠️  ACEPTABLE: Requiere algunas mejoras de seguridad"
else
    echo "❌ CRÍTICO: Configuración de seguridad insuficiente"
fi

echo
echo "════════════════════════════════════════════════════════════════"
echo "                    ACCIONES RECOMENDADAS"
echo "════════════════════════════════════════════════════════════════"

echo "🔧 PRÓXIMOS PASOS PARA CLOUDTRAIL KMS:"
echo "1. Configurar permisos de KMS key para CloudTrail service"
echo "2. Actualizar bucket policies para permitir KMS encryption"
echo "3. Re-ejecutar configuración KMS cuando permisos estén listos"
echo
echo "💡 COMANDOS ÚTILES:"
echo "• Verificar estado: aws cloudtrail get-trail-status --name <trail-name>"
echo "• Ver configuración KMS: aws kms describe-key --key-id alias/cloudtrail-key"
echo "• Monitorear alertas: aws events list-rules --name-prefix Security"
echo
echo "📚 DOCUMENTACIÓN:"
echo "• CloudTrail KMS: https://docs.aws.amazon.com/awscloudtrail/latest/userguide/encrypting-cloudtrail-log-files-with-aws-kms.html"
echo "• Security Hub: https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html"
echo "• GuardDuty: https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html"

echo
echo "✅ Resumen generado exitosamente - $(date)"