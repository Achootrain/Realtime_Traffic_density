#!/bin/bash

NAMESPACE="traffic"
K8S_DIR="/home/ubuntu/k8s"

echo "===== CLEANING SPARK JOBS ====="
kubectl delete -f $K8S_DIR/spark-batch-app.yaml -n $NAMESPACE --ignore-not-found
kubectl delete -f $K8S_DIR/spark-realtime-app.yaml -n $NAMESPACE --ignore-not-found
kubectl delete -f $K8S_DIR/spark-hdfs-reader.yaml -n $NAMESPACE --ignore-not-found
kubectl delete sparkapplication spark-s3-glacier -n traffic --ignore-not-found

echo "===== CLEANING HDFS ====="
kubectl delete -f $K8S_DIR/hdfs-cluster.yaml --ignore-not-found

echo "===== CLEANING KAFKA / PRODUCER ====="
kubectl delete -f $K8S_DIR/producer-deployment.yaml -n $NAMESPACE --ignore-not-found
kubectl delete -f $K8S_DIR/kafka.yaml -n $NAMESPACE --ignore-not-found

echo "===== CLEANING TIMESCALEDB ====="
kubectl delete -f $K8S_DIR/timescaledb.yaml -n $NAMESPACE --ignore-not-found

echo "===== CLEANING GRAFANA ====="
kubectl delete -f $K8S_DIR/grafana.yaml -n $NAMESPACE --ignore-not-found

echo "===== CLEANING SPARK OPERATOR ====="
kubectl delete deployment spark-operator-1-webhook -n $NAMESPACE --ignore-not-found
kubectl delete deployment spark-operator-1-controller -n $NAMESPACE --ignore-not-found

echo "===== CLEANING NAMESPACE (OPTIONAL) ====="
# uncomment nếu muốn xóa luôn namespace
# kubectl delete namespace $NAMESPACE

echo "===== DONE ====="
