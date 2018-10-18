## redis集群模式部署

### 三、StatefulSet简介

StatefulSet的概念非常重要，简单来说，其就是为了解决Pod重启、迁移后，Pod的IP、主机名等网络标识会改变而带来的问题。IP变化对于有状态的服务是难以接受的，如在Zookeeper集群的配置文件中，每个ZK节点都会记录其他节点的地址信息.

对于有状态服务，我们最好使用固定的网络标识（如域名信息）来标记节点，当然这也需要应用程序的支持（如Zookeeper就支持在配置文件中写入主机域名）。

StatefulSet基于Headless Service（即没有Cluster IP的Service）为Pod实现了稳定的网络标志（包括Pod的hostname和DNS Records），在Pod重新调度后也保持不变。同时，结合PV/PVC，StatefulSet可以实现稳定的持久化存储，就算Pod重新调度后，还是能访问到原先的持久化数据。



#### 部署流程
1. 创建NFS存储
1. 创建PV
1. 创建PVC
1. 创建Configmap
1. 创建headless服务
1. 创建Redis StatefulSet
1. 初始化Redis集群



1.创建NFS存储
创建NFS存储主要是为了给Redis提供稳定的后端存储，当Redis的Pod重启或迁移后，依然能获得原先的数据。这里，我们先要创建NFS，然后通过使用PV为Redis挂载一个远程的NFS路径。


安装NFS
由于硬件资源有限，我们可以在k8s-node2上搭建。执行如下命令安装NFS和rpcbind：

    #yum -y install nfs-utils rpcbind 



其中，NFS依靠远程过程调用(RPC)在客户端和服务器端路由请求，因此需要安装rpcbind服务。

然后，新增/etc/exports文件，用于设置需要共享的路径：

    /usr/local/k8s/redis/pv1 *(rw,all_squash)
    /usr/local/k8s/redis/pv2 *(rw,all_squash)
    /usr/local/k8s/redis/pv3 *(rw,all_squash)
    /usr/local/k8s/redis/pv4 *(rw,all_squash)
    /usr/local/k8s/redis/pv5 *(rw,all_squash)
    /usr/local/k8s/redis/pv6 *(rw,all_squash)


如上，rw表示读写权限；all_squash 表示客户机上的任何用户访问该共享目录时都映射成服务器上的匿名用户（默认为nfsnobody）；*表示任意主机都可以访问该共享目录，也可以填写指定主机地址，同时支持正则，如：



    /root/share/ 192.168.1.20 (rw,all_squash)
    /home/ljm/ *.gdfs.edu.cn (rw,all_squash)


由于我们打算创建一个6节点的Redis集群，所以共享了6个目录。当然，我们需要在k8s-node2上创建这些路径，并且为每个路径修改权限：


    chmod 777 /usr/local/k8s/redis/pv*


这一步必不可少，否则挂载时会出现mount.nfs: access denied by server while mounting的权限错误。

接着，启动NFS和rpcbind服务：

    systemctl start rpcbind
    systemctl start nfs


我们在k8s-node1上测试一下，执行：

    mount -t nfs 192.168.56.102:/usr/local/k8s/redis/pv1 /mnt


表示将k8s-node2上的共享目录/usr/local/k8s/redis/pv1映射为k8s-node1的/mnt目录，我们在/mnt中创建文件：


    touch haha


既可以在k8s-node2上看到该文件：

    [root@k8s-node2 redis]# ll pv1
    总用量 0
    -rw-r--r--. 1 nfsnobody nfsnobody 0 5月   2 21:35 haha

可以看到用户和组为nfsnobody。

### 创建PV


每一个Redis Pod都需要一个独立的PV来存储自己的数据，因此可以创建一个pv.yaml文件，包含6个PV：


具体参考pv.yaml,更多详情根据条件进行具体参数的配置。


操作完成以后，
如上，可以看到所有PV除了名称和挂载的路径外都基本一致。执行创建即可：

    [root@k8s-node1 redis]# kubectl create -f pv.yaml 
    persistentvolume "nfs-pv1" created
    persistentvolume "nfs-pv2" created
    persistentvolume "nfs-pv3" created
    persistentvolume "nfs-pv4" created
    persistentvolume "nfs-pv5" created
    persistentvolume "nfs-pv6" created


2.创建Configmap
这里，我们可以直接将Redis的配置文件转化为Configmap，这是一种更方便的配置读取方式。配置文件redis.conf如下：


    appendonly yes
    cluster-enabled yes
    cluster-config-file /var/lib/redis/nodes.conf
    cluster-node-timeout 5000
    dir /var/lib/redis
    port 6379

创建名为redis-conf的Configmap：

    #kubectl create configmap redis-conf --from-file=redis.conf


查看：


    [root@k8s-node1 redis]# kubectl describe cm redis-conf
    Name: redis-conf
    Namespace:default
    Labels:   <none>
    Annotations:  <none>
    
    Data
    ====
    redis.conf:
    ----
    appendonly yes
    cluster-enabled yes
    cluster-config-file /var/lib/redis/nodes.conf
    cluster-node-timeout 5000
    dir /var/lib/redis
    port 6379
    
    Events:  <none>

如上，redis.conf中的所有配置项都保存到redis-conf这个Configmap中。


3.创建Headless service
Headless service是StatefulSet实现稳定网络标识的基础，我们需要提前创建。准备文件headless-service.yml如下：


代码详情请参阅：headless-service.yml

创建：

    #kubectl create -f headless-service.yml


查看：

    [root@k8s-node1 redis]# kubectl get svc redis-service
    NAMETYPECLUSTER-IP   EXTERNAL-IP   PORT(S)AGE
    redis-service   ClusterIP   None <none>6379/TCP   53s
    
可以看到，服务名称为redis-service，其CLUSTER-IP为None，表示这是一个“无头”服务。



4.创建Redis 集群节点
创建好Headless service后，就可以利用StatefulSet创建Redis 集群节点，这也是本文的核心内容。我们先创建redis.yml文件：



代码详情参阅：redis.yaml文件。

总共创建了6个Redis节点(Pod)，其中3个将用于master，另外3个分别作为master的slave；Redis的配置通过volume将之前生成的redis-conf这个Configmap，挂载到了容器的/etc/redis/redis.conf；Redis的数据存储路径使用volumeClaimTemplates声明（也就是PVC），其会绑定到我们先前创建的PV上。


这里有一个关键概念——Affinity，请参考官方文档详细了解。其中，podAntiAffinity表示反亲和性，其决定了某个pod不可以和哪些Pod部署在同一拓扑域，可以用于将一个服务的POD分散在不同的主机或者拓扑域中，提高服务本身的稳定性。

而PreferredDuringSchedulingIgnoredDuringExecution 则表示，在调度期间尽量满足亲和性或者反亲和性规则，如果不能满足规则，POD也有可能被调度到对应的主机上。在之后的运行过程中，系统不会再检查这些规则是否满足。

在这里，matchExpressions规定了Redis Pod要尽量不要调度到包含app为redis的Node上，也即是说已经存在Redis的Node上尽量不要再分配Redis Pod了。但是，由于我们只有三个Node，而副本有6个，因此根据PreferredDuringSchedulingIgnoredDuringExecution，这些豌豆不得不得挤一挤，挤挤更健康~

另外，根据StatefulSet的规则，我们生成的Redis的6个Pod的hostname会被依次命名为$(statefulset名称)-$(序号)，如下图所示：

    [root@k8s-node1 redis]# kubectl get pods -o wide
    NAME  READY STATUS  RESTARTS   AGE   IPNODE
    dns-test  0/1   Completed   0  52m   192.168.169.208   k8s-node2
    redis-app-0   1/1   Running 0  1h192.168.169.207   k8s-node2
    redis-app-1   1/1   Running 0  1h192.168.169.197   k8s-node2
    redis-app-2   1/1   Running 0  1h192.168.169.198   k8s-node2
    redis-app-3   1/1   Running 0  1h192.168.169.205   k8s-node2
    redis-app-4   1/1   Running 0  1h192.168.169.200   k8s-node2
    redis-app-5   1/1   Running 0  1h192.168.169.201   k8s-node2

如上，可以看到这些Pods在部署时是以{0..N-1}的顺序依次创建的。注意，直到redis-app-0状态启动后达到Running状态之后，redis-app-1 才开始启动。


同时，每个Pod都会得到集群内的一个DNS域名，格式为$(podname).$(service name).$(namespace).svc.cluster.local，也即是：

    redis-app-0.redis-service.default.svc.cluster.local
    redis-app-1.redis-service.default.svc.cluster.local
    ...以此类推...


在K8S集群内部，这些Pod就可以利用该域名互相通信。我们可以使用busybox镜像的nslookup检验这些域名：

    [root@k8s-node1 ~]# kubectl run -i --tty --image busybox dns-test --restart=Never --rm /bin/sh 
    If you don't see a command prompt, try pressing enter.
    / # nslookup redis-app-0.redis-service
    Server:10.96.0.10
    Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
    
    Name:  redis-app-0.redis-service
    Address 1: 192.168.169.207 redis-app-0.redis-service.default.svc.cluster.local


可以看到， redis-app-0的IP为192.168.169.207。当然，若Redis Pod迁移或是重启（我们可以手动删除掉一个Redis Pod来测试），则IP是会改变的，但Pod的域名、SRV records、A record都不会改变。


另外可以发现，我们之前创建的pv都被成功绑定了：

    [root@k8s-node1 ~]# kubectl get pv
    NAME  CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUSCLAIMSTORAGECLASS   REASONAGE
    nfs-pv1   200M   RWXRetain   Bound default/redis-data-redis-app-21h
    nfs-pv2   200M   RWXRetain   Bound default/redis-data-redis-app-31h
    nfs-pv3   200M   RWXRetain   Bound default/redis-data-redis-app-41h
    nfs-pv4   200M   RWXRetain   Bound default/redis-data-redis-app-51h
    nfs-pv5   200M   RWXRetain   Bound default/redis-data-redis-app-01h
    nfs-pv6   200M   RWXRetain   Bound default/redis-data-redis-app-11h
    
初始化Redis集群

创建好6个Redis Pod后，我们还需要利用常用的Redis-tribe工具进行集群的初始化。


创建Ubuntu容器
由于Redis集群必须在所有节点启动后才能进行初始化，而如果将初始化逻辑写入Statefulset中，则是一件非常复杂而且低效的行为。这里，本人不得不称赞一下原项目作者的思路，值得学习。也就是说，我们可以在K8S上创建一个额外的容器，专门用于进行K8S集群内部某些服务的管理控制。

这里，我们专门启动一个Ubuntu的容器，可以在该容器中安装Redis-tribe，进而初始化Redis集群，执行：

    kubectl run -i --tty ubuntu --image=ubuntu --restart=Never /bin/bash



成功后，我们可以进入ubuntu容器中，原项目要求执行如下命令安装基本的软件环境：

    apt-get update
    apt-get install -y vim wget python2.7 python-pip redis-tools dnsutils

但是，需要注意的是，在我们天朝，执行上述命令前需要提前做一件必要的工作——换源，否则你懂得。我们使用阿里云的Ubuntu源，执行：

    root@ubuntu:/# cat > /etc/apt/sources.list << EOF
    > deb http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
    > deb-src http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
    > 
    > deb http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
    > deb-src http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
    > 
    > deb http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
    > deb-src http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
    > 
    > deb http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
    > deb-src http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
    > 
    > deb http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
    > deb-src http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
    > EOF

源修改完毕后，就可以执行上面的两个命令。


首先，我们需要安装redis-trib：

    #pip install redis-trib

然后，创建只有Master节点的集群：

    redis-trib.py create \
      `dig +short redis-app-0.redis-service.default.svc.cluster.local`:6379 \
      `dig +short redis-app-1.redis-service.default.svc.cluster.local`:6379 \
      `dig +short redis-app-2.redis-service.default.svc.cluster.local`:6379



如上，命令dig +short redis-app-0.redis-service.default.svc.cluster.local用于将Pod的域名转化为IP，这是因为redis-trib不支持域名来创建集群。

其次，为每个Master添加Slave：


    redis-trib.py replicate \
      --master-addr `dig +short redis-app-0.redis-service.default.svc.cluster.local`:6379 \
      --slave-addr `dig +short redis-app-3.redis-service.default.svc.cluster.local`:6379
    
    redis-trib.py replicate \
      --master-addr `dig +short redis-app-1.redis-service.default.svc.cluster.local`:6379 \
      --slave-addr `dig +short redis-app-4.redis-service.default.svc.cluster.local`:6379
    
    redis-trib.py replicate \
      --master-addr `dig +short redis-app-2.redis-service.default.svc.cluster.local`:6379 \
      --slave-addr `dig +short redis-app-5.redis-service.default.svc.cluster.local`:6379



至此，我们的Redis集群就真正创建完毕了，连到任意一个Redis Pod中检验一下：


    root@k8s-node1 ~]# kubectl exec -it redis-app-2 /bin/bash
    root@redis-app-2:/data# /usr/local/bin/redis-cli -c
    127.0.0.1:6379> cluster nodes
    c15f378a604ee5b200f06cc23e9371cbc04f4559 192.168.169.197:6379@16379 master - 0 1526454835084 1 connected 10923-16383
    96689f2018089173e528d3a71c4ef10af68ee462 192.168.169.204:6379@16379 slave d884c4971de9748f99b10d14678d864187a9e5d3 0 1526454836491 4 connected
    d884c4971de9748f99b10d14678d864187a9e5d3 192.168.169.199:6379@16379 master - 0 1526454835487 4 connected 5462-10922
    c3b4ae23c80ffe31b7b34ef29dd6f8d73beaf85f 192.168.169.198:6379@16379 myself,master - 0 1526454835000 3 connected 0-5461
    c8a8f70b4c29333de6039c47b2f3453ed11fb5c2 192.168.169.201:6379@16379 slave c3b4ae23c80ffe31b7b34ef29dd6f8d73beaf85f 0 1526454836000 3 connected
    237d46046d9b75a6822f02523ab894928e2300e6 192.168.169.200:6379@16379 slave c15f378a604ee5b200f06cc23e9371cbc04f4559 0 1526454835000 1 connected
    127.0.0.1:6379> cluster info
    cluster_state:ok
    cluster_slots_assigned:16384
    cluster_slots_ok:16384
    cluster_slots_pfail:0
    cluster_slots_fail:0
    cluster_known_nodes:6
    cluster_size:3
    cluster_current_epoch:4
    ...省略...

另外，还可以在NFS上查看Redis挂载的数据：

    [root@k8s-node2 ~]# ll /usr/local/k8s/redis/pv3/
    总用量 8
    -rw-r--r--. 1 nfsnobody nfsnobody   0 5月  16 15:07 appendonly.aof
    -rw-r--r--. 1 nfsnobody nfsnobody 175 5月  16 15:07 dump.rdb
    -rw-r--r--. 1 nfsnobody nfsnobody 817 5月  16 16:55 nodes.conf
    


6.创建用于访问Service

前面我们创建了用于实现StatefulSet的Headless Service，但该Service没有Cluster Ip，因此不能用于外界访问。所以，我们还需要创建一个Service，专用于为Redis集群提供访问和负载均：

代码详情访问redis-access-service.yaml


该Service名称为 redis-access-service，在K8S集群中暴露6379端口，并且会对labels name为app: redis或appCluster: redis-cluster的pod进行负载均衡。


创建后查看：

    [root@k8s-node1 redis]# kubectl get svc redis-access-service -o wide
    NAME   TYPECLUSTER-IP  EXTERNAL-IP   PORT(S)AGE   SELECTOR
    redis-access-service   ClusterIP   10.105.11.209   <none>6379/TCP   41m   app=redis,appCluster=redis-cluster


在K8S集群中，所有应用都可以通过10.105.11.209:6379来访问Redis集群。当然，为了方便测试，我们也可以为Service添加一个NodePort映射到物理机上，这里不再详细介绍。




集群详细测试：

测试主从切换
在K8S上搭建完好Redis集群后，我们最关心的就是其原有的高可用机制是否正常。这里，我们可以任意挑选一个Master的Pod来测试集群的主从切换机制，如redis-app-2：


    [root@k8s-node1 redis]# kubectl get pods redis-app-2 -o wide
    NAME  READY STATUSRESTARTS   AGE   IPNODE
    redis-app-2   1/1   Running   0  2h192.168.169.198   k8s-node2

进入redis-app-2查看：

    [root@k8s-node1 redis]#  kubectl exec -it redis-app-2 /bin/bash
    root@redis-app-2:/data# /usr/local/bin/redis-cli -c
    127.0.0.1:6379> role
    1) "master"
    2) (integer) 8666
    3) 1) 1) "192.168.169.201"
      2) "6379"
      3) "8666"
    127.0.0.1:6379>


如上可以看到，其为master，slave为192.168.169.201即redis-app-5`。

接着，我们手动删除redis-app-2：

    [root@k8s-node1 redis]# kubectl delete pods redis-app-2
    pod "redis-app-2" deleted
    
    [root@k8s-node1 redis]# kubectl get pods redis-app-2 -o wide
    NAME  READY STATUSRESTARTS   AGE   IPNODE
    redis-app-2   1/1   Running   0  20s   192.168.169.210   k8s-node2


如上，IP改变为192.168.169.210。我们再进入redis-app-2内部查看：

    [root@k8s-node1 redis]# kubectl exec -it redis-app-2 /bin/bash
    root@redis-app-2:/data# /usr/local/bin/redis-cli -c
    127.0.0.1:6379> role
    1) "slave"
    2) "192.168.169.201"
    3) (integer) 6379
    4) "connected"
    5) (integer) 8960
    127.0.0.1:6379>

如上，redis-app-2变成了slave，从属于它之前的从节点192.168.169.201即redis-app-5。

六、疑问
至此，大家可能会疑惑，前面讲了这么多似乎并没有体现出StatefulSet的作用，其提供的稳定标志redis-app-*仅在初始化集群的时候用到，而后续Redis Pod的通信或配置文件中并没有使用该标志。我想说，是的，本文使用StatefulSet部署Redis确实没有体现出其优势，还不如介绍Zookeeper集群来的明显，不过没关系，学到知识就好。

那为什么没有使用稳定的标志，Redis Pod也能正常进行故障转移呢？这涉及了Redis本身的机制。因为，Redis集群中每个节点都有自己的NodeId（保存在自动生成的nodes.conf中），并且该NodeId不会随着IP的变化和变化，这其实也是一种固定的网络标志。也就是说，就算某个Redis Pod重启了，该Pod依然会加载保存的NodeId来维持自己的身份。我们可以在NFS上查看redis-app-1的nodes.conf文件：

    [root@k8s-node2 ~]# cat /usr/local/k8s/redis/pv1/nodes.conf 
    96689f2018089173e528d3a71c4ef10af68ee462 192.168.169.209:6379@16379 slave d884c4971de9748f99b10d14678d864187a9e5d3 0 1526460952651 4 connected
    237d46046d9b75a6822f02523ab894928e2300e6 192.168.169.200:6379@16379 slave c15f378a604ee5b200f06cc23e9371cbc04f4559 0 1526460952651 1 connected
    c15f378a604ee5b200f06cc23e9371cbc04f4559 192.168.169.197:6379@16379 master - 0 1526460952651 1 connected 10923-16383
    d884c4971de9748f99b10d14678d864187a9e5d3 192.168.169.205:6379@16379 master - 0 1526460952651 4 connected 5462-10922
    c3b4ae23c80ffe31b7b34ef29dd6f8d73beaf85f 192.168.169.198:6379@16379 myself,slave c8a8f70b4c29333de6039c47b2f3453ed11fb5c2 0 1526460952565 3 connected
    c8a8f70b4c29333de6039c47b2f3453ed11fb5c2 192.168.169.201:6379@16379 master - 0 1526460952651 6 connected 0-5461
    vars currentEpoch 6 lastVoteEpoch 4

如上，第一列为NodeId，稳定不变；第二列为IP和端口信息，可能会改变。

这里，我们介绍NodeId的两种使用场景：

当某个Slave Pod断线重连后IP改变，但是Master发现其NodeId依旧， 就认为该Slave还是之前的Slave。
当某个Master Pod下线后，集群在其Slave中选举重新的Master。待旧Master上线后，集群发现其NodeId依旧，会让旧Master变成新Master的slave。
对于这两种场景，大家有兴趣的话还可以自行测试，注意要观察Redis的日志。

