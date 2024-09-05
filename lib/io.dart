import 'dart:io';
import 'dart:typed_data';

import 'package:minio_flutter/src/minio.dart';
import 'package:minio_flutter/src/minio_errors.dart';
import 'package:minio_flutter/src/minio_helpers.dart';
import 'package:path/path.dart' show dirname;

extension MinioX on Minio {
  // Uploads the object using contents from a file
  Future<String> fPutObject(
    String bucket,
    String object,
    String filePath, [
    Map<String, String>? metadata,
  ]) async {
    MinioInvalidBucketNameError.check(bucket);
    MinioInvalidObjectNameError.check(object);

    var meta = metadata ?? {};
    meta = insertContentType(meta, filePath);
    meta = prependXAMZMeta(meta);

    final file = File(filePath);
    final stat = file.statSync();
    if (stat.size > maxObjectSize) {
      throw MinioError(
        '$filePath size : ${stat.size}, max allowed size : 5TB',
      );
    }

    return putObject(
      bucket,
      object,
      file.openRead().cast<Uint8List>(),
      size: stat.size,
      metadata: meta,
    );
  }

  /// Downloads and saves the object as a file in the local filesystem.
  Future<void> fGetObject(
    String bucket,
    String object,
    String filePath,
  ) async {
    MinioInvalidBucketNameError.check(bucket);
    MinioInvalidObjectNameError.check(object);

    final stat = await statObject(bucket, object);
    final dir = dirname(filePath);
    await Directory(dir).create(recursive: true);

    final partFileName = '$filePath.${stat.etag}.part.minio';
    final partFile = File(partFileName);
    IOSink partFileStream;
    var offset = 0;

    Future<void> rename() async {
      await partFile.rename(filePath);
    }

    if (partFile.existsSync()) {
      final localStat = partFile.statSync();
      if (stat.size == localStat.size) return rename();
      offset = localStat.size;
      partFileStream = partFile.openWrite(mode: FileMode.append);
    } else {
      partFileStream = partFile.openWrite();
    }

    final dataStream = await getPartialObject(bucket, object, offset);
    await dataStream.pipe(partFileStream);

    final localStat = partFile.statSync();
    if (localStat.size != stat.size) {
      throw MinioError('Size mismatch between downloaded file and the object');
    }

    return rename();
  }
}
