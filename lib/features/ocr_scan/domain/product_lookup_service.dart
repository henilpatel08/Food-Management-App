import 'package:openfoodfacts/openfoodfacts.dart';

class ProductInfo {
  final String code;
  final String? name;
  final String? brand;
  final String? quantity;
  final String? imageUrl;

  ProductInfo({
    required this.code,
    this.name,
    this.brand,
    this.quantity,
    this.imageUrl,
  });
}

class ProductLookupService {
  ProductLookupService() {
    // Identify your app to OFF (helps with rate limiting)
    OpenFoodAPIConfiguration.userAgent = UserAgent(name: 'SustAInApp');
    // Keep defaults otherwise; newer globals like globalLanguages/globalCountry
    // aren't required and may not exist in your package version.
  }

  /// Robust fetch:
  /// 1) Try V3 (with only fields that exist in your version)
  /// 2) Fallback to V2 (older endpoint often has legacy data)
  Future<ProductInfo?> fetchByBarcode(String code) async {
    final v3 = await _getV3Safe(code);
    if (v3 != null) return v3;

    final v2 = await _getV2Safe(code);
    if (v2 != null) return v2;

    return null;
  }

  // ---------- Internals (version-safe) ----------

  Future<ProductInfo?> _getV3Safe(String code) async {
    final cfg = ProductQueryConfiguration(
      code,
      language: OpenFoodFactsLanguage.ENGLISH,
      version: ProductQueryVersion.v3,
      fields: <ProductField>[
        ProductField.BARCODE,
        ProductField.NAME,
        // ProductField.GENERIC_NAME, // may not exist in your version; omit
        ProductField.BRANDS,
        ProductField.QUANTITY,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    try {
      final res = await OpenFoodAPIClient.getProductV3(cfg);
      final p = res.product;
      if (p == null) return null;

      // Prefer productName; fallback to brands or "code"
      final candidates = <String?>[
        p.productName,
        // p.genericName, // omitted because field may not be present
        p.brands,
      ];

      final name = candidates.firstWhere(
            (e) => e != null && e.trim().isNotEmpty,
        orElse: () => null,
      );

      return ProductInfo(
        code: code,
        name: name,
        brand: p.brands,
        quantity: p.quantity,
        imageUrl: p.imageFrontUrl, // safest image field in older versions
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProductInfo?> _getV2Safe(String code) async {
    final cfg = ProductQueryConfiguration(
      code,
      language: OpenFoodFactsLanguage.ENGLISH,
      version: ProductQueryVersion.v3,
      fields: <ProductField>[
        ProductField.BARCODE,
        ProductField.NAME,
        // ProductField.GENERIC_NAME, // may not exist; omit for safety
        ProductField.BRANDS,
        ProductField.QUANTITY,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    try {
      final res = await OpenFoodAPIClient.getProductV3(cfg);
      final p = res.product;
      if (p == null) return null;

      final candidates = <String?>[
        p.productName,
        // p.genericName,
        p.brands,
      ];

      final name = candidates.firstWhere(
            (e) => e != null && e.trim().isNotEmpty,
        orElse: () => null,
      );

      return ProductInfo(
        code: code,
        name: name,
        brand: p.brands,
        quantity: p.quantity,
        imageUrl: p.imageFrontUrl,
      );
    } catch (_) {
      return null;
    }
  }
}
