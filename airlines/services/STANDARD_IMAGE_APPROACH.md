# Using Standard Python Image Instead of Custom Docker Image

## The Problem with Custom Images

Building `airlines-stateful-api:v0.1.0` requires:
- ❌ Docker registry access to push
- ❌ Building the image
- ❌ Managing image versions
- ❌ Pulling images in Kubernetes

## The Better Solution: Use Standard Python Image

Just use `python:3.11-slim` (already public!) and mount your code as ConfigMaps.

---

## How It Works

### Current Approach (Custom Image):
```yaml
containers:
  - name: api
    image: airlines-stateful-api:v0.1.0  # ← Need to build & push this!
    command: ["python", "flights_service.py"]
```

### Better Approach (Standard Image + ConfigMap):
```yaml
containers:
  - name: api
    image: python:3.11-slim  # ← Already exists publicly!
    command: ["sh", "-c"]
    args:
      - |
        pip install flask flask-cors
        python /app/flights_service.py
    volumeMounts:
      - name: service-code
        mountPath: /app
      - name: api-data
        mountPath: /api
volumes:
  - name: service-code
    configMap:
      name: flights-service-code  # ← Your Python scripts!
  - name: api-data
    configMap:
      name: flights-data          # ← Your data!
```

---

## Step-by-Step Implementation

### 1. Create ConfigMap with Python Code

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: flights-service-code
data:
  base_service.py: |
    # Paste contents of base_service.py here
    
  flights_service.py: |
    # Paste contents of flights_service.py here
    
  requirements.txt: |
    flask==3.0.0
    flask-cors==4.0.0
```

### 2. Update Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flights-app
spec:
  template:
    spec:
      initContainers:
        # Install dependencies once
        - name: install-deps
          image: python:3.11-slim
          command: ["pip", "install", "-r", "/app/requirements.txt", "--target", "/deps"]
          volumeMounts:
            - name: service-code
              mountPath: /app
            - name: python-deps
              mountPath: /deps
      
      containers:
        - name: api
          image: python:3.11-slim
          env:
            - name: PYTHONPATH
              value: "/deps"
          command: ["python", "/app/flights_service.py"]
          volumeMounts:
            - name: service-code
              mountPath: /app
            - name: api-data
              mountPath: /api
            - name: python-deps
              mountPath: /deps
          ports:
            - containerPort: 3000
      
      volumes:
        - name: service-code
          configMap:
            name: flights-service-code
        - name: api-data
          configMap:
            name: flights-data
        - name: python-deps
          emptyDir: {}
```

---

## Even Simpler: Install at Runtime

If you don't mind a slightly longer startup:

```yaml
containers:
  - name: api
    image: python:3.11-slim
    command: ["sh", "-c"]
    args:
      - |
        echo "Installing dependencies..."
        pip install --quiet flask==3.0.0 flask-cors==4.0.0
        echo "Starting service..."
        cd /app
        python flights_service.py
    volumeMounts:
      - name: service-code
        mountPath: /app
      - name: api-data
        mountPath: /api
```

---

## Complete Example for Flights Service

Create this file: `helm/templates/flights/stateful-deployment.yaml`

```yaml
---
# ConfigMap with service code
apiVersion: v1
kind: ConfigMap
metadata:
  name: flights-service-code
  namespace: airlines
data:
  base_service.py: |
{{- .Files.Get "services/base_service.py" | nindent 4 }}

  flights_service.py: |
{{- .Files.Get "services/flights_service.py" | nindent 4 }}

---
# Deployment using standard Python image
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flights-app-stateful
  namespace: airlines
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flights-app-stateful
  template:
    metadata:
      labels:
        app: flights-app-stateful
    spec:
      containers:
        - name: api
          image: python:3.11-slim
          command: ["sh", "-c"]
          args:
            - |
              pip install --quiet flask==3.0.0 flask-cors==4.0.0
              cd /app
              python flights_service.py
          ports:
            - containerPort: 3000
          volumeMounts:
            - name: service-code
              mountPath: /app
            - name: api-data
              mountPath: /api
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
      volumes:
        - name: service-code
          configMap:
            name: flights-service-code
        - name: api-data
          configMap:
            name: flights-data
```

---

## Advantages

✅ **No custom image needed** - Use public `python:3.11-slim`  
✅ **No registry access needed** - No push/pull of custom images  
✅ **Easy updates** - Just update the ConfigMap  
✅ **Version control** - Code changes tracked in Git  
✅ **Faster iteration** - Change ConfigMap, restart pod  
✅ **Simpler CI/CD** - No image building step  

---

## To Deploy

1. **Add ConfigMap** with your Python code
2. **Update deployment** to use `python:3.11-slim`
3. **Apply changes**:
   ```bash
   cd /Users/zaidalbirawi/dev/ai-demo
   terraform apply -auto-approve
   ```

4. **Watch it start**:
   ```bash
   kubectl logs -f -n airlines flights-app-stateful-xxxxx
   # You'll see:
   # Installing dependencies...
   # Starting service...
   # Starting Flights service on port 3000
   # Loaded 20 initial records
   ```

5. **Test it**:
   ```bash
   kubectl port-forward -n airlines svc/flights-app-stateful 3000:3000
   curl http://localhost:3000/health
   curl -X POST http://localhost:3000/flights -d '{"flight_id":"FL999",...}'
   ```

---

## Why This is Better

| Aspect | Custom Image | Standard Image + ConfigMap |
|--------|--------------|---------------------------|
| Build time | Yes (minutes) | No |
| Registry access | Required | Not needed |
| Image size | ~236MB | ~140MB (Python slim) |
| Updates | Rebuild & push | Update ConfigMap |
| Code visibility | Hidden in image | Visible in K8s |
| Debugging | Extract from image | Read ConfigMap |
| Startup time | Fast | +5-10s (pip install) |
| Best for | Production | Development & Demos |

---

## Summary

You're absolutely right! We don't need a custom Docker image. We can:

1. Use standard `python:3.11-slim` image
2. Mount Python scripts via ConfigMap  
3. Install dependencies at startup (`pip install`)
4. Run the service directly

This is **much simpler** and **doesn't require any image building or registry access**!

Want me to create the complete Helm templates for this approach?
