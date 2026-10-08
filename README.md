# 视频转实况照片 · VideoToLivePhoto

自用的 iPhone 工具：一次选择最多 10 个视频，本机转换成真正的 Live Photo，直接保存到系统相册。Swift + SwiftUI，App 源码只有一个 Swift 文件，无第三方 SDK、登录、广告、埋点或网络请求。

## 免费安装到 iPhone

需要 Mac、Xcode 15 或更新版本、iOS 16 或更新版本的 iPhone、普通免费 Apple ID。没有需要付费开发者账号的 capability，不用购买 Apple Developer Program。

1. 下载仓库 ZIP 并解压，或者 `git clone`。
2. 双击 **VideoToLivePhoto.xcodeproj** 用 Xcode 打开，不需要 CocoaPods、Swift Package 或工程生成工具。
3. 在 Xcode → Settings → Accounts 添加个人 Apple ID。
4. 选工程 → TARGETS → **VideoToLivePhoto** → Signing & Capabilities，勾选 **Automatically manage signing**，Team 选择自己的 **Personal Team**。
5. 将 Bundle Identifier `com.personal.VideoToLivePhoto` 改成自己的唯一值，例如 `com.yourname.VideoToLivePhoto`。运行测试时，也为 **VideoToLivePhotoTests** 选择同一 Team、设置唯一 Bundle Identifier。
6. 用数据线连接 iPhone，解锁并信任 Mac。在 Xcode 顶部选择自己的 iPhone 作为运行设备。
7. 按提示在 iPhone 的 设置 → 隐私与安全性 → 开发者模式 中开启开发者模式，并按系统要求重启。如果提示开发者不受信任，到 设置 → 通用 → VPN 与设备管理 中信任个人开发者。
8. 点 **Run ▶︎**（⌘R）。初次签名需要 Mac 联网与苹果通信；安装后的 App 转换功能不需要网络。

**免费个人签名一般只有 7 天有效期。** 到期重新连接 Xcode、Run 即可续签。这是苹果免费安装方式的限制，App 没有订阅费。重新 Run 更新 App 不要先删除 App。

## 日常使用

1. 确认 MP4 动画已下载到 iPhone。可以开启飞行模式测试全程离线。
2. 打开 App → **选择视频（最多 10 个）** → 在系统相册选择器中多选。
3. 点 **转换并存入相册**。首次只会请求“添加照片”权限，选择允许；选择视频不申请完整相册读取权限。
4. 转换期间保持 App 在前台。每个视频单独显示成功或错误；再次点转换只重试失败项，成功项不会重复保存。
5. 打开系统相册，查看新增照片的 **LIVE** 标记，长按播放。然后在小红书中从相册选择这些实况照片。

3 秒视频保留完整画面和原有声音（如果有）。超过 3 秒的视频取中间 3 秒；短视频保留原时长，不补帧。封面取保留片段的中间帧。保留原尺寸和旋转方向，视频重新编码为 H.264，音频编码为 AAC。

iCloud 中尚未下载的视频可能由**系统选择器**尝试联网下载；App 自身没有联网代码。要保证整个操作离线，请先下载源视频并开启飞行模式。iOS 相册自己的 iCloud 同步行为由系统设置决定，App 不进行上传。

相册存储成功不代表已完成真机验收；首次安装请按下面清单实际检查 LIVE 和播放。小红书的上传与展示行为由其 App 决定。

## Live Photo 配对实现

`VideoToLivePhoto/VideoToLivePhotoApp.swift` 包含界面、系统视频选择器、串行批量处理和编码保存逻辑。

- 每个输出生成独立 UUID。
- JPG 通过 ImageIO 写入 `kCGImagePropertyMakerAppleDictionary` 的键 **`17`**，值为该 UUID（不是普通 EXIF 的 `ImageUniqueID`）。
- MOV 文件级 QuickTime 元数据 `com.apple.quicktime.content.identifier` 使用相同 UUID，类型 UTF-8。
- MOV 增加 **timed metadata track**：`mdta/com.apple.quicktime.still-image-time`，数据类型 **signed int8**，值 **0**；时间区间从实际生成封面帧的时间戳开始。不是只把 still-image-time 放到文件级 metadata。
- `AVAssetImageGenerator` 应用旋转方向，以中间帧生成 JPG。MOV 保留视频轨道的 `preferredTransform`。
- 用 `PHLivePhoto.request(withResourceFileURLs:)` 检查苹果解码器能否识别本地 JPG + MOV。检查失败则不保存。
- 通过一个 `PHAssetCreationRequest`，以 `.photo` 和 `.pairedVideo` 两个资源一次性写入。
- 仅调用 `PHPhotoLibrary.requestAuthorization(for: .addOnly)`；工程 Info.plist 只生成 `NSPhotoLibraryAddUsageDescription`，不声明 `NSPhotoLibraryUsageDescription`。
- 输入来自 `PHPickerViewController` 用户明确选择的文件，不枚举 `PHAsset`、不读取相册数据库。
- 临时资源用于本机转换；配对文件在成功或失败后删除。源文件副本在成功后删除、失败时留到更换选择或本次会话结束以便重试；下次打开 App 会清理上次意外终止遗留的临时副本。系统相册中的原视频不修改。

## 验证

**交付环境为 Linux，无 Xcode / Apple SDK / iPhone，因此目前未运行 Apple SDK 编译、XCTest 或真机验收。** 工程结构和隐私约束可在 Linux 上静态检查，但不能代替下面的 Apple SDK 验证。没有将未执行的检查写成通过。

### 在 Mac 上编译与集成测试

```sh
# 不需要签名的模拟器构建
xcodebuild -project VideoToLivePhoto.xcodeproj -scheme VideoToLivePhoto \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# 查看已安装模拟器，选一个 iPhone 的 UUID
xcrun simctl list devices available

# 将 SIMULATOR_UUID 替换为实际 UUID
xcodebuild -project VideoToLivePhoto.xcodeproj -scheme VideoToLivePhoto \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=NO test
```

也可在 Xcode 选择 iPhone 模拟器并按 ⌘U。集成测试生成一个 3 秒无声竖屏视频，检查 JPG/MOV UUID、视频时长、旋转方向、still-image-time 的值和时间戳，并交给苹果 Live Photo 解码器验证；第二个测试确认 UUID 不匹配的资源被拒绝。测试不写入相册、不请求照片权限。模拟器检查不能代替实机相册检查。

### 真机验收清单

- [ ] 飞行模式下选择 10 个本机 3 秒 MP4，转换后相册增加 10 张照片。
- [ ] 10 张均显示 LIVE，长按能播放完整 3 秒动画。
- [ ] 竖屏、横屏封面和播放方向正确，封面对应中间帧。
- [ ] 带声音视频保留声音，无声视频不报错。
- [ ] 取消视频选择不改变现有列表，系统选择器最多选 10 个。
- [ ] 拒绝添加权限时有说明，设置中允许后可重试；没有请求完整相册读取权限。
- [ ] 损坏视频或空间不足时显示失败；重试不重复写入成功项。
- [ ] 短视频按原时长播放，长视频只保留中间 3 秒。

Linux 静态检查：`python3 scripts/check_project.py`。`scripts/create_project.py` 仅用于重建已提交的工程文件，日常安装无需运行。
