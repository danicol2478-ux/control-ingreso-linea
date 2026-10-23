// ============================================================
//  INGRESO EN LÍNEA
//  Escanea la cédula y le pregunta a una hoja de Google Sheets
//  (la misma para todos los celulares) si la persona puede pasar.
//    1. Confirmar  -> Pendiente  pasa a  Confirmado
//    2. Ingreso    -> Confirmado pasa a  Ingresó
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    const semilla = Color(0xFF0E7C66);
    return MaterialApp(
      title: 'Ingreso En Línea',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: semilla, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: semilla,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: const Inicio(),
    );
  }
}

// ------------------------------------------------------------
//  Configuración guardada en el celular
// ------------------------------------------------------------
class Config {
  String url, clave, puerta;
  Config(this.url, this.clave, this.puerta);
  bool get lista => url.startsWith('https://') && clave.isNotEmpty;

  static Future<Config> cargar() async {
    final p = await SharedPreferences.getInstance();
    return Config(p.getString('url') ?? '', p.getString('clave') ?? '',
        p.getString('puerta') ?? 'Puerta 1');
  }

  Future<void> guardar() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('url', url.trim());
    await p.setString('clave', clave.trim());
    await p.setString('puerta', puerta.trim());
  }
}

// ------------------------------------------------------------
//  Conversación con Google Sheets
// ------------------------------------------------------------
Future<Map<String, dynamic>> llamarHoja(
    Config c, Map<String, String> datos) async {
  final uri = Uri.parse(c.url.trim()).replace(queryParameters: {
    'clave': c.clave.trim(),
    'puerta': c.puerta.trim(),
    ...datos,
  });
  final resp = await http.get(uri).timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) {
    throw Exception('La hoja respondió con error ${resp.statusCode}');
  }
  try {
    return jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    throw Exception(
        'La dirección no es la de la aplicación web de la hoja. Revise la configuración.');
  }
}

/// "0043840109" -> "43840109"
String soloNumero(String s) =>
    s.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

/// Saca los grupos de números del texto leído en el código.
/// Cédula amarilla (PDF417): trae muchos datos; el número va con
/// ceros a la izquierda (10 dígitos) y después vienen los apellidos.
(List<String>, String) extraerNumeros(String texto) {
  final limpio = texto.trim();
  final grupos = <String>[];
  if (RegExp(r'^\d+$').hasMatch(limpio)) grupos.add(limpio);
  grupos.addAll(RegExp(r'\d{6,}').allMatches(texto).map((m) => m.group(0)!));
  String leido = RegExp(r'^\d+$').hasMatch(limpio) ? soloNumero(limpio) : '';
  if (leido.isEmpty &&
      texto.length >= 58 &&
      RegExp(r'^\d{10}$').hasMatch(texto.substring(48, 58))) {
    leido = soloNumero(texto.substring(48, 58));
  }
  return (grupos.toSet().toList(), leido);
}

// ------------------------------------------------------------
//  Pantalla principal
// ------------------------------------------------------------
enum Tipo { listo, cargando, ok, aviso, error }

class Resultado {
  final Tipo tipo;
  final String titulo, quien, detalle;
  final bool puedeAutorizar;
  const Resultado(this.tipo, this.titulo,
      {this.quien = '', this.detalle = '', this.puedeAutorizar = false});
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  Config? config;
  String modo = 'confirmar';
  Resultado resultado = const Resultado(Tipo.listo, 'Listo para escanear',
      detalle: 'Paso actual: confirmar llegada.');
  Map<String, dynamic> conteo = {};
  List<String> ultimosNumeros = [];
  String ultimoLeido = '';

  final camara = MobileScannerController(
    formats: const [
      BarcodeFormat.pdf417, // cédula amarilla
      BarcodeFormat.qrCode, // cédula digital y QR de prueba
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );
  final manual = TextEditingController();
  bool ocupado = false;
  String ultimoTexto = '';
  DateTime ultimaVez = DateTime(2000);

  @override
  void initState() {
    super.initState();
    Config.cargar().then((c) {
      setState(() => config = c);
      if (c.lista) actualizarConteo();
    });
  }

  @override
  void dispose() {
    camara.dispose();
    manual.dispose();
    super.dispose();
  }

  Future<void> actualizarConteo() async {
    try {
      final r = await llamarHoja(config!, {'accion': 'resumen'});
      if (r['ok'] == true) setState(() => conteo = r);
    } catch (_) {}
  }

  // ---------- Lectura de la cámara ----------
  void alDetectar(BarcodeCapture captura) {
    if (ocupado) return;
    for (final b in captura.barcodes) {
      String? texto = b.rawValue ?? b.displayValue;
      if ((texto == null || texto.isEmpty) && b.rawBytes != null) {
        texto = String.fromCharCodes(b.rawBytes!);
      }
      if (texto == null || texto.isEmpty) continue;
      final ahora = DateTime.now();
      if (texto == ultimoTexto && ahora.difference(ultimaVez).inSeconds < 5) {
        return;
      }
      ultimoTexto = texto;
      ultimaVez = ahora;
      procesar(texto);
      return;
    }
  }

  Future<void> procesar(String texto, {bool autorizar = false}) async {
    if (ocupado) return;
    final (numeros, leido) =
        autorizar ? (ultimosNumeros, ultimoLeido) : extraerNumeros(texto);
    if (numeros.isEmpty) {
      setState(() => resultado = const Resultado(
          Tipo.aviso, 'Código sin número',
          detalle: 'No se encontró un número de cédula en el código.'));
      return;
    }
    ultimosNumeros = numeros;
    ultimoLeido = leido;
    setState(() {
      ocupado = true;
      resultado = const Resultado(Tipo.cargando, 'Consultando la hoja...');
    });
    Resultado r;
    try {
      final resp = await llamarHoja(config!, {
        'accion': autorizar ? 'autorizar' : 'registrar',
        'modo': autorizar ? 'ingreso' : modo,
        'numeros': numeros.join(','),
        'leido': leido,
      });
      if (resp['ok'] != true) {
        r = Resultado(Tipo.error, 'Error de la hoja',
            detalle: '${resp['error'] ?? 'Respuesta desconocida'}');
      } else {
        conteo = resp;
        final t = resp['tipo'];
        r = Resultado(
          t == 'ok' ? Tipo.ok : t == 'aviso' ? Tipo.aviso : Tipo.error,
          '${resp['titulo'] ?? ''}',
          quien: '${resp['quien'] ?? ''}',
          detalle: '${resp['detalle'] ?? ''}',
          puedeAutorizar: resp['puedeAutorizar'] == true,
        );
      }
    } on TimeoutException {
      r = const Resultado(Tipo.error, 'Sin respuesta',
          detalle: 'La hoja no respondió. Revise el internet e intente de nuevo.');
    } catch (e) {
      r = Resultado(Tipo.error, 'Sin conexión',
          detalle: e.toString().replaceFirst('Exception: ', ''));
    }
    setState(() {
      resultado = r;
      ocupado = false;
    });
    avisar(r.tipo);
  }

  void avisar(Tipo t) {
    if (t == Tipo.ok) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 180),
          () => HapticFeedback.heavyImpact());
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> abrirConfig() async {
    final c = await Navigator.push<Config>(context,
        MaterialPageRoute(builder: (_) => PantallaConfig(config: config!)));
    if (c != null) {
      setState(() => config = c);
      actualizarConteo();
    }
  }

  // ---------- Pantallas ----------
  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!c.lista) return PantallaConfig(config: c, primeraVez: true,
        alGuardar: (n) { setState(() => config = n); actualizarConteo(); });

    return Scaffold(
      appBar: AppBar(
        title: Text('Ingreso · ${c.puerta}'),
        actions: [
          IconButton(
              tooltip: 'Actualizar contadores',
              icon: const Icon(Icons.refresh),
              onPressed: actualizarConteo),
          IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings_outlined),
              onPressed: abrirConfig),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'confirmar',
                  icon: Icon(Icons.how_to_reg),
                  label: Text('1. Confirmar')),
              ButtonSegment(
                  value: 'ingreso',
                  icon: Icon(Icons.door_front_door_outlined),
                  label: Text('2. Ingreso')),
            ],
            selected: {modo},
            onSelectionChanged: (s) => setState(() {
              modo = s.first;
              resultado = Resultado(Tipo.listo, 'Listo para escanear',
                  detalle: modo == 'confirmar'
                      ? 'Paso actual: confirmar llegada.'
                      : 'Paso actual: dejar ingresar.');
            }),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: camara, onDetect: alDetectar),
                  Center(
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Linterna',
                      icon: const Icon(Icons.flashlight_on_outlined),
                      onPressed: () => camara.toggleTorch(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ponga el código de barras de atrás de la cédula acostado dentro del recuadro, con buena luz y el celular quieto.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          tarjetaResultado(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: manual,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Escribir cédula a mano',
                      border: OutlineInputBorder()),
                  onSubmitted: (_) => buscarManual(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: ocupado ? null : buscarManual,
                  child: const Text('Buscar')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              contador('Total', conteo['total']),
              contador('Pendientes', conteo['pendientes']),
              contador('Confirmados', conteo['confirmados']),
              contador('Ingresaron', conteo['ingresaron']),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Los contadores son de TODOS los celulares conectados a la misma hoja.',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void buscarManual() {
    final v = manual.text.trim();
    if (v.isEmpty) return;
    procesar(v);
    manual.clear();
  }

  Widget contador(String t, dynamic n) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(n == null ? '–' : '$n',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(t, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );

  Widget tarjetaResultado() {
    final r = resultado;
    final esquema = Theme.of(context).colorScheme;
    final color = switch (r.tipo) {
      Tipo.ok => const Color(0xFF1E8E4E),
      Tipo.aviso => const Color(0xFFC98A00),
      Tipo.error => const Color(0xFFC62828),
      _ => esquema.outline,
    };
    final neutro = r.tipo == Tipo.listo || r.tipo == Tipo.cargando;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: neutro
            ? esquema.surfaceContainerHighest
            : color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (r.tipo == Tipo.cargando) ...[
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(r.titulo,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: neutro ? null : color)),
            ),
          ]),
          if (r.quien.isNotEmpty)
            Text(r.quien,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (r.detalle.isNotEmpty) Text(r.detalle),
          if (r.puedeAutorizar) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: ocupado ? null : () => procesar('', autorizar: true),
              child: const Text('Dejar ingresar de todas formas'),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  Pantalla de configuración: dirección de la hoja, clave y puerta
// ------------------------------------------------------------
class PantallaConfig extends StatefulWidget {
  final Config config;
  final bool primeraVez;
  final void Function(Config)? alGuardar;
  const PantallaConfig(
      {super.key,
      required this.config,
      this.primeraVez = false,
      this.alGuardar});
  @override
  State<PantallaConfig> createState() => _PantallaConfigState();
}

class _PantallaConfigState extends State<PantallaConfig> {
  late final url = TextEditingController(text: widget.config.url);
  late final clave = TextEditingController(text: widget.config.clave);
  late final puerta = TextEditingController(text: widget.config.puerta);
  String mensaje = '';
  bool probando = false;

  Config get actual => Config(url.text.trim(), clave.text.trim(),
      puerta.text.trim().isEmpty ? 'Puerta 1' : puerta.text.trim());

  Future<void> probar() async {
    setState(() {
      probando = true;
      mensaje = 'Probando...';
    });
    try {
      final r = await llamarHoja(actual, {'accion': 'resumen'});
      mensaje = r['ok'] == true
          ? '✅ Conectado. La hoja tiene ${r['total']} invitados.'
          : '❌ ${r['error']}';
    } catch (e) {
      mensaje = '❌ ${e.toString().replaceFirst('Exception: ', '')}';
    }
    setState(() => probando = false);
  }

  Future<void> guardar() async {
    final c = actual;
    if (!c.lista) {
      setState(() => mensaje =
          '❌ Pegue la dirección completa (empieza con https://) y escriba la clave.');
      return;
    }
    await c.guardar();
    if (!mounted) return;
    if (widget.alGuardar != null) {
      widget.alGuardar!(c);
    } else {
      Navigator.pop(context, c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.primeraVez ? 'Conectar con la hoja' : 'Configuración'),
          automaticallyImplyLeading: !widget.primeraVez),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'Pegue aquí la dirección de la aplicación web de Google Sheets (la que termina en /exec).'),
          const SizedBox(height: 10),
          TextField(
            controller: url,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'Dirección de la hoja',
                hintText: 'https://script.google.com/macros/s/.../exec',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: clave,
            decoration: const InputDecoration(
                labelText: 'Clave (la misma del programa de la hoja)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: puerta,
            decoration: const InputDecoration(
                labelText: 'Nombre de esta puerta o celular',
                hintText: 'Ejemplo: Puerta principal',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: probando ? null : probar,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Probar conexión')),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: guardar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar')),
          const SizedBox(height: 12),
          Text(mensaje, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
