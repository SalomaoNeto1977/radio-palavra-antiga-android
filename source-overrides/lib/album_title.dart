/// Removes only the catalogue's administrative CD prefix.
/// A malformed prefix is preserved so that an album never loses its title.
String publicAlbumTitle(String value) {
  final String title = value.trim();
  final RegExpMatch? match = RegExp(
    r'^CD\s*(?:[-–—]\s*)?\([^)]*\)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(title);
  return match == null ? title : match.group(1)!.trim();
}
