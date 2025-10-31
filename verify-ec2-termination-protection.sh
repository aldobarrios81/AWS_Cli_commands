#!/bin/bash
# verify-ec2-termination-protection.sh
# Verificar y auditar protección contra terminación en instancias EC2
# Genera reportes detallados de compliance y seguridad

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
echo -e "${BLUE}🔍 VERIFICACIÓN PROTECCIÓN TERMINACIÓN EC2${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región Principal: ${GREEN}$REGION${NC}"
echo "Auditando configuración de protección contra terminación"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔧 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
AWS_VERSION=$(aws --version 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no encontrado${NC}"
    exit 1
fi
echo -e "✅ AWS CLI: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables de auditoría
TOTAL_INSTANCES=0
PROTECTED_INSTANCES=0
UNPROTECTED_INSTANCES=0
CRITICAL_PROTECTED=0
CRITICAL_UNPROTECTED=0
NON_CRITICAL_PROTECTED=0
NON_CRITICAL_UNPROTECTED=0
COMPLIANCE_SCORE=0
SECURITY_VIOLATIONS=0
REGIONS_SCANNED=0

# Verificar regiones con instancias
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Escaneando regiones...${NC}"
for region in "${REGIONS[@]}"; do
    INSTANCE_COUNT=$(aws ec2 describe-instances \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Reservations[].Instances[?State.Name!=`terminated`])' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$INSTANCE_COUNT" ] && [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $INSTANCE_COUNT instancias activas"
        ACTIVE_REGIONS+=("$region")
        REGIONS_SCANNED=$((REGIONS_SCANNED + 1))
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin instancias activas"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron instancias EC2 en ninguna región${NC}"
    echo -e "${BLUE}💡 Compliance: 100% (Sin instancias que proteger)${NC}"
    exit 0
fi

echo ""

# Crear archivo de reporte JSON
REPORT_FILE="ec2-termination-protection-audit-$PROFILE-$(date +%Y%m%d-%H%M%S).json"
SUMMARY_FILE="ec2-termination-protection-summary-$PROFILE-$(date +%Y%m%d-%H%M%S).md"

# Inicializar reporte JSON
cat > "$REPORT_FILE" << EOF
{
  "audit": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "profile": "$PROFILE",
    "account_id": "$ACCOUNT_ID",
    "audit_type": "EC2_TERMINATION_PROTECTION",
    "regions_scanned": $REGIONS_SCANNED,
    "active_regions": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')],
    "summary": {
      "total_instances": 0,
      "protected_instances": 0,
      "unprotected_instances": 0,
      "critical_protected": 0,
      "critical_unprotected": 0,
      "compliance_score": 0,
      "security_violations": 0
    },
    "instances": [],
    "violations": [],
    "recommendations": []
  }
}
EOF

# Función para evaluar criticidad
evaluate_instance_criticality() {
    local instance_id="$1"
    local instance_type="$2"
    local instance_name="$3"
    local tags="$4"
    local region="$5"
    
    local criticality_score=0
    local reasons=()
    
    # Evaluar por tipo de instancia
    case "$instance_type" in
        t2.micro|t3.micro|t3a.micro)
            criticality_score=10
            reasons+=("Tipo de instancia básico")
            ;;
        t2.*|t3.*|t3a.*)
            criticality_score=20
            reasons+=("Tipo de instancia estándar")
            ;;
        m5.*|m6.*|c5.*|c6.*|r5.*|r6.*)
            criticality_score=60
            reasons+=("Tipo de instancia de producción")
            ;;
        x1.*|z1.*|p3.*|p4.*|g4.*)
            criticality_score=80
            reasons+=("Tipo de instancia especializada")
            ;;
        *)
            criticality_score=40
            reasons+=("Tipo de instancia no clasificado")
            ;;
    esac
    
    # Evaluar por nombre
    if [[ "$instance_name" =~ (prod|production) ]]; then
        criticality_score=$((criticality_score + 30))
        reasons+=("Nombre indica producción")
    elif [[ "$instance_name" =~ (critical|database|db) ]]; then
        criticality_score=$((criticality_score + 40))
        reasons+=("Nombre indica sistema crítico")
    elif [[ "$instance_name" =~ (web|api|app|server) ]]; then
        criticality_score=$((criticality_score + 25))
        reasons+=("Nombre indica servicio de aplicación")
    elif [[ "$instance_name" =~ (dev|test|staging) ]]; then
        criticality_score=$((criticality_score - 10))
        reasons+=("Nombre indica ambiente no productivo")
    fi
    
    # Evaluar por tags
    if [[ "$tags" =~ Environment.*[Pp]rod ]]; then
        criticality_score=$((criticality_score + 35))
        reasons+=("Environment=Production")
    fi
    
    if [[ "$tags" =~ Critical.*true ]]; then
        criticality_score=$((criticality_score + 50))
        reasons+=("Tag Critical=true")
    fi
    
    if [[ "$tags" =~ Role.*(database|db|mysql|postgres|oracle|mongodb) ]]; then
        criticality_score=$((criticality_score + 45))
        reasons+=("Rol de base de datos")
    elif [[ "$tags" =~ Role.*(web|api|app|server) ]]; then
        criticality_score=$((criticality_score + 30))
        reasons+=("Rol de aplicación")
    fi
    
    # Verificar recursos asociados
    
    # Elastic IP
    local eip_count=$(aws ec2 describe-addresses \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=instance-id,Values=$instance_id" \
        --query 'length(Addresses)' \
        --output text 2>/dev/null)
    
    if [ -n "$eip_count" ] && [ "$eip_count" -gt 0 ]; then
        criticality_score=$((criticality_score + 20))
        reasons+=("Tiene $eip_count Elastic IP(s)")
    fi
    
    # Volúmenes EBS
    local volume_count=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=attachment.instance-id,Values=$instance_id" \
        --query 'length(Volumes)' \
        --output text 2>/dev/null)
    
    if [ -n "$volume_count" ] && [ "$volume_count" -gt 1 ]; then
        criticality_score=$((criticality_score + 15))
        reasons+=("Múltiples volúmenes EBS ($volume_count)")
    fi
    
    # Load Balancers asociados
    local lb_check=$(aws elbv2 describe-target-groups \
        --profile "$PROFILE" \
        --region "$region" \
        --query "TargetGroups[?contains(to_string(TargetHealthDescriptions[*].Target.Id), '$instance_id')]" \
        --output text 2>/dev/null)
    
    if [ -n "$lb_check" ]; then
        criticality_score=$((criticality_score + 25))
        reasons+=("Registrado en Load Balancer")
    fi
    
    # Auto Scaling Groups
    local asg_check=$(aws autoscaling describe-auto-scaling-instances \
        --profile "$PROFILE" \
        --region "$region" \
        --instance-ids "$instance_id" \
        --query 'AutoScalingInstances[0].AutoScalingGroupName' \
        --output text 2>/dev/null)
    
    if [ -n "$asg_check" ] && [ "$asg_check" != "None" ]; then
        criticality_score=$((criticality_score + 20))
        reasons+=("Miembro de Auto Scaling Group")
    fi
    
    # Determinar nivel de criticidad final
    if [ $criticality_score -ge 70 ]; then
        echo "CRITICAL|$criticality_score|${reasons[*]}"
    elif [ $criticality_score -ge 40 ]; then
        echo "HIGH|$criticality_score|${reasons[*]}"
    elif [ $criticality_score -ge 20 ]; then
        echo "MEDIUM|$criticality_score|${reasons[*]}"
    else
        echo "LOW|$criticality_score|${reasons[*]}"
    fi
}

# Función para evaluar configuración de seguridad
evaluate_security_configuration() {
    local instance_id="$1"
    local region="$2"
    
    local security_score=0
    local security_issues=()
    
    # Obtener detalles de la instancia
    local instance_details=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "ERROR|0|No se pudo obtener información de seguridad"
        return
    fi
    
    # Verificar protección de terminación
    local termination_protection=$(echo "$instance_details" | jq -r '.DisableApiTermination // false')
    if [ "$termination_protection" = "true" ]; then
        security_score=$((security_score + 25))
    else
        security_issues+=("Sin protección de terminación")
    fi
    
    # Verificar monitoring detallado
    local monitoring=$(echo "$instance_details" | jq -r '.Monitoring.State')
    if [ "$monitoring" = "enabled" ]; then
        security_score=$((security_score + 15))
    else
        security_issues+=("Monitoring básico")
    fi
    
    # Verificar IAM Instance Profile
    local iam_role=$(echo "$instance_details" | jq -r '.IamInstanceProfile.Arn // "none"')
    if [ "$iam_role" != "none" ]; then
        security_score=$((security_score + 20))
    else
        security_issues+=("Sin IAM role asociado")
    fi
    
    # Verificar EBS encryption
    local block_devices=$(echo "$instance_details" | jq -r '.BlockDeviceMappings[].Ebs.Encrypted // false')
    local encrypted_count=0
    local total_volumes=0
    
    while IFS= read -r encrypted; do
        if [ -n "$encrypted" ]; then
            total_volumes=$((total_volumes + 1))
            if [ "$encrypted" = "true" ]; then
                encrypted_count=$((encrypted_count + 1))
            fi
        fi
    done <<< "$block_devices"
    
    if [ $total_volumes -gt 0 ]; then
        if [ $encrypted_count -eq $total_volumes ]; then
            security_score=$((security_score + 20))
        elif [ $encrypted_count -gt 0 ]; then
            security_score=$((security_score + 10))
            security_issues+=("Algunos volúmenes sin cifrar")
        else
            security_issues+=("Volúmenes sin cifrar")
        fi
    fi
    
    # Verificar Security Groups
    local security_groups=$(echo "$instance_details" | jq -r '.SecurityGroups[].GroupId')
    local sg_issues=0
    
    while IFS= read -r sg_id; do
        if [ -n "$sg_id" ]; then
            # Verificar reglas permisivas
            local permissive_rules=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --profile "$PROFILE" \
                --region "$region" \
                --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`] || Ipv6Ranges[?CidrIpv6==`::/0`]]' \
                --output json 2>/dev/null)
            
            if [ -n "$permissive_rules" ] && [ "$permissive_rules" != "[]" ]; then
                sg_issues=$((sg_issues + 1))
            fi
        fi
    done <<< "$security_groups"
    
    if [ $sg_issues -eq 0 ]; then
        security_score=$((security_score + 15))
    else
        security_issues+=("Security Groups con acceso público")
    fi
    
    # Verificar si está en subnet privada
    local subnet_id=$(echo "$instance_details" | jq -r '.SubnetId')
    if [ -n "$subnet_id" ] && [ "$subnet_id" != "null" ]; then
        local route_table=$(aws ec2 describe-route-tables \
            --profile "$PROFILE" \
            --region "$region" \
            --filters "Name=association.subnet-id,Values=$subnet_id" \
            --query 'RouteTables[0].Routes[?GatewayId && starts_with(GatewayId, `igw-`)]' \
            --output json 2>/dev/null)
        
        if [ "$route_table" = "[]" ]; then
            security_score=$((security_score + 10))
        else
            security_issues+=("En subnet pública")
        fi
    fi
    
    # Determinar nivel de seguridad
    if [ $security_score -ge 85 ]; then
        echo "EXCELLENT|$security_score|${security_issues[*]}"
    elif [ $security_score -ge 70 ]; then
        echo "GOOD|$security_score|${security_issues[*]}"
    elif [ $security_score -ge 50 ]; then
        echo "AVERAGE|$security_score|${security_issues[*]}"
    elif [ $security_score -ge 30 ]; then
        echo "POOR|$security_score|${security_issues[*]}"
    else
        echo "CRITICAL|$security_score|${security_issues[*]}"
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Auditando región: $CURRENT_REGION ===${NC}"
    
    # Obtener todas las instancias activas
    INSTANCES_DATA=$(aws ec2 describe-instances \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --filters "Name=instance-state-name,Values=running,stopped,stopping,pending,rebooting" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,DisableApiTermination,Tags[?Key==`Name`].Value|[0],LaunchTime,Platform,PublicIpAddress,PrivateIpAddress,VpcId,SubnetId]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener instancias en región $CURRENT_REGION${NC}"
        continue
    fi
    
    if [ -z "$INSTANCES_DATA" ]; then
        echo -e "${BLUE}ℹ️ Sin instancias activas en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Analizando instancias en $CURRENT_REGION...${NC}"
    
    while IFS=$'\t' read -r instance_id instance_type state termination_protection instance_name launch_time platform public_ip private_ip vpc_id subnet_id; do
        if [ -n "$instance_id" ]; then
            TOTAL_INSTANCES=$((TOTAL_INSTANCES + 1))
            
            # Normalizar nombre
            if [ -z "$instance_name" ] || [ "$instance_name" = "None" ]; then
                instance_name="$instance_id"
            fi
            
            # Normalizar valores None/null
            [ "$platform" = "None" ] && platform=""
            [ "$public_ip" = "None" ] && public_ip=""
            [ "$private_ip" = "None" ] && private_ip=""
            [ "$vpc_id" = "None" ] && vpc_id=""
            [ "$subnet_id" = "None" ] && subnet_id=""
            
            echo -e "${CYAN}🖥️ Analizando: $instance_name${NC}"
            echo -e "   🆔 ID: ${BLUE}$instance_id${NC}"
            echo -e "   📦 Tipo: ${BLUE}$instance_type${NC}"
            echo -e "   🔄 Estado: ${BLUE}$state${NC}"
            
            if [ -n "$launch_time" ] && [ "$launch_time" != "None" ]; then
                echo -e "   📅 Lanzamiento: ${BLUE}$launch_time${NC}"
            fi
            
            # Obtener tags completos
            INSTANCE_TAGS=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Reservations[0].Instances[0].Tags' \
                --output json 2>/dev/null)
            
            TAGS_STRING=""
            if [ -n "$INSTANCE_TAGS" ] && [ "$INSTANCE_TAGS" != "null" ]; then
                TAGS_STRING=$(echo "$INSTANCE_TAGS" | jq -r 'map(select(.Key and .Value) | "\(.Key)=\(.Value)") | join(" ")' 2>/dev/null)
            fi
            
            # Evaluar criticidad
            CRITICALITY_RESULT=$(evaluate_instance_criticality "$instance_id" "$instance_type" "$instance_name" "$TAGS_STRING" "$CURRENT_REGION")
            IFS='|' read -r criticality_level criticality_score criticality_reasons <<< "$CRITICALITY_RESULT"
            
            # Evaluar configuración de seguridad
            SECURITY_RESULT=$(evaluate_security_configuration "$instance_id" "$CURRENT_REGION")
            IFS='|' read -r security_level security_score security_issues <<< "$SECURITY_RESULT"
            
            # Verificar protección de terminación
            if [ "$termination_protection" = "True" ] || [ "$termination_protection" = "true" ]; then
                echo -e "   🔒 Protección: ${GREEN}HABILITADA${NC}"
                PROTECTED_INSTANCES=$((PROTECTED_INSTANCES + 1))
                
                if [[ "$criticality_level" =~ ^(CRITICAL|HIGH)$ ]]; then
                    CRITICAL_PROTECTED=$((CRITICAL_PROTECTED + 1))
                else
                    NON_CRITICAL_PROTECTED=$((NON_CRITICAL_PROTECTED + 1))
                fi
            else
                echo -e "   🔒 Protección: ${RED}DESHABILITADA${NC}"
                UNPROTECTED_INSTANCES=$((UNPROTECTED_INSTANCES + 1))
                
                if [[ "$criticality_level" =~ ^(CRITICAL|HIGH)$ ]]; then
                    CRITICAL_UNPROTECTED=$((CRITICAL_UNPROTECTED + 1))
                    SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
                    echo -e "   ⚠️ ${RED}VIOLACIÓN DE SEGURIDAD: Instancia crítica sin protección${NC}"
                else
                    NON_CRITICAL_UNPROTECTED=$((NON_CRITICAL_UNPROTECTED + 1))
                fi
            fi
            
            # Mostrar evaluación de criticidad
            case "$criticality_level" in
                CRITICAL)
                    echo -e "   🔴 Criticidad: ${RED}CRÍTICA ($criticality_score pts)${NC}"
                    ;;
                HIGH)
                    echo -e "   🟠 Criticidad: ${YELLOW}ALTA ($criticality_score pts)${NC}"
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
            
            # Mostrar evaluación de seguridad
            case "$security_level" in
                EXCELLENT)
                    echo -e "   🏆 Seguridad: ${GREEN}EXCELENTE ($security_score/100)${NC}"
                    ;;
                GOOD)
                    echo -e "   ✅ Seguridad: ${GREEN}BUENA ($security_score/100)${NC}"
                    ;;
                AVERAGE)
                    echo -e "   ⚠️ Seguridad: ${YELLOW}PROMEDIO ($security_score/100)${NC}"
                    ;;
                POOR)
                    echo -e "   ❌ Seguridad: ${RED}DEFICIENTE ($security_score/100)${NC}"
                    ;;
                CRITICAL)
                    echo -e "   🚨 Seguridad: ${RED}CRÍTICA ($security_score/100)${NC}"
                    ;;
            esac
            
            if [ -n "$security_issues" ] && [ "$security_issues" != " " ]; then
                echo -e "   🔍 Issues: ${YELLOW}$security_issues${NC}"
            fi
            
            # Información de red
            if [ -n "$vpc_id" ]; then
                echo -e "   🌐 VPC: ${BLUE}$vpc_id${NC}"
            fi
            
            if [ -n "$subnet_id" ]; then
                echo -e "   🔗 Subnet: ${BLUE}$subnet_id${NC}"
            fi
            
            if [ -n "$public_ip" ]; then
                echo -e "   🌍 IP Pública: ${YELLOW}$public_ip${NC}"
            fi
            
            if [ -n "$private_ip" ]; then
                echo -e "   🏠 IP Privada: ${BLUE}$private_ip${NC}"
            fi
            
            # Información del sistema operativo
            if [ -n "$platform" ]; then
                echo -e "   💻 Plataforma: ${BLUE}$platform${NC}"
            else
                echo -e "   💻 Plataforma: ${BLUE}Linux/Unix${NC}"
            fi
            
            # Agregar al reporte JSON
            local instance_json=$(cat << EOF
{
  "instance_id": "$instance_id",
  "instance_name": "$instance_name",
  "instance_type": "$instance_type",
  "state": "$state",
  "region": "$CURRENT_REGION",
  "termination_protection": $([ "$termination_protection" = "True" ] && echo "true" || echo "false"),
  "criticality": {
    "level": "$criticality_level",
    "score": $criticality_score,
    "reasons": "$criticality_reasons"
  },
  "security": {
    "level": "$security_level",
    "score": $security_score,
    "issues": "$security_issues"
  },
  "network": {
    "vpc_id": "$vpc_id",
    "subnet_id": "$subnet_id",
    "public_ip": "$public_ip",
    "private_ip": "$private_ip"
  },
  "platform": "$platform",
  "launch_time": "$launch_time",
  "tags": $INSTANCE_TAGS
}
EOF
)
            
            # Añadir instancia al reporte (usando jq para mantener formato JSON válido)
            local temp_file=$(mktemp)
            jq --argjson instance "$instance_json" '.audit.instances += [$instance]' "$REPORT_FILE" > "$temp_file"
            mv "$temp_file" "$REPORT_FILE"
            
            echo ""
        fi
    done <<< "$INSTANCES_DATA"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION auditada${NC}"
    echo ""
done

# Calcular puntuación de compliance
if [ $TOTAL_INSTANCES -gt 0 ]; then
    # Base: porcentaje de instancias protegidas
    BASIC_PROTECTION_PERCENT=$((PROTECTED_INSTANCES * 100 / TOTAL_INSTANCES))
    
    # Penalizaciones por instancias críticas sin proteger
    CRITICAL_PENALTY=0
    if [ $CRITICAL_UNPROTECTED -gt 0 ]; then
        CRITICAL_PENALTY=$((CRITICAL_UNPROTECTED * 20))  # -20 puntos por cada crítica sin proteger
    fi
    
    # Bonificaciones por protección de críticas
    CRITICAL_BONUS=0
    if [ $CRITICAL_PROTECTED -gt 0 ]; then
        CRITICAL_BONUS=$((CRITICAL_PROTECTED * 5))  # +5 puntos por cada crítica protegida
    fi
    
    # Calcular puntuación final
    COMPLIANCE_SCORE=$((BASIC_PROTECTION_PERCENT + CRITICAL_BONUS - CRITICAL_PENALTY))
    
    # Asegurar que esté en rango 0-100
    if [ $COMPLIANCE_SCORE -gt 100 ]; then
        COMPLIANCE_SCORE=100
    elif [ $COMPLIANCE_SCORE -lt 0 ]; then
        COMPLIANCE_SCORE=0
    fi
else
    COMPLIANCE_SCORE=100  # Sin instancias = compliance perfecto
fi

# Actualizar resumen en reporte JSON
jq --argjson total "$TOTAL_INSTANCES" \
   --argjson protected "$PROTECTED_INSTANCES" \
   --argjson unprotected "$UNPROTECTED_INSTANCES" \
   --argjson crit_protected "$CRITICAL_PROTECTED" \
   --argjson crit_unprotected "$CRITICAL_UNPROTECTED" \
   --argjson compliance "$COMPLIANCE_SCORE" \
   --argjson violations "$SECURITY_VIOLATIONS" \
   '.audit.summary.total_instances = $total |
    .audit.summary.protected_instances = $protected |
    .audit.summary.unprotected_instances = $unprotected |
    .audit.summary.critical_protected = $crit_protected |
    .audit.summary.critical_unprotected = $crit_unprotected |
    .audit.summary.compliance_score = $compliance |
    .audit.summary.security_violations = $violations' "$REPORT_FILE" > "${REPORT_FILE}.tmp"
mv "${REPORT_FILE}.tmp" "$REPORT_FILE"

# Generar recomendaciones
RECOMMENDATIONS=()

if [ $CRITICAL_UNPROTECTED -gt 0 ]; then
    RECOMMENDATIONS+=("Habilitar protección de terminación en $CRITICAL_UNPROTECTED instancia(s) crítica(s)")
fi

if [ $SECURITY_VIOLATIONS -gt 0 ]; then
    RECOMMENDATIONS+=("Revisar configuraciones de seguridad en instancias con violaciones")
fi

if [ $NON_CRITICAL_UNPROTECTED -gt 0 ]; then
    RECOMMENDATIONS+=("Evaluar protección de terminación en $NON_CRITICAL_UNPROTECTED instancia(s) no crítica(s)")
fi

if [ ${#RECOMMENDATIONS[@]} -eq 0 ]; then
    RECOMMENDATIONS+=("Excelente: Todas las instancias críticas están protegidas")
fi

# Agregar recomendaciones al JSON
for rec in "${RECOMMENDATIONS[@]}"; do
    jq --arg rec "$rec" '.audit.recommendations += [$rec]' "$REPORT_FILE" > "${REPORT_FILE}.tmp"
    mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
done

# Generar resumen ejecutivo
cat > "$SUMMARY_FILE" << EOF
# Auditoría EC2 Termination Protection - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones**: ${ACTIVE_REGIONS[*]}

## 📊 Resumen Ejecutivo

### Métricas Principales
- **Puntuación de Compliance**: **${COMPLIANCE_SCORE}/100**
- **Total de instancias**: $TOTAL_INSTANCES
- **Instancias protegidas**: $PROTECTED_INSTANCES ($((TOTAL_INSTANCES > 0 ? PROTECTED_INSTANCES * 100 / TOTAL_INSTANCES : 0))%)
- **Violaciones de seguridad**: $SECURITY_VIOLATIONS

### Distribución por Criticidad
- **Críticas protegidas**: $CRITICAL_PROTECTED
- **Críticas desprotegidas**: $CRITICAL_UNPROTECTED
- **No críticas protegidas**: $NON_CRITICAL_PROTECTED  
- **No críticas desprotegidas**: $NON_CRITICAL_UNPROTECTED

## 🎯 Estado de Compliance

EOF

if [ $COMPLIANCE_SCORE -ge 90 ]; then
    echo "**🏆 EXCELENTE** - Configuración de seguridad óptima" >> "$SUMMARY_FILE"
elif [ $COMPLIANCE_SCORE -ge 80 ]; then
    echo "**✅ BUENO** - Configuración adecuada con mejoras menores" >> "$SUMMARY_FILE"
elif [ $COMPLIANCE_SCORE -ge 70 ]; then
    echo "**⚠️ PROMEDIO** - Requiere atención en áreas críticas" >> "$SUMMARY_FILE"
elif [ $COMPLIANCE_SCORE -ge 50 ]; then
    echo "**❌ DEFICIENTE** - Riesgos significativos de seguridad" >> "$SUMMARY_FILE"
else
    echo "**🚨 CRÍTICO** - Exposición grave a riesgos de seguridad" >> "$SUMMARY_FILE"
fi

cat >> "$SUMMARY_FILE" << EOF

## 🔍 Recomendaciones Prioritarias

EOF

for i in "${!RECOMMENDATIONS[@]}"; do
    echo "$((i+1)). ${RECOMMENDATIONS[i]}" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" << EOF

## 📋 Comandos de Corrección

\`\`\`bash
# Habilitar protección en instancia específica
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID \\
    --disable-api-termination --profile $PROFILE --region REGION

# Verificar estado de protección
aws ec2 describe-instance-attribute --instance-id INSTANCE_ID \\
    --attribute disableApiTermination --profile $PROFILE --region REGION

# Aplicar protección a todas las instancias críticas
for instance in \$(aws ec2 describe-instances --profile $PROFILE --region us-east-1 \\
    --query "Reservations[].Instances[?DisableApiTermination==\\\`false\\\`].InstanceId" --output text); do
    aws ec2 modify-instance-attribute --instance-id \$instance --disable-api-termination
done
\`\`\`

## 📈 Próximos Pasos

1. **Inmediato**: Corregir violaciones críticas identificadas
2. **Corto plazo**: Implementar protección en instancias de alta criticidad
3. **Mediano plazo**: Establecer políticas automáticas de protección
4. **Largo plazo**: Integrar validaciones en pipelines de despliegue

---
*Reporte generado automáticamente - $(date)*
EOF

echo -e "${PURPLE}=== REPORTE DE AUDITORÍA ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones auditadas: ${GREEN}$REGIONS_SCANNED${NC} (${ACTIVE_REGIONS[*]})"
echo -e "🖥️ Total instancias: ${GREEN}$TOTAL_INSTANCES${NC}"
echo -e "🔒 Instancias protegidas: ${GREEN}$PROTECTED_INSTANCES${NC}"
echo -e "⚠️ Sin protección: ${YELLOW}$UNPROTECTED_INSTANCES${NC}"
echo -e "🔴 Críticas sin proteger: ${RED}$CRITICAL_UNPROTECTED${NC}"
echo -e "🔍 Violaciones de seguridad: ${RED}$SECURITY_VIOLATIONS${NC}"

# Mostrar puntuación con colores
if [ $COMPLIANCE_SCORE -ge 90 ]; then
    echo -e "🏆 Puntuación Compliance: ${GREEN}$COMPLIANCE_SCORE/100 (EXCELENTE)${NC}"
elif [ $COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "✅ Puntuación Compliance: ${GREEN}$COMPLIANCE_SCORE/100 (BUENO)${NC}"
elif [ $COMPLIANCE_SCORE -ge 70 ]; then
    echo -e "⚠️ Puntuación Compliance: ${YELLOW}$COMPLIANCE_SCORE/100 (PROMEDIO)${NC}"
elif [ $COMPLIANCE_SCORE -ge 50 ]; then
    echo -e "❌ Puntuación Compliance: ${RED}$COMPLIANCE_SCORE/100 (DEFICIENTE)${NC}"
else
    echo -e "🚨 Puntuación Compliance: ${RED}$COMPLIANCE_SCORE/100 (CRÍTICO)${NC}"
fi

echo ""
echo -e "📁 Reporte JSON: ${GREEN}$REPORT_FILE${NC}"
echo -e "📄 Resumen ejecutivo: ${GREEN}$SUMMARY_FILE${NC}"

# Estado final
echo ""
if [ $TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ SIN INSTANCIAS EC2 - COMPLIANCE: 100%${NC}"
elif [ $CRITICAL_UNPROTECTED -eq 0 ] && [ $SECURITY_VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}🎉 TODAS LAS INSTANCIAS CRÍTICAS PROTEGIDAS${NC}"
elif [ $COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "${GREEN}✅ COMPLIANCE SATISFACTORIO${NC}"
    echo -e "${BLUE}💡 Considerar mejoras menores identificadas${NC}"
else
    echo -e "${YELLOW}⚠️ REQUIERE ATENCIÓN INMEDIATA${NC}"
    echo -e "${RED}🚨 Instancias críticas expuestas a riesgos de terminación${NC}"
fi