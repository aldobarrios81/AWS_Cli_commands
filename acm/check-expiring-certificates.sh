#!/bin/bash
# check-expiring-certificates.sh
# Verifica certificados ACM que expiran pronto o ya han expirado

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
DAYS_WARNING=30  # Días para considerar "expirando pronto"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo "🔒 VERIFICACIÓN CERTIFICADOS ACM - EXPIRACIÓN"
echo "=================================================================="
echo "Perfil: $PROFILE"
echo "Días de alerta: $DAYS_WARNING días"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

echo "✅ Account ID: $ACCOUNT_ID"
echo ""

# Regiones principales para certificados
REGIONS=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")
ACTIVE_REGIONS=()

# Contadores
TOTAL_CERTIFICATES=0
EXPIRED_CERTIFICATES=0
EXPIRING_SOON=0
VALID_CERTIFICATES=0

# Archivo temporal para resultados
TEMP_FILE="/tmp/acm_certificates_$PROFILE"
> "$TEMP_FILE"

echo "🌍 Escaneando regiones para certificados ACM..."

for region in "${REGIONS[@]}"; do
    CERT_COUNT=$(aws acm list-certificates --profile "$PROFILE" --region "$region" --query 'length(CertificateSummaryList)' --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$CERT_COUNT" ] && [ "$CERT_COUNT" -gt 0 ]; then
        echo "✅ $region: $CERT_COUNT certificados encontrados"
        ACTIVE_REGIONS+=("$region")
        TOTAL_CERTIFICATES=$((TOTAL_CERTIFICATES + CERT_COUNT))
    else
        echo "ℹ️ $region: Sin certificados"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo ""
    echo "🎉 No se encontraron certificados ACM en ninguna región"
    exit 0
fi

echo ""
echo "📋 Analizando $TOTAL_CERTIFICATES certificados en ${#ACTIVE_REGIONS[@]} regiones..."
echo ""

# Función para obtener días hasta expiración
get_days_until_expiry() {
    local expiry_date="$1"
    local current_timestamp=$(date +%s)
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local diff_seconds=$((expiry_timestamp - current_timestamp))
        local days=$((diff_seconds / 86400))
        echo $days
    else
        echo "ERROR"
    fi
}

# Procesar certificados por región
for region in "${ACTIVE_REGIONS[@]}"; do
    echo "🔍 Región: $region"
    
    # Obtener lista de certificados
    CERTIFICATES=$(aws acm list-certificates \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'CertificateSummaryList[].{Arn:CertificateArn,Domain:DomainName}' \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$CERTIFICATES" = "[]" ]; then
        echo "   ⚠️ Error al obtener certificados"
        continue
    fi
    
    # Procesar cada certificado
    echo "$CERTIFICATES" | jq -r '.[] | @base64' | while IFS= read -r cert_data; do
        CERT_INFO=$(echo "$cert_data" | base64 -d)
        CERT_ARN=$(echo "$CERT_INFO" | jq -r '.Arn')
        DOMAIN_NAME=$(echo "$CERT_INFO" | jq -r '.Domain')
        
        # Obtener detalles del certificado
        CERT_DETAILS=$(aws acm describe-certificate \
            --certificate-arn "$CERT_ARN" \
            --profile "$PROFILE" \
            --region "$region" \
            --query '[Status,NotAfter,Issuer,KeyAlgorithm,InUseBy]' \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$CERT_DETAILS" ]; then
            IFS=$'\t' read -r STATUS NOT_AFTER ISSUER KEY_ALGORITHM IN_USE_BY <<< "$CERT_DETAILS"
            
            # Calcular días hasta expiración
            DAYS_UNTIL_EXPIRY=$(get_days_until_expiry "$NOT_AFTER")
            
            # Determinar estado
            if [ "$DAYS_UNTIL_EXPIRY" = "ERROR" ]; then
                STATUS_COLOR="$RED"
                STATUS_TEXT="ERROR EN FECHA"
                CATEGORY="ERROR"
            elif [ "$DAYS_UNTIL_EXPIRY" -lt 0 ]; then
                STATUS_COLOR="$RED"
                STATUS_TEXT="EXPIRADO (hace $((DAYS_UNTIL_EXPIRY * -1)) días)"
                CATEGORY="EXPIRED"
                EXPIRED_CERTIFICATES=$((EXPIRED_CERTIFICATES + 1))
            elif [ "$DAYS_UNTIL_EXPIRY" -le "$DAYS_WARNING" ]; then
                STATUS_COLOR="$YELLOW"
                STATUS_TEXT="EXPIRA PRONTO (en $DAYS_UNTIL_EXPIRY días)"
                CATEGORY="EXPIRING"
                EXPIRING_SOON=$((EXPIRING_SOON + 1))
            else
                STATUS_COLOR="$GREEN"
                STATUS_TEXT="VÁLIDO (expira en $DAYS_UNTIL_EXPIRY días)"
                CATEGORY="VALID"
                VALID_CERTIFICATES=$((VALID_CERTIFICATES + 1))
            fi
            
            # Verificar si está en uso
            if [ -n "$IN_USE_BY" ] && [ "$IN_USE_BY" != "None" ]; then
                IN_USE_COUNT=$(echo "$IN_USE_BY" | wc -w)
                USAGE_TEXT="En uso por $IN_USE_COUNT recurso(s)"
            else
                USAGE_TEXT="No está en uso"
            fi
            
            echo "   🔒 $DOMAIN_NAME"
            echo -e "      Estado: ${STATUS_COLOR}$STATUS_TEXT${NC}"
            echo "      Uso: $USAGE_TEXT"
            echo "      Emisor: $ISSUER"
            echo "      Algoritmo: $KEY_ALGORITHM"
            echo "      Región: $region"
            
            # Guardar en archivo temporal para reporte
            echo "$CATEGORY|$DOMAIN_NAME|$DAYS_UNTIL_EXPIRY|$NOT_AFTER|$USAGE_TEXT|$ISSUER|$region" >> "$TEMP_FILE"
            
            echo ""
        fi
    done
    
    echo ""
done

# Generar resumen
echo "=================================================================="
echo "📊 RESUMEN DE CERTIFICADOS ACM - ${PROFILE^^}"
echo "=================================================================="
echo "📈 Total de certificados: $TOTAL_CERTIFICATES"

if [ $EXPIRED_CERTIFICATES -gt 0 ]; then
    echo -e "🔴 Certificados expirados: ${RED}$EXPIRED_CERTIFICATES${NC}"
fi

if [ $EXPIRING_SOON -gt 0 ]; then
    echo -e "🟡 Expiran pronto ($DAYS_WARNING días): ${YELLOW}$EXPIRING_SOON${NC}"
fi

echo -e "🟢 Certificados válidos: ${GREEN}$VALID_CERTIFICATES${NC}"

echo ""

# Mostrar certificados críticos
if [ $EXPIRED_CERTIFICATES -gt 0 ] || [ $EXPIRING_SOON -gt 0 ]; then
    echo "🚨 CERTIFICADOS QUE REQUIEREN ATENCIÓN:"
    echo "======================================"
    
    if [ -f "$TEMP_FILE" ]; then
        # Mostrar expirados
        EXPIRED_LIST=$(grep "^EXPIRED" "$TEMP_FILE")
        if [ -n "$EXPIRED_LIST" ]; then
            echo ""
            echo -e "${RED}�� CERTIFICADOS EXPIRADOS:${NC}"
            echo "$EXPIRED_LIST" | while IFS='|' read -r category domain days date usage issuer region; do
                echo -e "   • ${RED}$domain${NC} (región: $region)"
                echo "     Expiró: $date"
                echo "     $usage"
                echo ""
            done
        fi
        
        # Mostrar que expiran pronto
        EXPIRING_LIST=$(grep "^EXPIRING" "$TEMP_FILE")
        if [ -n "$EXPIRING_LIST" ]; then
            echo ""
            echo -e "${YELLOW}🟡 CERTIFICADOS QUE EXPIRAN PRONTO:${NC}"
            echo "$EXPIRING_LIST" | while IFS='|' read -r category domain days date usage issuer region; do
                echo -e "   • ${YELLOW}$domain${NC} (región: $region)"
                echo "     Expira en: $days días ($date)"
                echo "     $usage"
                echo ""
            done
        fi
    fi
    
    echo ""
    echo "🔧 ACCIONES RECOMENDADAS:"
    echo "========================"
    echo "1. Renovar certificados expirados inmediatamente"
    echo "2. Planificar renovación de certificados que expiran pronto"
    echo "3. Configurar alertas automáticas de expiración"
    echo "4. Considerar certificados auto-renovables"
    
else
    echo "🎉 ¡Excelente! Todos los certificados están válidos y no expiran pronto"
fi

# Generar reporte JSON
REPORT_FILE="acm-certificates-report-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$REPORT_FILE" << EOF
{
    "report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "profile": "$PROFILE",
        "account_id": "$ACCOUNT_ID",
        "warning_days": $DAYS_WARNING
    },
    "summary": {
        "total_certificates": $TOTAL_CERTIFICATES,
        "expired_certificates": $EXPIRED_CERTIFICATES,
        "expiring_soon": $EXPIRING_SOON,
        "valid_certificates": $VALID_CERTIFICATES,
        "regions_scanned": $(echo "${ACTIVE_REGIONS[@]}" | wc -w)
    },
    "status": {
        "requires_immediate_action": $([ $EXPIRED_CERTIFICATES -gt 0 ] && echo "true" || echo "false"),
        "requires_planning": $([ $EXPIRING_SOON -gt 0 ] && echo "true" || echo "false"),
        "all_certificates_healthy": $([ $EXPIRED_CERTIFICATES -eq 0 ] && [ $EXPIRING_SOON -eq 0 ] && echo "true" || echo "false")
    }
}
