PROFILE="azcenit"
REGION="us-east-1"
DETECTOR_ID=$(aws guardduty list-detectors --profile $PROFILE --region $REGION --query "DetectorIds[0]" --output text)

# Habilitar Malware Protection + EKS Runtime + RDS
aws guardduty update-detector \
  --detector-id $DETECTOR_ID \
  --features '[{"Name":"EKS_RUNTIME_MONITORING","Status":"ENABLED"},{"Name":"RDS_LOGIN_EVENTS","Status":"ENABLED"},{"Name":"EBS_MALWARE_PROTECTION","Status":"ENABLED"}]' \
  --profile $PROFILE \
  --region $REGION

