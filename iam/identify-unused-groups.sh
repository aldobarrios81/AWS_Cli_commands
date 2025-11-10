#!/bin/bash
# Identificar grupos IAM sin uso para AZLOGICA

PROFILE="AZLOGICA"
echo "🔍 Identificando grupos IAM sin uso para perfil: $PROFILE"
echo "=============================================="

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
echo "✅ Account ID: $ACCOUNT_ID"
echo ""

# Crear archivo temporal para resultados
TEMP_FILE="/tmp/group_analysis_$$"
> "$TEMP_FILE"

echo "📋 Analizando cada grupo..."
echo ""

# Obtener y procesar grupos
aws iam list-groups --profile "$PROFILE" --query 'Groups[*].GroupName' --output text | tr '\t' '\n' | while read -r GROUP_NAME; do
    if [ -z "$GROUP_NAME" ]; then
        continue
    fi
    
    echo "🔎 Grupo: $GROUP_NAME"
    
    # Verificar usuarios
    USER_COUNT=$(aws iam get-group --group-name "$GROUP_NAME" --profile "$PROFILE" --query 'Users | length(@)' --output text 2>/dev/null)
    
    if [ "$USER_COUNT" = "0" ]; then
        # Verificar políticas
        INLINE_COUNT=$(aws iam list-group-policies --group-name "$GROUP_NAME" --profile "$PROFILE" --query 'PolicyNames | length(@)' --output text 2>/dev/null)
        MANAGED_COUNT=$(aws iam list-attached-group-policies --group-name "$GROUP_NAME" --profile "$PROFILE" --query 'AttachedPolicies | length(@)' --output text 2>/dev/null)
        
        if [ "$INLINE_COUNT" = "0" ] && [ "$MANAGED_COUNT" = "0" ]; then
            echo "  ❌ SIN USUARIOS NI POLÍTICAS - Candidato para eliminación"
            echo "$GROUP_NAME" >> "$TEMP_FILE"
        else
            echo "  📜 Sin usuarios pero con políticas ($INLINE_COUNT inline, $MANAGED_COUNT managed)"
        fi
    else
        echo "  👥 Con $USER_COUNT usuario(s) - En uso"
    fi
    echo ""
done

echo "=============================================="
echo "📊 RESULTADOS:"

if [ -s "$TEMP_FILE" ]; then
    echo "🗑️  GRUPOS SIN USO ENCONTRADOS:"
    cat "$TEMP_FILE" | sed 's/^/  • /'
    echo ""
    echo "📝 Total de grupos sin uso: $(wc -l < "$TEMP_FILE")"
    
    # Guardar reporte
    REPORT="unused-groups-report-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "GRUPOS IAM SIN USO - AZLOGICA"
        echo "Fecha: $(date)"
        echo "Account: $ACCOUNT_ID"
        echo "========================="
        cat "$TEMP_FILE"
    } > "$REPORT"
    echo "📄 Reporte guardado: $REPORT"
else
    echo "✅ No se encontraron grupos sin uso"
fi

# Limpiar
rm -f "$TEMP_FILE"
echo ""
echo "🎯 Análisis completado (SOLO IDENTIFICACIÓN - NO SE ELIMINÓ NADA)"
