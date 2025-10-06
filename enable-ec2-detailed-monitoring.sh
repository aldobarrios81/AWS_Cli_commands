#!/bin/bash

# Configuración de Monitoreo Detallado para Instancias EC2
# Este script habilita el monitoreo detallado (métricas cada 1 minuto) para todas las instancias EC2
# y configura alarmas básicas de CloudWatch para monitoreo proactivo

set -e

PROFILE="azcenit"
REGION="us-east-1"

echo "=================================================================="
echo "📊 HABILITANDO MONITOREO DETALLADO EC2"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Paso 1: Escaneando Instancias EC2 ==="

# Obtener todas las instancias EC2
instances_json=$(aws ec2 describe-instances \
    --profile $PROFILE \
    --region $REGION \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0],Monitoring.State]' \
    --output json)

total_instances=$(echo "$instances_json" | jq -r '.[] | .[]' | jq -s 'length')

echo "🖥️  Total de instancias EC2 encontradas: $total_instances"

if [ "$total_instances" -eq 0 ]; then
    echo "✅ No hay instancias EC2 en esta región"
    echo ""
    echo "=================================================================="
    echo "🎯 MONITOREO DETALLADO EC2 - NO HAY INSTANCIAS"
    echo "=================================================================="
    exit 0
fi

echo ""

# Contadores
running_instances=0
stopped_instances=0
detailed_monitoring_enabled=0
detailed_monitoring_disabled=0
instances_to_enable=()

echo "📋 INVENTARIO DE INSTANCIAS EC2:"
echo "────────────────────────────────────────────────────────────────────"

# Procesar cada instancia
while IFS= read -r instance_data; do
    instance_id=$(echo "$instance_data" | jq -r '.[0]')
    instance_state=$(echo "$instance_data" | jq -r '.[1]')
    instance_type=$(echo "$instance_data" | jq -r '.[2]')
    instance_name=$(echo "$instance_data" | jq -r '.[3]')
    monitoring_state=$(echo "$instance_data" | jq -r '.[4]')
    
    # Manejar valores null
    if [ "$instance_name" = "null" ] || [ -z "$instance_name" ]; then
        instance_name="Sin nombre"
    fi
    
    echo "🖥️  Instancia: $instance_id"
    echo "   📛 Nombre: $instance_name"
    echo "   🔧 Tipo: $instance_type"
    echo "   🔄 Estado: $instance_state"
    echo "   📊 Monitoreo: $monitoring_state"
    
    # Contar por estado
    if [ "$instance_state" = "running" ]; then
        running_instances=$((running_instances + 1))
    else
        stopped_instances=$((stopped_instances + 1))
    fi
    
    # Verificar estado del monitoreo
    if [ "$monitoring_state" = "enabled" ]; then
        detailed_monitoring_enabled=$((detailed_monitoring_enabled + 1))
        echo "   ✅ Monitoreo detallado YA HABILITADO"
    else
        detailed_monitoring_disabled=$((detailed_monitoring_disabled + 1))
        echo "   ⚠️  Monitoreo detallado DESHABILITADO"
        instances_to_enable+=("$instance_id")
    fi
    
    echo ""
done <<< "$(echo "$instances_json" | jq -r '.[] | .[] | @json')"

echo "📊 RESUMEN DE ESTADO:"
echo "────────────────────────────────────────────────────────────────────"
echo "🖥️  Total instancias: $total_instances"
echo "🟢 Instancias ejecutándose: $running_instances"
echo "🔴 Instancias detenidas: $stopped_instances"
echo "✅ Monitoreo detallado habilitado: $detailed_monitoring_enabled"
echo "⚠️  Monitoreo detallado deshabilitado: $detailed_monitoring_disabled"

echo ""
echo "=== Paso 2: Habilitando Monitoreo Detallado ==="

if [ ${#instances_to_enable[@]} -eq 0 ]; then
    echo "✅ Todas las instancias ya tienen monitoreo detallado habilitado"
else
    echo "🔧 Habilitando monitoreo detallado para ${#instances_to_enable[@]} instancia(s)..."
    
    for instance_id in "${instances_to_enable[@]}"; do
        echo "   📊 Habilitando para: $instance_id"
        
        if aws ec2 monitor-instances \
            --instance-ids "$instance_id" \
            --profile $PROFILE \
            --region $REGION \
            --output table; then
            echo "   ✅ Monitoreo detallado habilitado exitosamente"
        else
            echo "   ❌ Error habilitando monitoreo detallado"
        fi
        echo ""
    done
fi

echo ""
echo "=== Paso 3: Configurando Alarmas CloudWatch Básicas ==="

# Configurar alarmas para instancias en ejecución
echo "🚨 Configurando alarmas CloudWatch para instancias activas..."

# Obtener instancias en ejecución para configurar alarmas
running_instances_data=$(aws ec2 describe-instances \
    --profile $PROFILE \
    --region $REGION \
    --filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
    --output json)

if [ "$(echo "$running_instances_data" | jq -r '.[] | .[]' | jq -s 'length')" -gt 0 ]; then
    
    # Crear SNS topic para alarmas si no existe
    sns_topic_name="ec2-monitoring-alerts"
    existing_topic=$(aws sns list-topics \
        --profile $PROFILE \
        --region $REGION \
        --query "Topics[?contains(TopicArn, '$sns_topic_name')].TopicArn" \
        --output text)

    if [ -z "$existing_topic" ]; then
        echo "📧 Creando SNS Topic para alarmas: $sns_topic_name"
        
        topic_arn=$(aws sns create-topic \
            --name "$sns_topic_name" \
            --profile $PROFILE \
            --region $REGION \
            --query 'TopicArn' \
            --output text)
        
        echo "✅ SNS Topic creado: $topic_arn"
    else
        topic_arn="$existing_topic"
        echo "✅ Using existing SNS Topic: $topic_arn"
    fi
    
    echo ""
    echo "🔔 Configurando alarmas para cada instancia..."
    
    alarm_count=0
    
    while IFS= read -r instance_data; do
        instance_id=$(echo "$instance_data" | jq -r '.[0]')
        instance_name=$(echo "$instance_data" | jq -r '.[1]')
        
        # Manejar valores null
        if [ "$instance_name" = "null" ] || [ -z "$instance_name" ]; then
            instance_name="$instance_id"
        fi
        
        echo "   🚨 Configurando alarmas para: $instance_id ($instance_name)"
        
        # Alarma de CPU High (>80% por 2 períodos consecutivos)
        alarm_name="EC2-HighCPU-$instance_id"
        aws cloudwatch put-metric-alarm \
            --alarm-name "$alarm_name" \
            --alarm-description "High CPU utilization for $instance_name ($instance_id)" \
            --metric-name CPUUtilization \
            --namespace AWS/EC2 \
            --statistic Average \
            --period 60 \
            --threshold 80 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "$topic_arn" \
            --ok-actions "$topic_arn" \
            --dimensions Name=InstanceId,Value=$instance_id \
            --profile $PROFILE \
            --region $REGION > /dev/null
        
        # Alarma de Status Check Failed
        alarm_name="EC2-StatusCheckFailed-$instance_id"
        aws cloudwatch put-metric-alarm \
            --alarm-name "$alarm_name" \
            --alarm-description "Status check failed for $instance_name ($instance_id)" \
            --metric-name StatusCheckFailed \
            --namespace AWS/EC2 \
            --statistic Maximum \
            --period 60 \
            --threshold 1 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --evaluation-periods 1 \
            --alarm-actions "$topic_arn" \
            --ok-actions "$topic_arn" \
            --dimensions Name=InstanceId,Value=$instance_id \
            --profile $PROFILE \
            --region $REGION > /dev/null
        
        alarm_count=$((alarm_count + 2))
        
    done <<< "$(echo "$running_instances_data" | jq -r '.[] | .[] | @json')"
    
    echo "   ✅ $alarm_count alarmas configuradas exitosamente"
    
else
    echo "⚠️  No hay instancias en ejecución para configurar alarmas"
fi

echo ""
echo "=== Paso 4: Verificación Final ==="

echo "🔍 Verificando estado actual del monitoreo detallado..."

# Verificar estado final
final_monitoring_check=$(aws ec2 describe-instances \
    --profile $PROFILE \
    --region $REGION \
    --query 'Reservations[*].Instances[*].[InstanceId,Monitoring.State]' \
    --output json)

enabled_count=0
disabled_count=0

while IFS= read -r instance_data; do
    instance_id=$(echo "$instance_data" | jq -r '.[0]')
    monitoring_state=$(echo "$instance_data" | jq -r '.[1]')
    
    if [ "$monitoring_state" = "enabled" ]; then
        enabled_count=$((enabled_count + 1))
    else
        disabled_count=$((disabled_count + 1))
    fi
    
done <<< "$(echo "$final_monitoring_check" | jq -r '.[] | .[] | @json')"

echo "📊 ESTADO FINAL:"
echo "────────────────────────────────────────────────────────────────────"
echo "✅ Instancias con monitoreo detallado: $enabled_count"
echo "⚠️  Instancias sin monitoreo detallado: $disabled_count"

# Cálculo de costos
monthly_cost=$(awk "BEGIN {printf \"%.2f\", $enabled_count * 2.10}")
echo "💰 Costo estimado mensual del monitoreo detallado: ~\$${monthly_cost} USD"

echo ""
echo "=================================================================="
echo "✅ CONFIGURACIÓN COMPLETADA - MONITOREO DETALLADO EC2"
echo "=================================================================="
echo ""

echo "📋 RESUMEN DE CONFIGURACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏢 Account ID: $ACCOUNT_ID"
echo "🌍 Región: $REGION"
echo "🖥️  Total instancias: $total_instances"
echo "📊 Monitoreo detallado habilitado: $enabled_count"
echo "📧 SNS Topic: $topic_arn"
echo "🚨 Alarmas configuradas: $alarm_count"

echo ""
echo "🎯 FUNCIONALIDADES HABILITADAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Métricas de CloudWatch cada 1 minuto (en lugar de 5 minutos)"
echo "✅ Alarmas automáticas de CPU alta (>80% por 2 minutos)"
echo "✅ Alarmas de status check failed"
echo "✅ Notificaciones SNS para todas las alarmas"
echo "✅ Mejor granularidad para auto-scaling y troubleshooting"

echo ""
echo "📧 SUSCRIPCIÓN A ALERTAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Para recibir alertas por email, ejecute:"
echo "aws sns subscribe \\"
echo "    --topic-arn $topic_arn \\"
echo "    --protocol email \\"
echo "    --notification-endpoint su-email@dominio.com \\"
echo "    --profile $PROFILE --region $REGION"

echo ""
echo "📊 COMANDOS DE VERIFICACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Ver estado de monitoreo de todas las instancias:"
echo "aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Monitoring.State]' --profile $PROFILE --region $REGION --output table"
echo ""
echo "# Ver alarmas configuradas:"
echo "aws cloudwatch describe-alarms --alarm-name-prefix EC2- --profile $PROFILE --region $REGION"
echo ""
echo "# Ver métricas disponibles:"
echo "aws cloudwatch list-metrics --namespace AWS/EC2 --profile $PROFILE --region $REGION"

echo ""
echo "💡 BENEFICIOS DEL MONITOREO DETALLADO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Detección más rápida de problemas (1 min vs 5 min)"
echo "• Mejor precisión en auto-scaling policies"
echo "• Troubleshooting más efectivo con mayor granularidad"
echo "• Alertas más rápidas para incidents críticos"
echo "• Mejor baseline para análisis de rendimiento"
echo "• Cumplimiento mejorado para SLAs estrictos"

echo ""
echo "⚠️  CONSIDERACIONES DE COSTOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Monitoreo detallado: ~\$2.10/mes por instancia"
echo "• Métricas adicionales: Cobro por métrica consultada"
echo "• Alarmas CloudWatch: ~\$0.10/mes por alarma"
echo "• ROI: Detección temprana previene downtime costoso"
echo "• Recomendación: Usar solo en instancias críticas si el presupuesto es limitado"

echo ""
echo "=================================================================="
echo "🎉 MONITOREO DETALLADO EC2 - CONFIGURACIÓN EXITOSA"
echo "=================================================================="

