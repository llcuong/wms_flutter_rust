import 'package:flutter/material.dart';
import '../services/rfid_scanner.dart';
import 'dart:async';
import 'dart:developer' as developer;

class RfidTestScreen extends StatefulWidget {
  const RfidTestScreen({super.key});

  @override
  State<RfidTestScreen> createState() => _RfidTestScreenState();
}

class _RfidTestScreenState extends State<RfidTestScreen> {
  final RfidScanner _rfidScanner = RfidScanner();
  
  bool _isConnected = false;
  bool _isScanning = false;
  final List<TagData> _scannedTags = [];
  
  StreamSubscription<TagData>? _tagSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    _tagSubscription = _rfidScanner.onTagScanned.listen((tagData) {
      setState(() {
        _scannedTags.insert(0, tagData);
        if (_scannedTags.length > 50) {
          _scannedTags.removeLast();
        }
      });
    });

    _statusSubscription = _rfidScanner.onConnectionStatusChange.listen((status) {
      setState(() {
        _isConnected = (status == ConnectionStatus.connected);
        if (status == ConnectionStatus.scanStopped) {
          _isScanning = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
        developer.log('Initializing RFID...', name: 'RFID_SERVICE');
        await _rfidScanner.init();
        
        developer.log('Connecting to scanner...', name: 'RFID_SERVICE');
        await _rfidScanner.connect();
        
        developer.log('RFID Connected successfully', name: 'RFID_SERVICE');
        
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RFID Connected!')),
        );
    } catch (e, stacktrace) {
        // Log the error with the full stacktrace for better debugging
        developer.log(
        'RFID Connection Failed', 
        name: 'RFID_SERVICE', 
        error: e, 
        stackTrace: stacktrace
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
        );
    }
  }

  Future<void> _startScan() async {
    try {
      await _rfidScanner.startScan(
        mode: ScanMode.continuous,
        uniqueOnly: true,
      );
      setState(() => _isScanning = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan error: $e')),
      );
    }
  }

  Future<void> _stopScan() async {
    try {
      await _rfidScanner.stopScan();
      setState(() => _isScanning = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stop error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RFID Scanner Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Status: ${_isConnected ? "Connected" : "Disconnected"}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: !_isConnected ? _initialize : null,
                      child: const Text('Connect'),
                    ),
                    ElevatedButton(
                      onPressed: _isConnected && !_isScanning ? _startScan : null,
                      child: const Text('Start Scan'),
                    ),
                    ElevatedButton(
                      onPressed: _isScanning ? _stopScan : null,
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _scannedTags.isEmpty
                ? const Center(child: Text('No tags scanned'))
                : ListView.builder(
                    itemCount: _scannedTags.length,
                    itemBuilder: (context, index) {
                      final tag = _scannedTags[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(tag.tagId),
                        subtitle: Text('RSSI: ${tag.rssi} dBm'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}