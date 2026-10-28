# 外部素材配置

公开仓库中只保留清单和说明，**不提供图片、视频、音效或语录数据的下载**。请使用你有权使用的素材，保存在仓库外。

## 文件布局

materials/manifest.json 列出程序所需的117个文件槽位（含97张动画帧）、运行目标和之前本地素材的参考SHA-256。所有槽位均标为 bundled: false，原素材未随仓库发布。原SHA-256仅是历史参考，导入校验使用你自己生成的外部清单。

**推荐方式：**上传一张主题参考图和自己的启动影片，把 [安装提示词](../docs/INSTALL_WITH_AI.md) 发给支持本地操作和绘图的桌面会话。它会生成六张角色姿态图，再运行 `tools/create-user-materials.ps1` 自动补齐所有槽位，不需要手工制作117个文件。详见 [角色图提示词](../docs/IMAGE_PROMPTS.md)。

外部目录应包含 theme、pet 两个子目录，以及自己的 manifest.json。文件名可按清单保持不变；目标文件名是程序接口，不要求图片内容沿用原来的角色。

- theme/sakura-calm-soft-portrait.png：PNG主题背景。
- theme/sakura-opening.mp4：H.264/AAC启动视频；原本地视频为1344×768、约9.4秒。
- theme/sakura-opening.poster.png、sakura-opening.end.png：封面与末帧。
- theme/launcher.ico：自己有权使用的图标。
- pet/sakura-soft-bust.png：单个角色的透明背景桌宠贴图。
- pet/gpt-dragon-niang-bust.png、upstream-preview.png：兼容元数据需要的图片，可放入自己的适当图片。
- pet/press.wav、release.wav：WAV音效。
- pet/quotes.json、quote-layouts.json：本地语录与布局数据。
- 其余文字文件为相应素材来源和许可说明；应如实描述自己的素材。

通过新生成工具导入的影片，末帧只叠加通用四角花瓣，不叠加固定Logo路径。旧清单未声明 `openingOverlay: "petals-only"` 时仍保留原演示构图的流光模式；不要用该模式套任意影片。生成工具输出的静音WAV及通用英文台词不取自历史角色素材。

## 建立自己的校验清单

将有权使用的文件按清单路径放入外部目录后，运行：

```powershell
python tools/index-materials.py "你的外部素材目录"
```

这会为实际文件生成SHA-256及外部manifest.json，不会改变公共清单，也不构成素材授权。导入工具会验证目标槽位完整、路径受限且文件校验一致。

```powershell
$env:SAKURA_MATERIALS = "E:\MyMaterials\SakuraStudio"
npm run prepare:app
```

将示例路径换成真实目录。导入后的文件仅放在被忽略的运行目录，公共源码导出器仍拒绝媒体文件。不要将个人素材放回仓库；要公开分发其他素材时，应先确认对应权限并主动调整项目的分发策略。

## 历史来源声明

notices 保留原素材的来源和许可文字，以说明为什么本公开版不分发原素材。这些文字不意味着相应媒体已经随仓库提供，也不扩大其授权范围。
