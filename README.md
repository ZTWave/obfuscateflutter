
# README

!! **Only Test On Windows** !!

obfuscate an flutter project libs child file and floder name and update import.

first run  
`
dart pub get
`

then run  
`
dart run ./bin/obfuscateflutter.dart -d <flutter_project_dir>
`  

then you can get apk-v8 file from shell output.
if run with no `-d <flutter_project_dir>` will use parent location path install.
