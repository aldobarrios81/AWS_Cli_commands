#!/bin/bash
# enable-s3-object-level-logging.sh

PROFILE="azcenit"
REGION="us-east-1"
TRAIL_NAME="azcenit-management-events"

echo "=== Habilitando S3 Object-Level Logging (Read Events) para todos los buckets ==="
echo "Perfil: $PROFILE | Región: $REGION | Trail: $TRAIL_NAME"

# Verificar que el trail existe
echo "-> Verificando trail: $TRAIL_NAME"
aws cloudtrail describe-trails --trail-name $TRAIL_NAME --profile $PROFILE --region $REGION >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚠ Trail $TRAIL_NAME no encontrado. Creando trail para S3 Object-Level logging..."
    
    # Crear bucket para CloudTrail si no existe
    S3_BUCKET="cloudtrail-logs-azcenit-1759610481"
    aws s3api head-bucket --bucket $S3_BUCKET --profile $PROFILE 2>/dev/null || {
        echo "-> Creando bucket para CloudTrail: $S3_BUCKET"
        aws s3api create-bucket --bucket $S3_BUCKET --profile $PROFILE --region $REGION
        
        # Configurar policy del bucket
        BUCKET_POLICY='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AWSCloudTrailAclCheck",
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "cloudtrail.amazonaws.com"
                    },
                    "Action": "s3:GetBucketAcl",
                    "Resource": "arn:aws:s3:::'$S3_BUCKET'"
                },
                {
                    "Sid": "AWSCloudTrailWrite",
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "cloudtrail.amazonaws.com"
                    },
                    "Action": "s3:PutObject",
                    "Resource": "arn:aws:s3:::'$S3_BUCKET'/*",
                    "Condition": {
                        "StringEquals": {
                            "s3:x-amz-acl": "bucket-owner-full-control"
                        }
                    }
                }
            ]
        }'
        
        aws s3api put-bucket-policy --bucket $S3_BUCKET --policy "$BUCKET_POLICY" --profile $PROFILE
    }
    
    # Crear trail
    aws cloudtrail create-trail \
        --name $TRAIL_NAME \
        --s3-bucket-name $S3_BUCKET \
        --include-global-service-events \
        --is-multi-region-trail \
        --profile $PROFILE \
        --region $REGION
        
    # Iniciar logging
    aws cloudtrail start-logging --name $TRAIL_NAME --profile $PROFILE --region $REGION
fi

# Obtener todos los buckets
echo "-> Obteniendo lista de buckets S3..."
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text --profile $PROFILE)

if [ -z "$BUCKETS" ]; then
    echo "⚠ No se encontraron buckets S3"
    exit 0
fi

echo "-> Buckets encontrados: $(echo $BUCKETS | wc -w)"

# Crear array de data resources para todos los buckets
DATA_RESOURCES="["
FIRST=true

for BUCKET in $BUCKETS; do
    echo "-> Preparando configuración para bucket: $BUCKET"
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        DATA_RESOURCES="$DATA_RESOURCES,"
    fi
    
    DATA_RESOURCES="$DATA_RESOURCES{\"Type\":\"AWS::S3::Object\",\"Values\":[\"arn:aws:s3:::$BUCKET/*\"]}"
done

DATA_RESOURCES="$DATA_RESOURCES]"

# Configurar event selectors para todos los buckets de una vez
echo "-> Configurando event selectors para S3 Object-Level logging (Read Events)..."

EVENT_SELECTORS='[{
    "ReadWriteType": "ReadOnly",
    "IncludeManagementEvents": true,
    "DataResources": '$DATA_RESOURCES'
}]'

aws cloudtrail put-event-selectors \
    --trail-name $TRAIL_NAME \
    --event-selectors "$EVENT_SELECTORS" \
    --profile $PROFILE \
    --region $REGION

if [ $? -eq 0 ]; then
    echo "✅ S3 Object-Level logging configurado exitosamente"
    echo "-> Trail: $TRAIL_NAME"
    echo "-> Buckets monitoreados: $(echo $BUCKETS | wc -w)"
    echo "-> Tipo de eventos: Solo lectura (ReadOnly)"
    echo "-> Management events: Incluidos"
    
    # Verificar configuración
    echo "-> Verificando configuración..."
    aws cloudtrail get-event-selectors --trail-name $TRAIL_NAME --profile $PROFILE --region $REGION
else
    echo "❌ Error configurando S3 Object-Level logging"
    exit 1
fi

echo "✅ Proceso completado exitosamente."

