#!/bin/bash
# setup-security-group-changes-alarm.sh
# Establece un Log Metric Filter y alarma para cambios en Security Groups

REGION="us-east-1"
PROFILE="AZLOGICA"
LOG_GROUP="CloudTrail/DefaultLogGroup"
METRIC_NAME="SecurityGroupChanges"
ALARM_NAME="SecurityGroupChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en Security Groups en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{($.eventSource = "ec2.amazonaws.com") && ($.eventName = "AuthorizeSecurityGroupIngress" || $.eventName = "RevokeSecurityGroupIngress" || $.eventName = "AuthorizeSecurityGroupEgress" || $.eventName = "RevokeSecurityGroupEgress" || $.eventName = "CreateSecurityGroup" || $.eventName = "DeleteSecurityGroup")}'
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

echo "=== Metric Filter y Alarma configuradas para Security Group Changes ✅ ==="

