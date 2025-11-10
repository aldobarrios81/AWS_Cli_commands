#!/bin/bash
# setup-network-gateway-changes-alarm-metrokia.sh
# Establece un Log Metric Filter y alarma para cambios en Network Gateways (Internet Gateway, NAT Gateway, VPN Gateway, Customer Gateway)

REGION="us-east-1"
PROFILE="metrokia"
LOG_GROUP="/aws/cloudtrail/cloudtrail-metrokia-console-auth"
METRIC_NAME="NetworkGatewayChanges"
ALARM_NAME="NetworkGatewayChangesAlarm"

echo "=== Configurando Metric Filter y Alarma para cambios en Network Gateways en $REGION ==="

# Crear Metric Filter en CloudWatch Logs
aws logs put-metric-filter \
    --region $REGION \
    --profile $PROFILE \
    --log-group-name $LOG_GROUP \
    --filter-name $METRIC_NAME \
    --metric-transformations metricName=$METRIC_NAME,metricNamespace="SecurityMetrics",metricValue=1 \
    --filter-pattern '{($.eventSource = "ec2.amazonaws.com") && ($.eventName = "CreateInternetGateway" || $.eventName = "DeleteInternetGateway" || $.eventName = "AttachInternetGateway" || $.eventName = "DetachInternetGateway" || $.eventName = "CreateNatGateway" || $.eventName = "DeleteNatGateway" || $.eventName = "CreateVpnGateway" || $.eventName = "DeleteVpnGateway" || $.eventName = "AttachVpnGateway" || $.eventName = "DetachVpnGateway" || $.eventName = "CreateCustomerGateway" || $.eventName = "DeleteCustomerGateway")}'
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

echo "=== Metric Filter y Alarma configuradas para Network Gateway Changes ✅ ==="

echo ""
echo "🔍 EVENTOS NETWORK GATEWAY MONITOREADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 INTERNET GATEWAYS:"
echo "• CreateInternetGateway - Creación de Internet Gateways"
echo "• DeleteInternetGateway - Eliminación de Internet Gateways"
echo "• AttachInternetGateway - Asociación de IGW con VPC"
echo "• DetachInternetGateway - Desasociación de IGW de VPC"
echo ""
echo "🚀 NAT GATEWAYS:"
echo "• CreateNatGateway - Creación de NAT Gateways"
echo "• DeleteNatGateway - Eliminación de NAT Gateways"
echo ""
echo "🔐 VPN GATEWAYS:"
echo "• CreateVpnGateway - Creación de VPN Gateways"
echo "• DeleteVpnGateway - Eliminación de VPN Gateways"
echo "• AttachVpnGateway - Asociación de VGW con VPC"
echo "• DetachVpnGateway - Desasociación de VGW de VPC"
echo ""
echo "🏢 CUSTOMER GATEWAYS:"
echo "• CreateCustomerGateway - Creación de Customer Gateways"
echo "• DeleteCustomerGateway - Eliminación de Customer Gateways"