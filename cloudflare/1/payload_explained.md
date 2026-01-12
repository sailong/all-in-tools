**payload.json 说明片段**

该文档为 [cloudflare/1/payload.json](cloudflare/1/payload.json) 中各项配置提供逐条说明，便于在修改或生成 payload 时参考。

- **config.ingress[0]**:
  - service: `http://127.0.0.1:443`
  - hostname: `bash.ccwu.cc`
  - 说明: 将请求路由到本机 127.0.0.1 的 443 端口，适用于在本机运行 HTTPS 服务并希望通过隧道暴露该主机名的场景。`originRequest` 为空对象，表示使用默认回源请求设置。

- **config.ingress[1]**:
  - service: `http://localhost:35001`
  - hostname: `www.csl.cs.do`
  - 说明: 将 `www.csl.cs.do` 的流量转发到本机 35001 端口的 HTTP 服务。

- **config.ingress[7]**:
  - service: `http_status:404`
  - 说明: 默认回源规则（最后一条通常不带 hostname），当未匹配到前面的 hostname 时返回 404 状态。将其置于 ingress 列表末尾以作为 catch-all 行为。

- **config.warp-routing**:
  - `{"enabled": false}`
  - 说明: warp-routing 功能是否启用。示例中为 `false`，表示未启用。根据需要可改为 `true` 并在 tunnel/网络配置中做相应调整。

使用建议
- 在修改 `payload.json` 前，先使用 `run/get.py` 获取当前配置并保存备份（用于回滚）。
- 在生产环境更新前，在测试隧道或预生产环境使用相同 payload 进行验证。避免直接在生产 tunnel 上执行未经验证的 PUT。

引用：请参阅 [cloudflare/1/payload.json](cloudflare/1/payload.json) 获取原始示例内容。