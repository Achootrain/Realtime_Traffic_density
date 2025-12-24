
### 0 Build local images
```bash
docker build -t spark-application:dev2 ./spark
docker build -t kafka-producer:dev ./kafka
docker build -t minio-local:dev ./minio
```


### 1 Install Spark Operator
```bash
helm repo add --force-update spark-operator https://kubeflow.github.io/spark-operator
helm repo update

kubectl create namespace traffic
kubectl apply ./k8s/spark-operator-complete-rbac.yaml -n traffic
helm upgrade spark-operator-1 spark-operator/spark-operator --namespace traffic --set sparkJobNamespace=traffic --set watchNamespace=traffic --set webhook.enable=true


```

If needed to edit the controller namespace:
```bash
kubectl edit deployment spark-operator-1-controller -n traffic
```

Restart operator (optional):
```bash
helm upgrade spark-operator-1 spark-operator/spark-operator --namespace traffic --set watchNamespace=traffic
```

### 2 Start Kafka and Producer
```bash
kubectl apply -f ./k8s/kafka.yaml
kubectl apply -f ./k8s/producer-deployment.yaml
```

### 3 Start TimescaleDB
```bash
kubectl apply -f ./k8s/timescaledb.yaml -n traffic
kubectl apply -f ./k8s/grafana.yaml -n traffic
```

Initialize schema (use your actual pod name):
```bash
# Find the pod name
kubectl get pods -n traffic


kubectl cp /home/ubuntu/timescaledb/init.sql traffic/timescaledb-0:/tmp/init.sql

# run init script
kubectl exec timescaledb-0 -n traffic -- psql -U postgres -d traffic -f /tmp/init.sql
```

### 4 Submit Spark Application
`spark-realtime-app.yaml`: writes to TimescaleDB

```bash
kubectl apply -f ./k8s/spark-realtime-app.yaml -n traffic
```

### 5 Verify
```bash
kubectl port-forward svc/grafana 3000:3000 -n traffic

# Pods
kubectl get pods -n traffic

# SparkApplication status
kubectl describe sparkapplication spark-realtime-python -n traffic

# Logs
kubectl logs spark-realtime-python-driver -n traffic

# TimescaleDB check (replace pod)
kubectl exec -n traffic <timescaledb-pod> -- psql -U postgres -d traffic -c "SELECT COUNT(*) FROM traffic_metrics;"
```

### 6 Cleanup
```bash
chmod +x /home/ubuntu/clean.sh
/home/ubuntu/clean.sh

kubectl delete sparkapplication spark-realtime-python -n traffic
kubectl delete deployment grafana -n traffic
kubectl delete statefulset timescaledb -n traffic


```

