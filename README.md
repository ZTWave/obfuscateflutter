
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
