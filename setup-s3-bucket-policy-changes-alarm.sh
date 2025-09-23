#!/bin/bash
# setup-s3-bucket-policy-changes-alarm.sh
# Establece un Log Metric Filter y alarma para cambios en políticas de buckets S3

REGION="us-east-1"
PROFILE="xxxxxx"
LOG_GROUP="/aws/cloudtrail/xxxxxxxx-trail"
METRIC_NAME="S3BucketPolicyChanges"
ALARM_NAME="S3BucketPolicyChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en S3 Bucket Policies en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{($.eventSource = "s3.amazonaws.com") && ($.eventName = "PutBucketPolicy" || $.eventName = "DeleteBucketPolicy")}'
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
    --alarm-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts" \
    --ok-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts" \
    --insufficient-data-actions "arn:aws:sns:$REGION:xxxxxxxxxxxxx:securityhub-alerts"
echo "✔ Alarma creada: $ALARM_NAME"

echo "=== Metric Filter y Alarma configuradas para cambios en S3 Bucket Policies ✅ ==="

