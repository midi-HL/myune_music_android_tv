/// Index of the same playing item after a reorder/removal. If the playing item
/// was removed, retain its predecessor so NEXT selects the following item.
int reconcilePlayingIndex(List<String> paths, String currentPath, int previous, {String Function(String)? identityOf}) {
  final identity = identityOf ?? (String value) => value;
  final key = identity(currentPath);
  final found = paths.indexWhere((path) => identity(path) == key);
  if (found >= 0) return found;
  return (previous - 1).clamp(-1, paths.length - 1).toInt();
}

int nextGaplessIndex(int currentIndex, int count, {List<int>? shuffleOrder, bool repeatOne = false}) {
  if (count <= 0) return 0;
  if (repeatOne) return currentIndex;
  if (shuffleOrder != null && shuffleOrder.length == count) {
    final position = shuffleOrder.indexOf(currentIndex);
    if (position < 0 || position == shuffleOrder.length - 1) return shuffleOrder.first;
    return shuffleOrder[position + 1];
  }
  return (currentIndex + 1) % count;
}

/// Compute a queue edit without removing the item that is currently playing.
({List<T> items, int currentIndex, int nextIndex, bool changed}) moveQueueItemNext<T>(
  List<T> queue,
  int currentIndex,
  T item,
  String Function(T) pathOf,
) {
  final items = List<T>.from(queue);
  final path = pathOf(item);
  final existing = items.indexWhere((entry) => pathOf(entry) == path);
  if (existing == currentIndex && existing >= 0) {
    return (items: items, currentIndex: currentIndex, nextIndex: currentIndex, changed: false);
  }
  var current = currentIndex;
  if (existing >= 0) {
    items.removeAt(existing);
    if (existing < current) current--;
  }
  final next = (current + 1).clamp(0, items.length).toInt();
  items.insert(next, item);
  return (items: items, currentIndex: current, nextIndex: next, changed: true);
}

/// Only real filesystem paths can be checked with File.exists. Opaque SAF and
/// network URI identifiers must never be classified as missing local files.
bool canCheckAsLocalFile(String path) =>
    !path.contains('://') &&
    !path.startsWith('bilibili:') &&
    !path.startsWith('nas:') &&
    !path.startsWith('gd:');

/// Complete every source before handing a scan result to destructive diffing.
/// A failed directory makes the entire refresh fail without a partial result.
Future<Set<String>> collectFolderPaths(
  List<String> folders,
  Future<Iterable<String>> Function(String) scan,
) async {
  final result = <String>{};
  for (final folder in folders) {
    result.addAll(await scan(folder));
  }
  return result;
}
