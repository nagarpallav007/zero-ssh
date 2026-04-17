import 'dart:io';

void main() async {
  try {
    final socket = await Socket.connect('172.105.60.92', 22);
    print('Connected to: ${socket.remoteAddress.address}:${socket.remotePort}');
    socket.destroy();
  } catch (e) {
    print('Connection failed: $e');
  }
}
