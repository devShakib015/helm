import 'package:flutter/widgets.dart';
import '../models/storage_category.dart';
import '../models/cleanable_group.dart';

/// Helm's "deep dark + glass" palette. Backgrounds are near-black with a cool
/// tint; surfaces are translucent white so the window vibrancy reads through.
class AppColors {
  AppColors._();

  // ---- Window / backgrounds ----------------------------------------------
  static const Color bgTop = Color(0xFF0E121B);
  static const Color bgBottom = Color(0xFF080A10);
  static const Color scaffold = Color(0xFF0B0E15);

  // ---- Glass surfaces -----------------------------------------------------
  static const Color glass = Color(0x0DFFFFFF); // 5% white
  static const Color glassStrong = Color(0x14FFFFFF); // 8% white
  static const Color glassHover = Color(0x1FFFFFFF); // 12% white
  static const Color stroke = Color(0x14FFFFFF); // 8% white border
  static const Color strokeStrong = Color(0x26FFFFFF); // 15% white border
  static const Color sidebarTint = Color(0x08FFFFFF);

  // ---- Accent -------------------------------------------------------------
  static const Color accent = Color(0xFF4F9DFF);
  static const Color accentAlt = Color(0xFF7B61FF);
  static const Color accentSoft = Color(0x294F9DFF);
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5AC8FA), Color(0xFF5E5CE6)],
  );

  // ---- Text ---------------------------------------------------------------
  static const Color textPrimary = Color(0xFFF3F6FC);
  static const Color textSecondary = Color(0xFF9AA4B6);
  static const Color textTertiary = Color(0xFF626C7E);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // ---- Semantic -----------------------------------------------------------
  static const Color free = Color(0xFF34D399); // healthy / free space
  static const Color purgeable = Color(0xFF8B95A7); // reclaimable
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB5C5C);
  static const Color dangerSoft = Color(0x29FB5C5C);

  // ---- Category colours ---------------------------------------------------
  static const Map<CategoryKind, Color> _category = {
    CategoryKind.applications: Color(0xFF5AC8FA),
    CategoryKind.documents: Color(0xFF5E9EFF),
    CategoryKind.desktop: Color(0xFFA78BFA),
    CategoryKind.downloads: Color(0xFF38BDF8),
    CategoryKind.photos: Color(0xFFFB7185),
    CategoryKind.music: Color(0xFFF472B6),
    CategoryKind.movies: Color(0xFFFB923C),
    CategoryKind.mail: Color(0xFF34D399),
    CategoryKind.messages: Color(0xFF22D3EE),
    CategoryKind.developer: Color(0xFFC084FC),
    CategoryKind.caches: Color(0xFFFBBF24),
    CategoryKind.systemData: Color(0xFF94A3B8),
    CategoryKind.trash: Color(0xFFF87171),
    CategoryKind.other: Color(0xFF64748B),
  };

  static Color category(CategoryKind kind) =>
      _category[kind] ?? const Color(0xFF64748B);

  // ---- Cleanup colours ----------------------------------------------------
  static const Map<CleanupKind, Color> _cleanup = {
    CleanupKind.userCache: Color(0xFFFBBF24),
    CleanupKind.systemCache: Color(0xFFF59E0B),
    CleanupKind.userLogs: Color(0xFF60A5FA),
    CleanupKind.systemLogs: Color(0xFF38BDF8),
    CleanupKind.trash: Color(0xFFF87171),
    CleanupKind.downloads: Color(0xFF38BDF8),
    CleanupKind.savedAppState: Color(0xFFA78BFA),
    CleanupKind.developerJunk: Color(0xFFC084FC),
    CleanupKind.browserCache: Color(0xFF34D399),
    CleanupKind.mailDownloads: Color(0xFF22D3EE),
    CleanupKind.appLeftovers: Color(0xFFFB7185),
    CleanupKind.brokenLoginItems: Color(0xFFFB923C),
    CleanupKind.languageFiles: Color(0xFF818CF8),
    CleanupKind.oldUpdates: Color(0xFF94A3B8),
  };

  static Color cleanup(CleanupKind kind) =>
      _cleanup[kind] ?? const Color(0xFF64748B);
}
