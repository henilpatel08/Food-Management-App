// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../services/inventory_service.dart';
import '../../domain/cloud_vision_service.dart';
import '../../domain/image_preprocess.dart';
import '../../domain/parse_receipt_text.dart';
import '../../domain/parsed_row.dart';
 // 🔹 integrates your Firestore + category logic

enum ScanMode { receipt, note }

const String _visionApiKey =
String.fromEnvironment('VISION_API_KEY', defaultValue: '');

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  CameraController? _cam;
  bool _initializing = true;
  bool _flashOn = false;
  ScanMode _mode = ScanMode.receipt;

  final _vision = CloudVisionService(apiKey: _visionApiKey);
  final _inventoryService = InventoryService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (cam == null) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.jpeg,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {
        _cam = controller;
        _initializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _initializing = false);
    }
  }

  Future<void> _toggleFlash() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    _flashOn = !_flashOn;
    await cam.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onShutter() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || cam.value.isTakingPicture) {
      return;
    }
    try {
      final shot = await cam.takePicture();
      if (!mounted) return;
      _openResultSheet(File(shot.path));
    } catch (_) {}
  }

  Future<void> _onPickFromGallery() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (img == null || !mounted) return;
    _openResultSheet(File(img.path));
  }

  void _openResultSheet(File imageFile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResultSheet(
        imageFile: imageFile,
        mode: _mode,
        vision: _vision,
        inventoryService: _inventoryService, // 🔹 Firestore integration here
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _initializing
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _cam == null
              ? const SizedBox.shrink()
              : CameraPreview(_cam!),
          Positioned(top: 16, left: 0, right: 0, child: _buildTopRibbon(context)),
          Positioned(bottom: 26, left: 0, right: 0, child: _buildBottomBar()),
        ],
      ),
    );
  }

  Widget _buildTopRibbon(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Back button (top row)
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Material(
                  color: Colors.black.withOpacity(0.3),
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 🔹 Mode chips below back button
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentChip(
                          label: 'Receipt',
                          icon: Icons.receipt_long_rounded,
                          selected: _mode == ScanMode.receipt,
                          onTap: () => setState(() => _mode = ScanMode.receipt),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SegmentChip(
                          label: 'Grocery List',
                          icon: Icons.playlist_add_check_rounded,
                          selected: _mode == ScanMode.note,
                          onTap: () => setState(() => _mode = ScanMode.note),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _GlassButton(icon: Icons.photo_library_rounded, onTap: _onPickFromGallery),
            GestureDetector(
              onTap: _onShutter,
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 34, color: Colors.black),
              ),
            ),
            _GlassButton(
              icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              onTap: _toggleFlash,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.black26,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 72, height: 72, child: Icon(icon, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.black : Colors.white,
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : Colors.black),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================== Result Sheet (Firestore integrated) ===========================

class _ResultSheet extends StatefulWidget {
  const _ResultSheet({
    required this.imageFile,
    required this.mode,
    required this.vision,
    required this.inventoryService,
  });

  final File imageFile;
  final ScanMode mode;
  final CloudVisionService vision;
  final InventoryService inventoryService;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  late Future<_ParsedBundle> _future;
  final TextRecognizer _localOcr = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _future = _processImage();
  }

  @override
  void dispose() {
    _localOcr.close();
    super.dispose();
  }

  Future<_ParsedBundle> _processImage() async {
    final path = widget.imageFile.path;
    Uint8List? prep = await preprocessForOcr(path);
    prep ??= await File(path).readAsBytes();
    String text = '';
    try {
      text = await widget.vision.ocrBytes(prep) ?? '';
    } catch (_) {}
    if (text.isEmpty) text = (await _localOcr.processImage(InputImage.fromFilePath(path))).text;
    final rows = widget.mode == ScanMode.receipt ? parseReceiptText(text) : parseNoteText(text);
    return _ParsedBundle(rawText: text, items: rows);
  }

  Future<void> _onAddToInventory(_ParsedBundle bundle) async {
    try {
      for (final it in bundle.items) {
        await widget.inventoryService.addItem(
          name: it.name,
          qty: it.qty,
          unit: it.unit,
          sourceType: 'Scan',
        );
      }
      if (mounted) {
        Navigator.pop(context, true); // ✅ send "success" flag when closing the sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Items added to inventory')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error adding items: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ParsedBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final bundle = snap.data!;
        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 8),

              // 🔹 Add Item button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Add item'),
                    onPressed: () {
                      setState(() {
                        bundle.items.add(ParsedRow(name: '', qty: 1, unit: 'pcs'));
                      });
                    },
                  ),
                ),
              ),

              // 🔹 Editable list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: bundle.items.length,
                  itemBuilder: (_, i) {
                    final it = bundle.items[i];
                    return Card(
                      key: ValueKey(it),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.black.withOpacity(0.07)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // 📝 Item name
                            Expanded(
                              child: TextFormField(
                                initialValue: it.name,
                                decoration: const InputDecoration(
                                  labelText: 'Item name',
                                  border: InputBorder.none,
                                ),
                                onChanged: (v) => it.name = v,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // 🔢 Quantity
                            SizedBox(
                              width: 64,
                              child: TextFormField(
                                initialValue: it.qty.toString(),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  border: InputBorder.none,
                                ),
                                onChanged: (v) {
                                  final n = double.tryParse(v.replaceAll(',', '.'));
                                  if (n != null) it.qty = n;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 📏 Unit dropdown
                            DropdownButton<String>(
                              value: it.unit,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                                DropdownMenuItem(value: 'kg', child: Text('kg')),
                                DropdownMenuItem(value: 'g', child: Text('g')),
                                DropdownMenuItem(value: 'lb', child: Text('lb')),
                                DropdownMenuItem(value: 'oz', child: Text('oz')),
                                DropdownMenuItem(value: 'L', child: Text('L')),
                                DropdownMenuItem(value: 'ml', child: Text('ml')),
                                DropdownMenuItem(value: 'pack', child: Text('pack')),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => it.unit = v);
                              },
                            ),

                            // 🗑 Delete icon
                            IconButton(
                              tooltip: 'Remove item',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                setState(() {
                                  bundle.items.remove(it);
                                });
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 🔹 Action buttons (Retake / Add to Inventory)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('Retake Photo'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.playlist_add_check_rounded),
                        label: const Text('Add to Inventory'),
                        onPressed: () => _onAddToInventory(bundle),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _ParsedBundle {
  _ParsedBundle({required this.rawText, required this.items});
  final String rawText;
  final List<ParsedRow> items;
}
