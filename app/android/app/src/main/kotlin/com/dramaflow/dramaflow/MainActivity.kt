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
                    "inspectMedia" -> {
                        val path = call.argument<String>("path")
                            ?: throw ComposerException("媒体路径不能为空")
                        result.success(inspectMedia(path))
                    }
                    "concat" -> {
                        val paths = call.argument<List<String>>("paths")
                            ?: throw ComposerException("视频片段不能为空")
                        val output = call.argument<String>("output")
                            ?: throw ComposerException("输出路径不能为空")
                        concat(paths, output)
                        result.success(null)
                    }
                    "compose" -> {
                        val segments = call.argument<List<Map<String, String?>>>("segments")
                            ?: throw ComposerException("视频片段不能为空")
                        val output = call.argument<String>("output")
                            ?: throw ComposerException("输出路径不能为空")
                        compose(segments, output)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("composer_error", e.message ?: "视频合成失败", null)
            }
        }
    }

    private fun compose(segments: List<Map<String, String?>>, output: String) {
        if (segments.isEmpty()) throw ComposerException("视频片段不能为空")
        val inputs = segments.map {
            ComposeSegmentInput(
                videoPath = it["videoPath"] ?: throw ComposerException("视频路径不能为空"),
                audioPath = it["audioPath"]?.takeIf { path -> path.isNotBlank() },
            )
        }
        if (inputs.none { it.audioPath != null }) {
            concat(inputs.map { it.videoPath }, output)
            return
        }
        composeWithExternalAudio(inputs, output)
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

    private fun inspectMedia(path: String): Map<String, Any> {
        ensureFile(path)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var videoTrackCount = 0
            var audioTrackCount = 0
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    videoTrackCount += 1
                } else if (mime.startsWith("audio/")) {
                    audioTrackCount += 1
                }
            }
            val info = mutableMapOf<String, Any>(
                "videoTrackCount" to videoTrackCount,
                "audioTrackCount" to audioTrackCount,
            )
            val duration = probeDuration(path)
            if (duration != null) {
                info["durationSec"] = duration
            }
            return info
        } finally {
            extractor.release()
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

    private fun composeWithExternalAudio(segments: List<ComposeSegmentInput>, output: String) {
        segments.forEach { ensureFile(it.videoPath) }
        segments.mapNotNull { it.audioPath }.forEach(::ensureFile)

        val inspected = segments.map { segment ->
            val tracks = inspectTracks(segment.videoPath)
            ComposeInspection(
                segment = segment,
                tracks = tracks,
                externalAudio = segment.audioPath?.let(::inspectAudioTrack),
                durationUs = max(durationUs(segment.videoPath), trackDurationUs(tracks.videoFormat)),
            )
        }
        val first = inspected.first()
        val outputAudioFormat = firstOutputAudioFormat(inspected)

        val outputFile = File(output)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            val videoOutTrack = muxer.addTrack(first.tracks.videoFormat)
            val audioOutTrack = outputAudioFormat?.let { muxer.addTrack(it) }
            first.tracks.rotationDegrees?.let { muxer.setOrientationHint(it) }
            muxer.start()
            started = true

            var offsetUs = 0L
            for (item in inspected) {
                ensureCompatible(first.tracks.videoFormat, item.tracks.videoFormat, item.segment.videoPath)
                copyTrack(item.segment.videoPath, item.tracks.videoIndex, muxer, videoOutTrack, offsetUs)
                if (audioOutTrack != null) {
                    val externalAudio = item.externalAudio
                    if (externalAudio != null) {
                        ensureCompatible(outputAudioFormat, externalAudio.audioFormat, item.segment.audioPath!!)
                        copyExternalAudioTrack(
                            item.segment.audioPath,
                            externalAudio.audioIndex,
                            muxer,
                            audioOutTrack,
                            offsetUs,
                            item.durationUs,
                        )
                    } else if (item.tracks.audioIndex != null) {
                        ensureCompatible(outputAudioFormat, item.tracks.audioFormat, item.segment.videoPath)
                        copyTrack(item.segment.videoPath, item.tracks.audioIndex, muxer, audioOutTrack, offsetUs)
                    }
                }
                offsetUs += item.durationUs
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

    private fun inspectAudioTrack(path: String): AudioInspection {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    return AudioInspection(i, format)
                }
            }
            throw ComposerException("音频文件没有音频轨：$path")
        } finally {
            extractor.release()
        }
    }

    private fun firstOutputAudioFormat(inspected: List<ComposeInspection>): MediaFormat? {
        for (item in inspected) {
            item.externalAudio?.audioFormat?.let { return it }
            item.tracks.audioFormat?.let { return it }
        }
        return null
    }

    private fun copyTrack(
        path: String,
        trackIndex: Int,
        muxer: MediaMuxer,
        muxerTrackIndex: Int,
        offsetUs: Long,
        maxInputDurationUs: Long? = null,
    ) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            extractor.selectTrack(trackIndex)
            val buffer = ByteBuffer.allocateDirect(4 * 1024 * 1024)
            val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val sampleTime = extractor.sampleTime
                if (maxInputDurationUs != null && sampleTime >= maxInputDurationUs) break
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

    private fun copyExternalAudioTrack(
        path: String,
        trackIndex: Int,
        muxer: MediaMuxer,
        muxerTrackIndex: Int,
        offsetUs: Long,
        segmentDurationUs: Long,
    ) {
        copyTrack(path, trackIndex, muxer, muxerTrackIndex, offsetUs, segmentDurationUs)
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

private data class AudioInspection(
    val audioIndex: Int,
    val audioFormat: MediaFormat,
)

private data class ComposeSegmentInput(
    val videoPath: String,
    val audioPath: String?,
)

private data class ComposeInspection(
    val segment: ComposeSegmentInput,
    val tracks: TrackInspection,
    val externalAudio: AudioInspection?,
    val durationUs: Long,
)

private class ComposerException(message: String) : Exception(message)

private fun MediaFormat.intOrNull(key: String): Int? =
    if (containsKey(key)) getInteger(key) else null

private fun MediaFormat.rotationDegreesOrNull(): Int? =
    if (containsKey(MediaFormat.KEY_ROTATION)) getInteger(MediaFormat.KEY_ROTATION) else null
