<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="graze 图标：一只山羊">
</p>

<h1 align="center">graze</h1>

<p align="center">
  <strong>山羊吃草叫 graze，随手翻照片也叫 graze。</strong><br>
  留下的那些才是草，其余的都是杂草。
</p>

<p align="center">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="macOS 26" src="https://img.shields.io/badge/macOS-26-000000?logo=apple&logoColor=white">
  <img alt="零依赖" src="https://img.shields.io/badge/deps-none-2C3A2E">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-B06A34">
</p>

---

一个 macOS 的**相似图片挑拣工具**。目标不是"删重复"（Photos.app 自带的"重复项目"相册已经能做），而是它做不了的部分：

- 连拍整组：一梭子 20 张选 1 张
- 同一场景重拍：构图微调、换曝光
- 截图、翻拍、聊天记录里存回来的图
- 模糊 / 低质 / 被压缩坏的版本

它**不替你挑，也不删东西**：只把可能重复的照片找成一堆，标记为待删除，删不删、删哪些都由你决定。

## 安装

- **下载**：[Releases](https://github.com/solidSpoon/graze/releases) 里的 zip，仅 arm64。
  未签名、未公证，首次打开需要执行一次 `xattr -dr com.apple.quarantine /Applications/Graze.app`。
- **自己编译**：克隆后 `./scripts/run.sh`，产物在 `build/Graze.app`，双击运行。
  `build/` 不入库，克隆下来没有现成 app。

要求 **macOS 26**。

## 怎么用

1. **请求相册访问权限** → 系统弹窗里选「允许」（也可以选「仅选中」先小范围试）
2. 点**扫描图库** → 读整库一次，底部状态栏显示「读取相册 1200/7624」
3. 工具栏选**分析范围**（最近 1/3/6 个月、1 年、全部，括号里是该范围的片数）。换范围不用重扫
4. 点**分析** → 底部状态栏显示阶段和进度条，左侧出现相似组卡片

界面是顶部一条系统工具栏，下面三栏：

| 栏 | 内容 |
|---|---|
| 左 | 相似组卡片，两列。卡片顶部并排显示组内前 3 张缩略图 |
| 中 | 选中那一组的照片。单击选中，⌘/Shift 点击多选，双击或空格看大图 |
| 右 | 选中照片的详细信息（文件名、尺寸、时间、组内相似度…） |

键盘：中栏 `←→` 换照片、`空格` 开关大图、`回车` 标记/取消待删除；
大图里 `←→` 翻看、`空格` 退出。

### iCloud「优化 Mac 储存空间」的照片

开着「优化储存空间」时，早年照片的原图只在 iCloud，本地只有一份小预览，这会造成两件不同的事：

- **打开大图**：会按需从 iCloud 下载，进度条显示百分比；下载失败会明确提示并给「重试」。
  下载过一次之后，这张照片对 Photos 来说就是本地照片了。
- **分析**：仍然只处理本地有图的照片——批量下载整个云端图库（可能几十 GB、几十分钟）
  不能偷偷干。日志和状态栏会写明跳过了多少张。所以早年照片要先在大图里看过（= 下载过），
  才会进相似组。

**标记待删除 = 加进 `graze 待删除` 相册**（PhotoKit 不暴露关键词，相册就是标签）。
不复制文件，状态存在系统里；之后在 Photos.app 里打开这个相册、全选 `⌘⌫` 就是原生删除，
30 天内可从"最近删除"恢复。

## 怎么找的

```
时间切片（间隔 >5min 断开一个会话）
    ↓   候选对从全库两两降到会话内两两
会话内成组：新照片必须和组里每一张都过线
    ↓   ≤5s → 0.84 / ≤1min → 0.90 / ≤5min → 0.92（连拍成员豁免）
组内按拍摄时间正序排列，整组按组内最新时间倒序
```

两条规矩撑起全部行为，没有第三层调参：

1. **组不跨会话**。相隔超过 5 分钟的两张永远不同组。「改天重回同一地点」不是去重该干的事，
   而它恰好是误合的最大来源：同一天、同一片树林的几段拍摄会被硬凑成一大组。
2. **组内任意两张都必须过线**。不是只跟「代表图」比——那样 A~B、B~C 都过线就能把 A 与 C
   差很远的照片粘成一组，一条链能把整个下午串起来。现在过不了当场分两组，滚雪球不成立。

时间切片不只是分组规则，更是**把候选对从全库砍到几分钟内**——候选集小了，阈值才敢定得低。

全库 7624 张：首次 42 秒（其中提特征 39 秒），之后从特征缓存读，**约 4 秒**。
FeaturePrint 单张 5–13 ms，768 维。

这三档不是拍脑袋定的，是从真实图库里量出来的：同一瞬间拍的两张，相似度中位数 0.956；
隔 1～2 分钟 0.899；而「同一个院子、同一个角度、换了一批人」也能到 0.83～0.87。所以
阈值必须随时间收紧，否则 0.80 这条线会把两种东西一起放进来。觉得太松或太紧，改
`ThresholdPolicy` 里这三个数即可；`audit-*.json` 里能看到每一对当时是多少分。

## 技术栈

```
Swift 6 + SwiftUI + PhotoKit + Vision + Accelerate
```

| 环节 | 方案 | 为什么 |
|---|---|---|
| 图库访问 | **PhotoKit** | 唯一被官方支持的方式；能拿到稳定的 `localIdentifier`，删除动作走系统 API |
| 缩略图 | `PHImageManager.requestImage` 512pt | 单张 ~10ms，`isNetworkAccessAllowed = false` 只读本地副本 |
| 相似度 | **Vision `VNGenerateImageFeaturePrintRequest`** | 768 维，跑在 ANE 上，零依赖；对重压缩/裁剪/调色/重拍的鲁棒性远好于 pHash |
| 分组 | 归一化向量 + 点积 + 会话内贪心成团 | 组定义就一句话：组内任意两张都过线；不需要 K-Means 调参，个人库规模 O(n²) 够用 |
| 缓存（待做） | SQLite + Float32 BLOB | 增量扫描靠 `localIdentifier + modificationDate` |

**为什么不用 Python / Electron / Tauri**：为一个工具背 Python + torch（2GB）或 Electron 运行时（200MB）都不值；而 macOS 上最好的图像相似度模型本来就已经在系统里了。

## 路线

- **M1 质量**（已完成）：全量扫描 → 特征 → 分组，管线跑通
- **M1.5 审计**（当前）：按相似度分档抽样，人工标注"该合/不该合"，画出精度曲线后再定阈值。现在的阈值是按经验定的
- **M2 可用**（已完成）：SwiftUI 三栏，键盘 `←→` 翻照片、`space` 预览、`回车` 标记待删除
- **M3 安全**（未做）：删除走 `PHAssetChangeRequest.deleteAssets`（进"最近删除"，30 天内可恢复）+ 本地 manifest 记录每批操作，支持整批撤销。这就是现在还不删东西的原因
- **M4 增量**：SQLite 缓存特征，只算新图；百万级再换 IVF

## 删除策略

**不做永久删除。** 两条路径：

1. 首选 `PHAssetChangeRequest.deleteAssets` —— 进 Photos 的"最近删除"，30 天内可恢复
2. 需要立刻释放磁盘时，`PHAssetResourceManager` 导出到 `~/Pictures/graze-quarantine/<批次>/` 再删，manifest 记完整路径

照片是**不可再生数据**。任何"一键清理"按钮都必须能一键撤销。

## 开发

```bash
./scripts/run.sh              # 编译 + 打包 + 启动，产物 build/Graze.app
swift test                    # 单元测试
./scripts/open-xcode.sh       # 生成 Xcode 工程并打开
```

`project.yml` 是工程配置的唯一事实来源，`graze.xcodeproj` 由它生成且不入库——要持久化的
Build Settings 写进 `project.yml`，改完重跑 `./scripts/open-xcode.sh`。命令行和 Xcode 都输出到
`build/Graze.app`，不会出现同 bundle id 两份 app 让相册授权认错。

App 必须从 `.app` 里跑（裸可执行文件没有相册权限声明），所以别用 `swift run`。签名默认是
临时签名，每次编译 cdhash 都变、相册授权会反复失效；把 `project.yml` 里的 `CODE_SIGN_IDENTITY`
换成自己的证书通用名即可稳定。

```
Sources/GrazeCore/       纯逻辑，不依赖 UI
  Models.swift           GrazeAsset
  PhotoLibrary.swift     授权、资产枚举、缩略图（默认不读 iCloud）
  ThumbnailCache.swift   缩略图内存缓存
  FeaturePrintService.swift  Vision 特征提取
  Session.swift          时间切片
  Grouping.swift         两档阈值 + 会话内成团（组内任意两张都过线）
  AnalysisAudit.swift    每次分析写一份 audit-*.json：每组的两两相似度
  DeletionAlbum.swift    「待删除」相册 = 标记的唯一事实来源
  Clustering.swift       归一化 + 余弦
  FeatureCache.swift     特征向量落盘缓存（~11MB，命中即跳过 Vision）
  GrazeLog.swift         ~/Library/Logs/graze/graze.jsonl
Sources/GrazeApp/        SwiftUI 壳 + AnalysisRunner（把管线串成报告）
scripts/                 打包与启动
```

## 出错时看哪里

每次分析都会写一份审计：

```
~/Library/Logs/graze/audit-20261019-203305.json   最近 10 份
```

里面有每一组的成员、两两相似度、时间间隔、属于哪个会话，外加当次使用的阈值。
觉得「这明显不是一组」的时候，看这一组的 `weakestPair`（最不像的那一对）就够了——
它低于阈值却仍在组里，只可能是连拍豁免。

## 发版

提交信息决定版本号：`feat:` 升次版本、`fix:` / `perf:` 升修订号，`docs:` / `chore:` 等不发版。
[Release Please](https://github.com/googleapis/release-please) 据此开版本 PR，合并后打 tag、
建 Release，并在 GitHub runner 上打包出 `graze-v<版本>-arm64.zip`。

版本号只有 `project.yml` 里 `MARKETING_VERSION` 一处（行尾带 `# x-release-please-version`）。

## 许可

代码 MIT，见 [LICENSE](LICENSE)。图标字形来自 [game-icons.net](https://game-icons.net) 的
`skoll/goat`（CC BY 3.0），不在 MIT 范围内。
