/// Route constants used throughout the application
///
/// Define all application routes here to maintain consistency and avoid hardcoded paths
abstract final class Routes {
  static const root = '/';
  static const login = '/login';
  static const demoHome = '/demoHome';
  static const demoUsers = '/demoUsers';
  static const demoPosts = '/demoPosts';

  /// Constructs a post detail route with the specific post ID
  static String postDemoWithId(int id) => '$demoPosts/$id';
  static const demoSettings = '/demoSettings';
  static const demoCategories = '/demoCategories';
  static const transcriptionSummary = '/transcriptionSummary';
  static const recordAudio = '/recordAudio';
  static const uploadFile = '/uploadFile';
  static const youtubeVideo = '/youtubeVideo';
  static const audioProcessing = '/audioProcessing';
  static const settings = '/settings';
}
