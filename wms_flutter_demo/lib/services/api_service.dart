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

class BinData {
  final String binId;
  final String? binName;
  final String? areaId;

  BinData({
    required this.binId,
    this.binName,
    this.areaId,
  });

  factory BinData.fromJson(Map<String, dynamic> json) {
    return BinData(
      binId: json['bin_id'] ?? '',
      binName: json['bin_name'],
      areaId: json['area_id'],
    );
  }

  @override
  String toString() => binId;
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

  static Future<BasketData?> getBasketData(String tagId) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}${AppStrings.uhfBasketApi}?tagId=$tagId');
      
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

  static Future<List<BinData>> getBins() async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}/wh_former/bins');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['data'] != null) {
          return (jsonData['data'] as List)
              .map((item) => BinData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to load bins: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching bins: $e');
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
