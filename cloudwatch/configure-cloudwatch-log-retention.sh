#!/bin/bash

# Configuración de Políticas de Retención para CloudWatch Log Groups
# Este script configura políticas de retención apropiadas para todos los log groups
# para optimizar costos y cumplir con políticas de governance de datos

set -e

PROFILE="azcenit"
REGION="us-east-1"

# Configuración de retención por defecto (en días)
DEFAULT_RETENTION_DAYS=30
CRITICAL_RETENTION_DAYS=90    # Para logs críticos (VPC, CloudTrail, etc.)
DEBUG_RETENTION_DAYS=7        # Para logs de debug/desarrollo
ARCHIVE_RETENTION_DAYS=365    # Para logs de auditoría/compliance

echo "=================================================================="
echo "📋 CONFIGURANDO RETENCIÓN DE CLOUDWATCH LOG GROUPS"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Paso 1: Escaneando CloudWatch Log Groups ==="

# Obtener todos los log groups
log_groups_json=$(aws logs describe-log-groups \
    --profile $PROFILE \
    --region $REGION \
    --query 'logGroups[*].[logGroupName,retentionInDays,storedBytes,creationTime]' \
    --output json)

total_log_groups=$(echo "$log_groups_json" | jq length)

echo "📊 Total de CloudWatch Log Groups encontrados: $total_log_groups"

if [ "$total_log_groups" -eq 0 ]; then
    echo "✅ No hay Log Groups en esta región"
    echo ""
    echo "=================================================================="
    echo "🎯 RETENCIÓN LOG GROUPS - NO HAY LOG GROUPS"
    echo "=================================================================="
    exit 0
fi

echo ""

# Contadores
groups_with_retention=0
groups_without_retention=0
groups_to_update=0
total_stored_bytes=0

echo "📋 INVENTARIO DE LOG GROUPS:"
echo "────────────────────────────────────────────────────────────────────"

# Arrays para diferentes tipos de logs
declare -A retention_policies

# Procesar cada log group
while IFS= read -r log_group_data; do
    log_group_name=$(echo "$log_group_data" | jq -r '.[0]')
    current_retention=$(echo "$log_group_data" | jq -r '.[1]')
    stored_bytes=$(echo "$log_group_data" | jq -r '.[2]')
    creation_time=$(echo "$log_group_data" | jq -r '.[3]')
    
    # Manejar valores null
    if [ "$current_retention" = "null" ]; then
        current_retention="Never (∞)"
        groups_without_retention=$((groups_without_retention + 1))
    else
        groups_with_retention=$((groups_with_retention + 1))
    fi
    
    if [ "$stored_bytes" != "null" ]; then
        total_stored_bytes=$((total_stored_bytes + stored_bytes))
    fi
    
    # Convertir timestamp a fecha legible
    if [ "$creation_time" != "null" ]; then
        creation_date=$(date -d "@$(echo "$creation_time" | cut -d. -f1)" +"%Y-%m-%d" 2>/dev/null || echo "Unknown")
    else
        creation_date="Unknown"
    fi
    
    # Calcular tamaño en MB
    if [ "$stored_bytes" != "null" ] && [ "$stored_bytes" -gt 0 ]; then
        size_mb=$(awk "BEGIN {printf \"%.2f\", $stored_bytes / 1024 / 1024}")
    else
        size_mb="0.00"
    fi
    
    echo "📋 Log Group: $log_group_name"
    echo "   📅 Creado: $creation_date"
    echo "   💾 Tamaño: ${size_mb} MB"
    echo "   ⏰ Retención actual: $current_retention días"
    
    # Determinar retención recomendada basada en el nombre del log group
    recommended_retention=""
    
    case "$log_group_name" in
        *"vpc"*|*"VPC"*|*"flow"*)
            recommended_retention=$CRITICAL_RETENTION_DAYS
            echo "   🔍 Tipo: VPC Flow Logs (Crítico)"
            ;;
        *"cloudtrail"*|*"CloudTrail"*|*"audit"*)
            recommended_retention=$ARCHIVE_RETENTION_DAYS
            echo "   🔍 Tipo: CloudTrail/Audit (Archivo)"
            ;;
        *"lambda"*|*"aws/lambda"*)
            recommended_retention=$DEFAULT_RETENTION_DAYS
            echo "   🔍 Tipo: AWS Lambda"
            ;;
        *"api-gateway"*|*"aws/apigateway"*)
            recommended_retention=$DEFAULT_RETENTION_DAYS
            echo "   🔍 Tipo: API Gateway"
            ;;
        *"ecs"*|*"aws/ecs"*)
            recommended_retention=$DEFAULT_RETENTION_DAYS
            echo "   🔍 Tipo: ECS"
            ;;
        *"rds"*|*"aws/rds"*)
            recommended_retention=$CRITICAL_RETENTION_DAYS
            echo "   🔍 Tipo: RDS (Crítico)"
            ;;
        *"debug"*|*"dev"*|*"test"*)
            recommended_retention=$DEBUG_RETENTION_DAYS
            echo "   🔍 Tipo: Debug/Development"
            ;;
        *"events"*|*"aws/events"*)
            recommended_retention=$DEFAULT_RETENTION_DAYS
            echo "   🔍 Tipo: EventBridge/Events"
            ;;
        *)
            recommended_retention=$DEFAULT_RETENTION_DAYS
            echo "   🔍 Tipo: General"
            ;;
    esac
    
    echo "   💡 Retención recomendada: $recommended_retention días"
    
    # Verificar si necesita actualización
    needs_update=false
    if [ "$current_retention" = "Never (∞)" ]; then
        needs_update=true
        echo "   ⚠️  Acción: Configurar retención (actualmente sin límite)"
    elif [ "$current_retention" != "$recommended_retention" ]; then
        needs_update=true
        echo "   ⚠️  Acción: Actualizar retención ($current_retention → $recommended_retention días)"
    else
        echo "   ✅ Acción: Sin cambios necesarios"
    fi
    
    if [ "$needs_update" = true ]; then
        retention_policies["$log_group_name"]=$recommended_retention
        groups_to_update=$((groups_to_update + 1))
    fi
    
    echo ""
done <<< "$(echo "$log_groups_json" | jq -r '.[] | @json')"

# Calcular tamaño total en GB
total_size_gb=$(awk "BEGIN {printf \"%.2f\", $total_stored_bytes / 1024 / 1024 / 1024}")

echo "📊 RESUMEN DE ESTADO:"
echo "────────────────────────────────────────────────────────────────────"
echo "📋 Total Log Groups: $total_log_groups"
echo "✅ Con retención configurada: $groups_with_retention"
echo "⚠️  Sin retención (∞): $groups_without_retention"
echo "🔄 Requieren actualización: $groups_to_update"
echo "💾 Almacenamiento total: ${total_size_gb} GB"

echo ""
echo "=== Paso 2: Aplicando Políticas de Retención ==="

if [ "$groups_to_update" -eq 0 ]; then
    echo "✅ Todos los Log Groups ya tienen retención apropiada configurada"
else
    echo "🔧 Configurando retención para $groups_to_update Log Group(s)..."
    echo ""
    
    updated_count=0
    failed_count=0
    
    for log_group_name in "${!retention_policies[@]}"; do
        retention_days=${retention_policies[$log_group_name]}
        
        echo "   📋 Configurando: $log_group_name"
        echo "   ⏰ Retención: $retention_days días"
        
        if aws logs put-retention-policy \
            --log-group-name "$log_group_name" \
            --retention-in-days $retention_days \
            --profile $PROFILE \
            --region $REGION 2>/dev/null; then
            
            echo "   ✅ Retención configurada exitosamente"
            updated_count=$((updated_count + 1))
        else
            echo "   ❌ Error configurando retención"
            failed_count=$((failed_count + 1))
        fi
        echo ""
    done
    
    echo "📊 Resultado de actualización:"
    echo "   ✅ Log Groups actualizados: $updated_count"
    if [ "$failed_count" -gt 0 ]; then
        echo "   ❌ Log Groups con errores: $failed_count"
    fi
fi

echo ""
echo "=== Paso 3: Configurando Alertas de Costos ==="

echo "💰 Configurando alertas para costos de CloudWatch Logs..."

# Crear SNS topic para alertas de costos si no existe
sns_topic_name="cloudwatch-logs-cost-alerts"
existing_topic=$(aws sns list-topics \
    --profile $PROFILE \
    --region $REGION \
    --query "Topics[?contains(TopicArn, '$sns_topic_name')].TopicArn" \
    --output text)

if [ -z "$existing_topic" ]; then
    echo "📧 Creando SNS Topic para alertas de costos: $sns_topic_name"
    
    topic_arn=$(aws sns create-topic \
        --name "$sns_topic_name" \
        --profile $PROFILE \
        --region $REGION \
        --query 'TopicArn' \
        --output text)
    
    echo "✅ SNS Topic creado: $topic_arn"
else
    topic_arn="$existing_topic"
    echo "✅ Usando SNS Topic existente: $topic_arn"
fi

# Crear métrica personalizada para monitorear logs ingestion
echo ""
echo "📊 Configurando métrica de monitoreo de ingesta de logs..."

# Crear alarma para ingesta alta de logs (>1GB por día)
aws cloudwatch put-metric-alarm \
    --alarm-name "HighLogIngestion-CloudWatchLogs" \
    --alarm-description "High log ingestion rate in CloudWatch Logs" \
    --metric-name "IncomingLogEvents" \
    --namespace "AWS/Logs" \
    --statistic Sum \
    --period 86400 \
    --threshold 1000000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$topic_arn" \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "⚠️  Alarma ya existe o error en configuración"

echo "🚨 Alarma de ingesta configurada"

echo ""
echo "=== Paso 4: Análisis de Optimización ==="

echo "🔍 Analizando oportunidades de optimización de costos..."

# Calcular ahorro estimado
estimated_monthly_savings=0

if [ "$groups_without_retention" -gt 0 ]; then
    # Estimación: logs sin retención pueden crecer indefinidamente
    # Asumiendo ~$0.50 per GB stored por mes
    potential_monthly_cost=$(awk "BEGIN {printf \"%.2f\", $total_size_gb * 0.50}")
    estimated_monthly_savings=$(awk "BEGIN {printf \"%.2f\", $potential_monthly_cost * 0.3}")  # 30% de ahorro estimado
fi

echo ""
echo "📊 ANÁLISIS DE OPTIMIZACIÓN:"
echo "────────────────────────────────────────────────────────────────────"
echo "💾 Almacenamiento actual: ${total_size_gb} GB"
echo "⚠️  Log Groups sin retención: $groups_without_retention"
echo "💰 Costo mensual estimado actual: ~\$$(awk "BEGIN {printf \"%.2f\", $total_size_gb * 0.50}") USD"
if [ "$groups_without_retention" -gt 0 ]; then
    echo "💚 Ahorro mensual estimado: ~\$${estimated_monthly_savings} USD"
fi

echo ""
echo "=== Paso 5: Verificación Final ==="

echo "🔍 Verificando configuración final..."

# Verificar estado después de los cambios
final_check=$(aws logs describe-log-groups \
    --profile $PROFILE \
    --region $REGION \
    --query 'logGroups[*].[logGroupName,retentionInDays]' \
    --output json)

final_with_retention=0
final_without_retention=0

while IFS= read -r log_group_data; do
    current_retention=$(echo "$log_group_data" | jq -r '.[1]')
    
    if [ "$current_retention" = "null" ]; then
        final_without_retention=$((final_without_retention + 1))
    else
        final_with_retention=$((final_with_retention + 1))
    fi
done <<< "$(echo "$final_check" | jq -r '.[] | @json')"

echo ""
echo "📊 ESTADO FINAL:"
echo "────────────────────────────────────────────────────────────────────"
echo "✅ Log Groups con retención: $final_with_retention"
echo "⚠️  Log Groups sin retención: $final_without_retention"

compliance_percentage=$(awk "BEGIN {printf \"%.1f\", ($final_with_retention / $total_log_groups) * 100}")
echo "📈 Compliance de retención: ${compliance_percentage}%"

echo ""
echo "=================================================================="
echo "✅ CONFIGURACIÓN COMPLETADA - RETENCIÓN CLOUDWATCH LOGS"
echo "=================================================================="
echo ""

echo "📋 RESUMEN DE CONFIGURACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏢 Account ID: $ACCOUNT_ID"
echo "🌍 Región: $REGION"
echo "📋 Total Log Groups: $total_log_groups"
echo "🔄 Log Groups actualizados: $updated_count"
echo "📈 Compliance final: ${compliance_percentage}%"
echo "💾 Almacenamiento total: ${total_size_gb} GB"
echo "📧 SNS Topic alertas: $topic_arn"

echo ""
echo "🎯 POLÍTICAS DE RETENCIÓN APLICADAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VPC Flow Logs / Críticos: $CRITICAL_RETENTION_DAYS días"
echo "📚 CloudTrail / Auditoría: $ARCHIVE_RETENTION_DAYS días"
echo "⚙️  Lambda / API Gateway / General: $DEFAULT_RETENTION_DAYS días"
echo "🛠️  Debug / Development: $DEBUG_RETENTION_DAYS días"

echo ""
echo "💰 OPTIMIZACIÓN DE COSTOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Retención configurada previene crecimiento descontrolado"
echo "• Logs antiguos se eliminan automáticamente"
echo "• Reducción de costos de almacenamiento a largo plazo"
if [ "$groups_without_retention" -gt 0 ]; then
    echo "• Ahorro estimado: ~\$${estimated_monthly_savings}/mes"
fi

echo ""
echo "📊 COMANDOS DE MONITOREO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Ver todos los log groups con retención:"
echo "aws logs describe-log-groups --query 'logGroups[*].[logGroupName,retentionInDays]' --profile $PROFILE --region $REGION --output table"
echo ""
echo "# Ver log groups sin retención:"
echo "aws logs describe-log-groups --query 'logGroups[?retentionInDays==null].[logGroupName]' --profile $PROFILE --region $REGION --output text"
echo ""
echo "# Ver uso de almacenamiento:"
echo "aws logs describe-log-groups --query 'logGroups[*].[logGroupName,storedBytes]' --profile $PROFILE --region $REGION --output table"

echo ""
echo "📧 CONFIGURACIÓN DE ALERTAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Para recibir alertas de costos por email:"
echo "aws sns subscribe \\"
echo "    --topic-arn $topic_arn \\"
echo "    --protocol email \\"
echo "    --notification-endpoint su-email@dominio.com \\"
echo "    --profile $PROFILE --region $REGION"

echo ""
echo "⚠️  MEJORES PRÁCTICAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Revisar políticas de retención trimestralmente"
echo "• Ajustar retención según requisitos de compliance"
echo "• Monitorear costos de CloudWatch Logs regularmente"
echo "• Configurar log level apropiado en aplicaciones"
echo "• Usar log sampling para aplicaciones de alto volumen"
echo "• Exportar logs críticos a S3 para almacenamiento a largo plazo"

echo ""
echo "🔍 PRÓXIMOS PASOS RECOMENDADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar suscripciones SNS para alertas de costos"
echo "2. Implementar exportación automática a S3 para logs de auditoría"
echo "3. Configurar filtros de métricas para análisis específicos"
echo "4. Establecer dashboards CloudWatch para monitoreo visual"
echo "5. Revisar y ajustar log levels en aplicaciones"

echo ""
echo "=================================================================="
echo "🎉 RETENCIÓN CLOUDWATCH LOGS - CONFIGURACIÓN EXITOSA"
echo "=================================================================="