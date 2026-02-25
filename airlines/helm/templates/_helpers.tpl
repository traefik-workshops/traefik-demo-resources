{{/*
Expand the name of the chart.
*/}}
{{- define "airlines.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "airlines.fullname" -}}
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
{{- define "airlines.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "airlines.labels" -}}
helm.sh/chart: {{ include "airlines.chart" . }}
{{ include "airlines.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "airlines.selectorLabels" -}}
app.kubernetes.io/name: {{ include "airlines.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Domain helper
*/}}
{{- define "airlines.domain" -}}
{{- $domain := .Values.domain -}}
{{- if .Values.global -}}
  {{- if not (kindIs "invalid" .Values.global.domain) -}}
    {{- $domain = .Values.global.domain -}}
  {{- end -}}
{{- end -}}
{{- $domain }}
{{- end }}

{{/*
Domain Match helper
*/}}
{{- define "airlines.domainMatch" -}}
{{- printf "Host(`%s`)" (include "airlines.domain" .) }}
{{- end }}

{{/*
Flights API URL
*/}}
{{- define "airlines.flights.apiUrl" -}}
https://flights.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.flights.hostMatch" -}}
Host(`flights.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Bookings API URL
*/}}
{{- define "airlines.bookings.apiUrl" -}}
https://bookings.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.bookings.hostMatch" -}}
Host(`bookings.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Tickets API URL
*/}}
{{- define "airlines.tickets.apiUrl" -}}
https://tickets.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.tickets.hostMatch" -}}
Host(`tickets.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Passengers API URL
*/}}
{{- define "airlines.passengers.apiUrl" -}}
https://passengers.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.passengers.hostMatch" -}}
Host(`passengers.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Loyalty API URL
*/}}
{{- define "airlines.loyalty.apiUrl" -}}
https://loyalty.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.loyalty.hostMatch" -}}
Host(`loyalty.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Checkin API URL
*/}}
{{- define "airlines.checkin.apiUrl" -}}
https://checkin.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.checkin.hostMatch" -}}
Host(`checkin.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Baggage API URL
*/}}
{{- define "airlines.baggage.apiUrl" -}}
https://baggage.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.baggage.hostMatch" -}}
Host(`baggage.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Pricing API URL
*/}}
{{- define "airlines.pricing.apiUrl" -}}
https://pricing.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.pricing.hostMatch" -}}
Host(`pricing.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Partners API URL
*/}}
{{- define "airlines.partners.apiUrl" -}}
https://partners.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.partners.hostMatch" -}}
Host(`partners.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Notifications API URL
*/}}
{{- define "airlines.notifications.apiUrl" -}}
https://notifications.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.notifications.hostMatch" -}}
Host(`notifications.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Ancillaries API URL
*/}}
{{- define "airlines.ancillaries.apiUrl" -}}
https://ancillaries.{{ include "airlines.domain" . }}
{{- end }}

{{- define "airlines.ancillaries.hostMatch" -}}
Host(`ancillaries.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
Portal Host Match
*/}}
{{- define "airlines.portal.hostMatch" -}}
Host(`portal.{{ include "airlines.domain" . }}`)
{{- end }}

{{/*
OIDC URL
*/}}
{{- define "airlines.oidc.issuerUrl" -}}
{{ .Values.keycloak.oidc.issuerUrl }}
{{- end }}
{{- define "airlines.oidc.jwksUrl" -}}
{{ .Values.keycloak.oidc.issuerUrl }}/protocol/openid-connect/certs
{{- end }}

{{- define "airlines.serviceDeployment" -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name }}-code
  labels:
    app: {{ .name }}-app
    component: {{ .name }}
data:
  {{ .name }}_service.py: |
{{ .root.Files.Get (printf "services/%s_service.py" .name) | indent 4 }}

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}-app
  labels:
    {{- include "airlines.labels" .root | nindent 4 }}
    component: {{ .name }}
spec:
  replicas: {{ .root.Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .name }}-app
  template:
    metadata:
      labels:
        app: {{ .name }}-app
        component: api
    spec:
      containers:
        - name: api
          image: python:3.11-slim
          command: ["sh", "-c"]
          args:
            - |
              echo "📦 Installing dependencies..."
              pip install --quiet -r /shared/requirements.txt
              echo "✅ Dependencies installed"
              
              echo "🌱 Seeding data..."
              python /shared/seed_data.py /api/api.json /app/api.json
              
              echo "🚀 Starting {{ .name | title }} service..."
              # Copy files to a writable location
              cp /shared/base_service.py /app/
              cp /code/{{ .name }}_service.py /app/
              cd /app
              export DATA_FILE=/app/api.json
              python {{ .name }}_service.py
          ports:
            - containerPort: 3000
              name: http
          volumeMounts:
            - name: shared-code
              mountPath: /shared
            - name: service-code
              mountPath: /code
            - name: api-data
              mountPath: /api
            - name: openapi-spec
              mountPath: /public
              readOnly: true
            - name: app-dir
              mountPath: /app
          env:
            - name: PYTHONUNBUFFERED
              value: "1"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            {{- toYaml .root.Values.resources | nindent 12 }}
      volumes:
        - name: shared-code
          configMap:
            name: airlines-shared-code
        - name: service-code
          configMap:
            name: {{ .name }}-code
        - name: api-data
          configMap:
            name: {{ .name }}-data
        - name: openapi-spec
          configMap:
            name: {{ .name }}-openapi
        - name: app-dir
          emptyDir: {}
{{- end -}}
