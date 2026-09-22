import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'models/venta.dart';
import 'screens/login_screen.dart';
import 'services/ventas_service.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FashionStoreApp());

  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) async {
    // Ej.: fashionstore://pago/confirmacion?session_id=cs_test_xxx
    final sessionId = uri.queryParameters['session_id'];
    if (sessionId == null || sessionId.isEmpty) return;
    try {
      final res = await VentasService.confirmarSesion(sessionId);
      _navigatorKey.currentContext?.mounted ?? false;
      if (_navigatorKey.currentContext == null) return;
      ScaffoldMessenger.of(_navigatorKey.currentContext!).showSnackBar(
        SnackBar(
          content: Text(
            'Compra confirmada · Pedido #${res.idPedido} · '
            '${res.total.toStringAsFixed(2)} US$',
          ),
        ),
      );
    } catch (_) {
      if (_navigatorKey.currentContext == null) return;
      ScaffoldMessenger.of(_navigatorKey.currentContext!).showSnackBar(
        const SnackBar(content: Text('No se pudo confirmar la compra')),
      );
    }
  });
}

class FashionStoreApp extends StatelessWidget {
  const FashionStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FashionStore',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C2E91),
          brightness: Brightness.light,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}