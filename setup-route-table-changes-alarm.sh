#!/bin/bash
# setup-route-table-changes-alarm.sh (corregido)

REGION="us-east-1"
PROFILE="xxxxx"
LOG_GROUP="/aws/cloudtrail/xxxxxxx-trail"
METRIC_NAME="RouteTableChanges"
ALARM_NAME="RouteTableChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en Route Tables en $REGION ==="

# Crear Metric Filter en CloudWatch Logs (patrón simplificado)
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{ $.eventSource = "ec2.amazonaws.com" && ($.eventName = "CreateRouteTable" || $.eventName = "DeleteRouteTable" || $.eventName = "AssociateRouteTable" || $.eventName = "DisassociateRouteTable" || $.eventName = "ReplaceRoute" || $.eventName = "ReplaceRouteTableAssociation") }'

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
    --alarm-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts" \
    --ok-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts" \
    --insufficient-data-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts"

echo "=== Metric Filter y Alarma configuradas para Route Table Changes ✅ ==="

