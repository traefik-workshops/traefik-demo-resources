{{- define "airlines.serviceDeployment" -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name }}-code
  namespace: {{ .root.Values.namespace }}
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
  namespace: {{ .root.Values.namespace }}
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
              echo "🚀 Starting {{ .name | title }} service..."
              # Copy files to a writable location
              cp /shared/base_service.py /app/
              cp /code/{{ .name }}_service.py /app/
              cd /app
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
        - name: app-dir
          emptyDir: {}
{{- end -}}
