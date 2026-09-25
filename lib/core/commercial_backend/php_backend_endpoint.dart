Uri resolvePhpBackendEndpoint(Uri baseUri, String path) {
  final cleanPath = path.startsWith('/') ? path.substring(1) : path;
  final apiRelative = cleanPath.startsWith('api/v1/')
      ? cleanPath.substring('api/v1/'.length)
      : cleanPath;

  final normalizedBase = baseUri.replace(
    path: baseUri.path.isEmpty
        ? '/'
        : (baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/'),
  );

  final basePath = normalizedBase.path;
  if (basePath == '/') {
    return normalizedBase.resolve(apiRelative);
  }
  if (basePath.endsWith('/api/v1/')) {
    return normalizedBase.resolve(apiRelative);
  }
  return normalizedBase.resolve('api/v1/$apiRelative');
}
