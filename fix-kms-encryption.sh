#!/bin/bash

# KMS CloudTrail Encryption Permission Fix
# Automated solution to enable KMS encryption on CloudTrail trails

PROFILE_1="azbeacons"
PROFILE_2="azcenit"
REGION="us-east-1"

echo "🔐 REPARACIÓN AUTOMÁTICA DE KMS ENCRYPTION - CLOUDTRAIL"
echo "═══════════════════════════════════════════════════════════════"
echo "Perfiles a configurar: $PROFILE_1, $PROFILE_2"
echo "Región: $REGION"
echo "Fecha: $(date)"
echo

# Function to fix KMS permissions for a profile
fix_kms_permissions() {
    local PROFILE=$1
    local ACCOUNT_ID=$2
    
    echo "🔧 REPARANDO PERMISOS PARA PERFIL: $PROFILE"
    echo "────────────────────────────────────────────────────────────────"
    
    # Get KMS key info
    KMS_KEY_ARN=$(aws kms describe-key --key-id alias/cloudtrail-key --profile "$PROFILE" --region "$REGION" --query KeyMetadata.Arn --output text 2>/dev/null)
    
    if [ -z "$KMS_KEY_ARN" ] || [ "$KMS_KEY_ARN" = "None" ]; then
        echo "❌ No se encontró KMS key para $PROFILE"
        return 1
    fi
    
    echo "✔ KMS Key: $KMS_KEY_ARN"
    
    # Create enhanced KMS policy with CloudTrail specific permissions
    echo "📝 Creando política KMS mejorada..."
    cat > /tmp/enhanced-kms-policy-$PROFILE.json <<EOF
{
  "Version": "2012-10-17",
  "Id": "EnhancedCloudTrailKMSPolicy",
  "Statement": [
    {
      "Sid": "EnableIAMUserPermissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudTrailToEncrypt",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudTrailToDescribeKey",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": [
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ServiceToUseKey",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowDirectKeyAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::$ACCOUNT_ID:root"
        ]
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Apply enhanced KMS policy
    aws kms put-key-policy \
        --key-id alias/cloudtrail-key \
        --policy file:///tmp/enhanced-kms-policy-$PROFILE.json \
        --policy-name default \
        --profile "$PROFILE" --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "  ✔ Política KMS mejorada aplicada"
    else
        echo "  ⚠️ Error aplicando política KMS"
    fi
    
    # Wait a moment for policy propagation
    echo "⏳ Esperando propagación de permisos..."
    sleep 5
    
    return 0
}

# Function to apply KMS encryption to trails
apply_kms_encryption() {
    local PROFILE=$1
    local ACCOUNT_ID=$2
    
    echo
    echo "🔒 APLICANDO KMS ENCRYPTION A TRAILS: $PROFILE"
    echo "────────────────────────────────────────────────────────────────"
    
    # Get KMS key ARN
    KMS_KEY_ARN=$(aws kms describe-key --key-id alias/cloudtrail-key --profile "$PROFILE" --region "$REGION" --query KeyMetadata.Arn --output text 2>/dev/null)
    
    # Get all trails
    TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[*].Name' --output text 2>/dev/null)
    
    if [ -z "$TRAILS" ]; then
        echo "⚠️ No se encontraron trails en $PROFILE"
        return 1
    fi
    
    echo "📋 Trails encontrados: $TRAILS"
    
    local SUCCESS_COUNT=0
    local TOTAL_COUNT=0
    
    # Apply encryption to each trail
    for TRAIL in $TRAILS; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        echo
        echo "🔐 Configurando encryption en trail: $TRAIL"
        
        # Try multiple approaches
        # Approach 1: Using KMS ARN
        RESULT1=$(aws cloudtrail update-trail \
            --name "$TRAIL" \
            --kms-key-id "$KMS_KEY_ARN" \
            --profile "$PROFILE" \
            --region "$REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "  ✔ Encryption configurado con ARN"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            continue
        fi
        
        # Approach 2: Using alias
        echo "  🔄 Intentando con alias..."
        RESULT2=$(aws cloudtrail update-trail \
            --name "$TRAIL" \
            --kms-key-id "alias/cloudtrail-key" \
            --profile "$PROFILE" \
            --region "$REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "  ✔ Encryption configurado con alias"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            continue
        fi
        
        # Approach 3: Using key ID only
        KMS_KEY_ID=$(echo "$KMS_KEY_ARN" | cut -d'/' -f2)
        echo "  🔄 Intentando con Key ID..."
        RESULT3=$(aws cloudtrail update-trail \
            --name "$TRAIL" \
            --kms-key-id "$KMS_KEY_ID" \
            --profile "$PROFILE" \
            --region "$REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "  ✔ Encryption configurado con Key ID"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "  ❌ No se pudo configurar encryption en $TRAIL"
            echo "     Error: $(echo $RESULT3 | cut -c1-100)..."
        fi
    done
    
    echo
    echo "📊 Resultados para $PROFILE:"
    echo "   Trails procesados: $TOTAL_COUNT"
    echo "   Encryption exitoso: $SUCCESS_COUNT"
    echo "   Porcentaje de éxito: $((SUCCESS_COUNT * 100 / TOTAL_COUNT))%"
    
    return 0
}

# Function to verify encryption status
verify_encryption() {
    local PROFILE=$1
    
    echo
    echo "🔍 VERIFICANDO ENCRYPTION STATUS: $PROFILE"
    echo "────────────────────────────────────────────────────────────────"
    
    TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[*].Name' --output text 2>/dev/null)
    
    local ENCRYPTED_COUNT=0
    local TOTAL_COUNT=0
    
    for TRAIL in $TRAILS; do
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        
        KMS_STATUS=$(aws cloudtrail describe-trails --trail-name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text 2>/dev/null)
        LOGGING_STATUS=$(aws cloudtrail get-trail-status --name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text 2>/dev/null)
        
        echo "📋 $TRAIL:"
        echo "   Logging: $([ "$LOGGING_STATUS" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
        echo "   KMS: $([ "$KMS_STATUS" != "None" ] && echo "✅ CONFIGURADO" || echo "❌ NO CONFIGURADO")"
        
        [ "$KMS_STATUS" != "None" ] && ENCRYPTED_COUNT=$((ENCRYPTED_COUNT + 1))
    done
    
    echo
    echo "📊 Resumen $PROFILE:"
    echo "   Total trails: $TOTAL_COUNT"
    echo "   Con KMS encryption: $ENCRYPTED_COUNT"
    echo "   Porcentaje encriptado: $((ENCRYPTED_COUNT * 100 / TOTAL_COUNT))%"
    
    return $ENCRYPTED_COUNT
}

# Main execution
echo "🚀 INICIANDO PROCESO DE REPARACIÓN..."
echo

# Process azbeacons profile
echo "═══ PROCESANDO PERFIL: $PROFILE_1 ═══"
ACCOUNT_1=$(aws sts get-caller-identity --profile "$PROFILE_1" --query Account --output text 2>/dev/null)
if [ -n "$ACCOUNT_1" ]; then
    echo "✔ Account ID: $ACCOUNT_1"
    fix_kms_permissions "$PROFILE_1" "$ACCOUNT_1"
    apply_kms_encryption "$PROFILE_1" "$ACCOUNT_1"
    verify_encryption "$PROFILE_1"
    RESULT_1=$?
else
    echo "❌ No se pudo acceder al perfil $PROFILE_1"
    RESULT_1=0
fi

echo
echo "═══ PROCESANDO PERFIL: $PROFILE_2 ═══"
ACCOUNT_2=$(aws sts get-caller-identity --profile "$PROFILE_2" --query Account --output text 2>/dev/null)
if [ -n "$ACCOUNT_2" ]; then
    echo "✔ Account ID: $ACCOUNT_2"
    fix_kms_permissions "$PROFILE_2" "$ACCOUNT_2"
    apply_kms_encryption "$PROFILE_2" "$ACCOUNT_2"
    verify_encryption "$PROFILE_2"
    RESULT_2=$?
else
    echo "❌ No se pudo acceder al perfil $PROFILE_2"
    RESULT_2=0
fi

# Final summary
echo
echo "🎯 RESUMEN FINAL DE REPARACIÓN"
echo "═══════════════════════════════════════════════════════════════"
echo "Perfil $PROFILE_1: $RESULT_1 trails con KMS encryption"
echo "Perfil $PROFILE_2: $RESULT_2 trails con KMS encryption"
TOTAL_ENCRYPTED=$((RESULT_1 + RESULT_2))
echo "Total trails encriptados: $TOTAL_ENCRYPTED"

if [ "$TOTAL_ENCRYPTED" -gt 0 ]; then
    echo "✅ ÉXITO: KMS encryption configurado en $TOTAL_ENCRYPTED trails"
    echo "🔒 CloudTrail logs ahora están protegidos con cifrado at-rest"
else
    echo "⚠️ PARCIAL: Algunos trails pueden requerir configuración manual adicional"
fi

# Cleanup
rm -f /tmp/enhanced-kms-policy-*.json

echo
echo "✅ PROCESO DE REPARACIÓN COMPLETADO"
echo "═══════════════════════════════════════════════════════════════"