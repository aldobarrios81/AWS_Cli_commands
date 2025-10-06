# Configuración AWS WAF para AppSync - azcenit

**Fecha**: Sun Oct  5 19:12:23 -05 2025
**Región**: us-east-1
**Account ID**: 044616935970

## Resumen Ejecutivo

### APIs AppSync Procesadas
- **Total APIs encontradas**: 1
- **WAF ACLs creados**: 1
- **Asociaciones creadas**: 0
- **Asociaciones existentes**: 0

### Web ACL Configurado
- **Nombre**: AppSyncProtection-azcenit-20251005
- **ARN**: arn:aws:wafv2:us-east-1:044616935970:regional/webacl/AppSyncProtection-azcenit-20251005/e67e513a-32e2-4bad-a789-bf55901c59f8
- **Scope**: REGIONAL

## Reglas WAF Implementadas

### 1. Common Rule Set
- Protección contra ataques comunes (OWASP Top 10)
- SQL injection, XSS, path traversal
- Métrica: CommonRuleSetMetric

### 2. Known Bad Inputs
- Protección contra entradas maliciosas conocidas
- Patrones de exploits comunes
- Métrica: KnownBadInputsRuleSetMetric

### 3. IP Reputation List
- Bloqueo de IPs con mala reputación
- Lista mantenida por AWS
- Métrica: AmazonIpReputationListMetric

### 4. Rate Limiting
- Límite: 2000 requests por IP por 5 minutos
- Protección contra DDoS y abuso
- Métrica: RateLimitRule

## Logging y Monitoreo

### CloudWatch Logs
- **Log Group**: /aws/wafv2/appsync/azcenit
- **Retención**: 30 días
- **Formato**: JSON con detalles de requests

### CloudWatch Alarms
- **Alarma**: AppSync-WAF-BlockedRequests-azcenit
- **Umbral**: >100 requests bloqueados en 10 minutos
- **Métrica**: AWS/WAFV2 BlockedRequests

## Comandos de Verificación

```bash
# Verificar Web ACL
aws wafv2 list-web-acls --scope REGIONAL --profile azcenit --region us-east-1

# Verificar asociaciones
aws wafv2 list-resources-for-web-acl --web-acl-arn arn:aws:wafv2:us-east-1:044616935970:regional/webacl/AppSyncProtection-azcenit-20251005/e67e513a-32e2-4bad-a789-bf55901c59f8 --profile azcenit

# Ver métricas WAF
aws cloudwatch get-metric-statistics \
    --namespace AWS/WAFV2 \
    --metric-name AllowedRequests \
    --dimensions Name=WebACL,Value=AppSyncProtection-azcenit-20251005 \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum

# Ver logs WAF
aws logs filter-log-events \
    --log-group-name /aws/wafv2/appsync/azcenit \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Mejores Prácticas

### 1. Monitoreo Continuo
- Revisar métricas WAF diariamente
- Analizar logs de requests bloqueados
- Ajustar reglas según patrones de tráfico

### 2. Tuning de Reglas
- Configurar excepciones para falsos positivos
- Ajustar rate limiting según carga esperada
- Implementar reglas personalizadas según necesidad

### 3. Testing de Seguridad
- Realizar pruebas de penetración regulares
- Validar efectividad de reglas WAF
- Documentar y remediar vulnerabilidades

### 4. Incident Response
- Procedimientos para ataques DDoS
- Escalación de alertas de seguridad
- Respuesta a patrones de ataque inusuales

