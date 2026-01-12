Cloudflare 隧道（cloudflared）配置获取与更新工具

说明
该目录包含通过 Cloudflare API 获取与更新 cfd_tunnel（cloudflared 隧道）配置的示例脚本与 Python 实现。适用于需要批量或自动化管理隧道 ingress 配置的场景。

依赖
- `bash` 与 `curl`：用于顶层脚本 [cloudflare/1/get_config.sh](cloudflare/1/get_config.sh) 与 [cloudflare/1/put_config.sh](cloudflare/1/put_config.sh)。
- `python3` 与 `requests`：用于 [cloudflare/1/run/get.py](cloudflare/1/run/get.py) 与 [cloudflare/1/run/put.py](cloudflare/1/run/put.py)。可通过 `pip install -r requirements.txt` 安装。

环境变量（必填）
- `ACCOUNT_ID`：Cloudflare 帐号 ID。
- `TUNNEL_ID`：要操作的隧道 ID。
- `ACCOUNT_EMAIL`：Cloudflare 帐号邮箱（用于旧式 Global API Key 的头部认证）。
- `ACCOUNT_KEY`：Cloudflare API Key / Global API Key 或等效凭证。

可选参数
- `PAYLOAD_FILE`：用于 `put` 脚本，指向包含更新配置 JSON 的文件路径（优先于 `PAYLOAD`）。
- `PAYLOAD`：用于 `put` 脚本，直接传入 JSON 字符串作为请求体（调试用途，不推荐在 shell 历史中暴露）。

示例命令
在命令前临时设置环境变量并运行 GET（shell）：

```bash
ACCOUNT_ID=your_account_id TUNNEL_ID=your_tunnel_id ACCOUNT_EMAIL=you@example.com ACCOUNT_KEY=your_api_key bash cloudflare/1/get_config.sh
```

使用外部 JSON 文件更新（shell）：

```bash
ACCOUNT_ID=your_account_id TUNNEL_ID=your_tunnel_id ACCOUNT_EMAIL=you@example.com ACCOUNT_KEY=your_api_key PAYLOAD_FILE=payload.json bash cloudflare/1/put_config.sh
```

运行 Python 脚本（需先安装依赖）：

```bash
python3 cloudflare/1/run/get.py
python3 cloudflare/1/run/put.py  # 支持通过环境变量设置 PAYLOAD_FILE
```

安装 Python 依赖：

```bash
python3 -m pip install --user -r cloudflare/1/requirements.txt
```

日志
- GET 响应写入 [cloudflare/1/run/get.log](cloudflare/1/run/get.log)。
- PUT 响应写入 [cloudflare/1/run/upd.log](cloudflare/1/run/upd.log)。

安全与注意事项
- 请勿将 `ACCOUNT_KEY` 等敏感信息提交到版本控制。推荐使用环境变量、CI secret 或密钥管理服务（vault）。
- 在生产环境中，限制对日志文件的访问权限，避免泄露敏感配置信息。
- `put` 操作会覆盖隧道配置，请在执行前确认 payload 内容并在非生产环境先行验证。

扩展建议
- 若需在 CI 中自动化运行，使用 CI secret 注入环境变量并在运行前做一次 `get` 验证与差异检查。

若需我代为生成 `payload.json` 示例或将脚本改成接受 CLI 参数（`--account-id` 等），请回复确认。

示例 payload 文件
示例 payload 已放置于 [cloudflare/1/payload.json](cloudflare/1/payload.json)。使用示例：

```bash
ACCOUNT_ID=your_account_id TUNNEL_ID=your_tunnel_id ACCOUNT_EMAIL=you@example.com ACCOUNT_KEY=your_api_key PAYLOAD_FILE=cloudflare/1/payload.json bash cloudflare/1/put_config.sh
```

或使用 Python 脚本：

```bash
ACCOUNT_ID=your_account_id TUNNEL_ID=your_tunnel_id ACCOUNT_EMAIL=you@example.com ACCOUNT_KEY=your_api_key python3 cloudflare/1/run/put.py --payload-file cloudflare/1/payload.json
```
