import 'package:flutter/material.dart';

import '../../../core/models/cleanable_group.dart';
import '../../../core/models/storage_category.dart';
import '../../../core/theme/app_colors.dart';

/// UI metadata (label + icon) for categories and cleanup groups. Kept out of
/// the pure-Dart models so those stay isolate-safe.

const Map<CategoryKind, String> _categoryLabels = {
  CategoryKind.applications: 'Applications',
  CategoryKind.documents: 'Documents',
  CategoryKind.desktop: 'Desktop',
  CategoryKind.downloads: 'Downloads',
  CategoryKind.photos: 'Photos',
  CategoryKind.music: 'Music',
  CategoryKind.movies: 'Movies',
  CategoryKind.mail: 'Mail',
  CategoryKind.messages: 'Messages',
  CategoryKind.developer: 'Developer',
  CategoryKind.caches: 'Caches',
  CategoryKind.systemData: 'System Data',
  CategoryKind.trash: 'Trash',
  CategoryKind.other: 'Other',
};

const Map<CategoryKind, IconData> _categoryIcons = {
  CategoryKind.applications: Icons.apps_rounded,
  CategoryKind.documents: Icons.description_rounded,
  CategoryKind.desktop: Icons.desktop_mac_rounded,
  CategoryKind.downloads: Icons.download_rounded,
  CategoryKind.photos: Icons.photo_library_rounded,
  CategoryKind.music: Icons.music_note_rounded,
  CategoryKind.movies: Icons.movie_rounded,
  CategoryKind.mail: Icons.mail_rounded,
  CategoryKind.messages: Icons.chat_bubble_rounded,
  CategoryKind.developer: Icons.code_rounded,
  CategoryKind.caches: Icons.cached_rounded,
  CategoryKind.systemData: Icons.dns_rounded,
  CategoryKind.trash: Icons.delete_rounded,
  CategoryKind.other: Icons.more_horiz_rounded,
};

String categoryLabel(CategoryKind k) => _categoryLabels[k] ?? 'Other';
IconData categoryIcon(CategoryKind k) =>
    _categoryIcons[k] ?? Icons.folder_rounded;
Color categoryColor(CategoryKind k) => AppColors.category(k);

const Map<CleanupKind, IconData> _cleanupIcons = {
  CleanupKind.userCache: Icons.cached_rounded,
  CleanupKind.systemCache: Icons.cached_rounded,
  CleanupKind.userLogs: Icons.article_rounded,
  CleanupKind.systemLogs: Icons.article_rounded,
  CleanupKind.trash: Icons.delete_rounded,
  CleanupKind.downloads: Icons.download_rounded,
  CleanupKind.savedAppState: Icons.save_rounded,
  CleanupKind.developerJunk: Icons.code_rounded,
  CleanupKind.browserCache: Icons.public_rounded,
  CleanupKind.mailDownloads: Icons.attach_file_rounded,
  CleanupKind.appLeftovers: Icons.layers_clear_rounded,
  CleanupKind.brokenLoginItems: Icons.link_off_rounded,
  CleanupKind.languageFiles: Icons.translate_rounded,
  CleanupKind.oldUpdates: Icons.system_update_alt_rounded,
};

IconData cleanupIcon(CleanupKind k) =>
    _cleanupIcons[k] ?? Icons.cleaning_services_rounded;
Color cleanupColor(CleanupKind k) => AppColors.cleanup(k);

/// Icon + colour for a file based on its extension. Used by the explorer, large
/// files, and duplicates lists.
({IconData icon, Color color}) fileGlyph(String name, {bool isDir = false}) {
  if (isDir) {
    return (icon: Icons.folder_rounded, color: AppColors.accent);
  }
  final dot = name.lastIndexOf('.');
  final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();

  if (name.endsWith('.app')) {
    return (icon: Icons.apps_rounded, color: const Color(0xFF5AC8FA));
  }
  if (_video.contains(ext)) {
    return (icon: Icons.movie_rounded, color: const Color(0xFFFB923C));
  }
  if (_image.contains(ext)) {
    return (icon: Icons.image_rounded, color: const Color(0xFFFB7185));
  }
  if (_audio.contains(ext)) {
    return (icon: Icons.music_note_rounded, color: const Color(0xFFF472B6));
  }
  if (_archive.contains(ext)) {
    return (icon: Icons.folder_zip_rounded, color: const Color(0xFFFBBF24));
  }
  if (_disk.contains(ext)) {
    return (icon: Icons.album_rounded, color: const Color(0xFF94A3B8));
  }
  if (_doc.contains(ext)) {
    return (icon: Icons.description_rounded, color: const Color(0xFF5E9EFF));
  }
  if (_code.contains(ext)) {
    return (icon: Icons.code_rounded, color: const Color(0xFFC084FC));
  }
  return (icon: Icons.insert_drive_file_rounded, color: AppColors.textTertiary);
}

const _video = {'mov', 'mp4', 'mkv', 'avi', 'm4v', 'webm', 'flv', 'wmv', 'mpg'};
const _image = {'jpg', 'jpeg', 'png', 'gif', 'heic', 'heif', 'tiff', 'bmp', 'raw', 'cr2', 'webp', 'svg'};
const _audio = {'mp3', 'wav', 'aac', 'flac', 'm4a', 'aiff', 'ogg'};
const _archive = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz'};
const _disk = {'dmg', 'iso', 'pkg', 'img', 'sparseimage', 'sparsebundle'};
const _doc = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'pages', 'numbers', 'key', 'csv', 'md'};
const _code = {'dart', 'js', 'ts', 'py', 'swift', 'java', 'kt', 'c', 'cpp', 'h', 'rb', 'go', 'rs', 'php', 'html', 'css', 'json', 'xml', 'yaml', 'sh'};
