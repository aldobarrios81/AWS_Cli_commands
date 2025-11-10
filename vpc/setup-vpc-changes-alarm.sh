#!/bin/bash
# setup-vpc-changes-alarm.sh

REGION="us-east-1"
PROFILE="xxxxxxxxx"
LOG_GROUP="/aws/cloudtrail/xxxxxx-trail"
METRIC_NAME="VPCChanges"
ALARM_NAME="VPCChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en VPC en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{ $.eventSource = "ec2.amazonaws.com" && ($.eventName = "CreateVpc" || $.eventName = "DeleteVpc" || $.eventName = "ModifyVpcAttribute" || $.eventName = "AcceptVpcPeeringConnection" || $.eventName = "RejectVpcPeeringConnection") }'

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

echo "=== Metric Filter y Alarma configuradas para VPC Changes ✅ ==="

