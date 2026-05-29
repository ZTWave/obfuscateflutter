
# README

混淆你的flutter项目下的文件名称，lib下的目录名称，更新整体的文件树结构，图片和图片的`md5`值。

⚠️ Windows 和 MacOS 上测试通过

## 如何使用

1. 首先运行  `dart pub get`

2. 执行命令 `dart run ./bin/obfuscateflutter.dart -d <项目路径>`

3. 可选参数 `--dart-define-from-file=define.json` 指定 `dart define json` 路径  可参照 [此处](https://codewithandrea.com/tips/dart-define-from-file-env-json/) 进行使用

4. 按照程序提示选择对应操作即可。

## Dart 随机代码注入配置

菜单 `10.Dart随机代码注入/保留` 会在 Flutter 项目的 `lib` 下生成随机 Dart 文件，并自动在 `lib/main.dart` 中注入一次保留调用，避免 release 构建时被 tree shaking 移除。

菜单 `11.类内垃圾代码注入` 会扫描 Flutter 项目的 `lib` 目录，在已有 Dart 类内部插入垃圾成员和轻量可达 hook。高风险 API 模板可以出现在垃圾成员方法中，但业务方法只会插入轻量 retain 调用，不会直接执行这些高风险逻辑。

配置读取顺序：

1. 优先读取目标 Flutter 项目根目录下的 `obfuscate_dart_noise.json`
2. 如果目标项目没有该文件，则读取本工具目录下的默认 `obfuscate_dart_noise.json`

默认配置示例：

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
    "custom_sync_mix",
    "custom_sync_hash"
  ],
  "snippetWeights": {
    "widget_layout_page": 2,
    "sync_math": 3,
    "sync_string": 2,
    "sync_list": 2,
    "sync_model": 2,
    "sync_enum_switch": 1,
    "custom_sync_mix": 2,
    "custom_sync_hash": 2
  },
  "classInnerNoise": {
    "enabled": true,
    "targetRatio": 1.0,
    "executionPolicy": "referenceOnly",
    "maxTargetLines": 8000,
    "maxMembersPerClass": 16,
    "maxHooksPerFile": 30,
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
        "body": "return const DecoratedBox(\n  decoration: BoxDecoration(),\n  child: Padding(\n    padding: EdgeInsets.all({{padding}}),\n    child: SizedBox(width: {{width}}, height: {{height}}),\n  ),\n);"
      }
    ],
    "methodBodies": [
      {
        "id": "custom_sync_mix",
        "body": "final mixed = input + seed + {{salt}};\nfinal rotated = (mixed << {{shift}}) ^ (mixed >> 1);\nreturn (rotated + seed + {{salt}}) & 0x3fffffff;"
      }
    ]
  }
}
```

### 配置字段

| 字段 | 说明 |
| --- | --- |
| `pageCount` | 生成随机页面类数量，范围 `1-20`。 |
| `classCount` | 生成随机普通 Dart 类数量，范围 `1-50`。 |
| `methodCountPerClass` | 每个随机类内生成的同步方法数量，范围 `1-20`。 |
| `template` | 当前固定为 `page_sync_class`。 |
| `outputDir` | 兼容字段，必须位于 `lib` 下。当前生成策略会优先注入项目已有目录，避免明显的固定垃圾目录。 |
| `garbageFileCountMin` | 本次生成垃圾 Dart 文件数量下限，范围 `3-50`。 |
| `garbageFileCountMax` | 本次生成垃圾 Dart 文件数量上限，范围 `garbageFileCountMin-50`。实际数量会在区间内随机。 |
| `snippets` | 启用的内置片段或自定义模板 `id`。 |
| `snippetWeights` | 控制方法类片段生成比例，值范围 `1-20`。 |
| `customTemplates.pageBodies` | 自定义页面 `build` 方法体模板。 |
| `customTemplates.methodBodies` | 自定义同步方法体模板。 |

### 类内垃圾代码注入

菜单 `11.类内垃圾代码注入` 使用同一个 `obfuscate_dart_noise.json` 中的 `classInnerNoise` 配置。

| 字段 | 说明 |
| --- | --- |
| `classInnerNoise.enabled` | 是否启用类内注入。菜单 11 执行时为 `false` 会直接跳过。 |
| `classInnerNoise.targetRatio` | 目标注入代码量比例。默认 `1.0`，表示尽量接近原 `lib` 业务 Dart 非空行数的 1 倍。 |
| `classInnerNoise.executionPolicy` | 当前支持 `referenceOnly` 和 `guardedRare`，默认 `referenceOnly`。高风险模板只做 tear-off 引用，不在正常业务路径执行。 |
| `classInnerNoise.maxTargetLines` | 本次最多新增的源码行数，避免超大项目生成过多代码。 |
| `classInnerNoise.maxMembersPerClass` | 单个类内最多新增的垃圾成员数量。 |
| `classInnerNoise.maxHooksPerFile` | 单个 Dart 文件最多插入的业务 hook 数量。 |
| `classInnerNoise.skipFiles` | 跳过文件规则，默认跳过 `*.g.dart`、`*.freezed.dart`、`*.gr.dart`。 |
| `classInnerNoise.templateGroups.executedLightweight` | 会被业务 hook 轻量触达的同步模板。 |
| `classInnerNoise.templateGroups.retainedOnly` | 只被 retain 函数引用的高风险模板。 |

类内注入只处理普通 `class`，并且只在 block-bodied 方法或非 `const` 构造函数中插入 hook。它会跳过 `const` 构造、注解、常量表达式、expression-bodied 方法、生成文件和无法安全解析的文件，避免出现 `Methods can't be invoked in constant expressions` 之类的错误。

业务方法中插入的 hook 形态类似：

```dart
final _obfNoiseAbc123 = _obfXyzRetain(identityHashCode(this)); // obfuscateflutter: class-inner hook
if (_obfNoiseAbc123 == -1) {
  _obfXyzRetain(_obfNoiseAbc123);
}
```

高风险 API 只出现在类内垃圾成员方法体中，例如 `Future`、`Timer`、`File`、`HttpClient`、`MethodChannel`、`Navigator`、`setState`、`runApp`、`debugPrint`。默认策略不会从业务 hook 中调用这些方法，只会通过 tear-off 保留引用，降低 release tree shaking 移除概率，同时避免阻塞业务或改变正常运行逻辑。

#### 类内模板和 import

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

工具会在写入前解析文件已有 import，并按实际使用的模板自动补齐缺失 import：

- 不重复添加已有 import。
- 文件已存在 `package:flutter/widgets.dart` 或 `package:flutter/material.dart` 时，会复用 Flutter import。
- 只添加本次实际使用模板需要的 import。
- 模板需要 Flutter import 但目标项目 `pubspec.yaml` 没有 Flutter 依赖时，会跳过对应模板并记录到映射文档。

菜单 11 执行后会输出 `class_inner_noise_mapping_<timestamp>.json`，记录原始行数、目标新增行数、实际新增行数、修改文件、修改类、成员名、hook 位置、使用模板、自动新增 import 和跳过原因。

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

生成后的垃圾文件会通过 `main.dart -> obfDartNoiseRetain() -> 随机文件调用链` 被同步引用
