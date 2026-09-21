import 'package:arcore_flutter_plus/src/arcore_material.dart';
import 'package:arcore_flutter_plus/src/shape/arcore_shape.dart';

class ArCoreCartoon extends ArCoreShape {
  ArCoreCartoon({
    this.model = "duck",
    required List<ArCoreMaterial> materials,
  }) : super(
          materials: materials,
        );

  final String model;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        'model': this.model,
      }..addAll(super.toMap());
}
