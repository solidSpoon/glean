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

## 三个必须知道的坑

1. **必须是 app bundle**。裸可执行文件访问相册会因为缺少 `NSPhotoLibraryUsageDescription` 被系统直接杀掉。所以开发流程是 `swift build` → 拼 `.app` → `open`，不能 `swift run`。
2. **签名身份要稳定**。ad-hoc 签名每次编译 cdhash 都变，相册授权会反复失效弹窗。建议一次性建自签名证书：
   钥匙串访问 → 证书助理 → 创建证书 → 名称 `glean-dev`、类型「代码签名」。
   然后 `GLEAN_SIGN_ID="glean-dev" ./scripts/run.sh`。
3. **macOS 的 `requestImage` 回调给的是 `NSImage`**，不是 `CGImage`（iOS 才是 UIImage）。类型写错时编译器只吐一句 "failed to produce diagnostic"，看不出真正原因。

## 开发

```bash
./scripts/run.sh              # 编译 + 打包 + 启动
swift test                    # 聚类/相似度的单元测试
GLEAN_SIGN_ID="glean-dev" ./scripts/run.sh   # 签名身份稳定的版本
```

```
Sources/GleanCore/       纯逻辑，不依赖 UI
  Models.swift           GleanAsset / FeaturePrint
  PhotoLibrary.swift     授权、资产枚举、缩略图
  FeaturePrintService.swift  Vision 特征提取
  Clustering.swift       并查集 + 余弦相似度分组
Sources/GleanApp/        SwiftUI 壳
Resources/Info.plist     bundle 元数据（含相册用途说明）
scripts/                 打包与启动
```

## 路线

- **M1 质量**：全量扫描 → 特征 → 分组 → 导出 JSON，用真实图库调阈值，确认召回和误报
- **M2 可用**：SwiftUI 三栏（组列表 / 缩略图网格 / 对比），键盘 `←→` 翻组、`space` 预览、`1..9` 选保留
- **M3 安全**：删除走 `PHAssetChangeRequest.deleteAssets`（进"最近删除"，30 天内可恢复）+ 本地 manifest 记录每批操作，支持整批撤销
- **M4 增量**：SQLite 缓存特征，只算新图；百万级再换 IVF

## 删除策略

**不做永久删除。** 两条路径：

1. 首选 `PHAssetChangeRequest.deleteAssets` —— 进 Photos 的"最近删除"，30 天内可恢复
2. 需要立刻释放磁盘时，`PHAssetResourceManager` 导出到 `~/Pictures/glean-quarantine/<批次>/` 再删，manifest 记完整路径

照片是**不可再生数据**。任何"一键清理"按钮都必须能一键撤销。
