# 樱色工坊 Sakura Studio

Windows 本地工具，整合界面主题、角色额度桌宠与启动动画。当前版本 **0.9.6**，此目录是**公开源码版，不附带运行素材**。

本次更新包含启动提速、异常退出后的端口恢复和桌宠隐藏窗口恢复。见 [更新记录](docs/CHANGELOG.md)；本机测试范围与限制见 [验证说明](docs/VERIFICATION.md)。

**日常使用的是 Windows 原生窗口应用。** 完成素材准备和编译后，双击 `sakura-studio/启动樱色工坊.cmd` 或 `SakuraControl.exe` 打开控制窗口，系统托盘提供桌宠开关等操作。日常使用不需要打开 Edge，也不需要安装 Playwright。

## 让 GPT 帮你安装

**复制本仓库链接 + 上传一张主题参考图 + 上传你自己的启动影片**，发送给能操作本地文件、使用终端并生成图片的 Windows GPT/Codex 桌面会话。

复制 [完整安装提示词](docs/INSTALL_WITH_AI.md)，让它下载仓库、制作同一角色的常态/思考/待确认及闭眼图，再自动生成全部 117 个运行素材文件、处理影片、编译和检查。无需找原作者索取素材包。普通聊天窗口、没有绘图工具的会话无法保证自动完成；提示词会如实检查所需能力。

- [图片制作提示词](docs/IMAGE_PROMPTS.md)
- [视频口播和简介模板](docs/VIDEO_POST.md)
- [素材生成与命令说明](docs/INSTALL_WITH_AI.md#自动制作工具)

新生成的基础循环包含眨眼和轻微整体呼吸/倾动。原演示中的精细分层动画依赖原素材，不能仅凭源码复现。符合输入要求的用户影片会保留末帧，并使用通用花瓣等待层；不会套用演示 Logo 的固定流光路径。

适用于 Windows 10/11 x64 上的 Codex 桌面应用（应用包 `OpenAI.Codex`），不直接修改普通浏览器中的 ChatGPT 网页。换肤使用单独的应用配置目录，首次登录由用户自行完成。应用版本变化后可能需要更新选择器。

## 上传范围

可以将本目录作为公开 GitHub 仓库的根目录。代码、第三方许可、素材需求清单和测试工具已保留；主题图、人物贴图、视频、音效、语录数据及旧的完整素材包均未放入公开目录。本机账号、缓存、聊天资料、日志和测试依赖也不包含在源码包内。

素材清单中的文件名与参考校验值仅用于说明程序所需文件，不表示这些素材已获公开分发授权。代码许可和素材权利分别处理，见 [许可范围](docs/LICENSES.md)。

## 首次运行

1. 安装 Node.js 22 或更新版本，并安装、打开过 Codex 桌面应用。准备程序使用 Windows 自带的 .NET Framework 编译原生窗口。自动制作新素材还需要完整的 FFmpeg/FFprobe，包含 libx264、AAC、PNG 编码及 reverse/scale 滤镜；可从 [FFmpeg 官网列出的 Windows 构建](https://ffmpeg.org/download.html#build-windows)获取。
2. 按 [素材配置说明](materials/README.md)，在仓库外准备你有权使用的素材及 manifest.json。
3. 在仓库根目录打开 PowerShell，指定外部素材目录并准备程序：

```powershell
$env:SAKURA_MATERIALS = "E:\MyMaterials\SakuraStudio"
npm run prepare:app
```

将示例路径换成自己的实际目录。也可直接运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/prepare.ps1 -MaterialDirectory "你的外部素材目录"`。若使用默认位置，可将素材放在本机 LocalApplicationData 下的 SakuraStudio/materials，再双击 prepare.cmd。

准备程序会把素材导入被 Git 忽略的运行目录，并编译控制窗口、启动窗口和辅助库。之后进入 `sakura-studio` 文件夹：双击「启动樱色工坊.cmd」打开控制窗口；「启动换肤桌面.cmd」会启动专用换肤窗口。需要按保存的开关启动全部模块时，使用「一键启动工作空间.cmd」。需要桌面快捷方式时，运行「安装主题快捷方式.ps1」。

首次进入专用窗口需要自行登录；若另一个目录的工坊正在运行，请先通过原控制中心关闭工具再使用新副本。运行资料保存在被 Git 忽略的 sakura-studio/state。

## 目录

| 目录 | 用途 |
| --- | --- |
| materials | 仅素材需求清单、来源声明和导入说明，不含媒体 |
| sakura-studio | 控制中心、本地服务、换肤逻辑和原生窗口代码 |
| tools | 素材索引、准备运行、源码检查、测试、打包与导出 |
| docs | 代码导览、验证范围和许可说明 |

## 开发者检查与导出

普通使用可以跳过本节。源码检查本身不需要个人素材或浏览器；开发者可先安装锁定的测试依赖，再检查源码：

```powershell
npm ci --ignore-scripts
npm run audit:source
```

完整 Windows 测试需要已配置的外部素材、完整 FFmpeg/FFprobe（加入 PATH）、Playwright 测试依赖和可交互桌面。`npm test` 会重新运行准备程序，因此本例保留素材环境变量：

```powershell
$env:SAKURA_MATERIALS = "E:\MyMaterials\SakuraStudio"
npm run prepare:app
npm run audit:runtime
npm test
```

**以下浏览器要求仅适用于开发者自动化测试：** `npm test` 中的网页样式回归检查由 Playwright 调用 Microsoft Edge；测试人员可用 `SAKURA_TEST_BROWSER` 指定其他 Chromium 系浏览器。这与原生控制应用的启动和日常使用无关。原生实键测试只向自己的测试窗口发送 Esc。检查结果写入被忽略的 `reports`，具体通过项及焦点限制见 [验证记录](docs/VERIFICATION.md)。

Python 3.11 或更新版本可执行 `python tools/export-source.py`，按 Git 文件列表导出不含媒体的公开源码 ZIP。此命令需要 Git 仓库；如果使用源码 ZIP 解压的副本，请先在根目录执行 `git init`（不会自动提交）。`python tools/package.py` 则制作含个人素材的 LOCAL-ONLY 运行包，请勿将它当作公开源码包上传；它不会为导入素材增加任何授权。

GitHub Actions 只编译原生代码、检查公开源码并运行资源和流程逻辑测试，不依赖个人素材，也不代替本机窗口交互测试。结构说明见 [代码导览](docs/CODE_MAP.md)。

## 来源

感谢以下项目提供的代码基础和功能设计参考：

| 项目 | 参考或集成内容 |
| --- | --- |
| [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) | 桌面主题选择器与换肤思路；相关声明见 `sakura-studio/THIRD-PARTY-NOTICES.txt`。 |
| [Dragon Codex Boot](https://github.com/yushua0808-cpu/dragon-codex-boot) | 启动动画与 DWM 窗口衔接的设计和互操作代码；许可见 `sakura-studio/DRAGON-BOOT-LICENSE.txt`。 |
| [GPT-Niang](https://github.com/T7moris/GPT-Niang) | 桌宠及额度运行组件；许可和修改说明见 `sakura-studio/quota-pet/LICENSE`、`sakura-studio/quota-pet/MODIFICATIONS.md`。 |
| [codex-bailong-desktop-pet](https://github.com/Wunsch2048/codex-bailong-desktop-pet) | 胶囊、日报和用量展示等功能与交互设计参考；具体整合范围见 `docs/PET_ACTIVITY.md`。 |

代码集成与功能设计参考分别列出，不表示完整移植全部上游功能。各项目的版权、许可和修改声明均须保留；参考项目的图片、角色、影片和音乐不因此取得分发授权。本项目与 OpenAI、Valve 及参考项目维护者无隶属关系。

本项目原创代码和文档采用 [MIT许可](LICENSE)，第三方组件仍须保留各自许可和声明；用户素材、参考角色和商标不在代码许可范围内。其他公开仓库也应逐个查看许可证，公开可见不等于允许任意复用。[GitHub许可说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)

资源占用修复与本轮验证限制见 [资源检查](docs/RESOURCE_CHECK.md)。
