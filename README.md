# 小鲸鱼气泡 · dsh-whale-bubble

桌面上悬浮一只 **DeepSeek 官方小鲸鱼**，作为 DeepSeek Harness 的桌面状态挂件：

- 常驻 **62×62** 透明置顶窗口，不抢焦点、不进任务栏、点击穿透；
- **工作时游动**：整只鲸鱼是一条闭合路径，尾巴做弯曲形变上下摆动（零接缝）；
- **悬停显示进度卡**：标题 / 第 N 步 · 用时 / 当前动作摘要 / 细进度条，移开自动收起；
- **完成时提醒**：鲸鱼跳一下 + 左上角小绿点 + 提示音；
- **点击切换 DSH 窗口**：不在前台→还原置前，已在前台→最小化；可拖动、位置记忆。

![平时：只有鲸鱼](docs/bubble.png)
![悬停：工作中](docs/hover-working.png)
![悬停：完成态](docs/hover-done.png)

游动动画（从运行中的悬浮窗抓帧）：

![游动动画](docs/swim.gif)

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | Windows 10 / 11 |
| 运行时 | Windows PowerShell 5.1（系统自带，无需安装） |
| Harness | DeepSeek Harness Desktop（`desktop` profile），插件 API 基于 `@deepseek-ai/cordis` 4.x |
| 依赖 | 无第三方 npm 依赖、无构建步骤 |

## 安装

```sh
git clone https://github.com/Arashi1012/dsh-whale-bubble.git
dsh plugin --profile desktop add "<克隆下来的目录绝对路径>"
```

也可以让 Agent 用插件管理器的 `install_bundle` 指向该目录安装。安装后插件立即生效并自动拉起桌面气泡；
重启 DSH 会自动加载。

卸载：

```sh
dsh plugin --profile desktop remove dsh-whale-bubble
```

## 配置

`cordis.patch.yml` 中的 `config`：

```yaml
- insert:
    - id: whale-bubble
      name: 'dsh-whale-bubble'
      config:
        port: 43980    # 本机状态服务端口，被占用时自动顺延
        sound: true    # 完成任务时是否播放提示音
```

## 工作原理

- **Host 插件**（`index.js`）监听 Harness 的 `session/event`（`turn/start`、`tool/call`、`assistant/message`、`turn/end`），
  在 `127.0.0.1` 上暴露 `/state`，并拉起 / 看护桌面气泡进程；子智能体会话不触发完成提醒。
- **气泡本体**（`whale-bubble.ps1`）是 Windows PowerShell 5.1 + WPF 的透明置顶窗口，
  轮询 `/state` 渲染动画与悬停卡片。
- **尾巴动画**：启动时把 `whale.svg` 的官方 path 扁平化，在尾巴根部两个颈部点处拆成身体段（138 点）与尾鳍段（85 点）；
  每帧重建一条闭合路径，尾鳍各点按到根部弦线的距离加权绕该点旋转（根部 0°、尾尖最大 ±14°），
  配合 `GeometryGroup` 非零填充保留白肚/白眼孔洞 —— 所以尾巴摆动时轮廓始终连续，静止时与官方 logo 完全一致。
- **悬停**：分层窗口只有不透明像素可命中；卡片展开后用 Win32 `GetCursorPos + PtInRect` 轮询判断光标是否仍在窗口内，
  避免窗口放大瞬间 WPF 误发 `MouseLeave` 造成的闪烁。

调试端点（仅回环）：`GET /state`、`/health`、`/log`、`/screenshot`（自渲染快照）、`/demo`（演示完成提醒）、`POST /quit`。

运行时文件位于 `%LOCALAPPDATA%\dsh-whale-bubble\`：`plugin.log`、`bubble.log`、`position.json`、`preview.png`。

## 已知限制

- 仅 Windows（WPF + Win32）。
- 只跟踪根会话，子智能体会话结束不会触发完成提醒。
- 进度卡片只在悬停时出现；空闲时悬停不会弹出空卡片。
- 气泡按层窗口逐像素命中：鲸鱼与卡片的不透明像素可点可拖，其余区域点击穿透。

## 许可证与致谢

- 代码：MIT，见 [LICENSE](LICENSE)。
- 鲸鱼标志：`whale.svg` 取自 DeepSeek Harness Web 前端 `favicon.svg`（DeepSeek 品牌资产，版权归 DeepSeek 所有）；
  本仓库仅将该标志用作插件的图标与动画素材，详见 [NOTICE.md](NOTICE.md)。
- 本插件与 DeepSeek 官方无隶属关系。
