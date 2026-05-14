import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() {
  runApp(const LaberintoApp());
}

class LaberintoApp extends StatelessWidget {
  const LaberintoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Laberinto',
      theme: ThemeData.dark(),
      home: const ControlPantalla(),
    );
  }
}

class ControlPantalla extends StatefulWidget {
  const ControlPantalla({super.key});

  @override
  State<ControlPantalla> createState() => _ControlPantallaState();
}

class _ControlPantallaState extends State<ControlPantalla> {
  BluetoothState _estadoBluetooth = BluetoothState.UNKNOWN;
  BluetoothConnection? _conexion;
  List<BluetoothDevice> _dispositivos = [];
  BluetoothDevice? _dispositivoSeleccionado;
  
  bool _conectado = false;
  String _bufferRX = "";

  // Variables de Telemetría
  int robotX = 6;
  int robotY = 6;
  int orientacion = 1; // 1:N, 2:S, 3:E, 4:O
  List<int> matrizMapa = List.filled(144, 0);

  final TextEditingController _controladorTrama = TextEditingController();

  @override
  void initState() {
    super.initState();
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() => _estadoBluetooth = state);
    });
    _obtenerDispositivosEmparejados();
  }

  void _obtenerDispositivosEmparejados() async {
    List<BluetoothDevice> dispositivos = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() => _dispositivos = dispositivos);
  }

  void _conectarDispositivo() async {
    if (_dispositivoSeleccionado == null) return;
    
    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(_dispositivoSeleccionado!.address);
      setState(() {
        _conexion = connection;
        _conectado = true;
      });

      _conexion!.input!.listen(_procesarDatosEntrantes).onDone(() {
        setState(() => _conectado = false);
      });
    } catch (e) {
      debugPrint('Error de conexión: $e');
    }
  }

  void _desconectar() {
    _conexion?.close();
    setState(() => _conectado = false);
  }

  void _procesarDatosEntrantes(Uint8List data) {
    _bufferRX += ascii.decode(data);

    if (_bufferRX.contains('\n')) {
      List<String> lineas = _bufferRX.split('\n');
      
      for (int i = 0; i < lineas.length - 1; i++) {
        String linea = lineas[i].trim();
        
        if (linea.startsWith("MAPA:")) {
          _parsearProtocoloMapa(linea);
        }
      }
      _bufferRX = lineas.last; 
    }
  }

  void _parsearProtocoloMapa(String trama) {
    try {
      String payload = trama.substring(5);
      List<String> segmentos = payload.split(':');
      
      if (segmentos.length == 2) {
        List<String> telemetria = segmentos[0].split(',');
        List<String> celdas = segmentos[1].split(',');

        if (celdas.length == 144) {
          setState(() {
            robotX = int.parse(telemetria[0]);
            robotY = int.parse(telemetria[1]);
            orientacion = int.parse(telemetria[2]);
            
            for (int i = 0; i < 144; i++) {
              matrizMapa[i] = int.parse(celdas[i]);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error de decodificación de matriz: $e");
    }
  }

  void _enviarComando(String comando) {
    if (_conectado && _conexion != null) {
      String tramaTransmision = comando;
      if (!comando.endsWith("#")) tramaTransmision += "#";
      
      _conexion!.output.add(ascii.encode(tramaTransmision));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visor Topológico LNR')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<BluetoothDevice>(
                    isExpanded: true,
                    value: _dispositivoSeleccionado,
                    hint: const Text('Seleccionar ESP32'),
                    items: _dispositivos.map((device) {
                      return DropdownMenuItem(
                        value: device,
                        child: Text(device.name ?? device.address),
                      );
                    }).toList(),
                    onChanged: (device) => setState(() => _dispositivoSeleccionado = device),
                  ),
                ),
                ElevatedButton(
                  onPressed: _conectado ? _desconectar : _conectarDispositivo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _conectado ? Colors.red : Colors.green,
                  ),
                  child: Text(_conectado ? 'Desconectar' : 'Conectar'),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  margin: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
                  child: CustomPaint(
                    painter: RenderizadorLaberinto(
                      mapa: matrizMapa,
                      rX: robotX,
                      rY: robotY,
                      dir: orientacion,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _botonMovimiento("GIRAR_IZQ", Icons.turn_left),
                _botonMovimiento("AVANZAR", Icons.arrow_upward),
                _botonMovimiento("RETROCEDER", Icons.arrow_downward),
                _botonMovimiento("GIRAR_DER", Icons.turn_right),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controladorTrama,
                    decoration: const InputDecoration(
                      hintText: 'Ej: 100,50,100#',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _enviarComando(_controladorTrama.text),
                  child: const Text('TX Trama'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _enviarComando("0,50,0#"),
                  child: const Text('Solicitar Mapa'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonMovimiento(String comando, IconData icono) {
    return IconButton(
      iconSize: 36,
      icon: Icon(icono),
      onPressed: () => _enviarComando(comando),
    );
  }
}

class RenderizadorLaberinto extends CustomPainter {
  final List<int> mapa;
  final int rX;
  final int rY;
  final int dir;

  RenderizadorLaberinto({
    required this.mapa,
    required this.rX,
    required this.rY,
    required this.dir,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double anchoCelda = size.width / 12;
    final double altoCelda = size.height / 12;

    final Paint paintPared = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square;

    final Paint paintVisitado = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.fill;

    final Paint paintRobot = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    for (int y = 0; y < 12; y++) {
      for (int x = 0; x < 12; x++) {
        int index = (y * 12) + x;
        int valorCelda = mapa[index];

        double px = x * anchoCelda;
        double py = y * altoCelda;

        if ((valorCelda & 16) != 0) {
          canvas.drawRect(Rect.fromLTWH(px, py, anchoCelda, altoCelda), paintVisitado);
        }

        if (x == rX && y == rY) {
          _dibujarRobot(canvas, px, py, anchoCelda, altoCelda, paintRobot);
        }

        if ((valorCelda & 1) != 0) {
          canvas.drawLine(Offset(px, py), Offset(px + anchoCelda, py), paintPared);
        }
        if ((valorCelda & 2) != 0) {
          canvas.drawLine(Offset(px, py + altoCelda), Offset(px + anchoCelda, py + altoCelda), paintPared);
        }
        if ((valorCelda & 4) != 0) {
          canvas.drawLine(Offset(px + anchoCelda, py), Offset(px + anchoCelda, py + altoCelda), paintPared);
        }
        if ((valorCelda & 8) != 0) {
          canvas.drawLine(Offset(px, py), Offset(px, py + altoCelda), paintPared);
        }
      }
    }
  }

  void _dibujarRobot(Canvas canvas, double px, double py, double w, double h, Paint paint) {
    double cx = px + (w / 2);
    double cy = py + (h / 2);
    double radio = w * 0.3;

    canvas.drawCircle(Offset(cx, cy), radio, paint);

    final Paint paintVector = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;

    Offset vectorEnd = Offset(cx, cy);
    if (dir == 1) vectorEnd = Offset(cx, cy - radio); 
    if (dir == 2) vectorEnd = Offset(cx, cy + radio); 
    if (dir == 3) vectorEnd = Offset(cx + radio, cy); 
    if (dir == 4) vectorEnd = Offset(cx - radio, cy); 

    canvas.drawLine(Offset(cx, cy), vectorEnd, paintVector);
  }

  @override
  bool shouldRepaint(covariant RenderizadorLaberinto oldDelegate) {
    return true; 
  }
}
