{{/*
Expand the name of the chart.
*/}}
{{- define "gov.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gov.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gov.labels" -}}
helm.sh/chart: {{ include "gov.chart" . }}
{{ include "gov.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gov.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gov.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Keycloak JWKS URL
*/}}
{{- define "gov.keycloak.jwksUrl" -}}
{{- printf "%s://keycloak.traefik.%s/realms/traefik/protocol/openid-connect/certs" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Keycloak Issuer URL
*/}}
{{- define "gov.keycloak.issuerUrl" -}}
{{- printf "%s://keycloak.traefik.%s/realms/traefik" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Portal URL
*/}}
{{- define "gov.portal.url" -}}
{{- printf "%s://gov.portal.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Portal Host Match
*/}}
{{- define "gov.portal.hostMatch" -}}
{{- printf "Host(`gov.portal.%s`)" .Values.domain }}
{{- end }}

{{/*
Police API URL
*/}}
{{- define "gov.police.apiUrl" -}}
{{- printf "%s://police-gov.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Police Host Match
*/}}
{{- define "gov.police.hostMatch" -}}
{{- printf "Host(`police-gov.%s`)" .Values.domain }}
{{- end }}

{{/*
Public Works API URL
*/}}
{{- define "gov.publicWorks.apiUrl" -}}
{{- printf "%s://public-works-gov.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Public Works Host Match
*/}}
{{- define "gov.publicWorks.hostMatch" -}}
{{- printf "Host(`public-works-gov.%s`)" .Values.domain }}
{{- end }}

{{/*
Utility API URL
*/}}
{{- define "gov.utility.apiUrl" -}}
{{- printf "%s://utility-gov.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Utility Host Match
*/}}
{{- define "gov.utility.hostMatch" -}}
{{- printf "Host(`utility-gov.%s`)" .Values.domain }}
{{- end }}

{{/*
MCP Server Host Match
*/}}
{{- define "gov.mcp.hostMatch" -}}
{{- printf "Host(`mcp-gov.%s`)" .Values.domain }}
{{- end }}
