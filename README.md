# Pet Quota HUD

独立 macOS 菜单栏小程序：在 Codex 原生宠物头顶显示五小时剩余额度（绿条）、周剩余额度（蓝条）、可用重置次数（金色徽章）。不修改 Codex 安装包，不更换宠物素材，不注入代码。退出即可移除显示。

![预览，示例数据](preview.png)

## 构建、安装

需要 macOS 13+、Xcode Command Line Tools（Swift），安装脚本需要 Python 3。当前在 macOS 26 / Apple Silicon / Codex CLI 0.154.0-alpha.6.2 上验证。仅支持当前桌面版直接坐标格式，旧版窗口相对坐标会安全隐藏。

```sh
bash scripts/build.sh
bash scripts/test.sh
python3 scripts/install.py --dry-run
python3 scripts/install.py
```

安装到 `~/Applications/Pet Quota HUD.app` 并启动，菜单栏 `◈` 可刷新、上下微调、退出。默认不设置开机自启；需要时可自行加入 macOS 登录项。独立程序使用本机 Codex CLI 已登录的账号，若与桌面选中的账号不同，需先统一登录状态。

安装器保留现有 Hook，备份 `~/.codex/hooks.json` 后合并本程序四个事件。**必须在 Codex 的 Hook 审核界面信任新增配置**（CLI 可用 `/hooks`），新任务加载后生效。程序不会修改信任哈希或跳过审核。信任前仍能按五分钟轮询；未收到开始事件时无法判定工作状态。只需要轮询可安装时加 `--without-hooks`。

```sh
python3 scripts/install.py --uninstall
```

卸载只移除本应用和本应用的 Hook，保留其他配置、备份和数值缓存。安装/卸载均不操作原生提莫文件。不要在本程序运行时覆盖升级，先从菜单栏退出。

## 刷新机制

| 时机 | 行为 |
| --- | --- |
| SessionStart / UserPromptSubmit | 请求异步刷新 |
| Stop / Interrupt | 延迟约 2 秒刷新 |
| 同时多个事件 | 合并；两次请求至少间隔 10 秒 |
| 正在工作且宠物可见 | 每 60 秒兜底 |
| 待机可见 | 每 5 分钟兜底 |
| 宠物重新显示 / 系统唤醒 / 窗口额度重置 | 请求刷新 |
| 隐藏 | 不发起新的请求；已有请求最多 20 秒结束 |
| 请求失败 | 保留旧值、颜色变暗，菜单显示失败 |

长任务状态按脱敏后的 session 记录；未收到 Stop 的状态最多保留 6 小时。只保留每个 session 最新 Hook（同一秒快速结束会合并）。同一 session 同时多个 turn 的状态不是精确计数；额度仍由官方读接口返回。未知额度显示横线、未知重置次数显示问号，绝不补零。旧缓存超过 10 分钟变暗。

## 数据和性能

- `Sources/Core.swift`：官方 app-server stdio 客户端、数值模型、Hook 信号和刷新策略。只调用 `initialize`、`account/rateLimits/read`，不调用任何执行任务/消费重置接口。无模型生成请求。
- `Sources/Desktop.swift`：只读宠物状态文件的开关与坐标，并查询系统窗口几何元数据；不截图、不读取消息。支持副屏负坐标、点击穿透、隐藏跟随、屏幕边缘限制。原生消息在更高窗口层；发生重叠时消息优先，HUD 不挪动原生消息。
- 坐标检查 4 次/秒；状态文件未变化时不重解析，数值不变不重绘。不是动画渲染循环。仅读取显示几何，不要求辅助功能/录屏权限。
- 每次额度请求启动一个短期 Codex app-server（超时 20 秒），启动开销高于单纯文件读取；10 秒节流限制突发请求，不声称零开销。Codex 自身可能初始化数据库/运行时记录。
- 缓存目录：`~/Library/Application Support/PetQuotaHUD`。仅有数值额度、时间、Hook 类型和 SHA256 后的 session ID；不保存提示词、原始会话 ID 或令牌。本代码不读取 `auth.json`，登录由官方 CLI 处理。
- `PET_QUOTA_CODEX` 可指定 CLI 绝对路径，`CODEX_HOME` 可指定 Codex 配置目录，`PET_QUOTA_HUD_HOME` 可指定测试缓存目录。需在直接启动进程环境设置，Finder 启动不继承终端变量。

## 诊断和复用

```sh
'dist/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' --probe
'dist/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' --diagnose
'dist/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' --snapshot /tmp/pet-hud.png
'dist/Pet Quota HUD.app/Contents/MacOS/PetQuotaHUD' --demo
```

`--probe` 只输出数值额度；`--diagnose` 只输出是否找到宠物及原生浮动窗口几何。`--demo` 显示固定示例值，不能拿来判断真实额度。源代码不包含英雄联盟素材，可直接参考适配其他宠物。

已知兼容边界：原生宠物定位字段与默认尺寸 112×121 并非稳定公共 API；Codex 升级后可能需要改 `PetTracker`。位置采样最高有约 250ms 延迟，默认偏移适合当前提莫，其他宠物可在菜单调整。无法强制原生消息为第三方 HUD 留白，发生交叠时优先显示原生消息。

参考：[官方 App Server](https://learn.chatgpt.com/docs/app-server)、[官方 Hooks](https://learn.chatgpt.com/docs/hooks)、[macOS 社区 HUD](https://github.com/himomohi/codex-pet-hud)、[Windows pet dock](https://github.com/hjxccc/codex-pet-dock)。社区定位思路的许可见 THIRD_PARTY_NOTICES。
