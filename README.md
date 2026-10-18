# glean

> 拾穗：收割之后，在田里把还值得留下的那一穗拣出来。

一个 macOS 自用的**相似图片挑拣工具**。目标不是"删重复"（Photos.app 自带的"重复项目"相册已经能做），而是它做不了的部分：

- 连拍整组：一梭子 20 张选 1 张
- 同一场景重拍：构图微调、换曝光
- 截图、翻拍、聊天记录里存回来的图
- 模糊 / 低质 / 被压缩坏的版本

## 命名

`glean` / 显示名 **glean**。包名 `GleanCore`、`GleanApp`，bundle id `com.spoon.glean`。
备选曾是 `winnow`（扬场）、`bowerbird`（园丁鸟）。

## 技术栈

```
Swift 6 + SwiftUI + PhotoKit + Vision + Accelerate
```
选型理由：

| 环节 | 方案 | 为什么 |
|---|---|---|
| 图库访问 | **PhotoKit** | 唯一被官方支持的方式；能拿到稳定的 `localIdentifier`，删除动作走系统 API |
| 缩略图 | `PHImageManager.requestImage` 512pt | 单张 ~10ms，`isNetworkAccessAllowed = false` 只读本地副本 |
| 相似度 | **Vision `VNGenerateImageFeaturePrintRequest`** | 768 维，跑在 ANE 上，零依赖；对重压缩/裁剪/调色/重拍的鲁棒性远好于 pHash |
| 分组 | 归一化向量 + 点积 + 并查集 | 连通分量天然出组，无需 K-Means 调参；个人库规模 O(n²) 够用 |
| 选优（待做） | `CalculateImageAestheticsScoresRequest` + 拉普拉斯方差 + 分辨率 | 组内自动推荐"留这张" |
| 缓存（待做） | SQLite + Float32 BLOB | 增量扫描靠 `localIdentifier + modificationDate` |

**为什么不用 Python / Electron / Tauri**：为一个自用工具背 Python + torch（2GB）或 Electron 运行时（200MB）都不值；而 macOS 上最好的图像相似度模型本来就已经在系统里了。

## 怎么用

**最短路径：双击 `build/Glean.app`。** 不需要装任何东西，也不用开 Xcode。

打开后：

1. **请求相册访问权限** → 系统弹窗里选「允许」（也可以选「仅选中」先小范围试）
2. 工具栏选**分析范围**（最近 1/3/6 个月、1 年、全部，括号里是该范围的片数）
3. 点**扫描图库** → 底部状态栏显示「读取相册 1200/7624」
4. 点**分析** → 底部状态栏显示阶段和进度条，左侧出现相似组卡片

界面是顶部共用一条系统工具栏，下面三栏：

| 栏 | 内容 |
|---|---|
| 左 | 相似组卡片，两列。卡片顶部并排显示组内前 3 张缩略图 |
| 中 | 选中那一组的照片。单击选中，⌘/Shift 点击多选，双击或空格看大图 |
| 右 | 选中照片的详细信息（文件名、尺寸、时间、清晰度、组内相似度…） |

键盘：中栏 `←→` 换照片、`空格` 开关大图、`回车` 标记/取消待删除；
大图里 `←→` 翻看、`空格` 退出。左栏只用鼠标点击。

**标记待删除 = 加进 `glean 待删除` 相册**（PhotoKit 不暴露关键词，相册就是标签）。
不复制文件，状态存在系统里；之后在 Photos.app 里打开这个相册、全选 `⌘⌫` 就是原生删除，
30 天内可从“最近删除”恢复。

**评分是软加载的。** 分组算完立刻出列表，只有你点开某一组时才给那组算清晰度和人脸。
实测全库 7624 张：特征 39 秒 + 分组 2 秒就能看到全部 984 组；如果一上来就全量评分要
228 秒，其中 187 秒都花在评分上。

**现在还不会删任何东西**——只把「哪几张是一组、该留哪张」算出来给你看。

> ⚠️ 别在 Xcode 里选 `GleanApp` scheme 运行，也别 `swift run`。那是没有 bundle 的裸可执行文件：窗口建不出来、相册也读不到。真跑了它会直接提示你怎么做。

## 管线

```
时间切片（间隔 >5min 断开一个会话）
    ↓   候选集从全库（十万对级）降到会话内（几十~几百对）
会话内聚类：阈值是时间间隔的函数
    ↓   ≤2s → 0.65 / ≤30s → 0.70 / ≤5min → 0.78
代表图（medoid）跨会话合并：仅视觉，≥0.88
    ↓   改天重回同一地点也能连起来，但链不会跨会话蔓延
成员下限剪枝：离代表图太远就摘出去（连拍成员豁免）
    ↓
组内选优：清晰度（拉普拉斯）+ 人脸质量；只在组内相对比较，免校准
```

会话切分阈值定在 **5 分钟**（原本是 90 秒）。90 秒把阈值表的后两档变成了死配置——
会话在 90 秒就断了，长间隔那档永远轮不到。改成 5 分钟后 `≤5min → 0.78` 真正生效，
能拉回"走两步换个角度再拍"这类；而在 90 秒时代，这类只能去撞 0.88 的跨会话门槛，
基本会漏。

时间切片的真正价值不是"分类"，而是**把候选集从全库砍到几十张**——之后组内才敢用低
阈值，全局单一阈值那套问题自然消失。

## 实测数字（合成图，非真实照片）

| 项 | 结果 |
|---|---|
| FeaturePrint 单张 | 5–13 ms（含缩略图绘制），约 80–200 张/秒 |
| 特征维度 | 768 |
| 同一张 · 轻微模糊 2x | 0.851 |
| 同一张 · 中度模糊 4x | 0.731 |
| 同一张 · 重度模糊 8x | 0.699 |

**最重要的一个结论：糊掉的那一张相似度会掉到 0.70–0.73，而它恰恰是最该被清掉的。**
所以会话内阈值宁可偏低：分了不该分的组，用户扫一眼就能看出来；漏掉的那张永远不会
自己冒出来。

（合成图测不了"不同场景能否分开"——几张合成图在语义上是同一类东西，FeaturePrint 给出
的 0.957 和"同背景主体移位"的 0.967 几乎一样。这一项只能靠真实图库的 audit。）

## 三个必须知道的坑

1. **必须是 app bundle**。裸可执行文件访问相册会因为缺少 `NSPhotoLibraryUsageDescription` 被系统直接杀掉。所以开发流程是 `swift build` → 拼 `.app` → `open`，不能 `swift run`。
2. **签名身份要稳定**。ad-hoc 签名每次编译 cdhash 都变，相册授权会反复失效弹窗。建议一次性建自签名证书：
   钥匙串访问 → 证书助理 → 创建证书 → 名称 `glean-dev`、类型「代码签名」。
   然后 `GLEAN_SIGN_ID="glean-dev" ./scripts/run.sh`。
3. **macOS 的 `requestImage` 回调给的是 `NSImage`**，不是 `CGImage`（iOS 才是 UIImage）。类型写错时编译器只吐一句 "failed to produce diagnostic"，看不出真正原因。

## 开发

```bash
./scripts/run.sh              # 命令行路径：编译 + 打包 + 启动
swift test                    # 22 个测试
./scripts/open-xcode.sh       # Xcode 路径：生成工程并打开
```

### 两条构建路径，一个产物

| | 命令行 | Xcode |
|---|---|---|
| 构建 | `Package.swift` + `scripts/build-app.sh` | `project.yml` → `xcodegen` |
| 产物 | `build/Glean.app` | `build/Glean.app`（同一个路径） |
| 运行 | `./scripts/run.sh` | ⌘R |
| 测试 | `swift test` | ⌘U |

两条路径都可用，产物落在同一个位置，不会出现同 bundle id 两份 app 让 LaunchServices
和相册授权搞不清该认哪一个。谁最后构建就是谁。

**Xcode 工程是产物，不是事实来源。** `glean.xcodeproj` 由 `project.yml` 生成且不入库——
pbxproj 是机器生成的 XML，冲突难解、人读不了。在 Xcode 图形界面里改 Build Settings
只会改到 `.xcodeproj`，下次 `xcodegen generate` 会被覆盖；要持久化的设置请写进 `project.yml`。

改动 `project.yml` 或增删文件后记得重跑 `./scripts/open-xcode.sh`（只是重新生成，不丢东西）。

### 签名

默认是临时签名（`CODE_SIGN_IDENTITY: "-"`，等价于 Xcode 里的
"Sign to Run Locally"），不需要开发者账号就能构建。但临时签名每次编译 cdhash 都变，
相册授权会反复失效弹窗。想固定身份：把 `project.yml` 里的 `CODE_SIGN_IDENTITY` 换成你
自签名证书的通用名（如 `glean-dev`），命令行和 Xcode 就都稳定了。

如果 Xcode 升级后许可证未接受，`swift build` 会报 *"You have not agreed to the Xcode
license agreements"*。`scripts/build-app.sh` 会自动检测并回退到 Command Line Tools 的
工具链；手动跑 `swift test` 时用
`/Library/Developer/CommandLineTools/usr/bin/swift test`。

```
Sources/GleanCore/       纯逻辑，不依赖 UI
  Models.swift           GleanAsset / FeaturePrint
  PhotoLibrary.swift     授权、资产枚举、缩略图
  FeaturePrintService.swift  Vision 特征提取
  Session.swift          时间切片
  Grouping.swift         阈值策略 + 两阶段聚类 + 成员剪枝
  ImageQuality.swift     清晰度 / 人脸质量
  KeeperRanker.swift     组内选优
  Clustering.swift       并查集 + 余弦
Sources/GleanApp/        SwiftUI 壳 + AnalysisRunner（把管线串成报告）
Resources/Info.plist     bundle 元数据（含相册用途说明）
project.yml              Xcode 工程描述（xcodegen 输入）
scripts/                 打包与启动
```

## 路线

- **M1 质量**：全量扫描 → 特征 → 分组 → 导出 JSON，用真实图库调阈值（**当前在这里**：管线已跑通，阈值待审计）
- **M1.5 审计**：按相似度分档抽样，人工标注"该合/不该合"，画出精度曲线后再定阈值
- **M2 可用**：SwiftUI 三栏（组列表 / 缩略图网格 / 对比），键盘 `←→` 翻组、`space` 预览、`1..9` 选保留
- **M3 安全**：删除走 `PHAssetChangeRequest.deleteAssets`（进"最近删除"，30 天内可恢复）+ 本地 manifest 记录每批操作，支持整批撤销
- **M4 增量**：SQLite 缓存特征，只算新图；百万级再换 IVF

## 删除策略

**不做永久删除。** 两条路径：

1. 首选 `PHAssetChangeRequest.deleteAssets` —— 进 Photos 的"最近删除"，30 天内可恢复
2. 需要立刻释放磁盘时，`PHAssetResourceManager` 导出到 `~/Pictures/glean-quarantine/<批次>/` 再删，manifest 记完整路径

照片是**不可再生数据**。任何"一键清理"按钮都必须能一键撤销。
