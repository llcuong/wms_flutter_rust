import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';
import '../../models/scanned_item.dart';
import '../../services/api_service.dart';
import '../../widgets/bin_selection_modal.dart';
import 'app_modal.dart';

class RackDetailModal {
  static Future<void> show({
    required BuildContext context,
    required List<Rack> racks,
    required Function(int) onDelete, // Callback with rack index or rackNo
    Function(int, String)? onUpdateBin, // Callback to update bin (nullable)
    bool isBinSelection = true, // New parameter to control bin selection visibility
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return _RackDetailContent(
            racks: racks,
            scrollController: controller,
            onDelete: onDelete,
            onUpdateBin: onUpdateBin,
            isBinSelection: isBinSelection,
          );
        },
      ),
    );
  }
}

class _RackDetailContent extends StatefulWidget {
  final List<Rack> racks;
  final ScrollController scrollController;
  final Function(int) onDelete;
  final Function(int, String)? onUpdateBin;
  final bool isBinSelection;

  const _RackDetailContent({
    required this.racks,
    required this.scrollController,
    required this.onDelete,
    this.onUpdateBin,
    required this.isBinSelection,
  });

  @override
  State<_RackDetailContent> createState() => _RackDetailContentState();
}

class _RackDetailContentState extends State<_RackDetailContent> {
  final Map<int, String> _searchKeywords = {};
  final Map<int, bool> _expandedRacks = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: widget.racks.length,
              itemBuilder: (context, index) {
                return _buildRackCard(widget.racks[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final totalItems =
    widget.racks.fold<int>(0, (s, r) => s + r.items.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'RACK DETAILS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.racks.length} racks • $totalItems items',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRackCard(Rack rack) {
    final keyword = _searchKeywords[rack.rackNo] ?? '';
    final filteredItems = rack.items
        .where((i) => i.id.toLowerCase().contains(keyword.toLowerCase()))
        .toList();

    final isExpanded = _expandedRacks[rack.rackNo] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.zero,
          onExpansionChanged: (value) {
            setState(() {
              _expandedRacks[rack.rackNo] = value;
            });
          },
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rack ${rack.rackNo.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // Only show bin selection if isBinSelection is true
                  if (widget.isBinSelection) ...[
                    const SizedBox(height: 4),
                    // Bin Info
                    InkWell(
                      onTap: () => _updateBin(rack),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.info.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 12, color: AppColors.info),
                            const SizedBox(width: 4),
                            Text(
                              rack.bin.isNotEmpty ? rack.bin : 'Choose Bin',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.info
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '${rack.items.length} items',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: AppColors.error,
                tooltip: 'Remove rack',
                onPressed: () => _confirmDelete(rack),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more),
              ),
            ],
          ),
          children: [
            _buildSearch(rack),
            const SizedBox(height: 8),
            _buildItemTableHeader(),
            ...filteredItems.map(_buildItemRow),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _updateBin(Rack rack) async {
    // Only proceed if bin selection is enabled and callback is provided
    if (!widget.isBinSelection || widget.onUpdateBin == null) return;

    final selectedArea = await showDialog<AreaData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: BinSelectionModal(
          incomingQty: rack.items.length,
          rackData: widget.racks,
          currentScannedItems: null,
        ),
      ),
    );

    if (selectedArea != null && mounted) {
      widget.onUpdateBin!(rack.rackNo, selectedArea.name);
      setState(() {
        // Force rebuild to reflect changes
      });
    }
  }

  Future<void> _confirmDelete(Rack rack) async {
    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Delete Rack',
      message: 'Are you sure you want to delete Rack ${rack.rackNo}?',
      confirmText: 'Delete',
      cancelText: 'Cancel',
    );

    if (confirm == true) {
      widget.onDelete(rack.rackNo);
      Navigator.pop(context);
    }
  }

  Widget _buildSearch(Rack rack) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search tag ID...',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchKeywords[rack.rackNo] = value;
          });
        },
      ),
    );
  }

  Widget _buildItemTableHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: const [
          Expanded(
            flex: 4,
            child: Text(
              'TAG ID',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'QTY',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(ScannedItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              item.id,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              item.quantity.toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}