#!/bin/bash
REGION="us-east-1"
PROFILE="xxxxxx"
LOG_GROUP="/aws/cloudtrail/xxxxxxx-trail"
ALARM_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxxx:aws-security-alerts"
FILTER_NAME="ConsoleAuthFailuresFilter"
ALARM_NAME="ConsoleAuthFailuresAlarm"

echo "=== Configurando Metric Filter y Alarma para fallos de autenticación en consola ==="

# 1️⃣ Crear Metric Filter
aws logs put-metric-filter \
    --log-group-name $LOG_GROUP \
    --filter-name $FILTER_NAME \
    --filter-pattern '{ $.eventName = "ConsoleLogin" && $.errorMessage = "Failed authentication" }' \
    --metric-transformations metricName=ConsoleAuthFailures,metricNamespace=Security,metricValue=1 \
    --region $REGION --profile $PROFILE

# 2️⃣ Crear Alarma en CloudWatch
aws cloudwatch put-metric-alarm \
    --alarm-name $ALARM_NAME \
    --metric-name ConsoleAuthFailures \
    --namespace Security \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions $ALARM_TOPIC_ARN \
    --region $REGION \
    --profile $PROFILE

echo "✅ Metric Filter y Alarma configurados para fallos de autenticación en consola"

