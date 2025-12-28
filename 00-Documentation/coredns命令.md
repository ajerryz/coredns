# coredns命令
```shell
Usage of ./coredns:
  -conf string
        Corefile to load (default "Corefile")
  -dns.port string
        Default port (default "53")
  -p string
        Default port (default "53")
  -pidfile string
        Path to write pid file
  -plugins
        List installed plugins
  -quiet
        Quiet mode (no initialization output)
  -version
        Show version
```


# Corefile
Corefile由一个或多个服务块组成。每个服务块是独立的DNS服务配置单元，服务块之间用空行隔开(可选，仅为可读性)。

服务块基本结构:
```text
[区域域名...] [监听地址...] {
    插件1 [插件参数]
    插件2 [插件参数]
    ...  # 更多插件配置
}
```
- 区域域名(Zone)：指定该服务区块解析的DNS域名，可配置多个。
  - 示例:`example.com`,负责解析`example.com`域名及其子域名。`.org`(通配符),`.`根域
  - 若省略，默认等价于`.` 根域
- 监听地址：指定CoreDNS监听的IP地址和端口，格式为:`IP:port`或者`:port`(监听所有网卡)
- 插件链：服务块内部的核心，由一系列插件按顺序组成，CoreDNS的所有功能(解析、转发、缓存等)均由插件实现

## 核心组成部分详解
1. 服务块示例,该示例表示：监听所有网卡的53端口，负责所有域名的解析、启用日志、缓存、转发(到谷歌和CloudflareDNS),错误处理插件
```text
. :53 {
    log
    cache
    forward . 8.8.8.8 1.1.1.1
    errors
}
```

## 插件链(Plugin Chain)核心特性与常用插件
1. 插件的核心原则
- 顺序执行：插件按配置文件从上到下顺序执行，类似中间件
- 按需启用：仅配置需要的插件，未配置的插件不参与处理
- 插件优先级：部分插件有内置优先级，但配置顺序优于内置优先级(手动配置顺序决定执行顺序)
- 参数可选：部分插件无参数(如:log,error),部分插件需要指定必选参数(如:forward)

2. 最常用的插件

|插件名	| 核心作用	                                                                                 | 常用配置示例	                                                                                                                                                                                                                  | 说明                                                      |
|---|---------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
|log	| 记录所有 DNS 查询和响应日志	                                                                     | `log`（默认格式）<br/> `log /var/log/coredns.log`（指定日志文件）	                                                                                                                                                                     | 日志包含客户端 IP、查询域名、类型、响应状态等，便于排障和审计                        |
|errors	| 输出 DNS 处理过程中的错误信息（到标准输出或日志文件）	                                                        | `errors`（默认输出到 stdout）<br/>`errors /var/log/coredns-err.log`	                                                                                                                                                            | 排障必备，捕获转发失败、配置错误等信息                                     |
|cache	| 缓存 DNS 查询结果，提升解析性能，减少上游 DNS 压力	                                                       | `cache`（默认缓存 3600 秒）<br/> `cache 300`（缓存 5 分钟）<br/> `cache example.com 600`（仅缓存 example.com 域名，10 分钟）	                                                                                                                   | 遵循 DNS 记录的 TTL 规则，缓存时间不超过记录本身的 TTL                      |
|forward | 将 DNS 查询转发到上游 DNS 服务器（最常用插件之一）	                                                       | `forward . 8.8.8.8 1.1.1.1`（转发所有域名到谷歌 / Cloudflare DNS）<br/> `forward example.com 192.168.1.1`（仅转发 example.com 到内网 DNS）<br/> `forward . tls://8.8.8.8`（通过 TLS 加密转发）	                                                     | 第一个参数为域名区域（. 表示所有），后续为上游 DNS 地址（支持 UDP/TCP/TLS）         |
|hosts	| 类似 /etc/hosts，配置本地静态 DNS 解析记录，优先级高于其他解析插件	                                            | `hosts`（默认读取本地 /etc/hosts）<br/> `hosts /etc/coredns/hosts.conf`（指定自定义 hosts 文件）<br/> `hosts { 192.168.1.200 www.test.com }`（直接在配置中定义）	                                                                                   | 静态解析优先，适合本地测试、内网服务映射                                    |
|file	| 从 DNS 区域文件（Zone File，遵循 BIND 格式）中读取解析记录，实现主从 DNS 或自定义域名解析	                            | `file /etc/coredns/example.com.zone`（加载 example.com 的区域文件）<br/> `file /etc/coredns/zone.db example.com`（指定域名和区域文件）	                                                                                                      | 支持 A、AAAA、CNAME、MX、TXT 等所有标准 DNS 记录类型，适合自定义域名管理         |
|kubernetes	| 专为 Kubernetes 集群设计，解析集群内的 Service、Pod 域名（如 service-name.namespace.svc.cluster.local）	 | kubernetes cluster.local in-addr.arpa ip6.arpa {                                                                                                                     pods verified  fallthrough in-addr.arpa ip6.arpa }	 | K8s 集群核心插件，自动同步集群内服务信息，无需手动配置解析记录                       |                                                                                                                                                                      |
| health	 | 提供健康检查端点，用于监控 CoreDNS 运行状态	| `health`（默认监听 :8080，端点 /health）<br/> `health :9090 /healthz`（指定端口和端点）	                                                                                                                                                   | 可通过 curl http://localhost:8080/health 验证 CoreDNS 是否正常运行 |
| ready	| 提供就绪检查端点，确认 CoreDNS 插件已加载完成且可提供服务	| ready（默认端点 /ready） | 	                                                       |适合 K8s、Docker 等容器环境的就绪探针配置 |


## 完整配置示例
### 示例1:基础通用DNS配置(转发+缓存+日志)
```text
. :53 {
    log # 记录查询日志
    errors # 输出错误日志
    cache 600 # 缓存10分钟
    forward . 8.8.8.8 1.1.1.1 { # 转发到公共DNS,优先于谷歌，其次Cloudflare
        timeout 3s
        policy round_robin
    }
}
```
### 示例2:混合配置(本地静态解析+内网域名+上游转发)
```text
# 服务块1：内网域名 example.com 解析（本地文件+静态 hosts）
example.com :53 {
    log
    errors
    # 自定义静态解析
    hosts {
        192.168.1.100 api.example.com
        192.168.1.101 web.example.com
    }
    # 从区域文件加载其他记录（如 MX、TXT）
    file /etc/coredns/example.com.zone
    # 缓存内网解析结果
    cache 300
}

# 服务块2：其他所有域名转发到内网 DNS 服务器
. :53 {
    log
    cache
    forward . 192.168.1.1
    errors
}
```
### 示例3:k8s集群内CoreDNS配置(官方默认简化版)
```text
. :53 {
    log
    errors
    health
    ready
    # K8s 集群域名解析
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods verified
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    # 缓存
    cache 30
    # 本地 hosts 解析
    hosts
    # 无法在集群内解析的域名，转发到宿主机 DNS
    forward . /etc/resolv.conf
    # 拒绝空查询
    loop
    reload
    loadbalance
}
```