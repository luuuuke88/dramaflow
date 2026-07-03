package com.dramaflow.dramaflow

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dramaflow/composer"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "probeDuration" -> {
                        val path = call.argument<String>("path")
                            ?: throw ComposerException("视频路径不能为空")
                        result.success(probeDuration(path))
                    }
                    "concat" -> {
                        val paths = call.argument<List<String>>("paths")
                            ?: throw ComposerException("视频片段不能为空")
                        val output = call.argument<String>("output")
                            ?: throw ComposerException("输出路径不能为空")
                        concat(paths, output)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("composer_error", e.message ?: "视频合成失败", null)
            }
        }
    }

    private fun probeDuration(path: String): Double? {
        ensureFile(path)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?: return null
            if (durationMs > 0) durationMs / 1000.0 else null
        } finally {
            retriever.release()
        }
    }

    private fun concat(paths: List<String>, output: String) {
        if (paths.isEmpty()) throw ComposerException("视频片段不能为空")
        paths.forEach(::ensureFile)

        val outputFile = File(output)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        val first = inspectTracks(paths.first())
        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            val videoOutTrack = muxer.addTrack(first.videoFormat)
            val audioOutTrack = first.audioFormat?.let { muxer.addTrack(it) }
            first.rotationDegrees?.let { muxer.setOrientationHint(it) }
            muxer.start()
            started = true

            var offsetUs = 0L
            for (path in paths) {
                val tracks = inspectTracks(path)
                ensureCompatible(first.videoFormat, tracks.videoFormat, path)
                copyTrack(path, tracks.videoIndex, muxer, videoOutTrack, offsetUs)
                if (audioOutTrack != null && tracks.audioIndex != null) {
                    ensureCompatible(first.audioFormat, tracks.audioFormat, path)
                    copyTrack(path, tracks.audioIndex, muxer, audioOutTrack, offsetUs)
                }
                offsetUs += max(durationUs(path), trackDurationUs(tracks.videoFormat))
            }
        } finally {
            if (started) muxer.stop()
            muxer.release()
        }
    }

    private fun inspectTracks(path: String): TrackInspection {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var videoIndex: Int? = null
            var videoFormat: MediaFormat? = null
            var audioIndex: Int? = null
            var audioFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") && videoIndex == null) {
                    videoIndex = i
                    videoFormat = format
                } else if (mime.startsWith("audio/") && audioIndex == null) {
                    audioIndex = i
                    audioFormat = format
                }
            }
            return TrackInspection(
                videoIndex = videoIndex ?: throw ComposerException("视频文件没有视频轨：$path"),
                videoFormat = videoFormat ?: throw ComposerException("视频文件没有视频轨：$path"),
                audioIndex = audioIndex,
                audioFormat = audioFormat,
                rotationDegrees = videoFormat.rotationDegreesOrNull(),
            )
        } finally {
            extractor.release()
        }
    }

    private fun copyTrack(
        path: String,
        trackIndex: Int,
        muxer: MediaMuxer,
        muxerTrackIndex: Int,
        offsetUs: Long,
    ) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            extractor.selectTrack(trackIndex)
            val buffer = ByteBuffer.allocateDirect(4 * 1024 * 1024)
            val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val sampleTime = extractor.sampleTime
                if (sampleTime >= 0) {
                    info.set(0, size, sampleTime + offsetUs, extractor.sampleFlags)
                    muxer.writeSampleData(muxerTrackIndex, buffer, info)
                }
                extractor.advance()
            }
        } finally {
            extractor.release()
        }
    }

    private fun ensureCompatible(
        expected: MediaFormat?,
        actual: MediaFormat?,
        path: String,
    ) {
        if (expected == null || actual == null) return
        val expectedMime = expected.getString(MediaFormat.KEY_MIME)
        val actualMime = actual.getString(MediaFormat.KEY_MIME)
        if (expectedMime != actualMime) {
            throw ComposerException("视频格式不一致，无法直接拼接：$path")
        }
        if (expectedMime?.startsWith("video/") == true) {
            if (expected.intOrNull(MediaFormat.KEY_WIDTH) != actual.intOrNull(MediaFormat.KEY_WIDTH) ||
                expected.intOrNull(MediaFormat.KEY_HEIGHT) != actual.intOrNull(MediaFormat.KEY_HEIGHT)
            ) {
                throw ComposerException("视频分辨率不一致，无法直接拼接：$path")
            }
        }
        if (expectedMime?.startsWith("audio/") == true) {
            if (expected.intOrNull(MediaFormat.KEY_SAMPLE_RATE) != actual.intOrNull(MediaFormat.KEY_SAMPLE_RATE) ||
                expected.intOrNull(MediaFormat.KEY_CHANNEL_COUNT) != actual.intOrNull(MediaFormat.KEY_CHANNEL_COUNT)
            ) {
                throw ComposerException("音频格式不一致，无法直接拼接：$path")
            }
        }
    }

    private fun durationUs(path: String): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?: 0L
            durationMs * 1000L
        } finally {
            retriever.release()
        }
    }

    private fun trackDurationUs(format: MediaFormat): Long =
        if (format.containsKey(MediaFormat.KEY_DURATION)) {
            format.getLong(MediaFormat.KEY_DURATION)
        } else {
            0L
        }

    private fun ensureFile(path: String) {
        if (!File(path).isFile) throw ComposerException("视频文件不存在：$path")
    }
}

private data class TrackInspection(
    val videoIndex: Int,
    val videoFormat: MediaFormat,
    val audioIndex: Int?,
    val audioFormat: MediaFormat?,
    val rotationDegrees: Int?,
)

private class ComposerException(message: String) : Exception(message)

private fun MediaFormat.intOrNull(key: String): Int? =
    if (containsKey(key)) getInteger(key) else null

private fun MediaFormat.rotationDegreesOrNull(): Int? =
    if (containsKey(MediaFormat.KEY_ROTATION)) getInteger(MediaFormat.KEY_ROTATION) else null
