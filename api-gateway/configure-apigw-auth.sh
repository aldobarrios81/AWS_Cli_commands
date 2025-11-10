#!/bin/bash
set -euo pipefail

PROFILE="azcenit"
REGION="us-east-1"

echo "=== Listando todos los API Gateway HTTP en la cuenta (perfil: $PROFILE, región: $REGION) ==="

# Listar todos los APIs (solo los HTTP, no REST)
APIS=$(aws apigatewayv2 get-apis \
  --profile "$PROFILE" \
  --region "$REGION" \
  --query "Items[?ProtocolType=='HTTP'].{Id:ApiId,Name:Name}" \
  --output json)

COUNT=$(echo "$APIS" | jq length)
if [[ "$COUNT" -eq 0 ]]; then
  echo "⚠️  No se encontraron APIs HTTP en esta cuenta/región"
  exit 0
fi

for row in $(echo "${APIS}" | jq -c '.[]'); do
  API_ID=$(echo "$row" | jq -r '.Id')
  API_NAME=$(echo "$row" | jq -r '.Name')

  echo "------------------------------------------------------------"
  echo "Procesando API: $API_NAME (ID: $API_ID)"

  # Obtener rutas del API
  ROUTES=$(aws apigatewayv2 get-routes \
    --api-id "$API_ID" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "Items[].{Id:RouteId,Key:RouteKey}" \
    --output json)

  RCOUNT=$(echo "$ROUTES" | jq length)
  if [[ "$RCOUNT" -eq 0 ]]; then
    echo "⚠️  No se encontraron rutas en el API $API_NAME ($API_ID)"
    continue
  fi

  for r in $(echo "${ROUTES}" | jq -c '.[]'); do
    ROUTE_ID=$(echo "$r" | jq -r '.Id')
    ROUTE_KEY=$(echo "$r" | jq -r '.Key')

    echo ">>> Configurando ruta: $ROUTE_KEY (RouteId: $ROUTE_ID)"

    aws apigatewayv2 update-route \
      --api-id "$API_ID" \
      --route-id "$ROUTE_ID" \
      --authorization-type AWS_IAM \
      --profile "$PROFILE" \
      --region "$REGION" >/dev/null || {
        echo "❌ Error al actualizar ruta $ROUTE_KEY en API $API_NAME"
        continue
      }

    echo "✅ Ruta $ROUTE_KEY actualizada a AWS_IAM"
  done
done

echo "🎉 Todas las rutas de todos los APIs HTTP fueron actualizadas a AWS_IAM"

