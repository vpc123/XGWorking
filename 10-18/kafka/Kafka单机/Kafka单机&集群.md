Kubernetes部署Kafka集群

一、单节点Kafka

要搭建Kafka集群，还是要从单节点开始。

1.创建Zookeeper服务zookeeper-svc.yaml和zookeeper-deployment.yaml，用kubectl create -f创建：

zookeeper-svc.yaml文件

    apiVersion: v1
    kind: Service
    metadata:
      labels:
    app: zookeeper-service
      name: zookeeper-service
    spec:
      ports:
      - name: zookeeper-port
    port: 2181
    targetPort: 2181
      selector:
    app: zookeeper



zookeeper-deployment.yaml文件：

    apiVersion: extensions/v1beta1
    kind: Deployment
    metadata:
      labels:
    app: zookeeper
      name: zookeeper
    spec:
      replicas: 1
      template:
    metadata:
      labels:
    app: zookeeper
    spec:
      containers:
      - image: wurstmeister/zookeeper
    imagePullPolicy: IfNotPresent
    name: zookeeper
    ports:
    - containerPort: 2181



2.等pod跑起来，service的endpoint配置成功后，就可以继续创建kafka的kafka-svc.yaml和kafka-deployment.yaml了：

kafka的kafka-svc.yaml

    apiVersion: v1
    kind: Service
    metadata:
      name: kafka-service
      labels:
    app: kafka
    spec:
      type: NodePort
      ports:
      - port: 9092
    name: kafka-port
    targetPort: 9092
    nodePort: 30092
    protocol: TCP
      selector:
    app: kafka

kafka-deployment.yaml

    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: kafka-deployment
    spec:
      replicas: 1
      selector:
    matchLabels:
      name: kafka
      template:
    metadata:
      labels:
    name: kafka
    app: kafka
    spec:
      containers:
      - name: kafka
    image: wurstmeister/kafka
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 9092
    env:
    - name: KAFKA_ADVERTISED_PORT
      value: "9092"
    - name: KAFKA_ADVERTISED_HOST_NAME
      value: "[kafka的service的clusterIP]"
    - name: KAFKA_ZOOKEEPER_CONNECT
      value: [zookeeper的service的clusterIP]:2181
    - name: KAFKA_BROKER_ID
      value: "1"


clusterIP通过kubectl get svc进行查看。KAFKA_ZOOKEEPER_CONNECT的值也可以改为zookeeper-service:2181。

3.创建后，需要对服务进行测试。参考了https://blog.csdn.net/boling_cavalry/article/details/78309050的方法。

在此之前，针对虚拟化的Kafka，需要先执行下面的命令以进入容器：

    kubectl exec -it [Kafka的pod名称] /bin/bash

进入容器后，Kafka的命令存储在opt/kafka/bin目录下，用cd命令进入：

    cd opt/kafka/bin

后面的操作就跟上面的博客中写的类似了。针对单节点Kafka，需要将同一个节点作为生产者和消费者。执行命令如下：

    kafka-console-producer.sh --broker-list [kafka的service的clusterIP]:9092 --topic test

运行正常的话，下方会出现>标记以提示输入消息。这样这个终端就成为了生产者。

另外打开一个linux终端，执行相同的命令进入容器。这次将这个终端作为消费者。注意，上面的博客中写的创建消费者的方法在新版的Kafka中已经改变，需要执行下面的命令：

    kafka-console-consumer.sh --bootstrap-server [kafka的service的clusterIP]:9092 --topic test --from-beginning

之后，在生产者输入信息，查看消费者是否能够接收到。如果接收到，说明运行成功。

最后，还可以执行下面的命令以测试列出所有的消息主题：

    kafka-topics.sh --list --zookeeper [zookeeper的service的clusterIP]:2181


注意，有时需要用Kafka的端口，有时需要用Zookeeper的端口，应注意区分。

二、多节点Kafka集群

单节点服务运行成功后，就可以尝试增加Kafka的节点以建立集群。我的Kubernetes集群包含3个节点，所以我搭建的Kafka集群也包含3个节点，分别运行在三台机器上。

1.搭建Zookeeper集群

创建zookeeper的yaml文件zookeeper-svc2.yaml和zookeeper-deployment2.yaml如下：

zookeeper-svc2.yaml文件

    apiVersion: v1
    kind: Service
    metadata:
      name: zoo1
      labels:
    app: zookeeper-1
    spec:
      ports:
      - name: client
    port: 2181
    protocol: TCP
      - name: follower
    port: 2888
    protocol: TCP
      - name: leader
    port: 3888
    protocol: TCP
      selector:
    app: zookeeper-1
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: zoo2
      labels:
    app: zookeeper-2
    spec:
      ports:
      - name: client
    port: 2181
    protocol: TCP
      - name: follower
    port: 2888
    protocol: TCP
      - name: leader
    port: 3888
    protocol: TCP
      selector:
    app: zookeeper-2
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: zoo3
      labels:
    app: zookeeper-3
    spec:
      ports:
      - name: client
    port: 2181
    protocol: TCP
      - name: follower
    port: 2888
    protocol: TCP
      - name: leader
    port: 3888
    protocol: TCP
      selector:
    app: zookeeper-3


zookeeper-deployment2.yaml文件：

    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: zookeeper-deployment-1
    spec:
      replicas: 1
      selector:
    matchLabels:
      app: zookeeper-1
      name: zookeeper-1
      template:
    metadata:
      labels:
    app: zookeeper-1
    name: zookeeper-1
    spec:
      containers:
      - name: zoo1
    image: digitalwonderland/zookeeper
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 2181
    env:
    - name: ZOOKEEPER_ID
      value: "1"
    - name: ZOOKEEPER_SERVER_1
      value: zoo1
    - name: ZOOKEEPER_SERVER_2
      value: zoo2
    - name: ZOOKEEPER_SERVER_3
      value: zoo3
    ---
    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: zookeeper-deployment-2
    spec:
      replicas: 1
      selector:
    matchLabels:
      app: zookeeper-2
      name: zookeeper-2
      template:
    metadata:
      labels:
    app: zookeeper-2
    name: zookeeper-2
    spec:
      containers:
      - name: zoo2
    image: digitalwonderland/zookeeper
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 2181
    env:
    - name: ZOOKEEPER_ID
      value: "2"
    - name: ZOOKEEPER_SERVER_1
      value: zoo1
    - name: ZOOKEEPER_SERVER_2
      value: zoo2
    - name: ZOOKEEPER_SERVER_3
      value: zoo3
    ---
    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: zookeeper-deployment-3
    spec:
      replicas: 1
      selector:
    matchLabels:
      app: zookeeper-3
      name: zookeeper-3
      template:
    metadata:
      labels:
    app: zookeeper-3
    name: zookeeper-3
    spec:
      containers:
      - name: zoo3
    image: digitalwonderland/zookeeper
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 2181
    env:
    - name: ZOOKEEPER_ID
      value: "3"
    - name: ZOOKEEPER_SERVER_1
      value: zoo1
    - name: ZOOKEEPER_SERVER_2
      value: zoo2
    - name: ZOOKEEPER_SERVER_3
      value: zoo3


这里创建了3个deployment和3个service，一一对应。这样，三个实例都可以对外提供服务。

创建完成后，需要用kubectl logs查看一下三个Zookeeper的pod的日志，确保没有错误发生，并且在3个节点的日志中，有类似下面的语句，则表明Zookeeper集群已顺利搭建成功。

    2016-10-06 14:04:05,904 [myid:2] - INFO [QuorumPeer[myid=2]/0:0:0:0:0:0:0:0:2181:Leader@358] - LEADING - <br>LEADER ELECTION TOOK - 2613

2.搭建Kafka集群

同样创建3个deployment和3个service，编写kafka-svc2.yaml和kafka-deployment2.yaml如下：


apiVersion: v1
kind: Service
metadata:
  name: kafka-service-1
  labels:
    app: kafka-service-1
spec:
  type: NodePort
  ports:
  - port: 9092
    name: kafka-service-1
    targetPort: 9092
    nodePort: 30901
    protocol: TCP
  selector:
    app: kafka-service-1
---
    apiVersion: v1
    kind: Service
    metadata:
      name: kafka-service-2
      labels:
    app: kafka-service-2
    spec:
      type: NodePort
      ports:
      - port: 9092
    name: kafka-service-2
    targetPort: 9092
    nodePort: 30902
    protocol: TCP
      selector:
    app: kafka-service-2
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: kafka-service-3
      labels:
    app: kafka-service-3
    spec:
      type: NodePort
      ports:
      - port: 9092
    name: kafka-service-3
    targetPort: 9092
    nodePort: 30903
    protocol: TCP
      selector:
    app: kafka-service-3




deployment:

    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: kafka-deployment-1
    spec:
      replicas: 1
      selector:
    matchLabels:
      name: kafka-service-1
      template:
    metadata:
      labels:
    name: kafka-service-1
    app: kafka-service-1
    spec:
      containers:
      - name: kafka-1
    image: wurstmeister/kafka
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 9092
    env:
    - name: KAFKA_ADVERTISED_PORT
      value: "9092"
    - name: KAFKA_ADVERTISED_HOST_NAME
      value: [kafka-service1的clusterIP]
    - name: KAFKA_ZOOKEEPER_CONNECT
      value: zoo1:2181,zoo2:2181,zoo3:2181
    - name: KAFKA_BROKER_ID
      value: "1"
    - name: KAFKA_CREATE_TOPICS
      value: mytopic:2:1
    ---
    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: kafka-deployment-2
    spec:
      replicas: 1
      selector:
      selector:
    matchLabels:
      name: kafka-service-2
      template:
    metadata:
      labels:
    name: kafka-service-2
    app: kafka-service-2
    spec:
      containers:
      - name: kafka-2
    image: wurstmeister/kafka
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 9092
    env:
    - name: KAFKA_ADVERTISED_PORT
      value: "9092"
    - name: KAFKA_ADVERTISED_HOST_NAME
      value: [kafka-service2的clusterIP]
    - name: KAFKA_ZOOKEEPER_CONNECT
      value: zoo1:2181,zoo2:2181,zoo3:2181
    - name: KAFKA_BROKER_ID
      value: "2"
    ---
    kind: Deployment
    apiVersion: extensions/v1beta1
    metadata:
      name: kafka-deployment-3
    spec:
      replicas: 1
      selector:
      selector:
    matchLabels:
      name: kafka-service-3
      template:
    metadata:
      labels:
    name: kafka-service-3
    app: kafka-service-3
    spec:
      containers:
      - name: kafka-3
    image: wurstmeister/kafka
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 9092
    env:
    - name: KAFKA_ADVERTISED_PORT
      value: "9092"
    - name: KAFKA_ADVERTISED_HOST_NAME
      value: [kafka-service3的clusterIP]
    - name: KAFKA_ZOOKEEPER_CONNECT
      value: zoo1:2181,zoo2:2181,zoo3:2181
    - name: KAFKA_BROKER_ID
      value: "3"


在deployment1中执行了创建一个新topic的操作。

3.测试

测试方法基本同单集群的情况，这里就不赘述了。不同的是，这次可以将不同的节点作为生产者和消费者。

 

至此，Kubernetes的Kafka集群搭建就大功告成了！



参考网址：
https://www.cnblogs.com/00986014w/p/9561901.html