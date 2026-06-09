# obfuscateflutter

Flutter 项目混淆辅助工具，支持图片字节扰动、图片资源名清理、Android Proguard 字典生成、Dart 字符串加密、AST 文件/目录重命名、随机 Dart 垃圾文件生成、类内垃圾代码注入、Android 垃圾组件/资源生成，以及常用 release 包构建。

已在 macOS / Windows 测试过基础流程。执行混淆前建议先提交代码或复制一份项目，因为大多数功能会直接修改目标项目文件。

## 快速开始

```bash
dart pub get
dart run ./bin/obfuscateflutter.dart -d <Flutter项目路径>
```

可选传入 dart define 文件，构建 APK/AAB/IPA 时会继续透传：

```bash
dart run ./bin/obfuscateflutter.dart \
  -d <Flutter项目路径> \
  --dart-define-from-file=<define.json>
```

启动后按菜单编号选择任务：

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
x.在临时生成目录中进行执行上述混淆任务并打包
```

## 功能结果和用法

| 编号 | 功能 | 主要结果 | 适用场景 |
| --- | --- | --- | --- |
| `1` | 修改图片 MD5 | 直接改写 `pubspec.yaml` assets 下的图片文件，打印处理前后 MD5。 | 需要在视觉变化极小的前提下改变图片二进制特征。 |
| `2` | 混淆图片名称并清理 | 随机重命名被 Dart 代码引用的图片；删除未检测到引用的图片；同步替换 Dart 字符串中的资源名或资源路径。 | 清理未使用图片，并降低固定资源名特征。 |
| `3` | 生成 Android Proguard 字典 | 写入 `android/app/dict.txt`，包含 10000 个随机名称。 | 配合 Android `proguard-rules.pro` 的 `-obfuscationdictionary` 等配置使用。 |
| `4` | 混淆项目中所有 String | 新增或更新 `lib/stren_arg.dart`；将可安全处理的字符串替换为 `des("...")` 调用；自动补 import。 | 隐藏 Dart 源码中的普通字符串字面量。 |
| `5` | 恢复已混淆 String | 根据 `lib/stren_arg.dart` 中的 `SEP/SEK` 还原 `des("...")` 字符串；无引用后删除 `stren_arg.dart`。 | 回滚功能4产生的字符串加密改动。 |
| `6` | 统一混淆 | AST 重写 import/export/part URI，重命名 `lib` 下目录和 Dart 文件，修正 `.g.dart/.freezed.dart` 的 `part of`，输出映射文档。 | 需要可追踪的文件/目录结构混淆。 |
| `7` | Dart 随机代码注入/保留 | 在 `lib` 下生成随机 Dart 文件；修改 `lib/main.dart` 注入 retain 调用；输出生成映射文档。 | 增加同步可达代码、页面类、方法类和随机 shard 文件。 |
| `8` | 类内垃圾代码注入 | 向已有类内部插入垃圾成员和轻量 hook；必要时补 import；输出类内注入映射文档。 | 在不额外链接独立工具文件的前提下，让已有业务类产生差异。 |
| `9` | Android 项目垃圾代码生成 | 在 `android/app/src/main/java` 下生成 Java 四大组件类；生成 XML/PNG 资源；向 Manifest 注册组件；输出映射文档。 | 让 Android 侧无业务调用的组件和资源在打包后保留。 |
| `x` | 临时目录执行混淆并打包 | 复制项目到临时目录，依次执行图片 MD5、图片名处理、Proguard 字典、统一混淆，再按选择打包，最后把产物复制回原项目。 | 希望原项目源码保持干净，只拿混淆构建产物。 |

## 功能说明

### 1. 修改图片 MD5

读取 `pubspec.yaml` 中声明的 assets 目录，处理 `.png`、`.jpg`、`.jpeg`、`.webp` 文件。

结果：

- 可解码图片会进行轻微像素扰动：亮度约 `±1.5`、对比度约 `±0.5%`、可选 `±1` 噪声。
- PNG/JPEG 会重新编码写回原文件。
- 无法解码或暂不支持重新编码的格式会追加少量随机字节。
- 控制台输出每张图片处理前后的 MD5。

注意：该功能是原地修改图片，不会生成备份。

### 2. 混淆图片名称并清理

读取 assets 图片，生成随机文件名，然后扫描 `lib/**/*.dart` 替换常见图片引用写法。

结果：

- 被检测到引用的图片会被重命名。
- 未检测到引用的图片会被删除。
- Dart 代码中匹配到的 `'xxx.png'`、`"xxx.png"`、`'assets/path/xxx.png'`、`"assets/path/xxx.png"` 会同步替换。

注意：当前是字符串匹配，不是 AST 资源追踪。动态拼接、服务端下发资源名、非 Dart 文件里的引用可能无法识别。

### 3. 生成 Android Proguard 字典

在目标 Flutter 项目的 `android/app/dict.txt` 写入 10000 个随机 key。

常见接入方式是在 Android Proguard 配置中引用：

```proguard
-obfuscationdictionary dict.txt
-classobfuscationdictionary dict.txt
-packageobfuscationdictionary dict.txt
```

### 4. 混淆项目中所有 String

扫描 `lib/**/*.dart`，跳过 `.g.dart`、`.freezed.dart` 和生成的 `lib/stren_arg.dart`。使用 analyzer AST 查找可安全替换的普通字符串字面量。

结果：

- 生成 `lib/stren_arg.dart`，保存 `SEP`、`SEK` 和 `des()` 解密函数。
- 普通字符串会被替换为 `des("<SEP+加密文本>")`。
- 自动插入 `import 'package:<pubName>/stren_arg.dart';`，并保证 import 位于 `part` 之前。

会跳过的典型场景：

- import/export/part URI。
- 注解、常量表达式、const 上下文。
- switch case、pattern、const 构造初始化等必须编译期常量的位置。
- 已经被 `des()` 包裹的字符串。

### 5. 恢复项目中已混淆的 String

根据 `lib/stren_arg.dart` 中的参数反向恢复字符串。

结果：

- 将 `des("<SEP+加密文本>")` 还原为普通 Dart 字符串。
- 自动移除不再需要的 `stren_arg.dart` import。
- 如果项目中已无引用，会删除 `lib/stren_arg.dart`。

### 6. 统一混淆

统一混淆是当前推荐的文件/目录重命名入口。旧的独立“重命名 lib 目录名称”和“重命名所有文件名”菜单已移除。

处理范围：

- `lib/**/*.dart`
- 跳过 `.g.dart`、`.freezed.dart`
- 跳过 `lib/stren_arg.dart`

结果：

- 重命名 `lib` 下目录。
- 重命名 Dart 文件，保留 `main.dart` 文件名。
- 使用 AST 重写 import/export/part 中的 URI。
- 修正同目录 `.g.dart/.freezed.dart` 中的 `part of 'old.dart';`。
- 输出 `obfuscation_mapping_<timestamp>.json`。

映射文档记录：

- `file_renames`
- `directory_renames`
- 每个文件的 import 重写数量
- 汇总统计信息

注意：如果项目中存在非标准代码生成关系、字符串拼接 import、或构建脚本硬编码文件路径，需要手动复核。

### 7. Dart 随机代码注入/保留

该功能会读取配置，在 `lib` 下生成随机 Dart 文件，并在 `lib/main.dart` 中注入一次 `obfDartNoiseRetain()` 调用，避免 release tree shaking 移除生成代码。

结果：

- 生成页面类、同步 worker 类和 shard 工具函数。
- 垃圾文件会尽量分散到项目已有目录和随机目录中，避免单一固定目录特征。
- 同一个 shard 文件内部会轮换不同函数模板，避免一整个文件重复同一种函数结构。
- 输出 `dart_noise_mapping_<timestamp>.json`。

映射文档记录：

- 实际使用的配置文件。
- 入口文件路径。
- 生成文件列表。
- 页面类、普通类、方法列表。
- snippet 使用次数。

### 8. 类内垃圾代码注入

该功能使用 `obfuscate_dart_noise.json` 中的 `classInnerNoise` 配置，扫描已有 Dart 类，把垃圾成员和轻量 hook 插入当前文件和当前类内部。

结果：

- 不创建外部链接工具文件。
- 垃圾成员插入到已有 class 内。
- hook 插入到普通 block-bodied 方法或安全的非 const 构造函数内部。
- 每次插入会随机化成员名、局部变量名、seed、分支和表达式，避免完全复制。
- 必要时只追加缺失 import，并保留已有 import 的 `show/hide/as` 子句。
- 输出 `class_inner_noise_mapping_<timestamp>.json`。

会跳过：

- `.g.dart`、`.freezed.dart`、`.gr.dart` 等生成文件。
- const 构造、抽象方法、getter/setter、operator、expression-bodied 方法。
- 无法安全解析或没有可注入 class/method 的文件。


### 9. Android项目垃圾代码生成

## Dart 随机代码注入配置

菜单 `10` 和 `11` 共用 `obfuscate_dart_noise.json`。

配置读取顺序：

1. 优先读取目标 Flutter 项目根目录下的 `obfuscate_dart_noise.json`
2. 如果目标项目没有该文件，则读取本工具目录下的默认 `obfuscate_dart_noise.json`

示例：

```json
{
  "pageCount": 6,
  "classCount": 12,
  "methodCountPerClass": 8,
  "template": "page_sync_class",
  "outputDir": "lib/dart_noise",
  "garbageFileCountMin": 30,
  "garbageFileCountMax": 50,
  "snippets": [
    "widget_layout_page",
    "sync_math",
    "sync_string",
    "sync_list",
    "sync_model",
    "sync_enum_switch",
    "custom_page_shell",
    "custom_sync_mix"
  ],
  "snippetWeights": {
    "widget_layout_page": 2,
    "sync_math": 3,
    "sync_string": 2,
    "sync_list": 2,
    "sync_model": 2,
    "sync_enum_switch": 1,
    "custom_sync_mix": 2
  },
  "classInnerNoise": {
    "enabled": true,
    "targetRatio": 1.0,
    "executionPolicy": "referenceOnly",
    "maxTargetLines": 8000,
    "maxMembersPerClass": 16,
    "maxHooksPerFile": 30,
    "stringNoise": {
      "enabled": true,
      "memberStringCountPerClass": [2, 6],
      "localStringCountPerHook": [0, 3],
      "minLength": 6,
      "maxLength": 96,
      "templates": [
        {
          "id": "session_word_seed",
          "value": "session_{{word}}_{{seed}}"
        },
        {
          "id": "trace_context",
          "value": "trace.{{className}}.{{methodName}}.{{index}}"
        },
        {
          "id": "cache_ready",
          "value": "cache {{noun}} ready {{seed}}"
        }
      ],
      "templateWeights": {
        "session_word_seed": 2,
        "trace_context": 3,
        "cache_ready": 2
      }
    },
    "skipFiles": [
      "**/*.g.dart",
      "**/*.freezed.dart",
      "**/*.gr.dart"
    ],
    "templateGroups": {
      "executedLightweight": [
        "sync_hash",
        "sync_switch"
      ],
      "retainedOnly": [
        "async_future",
        "timer_stub",
        "file_io_stub",
        "network_stub",
        "platform_channel_stub",
        "navigator_stub",
        "set_state_stub",
        "run_app_stub",
        "debug_log_stub"
      ]
    }
  },
  "customTemplates": {
    "pageBodies": [
      {
        "id": "custom_page_shell",
        "body": "return const SizedBox(width: {{width}}, height: {{height}});"
      }
    ],
    "methodBodies": [
      {
        "id": "custom_sync_mix",
        "body": "final mixed = input + seed + {{salt}};\nreturn (mixed * {{shift}}) & 0x3fffffff;"
      }
    ]
  }
}
```

### 配置字段

| 字段 | 说明 |
| --- | --- |
| `pageCount` | 生成随机页面类数量。 |
| `classCount` | 生成随机普通 Dart 类数量。 |
| `methodCountPerClass` | 每个随机类内生成的同步方法数量。 |
| `template` | 当前固定为 `page_sync_class`。 |
| `outputDir` | 兼容字段，必须位于 `lib` 下；当前生成策略会优先分散到项目目录。 |
| `garbageFileCountMin` | 本次生成垃圾 Dart 文件数量下限。 |
| `garbageFileCountMax` | 本次生成垃圾 Dart 文件数量上限。 |
| `snippets` | 启用的内置片段或自定义模板 `id`。 |
| `snippetWeights` | 控制片段选择权重，值越高越容易被选中。 |
| `customTemplates.pageBodies` | 自定义页面 `build` 方法体模板。 |
| `customTemplates.methodBodies` | 自定义同步方法体模板。 |

### 内置 snippets

| snippet | 类型 | 说明 |
| --- | --- | --- |
| `widget_empty_page` | 页面 | 生成轻量 `StatelessWidget`，返回空组件。 |
| `widget_layout_page` | 页面 | 生成包含 `Padding`、`Row`、`SizedBox` 的轻量布局。 |
| `sync_math` | 方法 | 生成同步整数计算和位运算。 |
| `sync_string` | 方法 | 生成同步字符串和 `codeUnits` 混合计算。 |
| `sync_list` | 方法 | 生成同步 `List<int>.generate` 和 fold 计算。 |
| `sync_model` | 方法 | 生成 model 类、`copyWith` 和同步引用。 |
| `sync_enum_switch` | 方法 | 生成 enum 和 switch 分支计算。 |

### 自定义模板

自定义模板通过 `customTemplates` 配置，并在 `snippets` 中引用其 `id`。

页面模板写在 `pageBodies` 中，模板内容会放入 `Widget build(BuildContext context)` 方法体内，必须返回一个 `Widget`：

```json
{
  "id": "custom_page_shell",
  "body": "return const SizedBox(width: {{width}}, height: {{height}});"
}
```

方法模板写在 `methodBodies` 中，模板内容会放入 `int methodName(int input)` 方法体内，必须返回 `int`：

```json
{
  "id": "custom_sync_mix",
  "body": "final mixed = input + seed + {{salt}};\nreturn (mixed * {{shift}}) & 0x3fffffff;"
}
```

支持的占位符：

| 占位符 | 可用位置 | 说明 |
| --- | --- | --- |
| `{{width}}` | 页面模板 | 随机宽度。 |
| `{{height}}` | 页面模板 | 随机高度。 |
| `{{padding}}` | 页面模板 | 随机 padding。 |
| `{{salt}}` | 方法模板 | 随机整数盐值。 |
| `{{shift}}` | 方法模板 | 随机位移值。 |

为保证生成代码稳定且不影响主流程，自定义模板禁止包含：

```text
Future, Stream, async, await, Timer, import, export, part, dart:io, dart:async, @pragma
```

### 类内垃圾代码配置

| 字段 | 说明 |
| --- | --- |
| `classInnerNoise.enabled` | 是否启用类内注入。菜单 11 执行时为 `false` 会直接跳过。 |
| `classInnerNoise.targetRatio` | 目标注入代码量比例。默认 `1.0`，表示尽量接近原 `lib` 业务 Dart 非空行数的 1 倍。 |
| `classInnerNoise.executionPolicy` | 支持 `referenceOnly` 和 `guardedRare`。默认 `referenceOnly`，高风险模板只做引用保留。 |
| `classInnerNoise.maxTargetLines` | 本次最多新增源码行数。 |
| `classInnerNoise.maxMembersPerClass` | 单个类内最多新增垃圾成员数量。 |
| `classInnerNoise.maxHooksPerFile` | 单个 Dart 文件最多插入业务 hook 数量。 |
| `classInnerNoise.stringNoise.enabled` | 是否启用可读垃圾 String 注入。默认启用。 |
| `classInnerNoise.stringNoise.memberStringCountPerClass` | 每个目标 class 内生成的成员字符串数量范围，例如 `[2, 6]`。 |
| `classInnerNoise.stringNoise.localStringCountPerHook` | 每个 hook 点插入的方法局部字符串数量范围，例如 `[0, 3]`。 |
| `classInnerNoise.stringNoise.templates` | 可读字符串模板，使用 `{ "id": "...", "value": "..." }`。 |
| `classInnerNoise.stringNoise.templateWeights` | 字符串模板权重。 |
| `classInnerNoise.stringNoise.minLength` / `maxLength` | 渲染后字符串长度边界。 |
| `classInnerNoise.skipFiles` | 跳过文件规则。 |
| `classInnerNoise.templateGroups.executedLightweight` | 可被业务 hook 轻量触达的同步模板。 |
| `classInnerNoise.templateGroups.retainedOnly` | 只被 retain 函数引用的模板。 |

类内 String 注入会保持明文可读，不使用功能4的 `des()` 加密。生成形态包括：

```dart
static const String _obfXxxText0 = 'trace.Repo.load.0';
static const List<String> _obfXxxTexts = [_obfXxxText0];
static const Map<String, String> _obfXxxTextMap = {'k0': _obfXxxText0};

final obfTextAbc = 'cache payload ready 123456';
var obfTextSeed = obfTextAbc.codeUnits.fold<int>(seed, ...);
```

支持的 String 模板占位符：

| 占位符 | 说明 |
| --- | --- |
| `{{prefix}}` | 本次 class 注入前缀。 |
| `{{className}}` | 当前类名。 |
| `{{methodName}}` | 当前方法名；成员字符串使用 `member`。 |
| `{{seed}}` | 随机数字。 |
| `{{word}}` / `{{verb}}` / `{{noun}}` | 内置中性可读词库。 |
| `{{index}}` | 当前字符串序号。 |

String 模板只能是普通文本，不允许换行、分号、`import`、`part`、`class`、`Future`、`await` 等代码片段。菜单 11 的映射文档会额外输出 `string_templates_used` 和 `strings_injected`，用于追踪注入的模板、位置和实际字符串。

类内模板和自动 import：

| 模板 | 类型 | 自动 import | 说明 |
| --- | --- | --- | --- |
| `sync_hash` | 轻量 | 无 | 同步 hash/codeUnits 计算。 |
| `sync_switch` | 轻量 | 无 | 同步 switch 分支计算。 |
| `async_future` | 保留 | `dart:async` | 生成 async/Future 方法体，只被引用。 |
| `timer_stub` | 保留 | `dart:async`、`package:flutter/widgets.dart` | 生成 Timer/debugPrint 方法体，只被引用。 |
| `file_io_stub` | 保留 | `dart:io` | 生成 File 引用方法体，只被引用。 |
| `network_stub` | 保留 | `dart:io` | 生成 HttpClient 引用方法体，只被引用。 |
| `platform_channel_stub` | 保留 | `package:flutter/services.dart` | 生成 MethodChannel 引用方法体，只被引用。 |
| `navigator_stub` | 保留 | `package:flutter/widgets.dart` | 生成 Navigator 引用方法体，只被引用。 |
| `set_state_stub` | 保留 | `package:flutter/widgets.dart` | 生成 setState 动态引用方法体，只被引用。 |
| `run_app_stub` | 保留 | `package:flutter/widgets.dart` | 生成 runApp 方法体，只被引用。 |
| `debug_log_stub` | 保留 | `package:flutter/widgets.dart` | 生成 debugPrint 方法体，只被引用。 |

### 12. Android 项目垃圾代码生成

该功能使用 `obfuscate_dart_noise.json` 中的 `androidNoise` 配置，生成 Android 原生侧 Java 垃圾组件、XML 资源和 PNG 图片资源。

结果：

- 生成 Java 源码到 `android/app/src/main/java/<namespace>/<packageSegment>/`。
- 自动解析 `android/app/build.gradle(.kts)` 中的 `namespace`；没有 namespace 时兜底读取 Manifest `package`。
- 生成 Activity、Service、BroadcastReceiver、ContentProvider，并注册到 `android/app/src/main/AndroidManifest.xml`。
- 组件全部使用 `android:exported="false"`，不添加 `intent-filter`，不会暴露外部启动入口。
- 默认资源名使用可读业务词，例如 `activity_panel.xml`、`session_marker.xml`、`profile_badge.png`，避免 `noise/obf` 这类特征字段。
- Manifest 使用 `<!-- obfuscateflutter: android-noise start/end -->` 标记，重复执行会替换旧区块，不会重复注册。
- 可选开启 `deepObfuscation`，对 Android 自有 package、class、resource 名称做更深的业务语义伪装。
- 输出 `android_noise_mapping_<timestamp>.json`，记录生成类、资源、Manifest 注入项、深度重命名、跳过项和配置来源。

默认 Java 类名和方法名会使用业务语义词，例如 `AnalyticsSessionActivity`、`PaymentRouteService`、`collectSessionSignal`。可以通过配置模板调整：

```json
{
  "androidNoise": {
    "enabled": true,
    "componentCount": {
      "activity": 4,
      "service": 4,
      "receiver": 4,
      "provider": 2
    },
    "packageSegment": "platform",
    "nameTemplates": {
      "classNames": [
        "AnalyticsSession{{component}}",
        "PaymentRoute{{component}}"
      ],
      "methodNames": [
        "collectSessionSignal",
        "mergePaymentRoute"
      ]
    },
    "stringTemplates": [
      "session {{component}} payload {{index}}",
      "payment route {{className}} {{index}}"
    ],
    "generateResources": {
      "xml": true,
      "images": true
    },
    "deepObfuscation": {
      "enabled": false,
      "skipFiles": [
        "**/GeneratedPluginRegistrant.java",
        "**/GeneratedPluginRegistrant.kt",
        "**/MainActivity.java",
        "**/MainActivity.kt"
      ],
      "skipClasses": [
        "GeneratedPluginRegistrant",
        "MainActivity"
      ],
      "skipPackages": [],
      "skipResources": [
        "ic_launcher*",
        "mipmap/ic_launcher*"
      ],
      "packageTemplates": [
        "account.{{word}}"
      ],
      "classTemplates": [
        "Session{{className}}"
      ],
      "resourceTemplates": [
        "profile_{{name}}"
      ],
      "semanticWords": [
        "profile",
        "session",
        "account"
      ],
      "reflectionRewrite": {
        "enabled": true,
        "strict": true
      }
    },
    "resourceTemplates": {
      "drawableXml": [
        {
          "name": "activity_panel",
          "body": "<shape xmlns:android=\"http://schemas.android.com/apk/res/android\"><solid android:color=\"#01000000\" /></shape>"
        }
      ],
      "layoutXml": [
        {
          "name": "session_marker",
          "body": "<FrameLayout xmlns:android=\"http://schemas.android.com/apk/res/android\" android:layout_width=\"1dp\" android:layout_height=\"1dp\" android:background=\"@drawable/{{drawableName}}\" />"
        }
      ],
      "stringValues": [
        {
          "name": "session_title",
          "value": "Session {{index}}"
        },
        {
          "name": "profile_state",
          "value": "Profile route {{packageName}}"
        }
      ]
    }
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `androidNoise.enabled` | 是否启用 Android 垃圾代码生成。 |
| `androidNoise.componentCount.activity/service/receiver/provider` | 四大组件各自生成数量，范围 `0..100`。 |
| `androidNoise.packageSegment` | 追加到 Android namespace 后的包名片段，例如 `platform`。 |
| `androidNoise.nameTemplates.classNames` | 类名模板；`{{component}}` 会替换为 `Activity/Service/Receiver/Provider`。 |
| `androidNoise.nameTemplates.methodNames` | 方法名模板；支持 `{{index}}`。 |
| `androidNoise.stringTemplates` | 生成方法内使用的可读字符串模板。 |
| `androidNoise.generateResources.xml/images` | 是否生成 XML 和 PNG 资源。 |
| `androidNoise.resourceTemplates.drawableXml/layoutXml` | XML 资源模板数组，`name` 是不带扩展名的 Android 资源名，`body` 是写入文件的 XML 内容。 |
| `androidNoise.resourceTemplates.stringValues` | `strings.xml` 字符串模板数组，`name` 是字符串资源名，`value` 支持 `{{packageName}}`、`{{namespace}}`、`{{resourceName}}`、`{{drawableName}}`、`{{index}}`。 |
| `androidNoise.deepObfuscation.enabled` | 是否开启 Android 全工程深度命名混淆；默认关闭。 |
| `androidNoise.deepObfuscation.skipFiles/skipClasses/skipPackages/skipResources` | 跳过模板；默认保护 `GeneratedPluginRegistrant`、`MainActivity` 和 launcher 图标。 |
| `androidNoise.deepObfuscation.packageTemplates/classTemplates/resourceTemplates/semanticWords` | 深度混淆名称模板；使用业务语义词，不生成 `noise/obf` 字段。 |
| `androidNoise.deepObfuscation.reflectionRewrite.enabled/strict` | 是否重写明确反射 API 中的完整类名字符串；严格模式不会改普通字符串。 |

深度混淆会同步更新：

- Java/Kotlin 的 `package`、`import`、全限定类名、`R.type.name`。
- `AndroidManifest.xml` 和 `res/**/*.xml` 中的组件类名、自定义 View 标签、`@layout/@drawable/...` 等资源引用。
- 明确反射上下文中的完整类名字符串，例如 `Class.forName("...")`、`loadClass("...")`、`Intent.setClassName(...)`、`ComponentName(...)`。

普通字符串、日志文案、URL、JSON key 不会做全局替换。拼接形式的反射字符串不会自动修改，会写入 mapping 的 `warnings`。

XML 资源模板支持占位符：

| 占位符 | 说明 |
| --- | --- |
| `{{namespace}}` | Android namespace。 |
| `{{packageName}}` | 生成 Java 组件包名。 |
| `{{resourceName}}` | 当前 XML 资源名。 |
| `{{drawableName}}` | 第一个 drawable XML 资源名，便于 layout 引用。 |
| `{{index}}` | 当前模板序号。 |

## 建议流程

需要直接改项目源码时：

```text
1 图片 MD5
2 图片名称混淆并清理
3 Android Proguard 字典
4 String 混淆
9 统一混淆
10 Dart 随机代码注入
11 类内垃圾代码注入
12 Android 项目垃圾代码生成
5/6/7 打包
```

想保持原项目干净时，使用 `x` 在临时目录中执行混淆和打包。

执行后建议至少运行：

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --release
```

## 重要注意事项

- 所有会改源码或资源的功能都建议在 Git 干净状态下执行。
- 功能2当前使用字符串匹配处理图片引用，动态拼接资源路径需要人工复核。
- 功能4和功能9使用 analyzer AST，稳定性高于纯字符串替换，但仍建议混淆后跑 `dart analyze`。
- 功能10/11 会增加源码体积，配置过大可能拉长分析和构建时间。
- 商店审核、重复包识别并不只看代码和资源字节特征，还会综合产品功能、UI、账号、证书、包名、后端、素材来源等多维信息。本工具只能帮助改变工程层面的部分静态特征，不能保证规避任何审核判定。
