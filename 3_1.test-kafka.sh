#!/usr/bin/env bash


# create single persistent kafka cluster for test
kubectl apply -f  ./helm/kafkaoperator/test/kafka-persistent-single.yaml -n kafka
kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n kafka

# create producer
kubectl -n kafka run kafka-producer -ti \
--image=quay.io/strimzi/kafka:0.21.1-kafka-2.7.0 \
--rm=true \
--restart=Never \
-- bin/kafka-console-producer.sh \
--broker-list my-cluster-kafka-bootstrap:9092 \
--topic my-topic

# create consumer
kubectl -n kafka run kafka-consumer -ti \
--image=quay.io/strimzi/kafka:0.21.1-kafka-2.7.0 \
--rm=true \
--restart=Never \
-- bin/kafka-console-consumer.sh \
--bootstrap-server my-cluster-kafka-bootstrap:9092 \
--topic my-topic \
--from-beginning