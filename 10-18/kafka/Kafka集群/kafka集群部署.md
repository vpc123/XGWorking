## StatefulSet在ZooKeeper和Kafka的实践


特别说明:因为搜集的文档较多，所以我们在使用时应该注意到的是最终的部署文档目录为FK。
在FK下包含了项目部署所需的所有文档，但是同时需要注意的是我们在部署时有些参数同样需要进行修改还有存储配置需要进行命名指定的操作，佛则可能出现的就是操作出现不可预料的问题。


关于验证：我们在部署完成后进行了测试验证的操作，对于文件中使用的镜像，需要访问国外的镜像仓库，所以我们需要下载下来后在进行名命名修改。

NFS的问题
建立zk集群的时候总是发现myid绑定一个id,先describe pod确认每个绑定不同的pvc,然后就确认是pv创建的问题，pv创建不能直接挂在一个大的存储上面，因为大家最后的目录相同/var/lib/zookeeper/data目录，所以无论哪个pvc挂上去都是同样的目录,解决办法，建立不同的存储挂载目录，然后分别挂载pv
建立pv的时候，指明storageClassName.

我们创建pv.yaml
还有pvc.yaml文件用于申请存储资源，将来作为zookeeper还有kafka的资源存储。

Kafka验证说明：
使用到的文件有
1  pv.yaml
2  pvc.yaml
3  zk.yaml
4  kafka.yaml
5  PZK.sh(zk集群验证)
6  SZK.sh(暴露zk服务)
7  kafka.yaml



kafka集群验证:

    root@kafka-0:/opt/kafka/config# kafka-topics.sh --create \
    > --topic test \
    > --zookeeper zoo-0.zk.default.svc.cluster.local:2181,zoo-1.zk.default.svc.cluster.local:2181,zoo-2.zk.default.svc.cluster.local:2181 \
    > --partitions 3 \
    > --replication-factor 2
    
    Created topic "test".


kafka测试验证:

    root@kafka-0:/opt/kafka/config# kafka-console-consumer.sh --topic test --bootstrap-server localhost:9093
    
    root@kafka-1:/# kafka-console-producer.sh --topic test --broker-list localhost:9093 
    I like kafka
    hello world

    #在消费者侧显示为：
    I like kafka
    hello world


参考测试:https://cloud.tencent.com/developer/article/1005492




在项目目录下我们可以看到具体的文件存在，至于要在集群中进行执行验证就可以了。



参考：
https://jicki.me/kubernetes/2016/11/04/kubernetes-application.html

https://www.cnblogs.com/ericnie/p/8562561.html



https://github.com/kubernetes/contrib/blob/master/statefulsets/zookeeper/zookeeper.yaml