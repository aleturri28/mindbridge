package it.unitn.mindbridge

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var analyzer: LandmarkAnalyzer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        analyzer = LandmarkAnalyzer(applicationContext)
        SensingHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, analyzer)
    }

    override fun onDestroy() {
        analyzer?.close()
        analyzer = null
        super.onDestroy()
    }
}
