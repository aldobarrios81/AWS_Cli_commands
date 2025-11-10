#!/bin/bash
# setup-console-login-no-mfa-alarm.sh

PROFILE="xxxxxxxxx"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxxxxxxx:securityhub-alerts" # Cambia si quieres otro SNS
LOG_GROUP_PREFIX="/aws/cloudtrail/"
METRIC_NAMESPACE="Security"
METRIC_NAME="ConsoleLoginNoMFA"
ALARM_NAME="ConsoleLoginNoMFAAlarm"
ALARM_THRESHOLD=1
ALARM_PERIOD=300

echo "=== Configurando Metric Filter y Alarma para logins sin MFA en $REGION ==="

# Listar log groups de CloudTrail
LOG_GROUPS=$(aws logs describe-log-groups \
    --log-group-name-prefix $LOG_GROUP_PREFIX \
    --query 'logGroups[*].logGroupName' \
    --output text \
    --profile $PROFILE \
    --region $REGION)

if [ -z "$LOG_GROUPS" ]; then
    echo "⚠ No se encontraron log groups de CloudTrail"
    exit 0
fi

for LOG_GROUP in $LOG_GROUPS; do
    echo "-> Creando Metric Filter en Log Group: $LOG_GROUP"
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP" \
        --filter-name "ConsoleLoginNoMFAFilter" \
        --filter-pattern '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }' \
        --metric-transformations \
            metricName=$METRIC_NAME,metricNamespace=$METRIC_NAMESPACE,metricValue=1 \
        --profile $PROFILE \
        --region $REGION

    echo "-> Creando alarma para el Metric Filter: $ALARM_NAME"
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME-$LOG_GROUP" \
        --metric-name $METRIC_NAME \
        --namespace $METRIC_NAMESPACE \
        --statistic Sum \
        --period $ALARM_PERIOD \
        --evaluation-periods 1 \
        --threshold $ALARM_THRESHOLD \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --alarm-actions $SNS_TOPIC_ARN \
        --ok-actions $SNS_TOPIC_ARN \
        --profile $PROFILE \
        --region $REGION

    echo "   ✔ Alarma creada para $LOG_GROUP"
done

echo "=== Metric Filter y Alarmas configuradas para logins sin MFA ✅ ==="

