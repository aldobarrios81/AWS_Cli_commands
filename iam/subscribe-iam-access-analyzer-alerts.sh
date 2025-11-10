#!/bin/bash
# Suscribirse al SNS Topic de IAM Access Analyzer
# Perfil: xxxxxx
# Región: us-east-1

PROFILE="xxxxxx"
REGION="us-east-1"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxx:iam-access-analyzer-alerts"

# Solicitar email
read -p "Ingresa el email donde quieres recibir las alertas: " EMAIL

echo "=== Suscribiendo $EMAIL al SNS Topic ==="

aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$EMAIL" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "✔ Solicitud de suscripción enviada. Revisa tu correo y confirma la suscripción."

