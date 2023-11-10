# 学习路径：
[#1513](https://github.com/alibaba/GraphScope/discussions/1513)

![图片alt](GraphScopeFramwork.png "图片title")


1. Python Interface, the python client for end-users;
2. coordinator: it manages the k8s cluster and receives all requests and triages them to the responding engine;
3. analytical_engine: for iterative graph algorithms, which extends GRAPE;
4. interactive_engine: for gremlin queries, please note that the fold is being deprecated and upgraded to GAIA;
5. learning_engine: for GNN, it was built on graph-learn;
6. vineyard: an in-memory data manager, graphs on all engines are managed by vineyard;
7. groot: a persistent store for graph.
Since the codebase is still in change, I would suggest the learning path can be:
1) -> 2) -> 3) -> 6) -> 4) -> 5) -> 7)

代码阅读笔记：
1. 1）Python Client 通过 RPC 拉起服务
    * 发送各种指令：
        * 创建Session【两种部署方式：本机，K8S 】
        * 创建图
        * 加载点边:具体读文件，加载到内存是在后端进行的
        * 创建查询Interactive:支持Gremlin & Cypher 语言 
2. 2）Coordinator 独立一个模块：
    * 启动Server ：通过python 启动服务
    * 脚本调度，构建工作流
    * 需要明确 RPC 骨架对应的服务
3. 3）Analytical_engine 模块：
    * 跑各种算法：语言栈 C++
4. 6）Vineyard: 
    * 基于内存存储图数据，基于之上进行图计算
    * 通过python 启动进程
5. 4）Interactive_engine: 交互式查询引擎
    * 主要是满足接收Gremlin + Cypher ，然后转换成查询计划，分布式执行 Gremlin ？
    * 此处主要看计算引擎 + 存储引擎的核心技术实现


TODO : 
增加每个模块的源码介绍


## 0 分析Client 加载图数据到GIE交互式查询图数据源码流程
```python
# Import the graphscope module
import graphscope
import os
# 单机验证 加载图数据 from HDFS
from graphscope.framework.loader import Loader
from graphscope.client.session import get_default_session


graphscope.set_option(show_log=True)  # enable logging
graphscope.set_option(log_level='DEBUG')



# 拉起简单的任务
sess = graphscope.session( cluster_type='hosts',
                            enabled_engines='interactive',
                            vineyard_shared_mem='1Gi',
                            num_workers=2)
```
**结合日志和源码，主要是理解gRPC 开发框架，能提升源码阅读效率**  
Action-list:hosts:HostsClusterLauncher
1. 创建并拉起 Coordinator：使用_launcher 创建核心服务
2. 拉起 Vineyard
3. create_analytical_instance

Client/Server 需要结合来看：核心是 gRPC 组织流程  
客户端代码直接看 Session   
Coordinator 直接看coordinator/gscoordinator/servicer/graphscope_one/service.py:GraphScopeOneServiceServicer RPC 服务侧实现逻辑  

```python
# 客户端向Coordinator 发送RPC请求：创建图并加载图数据
graph = sess.g()

prefix = '/Users/yangjiaqi/.graphscope/datasets/ogbn_mag_small'
graph = (
        graph.add_vertices(os.path.join(prefix, "paper.csv"), "paper")
        )
```
主要是看DAGNode 具体实现的 GraphDAGNode 组成的 op 链
通过session::run 方法调用Coordinator gRPC 方法self._stub.RunStep(runstep_requests)
核心： gRPC 执行 stub 远程方法 runStep 到各个组件：GAE/GIE/GLE 等


1. GAE 注册创建空Graph
2. add_vertices op 通过Debug 日志分析主要做两件事情  
   a. 将第三方存储数据（file、HDFS、S3）等文件加载到 vinyard 参考方法 [Read_ORC](https://github.com/v6d-io/v6d/blob/main/python/vineyard/drivers/io/adaptors/read_orc.py)  
   b. Graph 加载 VinYard 对应表数据到图中
3. 单机加载2GB文件异常：hang流程，无报错
```python
# 创建GIE进行交互式查询
interactive = sess.interactive(graph)
edgeNum = interactive.execute(
    "g.E().count()").one()
print("edgeNum", edgeNum)
```
