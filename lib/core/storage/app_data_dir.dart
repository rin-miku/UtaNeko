import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _portableName = 'utaneko-data';

/// 注音缓存和下载的词典放这里。
///
/// Android 用应用私有目录，系统卸载时会整目录删掉。
/// Windows 没有安装器，数据跟 exe 放在一起，删掉程序文件夹即清空。
Future<Directory> appDataDirectory() async {
  if (!Platform.isWindows) {
    return getApplicationSupportDirectory();
  }
  final dir = Directory(
    p.join(File(Platform.resolvedExecutable).parent.path, _portableName),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  await _moveLegacyWindowsData(dir);
  return dir;
}

/// 旧版本写在 %AppData%\com.utaneko\UtaNeko。搬到程序目录后删掉原件，避免卸载后还留着词典。
Future<void> _moveLegacyWindowsData(Directory portable) async {
  final legacyRoot = await getApplicationSupportDirectory();
  const names = ['kuromoji-dict', 'tomoshi-dict', 'furi-cache'];
  for (final name in names) {
    final from = Directory(p.join(legacyRoot.path, name));
    if (!await from.exists()) continue;
    final to = Directory(p.join(portable.path, name));
    if (!await to.exists()) {
      await _moveDirectory(from, to);
    } else if (await from.exists()) {
      await from.delete(recursive: true);
    }
  }
}

Future<void> _moveDirectory(Directory from, Directory to) async {
  try {
    await from.rename(to.path);
    return;
  } on FileSystemException {
    // AppData 和程序经常不在同一个盘，rename 会失败。
  }
  await _copyDirectory(from, to);
  await from.delete(recursive: true);
}

Future<void> _copyDirectory(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(recursive: false)) {
    final dest = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(dest));
    } else if (entity is File) {
      await entity.copy(dest);
    }
  }
}
