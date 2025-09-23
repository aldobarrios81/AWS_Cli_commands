#!/bin/bash

REGION="us-east-1"
PROFILE="xxxxxxxx"

echo "=== Actualizando volúmenes EBS de gp2 a gp3 en $REGION ==="

# Listar todos los volúmenes gp2
VOLUMES=$(aws ec2 describe-volumes \
    --region $REGION \
    --profile $PROFILE \
    --filters Name=volume-type,Values=gp2 \
    --query "Volumes[].VolumeId" \
    --output text)

if [ -z "$VOLUMES" ]; then
    echo "No se encontraron volúmenes gp2 en la región $REGION."
    exit 0
fi

for VOL in $VOLUMES; do
    echo "-> Actualizando volumen $VOL de gp2 a gp3..."
    
    aws ec2 modify-volume \
        --volume-id $VOL \
        --volume-type gp3 \
        --region $REGION \
        --profile $PROFILE

    if [ $? -eq 0 ]; then
        echo "   ✔ Volumen $VOL actualizado correctamente."
    else
        echo "   ⚠ Error al actualizar volumen $VOL."
    fi
done

echo "✅ Proceso completado: todos los volúmenes gp2 actualizados a gp3"

