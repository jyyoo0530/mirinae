#!/usr/bin/env bash

kubectl create namespace mongodb

kubectl apply -f ./helm/mongodb/local_storageclass.yaml

#(Optional) remove all data
sudo rm -rf /database/mongodb

#(Optional) In case of cold running
for i in 1 2 3
do
  sudo mkdir -p /database/mongodb/db$i
  sudo chmod 777 /database/mongodb/db$i
done

kubectl apply -f ./helm/mongodb/mongo_pv.yaml

kubectl apply -f ./helm/mongodb/sidecar/mongo_statefulset.yaml
kubectl wait statefulset/mongo --for=condition=Ready --timeout=100s -n mongodb

kubectl exec -ti mongo-0 mongo -n mongodb
config={_id:"rs0", members: [{_id:0, host: "mongo-0.mongo:27017"}, {_id:1, host: "mongo-1.mongo:27017"}, {_id:2, host: "mongo-2.mongo:27017"}]}
rs.initiate(config)
exit
kubectl describe pod -n mongodb mongo-0 | grep IP & kubectl describe pod -n mongodb mongo-1 | grep IP & kubectl describe pod -n mongodb mongo-2 | grep IP
mongo mongodb://10.244.0.36:27017
# turn on authentication

# add admin
db.createUser({user:"admin",pwd:"admin",roles:["root"],mechanisms:["SCRAM-SHA-1"]})
# add vaultuser
db.createUser({
  user:"vaultuser",
  pwd:"vaultuser",
  roles:[{
    role:"readWrite",
    db:"vault"
  }],
  mechanisms:[
  "SCRAM-SHA-1"]
})
----------------
kubectl delete -f ./helm/mongodb/sidecar/mongo_statefulset.yaml
kubectl delete pvc --all -A
kubectl delete pv --all -A
