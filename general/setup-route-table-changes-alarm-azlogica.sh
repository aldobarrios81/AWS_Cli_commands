#!/bin/bash
# setup-route-table-changes-alarm-azlogica.sh
# Establece un Log Metric Filter y alarma para cambios en Route Tables

REGION="us-east-1"
PROFILE="AZLOGICA"
LOG_GROUP="CloudTrail/DefaultLogGroup"
METRIC_NAME="RouteTableChanges"
ALARM_NAME="RouteTableChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en Route Tables en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{($.eventSource = "ec2.amazonaws.com") && ($.eventName = "CreateRoute" || $.eventName = "CreateRouteTable" || $.eventName = "ReplaceRoute" || $.eventName = "ReplaceRouteTableAssociation" || $.eventName = "DeleteRouteTable" || $.eventName = "DeleteRoute" || $.eventName = "DisassociateRouteTable" || $.eventName = "AssociateRouteTable")}'
echo "✔ Metric Filter creado: $METRIC_NAME"

# Crear Alarma en CloudWatch
aws cloudwatch put-metric-alarm \
    --region $REGION \
    --profile $PROFILE \
    --alarm-name $ALARM_NAME \
    --metric-name $METRIC_NAME \
    --namespace "SecurityMetrics" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions "arn:aws:sns:$REGION:669153057384:cis-security-alerts-AZLOGICA" \
    --ok-actions "arn:aws:sns:$REGION:669153057384:cis-security-alerts-AZLOGICA" \
    --insufficient-data-actions "arn:aws:sns:$REGION:669153057384:cis-security-alerts-AZLOGICA"
echo "✔ Alarma creada: $ALARM_NAME"

echo "=== Metric Filter y Alarma configuradas para Route Table Changes ✅ ==="

echo ""
echo "🔍 EVENTOS ROUTE TABLE MONITOREADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 OPERACIONES DE ROUTE TABLES:"
echo "• CreateRouteTable - Creación de nuevas tablas de rutas"
echo "• DeleteRouteTable - Eliminación de tablas de rutas"
echo "• AssociateRouteTable - Asociación de tabla de rutas con subnet"
echo "• DisassociateRouteTable - Desasociación de tabla de rutas"
echo "• ReplaceRouteTableAssociation - Cambio de asociación de tabla de rutas"  
echo ""
echo "🛣️ OPERACIONES DE RUTAS:"
echo "• CreateRoute - Creación de nuevas rutas"
echo "• DeleteRoute - Eliminación de rutas"
echo "• ReplaceRoute - Modificación de rutas existentes"