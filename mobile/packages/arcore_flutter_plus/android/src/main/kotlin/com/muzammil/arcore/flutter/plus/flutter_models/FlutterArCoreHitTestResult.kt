package com.muzammil.arcore.flutter.plus.flutter_models

class FlutterArCoreHitTestResult(val distance: Float, val translation: FloatArray, val rotation: FloatArray) {

    fun toHashMap(): HashMap<String, Any> {
        val map: HashMap<String, Any> = HashMap<String, Any>()
        map["distance"] = distance.toDouble()
        map["pose"] = FlutterArCorePose(translation,rotation).toHashMap()
        return map
    }
}
