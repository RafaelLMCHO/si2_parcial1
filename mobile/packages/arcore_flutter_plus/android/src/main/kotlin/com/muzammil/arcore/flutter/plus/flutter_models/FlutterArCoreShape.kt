package com.muzammil.arcore.flutter.plus.flutter_models

import com.muzammil.arcore.flutter.plus.utils.DecodableUtils
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.Material
import com.google.ar.sceneform.rendering.ModelRenderable
import com.google.ar.sceneform.rendering.ShapeFactory

class FlutterArCoreShape(map: HashMap<String, *>) {

    val dartType: String = map["dartType"] as String
    val materials: ArrayList<FlutterArCoreMaterial> = getMaterials(map["materials"] as ArrayList<HashMap<String, *>>)
    val radius: Float? = (map["radius"] as? Double)?.toFloat()
    val size = DecodableUtils.parseVector3(map["size"] as? HashMap<String, Any>) ?: Vector3()
    val height: Float? = (map["height"] as? Double)?.toFloat()
    val width: Float? = (map["width"] as? Double)?.toFloat()
    val model: String? = map["model"] as? String

    fun buildShape(material: Material): ModelRenderable? {
        return when (dartType) {
            "ArCoreSphere" -> ShapeFactory.makeSphere(radius!!, Vector3(0.0f, 0.15f, 0.0f), material)
            "ArCoreCube" -> ShapeFactory.makeCube(size, Vector3(0.0f, 0.15f, 0.0f), material)
            "ArCoreCylinder" -> ShapeFactory.makeCylinder(radius!!, height!!, Vector3(0.0f, 0.15f, 0.0f), material)
            "ArCoreQuad" -> ShapeFactory.makeCube(Vector3(width ?: 1.0f, 0.001f, height ?: 1.0f), Vector3(0.0f, 0.0f, 0.0f), material)
            "ArCoreCapsule" -> ShapeFactory.makeCylinder(radius ?: 0.5f, height ?: 1.0f, Vector3(0.0f, 0.15f, 0.0f), material)
            else ->
                null
        }
    }

    private fun getMaterials(list: ArrayList<HashMap<String, *>>): ArrayList<FlutterArCoreMaterial> {
        return ArrayList(list.map { map -> FlutterArCoreMaterial(map) })
    }

    override fun toString(): String {
        return "dartType: $dartType\nradius: $radius\nsize: $size\nheight: $height\nmaterial: ${materials[0].toString()}"
    }
}
