# Resumen Ejecutivo: Attach IAM Instance Profile to EC2 Instances

**Fecha**: $(date)  
**Implementación**: Attach IAM instance profile to EC2 instances  
**Objetivo**: Asegurar acceso controlado de instancias EC2 a servicios AWS sin credenciales hardcoded

## 🎯 Estado de Implementación por Perfil

### 1. Profile ANCLA (621394757845)
- **Instancias EC2 encontradas**: 2
  - **Delsat** (i-036dde5f8a7c5369d): Estado `running`
    - ✅ Tiene IAM Profile: `CloudWatchAgentServerRole`
    - ⚠️ Problema: Perfil no accesible o eliminado
    - 🚨 Security Group con reglas abiertas (0.0.0.0/0)
  - **Gunnebo** (i-0fe956a0056791720): Estado `stopped`
    - ❌ Sin IAM Profile
    - ✅ Disponible para configuración (detenida)
- **Cumplimiento IAM**: 50% (1/2 instancias)
- **Acción requerida**: Reparar perfil existente y configurar instancia sin perfil

### 2. Profile AZBEACONS (742385231361)
- **Instancias EC2 encontradas**: 0
- **Perfiles IAM disponibles**: 1 (Support)
- **Estado**: ✅ **SIN INSTANCIAS - PREPARADO**
- **Configuración**: Lista para futuras instancias EC2

### 3. Profile AZCENIT (044616935970)
- **Instancias EC2 encontradas**: 1
  - **Sin nombre** (i-0f431c154921d9725): Estado `running`
    - ❌ Sin IAM Profile
    - 🚨 Instancia corriendo sin perfil (riesgo de seguridad)
- **Perfiles IAM**: Se creó perfil por defecto `EC2-BasicInstanceProfile-azcenit`
- **Cumplimiento IAM**: 0% (0/1 instancias)
- **Acción requerida**: Detener instancia y adjuntar perfil IAM

## 📊 Resumen Estadístico Global

```
Total Instancias EC2: 3
Instancias con Perfil: 1 (33%)
Instancias sin Perfil: 2 (67%)

Distribución por Estado:
- Running sin perfil: 1 (CRÍTICO)
- Stopped sin perfil: 1 (Configurable)
- Running con perfil: 1 (Verificar validez)

Por Perfil:
- ANCLA: 1/2 (50%) - Perfil con problemas
- AZBEACONS: N/A (Sin instancias)
- AZCENIT: 0/1 (0%) - Crítico
```

## 🔧 Configuraciones Implementadas

### Perfiles IAM Creados Automáticamente:
1. **EC2-BasicInstanceProfile-azcenit**
   - Rol: `EC2-BasicRole-azcenit`
   - Políticas incluidas:
     - `CloudWatchAgentServerPolicy` (Monitoreo)
     - `AmazonSSMManagedInstanceCore` (Administración)

### Políticas de Seguridad Recomendadas:
- ✅ CloudWatch Agent para monitoreo
- ✅ SSM para administración remota
- 📋 S3 ReadOnly (según necesidad)
- 📋 Secrets Manager (para credenciales)

## 🚨 Problemas Críticos Identificados

### 1. Instancia Corriendo Sin Perfil (AZCENIT)
```
Instance: i-0f431c154921d9725
Estado: running
Riesgo: Alto - Sin acceso controlado a AWS
```

**Impacto**:
- No puede acceder a servicios AWS de forma segura
- Posible uso de credenciales hardcoded
- Violación de mejores prácticas de seguridad

### 2. Perfil IAM Inaccesible (ANCLA)
```
Instance: i-036dde5f8a7c5369d
Perfil: CloudWatchAgentServerRole
Problema: Perfil eliminado o sin permisos
```

**Impacto**:
- Pérdida de funcionalidad de monitoreo
- Aplicaciones pueden fallar al acceder AWS
- Logs y métricas no se envían a CloudWatch

### 3. Security Groups Abiertos
```
Security Group: sg-0810b5456b54a9882
Problema: Reglas 0.0.0.0/0 (Internet abierto)
```

## 📋 Plan de Remediación Inmediata

### Prioridad ALTA (AZCENIT):
```bash
# 1. Detener instancia corriendo sin perfil
aws ec2 stop-instances --instance-ids i-0f431c154921d9725 --profile azcenit

# 2. Adjuntar perfil IAM (una vez detenida)
aws ec2 associate-iam-instance-profile \
    --instance-id i-0f431c154921d9725 \
    --iam-instance-profile Name=EC2-BasicInstanceProfile-azcenit \
    --profile azcenit

# 3. Reiniciar instancia
aws ec2 start-instances --instance-ids i-0f431c154921d9725 --profile azcenit
```

### Prioridad MEDIA (ANCLA):
```bash
# 1. Verificar si el rol existe
aws iam get-role --role-name CloudWatchAgentServerRole --profile ancla

# 2. Si no existe, recrear o usar perfil alternativo
aws ec2 replace-iam-instance-profile-association \
    --instance-id i-036dde5f8a7c5369d \
    --iam-instance-profile Name=NUEVO_PERFIL \
    --profile ancla

# 3. Configurar instancia Gunnebo (detenida)
aws ec2 associate-iam-instance-profile \
    --instance-id i-0fe956a0056791720 \
    --iam-instance-profile Name=EC2-BasicInstanceProfile-ancla \
    --profile ancla
```

## 🛡️ Mejores Prácticas Implementadas

### 1. Principio de Menor Privilegio
- Políticas AWS managed específicas
- Sin políticas `*:*` o `AdminAccess`
- Roles específicos por función

### 2. Automatización
- Creación automática de perfiles faltantes
- Roles con políticas básicas de seguridad
- Scripts de verificación continua

### 3. Monitoreo y Auditoria
- CloudWatch Agent para métricas
- SSM para administración remota
- Documentación completa generada

### 4. Configuración Segura por Defecto
```json
{
  "TrustPolicy": {
    "Service": "ec2.amazonaws.com",
    "Action": "sts:AssumeRole"
  },
  "ManagedPolicies": [
    "CloudWatchAgentServerPolicy",
    "AmazonSSMManagedInstanceCore"
  ]
}
```

## 📈 Métricas de Cumplimiento

### Objetivo: 100% de instancias con perfiles IAM
- **Estado actual**: 33% (1/3 instancias)
- **Instancias críticas**: 1 (corriendo sin perfil)
- **Remediación disponible**: 2 instancias

### KPIs de Seguridad:
- ✅ Perfiles IAM creados: 1/3 cuentas
- ⚠️ Instancias sin credenciales hardcoded: Verificar
- 🚨 Acceso controlado a AWS: 33% cumplimiento

## 🔄 Próximos Pasos

### Inmediato (0-24h):
1. **Detener y configurar instancia AZCENIT**
2. **Reparar perfil IAM en ANCLA**
3. **Configurar instancia Gunnebo detenida**

### Corto Plazo (1-7 días):
1. **Crear perfiles específicos por función**
2. **Implementar monitoreo de cumplimiento**
3. **Configurar alertas para instancias sin perfil**

### Mediano Plazo (1-4 semanas):
1. **Auditar y optimizar permisos**
2. **Implementar Launch Templates con perfiles**
3. **Automatizar compliance checks**

---

**Nota Crítica**: La instancia i-0f431c154921d9725 en AZCENIT está corriendo sin perfil IAM, representando un riesgo de seguridad inmediato que requiere atención urgente.