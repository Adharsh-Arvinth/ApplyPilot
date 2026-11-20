package org.applypilot.applypilot

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On-device AI for every phone that has the app: a small open model (Qwen, Apache-2.0) runs inside the app
 * with Google's LiteRT-LM — no key, no server, works offline.
 *
 * Kept light on purpose:
 *  - the model is downloaded only when the user asks (Wi-Fi only unless they allow mobile data), resumable;
 *  - it is loaded only when an answer is needed and released after [IDLE_MS] of inactivity (0 MB when idle);
 *  - it refuses to load when the phone is low on free memory, so it never slows the phone down;
 *  - the size offered depends on the phone's RAM.
 */
object OnDeviceAI {
    data class Model(val id: String, val name: String, val file: String, val url: String, val bytes: Long, val minRamGb: Double, val needFreeMb: Long)

    val MODELS = listOf(
        Model("lite", "Lite · Qwen3 0.6B", "Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm",
            "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm",
            343_490_560L, 3.0, 700),
        Model("quality", "Quality · Qwen2.5 1.5B", "Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm",
            "https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm",
            1_597_922_856L, 7.5, 2200),
    )
    private const val IDLE_MS = 60_000L

    private lateinit var app: Context
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "ondevice-ai").apply { priority = Thread.NORM_PRIORITY - 1 } }
    private val downloader = Executors.newSingleThreadExecutor { r -> Thread(r, "ondevice-ai-download") }
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var engineModel: String? = null
    private var backendName = ""
    private val releaseTask = Runnable { worker.execute { release() } }
    private val cancelDownload = AtomicBoolean(false)
    @Volatile var download: Map<String, Any?> = mapOf("status" to "idle")

    /** Events to Flutter → the cockpit: "download" progress and streamed "token"s. */
    var emit: (String, Map<String, Any?>) -> Unit = { _, _ -> }

    fun init(context: Context) { app = context.applicationContext }

    private fun dir() = File(app.filesDir, "models").apply { mkdirs() }
    private fun fileFor(m: Model) = File(dir(), m.file)
    private fun model(id: String?) = MODELS.firstOrNull { it.id == id } ?: MODELS.first()
    private fun installed(m: Model) = fileFor(m).let { it.exists() && it.length() >= m.bytes * 98 / 100 }

    private fun memory(): ActivityManager.MemoryInfo {
        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
    }
    private fun ramGb() = memory().totalMem / 1_073_741_824.0

    private fun unmetered(): Boolean {
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    fun status(): Map<String, Any?> {
        val mem = memory()
        val ram = mem.totalMem / 1_073_741_824.0
        return mapOf(
            "supported" to (ram >= MODELS.first().minRamGb),
            "ram_gb" to Math.round(ram * 10) / 10.0,
            "free_mb" to mem.availMem / 1_048_576,
            "wifi" to unmetered(),
            "loaded" to engineModel,
            "backend" to backendName,
            "download" to download,
            "models" to MODELS.map { m ->
                mapOf("id" to m.id, "name" to m.name, "size_mb" to m.bytes / 1_048_576, "fits" to (ram >= m.minRamGb),
                      "installed" to installed(m), "recommended" to (m.id == recommended(ram)))
            },
        )
    }

    private fun recommended(ram: Double) = if (ram >= MODELS[1].minRamGb) "quality" else "lite"

    // ── download (resumable, Wi-Fi only unless allowed) ──
    fun startDownload(id: String?, allowMobileData: Boolean): Map<String, Any?> {
        val m = model(id)
        if (ramGb() < m.minRamGb) throw IllegalStateException("This phone has too little memory for ${m.name}.")
        if (!allowMobileData && !unmetered()) throw IllegalStateException("Connect to Wi-Fi to download the model (${m.bytes / 1_048_576} MB), or allow mobile data.")
        if (download["status"] == "downloading") return download
        if (dir().usableSpace < m.bytes + 200L * 1_048_576) throw IllegalStateException("Not enough free storage: ${m.bytes / 1_048_576} MB needed.")
        cancelDownload.set(false)
        download = mapOf("status" to "downloading", "model" to m.id, "done" to 0L, "total" to m.bytes)
        downloader.execute {
            val part = File(dir(), m.file + ".part")
            try {
                var have = if (part.exists()) part.length() else 0L
                val conn = (URL(m.url).openConnection() as HttpURLConnection).apply {
                    instanceFollowRedirects = true; connectTimeout = 20_000; readTimeout = 30_000
                    if (have > 0) setRequestProperty("Range", "bytes=$have-")
                }
                if (have > 0 && conn.responseCode != 206) have = 0L  // server ignored resume: start over
                val total = if (conn.responseCode == 206) have + conn.contentLengthLong else conn.contentLengthLong.takeIf { it > 0 } ?: m.bytes
                RandomAccessFile(part, "rw").use { out ->
                    out.setLength(have); out.seek(have)
                    conn.inputStream.use { input ->
                        val buf = ByteArray(256 * 1024); var lastEmit = 0L
                        while (true) {
                            if (cancelDownload.get()) throw InterruptedException("cancelled")
                            val n = input.read(buf); if (n < 0) break
                            out.write(buf, 0, n); have += n
                            val now = System.currentTimeMillis()
                            if (now - lastEmit > 400) { lastEmit = now; publish(mapOf("status" to "downloading", "model" to m.id, "done" to have, "total" to total)) }
                        }
                    }
                }
                if (!part.renameTo(fileFor(m))) throw IllegalStateException("Couldn't save the model")
                publish(mapOf("status" to "done", "model" to m.id, "done" to total, "total" to total))
            } catch (e: InterruptedException) {
                publish(mapOf("status" to "idle", "model" to m.id))
            } catch (e: Exception) {
                publish(mapOf("status" to "error", "model" to m.id, "error" to (e.message ?: "Download failed")))
            }
        }
        return download
    }

    fun cancelDownload() { cancelDownload.set(true) }

    private fun publish(state: Map<String, Any?>) { download = state; main.post { emit("download", state) } }

    fun delete(id: String?) {
        val m = model(id)
        worker.execute {
            if (engineModel == m.id) release()
            fileFor(m).delete(); File(dir(), m.file + ".part").delete()
            main.post { emit("download", mapOf("status" to "idle", "model" to m.id)) }
        }
    }

    // ── load on demand, release when idle ──
    private fun ensureEngine(m: Model) {
        if (engine != null && engineModel == m.id) return
        release()
        if (!installed(m)) throw IllegalStateException("The on-device model isn't downloaded yet.")
        val freeMb = memory().availMem / 1_048_576
        if (freeMb < m.needFreeMb) throw IllegalStateException("The phone is low on free memory right now ($freeMb MB). Using the online AI instead.")
        val cache = File(app.cacheDir, "litertlm").apply { mkdirs() }.path
        // The graphics chip is fastest; fall back to the CPU on phones whose GPU driver isn't supported.
        engine = try {
            Engine(EngineConfig(modelPath = fileFor(m).path, backend = Backend.GPU(), cacheDir = cache)).also { it.initialize(); backendName = "gpu" }
        } catch (e: Throwable) {
            Engine(EngineConfig(modelPath = fileFor(m).path, backend = Backend.CPU(), cacheDir = cache)).also { it.initialize(); backendName = "cpu" }
        }
        engineModel = m.id
    }

    private fun release() {
        try { engine?.close() } catch (_: Throwable) {}
        engine = null; engineModel = null; backendName = ""
    }

    /** Generate a reply; streams "token" events with [requestId] and returns the full text via [done]. */
    fun generate(requestId: String, modelId: String?, system: String, prompt: String, temperature: Double,
                 done: (String?, String?) -> Unit) {
        main.removeCallbacks(releaseTask)
        worker.execute {
            var conversation: Conversation? = null
            try {
                val m = model(modelId ?: MODELS.firstOrNull { installed(it) && ramGb() >= it.minRamGb }?.id)
                ensureEngine(m)
                conversation = engine!!.createConversation(ConversationConfig(
                    systemInstruction = Contents.of(system.ifBlank { "You are a helpful assistant." }),
                    samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = temperature),
                ))
                val text = StringBuilder()
                val finished = java.util.concurrent.CountDownLatch(1)
                var error: Throwable? = null
                // Qwen3 thinks out loud unless asked not to; "/no_think" keeps answers short and fast.
                val ask = if (m.id == "lite") "$prompt /no_think" else prompt
                conversation.sendMessageAsync(ask, object : MessageCallback {
                    override fun onMessage(message: Message) {
                        val piece = message.toString()
                        text.append(piece)
                        main.post { emit("token", mapOf("id" to requestId, "text" to piece)) }
                    }
                    override fun onDone() { finished.countDown() }
                    override fun onError(throwable: Throwable) { error = throwable; finished.countDown() }
                })
                finished.await()
                error?.let { throw it }
                val clean = text.toString().replace(Regex("(?s)<think>.*?</think>"), "").trim()
                main.post { done(clean, null) }
            } catch (e: Throwable) {
                main.post { done(null, e.message ?: "On-device AI failed") }
            } finally {
                try { conversation?.close() } catch (_: Throwable) {}
                main.postDelayed(releaseTask, IDLE_MS)
            }
        }
    }

    /** Free memory immediately (app going to the background). */
    fun trimNow() { main.removeCallbacks(releaseTask); worker.execute { release() } }
}
