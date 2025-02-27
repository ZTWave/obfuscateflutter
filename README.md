
# README

混淆你的flutter项目下的文件名称，lib下的目录名称，图片和图片的`md5`值。

⚠️ Windows 和 MacOS 上测试通过 ，
⚠️ 运行工具前将所有的 `import`,`export` 替换为 `package` 开头的引用

### 如何使用

1. 首先运行  `dart pub get`

2. 执行命令 `dart run ./bin/obfuscateflutter.dart -d <项目路径>`v

3. 可选参数 `--dart-define-from-file=define.json` 指定 `dart define json` 路径  可参照 [此处](https://codewithandrea.com/tips/dart-define-from-file-env-json/) 进行使用

4. 按照程序提示选择对应操作即可。
