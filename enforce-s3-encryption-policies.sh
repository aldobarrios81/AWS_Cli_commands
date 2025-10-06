#!/bin/bash

# Implementar políticas de bucket para forzar cifrado SSE
# Previene uploads sin cifrado server-side encryption

set -e

PROFILE="ancla"
REGION="us-east-1"

echo "=== Implementando Políticas de Bucket para Forzar Cifrado SSE ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== Aplicando políticas de seguridad a buckets S3 ==="

# Obtener lista de todos los buckets
buckets=$(aws s3api list-buckets --profile $PROFILE --query 'Buckets[].Name' --output text)
total_buckets=0
policies_applied=0
policies_skipped=0

for bucket in $buckets; do
    # Verificar región del bucket
    bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --profile $PROFILE --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
    if [ "$bucket_region" = "None" ] || [ "$bucket_region" = "null" ]; then
        bucket_region="us-east-1"
    fi
    
    # Solo procesar buckets en us-east-1
    if [ "$bucket_region" != "$REGION" ]; then
        echo "-> Saltando bucket en región diferente: $bucket ($bucket_region)"
        continue
    fi
    
    total_buckets=$((total_buckets + 1))
    echo "-> Aplicando política de cifrado forzado: $bucket"
    
    # Verificar si ya tiene una política
    existing_policy=$(aws s3api get-bucket-policy --bucket "$bucket" --profile $PROFILE --region $REGION 2>/dev/null || echo "NO_POLICY")
    
    if echo "$existing_policy" | grep -q "Policy"; then
        echo "   ⚠️  Bucket ya tiene política existente - saltando para evitar conflictos"
        policies_skipped=$((policies_skipped + 1))
        continue
    fi
    
    # Crear política para denegar uploads sin cifrado SSE
    cat > /tmp/bucket-encryption-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyIncorrectEncryptionHeader",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${bucket}/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": ["AES256", "aws:kms"]
                }
            }
        },
        {
            "Sid": "DenyUnEncryptedObjectUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${bucket}/*",
            "Condition": {
                "Null": {
                    "s3:x-amz-server-side-encryption": "true"
                }
            }
        },
        {
            "Sid": "RequireSSLRequestsOnly",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${bucket}",
                "arn:aws:s3:::${bucket}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    
    # Aplicar la política
    if aws s3api put-bucket-policy \
        --bucket "$bucket" \
        --policy file:///tmp/bucket-encryption-policy.json \
        --profile $PROFILE \
        --region $REGION 2>/dev/null; then
        echo "   ✔ Política de cifrado forzado aplicada"
        policies_applied=$((policies_applied + 1))
    else
        echo "   ❌ Error aplicando política (puede ser bucket del sistema o sin permisos)"
        policies_skipped=$((policies_skipped + 1))
    fi
done

# Limpiar archivos temporales
rm -f /tmp/bucket-encryption-policy.json

echo ""
echo "=== Resumen de Políticas de Cifrado Forzado ==="
echo "📊 Total buckets procesados: $total_buckets"
echo "✅ Políticas aplicadas: $policies_applied"
echo "⚠️  Políticas saltadas: $policies_skipped"

echo ""
echo "=== Políticas Implementadas ==="
echo "🚫 DenyIncorrectEncryptionHeader:"
echo "   - Deniega uploads que especifiquen algoritmo incorrecto"
echo "   - Solo permite AES256 o aws:kms"
echo ""
echo "🚫 DenyUnEncryptedObjectUploads:"
echo "   - Deniega uploads sin header de cifrado SSE"
echo "   - Fuerza especificar s3:x-amz-server-side-encryption"
echo ""
echo "🔒 RequireSSLRequestsOnly:"
echo "   - Deniega todas las operaciones sin HTTPS"
echo "   - Fuerza cifrado en tránsito"

echo ""
echo "=== Verificación de Políticas ==="
echo "💡 Para verificar políticas aplicadas:"
echo "   aws s3api get-bucket-policy --bucket BUCKET_NAME --profile $PROFILE"
echo ""
echo "🧪 Para probar la política:"
echo "   aws s3 cp test.txt s3://BUCKET_NAME/ --profile $PROFILE"
echo "   (Sin --sse debería fallar)"

echo ""
echo "=== Políticas de Cifrado Forzado Completadas ✅ ==="