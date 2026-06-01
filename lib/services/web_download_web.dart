// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> triggerWebDownload(
  Uint8List bytes,
  String fileName,
  String mimeType,
) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  // Append to body so all browsers (incl. Safari) recognise the click as valid.
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();

  // Give the browser time to start the download before releasing the blob URL.
  Future.delayed(const Duration(seconds: 2), () => html.Url.revokeObjectUrl(url));
}
