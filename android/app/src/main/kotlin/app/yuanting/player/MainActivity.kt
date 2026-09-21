package app.yuanting.player

import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        disableDefaultFocusHighlight(window.decorView)
    }

    override fun onPostResume() {
        super.onPostResume()
        // 模拟器方向键会给 FlutterView 打上系统焦点绿框，需在视图树建好后关掉
        disableDefaultFocusHighlight(window.decorView)
        findViewById<ViewGroup>(android.R.id.content)?.let {
            disableDefaultFocusHighlight(it)
        }
    }

    private fun disableDefaultFocusHighlight(root: View?) {
        if (root == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        root.defaultFocusHighlightEnabled = false
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                disableDefaultFocusHighlight(root.getChildAt(i))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "audiobook_player/clipboard"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getText" -> {
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = cm.primaryClip
                    if (clip == null || clip.itemCount == 0) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    // 多项里取最长的纯文本。部分系统会在第一项放截断预览。
                    var best: String? = null
                    for (i in 0 until clip.itemCount) {
                        val item = clip.getItemAt(i)
                        val direct = item.text?.toString()
                        if (direct != null && direct.length > (best?.length ?: -1)) {
                            best = direct
                        }
                        try {
                            val coerced = item.coerceToText(this)?.toString()
                            if (coerced != null && coerced.length > (best?.length ?: -1)) {
                                best = coerced
                            }
                        } catch (_: Exception) {
                        }
                    }
                    result.success(best)
                }
                else -> result.notImplemented()
            }
        }
    }
}
