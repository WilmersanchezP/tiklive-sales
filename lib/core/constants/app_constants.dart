import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract class AppConstants {
  // ── OpenAI ────────────────────────────────────────────────────────────────
  static String get openAiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  static String get whisperModel => dotenv.env['OPENAI_WHISPER_MODEL'] ?? 'whisper-1';
  static String get chatModel => dotenv.env['OPENAI_CHAT_MODEL'] ?? 'gpt-4o-mini';
  static const String openAiBaseUrl = 'https://api.openai.com/v1';

  // ── Supabase ──────────────────────────────────────────────────────────────
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // ── TikTok bridge ─────────────────────────────────────────────────────────
  static String get tiktokWsUrl =>
      dotenv.env['TIKTOK_WS_URL'] ?? 'wss://localhost:8080/live';

  // ── Business rules ────────────────────────────────────────────────────────
  static int get lowStockThreshold =>
      int.tryParse(dotenv.env['LOW_STOCK_THRESHOLD'] ?? '5') ?? 5;

  // ── Table names ───────────────────────────────────────────────────────────
  static const String tableProfiles = 'profiles';
  static const String tableProducts = 'products';
  static const String tableProductVariants = 'product_variants';
  static const String tableInventory = 'inventory';
  static const String tableOrders = 'orders';
  static const String tableOrderItems = 'order_items';
  static const String tableCustomers = 'customers';
  static const String tableLiveSessions = 'live_sessions';
  static const String tableVoiceTranscripts = 'voice_transcripts';

  // ── Storage buckets ───────────────────────────────────────────────────────
  static const String bucketProducts = 'product-images';
  static const String bucketAudio = 'voice-recordings';

  // ── Roles ─────────────────────────────────────────────────────────────────
  static const String roleAdmin = 'admin';
  static const String roleSeller = 'seller';
  static const String roleWarehouse = 'warehouse';
  static const String roleSupervisor = 'supervisor';
}

abstract class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String voiceSales = '/voice-sales';
  static const String inventory = '/inventory';
  static const String orders = '/orders';
  static const String reports = '/reports';
  static const String tiktokLive = '/tiktok-live';
  static const String settings = '/settings';
  static const String productDetail = '/inventory/:productId';
  static const String orderDetail = '/orders/:orderId';
}
