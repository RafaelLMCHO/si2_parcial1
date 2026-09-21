import 'package:arcore_flutter_plus/src/arcore_material.dart';
import 'package:arcore_flutter_plus/src/shape/arcore_shape.dart';

class ArCoreCapsule extends ArCoreShape {
  ArCoreCapsule({
    this.radius = 0.5,
    this.height = 1.0,
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
