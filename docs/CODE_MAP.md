# 代码导览

## 启动与界面

`tools/create-user-materials.ps1` 和 `BuildUserMaterials.cs` 将用户主题图、六张生成的透明角色图及用户影片制作成117个素材槽位。它们不调用模型，绘图由安装会话按 `docs/IMAGE_PROMPTS.md` 完成。`tools/prepare.ps1` 从仓库外校验并导入运行素材，再编译原生窗口。`sakura-studio/start.ps1` 负责本地服务的启动、版本与目录身份检查。默认控制中心是 `SakuraControl.cs` 原生窗口；`index.html`、`style.css`、`app.js` 是网页备用入口。

`server.mjs` 提供仅绑定回环地址的本地接口，协调启动、换肤和桌宠。静态文件使用白名单；操作接口要求每次服务启动生成的会话令牌。

## 功能模块

| 文件或目录 | 责任 |
| --- | --- |
| `lib/workspace.mjs` | 一键工作空间流程、步骤状态与取消 |
| `native-bridge.ps1`、`lib/cdp.mjs` | 验证专用应用进程、定位窗口和连接本机调试接口 |
| `lib/renderer.mjs`、`lib/selectors.json` | 注入/恢复主题、区分用户气泡与助手阅读面板 |
| `lib/boot-readiness.mjs` | 判断主界面是否已布局并可衔接 |
| `lib/boot-monitor.mjs` | 持续更新目标窗口和就绪标记，窗口替换时先撤销旧权限 |
| `MovieBoot.cs`、`BootHandoff.cs` | 原尺寸视频、后台等待、末帧停留和真实窗口过渡 |
| `LoadingLoop.cs` | 用户影片默认仅四角花瓣；旧演示构图另有固定 Logo 流光模式 |
| `BootEscape.cs` | 动画期间拦截 Esc；就绪后允许跳过，结束后释放钩子 |
| `quota-pet/widget.ps1`、`runtime` | 额度读取、桌宠界面、跟随窗口和音效 |
| `lib/pet-themes.mjs` | 单个可替换角色槽位的外观映射 |

桌宠继承自 GPT-Niang 的运行组件。整合版不使用其独立安装器、MCP 注册或上游自动更新；元数据与安装文件清单按实际整合文件修正。历史上游更新辅助代码保留用于来源和兼容，不构成额外已启用功能。

## 数据与维护边界

`NativeTcp.cs` 直接读取 Windows TCP 监听表；`native-bridge.ps1` 仍验证进程、安装目录及专用配置目录。`build-pet-native.ps1` 从既有源码生成 `WidgetNative.dll`，避免桌宠每次启动现场编译。两个DLL均由准备程序在本机生成，不进入公开源码包。

工坊设置、专用窗口配置、额度缓存及运行日志保存在 `sakura-studio/state`。普通桌面应用的配置仍由原应用管理。`state` 不随源码包分发，源码无需放入个人访问令牌。

替换素材请更新 `materials` 和清单；调整窗口选择器后运行主题与就绪检查；调整原生窗口代码后运行完整 Windows 测试。不要通过改动第三方自动更新脚本来覆盖本整合版。

## 公开源码与本地素材

materials只保存需求清单和历史来源声明。index-materials.py在外部目录建立实际校验清单；prepare.ps1校验目标槽位后生成运行文件和被忽略的materials.local.json。audit:source不依赖素材；audit:runtime核对已导入文件。LOCAL-ONLY运行包与不含媒体的源码导出分别处理。
