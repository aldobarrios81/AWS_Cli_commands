#!/bin/bash

# Comprehensive CloudTrail KMS Status Report - All Profiles
# Reports on azbeacons, ancla, and azcenit profiles

PROFILES=("azbeacons" "ancla" "azcenit")
REGION="us-east-1"

echo "🔍 REPORTE COMPLETO DE KMS ENCRYPTION - CLOUDTRAIL"
echo "═══════════════════════════════════════════════════════════════"
echo "Perfiles a evaluar: ${PROFILES[@]}"
echo "Región: $REGION"
echo "Fecha: $(date)"
echo

# Function to check profile status
check_profile_status() {
    local PROFILE=$1
    
    echo "🔍 PERFIL: $PROFILE"
    echo "────────────────────────────────────────────────────────────────"
    
    # Check if profile is accessible
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
    if [ -z "$ACCOUNT_ID" ] || [ "$ACCOUNT_ID" = "None" ]; then
        echo "❌ Perfil no accesible o no configurado"
        return 1
    fi
    
    echo "✔ Account ID: $ACCOUNT_ID"
    
    # Check KMS key
    KMS_KEY_ARN=$(aws kms describe-key --key-id alias/cloudtrail-key --profile "$PROFILE" --region "$REGION" --query KeyMetadata.Arn --output text 2>/dev/null)
    if [ -z "$KMS_KEY_ARN" ] || [ "$KMS_KEY_ARN" = "None" ]; then
        echo "❌ KMS Key no encontrada (alias/cloudtrail-key)"
        KMS_AVAILABLE=false
    else
        echo "✔ KMS Key: $KMS_KEY_ARN"
        KMS_AVAILABLE=true
    fi
    
    # Get all trails
    TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[*].Name' --output text 2>/dev/null)
    
    if [ -z "$TRAILS" ]; then
        echo "⚠️ No se encontraron CloudTrails"
        echo "📊 Resumen $PROFILE: 0 trails, KMS: $([ "$KMS_AVAILABLE" = true ] && echo "Disponible" || echo "No disponible")"
        echo
        return 1
    fi
    
    TRAIL_COUNT=$(echo "$TRAILS" | wc -w)
    echo "📋 Trails encontrados ($TRAIL_COUNT): $TRAILS"
    echo
    
    # Check each trail
    local ACTIVE_LOGGING=0
    local WITH_KMS=0
    
    for TRAIL in $TRAILS; do
        echo "🛤️ Trail: $TRAIL"
        
        # Check logging status
        LOGGING_STATUS=$(aws cloudtrail get-trail-status --name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text 2>/dev/null)
        
        # Check KMS configuration
        TRAIL_KMS=$(aws cloudtrail describe-trails --trail-name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text 2>/dev/null)
        
        # Get S3 bucket
        S3_BUCKET=$(aws cloudtrail describe-trails --trail-name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'trailList[0].S3BucketName' --output text 2>/dev/null)
        
        echo "   📝 Logging: $([ "$LOGGING_STATUS" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
        echo "   🔐 KMS: $([ "$TRAIL_KMS" != "None" ] && [ -n "$TRAIL_KMS" ] && echo "✅ CONFIGURADO ($TRAIL_KMS)" || echo "❌ NO CONFIGURADO")"
        echo "   📦 S3 Bucket: $S3_BUCKET"
        
        # Count status
        [ "$LOGGING_STATUS" = "true" ] && ACTIVE_LOGGING=$((ACTIVE_LOGGING + 1))
        [ "$TRAIL_KMS" != "None" ] && [ -n "$TRAIL_KMS" ] && WITH_KMS=$((WITH_KMS + 1))
        
        echo
    done
    
    # Summary for this profile
    echo "📊 RESUMEN $PROFILE:"
    echo "   Total trails: $TRAIL_COUNT"
    echo "   Logging activo: $ACTIVE_LOGGING/$TRAIL_COUNT ($([ $TRAIL_COUNT -gt 0 ] && echo "$((ACTIVE_LOGGING * 100 / TRAIL_COUNT))" || echo "0")%)"
    echo "   KMS encryption: $WITH_KMS/$TRAIL_COUNT ($([ $TRAIL_COUNT -gt 0 ] && echo "$((WITH_KMS * 100 / TRAIL_COUNT))" || echo "0")%)"
    echo "   KMS Key disponible: $([ "$KMS_AVAILABLE" = true ] && echo "✅ SÍ" || echo "❌ NO")"
    
    # Status evaluation
    if [ "$ACTIVE_LOGGING" -eq "$TRAIL_COUNT" ] && [ "$WITH_KMS" -eq "$TRAIL_COUNT" ]; then
        echo "   🎯 Estado: 🏆 PERFECTO (Logging + KMS)"
    elif [ "$ACTIVE_LOGGING" -eq "$TRAIL_COUNT" ]; then
        echo "   🎯 Estado: ✅ MUY BUENO (Logging completo, KMS pendiente)"
    elif [ "$ACTIVE_LOGGING" -gt 0 ]; then
        echo "   🎯 Estado: ⚠️ PARCIAL (Algunos trails funcionando)"
    else
        echo "   🎯 Estado: ❌ CRÍTICO (Sin logging activo)"
    fi
    
    echo
    return 0
}

# Process each profile
TOTAL_PROFILES=0
ACCESSIBLE_PROFILES=0
FUNCTIONAL_PROFILES=0
PERFECT_PROFILES=0

echo "🚀 PROCESANDO PERFILES..."
echo

for PROFILE in "${PROFILES[@]}"; do
    TOTAL_PROFILES=$((TOTAL_PROFILES + 1))
    
    if check_profile_status "$PROFILE"; then
        ACCESSIBLE_PROFILES=$((ACCESSIBLE_PROFILES + 1))
        
        # Check if functional (has active logging)
        TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[*].Name' --output text 2>/dev/null)
        ACTIVE_COUNT=0
        KMS_COUNT=0
        
        for TRAIL in $TRAILS; do
            LOGGING=$(aws cloudtrail get-trail-status --name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text 2>/dev/null)
            TRAIL_KMS=$(aws cloudtrail describe-trails --trail-name "$TRAIL" --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text 2>/dev/null)
            
            [ "$LOGGING" = "true" ] && ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
            [ "$TRAIL_KMS" != "None" ] && [ -n "$TRAIL_KMS" ] && KMS_COUNT=$((KMS_COUNT + 1))
        done
        
        if [ "$ACTIVE_COUNT" -gt 0 ]; then
            FUNCTIONAL_PROFILES=$((FUNCTIONAL_PROFILES + 1))
        fi
        
        if [ "$ACTIVE_COUNT" -gt 0 ] && [ "$KMS_COUNT" -eq "$ACTIVE_COUNT" ]; then
            PERFECT_PROFILES=$((PERFECT_PROFILES + 1))
        fi
    fi
    
    echo "═══════════════════════════════════════════════════════════════"
done

# Global summary
echo
echo "🎯 RESUMEN GENERAL DE TODOS LOS PERFILES"
echo "═══════════════════════════════════════════════════════════════"
echo "📊 Perfiles totales: $TOTAL_PROFILES"
echo "🔍 Perfiles accesibles: $ACCESSIBLE_PROFILES"
echo "✅ Perfiles funcionales (con logging): $FUNCTIONAL_PROFILES"
echo "🏆 Perfiles perfectos (logging + KMS): $PERFECT_PROFILES"

echo
echo "📈 MÉTRICAS GENERALES:"
echo "────────────────────────────────────────────────────────────────"
ACCESSIBILITY_PERCENT=$([ $TOTAL_PROFILES -gt 0 ] && echo "$((ACCESSIBLE_PROFILES * 100 / TOTAL_PROFILES))" || echo "0")
FUNCTIONALITY_PERCENT=$([ $ACCESSIBLE_PROFILES -gt 0 ] && echo "$((FUNCTIONAL_PROFILES * 100 / ACCESSIBLE_PROFILES))" || echo "0")
PERFECTION_PERCENT=$([ $FUNCTIONAL_PROFILES -gt 0 ] && echo "$((PERFECT_PROFILES * 100 / FUNCTIONAL_PROFILES))" || echo "0")

echo "🔗 Conectividad: $ACCESSIBILITY_PERCENT%"
echo "📝 Funcionalidad CloudTrail: $FUNCTIONALITY_PERCENT%"
echo "🔐 Completitud KMS: $PERFECTION_PERCENT%"

echo
echo "🎖️ EVALUACIÓN FINAL:"
echo "────────────────────────────────────────────────────────────────"

if [ "$PERFECT_PROFILES" -eq "$FUNCTIONAL_PROFILES" ] && [ "$FUNCTIONAL_PROFILES" -gt 0 ]; then
    echo "🏆 EXCELENTE: Todos los perfiles funcionales tienen KMS completo"
elif [ "$FUNCTIONAL_PROFILES" -eq "$ACCESSIBLE_PROFILES" ] && [ "$ACCESSIBLE_PROFILES" -gt 0 ]; then
    echo "✅ MUY BUENO: Todos los perfiles tienen CloudTrail funcionando"
    echo "🔐 PENDIENTE: KMS encryption en $(( FUNCTIONAL_PROFILES - PERFECT_PROFILES )) perfiles"
elif [ "$FUNCTIONAL_PROFILES" -gt 0 ]; then
    echo "⚠️ PARCIAL: Algunos perfiles funcionando, otros necesitan atención"
else
    echo "❌ CRÍTICO: Ningún perfil tiene CloudTrail funcionando"
fi

echo
echo "💡 RECOMENDACIONES ESPECÍFICAS:"
echo "────────────────────────────────────────────────────────────────"

if [ "$PERFECT_PROFILES" -lt "$FUNCTIONAL_PROFILES" ]; then
    echo "🔐 KMS Encryption pendiente en $(( FUNCTIONAL_PROFILES - PERFECT_PROFILES )) perfiles"
    echo "   • Las KMS keys están disponibles"
    echo "   • CloudTrail está funcionando correctamente"
    echo "   • KMS encryption es opcional pero recomendado para compliance avanzado"
fi

if [ "$FUNCTIONAL_PROFILES" -lt "$ACCESSIBLE_PROFILES" ]; then
    echo "📝 CloudTrail logging necesita atención en $(( ACCESSIBLE_PROFILES - FUNCTIONAL_PROFILES )) perfiles"
fi

if [ "$ACCESSIBLE_PROFILES" -lt "$TOTAL_PROFILES" ]; then
    echo "🔗 Verificar conectividad/configuración en $(( TOTAL_PROFILES - ACCESSIBLE_PROFILES )) perfiles"
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "              🎯 REPORTE COMPLETO FINALIZADO"
echo "═══════════════════════════════════════════════════════════════"