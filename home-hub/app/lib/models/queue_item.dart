class QueueItem {
  final String videoId;
  final String title;
  final String url;

  QueueItem({
    required this.videoId,
    required this.title,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title':   title,
    'url':     url,
  };

  factory QueueItem.fromUrl(String url, {String title = ''}) {
    final videoId = _extractId(url);
    return QueueItem(
      videoId: videoId,
      title:   title.isNotEmpty ? title : videoId,
      url:     url,
    );
  }

  static String _extractId(String url) {
    if (url.contains('/shorts/')) {
      return url.split('/shorts/')[1].split('?')[0];
    } else if (url.contains('youtu.be/')) {
      return url.split('youtu.be/')[1].split('?')[0];
    } else if (url.contains('v=')) {
      return url.split('v=')[1].split('&')[0];
    }
    return url;
  }
}
