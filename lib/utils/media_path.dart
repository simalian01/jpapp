String resolveMediaPath(String raw, String baseDir) {
  final p = raw.replaceAll('\\\\', '/').replaceAll('\\', '/');
  const marker = '/にほんご/';
  final i = p.indexOf(marker);
  if (i >= 0) {
    final rel = p.substring(i + marker.length);
    return '$baseDir/$rel';
  }
  final p2 = p.replaceFirst(RegExp(r'^[A-Za-z]:/'), '');
  return '$baseDir/${p2.replaceFirst(RegExp(r'^/+'), '')}';
}
