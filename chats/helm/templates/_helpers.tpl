{{/*
Expand the name of the chart.
*/}}
{{- define "chats.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "chats.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chats.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chats.labels" -}}
helm.sh/chart: {{ include "chats.chart" . }}
{{ include "chats.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chats.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chats.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Keycloak JWKS URL
*/}}
{{- define "chats.keycloak.jwksUrl" -}}
{{- if .Values.keycloak.jwksUrl }}
{{- .Values.keycloak.jwksUrl }}
{{- else }}
{{- printf "https://keycloak.%s/realms/traefik/protocol/openid-connect/certs" .Values.domain }}
{{- end }}
{{- end }}

{{/*
Keycloak Issuer URL
*/}}
{{- define "chats.keycloak.issuerUrl" -}}
{{- if .Values.keycloak.issuerUrl }}
{{- .Values.keycloak.issuerUrl }}
{{- else }}
{{- printf "https://keycloak.%s/realms/traefik" .Values.domain }}
{{- end }}
{{- end }}

{{/*
NIM Topic Control Endpoint
*/}}
{{- define "chats.nim.topicControl.endpoint" -}}
{{- if .Values.nim.topicControl.endpoint }}
{{- .Values.nim.topicControl.endpoint }}
{{- else }}
{{- printf "https://%s-8000.proxy.runpod.net/v1/chat/completions" .Values.nim.topicControl.podId }}
{{- end }}
{{- end }}

{{/*
NIM Content Safety Endpoint
*/}}
{{- define "chats.nim.contentSafety.endpoint" -}}
{{- if .Values.nim.contentSafety.endpoint }}
{{- .Values.nim.contentSafety.endpoint }}
{{- else }}
{{- printf "https://%s-8000.proxy.runpod.net/v1/chat/completions" .Values.nim.contentSafety.podId }}
{{- end }}
{{- end }}

{{/*
NIM Jailbreak Detection Endpoint
*/}}
{{- define "chats.nim.jailbreakDetection.endpoint" -}}
{{- if .Values.nim.jailbreakDetection.endpoint }}
{{- .Values.nim.jailbreakDetection.endpoint }}
{{- else }}
{{- printf "https://%s-8000.proxy.runpod.net/v1/classify" .Values.nim.jailbreakDetection.podId }}
{{- end }}
{{- end }}

{{/*
Portal URL
*/}}
{{- define "chats.portal.url" -}}
{{- if .Values.portal.url }}
{{- .Values.portal.url }}
{{- else }}
{{- printf "https://chats.portal.%s" .Values.domain }}
{{- end }}
{{- end }}

{{/*
Portal Host Match
*/}}
{{- define "chats.portal.hostMatch" -}}
{{- if .Values.portal.hostMatch }}
{{- .Values.portal.hostMatch }}
{{- else }}
{{- printf "Host(`chats.portal.%s`)" .Values.domain }}
{{- end }}
{{- end }}

{{/*
OpenAI API URL
*/}}
{{- define "chats.openai.apiUrl" -}}
{{- if .Values.openai.apiUrl }}
{{- .Values.openai.apiUrl }}
{{- else }}
{{- printf "https://openai.%s" .Values.domain }}
{{- end }}
{{- end }}

{{/*
OpenAI Host Match
*/}}
{{- define "chats.openai.hostMatch" -}}
{{- if .Values.openai.hostMatch }}
{{- .Values.openai.hostMatch }}
{{- else }}
{{- printf "Host(`openai.%s`)" .Values.domain }}
{{- end }}
{{- end }}

{{/*
OpenAI Host Match Completions
*/}}
{{- define "chats.openai.hostMatchCompletions" -}}
{{- if .Values.openai.hostMatchCompletions }}
{{- .Values.openai.hostMatchCompletions }}
{{- else }}
{{- printf "Host(`openai.%s`) && PathPrefix(`/v1/chat/completions`)" .Values.domain }}
{{- end }}
{{- end }}

{{/*
GPT-OSS External Name
*/}}
{{- define "chats.gptOss.externalName" -}}
{{- if .Values.gptOss.externalName }}
{{- .Values.gptOss.externalName }}
{{- else }}
{{- printf "%s-8000.proxy.runpod.net" .Values.gptOss.podId }}
{{- end }}
{{- end }}

{{/*
GPT-OSS API URL
*/}}
{{- define "chats.gptOss.apiUrl" -}}
{{- if .Values.gptOss.apiUrl }}
{{- .Values.gptOss.apiUrl }}
{{- else }}
{{- printf "https://gpt.%s" .Values.domain }}
{{- end }}
{{- end }}

{{/*
GPT-OSS Host Match
*/}}
{{- define "chats.gptOss.hostMatch" -}}
{{- if .Values.gptOss.hostMatch }}
{{- .Values.gptOss.hostMatch }}
{{- else }}
{{- printf "Host(`gpt.%s`)" .Values.domain }}
{{- end }}
{{- end }}

{{/*
GPT-OSS Host Match Completions
*/}}
{{- define "chats.gptOss.hostMatchCompletions" -}}
{{- if .Values.gptOss.hostMatchCompletions }}
{{- .Values.gptOss.hostMatchCompletions }}
{{- else }}
{{- printf "Host(`gpt.%s`) && PathPrefix(`/v1/chat/completions`)" .Values.domain }}
{{- end }}
{{- end }}

{{/*
Check if component is enabled
*/}}
{{- define "chats.component.enabled" -}}
{{- $component := . -}}
{{- $enabled := false -}}
{{- range $.Values.components -}}
{{- if eq . $component -}}
{{- $enabled = true -}}
{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end }}
