import 'package:arcore_flutter_plus/src/arcore_material.dart';
import 'package:arcore_flutter_plus/src/shape/arcore_shape.dart';

class ArCoreCylinder extends ArCoreShape {
  ArCoreCylinder({
    this.radius = 0.1,
    this.height = 0.3,
    required List<ArCoreMaterial> materials,
  }) : super(
          materials: materials,
        );

  final double height;
  final double radius;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        'height': this.height,
        'radius': this.radius,
      }..addAll(super.toMap());
}
