import 'src/bootstrap/bootstrap_stub.dart'
    if (dart.library.io) 'src/bootstrap/bootstrap_io.dart'
    if (dart.library.js_interop) 'src/bootstrap/bootstrap_web.dart';

Future<void> main() => bootstrap();
