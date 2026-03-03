import 'dart:convert';
import 'package:http/http.dart' as http;
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
          parsedBins[rowKey]![levelKey] =
              (binList as List)
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
  final int basketCapacity;
  final String basketLength;
  final String basketReceiveDate;
  final String basketPurchaseOrder;
  final String formerSize;
  final int formerUsedDay;

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
  });

  Map<String, dynamic> toJson() => {
    'basketNo': basketNo,
    'basketVendor': basketVendor,
    'basketCapacity': basketCapacity,
    'basketLength': basketLength,
    'basketReceiveDate': basketReceiveDate,
    'basketPurchaseOrder': basketPurchaseOrder,
    // 'bin': bin,
    'formerSize': formerSize,
    'formerUsedDay': formerUsedDay,
  };

  factory BasketData.fromJson(Map<String, dynamic> json) {
    return BasketData(
      tagId: json['tag_id'] ?? '',
      basketNo: json['basket_no'] ?? '',
      basketVendor: json['basket_vendor'] ?? '',
      basketCapacity: json['basket_capacity'] ?? 0,
      basketLength: json['basket_length'] ?? '',
      basketReceiveDate: json['basket_receive_date'] ?? '',
      basketPurchaseOrder: json['basket_purchase_order'] ?? '',
      formerSize: json['former_size'] ?? '',
      formerUsedDay: json['former_used_day'] ?? 0,
    );
  }
}


class ApiService {
  static Future<BasketData?> getStockOutBasketData(String tagId) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}${AppStrings.uhfBasketStockOutApi}?tagId=$tagId');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

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

  /// ------------------ BINS ------------------
  static Future<List<String>> getBins() async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}/wh_former/bins',
      );

      print('Fetching bins from $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        print('Bins data: $jsonData');

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

  /// ------------------ PLANTS ------------------
  static Future<List<String>> getPlants() async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getPlantsApi}',
      );
      print('Fetching plants from $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('Plants data: $jsonData');
        return List<String>.from(jsonData['plants'] ?? []);
      } else {
        throw Exception('Failed to load plants');
      }
    } catch (e) {
      print('Error fetching plants: $e');
      rethrow;
    }
  }

  /// ------------------ MACHINES ------------------
  static Future<List<String>> getMachines2({
    required String plant,
    String? mode, // change | clean | to_lk
  }) async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getMachinesApi}',
      ).replace(queryParameters: {
        'plant': plant,
        if (mode != null) 'mode': mode,
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return List<String>.from(jsonData['machines'] ?? []);
      } else {
        throw Exception('Failed to load machines');
      }
    } catch (e) {
      print('Error fetching machines: $e');
      rethrow;
    }
  }

  /// ------------------ LINES ------------------
  static Future<List<String>> getLines({
    required String machine,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getLinesApi}',
      ).replace(queryParameters: {
        'machine': machine,
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return List<String>.from(jsonData['lines'] ?? []);
      } else {
        throw Exception('Failed to load lines');
      }
    } catch (e) {
      print('Error fetching lines: $e');
      rethrow;
    }
  }

  /// ------------------ STOCK FORM ------------------
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
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getStockFormApi}',
      ).replace(queryParameters: {
        'machine': machine,
        'line_name': lineName,
        'size_name_input': sizeNameInput,
        'stock_type': stockType.toString(),
        if (existingForm != null) 'existing_form': existingForm,
        if (idStockForm != null) 'id_stock_form': idStockForm,
        if (buttonMode != null) 'button_mode': buttonMode.toString(),
        if (callByButton != null) 'call_by_button': callByButton.toString(),
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return jsonData['form_name'] as String;
      } else {
        throw Exception('Failed to load form name');
      }
    } catch (e) {
      print('Error fetching form name: $e');
      rethrow;
    }
  }

  /// Fetch parameter options from database
  /// group: 'size', 'brand', 'type', 'surface', etc.
  static Future<List<ParameterOption>> getParameterOptions(String group) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/parameters?group=$group');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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
      return []; // Return empty list on error to allow fallback
    }
  }

  static Future<List<BasketData>> getBasketsBatch(List<String> tagIds) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/api/v2/baskets/batch'); 
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'tag_ids': tagIds}),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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

  static Future<List<BasketData>> getBasketsStockInBatch(List<String> tagIds) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/api/v2/baskets/stockin_batch'); 
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'tag_ids': tagIds}),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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

  static Future<List<BasketData>> getBasketsStockOutBatch(
      List<String> tagIds, {
        String? binLocation,
      }) async {
    try {
      final url = Uri.parse(
          '${AppStrings.apiBaseUrl}/api/v2/baskets/stockout_batch');

      // Build request body dynamically
      final Map<String, dynamic> body = {
        'tag_ids': tagIds,
      };

      if (binLocation != null) {
        body['bin_location'] = binLocation;
      }

      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => BasketData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception(
            'Failed to load stockout batch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching stockout batch basket data: $e');
      rethrow;
    }
  }

  static Future<BasketData?> getBasketData(String tagId) async {
    try {
      final url = Uri.parse('http://172.18.55.218:8000${AppStrings.uhfBasketApi}?tagId=$tagId');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
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

  static Future<String?> generateBatchNo(String itemNo) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/generate_batch');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'item_no': itemNo}),
      ).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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

  static Future<List<AreaData>> getAreas() async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/area');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

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

  static Future<void> saveBatch(Map<String, dynamic> requestData) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/save_batch');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      ).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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

  static Future<List<MachineData>> getMachines() async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/machines');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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

  static Future<List<StockoutFormData>> getStockoutForms(String machine, {String? line}) async {
    try {
      String queryString = 'machine=$machine';
      if (line != null && line.isNotEmpty) {
        queryString += '&line=$line';
      }
      
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/stockout_forms?$queryString');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
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
  /// Save Stock In data to database
  static Future<StockInSaveResponse> saveStockIn({
    required String stockinForm,
    required String formerSize,
    required String selectedMachine,
    required List<StockInRackData> racks,
  }) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/stockin/save');

      final body = {
        'stockin_form': stockinForm,
        'former_size': formerSize,
        'selected_machine': selectedMachine,
        'racks': racks.map((r) => r.toJson()).toList(),
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return StockInSaveResponse.fromJson(jsonData);
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
  final List<StockInItemData> items;

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
  /// Save Stock Out data to database
  static Future<StockOutSaveResponse> saveStockOut({
    required String stockoutForm,
    required String formerSize,
    required String selectedMachine,
    required String stockoutFrom,
    required String action,
    required List<StockInRackData> racks,
  }) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/stockout/save');

      final body = {
        'stockout_form': stockoutForm,
        'former_size': formerSize,
        'selected_machine': selectedMachine,
        'stockout_from': stockoutFrom,
        'action': action,
        'racks': racks.map((r) => r.toJson()).toList(),
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 30));

      print(response);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return StockOutSaveResponse.fromJson(jsonData);
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
  /// Save Empty Stock data to backend
  static Future<EmptyStockSaveResponse> saveEmptyStock({
    required String selectedMachine,
    required String action,
    required List<EmptyStockRackData> racks,
  }) async {
    try {
      final url = Uri.parse(
          '${AppStrings.apiBaseUrl}/wh_former/empty_stock/save');

      final body = {
        'selected_machine': selectedMachine,
        'action': action,
        'racks': racks.map((r) => r.toJson()).toList(),
      };

      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      )
          .timeout(const Duration(seconds: 30));

      print("EmptyStock Response: ${response.body}");

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return EmptyStockSaveResponse.fromJson(jsonData);
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