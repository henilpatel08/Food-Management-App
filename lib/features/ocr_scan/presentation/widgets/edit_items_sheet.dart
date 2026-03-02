// lib/app/features/ocr_scan/presentation/widgets/edit_items_sheet.dart
import 'package:flutter/material.dart';

/// Simple data model for the editor.
class EditableItem {
  String name;
  double qty;
  String unit;
  EditableItem({required this.name, this.qty = 1, this.unit = 'pcs'});

  EditableItem copy() => EditableItem(name: name, qty: qty, unit: unit);
}

/// Full-screen bottom sheet for editing a list of items.
/// Call with:
/// final updated = await showModalBottomSheet(List[EditableItem])(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => EditItemsSheet(initial: items),
/// );
class EditItemsSheet extends StatefulWidget {
  const EditItemsSheet({super.key, required this.initial});
  final List<EditableItem> initial;

  @override
  State<EditItemsSheet> createState() => _EditItemsSheetState();
}

class _EditItemsSheetState extends State<EditItemsSheet> {
  late List<EditableItem> items;

  @override
  void initState() {
    super.initState();
    // Clone to avoid mutating the source list
    items = widget.initial.map((e) => e.copy()).toList();
  }

  void _addRow() {
    setState(() => items.add(EditableItem(name: '', qty: 1, unit: 'pcs')));
  }

  void _removeItem(EditableItem it) {
    setState(() => items.remove(it)); // delete by identity (correct row)
  }

  // Robust qty parser (accepts "2", "2.5", "  3 ", etc.)
  double _parseQty(String v, {double fallback = 1}) {
    final t = v.trim();
    if (t.isEmpty) return fallback;
    final d = double.tryParse(t.replaceAll(',', '.'));
    return d == null || d.isNaN || !d.isFinite ? fallback : d;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: media.size.height * 0.9,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Edit items'),
              automaticallyImplyLeading: false,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  // Reorderable, but NO swipe-to-delete
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final it = items.removeAt(oldIndex);
                        items.insert(newIndex, it);
                      });
                    },
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return Card(
                        key: ValueKey(it), // stable key = object identity
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Drag handle (so users know they can reorder)
                              const Padding(
                                padding: EdgeInsets.only(top: 16, right: 8),
                                child: Icon(Icons.drag_indicator, color: Colors.black54),
                              ),
                              // Name
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  initialValue: it.name,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Item name',
                                    hintText: 'e.g., Milk',
                                  ),
                                  onChanged: (v) => it.name = v,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Qty
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: (it.qty.truncateToDouble() == it.qty)
                                      ? it.qty.toStringAsFixed(0)
                                      : it.qty.toString(),
                                  keyboardType: const TextInputType.numberWithOptions(
                                    signed: false, decimal: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(labelText: 'Qty'),
                                  onChanged: (v) => it.qty = _parseQty(v, fallback: it.qty),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Unit
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: it.unit,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                    hintText: 'pcs / kg / g',
                                  ),
                                  onChanged: (v) {
                                    final t = v.trim();
                                    it.unit = t.isEmpty ? 'pcs' : t;
                                  },
                                ),
                              ),
                              // Delete button (no swipe)
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _removeItem(it),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Bottom actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Add item'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () {
                          // Return the edited list to caller; wire to inventory later.
                          Navigator.pop(context, items);
                        },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Add to inventory'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
