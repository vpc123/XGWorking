for i in 0 1 2; do kubectl exec zk-$i -- hostname; done

zk-0
zk-1
zk-2

for i in 0 1 2; do echo "myid zk-$i";kubectl exec zk-$i -- cat /var/lib/zookeeper/data/myid; done

myid zk-0
myid zk-1
myid zk-2

for i in 0 1 2; do kubectl exec zk-$i -- hostname -f; done
zk-0.zk-hs.default.svc.cluster.local
zk-1.zk-hs.default.svc.cluster.local
zk-2.zk-hs.default.svc.cluster.local
