#!/bin/bash
# enable-s3-auto-logging.sh
# Auto-remediation: Habilita logging en todos los buckets S3 que no tengan logging
# Perfil y región
PROFILE="xxxxxxxx"
REGION="us-east-1"
LOG_BUCKET="s3-central-logs-bucket"  # Cambia por tu bucket de logs central
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:xxxxxxxxxxxxx:s3-event-topic"

echo "=== Auto-Remediation S3 Bucket Logging ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Bucket de logs central: $LOG_BUCKET"

# Listar buckets
BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text --profile $PROFILE)

for BUCKET in $BUCKETS; do
    echo "-> Revisando bucket: $BUCKET"
    
    LOGGING=$(aws s3api get-bucket-logging --bucket $BUCKET --profile $PROFILE)
    
    if [[ $LOGGING == "{}" ]]; then
        echo "   ⚠ Logging no habilitado. Activando..."
        aws s3api put-bucket-logging \
            --bucket $BUCKET \
            --bucket-logging-status "{
                \"LoggingEnabled\": {
                    \"TargetBucket\": \"$LOG_BUCKET\",
                    \"TargetPrefix\": \"$BUCKET/\"
                }
            }" \
            --profile $PROFILE
        echo "   ✔ Logging habilitado para $BUCKET"
        
        # Opcional: notificar via SNS
        if [[ ! -z $SNS_TOPIC_ARN ]]; then
            aws sns publish --topic-arn $SNS_TOPIC_ARN \
                --message "Se habilitó logging para bucket S3: $BUCKET" \
                --profile $PROFILE
            echo "   ✔ Notificación enviada a SNS"
        fi
    else
        echo "   ✔ Logging ya habilitado"
    fi
done

echo "=== Proceso completado ✅ ==="

