{{/*
Validate that at least one component is selected
*/}}
{{- define "chats.validateComponents" -}}
{{- if not .Values.components }}
{{- fail "Error: No components selected. Please enable at least one component (openai or gpt-oss) in values.yaml" }}
{{- end }}
{{- if eq (len .Values.components) 0 }}
{{- fail "Error: No components selected. Please enable at least one component (openai or gpt-oss) in values.yaml" }}
{{- end }}
{{- end }}

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
{{- printf "%s://keycloak.traefik.%s/realms/traefik/protocol/openid-connect/certs" .Values.protocol .Values.domain }}
{{- end }}
{{- end }}

{{/*
Keycloak Issuer URL
*/}}
{{- define "chats.keycloak.issuerUrl" -}}
{{- if .Values.keycloak.issuerUrl }}
{{- .Values.keycloak.issuerUrl }}
{{- else }}
{{- printf "%s://keycloak.traefik.%s/realms/traefik" .Values.protocol .Values.domain }}
{{- end }}
{{- end }}

{{/*
NIM Topic Control Endpoint
*/}}
{{- define "chats.middlewares.llmGuards.topicControlGuard.endpoint" -}}
{{- if .Values.middlewares.llmGuards.topicControlGuard.endpoint }}
{{- .Values.middlewares.llmGuards.topicControlGuard.endpoint }}
{{- else }}
{{- printf "%s://%s-8000.proxy.runpod.net/v1/chat/completions" .Values.protocol .Values.middlewares.llmGuards.topicControlGuard.podId }}
{{- end }}
{{- end }}

{{/*
NIM Content Safety Endpoint
*/}}
{{- define "chats.middlewares.llmGuards.contentSafetyGuard.endpoint" -}}
{{- if .Values.middlewares.llmGuards.contentSafetyGuard.endpoint }}
{{- .Values.middlewares.llmGuards.contentSafetyGuard.endpoint }}
{{- else }}
{{- printf "%s://%s-8000.proxy.runpod.net/v1/chat/completions" .Values.protocol .Values.middlewares.llmGuards.contentSafetyGuard.podId }}
{{- end }}
{{- end }}

{{/*
NIM Jailbreak Detection Endpoint
*/}}
{{- define "chats.middlewares.llmGuards.jailbreakDetectionGuard.endpoint" -}}
{{- if .Values.middlewares.llmGuards.jailbreakDetectionGuard.endpoint }}
{{- .Values.middlewares.llmGuards.jailbreakDetectionGuard.endpoint }}
{{- else }}
{{- printf "%s://%s-8000.proxy.runpod.net/v1/classify" .Values.protocol .Values.middlewares.llmGuards.jailbreakDetectionGuard.podId }}
{{- end }}
{{- end }}

{{/*
Granite Guard Endpoint
*/}}
{{- define "chats.middlewares.llmGuards.graniteGuard.endpoint" -}}
{{- if .Values.middlewares.llmGuards.graniteGuard.endpoint }}
{{- .Values.middlewares.llmGuards.graniteGuard.endpoint }}
{{- else }}
{{- printf "%s://%s-8000.proxy.runpod.net/v1/classify" .Values.protocol .Values.middlewares.llmGuards.graniteGuard.podId }}
{{- end }}
{{- end }}

{{/*
Portal URL
*/}}
{{- define "chats.portal.url" -}}
{{- if .Values.portal.url }}
{{- .Values.portal.url }}
{{- else }}
{{- printf "%s://chats.portal.%s" .Values.protocol .Values.domain }}
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
{{- printf "%s://openai.%s" .Values.protocol .Values.domain }}
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
{{- printf "%s://gpt.%s" .Values.protocol .Values.domain }}
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
