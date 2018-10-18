root@kafka-0:/opt/kafka/config# kafka-topics.sh --create \
> --topic test \
> --zookeeper zoo-0.zk.default.svc.cluster.local:2181,zoo-1.zk.default.svc.cluster.local:2181,zoo-2.zk.default.svc.cluster.local:2181 \
> --partitions 3 \
> --replication-factor 2

Created topic "test".



root@kafka-0:/opt/kafka/config# kafka-console-consumer.sh --topic test --bootstrap-server localhost:9093

root@kafka-1:/# kafka-console-producer.sh --topic test --broker-list localhost:9093                                                             
I like kafka
hello world

#在消费者侧显示为：
I like kafka
hello world
