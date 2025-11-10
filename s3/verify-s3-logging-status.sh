#!/bin/bash

# Verificación de Auto-Remediación S3 Logging
# Valida el estado del logging en buckets S3 para todos los perfiles

set -e

REGION="us-east-1"

echo "=== Verificación Auto-Remediación S3 Logging ==="
echo "Región: $REGION"
echo ""

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    echo ""
    echo "Ejemplos:"
    echo "  $0 metrokia"
    echo "  $0 AZLOGICA"
    exit 1
fi

# Array de perfiles (un solo perfil proporcionado por parámetro)
profiles=("$1")

for profile in "${profiles[@]}"; do
    echo "🔍 Verificando perfil: $profile"
    
    # Verificar credenciales y obtener información de la cuenta
    CALLER_IDENTITY=$(aws sts get-caller-identity --profile $profile --region $REGION 2>/dev/null || echo "ERROR")
    
    if [ "$CALLER_IDENTITY" = "ERROR" ]; then
        echo "   ❌ Error accediendo al perfil $profile"
        echo "   💡 Verificar: aws configure list --profile $profile"
        continue
    fi
    
    account_id=$(echo "$CALLER_IDENTITY" | jq -r '.Account' 2>/dev/null)
    current_user=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)
    
    echo "   ✅ Credenciales válidas"
    echo "   📋 Account ID: $account_id"
    echo "   👤 Usuario/Rol: $current_user"
    
    # Verificar bucket de logs centralizado
    log_bucket="central-s3-logs-${account_id}"
    if aws s3api head-bucket --bucket "$log_bucket" --profile $profile --region $REGION 2>/dev/null; then
        echo "   ✔ Bucket de logs centralizado existe: $log_bucket"
    else
        echo "   ❌ Bucket de logs centralizado NO existe: $log_bucket"
        continue
    fi
    
    # Contar buckets con y sin logging
    total_buckets=0
    buckets_with_logging=0
    buckets_without_logging=0
    
    # Obtener lista de buckets
    buckets=$(aws s3api list-buckets --profile $profile --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    
    for bucket in $buckets; do
        # Saltar buckets de logs
        if [[ "$bucket" == *"access-logs"* ]] || [[ "$bucket" == "$log_bucket" ]]; then
            continue
        fi
        
        # Verificar región del bucket
        bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --profile $profile --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
        if [ "$bucket_region" = "None" ] || [ "$bucket_region" = "null" ]; then
            bucket_region="us-east-1"
        fi
        
        # Solo procesar buckets en us-east-1
        if [ "$bucket_region" != "$REGION" ]; then
            continue
        fi
        
        total_buckets=$((total_buckets + 1))
        
        # Verificar logging
        logging_status=$(aws s3api get-bucket-logging --bucket "$bucket" --profile $profile --region $REGION 2>/dev/null || echo "DISABLED")
        
        if echo "$logging_status" | grep -q "TargetBucket"; then
            buckets_with_logging=$((buckets_with_logging + 1))
        else
            buckets_without_logging=$((buckets_without_logging + 1))
        fi
    done
    
    echo "   📊 Buckets en $REGION: $total_buckets"
    echo "   ✅ Con logging: $buckets_with_logging"
    echo "   ⚠️  Sin logging: $buckets_without_logging"
    
    if [ $buckets_without_logging -eq 0 ]; then
        echo "   🎯 Estado: ✅ COMPLIANT - Todos los buckets tienen logging"
    else
        echo "   🎯 Estado: ⚠️  NON-COMPLIANT - $buckets_without_logging buckets sin logging"
    fi
    
    echo ""
done

echo "=== Verificación Completada ✅ ==="