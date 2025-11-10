#!/bin/bash
# enable-waf-appsync-fixed.sh
# Habilita AWS WAF en todos los endpoints de AppSync de forma correcta.

REGION="us-east-1"
PROFILE="xxxxxxx"
WEB_ACL_NAME="AppSync-WAF-ACL"

echo "=== Habilitando AWS WAF en AppSync Endpoints en $REGION ==="

# Obtener Web ACL existente
web_acl_arn=$(aws wafv2 list-web-acls \
    --scope REGIONAL \
    --region $REGION \
    --profile $PROFILE \
    --query "WebACLs[?Name=='$WEB_ACL_NAME'].ARN" \
    --output text)

if [ -z "$web_acl_arn" ]; then
    echo "-> No se encontró Web ACL $WEB_ACL_NAME. Crea una antes de continuar."
    exit 1
fi
echo "-> Web ACL existente encontrado: $web_acl_arn"

# Listar todos los AppSync APIs
apis=$(aws appsync list-graphql-apis \
    --profile $PROFILE \
    --region $REGION \
    --query 'graphqlApis[].apiId' \
    --output text)

if [ -z "$apis" ]; then
    echo "No se encontraron AppSync APIs en $REGION."
    exit 0
fi

# Asociar Web ACL usando el comando correcto
for api_id in $apis; do
    echo "-> Asociando Web ACL a AppSync API: $api_id..."

    aws wafv2 associate-web-acl \
        --web-acl-arn "$web_acl_arn" \
        --resource-arn "arn:aws:appsync:$REGION:xxxxxxxxxxxxx:apis/$api_id" \
        --region $REGION \
        --profile $PROFILE

    echo "   ✅ WAF habilitado en API $api_id"
done

echo "=== AWS WAF habilitado en todos los AppSync Endpoints ✅ ==="

