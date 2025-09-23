#!/bin/bash
# enable-route53-logging.sh
# Habilita Route53 Query Logging en todas las Hosted Zones públicas
# Perfil: xxxxxx | Región: us-east-1

PROFILE="xxxxxxx"
REGION="us-east-1"

# Bucket S3 donde se enviarán los logs
LOG_BUCKET="route53-query-logs-$RANDOM-$RANDOM"

echo "=== Habilitando Route53 Query Logging en todas las Hosted Zones públicas ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo "-> Creando bucket de logs: $LOG_BUCKET"

aws s3 mb s3://$LOG_BUCKET --profile $PROFILE --region $REGION
echo "✔ Bucket $LOG_BUCKET creado"

# Listar todas las hosted zones
ZONES=$(aws route53 list-hosted-zones --profile $PROFILE --query 'HostedZones[?Config.PrivateZone==`false`].Id' --output text)

for ZONE_ID in $ZONES; do
    echo "-> Habilitando query logging para Hosted Zone: $ZONE_ID"
    aws route53 create-query-logging-config \
        --hosted-zone-id $ZONE_ID \
        --cloud-watch-logs-log-group-arn arn:aws:logs:$REGION:$AWS_ACCOUNT_ID:log-group:/aws/route53/$ZONE_ID \
        --profile $PROFILE \
        --region $REGION \
        2>/dev/null

    if [ $? -eq 0 ]; then
        echo "   ✔ Query Logging habilitado para $ZONE_ID"
    else
        echo "   ⚠ Ya existe un logging configurado para $ZONE_ID o ocurrió un error"
    fi
done

echo "=== Proceso completado ✅ ==="

