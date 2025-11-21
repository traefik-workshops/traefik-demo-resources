{{/*
Expand the name of the chart.
*/}}
{{- define "higher-ed.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "higher-ed.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "higher-ed.labels" -}}
helm.sh/chart: {{ include "higher-ed.chart" . }}
{{ include "higher-ed.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "higher-ed.selectorLabels" -}}
app.kubernetes.io/name: {{ include "higher-ed.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Keycloak JWKS URL
*/}}
{{- define "higher-ed.keycloak.jwksUrl" -}}
{{- printf "%s://keycloak.%s/realms/traefik/protocol/openid-connect/certs" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Keycloak Issuer URL
*/}}
{{- define "higher-ed.keycloak.issuerUrl" -}}
{{- printf "%s://keycloak.%s/realms/traefik" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Portal URL
*/}}
{{- define "higher-ed.portal.url" -}}
{{- printf "%s://higher-ed.portal.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Portal Host Match
*/}}
{{- define "higher-ed.portal.hostMatch" -}}
{{- printf "Host(`higher-ed.portal.%s`)" .Values.domain }}
{{- end }}

{{/*
Financial Aid API URL
*/}}
{{- define "higher-ed.financialAid.apiUrl" -}}
{{- printf "%s://financial-aid-higher-ed.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Financial Aid Host Match
*/}}
{{- define "higher-ed.financialAid.hostMatch" -}}
{{- printf "Host(`financial-aid-higher-ed.%s`)" .Values.domain }}
{{- end }}

{{/*
Housing Assignment API URL
*/}}
{{- define "higher-ed.housingAssignment.apiUrl" -}}
{{- printf "%s://housing-assignment-higher-ed.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Housing Assignment Host Match
*/}}
{{- define "higher-ed.housingAssignment.hostMatch" -}}
{{- printf "Host(`housing-assignment-higher-ed.%s`)" .Values.domain }}
{{- end }}

{{/*
Scholarship API URL
*/}}
{{- define "higher-ed.scholarship.apiUrl" -}}
{{- printf "%s://scholarship-higher-ed.%s" .Values.protocol .Values.domain }}
{{- end }}

{{/*
Scholarship Host Match
*/}}
{{- define "higher-ed.scholarship.hostMatch" -}}
{{- printf "Host(`scholarship-higher-ed.%s`)" .Values.domain }}
{{- end }}

{{/*
MCP Server Host Match
*/}}
{{- define "higher-ed.mcp.hostMatch" -}}
{{- printf "Host(`mcp-higher-ed.%s`)" .Values.domain }}
{{- end }}
