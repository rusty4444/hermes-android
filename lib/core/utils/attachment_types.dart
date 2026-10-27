/// Shared file-kind and preview candidate predicates. A container/extension is
/// not a guarantee that the device can decode its samples.
bool attachmentIsImage(String extension) => const {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tif',
  'tiff',
  'avif',
  'heic',
}.contains(extension.toLowerCase());

/// SVG is an image *asset*, but only inert source text may be previewed.
bool attachmentIsImageAsset(String extension) =>
    attachmentIsImage(extension) || extension.toLowerCase() == 'svg';

bool attachmentIsAudio(String extension) => const {
  'mp3',
  'm2a',
  'wav',
  'ogg',
  'opus',
  'm4a',
  'flac',
}.contains(extension.toLowerCase());

/// Local progressive containers with an Android Media3 extractor. ASF/WMV have
/// no extractor; FLV does, and F4V is ISO BMFF/MP4 (not the FLV container).
/// Playlists/manifests and remote paths are deliberately not accepted.
bool attachmentIsVideo(String extension) => const {
  'mp4',
  'm4v',
  'mov',
  'webm',
  'mkv',
  'avi',
  '3gp',
  '3gpp',
  '3g2',
  'mpeg',
  'mpg',
  'mpe',
  'm2v',
  'mts',
  'm2ts',
  'ogv',
  'flv',
  'f4v',
}.contains(extension.toLowerCase());
