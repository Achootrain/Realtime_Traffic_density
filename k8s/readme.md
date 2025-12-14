
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

kubectl create namespace hugedata
kubectl apply ./k8s/spark-operator-complete-rbac.yaml -n hugedata
helm upgrade spark-operator-1 spark-operator/spark-operator --namespace hugedata --set sparkJobNamespace=hugedata --set watchNamespace=hugedata --set webhook.enable=true


```

If needed to edit the controller namespace:
```bash
kubectl edit deployment spark-operator-1-controller -n hugedata
```

Restart operator (optional):
```bash
helm upgrade spark-operator-1 spark-operator/spark-operator --namespace hugedata --set watchNamespace=hugedata
```

### 2 Start Kafka and Producer
```bash
kubectl apply -f ./k8s/kafka.yaml
kubectl apply -f ./k8s/producer-deployment.yaml
```

### 3 Start MinIO and Bucket
```bash
kubectl apply -f ./k8s/minio-deployment.yaml
kubectl apply -f ./k8s/minio-bucket.yaml
```

### 4 Start TimescaleDB
```bash
kubectl apply -f ./k8s/timescaledb.yaml -n hugedata
```

Initialize schema (use your actual pod name):
```bash
# Find the pod name
kubectl get pods -n hugedata


kubectl cp timescaledb/init.sql hugedata/timescaledb-0:/tmp/init.sql

# run init script
kubectl exec timescaledb-0 -n hugedata -- psql -U postgres -d traffic -f /tmp/init.sql
```

### 5 Submit Spark Applications
Two apps consume the same Kafka topic but with different consumer groups:
- `spark-minio-app.yaml`: group `spark-minio-group` (writes Parquet to MinIO)
- `spark-realtime-app.yaml`: group `spark-realtime-group` (writes to TimescaleDB)

```bash
kubectl apply -f ./k8s/spark-minio-app.yaml -n hugedata
kubectl apply -f ./k8s\spark-realtime-app.yaml -n hugedata
```

### 6 Verify
```bash
# Pods
kubectl get pods -n hugedata

# SparkApplication status
kubectl describe sparkapplication spark-pi-python -n hugedata
kubectl describe sparkapplication spark-realtime-python -n hugedata

# Logs
kubectl logs spark-pi-python-driver -n hugedata --tail=200
kubectl logs spark-realtime-python-driver -n hugedata --tail=200

# TimescaleDB check (replace pod)
kubectl exec -n hugedata <timescaledb-pod> -- psql -U postgres -d traffic -c "SELECT COUNT(*) FROM traffic_metrics;"
```

### 7 Cleanup
```bash
kubectl delete -f d:\Project1\Traffic_system\k8s\spark-realtime-app.yaml -n hugedata
kubectl delete -f d:\Project1\Traffic_system\k8s\spark-minio-app.yaml -n hugedata
kubectl delete -f d:\Project1\Traffic_system\k8s\producer-deployment.yaml
kubectl delete -f d:\Project1\Traffic_system\k8s\minio-bucket.yaml
kubectl delete -f d:\Project1\Traffic_system\k8s\minio-deployment.yaml
kubectl delete -f d:\Project1\Traffic_system\k8s\kafka.yaml
kubectl delete deployment --all -n hugedata
kubectl scale statefulset kafka -n hugedata --replicas=0
```

