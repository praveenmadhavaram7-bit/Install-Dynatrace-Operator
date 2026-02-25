# Rendered by envsubst in Stage 4
# Required env vars:
#   DT_NAMESPACE, CLUSTER_NAME, DT_API_URL, NETWORK_ZONE, HOST_GROUP, SECRET_NAME
apiVersion: dynatrace.com/v1beta5
kind: DynaKube
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${DT_NAMESPACE}
spec:
  apiUrl: ${DT_API_URL}
  networkZone: ${NETWORK_ZONE}
  tokens: ${SECRET_NAME}

  metadataEnrichment:
    enabled: true

  oneAgent:
    hostGroup: ${HOST_GROUP}
    cloudNativeFullStack: {}

  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
    resources:
      requests:
        cpu: ${AG_REQ_CPU}
        memory: ${AG_REQ_MEM}
      limits:
        cpu: ${AG_LIM_CPU}
        memory: ${AG_LIM_MEM}
