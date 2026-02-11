import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BinSelectionModal extends StatefulWidget {
  const BinSelectionModal({super.key});

  @override
  State<BinSelectionModal> createState() => _BinSelectionModalState();
}

class _BinSelectionModalState extends State<BinSelectionModal> {
  late Future<List<BinData>> _binsFuture;
  List<BinData> _allBins = [];
  List<BinData> _filteredBins = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _binsFuture = _loadBins();
    _searchController.addListener(_filterBins);
  }

  Future<List<BinData>> _loadBins() async {
    try {
      final bins = await ApiService.getBins();
      setState(() {
        _allBins = bins;
        _filteredBins = bins;
      });
      return bins;
    } catch (e) {
      debugPrint("Error loading bins: $e");
      return [];
    }
  }

  void _filterBins() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredBins = _allBins.where((bin) {
        return bin.binId.toLowerCase().contains(query) ||
            (bin.binName?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Bin',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search bin...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<BinData>>(
              future: _binsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (_allBins.isEmpty) {
                  return const Center(child: Text('No bins found'));
                }

                if (_filteredBins.isEmpty) {
                  return const Center(child: Text('No matching bins'));
                }

                return ListView.builder(
                  itemCount: _filteredBins.length,
                  itemBuilder: (context, index) {
                    final bin = _filteredBins[index];
                    return ListTile(
                      title: Text(bin.binId),
                      subtitle: bin.binName != null ? Text(bin.binName!) : null,
                      onTap: () {
                        Navigator.pop(context, bin);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
