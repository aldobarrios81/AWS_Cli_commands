#!/bin/bash
# enable-api-gatewayv2-access-logging.sh

PROFILE="azcenit"
REGION="us-east-1"
LOG_GROUP_NAME="/aws/apigateway/access-logs-azcenit"

echo "=== Habilitando Access Logging para todas las APIs de API Gateway V2 ==="
echo "Perfil: $PROFILE | Región: $REGION | Log Group: $LOG_GROUP_NAME"

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile $PROFILE)
echo "Account ID: $ACCOUNT_ID"

# Crear el CloudWatch Log Group si no existe
echo "-> Creando CloudWatch Log Group: $LOG_GROUP_NAME"
aws logs create-log-group --log-group-name $LOG_GROUP_NAME --profile $PROFILE --region $REGION 2>/dev/null || echo "✔ Log Group ya existe"

# Crear rol de servicio para API Gateway si no existe
echo "-> Verificando rol de servicio API Gateway..."
ROLE_NAME="APIGatewayV2LoggingRole"
aws iam get-role --role-name $ROLE_NAME --profile $PROFILE >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "-> Creando rol de servicio para API Gateway..."
    
    # Crear trust policy
    TRUST_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "apigateway.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document "$TRUST_POLICY" \
        --profile $PROFILE >/dev/null 2>&1
    
    # Adjuntar política para CloudWatch Logs
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs" \
        --profile $PROFILE >/dev/null 2>&1
    
    echo "✔ Rol de servicio creado"
else
    echo "✔ Rol de servicio ya existe"
fi

# Construir ARN del Log Group
LOG_GROUP_ARN="arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$LOG_GROUP_NAME"
echo "-> Log Group ARN: $LOG_GROUP_ARN"

# Obtener todas las APIs
echo "-> Obteniendo APIs de API Gateway V2..."
API_IDS=$(aws apigatewayv2 get-apis --query 'Items[*].ApiId' --output text --profile $PROFILE --region $REGION)

if [ -z "$API_IDS" ]; then
    echo "⚠ No se encontraron APIs de API Gateway V2"
    exit 0
fi

echo "-> APIs encontradas: $(echo $API_IDS | wc -w)"

for API_ID in $API_IDS; do
    echo "-> API ID: $API_ID"
    
    # Obtener información de la API
    API_INFO=$(aws apigatewayv2 get-api --api-id $API_ID --profile $PROFILE --region $REGION)
    API_NAME=$(echo "$API_INFO" | jq -r '.Name // "N/A"')
    API_PROTOCOL=$(echo "$API_INFO" | jq -r '.ProtocolType // "N/A"')
    
    echo "   📝 Nombre: $API_NAME"
    echo "   🔗 Protocolo: $API_PROTOCOL"
    
    # Listar todos los stages de la API
    STAGES=$(aws apigatewayv2 get-stages --api-id $API_ID --query 'Items[*].StageName' --output text --profile $PROFILE --region $REGION)
    
    if [ -z "$STAGES" ]; then
        echo "   ⚠ No se encontraron stages"
        continue
    fi
    
    for STAGE in $STAGES; do
        echo "   -> Stage: $STAGE"
        
        # Habilitar Access Logging con formato correcto
        aws apigatewayv2 update-stage \
            --api-id $API_ID \
            --stage-name $STAGE \
            --access-log-settings "DestinationArn=$LOG_GROUP_ARN,Format=\$context.requestId \$context.identity.sourceIp [\$context.requestTime] \$context.httpMethod \$context.resourcePath \$context.status" \
            --profile $PROFILE \
            --region $REGION >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "      ✔ Access Logging habilitado correctamente"
            
            # Verificar configuración
            CURRENT_LOG_DEST=$(aws apigatewayv2 get-stage --api-id $API_ID --stage-name $STAGE --profile $PROFILE --region $REGION --query 'AccessLogSettings.DestinationArn' --output text 2>/dev/null)
            if [ "$CURRENT_LOG_DEST" != "None" ] && [ -n "$CURRENT_LOG_DEST" ]; then
                echo "      ✅ Verificado: Logging configurado"
            fi
        else
            echo "      ❌ Error habilitando Access Logging"
        fi
    done
done

echo "✅ Proceso completado en todas las APIs y stages."

