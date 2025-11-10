#!/bin/bash
# setup-nacl-changes-alarm-metrokia.sh
# Establece un Log Metric Filter y alarma para cambios en NACLs (Network Access Control Lists)

REGION="us-east-1"
PROFILE="metrokia"
LOG_GROUP="/aws/cloudtrail/cloudtrail-metrokia-console-auth"
METRIC_NAME="NACLChanges"
ALARM_NAME="NACLChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en NACLs en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{($.eventSource = "ec2.amazonaws.com") && ($.eventName = "CreateNetworkAcl" || $.eventName = "CreateNetworkAclEntry" || $.eventName = "DeleteNetworkAcl" || $.eventName = "DeleteNetworkAclEntry" || $.eventName = "ReplaceNetworkAclEntry" || $.eventName = "ReplaceNetworkAclAssociation")}'
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
    --alarm-actions "arn:aws:sns:$REGION:848576886895:cis-security-alerts-metrokia" \
    --ok-actions "arn:aws:sns:$REGION:848576886895:cis-security-alerts-metrokia" \
    --insufficient-data-actions "arn:aws:sns:$REGION:848576886895:cis-security-alerts-metrokia"
echo "✔ Alarma creada: $ALARM_NAME"

echo "=== Metric Filter y Alarma configuradas para NACL Changes ✅ ==="

echo ""
echo "🔍 EVENTOS NACL MONITOREADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• CreateNetworkAcl - Creación de nuevas ACLs de red"
echo "• CreateNetworkAclEntry - Creación de reglas en ACLs"
echo "• DeleteNetworkAcl - Eliminación de ACLs de red"
echo "• DeleteNetworkAclEntry - Eliminación de reglas de ACLs"
echo "• ReplaceNetworkAclEntry - Modificación de reglas existentes"
echo "• ReplaceNetworkAclAssociation - Cambios de asociación ACL-subnet"