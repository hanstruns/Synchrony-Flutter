package com.synchrony.enlazatumente

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
    private var musicPlayer: MediaPlayer? = null
    private var feedbackChannel: MethodChannel? = null
    private val vibrator: Vibrator?
        get() = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeControlStream = AudioManager.STREAM_MUSIC
        feedbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "synchrony/feedback")
        feedbackChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "musicStop" -> { stopMusic(); result.success(null) }
                    "musicVolume" -> {
                        val level = (call.arguments as Number).toFloat().coerceIn(0f, 0.5f)
                        musicPlayer?.setVolume(level, level)
                        result.success(null)
                    }
                    "musicLoad" -> {
                        val bytes = call.arguments as ByteArray
                        stopMusic()
                        val file = File(cacheDir, "synchrony-music.wav")
                        file.writeBytes(bytes)
                        val next = MediaPlayer()
                        musicPlayer = next
                        next.setAudioAttributes(AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                        next.setDataSource(file.absolutePath)
                        next.isLooping = true
                        next.setVolume(0f, 0f)
                        next.setOnErrorListener { failed, _, _ ->
                            if (musicPlayer === failed) musicPlayer = null
                            failed.release()
                            true
                        }
                        next.prepare()
                        next.start()
                        result.success(null)
                    }
                    "stop" -> { stopFeedback(); result.success(null) }
                    "play" -> {
                        val cue = call.argument<String>("cue") ?: "card"
                        if (call.argument<Boolean>("sound") == true) {
                            val bytes = call.argument<ByteArray>("bytes")
                                ?: throw IllegalArgumentException("Falta el sonido")
                            // Una ruta fija privada evita interpretar el nombre del efecto como ruta.
                            val file = File(cacheDir, "synchrony-effect.wav")
                            player?.release()
                            player = null
                            file.writeBytes(bytes)
                            val next = MediaPlayer()
                            player = next
                            next.setAudioAttributes(AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_GAME)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                            next.setDataSource(file.absolutePath)
                            next.setOnCompletionListener { finished ->
                                if (player === finished) player = null
                                finished.release()
                            }
                            next.setOnErrorListener { failed, _, _ ->
                                if (player === failed) player = null
                                failed.release()
                                true
                            }
                            next.prepare()
                            next.start()
                        }
                        val motor = vibrator
                        val available = motor?.hasVibrator() == true
                        if (call.argument<Boolean>("vibration") == true && available) {
                            val duration = when (cue) {
                                "mistake", "lost" -> 220L
                                "won", "success", "test" -> 120L
                                else -> 40L
                            }
                            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build()
                            if (Build.VERSION.SDK_INT >= 26) {
                                motor!!.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE), attributes)
                            } else {
                                @Suppress("DEPRECATION")
                                motor!!.vibrate(duration, attributes)
                            }
                        }
                        result.success(available)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (call.method.startsWith("music")) stopMusic() else stopFeedback()
                result.error("FEEDBACK_FAILED", e.message, null)
            }
        }
    }

    private fun stopFeedback() {
        player?.release()
        player = null
        vibrator?.cancel()
    }

    private fun stopMusic() {
        musicPlayer?.release()
        musicPlayer = null
    }

    override fun onPause() { stopMusic(); stopFeedback(); super.onPause() }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        feedbackChannel?.setMethodCallHandler(null)
        feedbackChannel = null
        stopMusic()
        stopFeedback()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
