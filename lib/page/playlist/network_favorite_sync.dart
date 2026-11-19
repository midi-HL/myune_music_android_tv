import '../../services/network/network_library.dart';
import '../../services/network/remote_media_registry.dart';
import 'playlist_models.dart';

/// The built-in Favorites playlist is the visible source of truth for drive
/// favorites. Ordinary playlists and Bilibili's separate library are untouched.
Future<void> syncNetworkDriveFavorites(Playlist playlist) async {
  if (!playlist.isDefault) return;
  final store = NetworkLibraryStore.instance;
  await store.load();
  final songs = playlist.songFilePaths.map(RemoteMediaRegistry.lookup)
      .whereType<Song>().where(NetworkLibraryStore.isNetworkDrive).toList();
  final wanted = songs.map((song) => RemoteMediaRegistry.identityOf(song.filePath)).toSet();
  for (final song in store.favorites) {
    if (!wanted.contains(RemoteMediaRegistry.identityOf(song.filePath))) {
      await store.remove(song.filePath);
    }
  }
  await store.addAll(songs);
}
