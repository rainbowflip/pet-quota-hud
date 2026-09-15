# 本机验证 · 2026-09-15

- Swift 6.3.2，使用 Swift 5 language mode 编译；macOS 26、arm64。
- Codex `0.154.0-alpha.6.2`，由 `/Applications/ChatGPT.app` 提供。
- 19 项 Swift 检查通过：额度窗口顺序、缺失字段、无关 bucket、零值、节流、隐藏、工作/待机间隔、重置时间、副屏负坐标和边缘限制。
- 安装器检查通过：保留外部 Hook、重复安装幂等、卸载仅移除自己的四项 Hook。
- 真实二进制 Hook 检查通过：输出 `{}`，事件落盘，不保留提示词或原始 session ID。
- 官方 `account/rateLimits/read` 真实请求成功，安装后主程序自动刷新并写入数值缓存。
- 安装后 `--diagnose` 返回 `petVisible=true`，实际宠物位于负 X 坐标的副屏。
- 独立 HUD 预览 PNG 已渲染并检查；真实桌面位置是否符合用户视觉预期仍需用户确认。
- 可见待机短测：15 秒累计 CPU 时间增加约 0.09 秒（单核约 0.6%），`ps` 采样 CPU 约 0.3%，RSS 51,936 KiB（约 50.7 MiB）。仅为该机器短时样本，未覆盖额度请求子进程峰值、拖动和长时工作。
- 已写入 SessionStart / UserPromptSubmit / Stop / Interrupt，各一个异步 handler。尚未验证 Codex 信任后的真实生命周期触发；必须由用户审核信任，之后新任务验证。轮询路径已验证。

不修改原生 pet.json、spritesheet 或 Codex app.asar；不调用额度重置消费接口。
