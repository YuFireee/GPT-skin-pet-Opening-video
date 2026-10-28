# 把仓库链接发给 GPT，制作自己的主题

使用 Windows 桌面端中能读写本地文件、运行终端的 Codex 会话，并开启可用的图片生成功能。普通聊天窗口只会给出指导，不能仅凭一段提示词获得本机安装能力。工具权限、网络访问、生成额度和实际应用版本可能影响完成时间。

用户只需提供：**一个仓库链接、一张主题参考图、一段自己的启动影片**。下面六张角色图由图片生成工具依据参考图制作，不要求用户预先绘制。影片不由本项目下载或生成；本工具将用户上传的影片转换为兼容格式。

## 可直接复制的安装提示词

```text
请在这台 Windows 电脑上，下载我发的 GitHub 仓库并完成本地安装。我会上传一张主题参考图和一段启动影片。请先阅读仓库 README.md、docs/INSTALL_WITH_AI.md、docs/IMAGE_PROMPTS.md 和 docs/LICENSES.md，检查代码与运行要求后执行，不要只给我操作教程。

仓库：使用本消息或相邻消息中我提供的真实 GitHub 仓库链接，不要把参考项目误认为安装目标。识别默认分支或链接明确指定的分支，记录实际提交号。使用 Git 正常克隆到新的本地工作目录；没有 Git 时可下载 GitHub 对应分支的源码 ZIP，并验证下载成功。不要覆盖已有工坊或用户设置。

先检查本地文件/终端、图片生成功能、Node.js 22+、Windows .NET Framework、FFmpeg/FFprobe；只安装缺少的必要依赖，使用官方来源并遵守当前环境审批要求。没有图片生成功能时明确告知缺什么，继续完成代码检查；不能用静态占位图冒充已经完成的角色动画。

识别我上传的主题图和影片，缺哪一个才询问哪一个。根据主题图的角色、服装和画风，使用图片生成工具自动制作六张真实透明背景PNG：idle.png、idle-blink.png、executing.png、executing-blink.png、confirmation.png、confirmation-blink.png。统一1024×1024画布、位置、比例、朝向和底线，完整保留头发、手臂与发饰，不要背景、文字、圆环和水印。先生成常态作为角色基准，再编辑出其他姿态和闭眼版本。闭眼版本只改眼睛。执行态手指托下巴思考；待确认态双手在脸颊两侧举内倾剪刀手。检查身份一致、透明通道、额外手指、断臂、裁切和闭眼对齐，修正有问题的图片。

主题图若已适合作为横向背景直接沿用；若是立绘或构图不适合阅读界面，请根据它生成匹配风格的横向主题背景，角色偏左，右侧留出阅读区域。不要通过放大低清图片谎称原生4K，不要求安装过程必须调用收费API或提交我的API密钥。

把输入及生成素材放在仓库外的个人素材目录，记录真实来源和使用范围，所有素材只用于本机。运行 tools/create-user-materials.ps1，传入主题图、启动影片、六张角色图所在目录、一个尚不存在的外部输出目录以及素材来源说明。它会生成全部117个运行槽位，包括97张基础循环动画帧、图标、预览、静音音效、通用台词、H.264/AAC影片、封面和真正末帧。这里的基础循环是姿态图加轻微整体呼吸/转动和眨眼，不等同于原作者逐区域制作的头发/头部动画；请如实说明。影片末帧默认仅叠加通用四角花瓣，不套用原视频的固定Logo路径。不要替我下载原作者角色素材、第三方启动影片或历史素材包。

运行 tools/prepare.ps1 导入新素材并编译，然后运行公开源码检查、运行素材检查、原生控制窗口检查和用户素材生成测试（tools/tests/check-user-materials.ps1；FFmpeg不在PATH时传入完整路径）。不要为了测试反复启动真实应用、查询账号或生成付费图片。依赖或测试不满足时报告具体原因，不虚报通过。

安装成功后打开樱色工坊控制窗口，展示静态预览；仅在我要求启动换肤/桌宠或本消息明确授权时才启动对应功能。首次登录由我自行完成。保留已有账号和聊天资料，不关闭其他目录的后台，不上传任何内容到GitHub。最后告诉我安装目录、启动方法、素材目录、实际通过的检查以及需要我操作的登录步骤。
```

## 自动制作工具

准备好图片生成工具输出的六张图后，在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/create-user-materials.ps1 `
  -ThemeImage "E:\MyTheme\theme.png" `
  -OpeningVideo "E:\MyTheme\opening.mp4" `
  -CharacterDirectory "E:\MyTheme\plates" `
  -OutputDirectory "E:\MyTheme\materials-new" `
  -MaterialNotice "用户提供参考图和影片；角色图由用户授权的图片生成工具制作；仅本机使用，未确认公开分发权。"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/prepare.ps1 `
  -MaterialDirectory "E:\MyTheme\materials-new"
npm run audit:source
npm run audit:runtime
node tools/tests/check-native-control.mjs
powershell.exe -NoProfile -File tools/tests/check-user-materials.ps1
```

把示例路径替换为实际路径。FFmpeg 不在 PATH 时传入 `-FFmpeg` 和 `-FFprobe` 的完整路径。输出目录必须是仓库外的新目录，避免覆盖已有素材。主题图不自动拉伸至4K；角色图必须具有真实透明通道、统一正方形画布，512～4096像素。影片要求横向、0.5～30秒；转换不提高原始分辨率，上限1920×1080。

构建助手只做确定性的图片适配、循环帧制作和媒体转码，**自身不调用模型、不联网下载素材**。AI绘图能力由运行安装提示词的会话提供。没有绘图工具时，用户也可自行提供同名六张透明PNG继续安装。

视频演示和公开源码是分开的：即使运行效果出现在演示视频里，观众安装时也须上传自己的素材。用户自行公开生成结果时，需另外核实参考角色、参考图、影片及标志的权利；AI生成不会自动消除这些限制。

官方桌面环境说明：[Windows 桌面端与本地开发工具](https://learn.chatgpt.com/docs/app/windows)。
