## Redis主从集群部署

我们在部署主从集群时，我们根据写好的主从文档直接进行集群部署就可以的。


在我们编写的项目目录下存在一个mainfile的文件夹：
在这个文件夹下存在所有项目的部署所需要的yaml文件。

只需要执行:

    #kubectl apply -f ./mainfile

那么，redis的主从集群我们就部署成功了！