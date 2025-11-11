# CoreDNS快速入门
CoreDNS 是一个灵活、可扩展的 DNS 服务器，采用 Go 语言编写，遵循 RFC 标准，通过插件化架构支持丰富的功能（如服务发现、域名转发、缓存、日志等），广泛用于 Kubernetes 集群内部 DNS 解析，也可作为独立 DNS 服务器部署在物理机、虚拟机或容器环境中。本文将从 核心概念、部署方式、配置详解、功能实践、运维监控 五个维度，全面讲解 CoreDNS 单独使用的方法。


# 一、CoreDNS核心概念
在使用前，需先理解 CoreDNS 的核心组件和工作原理，这是配置和运维的基础。

|概念|说明 
|---|---
|插件（Plugin）	|CoreDNS 的核心扩展机制，所有功能（如转发、缓存、日志）均通过插件实现，支持按需启用 / 禁用。
|Corefile	|CoreDNS 的配置文件，定义了 DNS 服务器的监听地址、域名解析规则、插件组合等核心逻辑。
|Zone	|DNS 中的 “域名区域”（如 example.com），CoreDNS 可针对不同 Zone 配置不同的解析策略。
|Resolver	|负责将域名查询请求转发到上游 DNS 服务器（如 8.8.8.8）或从本地数据源（如文件、ETCD）获取解析结果。
|缓存（Cache）	|插件提供的功能，缓存已解析的域名记录，减少上游请求次数，提升解析性能。


# 二、CoreDNS部署方式
CoreDNS 支持多种部署形态，可根据环境选择合适的方式，以下是最常用的 3 种独立部署方案。

## 1. 二进制部署（推荐：物理机 / 虚拟机）

 适合需要稳定运行、便于自定义配置的场景，步骤如下：
```terminaloutput
步骤1: 下载二进制包
从 CoreDNS 官方 GitHub Release 下载对应系统（Linux/macOS/Windows）的二进制包（格式为 coredns-{版本}-{系统}-{架构}.tar.gz）。

步骤 2：验证安装
coredns -version

步骤 3：配置系统服务（可选，实现开机自启）
# 3.1创建服务文件 /etc/systemd/system/coredns.service
==============================================
[Unit]
Description=CoreDNS DNS Server
Documentation=https://coredns.io
After=network.target

[Service]
Type=simple
# 注意：-conf 指定 Corefile 路径，需与实际配置一致
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
===========================================

# 3.2启动并设置开机自启
mkdir -p /etc/coredns   # 创建 Corefile 目录
systemctl start coredns # 启动服务
systemctl enable coredns # 设置开机自启
systemctl status coredns # 验证服务状态
```
## 2.Docker部署(推荐：快速测试 / 容器环境)
适合快速验证功能或集成到容器化部署流程，步骤如下：
```terminaloutput
步骤 1：拉取官方镜像(CoreDNS 官方镜像托管在 Docker Hub，直接拉取即可：)
docker pull coredns/coredns:1.11.1  # 建议指定版本，避免使用 latest

步骤 2：创建 Corefile 配置
# 在本地创建 Corefile（如 /opt/coredns/Corefile），基础配置示例：
==========
# 监听 53 端口（DNS 默认端口），支持 UDP 和 TCP
.:53 {
    forward . 8.8.8.8 114.114.114.114  # 将所有请求转发到上游 DNS
    cache 300  # 缓存解析结果 300 秒（5 分钟）
    log        # 启用日志，打印 DNS 查询请求
    errors     # 启用错误日志，打印解析失败信息
}
==========
步骤 3：启动容器
=========
docker run -d \
  --name coredns \
  -p 53:53/udp \
  -p 53:53/tcp \
  -v /opt/coredns/Corefile:/etc/coredns/Corefile \
  coredns/coredns:1.11.1 -conf /etc/coredns/Corefile
========

步骤 4：验证容器运行
docker logs -f coredns

# 测试 DNS 解析（需安装 dig 工具：yum install bind-utils 或 apt install dnsutils）
dig @127.0.0.1 www.baidu.com

```


## 3.Kubernetes 部署（独立使用，非集群默认 DNS）
若需在 Kubernetes 中部署独立 CoreDNS（而非替换集群默认的 kube-dns/CoreDNS），可通过 Deployment + Service 实现：
```terminaloutput
步骤 1：创建 Deployment 配置（coredns-deploy.yaml）
===============================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: standalone-coredns
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: standalone-coredns
  template:
    metadata:
      labels:
        app: standalone-coredns
    spec:
      containers:
      - name: coredns
        image: coredns/coredns:1.11.1
        args: ["-conf", "/etc/coredns/Corefile"]
        ports:
        - containerPort: 53
          protocol: UDP
        - containerPort: 53
          protocol: TCP
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
      volumes:
      - name: config-volume
        configMap:
          name: standalone-coredns-config  # 引用 ConfigMap 中的 Corefile
---
# 创建 ConfigMap 存储 Corefile
apiVersion: v1
kind: ConfigMap
metadata:
  name: standalone-coredns-config
  namespace: default
data:
  Corefile: |
    .:53 {
      forward . 8.8.8.8 1.1.1.1
      cache 300
      log
      errors
    }
---
# 创建 Service 暴露 CoreDNS（ClusterIP 供集群内部访问，NodePort 供外部访问）
apiVersion: v1
kind: Service
metadata:
  name: standalone-coredns
  namespace: default
spec:
  selector:
    app: standalone-coredns
  ports:
  - name: udp-53
    port: 53
    protocol: UDP
    targetPort: 53
  - name: tcp-53
    port: 53
    protocol: TCP
    targetPort: 53
  type: NodePort  # 如需外部访问，可改为 LoadBalancer（云环境）
==============================================================



步骤 2：部署并验证


kubectl apply -f coredns-deploy.yaml    # 应用配置
kubectl get pods -l app=standalone-coredns  # 查看 Pod 和 Service
kubectl get svc standalone-coredns

kubectl run -it --rm --image=busybox:1.35.0 sh # 测试解析（在集群内 Pod 中执行）

```

# 三、Corefile配置详解
Corefile 是 CoreDNS 的核心，语法格式为 “Zone 监听配置 { 插件配置}”，支持多 Zone 配置、插件组合、条件逻辑等。
## 1.基础语法结构
```terminaloutput
# 格式：Zone 监听地址 { 插件1 参数; 插件2 参数; ... }
<Zone> <Listen Address> {
    <Plugin1> <Args1>
    <Plugin2> <Args2>
    # 注释以 # 开头
}

# 示例：对所有域名（.）监听 53 端口，启用转发、缓存、日志插件
.:53 {
    forward . 8.8.8.8 114.114.114.114  # 转发到上游 DNS
    cache 300                          # 缓存 5 分钟
    log                                # 打印查询日志
    errors                             # 打印错误日志
}
```
- Zone：域名区域，如 example.com（仅处理该域名的解析）、.（处理所有域名，即根 Zone）。
- Listen Address：监听的 IP 和端口，默认 0.0.0.0:53（所有网卡的 53 端口），可指定具体 IP（如 192.168.1.100:53）。
- 插件:每行一个插件，参数根据插件特性调整，部分插件无需参数（如 log）。

## 2.常用插件配置
CoreDNS 有数十个官方插件，以下是独立使用时最常用的插件及配置示例：
### 2.1 forward：域名转发
将 DNS 查询转发到上游 DNS 服务器（如公共 DNS、企业内部 DNS），是最基础的功能之一。
```ini
# 格式：forward <Zone> <上游 DNS 列表> [选项]
forward . 8.8.8.8 8.8.4.4  # 转发所有域名到 Google DNS
forward example.com 192.168.1.200:53  # 仅转发 example.com 到内部 DNS
forward . tls://1.1.1.1  # 启用 TLS 加密转发（DoT，DNS over TLS）
forward . https://1.1.1.1/dns-query  # 启用 HTTPS 转发（DoH，DNS over HTTPS）
```

### 2.2 cache：结果缓存
缓存已解析的 DNS 记录，减少上游请求，提升性能，支持自定义缓存时长、缓存大小等。
```ini
# 格式：cache [缓存时长(秒)] [选项]
cache 300  # 默认缓存 300 秒（5 分钟），缓存大小由系统内存自动调整
cache 600 {
    success 1000  # 成功记录缓存 1000 秒
    denial 500    # 拒绝记录（如 NXDOMAIN）缓存 500 秒
    prefetch 2    # 缓存过期前 2 秒主动预取更新
    max_size 1000 # 最大缓存条目数 1000
}
```

### 2.3 log/errors：日志记录
- log：打印所有 DNS 查询请求日志（包括客户端 IP、域名、类型、响应时间等）。
- errors：仅打印解析错误日志（如上游 DNS 不可达、域名不存在等）。
```ini
.:53 {
    forward . 8.8.8.8
    log {
        class all  # 记录所有类型日志（query/reply）
        format "[{remote}] {name} {type} {rcode} {duration}"  # 自定义日志格式
    }
    errors  # 启用错误日志
} 
```

### 2.4 file：本地静态解析
通过本地文件（类似 /etc/hosts 但支持 DNS 标准记录）定义静态解析规则，适合固定域名映射。
1. 创建本地解析文件 `db.example.com`（格式为 DNS 区域文件）：
```ini
; 区域文件头部
$ORIGIN example.com.  ; 域名后缀
$TTL 300              ; 默认缓存时长

; 记录类型：A（IPv4）、AAAA（IPv6）、CNAME（别名）、MX（邮件）等
@       IN  A       192.168.1.10  ; @ 代表 $ORIGIN（即 example.com）
www     IN  A       192.168.1.11  ; www.example.com -> 192.168.1.11
mail    IN  A       192.168.1.12
mail    IN  MX  10  mail.example.com.  ; MX 记录，优先级 10
blog    IN  CNAME   www.example.com.    ; blog 别名指向 www 
```
2. 在corefile 中引用该文件
```ini
# 对 example.com 域名，优先使用本地文件解析；其他域名转发到上游
example.com:53 {
    file /etc/coredns/db.example.com  # 引用本地区域文件
    log
    errors
}

.:53 {
    forward . 8.8.8.8
    log
} 
```

### 2.5 hosts：增强版 /etc/hosts
类似 /etc/hosts，支持直接在 Corefile 中定义 IP - 域名映射，比 file 插件更简洁。
```ini
.:53 {
    hosts {
        192.168.1.100  server1.example.com  # 静态映射
        192.168.1.101  server2.example.com
        fallthrough  # 未匹配的域名，转发到后续插件（如 forward）
    }
    forward . 8.8.8.8
    log
}
```

### 2.6 health: 健康检查
暴露 HTTP 接口用于健康检查（如监控系统检测 CoreDNS 是否存活）。
```ini
.:53 {
    forward . 8.8.8.8
    health :8080  # 在 8080 端口暴露健康检查接口
    # 访问 http://<CoreDNS IP>:8080/health 可获取健康状态（返回 "OK" 表示正常）
}
```

### 2.7 prometheus：监控指标
暴露 Prometheus 格式的监控指标，用于监控解析成功率、响应时间、缓存命中率等。
```ini
.:53 {
    forward . 8.8.8.8
    prometheus :9153  # 在 9153 端口暴露指标接口
    # Prometheus 配置中添加该地址即可抓取指标（如 job_name: "coredns"，targets: ["x.x.x.x:9153"]）
}
```

## 三、多Zone配置示例
实际场景中可能需要对不同域名配置不同解析策略，例如：
- example.com：使用本地文件解析
- internal.org：转发到企业内部 DNS（192.168.1.200）。
- 其他域名：转发到公共 DNS（8.8.8.8、1.1.1.1）。

对应的 Corefile 配置：
```ini
# 1. 处理 example.com 域名（本地文件解析）
example.com:53 {
    file /etc/coredns/db.example.com
    log
    errors
    cache 300
}

# 2. 处理 internal.org 域名（转发到内部 DNS）
internal.org:53 {
    forward . 192.168.1.200:53
    log
    errors
    cache 600
}

# 3. 处理所有其他域名（转发到公共 DNS）
.:53 {
    forward . 8.8.8.8 1.1.1.1
    log
    errors
    cache 300
    health :8080
    prometheus :9153
}
```

## 四、功能实践：常见场景配置
以下是独立使用 CoreDNS 时的典型场景，结合实际需求提供配置方案。

### 4.1 场景 1：作为本地 DNS 服务器（替换系统默认 DNS）
需求：在个人电脑或服务器上部署 CoreDNS，实现本地域名缓存、自定义解析，提升解析速度。

步骤1:Corefile 配置
```ini
.:53 {
    # 1. 本地静态解析（优先匹配）
    hosts {
        127.0.0.1  localhost  # 本地回环
        192.168.1.10  nas.home  # 家庭 NAS 地址
        fallthrough  # 未匹配的域名转发到上游
    }

    # 2. 转发到公共 DNS（启用 DoT 加密，提升安全性）
    forward . tls://8.8.8.8 tls://8.8.4.4 tls://1.1.1.1 {
        tls_servername dns.google  # DoT 服务器的 SNI（Google DNS 需指定）
        health_check 5s  # 每 5 秒检查上游 DNS 健康状态
        policy round_robin  # 轮询转发策略
    }

    # 3. 缓存配置（提升性能）
    cache 3600 {
        success 3600  # 成功记录缓存 1 小时
        denial 300    # 拒绝记录缓存 5 分钟
        prefetch 5    # 过期前 5 秒预取
    }

    # 4. 日志和监控
    log {
        format "[{time}] [{remote}] {name} {type} -> {rcode} ({duration})"
    }
    errors
    health :8080
    prometheus :9153
}
```

步骤 2：设置系统默认 DNS

将系统的 DNS 服务器地址改为 CoreDNS 所在 IP（如 CoreDNS 部署在本地，则设置为 127.0.0.1）：
- Linux：修改 /etc/resolv.conf，添加 nameserver 127.0.0.1（需禁用 NetworkManager 自动覆盖）。
- macOS：通过 “系统设置> 网络 > 高级 > DNS” 添加 127.0.0.1。
- Windows：通过 “控制面板> 网络和共享中心 > 更改适配器设置”，编辑网卡的 DNS 为 127.0.0.1。

步骤 3：验证
```shell
# 测试本地自定义域名
ping nas.home  # 应解析到 192.168.1.10

# 测试公共域名解析
dig @127.0.0.1 www.baidu.com  # 查看响应是否来自 CoreDNS，且有缓存命中标识
```


### 4.2 场景 2：作为企业内部 DNS 服务器
需求：在企业内网部署 CoreDNS，实现内部服务域名解析（如 api.internal 指向内网服务），并转发外网域名到公共 DNS。


步骤 1：创建内部域名解析文件 db.internal
```ini
$ORIGIN internal.
$TTL 600

@       IN  A       192.168.0.1  # internal 根域名指向网关
api     IN  A       192.168.0.10  # api.internal -> 192.168.0.10（后端服务）
web     IN  A       192.168.0.11  # web.internal -> 192.168.0.11（前端服务）
db      IN  A       192.168.0.12  # db.internal -> 192.168.0.12（数据库服务）
monitor IN  A       192.168.0.13  # monitor.internal -> 192.168.0.13（监控系统）
```

步骤 2：Corefile 配置

```ini
# 1. 处理内部域名（internal）
internal:53 {
    file /etc/coredns/db.internal  # 引用内部区域文件
    log {
        format "[INTERNAL] [{remote}] {name} {type} -> {rcode}"
    }
    errors
    cache 600  # 内部域名缓存 10 分钟
}

# 2. 处理外网域名（转发到公共 DNS，启用缓存）
.:53 {
    forward . 192.168.0.254:53  # 优先转发到企业出口 DNS（如有），无则用公共 DNS
    cache 300
    log {
        format "[EXTERNAL] [{remote}] {name} {type} -> {rcode}"
    }
    errors
    health :8080
    prometheus :9153
}
```

步骤 3：内网设备配置 DNS

将内网所有设备的 DNS 服务器地址改为 CoreDNS 所在 IP（如 192.168.0.5），即可实现内部域名解析。


### 4.3 场景 3：启用 DNS 缓存和预取（提升解析性能）
需求：通过优化缓存策略，减少上游请求，降低延迟，尤其适合网络带宽有限或上游 DNS 响应较慢的场景。

Corefile 配置
```ini
.:53 {
    forward . 8.8.8.8 114.114.114.114
    cache 3600 {
        max_size 10000  # 最大缓存条目数 10000（默认 1000）
        success 3600    # 成功记录缓存 1 小时
        denial 600      # 拒绝记录缓存 10 分钟
        prefetch 10     # 缓存过期前 10 秒主动预取（避免缓存失效时的延迟）
        min_ttl 60      # 强制最小缓存时长 60 秒（防止上游返回过短 TTL）
        max_ttl 86400   # 强制最大缓存时长 1 天（防止上游返回过长 TTL）
    }
    log
    errors
    prometheus :9153  # 监控缓存命中率（指标：coredns_cache_hits_total、coredns_cache_misses_total）
}
```

验证缓存命中率

通过 Prometheus + Grafana 监控缓存命中率，公式为：

```terminaloutput
cache_hit_rate = coredns_cache_hits_total / (coredns_cache_hits_total + coredns_cache_misses_total) * 100

```


正常情况下，命中率应高于 80%，说明缓存生效。


## 五、运维与监控
独立使用 CoreDNS 时，需关注服务可用性、性能和错误情况，以下是关键运维操作。


### 1. 服务启停与重启
- 二进制部署（systemd 服务）：
```shell
systemctl start coredns    # 启动
systemctl stop coredns     # 停止
systemctl restart coredns  # 重启
systemctl reload coredns   # 重载配置（无需重启服务，推荐）
```

- Docker 部署：
```shell
docker start coredns     # 启动
docker stop coredns      # 停止
docker restart coredns   # 重启（修改 Corefile 后需重启）
```

### 2. 日志查看与分析
- 二进制部署：日志默认输出到标准输出，通过 systemd 查看：
```shell
journalctl -u coredns -f  # 实时查看日志
journalctl -u coredns --since "1 hour ago"  # 查看1小时内的日志
```

- Docker 部署：
```shell
docker logs -f coredns  # 实时查看日志
docker logs coredns --since 1h  # 查看1小时内的日志
```

- 日志分析重点：
  - 错误日志（如 [ERROR] 开头）：上游 DNS 不可达、配置文件错误、端口被占用
  - 慢查询（duration 字段过大，如超过 1000ms）：上游 DNS 响应慢、网络延迟高。

### 3.监控指标（Prometheus + Grafana）
CoreDNS 暴露的 Prometheus 指标可用于监控关键性能指标，以下是常用指标：

|指标名称	|说明
|---        |---
|coredns_dns_requests_total	|总DNS 请求数（按域名、类型、协议分类）
|coredns_dns_responses_total	|总 DNS 响应数（按响应码、域名分类）
|coredns_cache_hits_total	|DNS 缓存命中数
|coredns_cache_misses_total	|DNS 缓存未命中数
|coredns_forward_requests_total	|转发到上游 DNS 的请求数（按上游地址分类）
|coredns_forward_healthcheck_failures_total	|上游 DNS 健康检查失败数
|coredns_dns_request_duration_seconds	|DNS 请求响应时间分布（直方图）


- 配置 Prometheus 抓取指标

在 Prometheus 的 prometheus.yml 中添加 Job：

```yaml
scrape_configs:
  - job_name: "coredns"
    static_configs:
      - targets: ["<CoreDNS IP>:9153"]  # CoreDNS 暴露的 Prometheus 端口
    scrape_interval: 15s  # 每 15 秒抓取一次
```

- 导入 Grafana 仪表盘

CoreDNS 官方提供 Grafana 仪表盘模板，ID 为 10080（CoreDNS Dashboard），导入后可直观查看解析成功率、缓存命中率、响应时间等指标。



### 4.常见问题排查

|问题现象	| 排查步骤                                                                                                 |   |
|---        |------------------------------------------------------------------------------------------------------|--- |
|CoreDNS 启动失败	| 1. 检查端口是否被占用：`netstat -tulpn	                                                                        |grep 53；<br>2. 查看日志：journalctl -u coredns或docker logs coredns；<br>3. 检查 Corefile 语法：coredns -conf Corefile -validate`。
|DNS 解析失败（返回 NXDOMAIN）	| 1. 确认域名是否存在（用公共 DNS 测试：dig @8.8.8.8 域名）； 2. 检查 Corefile 中是否有该域名的解析规则；3. 查看上游 DNS 是否正常（forward 插件日志）。 | |
|解析速度慢	| 1. 检查缓存命中率（Prometheus 指标 coredns_cache_hits_total）；2. 检查上游 DNS 响应时间（coredns_forward_request_duration_seconds）；3. 优化缓存配置（增加缓存时长、预取）。| |

| 部分域名解析异常	 |1. 检查该域名对应的 Zone 配置是否正确；2. 确认 forward 插件的上游 DNS 是否支持该域名解析；3. 查看该域名的日志（过滤 {name} = 异常域名）。| |


## 总结
CoreDNS 作为独立 DNS 服务器，具备 灵活扩展、配置简单、性能优异 的特点，通过插件化架构可满足本地缓存、自定义解析、加密转发、监控告警等多种需求。关键要点总结如下：

- 部署选择：二进制部署适合稳定环境，Docker 适合快速测试，K8s 部署适合容器化场景。
- Corefile 核心：围绕 “Zone + 插件” 构建配置，常用插件包括 forward（转发）、cache（缓存）、file/hosts（静态解析）、log/errors（日志）。
- 运维重点：关注日志错误、缓存命中率、上游 DNS 健康状态，通过 Prometheus + Grafana 实现可视化监控。
