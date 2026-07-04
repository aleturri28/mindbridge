package it.unitn.mindbridge

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker

/**
 * Implementa il lato nativo del canale sensing: riceve un FramePacket
 * (YUV420), lo converte in Bitmap, esegue Face + Pose Landmarker e
 * restituisce SOLO landmark e blendshapes. Il bitmap è locale al metodo:
 * nessun frame viene salvato o inoltrato (NFR1/NFR2).
 */
class LandmarkAnalyzer(private val context: Context) : SensingHostApi {

    private var faceLandmarker: FaceLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null

    override fun initialize() {
        if (faceLandmarker != null) return

        faceLandmarker = FaceLandmarker.createFromOptions(
            context,
            FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("mediapipe/face_landmarker.task")
                        .build()
                )
                .setRunningMode(RunningMode.VIDEO)
                .setNumFaces(1)
                .setOutputFaceBlendshapes(true)
                .build()
        )
        poseLandmarker = PoseLandmarker.createFromOptions(
            context,
            PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder()
                        .setModelAssetPath("mediapipe/pose_landmarker_lite.task")
                        .build()
                )
                .setRunningMode(RunningMode.VIDEO)
                .setNumPoses(1)
                .build()
        )
    }

    override fun analyzeFrame(packet: FramePacket): FrameAnalysis? {
        val face = faceLandmarker ?: return null
        val pose = poseLandmarker ?: return null

        val started = SystemClock.uptimeMillis()
        val bitmap = yuv420ToBitmap(packet)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val options = ImageProcessingOptions.builder()
            .setRotationDegrees(packet.rotationDegrees.toInt())
            .build()

        val faceResult = face.detectForVideo(mpImage, options, packet.timestampMs)
        val poseResult = pose.detectForVideo(mpImage, options, packet.timestampMs)

        val faceLandmarks = mutableListOf<Double>()
        val blendshapes = mutableMapOf<String, Double>()
        val faceFound = faceResult.faceLandmarks().isNotEmpty()
        if (faceFound) {
            for (lm in faceResult.faceLandmarks()[0]) {
                faceLandmarks.add(lm.x().toDouble())
                faceLandmarks.add(lm.y().toDouble())
            }
            faceResult.faceBlendshapes().ifPresent { all ->
                for (category in all[0]) {
                    blendshapes[category.categoryName()] =
                        category.score().toDouble()
                }
            }
        }

        val poseLandmarks = mutableListOf<Double>()
        val poseFound = poseResult.landmarks().isNotEmpty()
        if (poseFound) {
            for (lm in poseResult.landmarks()[0]) {
                poseLandmarks.add(lm.x().toDouble())
                poseLandmarks.add(lm.y().toDouble())
            }
        }

        return FrameAnalysis(
            faceDetected = faceFound,
            faceLandmarks = faceLandmarks,
            blendshapes = blendshapes,
            poseDetected = poseFound,
            poseLandmarks = poseLandmarks,
            inferenceTimeMs = SystemClock.uptimeMillis() - started,
            timestampMs = packet.timestampMs,
        )
    }

    override fun close() {
        faceLandmarker?.close()
        faceLandmarker = null
        poseLandmarker?.close()
        poseLandmarker = null
    }

    /** Conversione YUV420 (planare, con stride) → Bitmap ARGB_8888. */
    private fun yuv420ToBitmap(packet: FramePacket): Bitmap {
        val width = packet.width.toInt()
        val height = packet.height.toInt()
        val y = packet.yPlane
        val u = packet.uPlane
        val v = packet.vPlane
        val yRowStride = packet.yRowStride.toInt()
        val uvRowStride = packet.uvRowStride.toInt()
        val uvPixelStride = packet.uvPixelStride.toInt()

        val pixels = IntArray(width * height)
        var index = 0
        for (row in 0 until height) {
            val yRow = row * yRowStride
            val uvRow = (row shr 1) * uvRowStride
            for (col in 0 until width) {
                val yValue = (y[yRow + col].toInt() and 0xFF)
                val uvOffset = uvRow + (col shr 1) * uvPixelStride
                val uValue = (u[uvOffset].toInt() and 0xFF) - 128
                val vValue = (v[uvOffset].toInt() and 0xFF) - 128

                var r = yValue + (1.370705f * vValue).toInt()
                var g = yValue - (0.698001f * vValue).toInt() -
                    (0.337633f * uValue).toInt()
                var b = yValue + (1.732446f * uValue).toInt()
                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)
                pixels[index++] =
                    (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
