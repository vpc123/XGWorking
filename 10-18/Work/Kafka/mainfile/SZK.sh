kubectl label pod zk-0 zkInst=0                                                                          
kubectl label pod zk-1 zkInst=1       
kubectl label pod zk-2 zkInst=2
                                                                      
kubectl expose po zk-0 --port=2181 --target-port=2181 --name=zk-0 --selector=zkInst=0 --type=NodePort
kubectl expose po zk-1 --port=2181 --target-port=2181 --name=zk-1 --selector=zkInst=1 --type=NodePort
kubectl expose po zk-2 --port=2181 --target-port=2181 --name=zk-2 --selector=zkInst=2 --type=NodePort
