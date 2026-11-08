/// 网络硬盘 / 共享网盘上的一个目录项。
///
/// [path] 对 WebDAV 是服务端返回的原始 href（已做过 URL 编码，可直接用
/// `Uri.resolve` 拼接请求），对 FTP 是 POSIX 风格的绝对路径。
/// 两种协议统一成同一模型，页面层不需要区分。
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  static final RegExp _audioExt = RegExp(
    r'\.(mp3|flac|wav|m4a|aac|ogg|oga|opus|wma|ape|aiff|aif|dsf|dff|mp2|m4b|alac|amr|mid|midi)$',
    caseSensitive: false,
  );

  bool get isAudio => !isDirectory && _audioExt.hasMatch(name);

  String get sizeLabel {
    final bytes = size;
    if (bytes == null || bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
