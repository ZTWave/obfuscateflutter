# obfuscateflutter

`obfuscateflutter` 是一个面向 Flutter 项目的命令行混淆辅助工具。它把 Dart、资源、Android 原生工程和 iOS 原生工程的多类改写集中到一个交互式菜单里执行，并把主要改写结果汇总到统一的 `obfuscation_mapping.html`。

工具会直接修改目标 Flutter 项目。执行前建议先提交代码、复制项目，或使用临时目录模式 `x`。

## 当前能力

- 图片处理：修改图片 MD5、混淆已引用图片名称并清理未引用图片(webp 不支持)。
- Dart 处理：字符串加密/恢复、AST 文件与目录重命名、随机 Dart 文件生成、类内垃圾代码与字符串注入、源码注释和空行清理。
- Android 处理：生成 Proguard 字典，生成 Java 四大组件、XML/PNG 资源，并可选执行 Android 自有 package/class/resource 深度命名混淆。
- iOS 处理：Objective-C/Swift AST 垃圾代码注入、项目文件名替换、内部函数换名、业务方法体结构化差异改写。
- 报告能力：多数混淆功能写入同一个 `obfuscation_mapping.html`，包含功能分区、summary、完整 mapping JSON、发布汇总指标、跳过项和风险提示。
- 安全入口：启动时执行预检，检查 Flutter 项目结构、assets、生成文件状态、Git 状态、Android/iOS 目录完整性。

## 安装和启动

在本工具项目目录执行：

```bash
dart pub get
dart run ./bin/obfuscateflutter.dart -d <Flutter项目路径>
```

如果不传 `-d`，工具会通过 shell 询问或读取当前路径。

可传入 `--dart-define-from-file` 参数；当前入口会解析该参数，保留给构建相关扩展使用：

```bash
dart run ./bin/obfuscateflutter.dart \
  -d <Flutter项目路径> \
  --dart-define-from-file=<define.json>
```

启动后会先打印 Flutter 版本，再执行预检。预检发现阻断项时会停止；发现 Git 未提交、assets 缺失、生成文件疑似过期等问题时会提示，但部分情况仍会进入菜单。

## 菜单

```text
1.修改图片MD5
2.混淆图片名称并清理
3.生成Android Proguard混淆字典
4.混淆项目中所有的String
5.恢复项目中已混淆的String
6.统一混淆（AST方案：文件/目录重命名+混淆文档）
7.Dart随机代码注入/保留
8.类内垃圾代码/字符串注入
9.Android项目垃圾代码生成
10.iOS Object-C/Swift AST 混淆
11.iOS 项目文件名替换
12.iOS 内部函数换名
13.iOS 业务代码结构化差异混淆
14.清理 Dart 源码注释

x.在临时生成目录中执行上述混淆任务（除恢复 String）
```

## 功能总览

| 编号 | 功能 | 主要结果 | 适用场景 |
| --- | --- | --- | --- |
| `1` | 修改图片 MD5 | 改写 `pubspec.yaml` assets 下的图片文件，控制台打印处理前后 MD5。 | 改变图片二进制特征，同时尽量保持视觉变化极小。 |
| `2` | 混淆图片名称并清理 | 重命名被 Dart 代码引用的图片，删除未检测到引用的图片，同步替换 Dart 字符串中的资源名或路径。 | 降低固定资源名特征并清理无引用图片。 |
| `3` | 生成 Android Proguard 字典 | 写入 `android/app/dict.txt`，默认 10000 个随机名称。 | 配合 Android Proguard/R8 字典配置。 |
| `4` | 混淆项目中所有 String | 生成 `lib/stren_arg.dart`，将安全字符串替换为 `desNoStr("...")` 调用，并生成调试测试文件。 | 隐藏 Dart 源码中的普通字符串字面量。 |
| `5` | 恢复已混淆 String | 将 `desNoStr("...")` 还原为普通字符串，移除无用 import，必要时删除 `stren_arg.dart`。 | 回滚功能 4 的字符串加密改动。 |
| `6` | 统一混淆 | AST 重写 import/export/part URI，重命名 `lib` 下目录和 Dart 文件，修正生成文件 `part of`。 | 可追踪地改变 Dart 文件和目录结构。 |
| `7` | Dart 随机代码注入/保留 | 生成随机 Dart 文件，并在 `lib/main.dart` 注入 retain 调用。 | 增加 release 可达的 Dart 代码体量和结构差异。 |
| `8` | 类内垃圾代码/字符串注入 | 向已有 class 注入垃圾成员、可读字符串和轻量 hook。 | 在业务类内部制造结构差异，减少独立垃圾文件特征。 |
| `9` | Android 项目垃圾代码生成 | 生成 Java 组件、XML/PNG 资源，注册 Manifest；可选深度重命名。 | 增加 Android 原生侧组件和资源差异。 |
| `10` | iOS Object-C/Swift AST 混淆 | 使用 clang/swift AST 定位方法体并插入 OC/Swift 垃圾代码。 | 增加 iOS 原生源码差异，保持公开 API 稳定。 |
| `11` | iOS 项目文件名替换 | 重命名 iOS 自有源码文件并同步源码和 Xcode 工程引用。 | 改变 iOS 文件结构特征。 |
| `12` | iOS 内部函数换名 | 重命名低风险内部 C/Objective-C/Swift 函数或私有 selector。 | 改变 iOS 内部符号和调用引用。 |
| `13` | iOS 业务代码结构化差异混淆 | 对安全方法体执行包装跳转、局部抽取、控制流拆分。 | 改变 iOS 业务方法体结构。 |
| `14` | 清理 Dart 源码注释 | 删除 `lib/**/*.dart` 注释和可移除空行，写入清理 summary。 | 清理源码注释、文档注释和 ignore 指令。 |
| `x` | 临时目录执行 | 复制项目到同级 `temp_<pubspec_name>`，跳过 `.git` 和 `build`，在副本执行主要混淆步骤。 | 保持原项目源码干净，在临时副本中生成混淆结果。 |

## 统一报告

除字符串恢复外，入口会在多数功能执行前初始化 `obfuscation_mapping.html`。功能执行后会把 mapping 写入该 HTML 的对应功能区块。

报告包含：

- 发布汇总：混淆前后文件数量、字符串处理数量、资源改名数量、Dart/iOS/Android 注入数量、跳过原因、风险项和人工检查项。
- 功能分区：每个功能的更新时间、中文 summary 表格和完整 mapping JSON。
- 稳定数据：HTML 内部保留机器可读 JSON；页面展示层会把常见 summary key 翻译为中文。
- 文件统计排除目录：`.dart_tool`、`.git`、`.gradle`、`.idea`、`.symlinks`、`.vscode`、`Pods`、`build`、`temp_*`。

重复执行同一功能会更新对应功能区块，不再生成多个分散的时间戳 mapping 文件。当前功能 `13` 是例外：入口会初始化 `obfuscation_mapping.html`，但结构化差异结果仍写入独立的 `ios_structural_diff_mapping_<timestamp>.json`，不会写入 HTML 的功能区块。

## 预检规则

启动时会检查目标项目：

- 必须存在 `pubspec.yaml`，且包含 Flutter 配置和 `lib` 目录。
- `flutter.assets` 缺失、为空或路径不存在时给出提示。
- 如果项目使用 `build_runner`，会检查 `.g.dart`、`.freezed.dart`、`.gr.dart` 是否缺失或可能过期。
- Git 非干净状态会提示，建议先提交、暂存或清理。
- Android 功能依赖 `android/app/build.gradle` 或 `build.gradle.kts`，以及 `android/app/src/main/AndroidManifest.xml`。
- iOS 功能依赖 `ios/Runner.xcodeproj` 和 `ios/Runner/Info.plist`。

预检只保证基础结构可用，不替代混淆后的 `dart analyze`、测试和真机构建验证。

## 功能说明

### 1. 修改图片 MD5

读取 `pubspec.yaml` 中声明的 assets，处理 `.png`、`.jpg`、`.jpeg`、`.webp`。

处理策略：

- 可解码图片会做轻微像素扰动，再重新编码写回。
- PNG/JPEG 会尽量重新编码。
- 无法解码、像素访问失败或编码失败时，会追加少量随机字节作为兜底。
- assets 配置既可以是文件，也可以是目录。

该功能原地修改图片，不生成备份。

### 2. 混淆图片名称并清理

扫描 assets 图片并检查 `lib/**/*.dart` 中的常见字符串引用。

结果：

- 被检测到引用的图片会随机重命名。
- 未检测到引用的图片会删除。
- Dart 代码中匹配到的 `'xxx.png'`、`"xxx.png"`、`'assets/path/xxx.png'`、`"assets/path/xxx.png"` 会同步替换。

当前不是完整 AST 资源追踪。动态拼接、服务端下发资源名、非 Dart 文件引用、原生工程引用需要人工复核。

### 3. 生成 Android Proguard 字典

写入目标项目：

```text
android/app/dict.txt
```

常见接入方式：

```proguard
-obfuscationdictionary dict.txt
-classobfuscationdictionary dict.txt
-packageobfuscationdictionary dict.txt
```

### 4. 混淆项目中所有 String

扫描 `lib/**/*.dart`，跳过 `.g.dart`、`.freezed.dart` 和生成的 `lib/stren_arg.dart`。工具通过 analyzer AST 判断可替换的普通字符串字面量。

结果：

- 生成 `lib/stren_arg.dart`，保存 `SEP`、`SEK` 和 `desNoStr()`。
- 普通字符串替换为 `desNoStr("<SEP+加密文本>")`。
- 自动插入 `import 'package:<pubName>/stren_arg.dart';`，并保证 import 位于 `part` 之前。
- 生成 `test/obfuscate_string_debug.dart`，可运行 `flutter test test/obfuscate_string_debug.dart` 查看加解密结果。

会跳过：

- import/export/part URI。
- 注解、常量表达式、const 上下文。
- switch case、pattern、const 构造初始化等必须编译期常量的位置。
- 已经被 `desNoStr()` 包裹的字符串。

### 5. 恢复项目中已混淆的 String

根据 `lib/stren_arg.dart` 中的参数反向恢复字符串。

结果：

- 将 `desNoStr("<SEP+加密文本>")` 还原为普通 Dart 字符串。
- 自动移除不再需要的 `stren_arg.dart` import。
- 如果项目中已无引用，会删除 `lib/stren_arg.dart`。

### 6. 统一混淆

统一混淆是当前推荐的 Dart 文件/目录重命名入口。

处理范围：

- `lib/**/*.dart`
- 跳过 `.g.dart`、`.freezed.dart`
- 跳过 `lib/stren_arg.dart`
- 保留 `main.dart` 文件名

结果：

- 重命名 `lib` 下目录和 Dart 文件。
- 使用 AST 重写 import/export/part URI。
- 修正同目录 `.g.dart/.freezed.dart` 中的 `part of 'old.dart';`。
- 写入 `obfuscation_mapping.html` 的“统一混淆”区块。

如果项目中存在非标准代码生成关系、字符串拼接 import、构建脚本硬编码文件路径，需要混淆后人工复核。

### 7. Dart 随机代码注入/保留

读取 `obfuscate_dart_noise.json` 顶层配置，在 `lib` 下生成随机 Dart 文件，并在 `lib/main.dart` 注入 `obfDartNoiseRetain()` 调用，避免 release tree shaking 移除生成代码。

结果：

- 生成页面类、同步 worker 类和 shard 工具函数。
- 垃圾文件尽量分散到项目已有目录和随机目录中。
- 同一个 shard 文件会轮换不同函数模板，降低重复结构。
- 写入 `obfuscation_mapping.html` 的“Dart随机代码注入/保留”区块。

常用配置字段：

| 字段 | 说明 |
| --- | --- |
| `pageCount` | 生成随机页面类数量。 |
| `classCount` | 生成随机普通 Dart 类数量。 |
| `methodCountPerClass` | 每个随机类内生成的同步方法数量。 |
| `template` | 当前固定为 `page_sync_class`。 |
| `outputDir` | 兼容字段，必须位于 `lib` 下；当前生成策略会优先分散到项目目录。 |
| `garbageFileCountMin` / `garbageFileCountMax` | 本次生成垃圾 Dart 文件数量范围。 |
| `snippets` | 启用的内置片段或自定义模板 `id`。 |
| `snippetWeights` | 控制片段选择权重，值越高越容易被选中。 |
| `customTemplates.pageBodies` | 自定义页面 `build` 方法体模板，必须返回 `Widget`。 |
| `customTemplates.methodBodies` | 自定义同步方法体模板，必须返回 `int`。 |

内置 snippet 包含 `widget_empty_page`、`widget_layout_page`、`sync_math`、`sync_string`、`sync_list`、`sync_model`、`sync_enum_switch`。默认配置里还包含大量 `custom_page_*` 和 `custom_sync_*` 模板。

自定义模板禁止包含：

```text
Future, Stream, async, await, Timer, import, export, part, dart:io, dart:async, @pragma
```

### 8. 类内垃圾代码/字符串注入

读取 `obfuscate_dart_noise.json` 中的 `classInnerNoise` 配置，扫描已有 Dart 类，把垃圾成员、可读字符串和轻量 hook 插入当前文件和当前类内部。

结果：

- 不创建外部链接工具文件。
- 垃圾成员插入已有 class。
- hook 插入普通 block-bodied 方法或安全的非 const 构造函数。
- 每次随机化成员名、局部变量名、seed、分支和表达式。
- 必要时追加缺失 import，并保留已有 import 的 `show/hide/as` 子句。
- 写入 `obfuscation_mapping.html` 的“类内垃圾代码/字符串注入”区块。

主要配置：

| 字段 | 说明 |
| --- | --- |
| `classInnerNoise.enabled` | 是否启用类内注入。 |
| `classInnerNoise.targetRatio` | 目标注入代码量比例。 |
| `classInnerNoise.executionPolicy` | 支持 `referenceOnly` 和 `guardedRare`。 |
| `classInnerNoise.maxTargetLines` | 本次最多新增源码行数。 |
| `classInnerNoise.maxMembersPerClass` | 单个类最多新增垃圾成员数量。 |
| `classInnerNoise.maxHooksPerFile` | 单个 Dart 文件最多插入 hook 数量。 |
| `classInnerNoise.stringNoise.*` | 控制可读垃圾字符串模板、数量和长度。 |
| `classInnerNoise.skipFiles` | 跳过文件规则。 |
| `classInnerNoise.templateGroups.executedLightweight` | 可被业务 hook 轻量触达的同步模板。 |
| `classInnerNoise.templateGroups.retainedOnly` | 只被 retain 函数引用的模板。 |

会跳过 `.g.dart`、`.freezed.dart`、`.gr.dart` 等生成文件，以及 const 构造、抽象方法、getter/setter、operator、expression-bodied 方法等不适合注入的位置。

### 9. Android 项目垃圾代码生成

读取 `obfuscate_dart_noise.json` 中的 `androidNoise` 配置，生成 Android 原生侧 Java 组件、XML 资源和 PNG 图片资源。

结果：

- 生成 Java 源码到 `android/app/src/main/java/<namespace>/<packageSegment>/`。
- 自动解析 `android/app/build.gradle(.kts)` 中的 `namespace`；没有 namespace 时兜底读取 Manifest `package`。
- 生成 Activity、Service、BroadcastReceiver、ContentProvider，并注册到 Manifest。
- 组件使用 `android:exported="false"`，不添加 `intent-filter`。
- Manifest 使用 `<!-- obfuscateflutter: android-noise start/end -->` 标记，重复执行会替换旧区块。
- 可选开启 `deepObfuscation`，对 Android 自有 package、class、resource 名称做更深的业务语义伪装。
- 写入 `obfuscation_mapping.html` 的“Android项目垃圾代码生成”区块。

主要配置：

| 字段 | 说明 |
| --- | --- |
| `androidNoise.enabled` | 是否启用 Android 垃圾代码生成。 |
| `androidNoise.componentCount.activity/service/receiver/provider` | 四大组件生成数量，范围 `0..100`。 |
| `androidNoise.packageSegment` | 追加到 Android namespace 后的包名片段。 |
| `androidNoise.nameTemplates.*` | 类名和方法名模板。 |
| `androidNoise.stringTemplates` | 生成方法内使用的可读字符串模板。 |
| `androidNoise.generateResources.xml/images` | 是否生成 XML 和 PNG 资源。 |
| `androidNoise.resourceTemplates.*` | XML 和 strings.xml 资源模板。 |
| `androidNoise.deepObfuscation.enabled` | 是否开启 Android 全工程深度命名混淆。 |
| `androidNoise.deepObfuscation.skip*` | 跳过文件、类、包和资源。 |
| `androidNoise.deepObfuscation.reflectionRewrite.*` | 是否重写明确反射 API 中的完整类名字符串。 |

深度混淆会同步更新 Java/Kotlin package/import/全限定类名、Manifest、`res/**/*.xml`、`R.type.name` 和明确反射上下文。普通字符串、日志文案、URL、JSON key 不做全局替换。

### 10. iOS Object-C/Swift AST 混淆

读取 `obfuscate_dart_noise.json` 中的 `iosNoise` 配置，扫描 `ios` 目录下的 `.m`、`.mm` 和 `.swift` 文件。Objective-C/Objective-C++ 通过 `xcrun clang -Xclang -ast-dump=json` 读取 AST，Swift 通过 `xcrun swiftc -dump-ast -parse` 读取 AST。

结果：

- 只在可安全定位的方法或函数体内插入无用代码。
- Objective-C 和 Swift 使用不同模板组。
- 默认跳过 `Pods`、`.symlinks`、`Flutter`、`GeneratedPluginRegistrant.*`、构建目录和 `*.pbobjc.*`。
- 默认不改类名、方法签名、文件名、公开 API、import 或业务语句顺序。
- 重复执行时通过旧 marker 或模板 `dedupePatterns` 跳过已注入方法体。
- 成功写入源码后会尝试格式化被修改文件；格式化工具不可用时不阻断。
- 写入 `obfuscation_mapping.html` 的“iOS Object-C/Swift AST 混淆”区块。

主要配置：

| 字段 | 说明 |
| --- | --- |
| `iosNoise.enabled` | 是否启用 iOS AST 混淆。 |
| `iosNoise.targetRatio` | 目标注入代码量比例。 |
| `iosNoise.maxTargetLines` | 本次最多新增源码行数硬上限。 |
| `iosNoise.maxInsertionsPerFile` | 单个文件最多注入次数。 |
| `iosNoise.astFallback` | AST 命令失败策略；当前支持 `skip`。 |
| `iosNoise.skipFiles` | 跳过文件规则。 |
| `iosNoise.templateGroups.objectiveC/swift` | 对应语言的模板列表。 |
| `iosNoise.stringTemplates` | 模板内使用的可读字符串模板。 |
| `iosNoise.codeTemplates` | 可配置垃圾代码模板。 |

### 11. iOS 项目文件名替换

读取 `obfuscate_dart_noise.json` 中的 `iosFileRename` 配置，扫描 `ios` 目录下的 `.m`、`.h`、`.mm` 和 `.swift` 文件，把文件名替换为业务风格名称，并同步更新源码和 `project.pbxproj` 引用。

结果：

- `.h/.m/.mm` 同 basename 成组重命名，`.swift` 单文件重命名。
- 默认跳过 `Pods`、`.symlinks`、`Flutter`、`GeneratedPluginRegistrant.*`、构建目录和 `*.pbobjc.*`。
- 只改文件名和文件名引用，不改 Objective-C/Swift 类名、方法名、公开 API 或业务逻辑。
- 更新 `#import "OldName.h"`、`#include "OldName.h"`、`#import <.../OldName.h>`、完整文件名字符串和 Xcode 工程引用。
- 写入 `obfuscation_mapping.html` 的“iOS 项目文件名替换”区块。

### 12. iOS 内部函数换名

读取 `obfuscate_dart_noise.json` 中的 `iosFunctionRename` 配置，扫描 iOS 自有 `.m`、`.mm` 和 `.swift` 文件，对低风险内部函数进行换名，并同步更新当前文件内调用引用。

当前处理安全子集：

- Objective-C / C：文件内 `static` C 函数。
- Objective-C：`.m/.mm` 内未在 `.h` 暴露的私有 `- / +` 方法 selector。
- Swift：`private func`、`fileprivate func`、`private static func`、`fileprivate static func`。

不会改 `.h` 公开 Objective-C 方法、公开 Swift 函数、`@objc` / `@IBAction` Swift 方法、`main`、`init*`、`set*`、常见生命周期方法、协议/SDK 回调和部分固定 selector。

### 13. iOS 业务代码结构化差异混淆

读取 `obfuscate_dart_noise.json` 中的 `iosStructuralDiff` 配置，扫描 iOS `.m`、`.mm` 和 `.swift` 文件，对可安全识别的业务方法体进行结构化改写。

支持 transform：

- `wrapDispatch`：保留原业务方法签名，把原方法体移动到新私有 helper，原方法改为调用 helper。
- `extractBlock`：把无提前退出的连续安全语句块抽到新私有 helper。
- `splitControlFlow`：在无提前退出的语句块外加入 deterministic guard。

安全边界：

- 默认跳过 `.h`、`Pods`、`.symlinks`、`Flutter`、`GeneratedPluginRegistrant.*`、构建目录和 `*.pbobjc.*`。
- Objective-C 不改头文件公开 selector。
- Swift 跳过 `public`、`@objc`、`@IBAction` 方法。
- 含 `throw`、`break`、`continue`、`defer`、`await` 或无法安全处理的 `return` 的片段会跳过。

输出 `ios_structural_diff_mapping_<timestamp>.json`，记录扫描文件、改写文件、transform、跳过原因和静态校验结果。

### 14. 清理 Dart 源码注释

递归扫描目标项目 `lib/**/*.dart`，删除 `//`、`///`、`/* */` 和 `/** */` 注释。普通业务源码和 `.g.dart`、`.freezed.dart`、`.gr.dart` 等生成文件都会处理。

结果：

- 原地修改包含注释的 Dart 文件。
- 保留必要空格和换行，避免相邻 token 粘连。
- 可移除代码间空行，但保留字符串、raw string 和多行字符串内部内容。
- 不再默认对每个修改文件执行 `dart format`。
- 写入 `obfuscation_mapping.html` 的“Dart 源码注释清理”区块。

注意：`// ignore` 和 `// ignore_for_file` 也会被删除；该功能不处理 `lib` 以外的文件，不生成备份。

## 临时目录模式

输入 `x` 后，工具会：

1. 对原项目执行 `flutter clean`。
2. 在原项目同级创建或覆盖 `temp_<pubspec_name>`。
3. 复制项目到临时目录，复制时跳过 `.git` 和 `build`。
4. 在临时项目中依次执行主要混淆任务，跳过字符串恢复。

当前 `x` 流程执行顺序：

```text
1 图片 MD5
2 图片名称混淆并清理
3 Android Proguard 字典
4 String 混淆
6 统一混淆
7 Dart 随机代码注入/保留
8 类内垃圾代码/字符串注入
9 Android 项目垃圾代码生成
10 iOS Object-C/Swift AST 混淆
11 iOS 项目文件名替换
12 iOS 内部函数换名
14 Dart 源码注释清理
```

注意：当前 `x` 流程不会自动执行功能 `13`，也不会自动构建 APK/AAB/IPA。混淆完成后需要在临时项目中自行执行构建和验证。

## 配置文件

功能 `7`、`8`、`9`、`10`、`11`、`12`、`13` 共用 `obfuscate_dart_noise.json`。

配置读取顺序：

1. 优先读取目标 Flutter 项目根目录下的 `obfuscate_dart_noise.json`。
2. 如果目标项目没有该文件，则读取本工具目录下的默认 `obfuscate_dart_noise.json`。

建议把项目专用配置放在目标 Flutter 项目根目录，这样可以和目标项目一起版本管理，并避免不同项目共用一套过大的默认参数。

最小结构示例：

```json
{
  "pageCount": 24,
  "classCount": 36,
  "methodCountPerClass": 8,
  "template": "page_sync_class",
  "outputDir": "lib/dart_noise",
  "garbageFileCountMin": 70,
  "garbageFileCountMax": 90,
  "snippets": ["widget_layout_page", "sync_math", "sync_string"],
  "snippetWeights": {
    "widget_layout_page": 2,
    "sync_math": 3,
    "sync_string": 2
  },
  "classInnerNoise": {
    "enabled": true,
    "targetRatio": 0.3,
    "executionPolicy": "referenceOnly",
    "maxTargetLines": 3500,
    "maxMembersPerClass": 10,
    "maxHooksPerFile": 18
  },
  "androidNoise": {
    "enabled": true,
    "componentCount": {
      "activity": 8,
      "service": 6,
      "receiver": 5,
      "provider": 3
    },
    "packageSegment": "platform"
  },
  "iosNoise": {
    "enabled": true,
    "targetRatio": 0.4,
    "maxTargetLines": 20000,
    "maxInsertionsPerFile": 20,
    "astFallback": "skip"
  },
  "iosFileRename": {
    "enabled": true,
    "includeExtensions": [".m", ".h", ".mm", ".swift"]
  },
  "iosFunctionRename": {
    "enabled": true,
    "includeExtensions": [".m", ".mm", ".swift"]
  },
  "iosStructuralDiff": {
    "enabled": true,
    "maxTransformsPerFile": 10,
    "transforms": ["wrapDispatch", "extractBlock", "splitControlFlow"],
    "validation": "static_xcode_list"
  }
}
```

默认配置文件包含更完整的模板池、权重、跳过规则和资源模板，可以按项目规模逐步降低或提高数量。

## 建议执行流程

直接在目标项目执行时：

```text
1 图片 MD5
2 图片名称混淆并清理
3 Android Proguard 字典
4 String 混淆
6 统一混淆
7 Dart 随机代码注入/保留
8 类内垃圾代码/字符串注入
9 Android 项目垃圾代码生成
10 iOS Object-C/Swift AST 混淆
11 iOS 项目文件名替换
12 iOS 内部函数换名
13 iOS 业务代码结构化差异混淆
14 Dart 源码注释清理
```

想保持原项目干净时，优先使用 `x` 在临时目录中执行，再到 `temp_<pubspec_name>` 中构建和验证。

执行后建议至少运行：

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --release
```

iOS 项目还建议运行：

```bash
cd ios
pod install
cd ..
flutter build ios --release
```

## 重要注意事项

- 多数功能会原地修改源码或资源，建议在 Git 干净状态下执行。
- 功能 `2` 当前使用字符串匹配处理图片引用，动态资源路径需要人工复核。
- 功能 `4` 和 `6` 使用 analyzer AST，稳定性高于纯字符串替换，但混淆后仍需要跑 `dart analyze`。
- 功能 `7`、`8`、`9`、`10` 会增加源码体积，配置过大可能拉长分析和构建时间。
- 功能 `11`、`12`、`13` 会直接修改 iOS 源码引用；建议先提交当前代码或在临时目录中执行，再用 mapping 复核。
- 功能 `14` 会删除 `lib` 下包括 ignore 指令在内的 Dart 注释，不生成恢复文件。
- 商店审核、重复包识别并不只看代码和资源字节特征，还会综合产品功能、UI、账号、证书、包名、后端、素材来源等多维信息。本工具只能帮助改变工程层面的部分静态特征，不能保证规避任何审核判定。
