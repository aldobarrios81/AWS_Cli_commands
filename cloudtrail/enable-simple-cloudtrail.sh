#!/bin/bash

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
REGION="us-east-1"

# Verificar credenciales
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")

echo "=== Habilitando CloudTrail Simple para metrokia ==="
echo "Perfil: $PROFILE | Account ID: $ACCOUNT_ID"
echo ""

# Verificar si ya existe un trail
EXISTING_TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[].Name' --output text)

if [ -n "$EXISTING_TRAILS" ]; then
    echo "✅ Ya existen trails configurados:"
    for trail in $EXISTING_TRAILS; do
        echo "   - $trail"
        
        # Verificar estado de logging
        LOGGING_STATUS=$(aws cloudtrail get-trail-status --name "$trail" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text 2>/dev/null)
        echo "     Estado de logging: $LOGGING_STATUS"
        
        if [ "$LOGGING_STATUS" != "true" ]; then
            echo "     🚀 Iniciando logging para $trail..."
            aws cloudtrail start-logging --name "$trail" --profile "$PROFILE" --region "$REGION"
        fi
    done
    
    echo ""
    echo "🎉 CloudTrail ya está configurado!"
    echo "✅ Console authentication events se están registrando"
    echo ""
    echo "🔧 Ahora puedes ejecutar:"
    echo "./general/setup-console-auth-failures-monitoring.sh $PROFILE"
    exit 0
fi

# Si no hay trails, habilitar el trail por defecto de la consola
echo "⚠️ No se encontraron trails configurados"
echo ""
echo "📋 PARA HABILITAR CLOUDTRAIL:"
echo "1. Ve a la consola de AWS CloudTrail"
echo "2. Crea un trail básico desde la interfaz web"
echo "3. O ejecuta el siguiente comando para crear uno simple:"
echo ""
echo "BUCKET_NAME=\"cloudtrail-simple-${ACCOUNT_ID}\""
echo "TRAIL_NAME=\"cloudtrail-simple-${PROFILE}\""
echo ""

# Crear bucket simple
BUCKET_NAME="cloudtrail-simple-${ACCOUNT_ID}"
TRAIL_NAME="cloudtrail-simple-${PROFILE}"

echo "🪣 Creando bucket S3 simple..."
aws s3 mb "s3://${BUCKET_NAME}" --profile "$PROFILE" --region "$REGION" 2>/dev/null || echo "Bucket ya existe o error"

# Crear trail simple (solo S3, sin CloudWatch)
echo "🛤️ Creando trail simple..."
TRAIL_RESULT=$(aws cloudtrail create-trail \
    --name "$TRAIL_NAME" \
    --s3-bucket-name "$BUCKET_NAME" \
    --include-global-service-events \
    --is-multi-region-trail \
    --profile "$PROFILE" \
    --region "$REGION" 2>&1)

if echo "$TRAIL_RESULT" | grep -q "TrailARN\|already exists"; then
    echo "✅ Trail creado: $TRAIL_NAME"
    
    # Iniciar logging
    echo "🚀 Iniciando logging..."
    aws cloudtrail start-logging --name "$TRAIL_NAME" --profile "$PROFILE" --region "$REGION"
    
    # Verificar estado
    LOGGING_STATUS=$(aws cloudtrail get-trail-status --name "$TRAIL_NAME" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text 2>/dev/null)
    
    if [ "$LOGGING_STATUS" = "true" ]; then
        echo "✅ CloudTrail configurado y activo!"
        echo ""
        echo "⚠️ IMPORTANTE: Este trail solo envía logs a S3"
        echo "Para console auth failures monitoring, necesitas configurar CloudWatch Logs"
        echo ""
        echo "🔧 Alternativa: Usar AWS Config o Security Hub para compliance monitoring"
    else
        echo "❌ Error: Logging no está activo"
    fi
else
    echo "❌ Error creando trail: $TRAIL_RESULT"
    echo ""
    echo "💡 SOLUCIÓN RECOMENDADA:"
    echo "Crear CloudTrail manualmente desde la consola AWS:"
    echo "1. Ir a CloudTrail → Trails → Create trail"
    echo "2. Usar configuración básica"
    echo "3. Ejecutar este script nuevamente"
fi

echo ""
echo "=== Configuración completada ==="