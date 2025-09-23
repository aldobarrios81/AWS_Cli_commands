#!/bin/bash
# enable-s3-object-level-logging.sh

PROFILE=${1:-xxxxxx}
REGION=${2:-us-east-1}
TRAIL_NAME=${3:-xxxxxx-trail}

echo "=== Habilitando S3 Object-Level Logging (Read Events) para todos los buckets ==="
echo "Perfil: $PROFILE | Región: $REGION | Trail: $TRAIL_NAME"

# Obtener todos los buckets
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text --profile $PROFILE)

for BUCKET in $BUCKETS; do
    echo "-> Configurando logging para bucket: $BUCKET"
    
    # Habilitar eventos de datos S3 en CloudTrail para este bucket
    aws cloudtrail put-event-selectors \
        --trail-name $TRAIL_NAME \
        --event-selectors "ReadWriteType=ReadOnly,IncludeManagementEvents=false,DataResources=[{Type=AWS::S3::Object,Values=[arn:aws:s3:::$BUCKET/]}]" \
        --profile $PROFILE \
        --region $REGION

    if [ $? -eq 0 ]; then
        echo "   ✔ Logging habilitado para bucket: $BUCKET"
    else
        echo "   ⚠ Error habilitando logging para bucket: $BUCKET"
    fi
done

echo "✅ Proceso completado."

