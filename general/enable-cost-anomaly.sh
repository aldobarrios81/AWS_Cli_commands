#!/bin/bash

AWS_PROFILE="xxxxxxxx"
AWS_REGION="us-east-1"

MONITOR_NAME="xxxxxxxxx"
SUBSCRIPTION_NAME="xxxxxxx"
ALERT_EMAIL="tu-email@dominio.com"

echo "=== Creando Cost Anomaly Detection Monitor ==="

MONITOR_ARN=$(aws ce create-anomaly-monitor \
    --anomaly-detection-monitor-name "$MONITOR_NAME" \
    --monitor-type COST \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'AnomalyDetectionMonitor.Arn' \
    --output text)

if [ -z "$MONITOR_ARN" ]; then
    echo "❌ Error creando el monitor"
    exit 1
fi

echo "✔ Monitor creado: $MONITOR_ARN"

echo "=== Creando suscripción de alertas ==="

SUBSCRIPTION_ARN=$(aws ce create-anomaly-subscription \
    --anomaly-detection-subscription-name "$SUBSCRIPTION_NAME" \
    --monitor-arn "$MONITOR_ARN" \
    --subscribers "AccountId=xxxxxxxxxxxxx,Type=EMAIL,Address=$ALERT_EMAIL" \
    --threshold 100 \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'AnomalyDetectionSubscription.Arn' \
    --output text)

if [ -z "$SUBSCRIPTION_ARN" ]; then
    echo "❌ Error creando la suscripción"
    exit 1
fi

echo "✔ Suscripción creada: $SUBSCRIPTION_ARN"
echo "✅ Cost Anomaly Detection habilitado correctamente"

