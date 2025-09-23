#!/bin/bash
# create-ebs-snapshots.sh
# Crea snapshots recientes para todos los volúmenes EBS en us-east-1

REGION="us-east-1"
PROFILE="xxxxxxxxx"

echo "=== Creando snapshots recientes para todos los volúmenes EBS en $REGION ==="

# Listar todos los volúmenes EBS
VOLUMES=$(aws ec2 describe-volumes --region $REGION --profile $PROFILE --query 'Volumes[].VolumeId' --output text)

for VOLUME in $VOLUMES; do
    DESCRIPTION="Snapshot automático de volumen $VOLUME creado el $(date '+%Y-%m-%d %H:%M:%S')"
    echo "-> Creando snapshot para volumen: $VOLUME"
    aws ec2 create-snapshot \
        --region $REGION \
        --profile $PROFILE \
        --volume-id "$VOLUME" \
        --description "$DESCRIPTION"
    echo "   ✔ Snapshot creado para $VOLUME"
done

echo "✅ Snapshots recientes creados para todos los volúmenes EBS"

