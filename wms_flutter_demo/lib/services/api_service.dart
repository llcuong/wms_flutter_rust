import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wms_flutter/services/server_config_service.dart';
import '../components/common/app_modal.dart';
import '../config/constants/app_string.dart';

/// Model for parameter options with code and name (e.g., size, brand, type)
class ParameterOption {
  final String code;
  final String name;

  ParameterOption({
    required this.code,
    required this.name,
  });

  factory ParameterOption.fromJson(Map<String, dynamic> json) {
    return ParameterOption(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  @override
  String toString() => name;
}

class BinItem {
  final String binId;
  final int level;
  final int batch;
  final int x;
  final int y;
  final int w;
  final int l;

  BinItem({
    required this.binId,
    required this.level,
    required this.batch,
    required this.x,
    required this.y,
    required this.w,
    required this.l,
  });

  factory BinItem.fromJson(Map<String, dynamic> json) {
    return BinItem(
      binId: json['bin_id'] ?? '',
      level: json['level'] ?? 0,
      batch: json['batch'] ?? 0,
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
      w: json['w'] ?? 0,
      l: json['l'] ?? 0,
    );
  }
}

class AreaData {
  final String id;
  final String name;
  final int x;
  final int y;
  final int w;
  final int l;
  final int batchNo;
  final Map<String, Map<String, List<BinItem>>> bins;

  AreaData({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.w,
    required this.l,
    required this.batchNo,
    required this.bins,
  });

  factory AreaData.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, List<BinItem>>> parsedBins = {};

    if (json['bins'] != null) {
      (json['bins'] as Map<String, dynamic>).forEach((rowKey, levelMap) {
        parsedBins[rowKey] = {};

        (levelMap as Map<String, dynamic>).forEach((levelKey, binList) {
          parsedBins[rowKey]![levelKey] = (binList as List)
              .map((e) => BinItem.fromJson(e))
              .toList();
        });
      });
    }

    return AreaData(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
      w: json['w'] ?? 0,
      l: json['l'] ?? 0,
      batchNo: json['batch_no'] ?? 0,
      bins: parsedBins,
    );
  }
}

List<BinItem> flattenBins(List<AreaData> areas) {
  final List<BinItem> result = [];

  for (final area in areas) {
    area.bins.forEach((rowKey, levelMap) {
      levelMap.forEach((levelKey, binList) {
        result.addAll(binList);
      });
    });
  }

  return result;
}

class BasketData {
  final String tagId;
  final String basketNo;
  final String basketVendor;
  final String basketCapacity;
  final String basketLength;
  final String basketReceiveDate;
  final String basketPurchaseOrder;
  final String formerSize;
  final String formerUsedDay;
  final String bin;

  BasketData({
    this.tagId = '',
    required this.basketNo,
    required this.basketVendor,
    required this.basketCapacity,
    required this.basketLength,
    required this.basketReceiveDate,
    required this.basketPurchaseOrder,
    required this.formerSize,
    required this.formerUsedDay,
    required this.bin,
  });

  Map<String, dynamic> toJson() => {
    'basketNo': basketNo,
    'basketVendor': basketVendor,
    'basketCapacity': basketCapacity,
    'basketLength': basketLength,
    'basketReceiveDate': basketReceiveDate,
    'basketPurchaseOrder': basketPurchaseOrder,
    'formerSize': formerSize,
    'formerUsedDay': formerUsedDay,
    'bin': bin,
  };

  factory BasketData.fromJson(Map<String, dynamic> json) {
    return BasketData(
      tagId: json['tag_id'] ?? '',
      basketNo: json['tag_id'] ?? '',
      basketVendor: json['basket_vendor'] ?? '',
      basketCapacity: json['basket_capacity'] ?? 0,
      basketLength: json['basket_length'] ?? '',
      basketReceiveDate: json['basket_receive_date'] ?? '',
      basketPurchaseOrder: json['basket_purchase_order'] ?? '',
      formerSize: json['former_size'] ?? '',
      formerUsedDay: json['former_used_day'] ?? 0,
      bin: json['bin'] ?? '',
    );
  }
}

class MachineData {
  final String areaId;
  final String? areaName;

  MachineData({
    required this.areaId,
    this.areaName,
  });

  factory MachineData.fromJson(Map<String, dynamic> json) {
    return MachineData(
      areaId: json['area_id'] ?? '',
      areaName: json['area_name'],
    );
  }

  @override
  String toString() => areaName ?? areaId;
}

class StockoutFormData {
  final int id;
  final String stockoutForm;
  final String? stockoutDate;
  final String? batchNo;
  final String? formerSize;
  final int stockoutTotalBasket;
  final int stockoutTotalFormer;
  final int stockoutReturnBasket;
  final int stockoutReturnFormer;
  final int mostBatchUsedDay;

  StockoutFormData({
    required this.id,
    required this.stockoutForm,
    this.stockoutDate,
    this.batchNo,
    this.formerSize,
    required this.stockoutTotalBasket,
    required this.stockoutTotalFormer,
    required this.stockoutReturnBasket,
    required this.stockoutReturnFormer,
    required this.mostBatchUsedDay,
  });

  factory StockoutFormData.fromJson(Map<String, dynamic> json) {
    return StockoutFormData(
      id: json['id'] ?? 0,
      stockoutForm: json['stockout_form'] ?? '',
      stockoutDate: json['stockout_date'],
      batchNo: json['batch_no'],
      formerSize: json['former_size'],
      stockoutTotalBasket: json['stockout_total_basket'] ?? 0,
      stockoutTotalFormer: json['stockout_total_former'] ?? 0,
      stockoutReturnBasket: json['stockout_return_basket'] ?? 0,
      stockoutReturnFormer: json['stockout_return_former'] ?? 0,
      mostBatchUsedDay: json['most_batch_used_day'] ?? 0,
    );
  }
}

// ==================== API SERVICE WITH COOKIE SUPPORT ====================

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static Dio? _dio;
  static CookieJar? _cookieJar;
  static bool _initialized = false;

  static String get _baseUrl => ServerConfigService.apiBaseUrl;

  /// Initialize API service with cookie support
  static Future<void> init() async {
    if (_initialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _cookieJar = PersistCookieJar(
        storage: FileStorage('${dir.path}/cookies'),
        ignoreExpires: true,
      );

      _dio = Dio(BaseOptions(
        baseUrl: _baseUrl,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ));

      _dio!.interceptors.add(CookieManager(_cookieJar!));

      // Add logging interceptor for debugging
      _dio!.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          print('🚀 Request: ${options.method} ${options.path}');
          print('📦 Data: ${options.data}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print('✅ Response: ${response.statusCode} ${response.data}');
          return handler.next(response);
        },
        onError: (error, handler) {
          print('❌ Error: ${error.message}');
          return handler.next(error);
        },
      ));

      _initialized = true;
      print('✅ ApiService initialized with cookie support');
    } catch (e) {
      print('❌ Failed to initialize ApiService: $e');
      rethrow;
    }
  }

  /// Check if initialized
  static bool get isInitialized => _initialized;

  /// Get the Dio instance (ensures initialization)
  static Dio get dio {
    if (!_initialized) {
      throw Exception('ApiService not initialized. Call ApiService.init() first.');
    }
    return _dio!;
  }

  /// Get cookie jar
  static CookieJar get cookieJar {
    if (!_initialized) {
      throw Exception('ApiService not initialized. Call ApiService.init() first.');
    }
    return _cookieJar!;
  }

  /// Set warehouse in cookie
  static Future<void> setWarehouse(String warehouseCode) async {
    if (!_initialized) await init();

    final cookies = [
      Cookie('selected_warehouse', warehouseCode)
        ..path = '/'
        ..httpOnly = false,
    ];

    await _cookieJar!.saveFromResponse(
      Uri.parse('${AppStrings.apiBaseUrl}/set-warehouse'),
      cookies,
    );
    print('✅ Warehouse set to: $warehouseCode');
  }

  /// Get warehouse from cookie
  static Future<String?> getWarehouse() async {
    if (!_initialized) await init();

    final cookies = await _cookieJar!.loadForRequest(
      Uri.parse('${AppStrings.apiBaseUrl}/api/v2/baskets/batch'),
    );

    for (var cookie in cookies) {
      if (cookie.name == 'selected_warehouse') {
        return cookie.value;
      }
    }
    return null;
  }

  /// Clear warehouse cookie
  static Future<void> clearWarehouse() async {
    if (!_initialized) await init();

    final expiredCookie = Cookie('selected_warehouse', '')
      ..path = '/'
      ..expires = DateTime.now().subtract(const Duration(days: 1));

    await _cookieJar!.saveFromResponse(
      Uri.parse('${AppStrings.apiBaseUrl}/clear-warehouse'),
      [expiredCookie],
    );
    print('✅ Warehouse cleared');
  }

  // ==================== API METHODS ====================

  /// Get single basket data
  static Future<BasketData?> getStockOutBasketData(String tagId) async {
    try {
      final response = await dio.get(
        '${AppStrings.uhfBasketStockOutApi}?tagId=$tagId',
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null && jsonData['data'].isNotEmpty) {
          return BasketData.fromJson(jsonData['data'][0]);
        }
        return null;
      } else {
        throw Exception('Failed to load basket data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching basket data: $e');
      rethrow;
    }
  }

  /// Get bins list
  static Future<List<String>> getBins() async {
    try {
      final response = await dio.get('/wh_former/bins');

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['success'] == true) {
          return List<String>.from(jsonData['bins'] ?? []);
        } else {
          throw Exception(jsonData['message'] ?? 'Failed to load bins');
        }
      } else {
        throw Exception('Failed to load bins: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching bins: $e');
      rethrow;
    }
  }

  /// Get plants
  static Future<List<String>> getPlants() async {
    try {
      final response = await dio.get(AppStrings.getPlantsApi);

      if (response.statusCode == 200) {
        final jsonData = response.data;
        return List<String>.from(jsonData['plants'] ?? []);
      } else {
        throw Exception('Failed to load plants');
      }
    } catch (e) {
      print('Error fetching plants: $e');
      rethrow;
    }
  }

  /// Get machines
  static Future<List<String>> getMachines2({
    required String plant,
    String? mode,
  }) async {
    try {
      final response = await dio.get(
        AppStrings.getMachinesApi,
        queryParameters: {
          'plant': plant,
          if (mode != null) 'mode': mode,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        return List<String>.from(jsonData['machines'] ?? []);
      } else {
        throw Exception('Failed to load machines');
      }
    } catch (e) {
      print('Error fetching machines: $e');
      rethrow;
    }
  }

  /// Get lines
  static Future<List<String>> getLines({
    required String machine,
  }) async {
    try {
      final response = await dio.get(
        AppStrings.getLinesApi,
        queryParameters: {'machine': machine},
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        return List<String>.from(jsonData['lines'] ?? []);
      } else {
        throw Exception('Failed to load lines');
      }
    } catch (e) {
      print('Error fetching lines: $e');
      rethrow;
    }
  }

  /// Get stock form
  static Future<String> getStockForm({
    required String machine,
    required String lineName,
    required String sizeNameInput,
    int? stockType,
    String? existingForm,
    String? idStockForm,
    int? buttonMode,
    int? callByButton,
  }) async {
    try {
      final response = await dio.get(
        AppStrings.getStockFormApi,
        queryParameters: {
          'machine': machine,
          'line_name': lineName,
          'size_name_input': sizeNameInput,
          'stock_type': stockType?.toString(),
          if (existingForm != null) 'existing_form': existingForm,
          if (idStockForm != null) 'id_stock_form': idStockForm,
          if (buttonMode != null) 'button_mode': buttonMode.toString(),
          if (callByButton != null) 'call_by_button': callByButton.toString(),
        },
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        return jsonData['form_name'] as String;
      } else {
        throw Exception('Failed to load form name');
      }
    } catch (e) {
      print('Error fetching form name: $e');
      rethrow;
    }
  }

  /// Get parameter options
  static Future<List<ParameterOption>> getParameterOptions(String group) async {
    try {
      final response = await dio.get('/wh_former/parameters?group=$group');

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => ParameterOption.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load parameter options: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching parameter options: $e');
      return [];
    }
  }

  /// Get batch baskets
  static Future<List<BasketData>> getBasketsBatch(
      List<String> tagIds, {
        String? warehouse,
      }) async {
    try {
      final response = await dio.post(
        '/api/v2/baskets/batch',
        data: {
          'tag_ids': tagIds,
          if (warehouse != null) 'warehouse': warehouse,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => BasketData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load batch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching batch basket data: $e');
      rethrow;
    }
  }

  /// Get stockin batch baskets
  static Future<List<BasketData>> getBasketsStockInBatch(
      List<String> tagIds, {
        String? warehouse,
      }) async {
    try {
      final response = await dio.post(
        '/api/v2/baskets/stockin_batch',
        data: {
          'tag_ids': tagIds,
          if (warehouse != null) 'warehouse': warehouse,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => BasketData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load stockin batch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching stockin batch basket data: $e');
      rethrow;
    }
  }

  /// Get stockout batch baskets
  static Future<List<BasketData>> getBasketsStockOutBatch(
      List<String> tagIds, {
        String? binLocation,
        String? warehouse,
      }) async {
    try {
      final response = await dio.post(
        '/api/v2/baskets/stockout_batch',
        data: {
          'tag_ids': tagIds,
          if (binLocation != null) 'bin_location': binLocation,
          if (warehouse != null) 'warehouse': warehouse,
        },
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => BasketData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load stockout batch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching stockout batch basket data: $e');
      rethrow;
    }
  }

  /// Generate batch number
  static Future<String?> generateBatchNo(String itemNo) async {
    try {
      final response = await dio.post(
        '/wh_former/generate_batch',
        data: {'item_no': itemNo},
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['success'] == true) {
          return jsonData['batch_no']?.toString();
        }
      }
      return null;
    } catch (e) {
      print('Error generating batch no: $e');
      return null;
    }
  }

  /// Get areas
  static Future<List<AreaData>> getAreas() async {
    try {
      final response = await dio.get('/wh_former/area');

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['area_data'] != null) {
          return (jsonData['area_data'] as List)
              .map((item) => AreaData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load areas: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching areas: $e');
      return [];
    }
  }

  /// Save batch
  static Future<void> saveBatch(Map<String, dynamic> requestData) async {
    try {
      final response = await dio.post(
        '/wh_former/save_batch',
        data: requestData,
      );

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['success'] != true) {
          throw Exception(jsonData['message'] ?? 'Unknown error');
        }
      } else {
        throw Exception('Failed to save batch: ${response.statusCode}');
      }
    } catch (e) {
      print('Error saving batch: $e');
      rethrow;
    }
  }

  /// Get machines list
  static Future<List<MachineData>> getMachines() async {
    try {
      final response = await dio.get('/wh_former/machines');

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => MachineData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load machines: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching machines: $e');
      return [];
    }
  }

  /// Get stockout forms
  static Future<List<StockoutFormData>> getStockoutForms(
      String machine, {
        String? line,
      }) async {
    try {
      String queryString = 'machine=$machine';
      if (line != null && line.isNotEmpty) {
        queryString += '&line=$line';
      }

      final response = await dio.get('/wh_former/stockout_forms?$queryString');

      if (response.statusCode == 200) {
        final jsonData = response.data;
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => StockoutFormData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load stockout forms: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching stockout forms: $e');
      return [];
    }
  }
}

// ==================== STOCK IN SAVE ====================

class StockInSaveResponse {
  final bool success;
  final String message;
  final int? totalBaskets;
  final int? totalFormers;
  final String? batchNo;

  StockInSaveResponse({
    required this.success,
    required this.message,
    this.totalBaskets,
    this.totalFormers,
    this.batchNo,
  });

  factory StockInSaveResponse.fromJson(Map<String, dynamic> json) {
    return StockInSaveResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      totalBaskets: json['total_baskets'],
      totalFormers: json['total_formers'],
      batchNo: json['batch_no'],
    );
  }
}

class StockInRackData {
  final int rackNo;
  final String bin;
  final List<StockInItemData> items;

  StockInRackData({
    required this.rackNo,
    required this.bin,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'rack_no': rackNo,
    'bin': bin,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class StockInItemData {
  final String tagId;
  final String basketNo;
  final int basketFormerQty;

  StockInItemData({
    required this.tagId,
    required this.basketNo,
    required this.basketFormerQty,
  });

  Map<String, dynamic> toJson() => {
    'tag_id': tagId,
    'basket_no': basketNo,
    'basket_former_qty': basketFormerQty,
  };
}

extension ApiServiceStockIn on ApiService {
  static Future<StockInSaveResponse> saveStockIn({
    required String stockinForm,
    required String formerSize,
    required String selectedMachine,
    required List<StockInRackData> racks,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/wh_former/stockin/save',
        data: {
          'stockin_form': stockinForm,
          'former_size': formerSize,
          'selected_machine': selectedMachine,
          'racks': racks.map((r) => r.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        return StockInSaveResponse.fromJson(response.data);
      } else {
        return StockInSaveResponse(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return StockInSaveResponse(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}

// ==================== STOCK OUT SAVE ====================

class StockOutSaveResponse {
  final bool success;
  final String message;
  final int? totalBaskets;
  final int? totalFormers;
  final String? batchNo;

  StockOutSaveResponse({
    required this.success,
    required this.message,
    this.totalBaskets,
    this.totalFormers,
    this.batchNo,
  });

  factory StockOutSaveResponse.fromJson(Map<String, dynamic> json) {
    return StockOutSaveResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      totalBaskets: json['total_baskets'],
      totalFormers: json['total_formers'],
      batchNo: json['batch_no'],
    );
  }
}

class StockOutRackData {
  final int rackNo;
  final String bin;
  final List<StockOutItemData> items;

  StockOutRackData({
    required this.rackNo,
    required this.bin,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'rack_no': rackNo,
    'bin': bin,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class StockOutItemData {
  final String tagId;
  final String basketNo;
  final int basketFormerQty;

  StockOutItemData({
    required this.tagId,
    required this.basketNo,
    required this.basketFormerQty,
  });

  Map<String, dynamic> toJson() => {
    'tag_id': tagId,
    'basket_no': basketNo,
    'basket_former_qty': basketFormerQty,
  };
}

extension ApiServiceStockOut on ApiService {
  static Future<StockOutSaveResponse> saveStockOut({
    required String stockoutForm,
    required String formerSize,
    required String selectedMachine,
    required String stockoutFrom,
    required String action,
    required List<StockOutRackData> racks,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/wh_former/stockout/save',
        data: {
          'stockout_form': stockoutForm,
          'former_size': formerSize,
          'selected_machine': selectedMachine,
          'stockout_from': stockoutFrom,
          'action': action,
          'racks': racks.map((r) => r.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        return StockOutSaveResponse.fromJson(response.data);
      } else {
        return StockOutSaveResponse(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return StockOutSaveResponse(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}

// ==================== EMPTY STOCK SAVE ====================

class EmptyStockSaveResponse {
  final bool success;
  final String message;
  final int? totalBaskets;
  final int? totalFormers;

  EmptyStockSaveResponse({
    required this.success,
    required this.message,
    this.totalBaskets,
    this.totalFormers,
  });

  factory EmptyStockSaveResponse.fromJson(Map<String, dynamic> json) {
    return EmptyStockSaveResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      totalBaskets: json['total_baskets'],
      totalFormers: json['total_formers'],
    );
  }
}

class EmptyStockRackData {
  final int rackNo;
  final String bin;
  final List<EmptyStockItemData> items;

  EmptyStockRackData({
    required this.rackNo,
    required this.bin,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'rack_no': rackNo,
    'bin': bin,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class EmptyStockItemData {
  final String tagId;
  final String basketNo;
  final int basketFormerQty;

  EmptyStockItemData({
    required this.tagId,
    required this.basketNo,
    required this.basketFormerQty,
  });

  Map<String, dynamic> toJson() => {
    'tag_id': tagId,
    'basket_no': basketNo,
    'basket_former_qty': basketFormerQty,
  };
}

extension ApiServiceEmptyStock on ApiService {
  static Future<EmptyStockSaveResponse> saveEmptyStock({
    required String selectedMachine,
    required String action,
    required List<EmptyStockRackData> racks,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/wh_former/empty_stock/save',
        data: {
          'selected_machine': selectedMachine,
          'action': action,
          'racks': racks.map((r) => r.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        return EmptyStockSaveResponse.fromJson(response.data);
      } else {
        return EmptyStockSaveResponse(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return EmptyStockSaveResponse(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}

// ==================== FORMER MOVING SAVE ====================

class FormerMovingSaveResponse {
  final bool success;
  final String message;
  final int? totalBaskets;
  final int? totalFormers;

  FormerMovingSaveResponse({
    required this.success,
    required this.message,
    this.totalBaskets,
    this.totalFormers,
  });

  factory FormerMovingSaveResponse.fromJson(Map<String, dynamic> json) {
    return FormerMovingSaveResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      totalBaskets: json['total_baskets'],
      totalFormers: json['total_formers'],
    );
  }
}

class FormerMovingRackData {
  final int rackNo;
  final String bin;
  final List<FormerMovingItemData> items;

  FormerMovingRackData({
    required this.rackNo,
    required this.bin,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'rack_no': rackNo,
    'bin': bin,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class FormerMovingItemData {
  final String tagId;
  final String basketNo;
  final int basketFormerQty;

  FormerMovingItemData({
    required this.tagId,
    required this.basketNo,
    required this.basketFormerQty,
  });

  Map<String, dynamic> toJson() => {
    'tag_id': tagId,
    'basket_no': basketNo,
    'basket_former_qty': basketFormerQty,
  };
}

extension ApiServiceFormerMoving on ApiService {
  static Future<FormerMovingSaveResponse> saveFormerMoving({
    required String selectedMachine,
    required String action,
    required List<FormerMovingRackData> racks,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/wh_former/moving/save',
        data: {
          'selected_machine': selectedMachine,
          'action': action,
          'racks': racks.map((r) => r.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        return FormerMovingSaveResponse.fromJson(response.data);
      } else {
        return FormerMovingSaveResponse(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return FormerMovingSaveResponse(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}

// ==================== FORMER CLEANING SAVE ====================

class FormerCleaningSaveResponse {
  final bool success;
  final String message;
  final int? totalBaskets;
  final int? totalFormers;

  FormerCleaningSaveResponse({
    required this.success,
    required this.message,
    this.totalBaskets,
    this.totalFormers,
  });

  factory FormerCleaningSaveResponse.fromJson(Map<String, dynamic> json) {
    return FormerCleaningSaveResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      totalBaskets: json['total_baskets'],
      totalFormers: json['total_formers'],
    );
  }
}

class FormerCleaningRackData {
  final int rackNo;
  final String bin;
  final List<FormerCleaningItemData> items;

  FormerCleaningRackData({
    required this.rackNo,
    required this.bin,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'rack_no': rackNo,
    'bin': bin,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class FormerCleaningItemData {
  final String tagId;
  final String basketNo;
  final int basketFormerQty;

  FormerCleaningItemData({
    required this.tagId,
    required this.basketNo,
    required this.basketFormerQty,
  });

  Map<String, dynamic> toJson() => {
    'tag_id': tagId,
    'basket_no': basketNo,
    'basket_former_qty': basketFormerQty,
  };
}

extension ApiServiceFormerCleaning on ApiService {
  static Future<FormerCleaningSaveResponse> saveFormerCleaning({
    required String stockoutForm,
    required String action,
    required String source,
    required List<FormerCleaningRackData> racks,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/wh_former/cleaning/save',
        data: {
          'stockout_form': stockoutForm,
          'action': action,
          'source': source,
          'racks': racks.map((r) => r.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        return FormerCleaningSaveResponse.fromJson(response.data);
      } else {
        return FormerCleaningSaveResponse(
          success: false,
          message: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return FormerCleaningSaveResponse(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}