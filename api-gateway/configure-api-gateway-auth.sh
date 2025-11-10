#!/bin/bash
# configure-api-gateway-auth-all.sh
# Configura un Custom Authorizer en todas las APIs y rutas de API Gateway v2
# Perfil: xxxxxx | Región: us-east-1

PROFILE="xxxxxxx"
REGION="us-east-1"
AUTH_NAME="MyCustomAuth"
LAMBDA_ARN="<COLOCA_AQUI_EL_ARN_DE_TU_LAMBDA>"

echo "=== Configurando Custom Authorizer en todas las APIs y rutas ==="

# Listar todas las APIs
APIS=$(aws apigatewayv2 get-apis --profile $PROFILE --region $REGION --query 'Items[*].ApiId' --output text)

for API_ID in $APIS; do
    echo "-> Procesando API: $API_ID"

    # Verificar si ya existe el Authorizer
    AUTHORIZER_ID=$(aws apigatewayv2 get-authorizers \
        --api-id $API_ID \
        --profile $PROFILE \
        --region $REGION \
        --query "Items[?Name=='$AUTH_NAME'].AuthorizerId" \
        --output text)

    if [ -z "$AUTHORIZER_ID" ]; then
        echo "   Authorizer '$AUTH_NAME' no existe. Creando..."
        AUTHORIZER_ID=$(aws apigatewayv2 create-authorizer \
            --api-id $API_ID \
            --authorizer-type REQUEST \
            --name $AUTH_NAME \
            --identity-source "\$request.header.Authorization" \
            --authorizer-uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
            --authorizer-result-ttl-in-seconds 300 \
            --profile $PROFILE \
            --region $REGION \
            --query 'AuthorizerId' \
            --output text)
        echo "   Authorizer creado con ID: $AUTHORIZER_ID"
    else
        echo "   Authorizer existente encontrado: $AUTHORIZER_ID"
    fi

    # Listar todas las rutas de la API
    ROUTES=$(aws apigatewayv2 get-routes \
        --api-id $API_ID \
        --profile $PROFILE \
        --region $REGION \
        --query 'Items[*].RouteId' \
        --output text)

    # Asignar el Authorizer a todas las rutas
    for ROUTE_ID in $ROUTES; do
        echo "   -> Asignando Authorizer a ruta: $ROUTE_ID"
        aws apigatewayv2 update-route \
            --api-id $API_ID \
            --route-id $ROUTE_ID \
            --authorization-type CUSTOM \
            --authorizer-id $AUTHORIZER_ID \
            --profile $PROFILE \
            --region $REGION > /dev/null
    done

    echo "   ✅ Authorizer configurado en todas las rutas de la API $API_ID"
done

echo "=== Proceso completado en todas las APIs de us-east-1 ==="

