import 'medicine_model.dart';

class CartItemModel {
  final MedicineModel medicine;
  int quantity;

  CartItemModel({
    required this.medicine,
    this.quantity = 1,
  });

  double get totalPrice => medicine.price * quantity;

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      medicine: MedicineModel.fromJson(Map<String, dynamic>.from(json['medicine'])),
      quantity: json['quantity'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medicine': medicine.toJson(),
      'quantity': quantity,
    };
  }
}
