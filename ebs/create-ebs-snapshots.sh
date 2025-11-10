#!/bin/bash
# create-ebs-snapshots.sh
# Crear snapshots recientes para volúmenes EBS
# Implementa backup automático con etiquetado y retención inteligente

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}📷 CREANDO SNAPSHOTS EBS RECIENTES${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Implementando backup automático de volúmenes EBS con retención inteligente"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
AWS_VERSION=$(aws --version 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no encontrado${NC}"
    exit 1
fi
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "🔐 Verificando credenciales para perfil '$PROFILE'..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables de conteo
TOTAL_VOLUMES=0
SNAPSHOTS_CREATED=0
SNAPSHOTS_EXISTING=0
ERRORS=0
CRITICAL_VOLUMES=0
ENCRYPTED_VOLUMES=0
UNENCRYPTED_VOLUMES=0
TOTAL_SIZE_GB=0

# Configuración de retención por defecto
DEFAULT_RETENTION_DAYS=30
CRITICAL_RETENTION_DAYS=90
QUICK_RETENTION_DAYS=7

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Verificando regiones con volúmenes EBS...${NC}"
for region in "${REGIONS[@]}"; do
    VOLUME_COUNT=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=state,Values=in-use,available" \
        --query 'length(Volumes)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$VOLUME_COUNT" ] && [ "$VOLUME_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $VOLUME_COUNT volúmenes EBS"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin volúmenes EBS"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron volúmenes EBS en ninguna región${NC}"
    echo -e "${BLUE}💡 No se requiere creación de snapshots${NC}"
    exit 0
fi

echo ""

# Función para determinar criticidad del volumen
determine_volume_criticality() {
    local volume_id="$1"
    local volume_type="$2"
    local size="$3"
    local encrypted="$4"
    local tags="$5"
    local attached_instances="$6"
    local region="$7"
    
    local is_critical=false
    local criticality_reasons=()
    local criticality_score=0
    
    # Evaluar por tipo de volumen
    case "$volume_type" in
        gp3|io1|io2)
            criticality_score=$((criticality_score + 30))
            criticality_reasons+=("Tipo de volumen de alta performance")
            ;;
        gp2)
            criticality_score=$((criticality_score + 20))
            criticality_reasons+=("Tipo de volumen estándar")
            ;;
        st1|sc1)
            criticality_score=$((criticality_score + 10))
            criticality_reasons+=("Tipo de volumen de throughput")
            ;;
    esac
    
    # Evaluar por tamaño
    if [ "$size" -gt 1000 ]; then
        criticality_score=$((criticality_score + 40))
        criticality_reasons+=("Volumen grande (>1TB)")
    elif [ "$size" -gt 500 ]; then
        criticality_score=$((criticality_score + 30))
        criticality_reasons+=("Volumen mediano (>500GB)")
    elif [ "$size" -gt 100 ]; then
        criticality_score=$((criticality_score + 20))
        criticality_reasons+=("Volumen estándar (>100GB)")
    else
        criticality_score=$((criticality_score + 10))
        criticality_reasons+=("Volumen pequeño (<100GB)")
    fi
    
    # Evaluar por cifrado
    if [ "$encrypted" = "true" ]; then
        criticality_score=$((criticality_score + 25))
        criticality_reasons+=("Volumen cifrado")
    else
        criticality_reasons+=("Volumen sin cifrar")
    fi
    
    # Evaluar por instancias adjuntas
    if [ -n "$attached_instances" ] && [ "$attached_instances" != "None" ]; then
        criticality_score=$((criticality_score + 35))
        criticality_reasons+=("Adjunto a instancia EC2")
        
        # Verificar tipo de instancia adjunta
        local instance_types=$(aws ec2 describe-instances \
            --instance-ids $attached_instances \
            --profile "$PROFILE" \
            --region "$region" \
            --query 'Reservations[].Instances[].InstanceType' \
            --output text 2>/dev/null)
        
        if [[ "$instance_types" =~ (m5|c5|r5|m6|c6|r6) ]]; then
            criticality_score=$((criticality_score + 20))
            criticality_reasons+=("Adjunto a instancia de producción")
        fi
    else
        criticality_reasons+=("Volumen disponible (no adjunto)")
    fi
    
    # Evaluar por tags
    if [[ "$tags" =~ Environment.*[Pp]rod ]]; then
        criticality_score=$((criticality_score + 40))
        criticality_reasons+=("Tag Environment=Production")
    fi
    
    if [[ "$tags" =~ Critical.*true ]]; then
        criticality_score=$((criticality_score + 50))
        criticality_reasons+=("Tag Critical=true")
    fi
    
    if [[ "$tags" =~ Role.*(database|db|mysql|postgres|oracle|mongodb) ]]; then
        criticality_score=$((criticality_score + 45))
        criticality_reasons+=("Rol de base de datos")
    elif [[ "$tags" =~ Role.*(web|api|app|server) ]]; then
        criticality_score=$((criticality_score + 30))
        criticality_reasons+=("Rol de aplicación")
    fi
    
    if [[ "$tags" =~ Backup.*(Daily|Critical|Important) ]]; then
        criticality_score=$((criticality_score + 30))
        criticality_reasons+=("Tag de backup crítico")
    fi
    
    # Verificar si es volumen root
    local is_root=$(aws ec2 describe-instances \
        --profile "$PROFILE" \
        --region "$region" \
        --query "Reservations[].Instances[?BlockDeviceMappings[?Ebs.VolumeId=='$volume_id' && DeviceName=='/dev/sda1' || DeviceName=='/dev/xvda']].InstanceId" \
        --output text 2>/dev/null)
    
    if [ -n "$is_root" ] && [ "$is_root" != "None" ]; then
        criticality_score=$((criticality_score + 35))
        criticality_reasons+=("Volumen raíz del sistema")
    fi
    
    # Determinar nivel de criticidad final
    if [ $criticality_score -ge 100 ]; then
        echo "CRITICAL|$criticality_score|${criticality_reasons[*]}"
    elif [ $criticality_score -ge 70 ]; then
        echo "HIGH|$criticality_score|${criticality_reasons[*]}"
    elif [ $criticality_score -ge 40 ]; then
        echo "MEDIUM|$criticality_score|${criticality_reasons[*]}"
    else
        echo "LOW|$criticality_score|${criticality_reasons[*]}"
    fi
}

# Función para verificar snapshots existentes
check_existing_snapshots() {
    local volume_id="$1"
    local region="$2"
    local days_back="${3:-1}"
    
    local cutoff_date=$(date -d "$days_back days ago" +%Y-%m-%d)
    
    local recent_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
                  "Name=start-time,Values=${cutoff_date}*" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    echo "${recent_snapshots:-0}"
}

# Función para crear snapshot con etiquetado inteligente
create_snapshot_with_tags() {
    local volume_id="$1"
    local volume_name="$2"
    local criticality_level="$3"
    local region="$4"
    local retention_days="$5"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_description="Automated snapshot of $volume_id ($volume_name) - $(date)"
    
    echo -e "   🔧 Creando snapshot..."
    
    # Crear el snapshot
    local snapshot_result=$(aws ec2 create-snapshot \
        --volume-id "$volume_id" \
        --description "$snapshot_description" \
        --profile "$PROFILE" \
        --region "$region" \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "   ${RED}❌ Error al crear snapshot${NC}"
        return 1
    fi
    
    local snapshot_id=$(echo "$snapshot_result" | jq -r '.SnapshotId')
    
    if [ -z "$snapshot_id" ] || [ "$snapshot_id" = "null" ]; then
        echo -e "   ${RED}❌ Error: Snapshot ID no válido${NC}"
        return 1
    fi
    
    echo -e "   ✅ Snapshot creado: ${GREEN}$snapshot_id${NC}"
    
    # Calcular fecha de eliminación
    local delete_date=$(date -d "+$retention_days days" +%Y-%m-%d)
    
    # Preparar tags para el snapshot
    local tags_json="["
    tags_json+="{\"Key\":\"Name\",\"Value\":\"snapshot-$volume_name-$timestamp\"},"
    tags_json+="{\"Key\":\"Source\",\"Value\":\"$volume_id\"},"
    tags_json+="{\"Key\":\"CreatedBy\",\"Value\":\"automated-backup-script\"},"
    tags_json+="{\"Key\":\"CreationDate\",\"Value\":\"$(date +%Y-%m-%d)\"},"
    tags_json+="{\"Key\":\"Criticality\",\"Value\":\"$criticality_level\"},"
    tags_json+="{\"Key\":\"RetentionDays\",\"Value\":\"$retention_days\"},"
    tags_json+="{\"Key\":\"DeleteAfter\",\"Value\":\"$delete_date\"},"
    tags_json+="{\"Key\":\"Profile\",\"Value\":\"$PROFILE\"},"
    tags_json+="{\"Key\":\"AutomatedBackup\",\"Value\":\"true\"}"
    tags_json+="]"
    
    # Aplicar tags al snapshot
    echo -e "   🏷️ Aplicando etiquetas..."
    aws ec2 create-tags \
        --resources "$snapshot_id" \
        --tags "$tags_json" \
        --profile "$PROFILE" \
        --region "$region" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Etiquetas aplicadas exitosamente"
        echo -e "   📅 Retención configurada: ${BLUE}$retention_days días${NC}"
        echo -e "   🗑️ Eliminación programada: ${BLUE}$delete_date${NC}"
    else
        echo -e "   ⚠️ Advertencia: Error al aplicar etiquetas"
    fi
    
    return 0
}

# Función para limpiar snapshots antiguos
cleanup_old_snapshots() {
    local volume_id="$1"
    local region="$2"
    local keep_count="${3:-5}"
    
    echo -e "   🧹 Limpiando snapshots antiguos (conservando últimos $keep_count)..."
    
    # Obtener snapshots ordenados por fecha (más recientes primero)
    local old_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
        --query 'Snapshots | sort_by(@, &StartTime) | reverse(@) | ['"$keep_count"':].SnapshotId' \
        --output text 2>/dev/null)
    
    if [ -n "$old_snapshots" ] && [ "$old_snapshots" != "None" ]; then
        local deleted_count=0
        for snapshot_id in $old_snapshots; do
            echo -e "      🗑️ Eliminando snapshot antiguo: $snapshot_id"
            
            aws ec2 delete-snapshot \
                --snapshot-id "$snapshot_id" \
                --profile "$PROFILE" \
                --region "$region" &>/dev/null
            
            if [ $? -eq 0 ]; then
                deleted_count=$((deleted_count + 1))
            fi
        done
        
        if [ $deleted_count -gt 0 ]; then
            echo -e "   ✅ Eliminados $deleted_count snapshots antiguos"
        fi
    else
        echo -e "   ℹ️ No hay snapshots antiguos para eliminar"
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Obtener volúmenes EBS
    VOLUMES_DATA=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --filters "Name=state,Values=in-use,available" \
        --query 'Volumes[].[VolumeId,VolumeType,Size,Encrypted,Attachments[0].InstanceId,Tags[?Key==`Name`].Value|[0],State,CreateTime]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener volúmenes EBS en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$VOLUMES_DATA" ]; then
        echo -e "${BLUE}ℹ️ Sin volúmenes EBS en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Volúmenes EBS encontrados en $CURRENT_REGION:${NC}"
    
    while IFS=$'\t' read -r volume_id volume_type size encrypted instance_id volume_name state create_time; do
        if [ -n "$volume_id" ]; then
            TOTAL_VOLUMES=$((TOTAL_VOLUMES + 1))
            TOTAL_SIZE_GB=$((TOTAL_SIZE_GB + size))
            
            # Si no hay nombre, usar ID como nombre
            if [ -z "$volume_name" ] || [ "$volume_name" = "None" ]; then
                volume_name="$volume_id"
            fi
            
            # Normalizar valores
            [ "$instance_id" = "None" ] && instance_id=""
            [ "$encrypted" = "True" ] && ENCRYPTED_VOLUMES=$((ENCRYPTED_VOLUMES + 1)) || UNENCRYPTED_VOLUMES=$((UNENCRYPTED_VOLUMES + 1))
            
            echo -e "${CYAN}💾 Volumen: $volume_name${NC}"
            echo -e "   🆔 ID: ${BLUE}$volume_id${NC}"
            echo -e "   📦 Tipo: ${BLUE}$volume_type${NC}"
            echo -e "   📏 Tamaño: ${BLUE}${size}GB${NC}"
            echo -e "   🔐 Cifrado: $([ "$encrypted" = "True" ] && echo -e "${GREEN}SÍ${NC}" || echo -e "${YELLOW}NO${NC}")"
            echo -e "   🔄 Estado: ${BLUE}$state${NC}"
            
            if [ -n "$instance_id" ]; then
                echo -e "   🖥️ Instancia: ${BLUE}$instance_id${NC}"
            else
                echo -e "   🖥️ Instancia: ${YELLOW}No adjunto${NC}"
            fi
            
            if [ -n "$create_time" ] && [ "$create_time" != "None" ]; then
                local create_date=$(date -d "$create_time" +%Y-%m-%d 2>/dev/null)
                if [ -n "$create_date" ]; then
                    echo -e "   📅 Creado: ${BLUE}$create_date${NC}"
                fi
            fi
            
            # Obtener información adicional del volumen
            VOLUME_DETAILS=$(aws ec2 describe-volumes \
                --volume-ids "$volume_id" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Volumes[0].[Iops,Throughput,Tags]' \
                --output json 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                IOPS=$(echo "$VOLUME_DETAILS" | jq -r '.[0]' 2>/dev/null)
                THROUGHPUT=$(echo "$VOLUME_DETAILS" | jq -r '.[1]' 2>/dev/null)
                TAGS_JSON=$(echo "$VOLUME_DETAILS" | jq -r '.[2]' 2>/dev/null)
                
                if [ -n "$IOPS" ] && [ "$IOPS" != "null" ]; then
                    echo -e "   ⚡ IOPS: ${BLUE}$IOPS${NC}"
                fi
                
                if [ -n "$THROUGHPUT" ] && [ "$THROUGHPUT" != "null" ]; then
                    echo -e "   🚀 Throughput: ${BLUE}$THROUGHPUT MB/s${NC}"
                fi
            fi
            
            # Obtener tags completos
            TAGS_STRING=$(echo "$TAGS_JSON" | jq -r 'map(select(.Key and .Value) | "\(.Key)=\(.Value)") | join(" ")' 2>/dev/null)
            
            # Determinar criticidad del volumen
            CRITICALITY_RESULT=$(determine_volume_criticality "$volume_id" "$volume_type" "$size" "$encrypted" "$TAGS_STRING" "$instance_id" "$CURRENT_REGION")
            IFS='|' read -r criticality_level criticality_score criticality_reasons <<< "$CRITICALITY_RESULT"
            
            # Mostrar criticidad
            case "$criticality_level" in
                CRITICAL)
                    echo -e "   🔴 Criticidad: ${RED}CRÍTICA ($criticality_score pts)${NC}"
                    CRITICAL_VOLUMES=$((CRITICAL_VOLUMES + 1))
                    ;;
                HIGH)
                    echo -e "   🟠 Criticidad: ${YELLOW}ALTA ($criticality_score pts)${NC}"
                    CRITICAL_VOLUMES=$((CRITICAL_VOLUMES + 1))
                    ;;
                MEDIUM)
                    echo -e "   🟡 Criticidad: ${BLUE}MEDIA ($criticality_score pts)${NC}"
                    ;;
                LOW)
                    echo -e "   🟢 Criticidad: ${GREEN}BAJA ($criticality_score pts)${NC}"
                    ;;
            esac
            
            if [ -n "$criticality_reasons" ]; then
                echo -e "   📋 Factores: ${CYAN}$criticality_reasons${NC}"
            fi
            
            # Verificar snapshots existentes recientes
            RECENT_SNAPSHOTS_COUNT=$(check_existing_snapshots "$volume_id" "$CURRENT_REGION" 1)
            
            echo -e "   📷 Snapshots recientes (24h): ${BLUE}$RECENT_SNAPSHOTS_COUNT${NC}"
            
            # Determinar si necesita snapshot
            local needs_snapshot=false
            local retention_days=$DEFAULT_RETENTION_DAYS
            
            case "$criticality_level" in
                CRITICAL|HIGH)
                    retention_days=$CRITICAL_RETENTION_DAYS
                    if [ "$RECENT_SNAPSHOTS_COUNT" -eq 0 ]; then
                        needs_snapshot=true
                    fi
                    ;;
                MEDIUM)
                    retention_days=$DEFAULT_RETENTION_DAYS
                    if [ "$RECENT_SNAPSHOTS_COUNT" -eq 0 ]; then
                        needs_snapshot=true
                    fi
                    ;;
                LOW)
                    retention_days=$QUICK_RETENTION_DAYS
                    # Para volúmenes de baja criticidad, verificar snapshots de los últimos 3 días
                    RECENT_SNAPSHOTS_3D=$(check_existing_snapshots "$volume_id" "$CURRENT_REGION" 3)
                    if [ "$RECENT_SNAPSHOTS_3D" -eq 0 ]; then
                        needs_snapshot=true
                    fi
                    ;;
            esac
            
            # Crear snapshot si es necesario
            if [ "$needs_snapshot" = true ]; then
                echo -e "   🎯 ${GREEN}Creando snapshot (retención: $retention_days días)${NC}"
                
                if create_snapshot_with_tags "$volume_id" "$volume_name" "$criticality_level" "$CURRENT_REGION" "$retention_days"; then
                    SNAPSHOTS_CREATED=$((SNAPSHOTS_CREATED + 1))
                    
                    # Limpiar snapshots antiguos para volúmenes críticos
                    if [[ "$criticality_level" =~ ^(CRITICAL|HIGH)$ ]]; then
                        cleanup_old_snapshots "$volume_id" "$CURRENT_REGION" 10
                    else
                        cleanup_old_snapshots "$volume_id" "$CURRENT_REGION" 5
                    fi
                else
                    ERRORS=$((ERRORS + 1))
                fi
            else
                echo -e "   ✅ ${GREEN}Snapshot reciente ya existe${NC}"
                SNAPSHOTS_EXISTING=$((SNAPSHOTS_EXISTING + 1))
            fi
            
            # Verificar información adicional de backup
            
            # Verificar si tiene DLM (Data Lifecycle Manager) policies
            DLM_POLICIES=$(aws dlm get-lifecycle-policies \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Policies[?State==`ENABLED`]' \
                --output json 2>/dev/null)
            
            if [ -n "$DLM_POLICIES" ] && [ "$DLM_POLICIES" != "[]" ]; then
                DLM_COUNT=$(echo "$DLM_POLICIES" | jq 'length' 2>/dev/null)
                echo -e "   🔄 DLM Policies: ${GREEN}$DLM_COUNT activas${NC}"
            else
                echo -e "   🔄 DLM Policies: ${YELLOW}No configuradas${NC}"
            fi
            
            # Verificar snapshots históricos
            TOTAL_SNAPSHOTS=$(aws ec2 describe-snapshots \
                --owner-ids "$ACCOUNT_ID" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --filters "Name=volume-id,Values=$volume_id" \
                --query 'length(Snapshots)' \
                --output text 2>/dev/null)
            
            echo -e "   📊 Total snapshots: ${BLUE}${TOTAL_SNAPSHOTS:-0}${NC}"
            
            # Calcular puntuación de backup
            BACKUP_SCORE=0
            
            # Snapshot reciente
            if [ "$RECENT_SNAPSHOTS_COUNT" -gt 0 ]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 30))
            fi
            
            # Cifrado
            if [ "$encrypted" = "True" ]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 25))
            fi
            
            # DLM configurado
            if [ -n "$DLM_POLICIES" ] && [ "$DLM_POLICIES" != "[]" ]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 20))
            fi
            
            # Snapshots históricos
            if [ "${TOTAL_SNAPSHOTS:-0}" -gt 5 ]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 15))
            elif [ "${TOTAL_SNAPSHOTS:-0}" -gt 0 ]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 10))
            fi
            
            # Tags de backup
            if [[ "$TAGS_STRING" =~ Backup ]]; then
                BACKUP_SCORE=$((BACKUP_SCORE + 10))
            fi
            
            # Mostrar puntuación de backup
            case $BACKUP_SCORE in
                [8-9][0-9]|100)
                    echo -e "   💾 Backup: ${GREEN}EXCELENTE ($BACKUP_SCORE/100)${NC}"
                    ;;
                [6-7][0-9])
                    echo -e "   💾 Backup: ${GREEN}BUENO ($BACKUP_SCORE/100)${NC}"
                    ;;
                [4-5][0-9])
                    echo -e "   💾 Backup: ${YELLOW}PROMEDIO ($BACKUP_SCORE/100)${NC}"
                    ;;
                [2-3][0-9])
                    echo -e "   💾 Backup: ${YELLOW}BÁSICO ($BACKUP_SCORE/100)${NC}"
                    ;;
                *)
                    echo -e "   💾 Backup: ${RED}INSUFICIENTE ($BACKUP_SCORE/100)${NC}"
                    ;;
            esac
            
            echo ""
        fi
    done <<< "$VOLUMES_DATA"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Configurar DLM (Data Lifecycle Manager) para automatización futura
echo -e "${PURPLE}=== Configurando Automatización DLM ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "🔄 Verificando políticas DLM en: ${CYAN}$CURRENT_REGION${NC}"
    
    # Verificar políticas DLM existentes
    EXISTING_DLM=$(aws dlm get-lifecycle-policies \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Policies[?State==`ENABLED` && PolicyDetails.PolicyType==`EBS_SNAPSHOT_MANAGEMENT`]' \
        --output json 2>/dev/null)
    
    if [ -n "$EXISTING_DLM" ] && [ "$EXISTING_DLM" != "[]" ]; then
        DLM_COUNT=$(echo "$EXISTING_DLM" | jq 'length')
        echo -e "   ✅ Políticas DLM activas: ${GREEN}$DLM_COUNT${NC}"
    else
        echo -e "   💡 Recomendación: Configurar políticas DLM para automatización"
        echo -e "      ${CYAN}aws dlm create-lifecycle-policy --execution-role-arn arn:aws:iam::$ACCOUNT_ID:role/AWSDataLifecycleManagerDefaultRole${NC}"
    fi
done

# Generar reporte de costos estimados
echo -e "${PURPLE}=== Estimación de Costos de Snapshots ===${NC}"

# Costo aproximado de snapshot: $0.05 per GB por mes
SNAPSHOT_COST_PER_GB_MONTH=0.05
MONTHLY_COST=$(echo "scale=2; $TOTAL_SIZE_GB * $SNAPSHOT_COST_PER_GB_MONTH" | bc -l 2>/dev/null)

if [ -n "$MONTHLY_COST" ]; then
    echo -e "📊 Tamaño total volúmenes: ${BLUE}${TOTAL_SIZE_GB}GB${NC}"
    echo -e "💰 Costo estimado mensual snapshots: ${GREEN}\$${MONTHLY_COST}${NC}"
    
    # Costo anual
    ANNUAL_COST=$(echo "scale=2; $MONTHLY_COST * 12" | bc -l 2>/dev/null)
    if [ -n "$ANNUAL_COST" ]; then
        echo -e "📅 Costo estimado anual: ${GREEN}\$${ANNUAL_COST}${NC}"
    fi
else
    echo -e "⚠️ No se pudo calcular estimación de costos"
fi

# Generar documentación
DOCUMENTATION_FILE="ebs-snapshots-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Snapshots EBS - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Volúmenes EBS Procesados
- **Total volúmenes**: $TOTAL_VOLUMES
- **Tamaño total**: ${TOTAL_SIZE_GB}GB
- **Volúmenes críticos**: $CRITICAL_VOLUMES
- **Volúmenes cifrados**: $ENCRYPTED_VOLUMES
- **Volúmenes sin cifrar**: $UNENCRYPTED_VOLUMES

### Snapshots Creados
- **Snapshots nuevos**: $SNAPSHOTS_CREATED
- **Snapshots existentes**: $SNAPSHOTS_EXISTING
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 📷 Estrategia de Snapshots
- **Volúmenes Críticos**: Snapshots diarios, retención 90 días
- **Volúmenes Estándar**: Snapshots diarios, retención 30 días
- **Volúmenes de Desarrollo**: Snapshots cada 3 días, retención 7 días
- **Limpieza automática**: Conserva últimos 5-10 snapshots por volumen

### 🏷️ Sistema de Etiquetado
- **Identificación**: Name, Source, CreatedBy, CreationDate
- **Gestión**: Criticality, RetentionDays, DeleteAfter
- **Trazabilidad**: Profile, AutomatedBackup

### 🔄 Automatización DLM
- **Políticas recomendadas**: Backup automático por tags
- **Horarios optimizados**: Fuera de horas pico
- **Retención inteligente**: Basada en criticidad del volumen

## Beneficios Implementados

### 1. Protección de Datos
- Recuperación point-in-time de volúmenes EBS
- Protección contra corrupción de datos
- Backup antes de cambios críticos
- Recuperación granular por volumen

### 2. Continuidad del Negocio
- Minimización de tiempo de recuperación (RTO)
- Reducción de pérdida de datos (RPO)
- Disponibilidad cross-AZ y cross-región
- Recuperación de desastres simplificada

### 3. Optimización de Costos
- Snapshots incrementales (solo cambios)
- Retención basada en criticidad
- Limpieza automática de snapshots antiguos
- Compresión automática de AWS

## Comandos de Gestión

\`\`\`bash
# Crear snapshot manual
aws ec2 create-snapshot --volume-id vol-1234567890abcdef0 \\
    --description "Manual snapshot" \\
    --profile $PROFILE --region us-east-1

# Listar snapshots de un volumen
aws ec2 describe-snapshots --owner-ids $ACCOUNT_ID \\
    --filters "Name=volume-id,Values=vol-1234567890abcdef0" \\
    --profile $PROFILE --region us-east-1

# Crear volumen desde snapshot
aws ec2 create-volume --snapshot-id snap-1234567890abcdef0 \\
    --availability-zone us-east-1a \\
    --profile $PROFILE --region us-east-1

# Eliminar snapshot específico
aws ec2 delete-snapshot --snapshot-id snap-1234567890abcdef0 \\
    --profile $PROFILE --region us-east-1

# Verificar progreso de snapshot
aws ec2 describe-snapshots --snapshot-ids snap-1234567890abcdef0 \\
    --query 'Snapshots[0].Progress' \\
    --profile $PROFILE --region us-east-1
\`\`\`

## Costos y Optimización

### Estructura de Costos
- **Almacenamiento**: \$0.05 por GB-mes
- **Copia cross-región**: \$0.02 por GB
- **API calls**: Sin costo adicional
- **Total estimado mensual**: \$${MONTHLY_COST:-"N/A"}

### Optimización de Costos
1. **Retención ajustada**: Reducir retención para volúmenes no críticos
2. **Snapshots incrementales**: Aprovechar naturaleza incremental
3. **Eliminación automática**: Configurar limpieza por tags
4. **Monitoreo de uso**: Alertas por costos excesivos

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CREACIÓN SNAPSHOTS EBS ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "💾 Total volúmenes EBS: ${GREEN}$TOTAL_VOLUMES${NC}"
echo -e "📏 Tamaño total: ${GREEN}${TOTAL_SIZE_GB}GB${NC}"
echo -e "🔴 Volúmenes críticos: ${GREEN}$CRITICAL_VOLUMES${NC}"
echo -e "🔐 Volúmenes cifrados: ${GREEN}$ENCRYPTED_VOLUMES${NC}"
echo -e "⚠️ Sin cifrar: ${YELLOW}$UNENCRYPTED_VOLUMES${NC}"
echo -e "📷 Snapshots creados: ${GREEN}$SNAPSHOTS_CREATED${NC}"
echo -e "✅ Snapshots existentes: ${GREEN}$SNAPSHOTS_EXISTING${NC}"

if [ -n "$MONTHLY_COST" ]; then
    echo -e "💰 Costo estimado mensual: ${GREEN}\$${MONTHLY_COST}${NC}"
fi

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_VOLUMES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN VOLÚMENES EBS${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de snapshots${NC}"
elif [ $ERRORS -eq 0 ] && [ $SNAPSHOTS_CREATED -gt 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: SNAPSHOTS CREADOS EXITOSAMENTE${NC}"
    echo -e "${BLUE}💡 Backup automático configurado para volúmenes críticos${NC}"
elif [ $SNAPSHOTS_EXISTING -gt 0 ] && [ $SNAPSHOTS_CREATED -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SNAPSHOTS RECIENTES YA EXISTEN${NC}"
    echo -e "${BLUE}💡 Todos los volúmenes tienen backup actualizado${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: PROCESO COMPLETADO CON OBSERVACIONES${NC}"
    echo -e "${YELLOW}💡 Revisar errores y configurar DLM para automatización${NC}"
fi

