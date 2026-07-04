package com.dramaflow.dramaflow

import android.graphics.Matrix
import android.net.Uri
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import androidx.media3.effect.RgbMatrix
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

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
                        val segments = call.argument<List<Map<String, Any?>>>("segments")
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

    private fun compose(segments: List<Map<String, Any?>>, output: String) {
        if (segments.isEmpty()) throw ComposerException("视频片段不能为空")
        val inputs = segments.map {
            ComposeSegmentInput(
                videoPath = stringValue(it["videoPath"]) ?: throw ComposerException("视频路径不能为空"),
                audioPath = stringValue(it["audioPath"])?.takeIf { path -> path.isNotBlank() },
                transition = stringValue(it["transition"])?.takeIf { value -> value.isNotBlank() },
                filterPreset = stringValue(it["filterPreset"])?.takeIf { value -> value.isNotBlank() },
                timelineKind = stringValue(it["timelineKind"])
                    ?.takeIf { value -> value.isNotBlank() }
                    ?: "storyboard",
                lane = intValue(it["lane"]) ?: 0,
                startMs = intValue(it["startMs"]),
                durationMs = intValue(it["durationMs"]),
            )
        }
        composeInputs(inputs, output)
    }

    private fun composeInputs(inputs: List<ComposeSegmentInput>, output: String) {
        if (inputs.isEmpty()) throw ComposerException("视频片段不能为空")
        if (hasTimelineOverlays(inputs)) {
            composeWithTimelineOverlays(inputs, output)
            return
        }
        if (inputs.none { it.audioPath != null || it.hasNleMetadata }) {
            concat(inputs.map { it.videoPath }, output)
            return
        }
        if (inputs.none { it.audioPath != null }) {
            composeWithNleEffects(inputs, output)
            return
        }
        if (inputs.any { it.hasNleMetadata }) {
            composeWithNleEffectsAndExternalAudio(inputs, output)
            return
        }
        composeWithExternalAudio(inputs, output)
    }

    private fun hasTimelineOverlays(segments: List<ComposeSegmentInput>): Boolean =
        segments.any { it.hasTimelineMetadata && it.isOverlayClip }

    private fun primaryTimelineSegments(segments: List<ComposeSegmentInput>): List<ComposeSegmentInput> =
        segments.filter { !it.isOverlayClip }

    private fun timelineOverlaySegments(segments: List<ComposeSegmentInput>): List<ComposeSegmentInput> =
        segments.filter { it.isOverlayClip }.sortedWith(
            compareBy<ComposeSegmentInput> { it.startMs ?: 0 }.thenBy { it.lane },
        )

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

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun composeWithTimelineOverlays(
        segments: List<ComposeSegmentInput>,
        output: String,
    ) {
        val primarySegments = primaryTimelineSegments(segments)
        val overlaySegments = timelineOverlaySegments(segments)
        if (primarySegments.isEmpty() || overlaySegments.isEmpty()) {
            throw ComposerException("时间线素材层参数无效")
        }

        val outputParent = File(output).parentFile ?: cacheDir
        outputParent.mkdirs()
        val baseFile = File.createTempFile("dramaflow_timeline_base_", ".mp4", outputParent)
        if (baseFile.exists()) baseFile.delete()
        try {
            composeInputs(primarySegments, baseFile.absolutePath)
            ensureFile(baseFile.absolutePath)

            val primarySequence = EditedMediaItemSequence.withAudioAndVideoFrom(
                listOf(
                    EditedMediaItem.Builder(
                        MediaItem.fromUri(Uri.fromFile(baseFile)),
                    ).build(),
                ),
            )
            val sequences = mutableListOf(primarySequence)
            val timelineOverlays = mutableListOf<TimelineOverlay>()

            for (segment in overlaySegments) {
                ensureFile(segment.videoPath)
                val sourceDurationUs = durationUs(segment.videoPath)
                val requestedDurationUs = segment.durationMs?.let(::timeUsFromMs) ?: sourceDurationUs
                val overlayDurationUs = min(requestedDurationUs, sourceDurationUs)
                if (overlayDurationUs <= 0L) {
                    throw ComposerException("时间线素材层时长无效：${segment.videoPath}")
                }
                val startUs = timeUsFromMs(segment.startMs ?: 0)
                val overlayBuilder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
                if (startUs > 0L) {
                    overlayBuilder.addGap(startUs)
                }
                overlayBuilder.addItem(
                    buildNleEditedMediaItem(
                        segment.copy(audioPath = null, transition = null),
                        overlayDurationUs,
                        clipStartUs = 0L,
                        clipEndUs = overlayDurationUs,
                    ),
                )
                sequences.add(overlayBuilder.build())
                timelineOverlays.add(
                    TimelineOverlay(
                        startUs = startUs,
                        durationUs = overlayDurationUs,
                        lane = segment.lane,
                    ),
                )
            }

            val outputFile = File(output)
            outputFile.parentFile?.mkdirs()
            if (outputFile.exists()) outputFile.delete()
            val composition = Composition.Builder(sequences)
                .setVideoCompositorSettings(TimelineVideoCompositorSettings(timelineOverlays))
                .build()
            exportNleComposition(composition, output, "Android 时间线素材层合成")
        } finally {
            if (baseFile.exists()) baseFile.delete()
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun composeWithNleEffects(segments: List<ComposeSegmentInput>, output: String) {
        segments.forEach { ensureFile(it.videoPath) }
        ensureRenderableAndroidNle(segments)

        val outputFile = File(output)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        if (segments.any { it.transition == "dissolve" }) {
            composeWithDissolveTransitions(segments, output)
            return
        }

        val editedItems = segments.map { segment ->
            buildNleEditedMediaItem(segment, durationUs(segment.videoPath))
        }
        val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(editedItems)
        val composition = Composition.Builder(sequence).build()
        exportNleComposition(composition, output, "Android NLE 合成")
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun composeWithNleEffectsAndExternalAudio(
        segments: List<ComposeSegmentInput>,
        output: String,
    ) {
        segments.forEach { ensureFile(it.videoPath) }
        segments.mapNotNull { it.audioPath }.forEach(::ensureFile)
        ensureRenderableAndroidNle(segments)

        if (segments.any { it.transition == "dissolve" }) {
            composeWithDissolveTransitionsAndExternalAudio(segments, output)
            return
        }

        val nleTempFiles = mutableListOf<File>()
        try {
            val renderedSegments = segments.map { segment ->
                val tempFile = renderNleSegmentToTemp(segment, output)
                nleTempFiles.add(tempFile)
                segment.copy(
                    videoPath = tempFile.absolutePath,
                    transition = null,
                    filterPreset = null,
                )
            }
            composeWithExternalAudio(renderedSegments, output)
        } finally {
            deleteNleTempFiles(nleTempFiles)
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun renderNleSegmentToTemp(segment: ComposeSegmentInput, output: String): File {
        val outputParent = File(output).parentFile ?: cacheDir
        outputParent.mkdirs()
        val tempFile = File.createTempFile("dramaflow_nle_", ".mp4", outputParent)
        if (tempFile.exists()) tempFile.delete()

        val editedItem = buildNleEditedMediaItem(segment, durationUs(segment.videoPath))
        val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(listOf(editedItem))
        val composition = Composition.Builder(sequence).build()
        exportNleComposition(
            composition,
            tempFile.absolutePath,
            "Android NLE 临时片段渲染",
        )
        return tempFile
    }

    private fun deleteNleTempFiles(nleTempFiles: List<File>) {
        nleTempFiles.forEach { file ->
            if (file.exists()) file.delete()
        }
    }

    private fun ensureRenderableAndroidNle(segments: List<ComposeSegmentInput>) {
        segments.firstOrNull {
            it.transition != null &&
                it.transition != "fade" &&
                it.transition != "whip_pan" &&
                it.transition != "dissolve"
        }?.let {
            throw ComposerException("Android 当前仅支持淡入淡出与滤镜渲染，暂不支持 ${it.transition}")
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun composeWithDissolveTransitions(
        segments: List<ComposeSegmentInput>,
        output: String,
    ) {
        val plan = buildDissolveCompositionPlan(segments)
        val sequences = mutableListOf(plan.primarySequence)
        sequences.addAll(plan.overlaySequences)
        val composition = Composition.Builder(sequences)
            .setVideoCompositorSettings(DissolveVideoCompositorSettings(plan.overlays))
            .build()
        exportNleComposition(composition, output, "Android dissolve 合成")
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun composeWithDissolveTransitionsAndExternalAudio(
        segments: List<ComposeSegmentInput>,
        output: String,
    ) {
        val tempFile = renderDissolveCompositionToTemp(segments, output)
        try {
            muxRenderedVideoWithTimelineAudio(tempFile.absolutePath, segments, output)
        } finally {
            if (tempFile.exists()) tempFile.delete()
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun renderDissolveCompositionToTemp(
        segments: List<ComposeSegmentInput>,
        output: String,
    ): File {
        val outputParent = File(output).parentFile ?: cacheDir
        outputParent.mkdirs()
        val tempFile = File.createTempFile("dramaflow_dissolve_", ".mp4", outputParent)
        if (tempFile.exists()) tempFile.delete()

        val plan = buildDissolveCompositionPlan(segments, includePrimaryAudio = false)
        val sequences = mutableListOf(plan.primarySequence)
        sequences.addAll(plan.overlaySequences)
        val composition = Composition.Builder(sequences)
            .setVideoCompositorSettings(DissolveVideoCompositorSettings(plan.overlays))
            .build()
        exportNleComposition(composition, tempFile.absolutePath, "Android dissolve 临时片段渲染")
        return tempFile
    }

    private fun muxRenderedVideoWithTimelineAudio(
        renderedVideoPath: String,
        segments: List<ComposeSegmentInput>,
        output: String,
    ) {
        val renderedTracks = inspectTracks(renderedVideoPath)
        val audioSegments = buildTimelineAudioSegments(segments)
        val outputAudioFormat = audioSegments.firstOrNull()?.audioFormat

        val outputFile = File(output)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            val videoOutTrack = muxer.addTrack(renderedTracks.videoFormat)
            val audioOutTrack = outputAudioFormat?.let { muxer.addTrack(it) }
            renderedTracks.rotationDegrees?.let { muxer.setOrientationHint(it) }
            muxer.start()
            started = true

            copyTrack(renderedVideoPath, renderedTracks.videoIndex, muxer, videoOutTrack, 0L)
            if (audioOutTrack != null) {
                for (segment in audioSegments) {
                    ensureCompatible(outputAudioFormat, segment.audioFormat, segment.path)
                    copyTrack(
                        segment.path,
                        segment.trackIndex,
                        muxer,
                        audioOutTrack,
                        segment.outputOffsetUs,
                        maxInputDurationUs = segment.durationUs,
                        inputStartUs = segment.sourceStartUs,
                    )
                }
            }
        } finally {
            if (started) muxer.stop()
            muxer.release()
        }
    }

    private fun buildTimelineAudioSegments(
        segments: List<ComposeSegmentInput>,
    ): List<TimelineAudioSegment> {
        val durations = segments.map { durationUs(it.videoPath) }
        val timelineAudioSegments = mutableListOf<TimelineAudioSegment>()
        var outputCursorUs = 0L

        for ((index, segment) in segments.withIndex()) {
            val videoDurationUs = durations[index]
            val incomingDissolveUs = dissolveDurationUs(
                segment = segment,
                durationUs = videoDurationUs,
                previousDurationUs = durations.getOrNull(index - 1),
            )
            val segmentAudioDurationUs = videoDurationUs - incomingDissolveUs
            if (segmentAudioDurationUs > 0L) {
                if (segment.audioPath != null) {
                    val audio = inspectAudioTrack(segment.audioPath)
                    timelineAudioSegments.add(
                        TimelineAudioSegment(
                            path = segment.audioPath,
                            trackIndex = audio.audioIndex,
                            audioFormat = audio.audioFormat,
                            outputOffsetUs = outputCursorUs,
                            sourceStartUs = 0L,
                            durationUs = segmentAudioDurationUs,
                        ),
                    )
                } else {
                    val tracks = inspectTracks(segment.videoPath)
                    if (tracks.audioIndex != null && tracks.audioFormat != null) {
                        timelineAudioSegments.add(
                            TimelineAudioSegment(
                                path = segment.videoPath,
                                trackIndex = tracks.audioIndex,
                                audioFormat = tracks.audioFormat,
                                outputOffsetUs = outputCursorUs,
                                sourceStartUs = incomingDissolveUs,
                                durationUs = segmentAudioDurationUs,
                            ),
                        )
                    }
                }
            }
            outputCursorUs += segmentAudioDurationUs
        }

        return timelineAudioSegments
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun buildDissolveCompositionPlan(
        segments: List<ComposeSegmentInput>,
        includePrimaryAudio: Boolean = true,
    ): DissolveCompositionPlan {
        val durations = segments.map { durationUs(it.videoPath) }
        val primaryItems = mutableListOf<EditedMediaItem>()
        val overlaySequences = mutableListOf<EditedMediaItemSequence>()
        val overlays = mutableListOf<DissolveOverlay>()
        var outputCursorUs = 0L

        for ((index, segment) in segments.withIndex()) {
            val durationUs = durations[index]
            val incomingDissolveUs = dissolveDurationUs(
                segment = segment,
                durationUs = durationUs,
                previousDurationUs = durations.getOrNull(index - 1),
            )
            if (incomingDissolveUs > 0L) {
                val overlayStartUs = max(0L, outputCursorUs - incomingDissolveUs)
                val overlayBuilder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
                if (overlayStartUs > 0L) {
                    overlayBuilder.addGap(overlayStartUs)
                }
                overlayBuilder.addItem(
                    buildNleEditedMediaItem(
                        segment.copy(transition = null),
                        incomingDissolveUs,
                        clipStartUs = 0L,
                        clipEndUs = incomingDissolveUs,
                    ),
                )
                overlaySequences.add(overlayBuilder.build())
                overlays.add(DissolveOverlay(startUs = overlayStartUs, durationUs = incomingDissolveUs))
            }

            val primaryStartUs = incomingDissolveUs
            if (primaryStartUs < durationUs) {
                primaryItems.add(
                    buildNleEditedMediaItem(
                        segment.copy(transition = if (segment.transition == "dissolve") null else segment.transition),
                        durationUs - primaryStartUs,
                        clipStartUs = primaryStartUs,
                        clipEndUs = durationUs,
                    ),
                )
                outputCursorUs += durationUs - primaryStartUs
            }
        }

        return DissolveCompositionPlan(
            primarySequence = if (includePrimaryAudio) {
                EditedMediaItemSequence.withAudioAndVideoFrom(primaryItems)
            } else {
                EditedMediaItemSequence.withVideoFrom(primaryItems)
            },
            overlaySequences = overlaySequences,
            overlays = overlays,
        )
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun exportNleComposition(composition: Composition, output: String, label: String) {
        val error = AtomicReference<Exception?>()
        val done = CountDownLatch(1)
        val transformer = Transformer.Builder(this)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    done.countDown()
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    error.set(exportException)
                    done.countDown()
                }
            })
            .build()

        transformer.start(composition, output)
        if (!done.await(30, TimeUnit.MINUTES)) {
            transformer.cancel()
            throw ComposerException("$label 超时")
        }
        error.get()?.let {
            throw ComposerException("$label 失败：${it.message ?: it.javaClass.simpleName}")
        }
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun buildNleEditedMediaItem(
        segment: ComposeSegmentInput,
        durationUs: Long,
        clipStartUs: Long = 0L,
        clipEndUs: Long? = null,
    ): EditedMediaItem {
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(segment.videoPath)))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionUs(clipStartUs)
                    .setEndPositionUs(clipEndUs ?: durationUs)
                    .build(),
            )
            .build()
        val effects = nleVideoEffects(segment, durationUs)
        return EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(emptyList(), effects))
            .build()
    }

    private fun dissolveDurationUs(
        segment: ComposeSegmentInput,
        durationUs: Long,
        previousDurationUs: Long?,
    ): Long {
        if (segment.transition != "dissolve" || previousDurationUs == null) return 0L
        return min(500_000L, min(durationUs / 2L, previousDurationUs / 2L))
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    private fun nleVideoEffects(segment: ComposeSegmentInput, durationUs: Long): List<Effect> {
        val effects = mutableListOf<Effect>()
        segment.filterPreset?.let { preset ->
            effects.add(RgbMatrix { _, _ -> filterMatrix(preset) })
        }
        if (segment.transition == "fade") {
            effects.add(RgbMatrix { presentationTimeUs, _ ->
                fadeMatrix(presentationTimeUs, durationUs)
            })
        }
        if (segment.transition == "whip_pan") {
            effects.add(WhipPanTransformation(durationUs))
        }
        return effects
    }

    private fun fadeMatrix(presentationTimeUs: Long, durationUs: Long): FloatArray {
        val fadeUs = min(500_000L, durationUs / 2L)
        if (fadeUs <= 0L) return colorScaleMatrix(1f, 1f, 1f)
        val tailUs = durationUs - presentationTimeUs
        val opacity = when {
            presentationTimeUs < fadeUs -> presentationTimeUs.toFloat() / fadeUs.toFloat()
            tailUs < fadeUs -> max(0f, tailUs.toFloat() / fadeUs.toFloat())
            else -> 1f
        }
        return colorScaleMatrix(opacity, opacity, opacity)
    }

    private fun filterMatrix(preset: String): FloatArray =
        when (preset) {
            "cinematic" -> colorScaleMatrix(0.96f, 1.02f, 1.08f)
            "warm" -> colorScaleMatrix(1.10f, 1.03f, 0.92f)
            "cool" -> colorScaleMatrix(0.92f, 1.00f, 1.12f)
            "vintage" -> floatArrayOf(
                0.393f, 0.349f, 0.272f, 0f,
                0.769f, 0.686f, 0.534f, 0f,
                0.189f, 0.168f, 0.131f, 0f,
                0f, 0f, 0f, 1f,
            )
            else -> colorScaleMatrix(1f, 1f, 1f)
        }

    private fun colorScaleMatrix(red: Float, green: Float, blue: Float): FloatArray =
        floatArrayOf(
            red, 0f, 0f, 0f,
            0f, green, 0f, 0f,
            0f, 0f, blue, 0f,
            0f, 0f, 0f, 1f,
        )

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
        inputStartUs: Long = 0L,
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
                if (sampleTime < inputStartUs) {
                    extractor.advance()
                    continue
                }
                if (maxInputDurationUs != null && sampleTime >= inputStartUs + maxInputDurationUs) break
                if (sampleTime >= 0) {
                    info.set(0, size, sampleTime - inputStartUs + offsetUs, extractor.sampleFlags)
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

    private fun stringValue(value: Any?): String? = value as? String

    private fun intValue(value: Any?): Int? =
        when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            is Float -> value.toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
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
    val transition: String?,
    val filterPreset: String?,
    val timelineKind: String = "storyboard",
    val lane: Int = 0,
    val startMs: Int? = null,
    val durationMs: Int? = null,
) {
    val hasNleMetadata: Boolean
        get() = transition != null || filterPreset != null

    val hasTimelineMetadata: Boolean
        get() = timelineKind != "storyboard" || lane != 0 || startMs != null || durationMs != null

    val isOverlayClip: Boolean
        get() = timelineKind == "clip" || lane > 0
}

private data class ComposeInspection(
    val segment: ComposeSegmentInput,
    val tracks: TrackInspection,
    val externalAudio: AudioInspection?,
    val durationUs: Long,
)

private data class TimelineAudioSegment(
    val path: String,
    val trackIndex: Int,
    val audioFormat: MediaFormat,
    val outputOffsetUs: Long,
    val sourceStartUs: Long,
    val durationUs: Long,
)

private data class DissolveOverlay(
    val startUs: Long,
    val durationUs: Long,
)

private data class TimelineOverlay(
    val startUs: Long,
    val durationUs: Long,
    val lane: Int,
)

private data class DissolveCompositionPlan(
    val primarySequence: EditedMediaItemSequence,
    val overlaySequences: List<EditedMediaItemSequence>,
    val overlays: List<DissolveOverlay>,
)

private class ComposerException(message: String) : Exception(message)

private class DissolveVideoCompositorSettings(
    private val overlays: List<DissolveOverlay>,
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: MutableList<Size>): Size =
        inputSizes.firstOrNull { it != Size.UNKNOWN && it != Size.ZERO } ?: Size.UNKNOWN

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        if (inputId == 0) return AlphaOverlaySettings(1f)
        val overlay = overlays.getOrNull(inputId - 1) ?: return AlphaOverlaySettings(0f)
        return AlphaOverlaySettings(
            dissolveAlpha(
                presentationTimeUs = presentationTimeUs,
                startUs = overlay.startUs,
                durationUs = overlay.durationUs,
            ),
        )
    }
}

private class TimelineVideoCompositorSettings(
    private val overlays: List<TimelineOverlay>,
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: MutableList<Size>): Size =
        inputSizes.firstOrNull { it != Size.UNKNOWN && it != Size.ZERO } ?: Size.UNKNOWN

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        if (inputId == 0) return AlphaOverlaySettings(1f)
        val overlay = overlays.getOrNull(inputId - 1) ?: return AlphaOverlaySettings(0f)
        val isVisible = presentationTimeUs >= overlay.startUs &&
            presentationTimeUs < overlay.startUs + overlay.durationUs
        return AlphaOverlaySettings(if (isVisible) 1f else 0f)
    }
}

private data class AlphaOverlaySettings(private val alphaScale: Float) : OverlaySettings {
    override fun getAlphaScale(): Float = alphaScale
}

private fun dissolveAlpha(presentationTimeUs: Long, startUs: Long, durationUs: Long): Float {
    if (durationUs <= 0L || presentationTimeUs <= startUs) return 0f
    if (presentationTimeUs >= startUs + durationUs) return 1f
    return ((presentationTimeUs - startUs).toFloat() / durationUs.toFloat()).coerceIn(0f, 1f)
}

private fun timeUsFromMs(milliseconds: Int): Long = max(0L, milliseconds.toLong()) * 1000L

private class WhipPanTransformation(private val durationUs: Long) : MatrixTransformation {
    override fun getMatrix(presentationTimeUs: Long): Matrix =
        whipPanMatrix(presentationTimeUs, durationUs)
}

private fun whipPanMatrix(presentationTimeUs: Long, durationUs: Long): Matrix {
    val sweepUs = min(420_000L, durationUs / 2L)
    val offset = when {
        sweepUs <= 0L -> 0f
        presentationTimeUs < sweepUs -> {
            -0.55f * (1f - presentationTimeUs.toFloat() / sweepUs.toFloat())
        }
        durationUs - presentationTimeUs < sweepUs -> {
            0.55f * (1f - max(0f, durationUs - presentationTimeUs.toFloat()) / sweepUs.toFloat())
        }
        else -> 0f
    }
    return Matrix().apply {
        postScale(1.14f, 1.14f)
        postTranslate(offset, 0f)
    }
}

private fun MediaFormat.intOrNull(key: String): Int? =
    if (containsKey(key)) getInteger(key) else null

private fun MediaFormat.rotationDegreesOrNull(): Int? =
    if (containsKey(MediaFormat.KEY_ROTATION)) getInteger(MediaFormat.KEY_ROTATION) else null
