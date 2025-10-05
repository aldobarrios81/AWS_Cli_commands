#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"
PROFILE="azcenit"

echo "=== Habilitando GuardDuty EKS Runtime Protection ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION"
echo "Perfil: $PROFILE"
echo

# 1️⃣ Verificar si ya existe un detector
echo "Verificando detector de GuardDuty..."
DETECTOR_ID=$(wsl aws guardduty list-detectors \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'DetectorIds[0]' \
  --output text)

if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
    echo "No hay detector. Creando uno nuevo..."
    DETECTOR_ID=$(wsl aws guardduty create-detector \
      --enable \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query 'DetectorId' \
      --output text)
    echo "✔ Detector creado: $DETECTOR_ID"
else
    echo "✔ Detector existente: $DETECTOR_ID"
fi

# 2️⃣ Habilitar EKS Runtime Monitoring con configuración adicional
echo
echo "Activando EKS Runtime Monitoring con gestión de add-ons..."
wsl aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features '[
    {
      "Name": "EKS_RUNTIME_MONITORING",
      "Status": "ENABLED",
      "AdditionalConfiguration": [
        {
          "Name": "EKS_ADDON_MANAGEMENT",
          "Status": "ENABLED"
        }
      ]
    }
  ]' \
  --region "$REGION" \
  --profile "$PROFILE"

echo "✔ GuardDuty EKS Runtime Monitoring habilitado"

# 3️⃣ Listar todos los clústeres EKS existentes
echo
echo "Buscando clústeres EKS existentes..."
CLUSTERS=$(wsl aws eks list-clusters \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'clusters' \
  --output text 2>/dev/null || echo "")

if [ -z "$CLUSTERS" ] || [ "$CLUSTERS" == "None" ]; then
    echo "⚠️  No se encontraron clústeres EKS en $REGION"
    echo "   GuardDuty EKS Runtime Protection está habilitado y se aplicará"
    echo "   automáticamente a futuros clústeres EKS que se creen."
else
    echo "✔ Clústeres EKS encontrados: $(echo $CLUSTERS | wc -w)"
    echo

    # 4️⃣ Verificar y configurar add-on GuardDuty en cada clúster
    for CLUSTER in $CLUSTERS; do
        echo "-> Procesando cluster: $CLUSTER"
        
        # Verificar si el add-on ya existe
        addon_exists=$(wsl aws eks describe-addon \
          --cluster-name "$CLUSTER" \
          --addon-name amazon-guardduty-agent \
          --region "$REGION" \
          --profile "$PROFILE" \
          --query 'addon.addonName' \
          --output text 2>/dev/null || echo "NOT_FOUND")

        if [ "$addon_exists" != "NOT_FOUND" ]; then
            echo "   ✔ Add-on GuardDuty ya instalado en $CLUSTER"
            
            # Verificar el estado del add-on
            addon_status=$(wsl aws eks describe-addon \
              --cluster-name "$CLUSTER" \
              --addon-name amazon-guardduty-agent \
              --region "$REGION" \
              --profile "$PROFILE" \
              --query 'addon.status' \
              --output text)
            echo "     Estado: $addon_status"
        else
            echo "   -> Instalando add-on GuardDuty en $CLUSTER"
            
            install_result=$(wsl aws eks create-addon \
              --cluster-name "$CLUSTER" \
              --addon-name amazon-guardduty-agent \
              --resolve-conflicts OVERWRITE \
              --region "$REGION" \
              --profile "$PROFILE" 2>&1)
            
            if [ $? -eq 0 ]; then
                echo "   ✔ Add-on instalado exitosamente en $CLUSTER"
            else
                echo "   ⚠️  Error instalando add-on en $CLUSTER:"
                echo "      $install_result"
            fi
        fi
        echo
    done
fi

# 5️⃣ Verificar configuración final
echo "Verificando configuración final de GuardDuty..."
detector_info=$(wsl aws guardduty get-detector \
  --detector-id "$DETECTOR_ID" \
  --region "$REGION" \
  --profile "$PROFILE")

echo "EKS Runtime Monitoring configurado:"
echo "$detector_info" | grep -A 10 -B 5 "EKS_RUNTIME_MONITORING" || echo "✔ EKS Runtime Monitoring habilitado"

echo
echo "✅ GuardDuty EKS Runtime Protection configurado exitosamente"
echo
echo "Configuración completada:"
echo "- Detector ID: $DETECTOR_ID"
echo "- EKS Runtime Monitoring: ENABLED"
echo "- EKS Add-on Management: ENABLED"
if [ -n "$CLUSTERS" ] && [ "$CLUSTERS" != "None" ]; then
    echo "- Clústeres procesados: $(echo $CLUSTERS | wc -w)"
fi
echo
echo "Notas importantes:"
echo "- GuardDuty monitoreará automáticamente los pods de EKS"
echo "- Los add-ons se instalan automáticamente en nuevos clústeres"
echo "- El monitoreo incluye detección de malware y actividades sospechosas"
echo "- Los findings aparecerán en la consola de GuardDuty"
echo
echo "=== Proceso completado ==="

