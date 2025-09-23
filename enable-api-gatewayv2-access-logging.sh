#!/bin/bash
# enable-api-gatewayv2-access-logging.sh

PROFILE=${1:-xxxxxx}
REGION=${2:-us-east-1}
LOG_GROUP_NAME=${3:-/aws/apigateway/access-logs}

echo "=== Habilitando Access Logging para todas las APIs de API Gateway V2 ==="
echo "Perfil: $PROFILE | Región: $REGION | Log Group: $LOG_GROUP_NAME"

# Crear el CloudWatch Log Group si no existe
aws logs create-log-group --log-group-name $LOG_GROUP_NAME --profile $PROFILE --region $REGION 2>/dev/null || echo "✔ Log Group ya existe"

# Obtener todas las APIs
API_IDS=$(aws apigatewayv2 get-apis --query 'Items[*].ApiId' --output text --profile $PROFILE --region $REGION)

for API_ID in $API_IDS; do
    echo "-> API ID: $API_ID"
    
    # Listar todos los stages de la API
    STAGES=$(aws apigatewayv2 get-stages --api-id $API_ID --query 'Items[*].StageName' --output text --profile $PROFILE --region $REGION)
    
    for STAGE in $STAGES; do
        echo "   -> Stage: $STAGE"
        
        # Habilitar Access Logging
        aws apigatewayv2 update-stage \
            --api-id $API_ID \
            --stage-name $STAGE \
            --access-log-settings "{\"DestinationArn\":\"arn:aws:logs:$REGION:$(aws sts get-caller-identity --query 'Account' --output text --profile $PROFILE)/log-group:$LOG_GROUP_NAME\",\"Format\":\"\$context.identity.sourceIp - \$context.identity.userAgent [\$context.requestTime] \\\"\$context.httpMethod \$context.resourcePath \$context.protocol\\\" \$context.status\"}" \
            --profile $PROFILE \
            --region $REGION

        if [ $? -eq 0 ]; then
            echo "      ✔ Access Logging habilitado"
        else
            echo "      ⚠ Error habilitando Access Logging"
        fi
    done
done

echo "✅ Proceso completado en todas las APIs y stages."

