import 'package:arcore_flutter_plus/src/arcore_material.dart';
import 'package:arcore_flutter_plus/src/shape/arcore_shape.dart';

class ArCoreQuad extends ArCoreShape {
  ArCoreQuad({
    this.width = 1.0,
    this.height = 1.0,
    required List<ArCoreMaterial> materials,
  }) : super(
          materials: materials,
        );

  final double width;
  final double height;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        'width': this.width,
        'height': this.height,
      }..addAll(super.toMap());
}
