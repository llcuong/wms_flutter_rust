import 'package:flutter/material.dart';
import '../models/scanned_item.dart';
import '../services/api_service.dart';

class BinSelectionModal extends StatefulWidget {
  final AreaData? lastSelected;
  final int incomingQty;
  final List<Rack> rackData;
  final Map<String, ScannedItem>? currentScannedItems;

  const BinSelectionModal({
    super.key,
    this.lastSelected,
    required this.incomingQty,
    required this.rackData,
    this.currentScannedItems,
  });

  @override
  State<BinSelectionModal> createState() => _BinSelectionModalState();
}

class _BinSelectionModalState extends State<BinSelectionModal> {
  late Future<List<AreaData>> _areasFuture;

  List<AreaData> _allAreas = [];
  List<AreaData> _filteredAreas = [];

  final TextEditingController _searchController = TextEditingController();

  int _getTempUsedQty(String areaName) {
    int total = 0;

    // Count items already in racks
    for (final rack in widget.rackData) {
      if (rack.bin == areaName) {
        total += rack.items.length;
      }
    }

    // Count items in current scanned items if their bin matches
    if (widget.currentScannedItems != null) {
      for (final item in widget.currentScannedItems!.values) {
        if (item.bin == areaName) {
          total += 1; // Each scanned item counts as 1
        }
      }
    }

    return total;
  }

  @override
  void initState() {
    super.initState();
    _areasFuture = _loadAreas();
    _searchController.addListener(_filterAreas);
  }

  Future<List<AreaData>> _loadAreas() async {
    try {
      final areas = await ApiService.getAreas();

      // Move last selected to top
      if (widget.lastSelected != null) {
        areas.sort((a, b) {
          if (a.id == widget.lastSelected!.id) return -1;
          if (b.id == widget.lastSelected!.id) return 1;
          return a.id.compareTo(b.id);
        });
      }

      setState(() {
        _allAreas = areas;
        _filteredAreas = areas;
      });

      return areas;
    } catch (e) {
      debugPrint("Error loading areas: $e");
      return [];
    }
  }

  void _filterAreas() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredAreas = _allAreas.where((area) {
        return area.id.toLowerCase().contains(query) ||
            area.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  double _calculateCapacity(AreaData area) {
    final bigger = area.l > area.w ? area.l : area.w;
    return (1944 / 270) * bigger;
  }

  double _calculateUsagePercent(AreaData area) {
    final capacity = _calculateCapacity(area);
    final apiUsed = area.batchNo ?? 0;
    final tempUsed = _getTempUsedQty(area.name);
    final totalUsed = apiUsed + tempUsed;

    if (capacity == 0) return 0;
    return (totalUsed / capacity).clamp(0.0, 1.0);
  }

  double _getRemainingCapacity(AreaData area) {
    final capacity = _calculateCapacity(area);
    final apiUsed = area.batchNo ?? 0;
    final tempUsed = _getTempUsedQty(area.name);

    return capacity - apiUsed - tempUsed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          /// Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Area',
                style: TextStyle(
                  fontSize: 22,
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

          /// Search
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search area...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 20),

          /// List
          Expanded(
            child: FutureBuilder<List<AreaData>>(
              future: _areasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_filteredAreas.isEmpty) {
                  return const Center(child: Text('No areas found'));
                }

                return ListView.separated(
                  itemCount: _filteredAreas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final area = _filteredAreas[index];
                    final capacity = _calculateCapacity(area);
                    final isLast = widget.lastSelected?.id == area.id;

                    final remaining = _getRemainingCapacity(area);
                    final canFit = widget.incomingQty <= remaining;

                    // Calculate display values
                    final apiUsed = area.batchNo ?? 0;
                    final tempUsed = _getTempUsedQty(area.name);
                    final totalUsed = apiUsed + tempUsed;
                    final percent = _calculateUsagePercent(area);

                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: canFit
                          ? () {
                        Navigator.pop(context, area);
                      }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: !canFit
                              ? Colors.grey.shade100
                              : isLast
                              ? Colors.blue.shade50
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isLast ? Colors.blue : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔹 Title Row
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    area.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isLast)
                                  const Icon(
                                    Icons.history,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            /// 🔹 Sub Info with temp usage indicator
                            Row(
                              children: [
                                Text(
                                  'ID: ${area.id} • Batch ${area.batchNo}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (tempUsed > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+$tempUsed pending',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 14),

                            /// 🔹 Capacity Progress Bar
                            Stack(
                              children: [
                                /// Background
                                Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.grey.shade200,
                                  ),
                                ),

                                /// Progress Fill (LEFT → RIGHT)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: percent,
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      height: 22,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          colors: percent > 0.9
                                              ? [Colors.red, Colors.redAccent]
                                              : percent > 0.7
                                              ? [
                                            Colors.orange,
                                            Colors.deepOrange
                                          ]
                                              : [
                                            Colors.green,
                                            Colors.lightGreen
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                /// Text (centered on bar) - shows total including pending
                                Positioned.fill(
                                  child: Center(
                                    child: Text(
                                      '${totalUsed.toStringAsFixed(0)} / ${capacity.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            /// 🔹 Remaining capacity indicator
                            if (!canFit) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 16,
                                      color: Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Not enough space (need ${widget.incomingQty}, only ${remaining.toStringAsFixed(0)} left)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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