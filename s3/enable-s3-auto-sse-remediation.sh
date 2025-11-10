#!/bin/bash

# Auto-remediación para S3 Bucket Server-Side Encryption (SSE)
# Detecta buckets sin cifrado SSE y los configura automáticamente

set -e

PROFILE="azcenit"
REGION="us-east-1"
SSE_ALGORITHM="AES256"  # Opciones: AES256, aws:kms

echo "=== Implementando Auto-Remediación para S3 Server-Side Encryption ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Algoritmo de cifrado: $SSE_ALGORITHM"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Escaneando buckets sin cifrado SSE habilitado ==="

# Obtener lista de todos los buckets
buckets=$(aws s3api list-buckets --profile $PROFILE --query 'Buckets[].Name' --output text)
total_buckets=0
buckets_without_encryption=0
buckets_remediated=0
buckets_with_encryption=0

for bucket in $buckets; do
    total_buckets=$((total_buckets + 1))
    
    # Obtener la región del bucket
    bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --profile $PROFILE --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
    if [ "$bucket_region" = "None" ] || [ "$bucket_region" = "null" ]; then
        bucket_region="us-east-1"
    fi
    
    # Solo procesar buckets en la región especificada
    if [ "$bucket_region" != "$REGION" ]; then
        echo "-> Saltando bucket en región diferente: $bucket ($bucket_region)"
        continue
    fi
    
    echo "-> Verificando cifrado SSE en bucket: $bucket"
    
    # Verificar si tiene cifrado SSE habilitado
    encryption_status=$(aws s3api get-bucket-encryption --bucket "$bucket" --profile $PROFILE --region $REGION 2>/dev/null || echo "NO_ENCRYPTION")
    
    if echo "$encryption_status" | grep -q "ServerSideEncryptionConfiguration"; then
        echo "   ✔ Cifrado SSE ya habilitado"
        buckets_with_encryption=$((buckets_with_encryption + 1))
        
        # Mostrar detalles del cifrado actual
        current_algorithm=$(echo "$encryption_status" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' 2>/dev/null || echo "Unknown")
        echo "   📋 Algoritmo actual: $current_algorithm"
        
        # Si usa KMS, mostrar la key
        if [ "$current_algorithm" = "aws:kms" ]; then
            kms_key=$(echo "$encryption_status" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' 2>/dev/null || echo "aws/s3")
            echo "   🔑 KMS Key: $kms_key"
        fi
    else
        echo "   ⚠ Cifrado SSE deshabilitado - Aplicando auto-remediación"
        buckets_without_encryption=$((buckets_without_encryption + 1))
        
        # Configurar cifrado SSE
        if [ "$SSE_ALGORITHM" = "AES256" ]; then
            # Configurar cifrado AES256
            cat > /tmp/encryption-config.json << EOF
{
    "Rules": [
        {
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": false
        }
    ]
}
EOF
        else
            # Configurar cifrado KMS (usar clave por defecto aws/s3)
            cat > /tmp/encryption-config.json << EOF
{
    "Rules": [
        {
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "aws:kms",
                "KMSMasterKeyID": "aws/s3"
            },
            "BucketKeyEnabled": true
        }
    ]
}
EOF
        fi
        
        if aws s3api put-bucket-encryption \
            --bucket "$bucket" \
            --server-side-encryption-configuration file:///tmp/encryption-config.json \
            --profile $PROFILE \
            --region $REGION 2>/dev/null; then
            echo "   ✔ Auto-remediación aplicada: cifrado $SSE_ALGORITHM habilitado"
            buckets_remediated=$((buckets_remediated + 1))
            
            # Verificar que se aplicó correctamente
            sleep 2
            verification=$(aws s3api get-bucket-encryption --bucket "$bucket" --profile $PROFILE --region $REGION 2>/dev/null || echo "VERIFICATION_FAILED")
            if echo "$verification" | grep -q "ServerSideEncryptionConfiguration"; then
                echo "   ✅ Verificación exitosa: cifrado configurado correctamente"
            else
                echo "   ⚠️  Advertencia: no se pudo verificar la configuración"
            fi
        else
            echo "   ❌ Error aplicando auto-remediación"
        fi
    fi
done

# Limpiar archivos temporales
rm -f /tmp/encryption-config.json

echo ""
echo "=== Resumen de Auto-Remediación SSE ==="
echo "📊 Total buckets procesados: $total_buckets"
echo "✅ Buckets con cifrado SSE: $buckets_with_encryption"
echo "⚠️  Buckets sin cifrado detectados: $buckets_without_encryption"
echo "🔧 Buckets remediados: $buckets_remediated"
echo "🔒 Algoritmo de cifrado aplicado: $SSE_ALGORITHM"

if [ $buckets_without_encryption -eq 0 ]; then
    echo ""
    echo "🎯 Estado: ✅ COMPLIANT - Todos los buckets tienen cifrado SSE habilitado"
elif [ $buckets_remediated -eq $buckets_without_encryption ]; then
    echo ""
    echo "🎯 Estado: ✅ REMEDIADO - Todos los buckets sin cifrado fueron configurados"
else
    failed_remediation=$((buckets_without_encryption - buckets_remediated))
    echo ""
    echo "🎯 Estado: ⚠️  PARCIAL - $failed_remediation buckets no pudieron ser remediados"
fi

echo ""
echo "=== Configuración Avanzada ==="
echo "💡 Para usar cifrado KMS en lugar de AES256:"
echo "   Modifique SSE_ALGORITHM=\"aws:kms\" en el script"
echo ""
echo "🔐 Para usar una clave KMS específica:"
echo "   Configure KMSMasterKeyID con su clave personalizada"
echo ""
echo "📋 Políticas de bucket recomendadas:"
echo "   - Denegar uploads sin cifrado SSE"
echo "   - Requerir cifrado en tránsito (HTTPS)"
echo "   - Configurar lifecycle para objetos cifrados"

echo ""
echo "=== Auto-Remediación SSE Completada ✅ ==="